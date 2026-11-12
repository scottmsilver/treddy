//! RELAY_PULSE liveness budget for the Rev E relay liveness switch.
//!
//! Hardware (design.py, nets RELAY_PULSE/PUMP_IN/PUMP_AC/Q3_G/RELAY_RTN): Q3
//! sits in series with the K1 coil driver and conducts only while IO8 keeps
//! toggling, because its gate is fed through a capacitor. A level cannot hold
//! it on. So K1 needs three things at once: TREAD_OK, RELAY_CMD high, and
//! pulses.
//!
//! The pulses must stop when the supervised safety loop stops. A hardware PWM
//! would keep running through a hang, which defeats the switch. So the toggler
//! holds a PERMISSION THAT EXPIRES: the safety loop renews it every pass, a
//! 500 us timer emits an edge only while it is unexpired, and when nothing
//! renews it the pin goes low and stays low. The expiry is a clock time, not
//! a count of callbacks: a delayed timer task must not be able to bank edges
//! and spend them later. A hung loop therefore stops the pulses within
//! `PERMIT_US` (20 ms) of its last pass; the hardware then opens Q3 roughly
//! 50-150 ms later (calculated from R34 x C23, not measured).
//!
//! This module is the whole decision. The HAL only creates the timer and
//! writes the level this returns.

use crate::safety::controller::SafeMode;
use core::sync::atomic::{AtomicBool, AtomicU32, Ordering};

/// Half period of the pulse train: 500 us per edge is a 1 kHz square wave.
///
/// 1 kHz is a hardware requirement, not a preference: the calculated Q3 gate
/// level is about 2.55 V at 1 kHz against 2.33 V at 500 Hz, and the AO3400A's
/// on-resistance is specified at 2.5 V.
pub const PULSE_HALF_PERIOD_US: u32 = 500;

/// How long one renewal lasts.
///
/// It must outlast one 5 ms loop pass plus the 10 ms relay feedback window
/// that can run inside a pass, with margin; and it should be short, because
/// it is how long a hung loop keeps pulsing.
pub const PERMIT_US: u32 = 20_000;

/// Edges one renewal can pay for: a permit's worth plus a little slack for
/// timer jitter. This is the SECOND bound on a permission, beside its clock
/// expiry. The clock is 32-bit (no 64-bit atomics on this target) and cannot
/// tell an outage of exactly one wrap (71.6 minutes) from no outage at all;
/// the edge count cannot be fooled that way, so even then a dead loop gets at
/// most this many edges and no more.
pub const PERMIT_EDGES: u32 = PERMIT_US / PULSE_HALF_PERIOD_US + 4;

/// Unbroken edges required before the relay may be commanded: 60 x 500 us is
/// 30 ms of pulses.
///
/// The gate capacitor charges over several milliseconds (model: coil pickup
/// 4.6-9.6 ms after pulses start at 1 kHz), and the controller allows the
/// relay only 10 ms to report closed. Commanding K1 into a cold Q3 would fail
/// every transfer at that deadline. This counts edges the timer actually
/// emitted since the last interruption, so an outage of any kind (permission
/// lapsed, cancelled, timer starved) starts the count again. Fails safe if
/// too small: the transfer is abandoned and the board stays in Proxy.
pub const PRECHARGE_EDGES: u32 = 60;

/// Whether the liveness switch should be held on in this controller mode.
///
/// On for every mode in which K1 is, or is about to be, energized. Off in
/// Proxy, so a stuck RELAY_GATE cannot energize K1 while the console owns the
/// belt, and off once the exit has commanded the relay open.
pub const fn pulse_wanted(mode: SafeMode) -> bool {
    match mode {
        SafeMode::EntryWaitGap
        | SafeMode::EntryWaitFeedback
        | SafeMode::Emulating
        | SafeMode::ExitWaitGap => true,
        SafeMode::Proxy | SafeMode::ExitWaitFeedback => false,
    }
}

/// The longest gap between two timer ticks that still counts as unbroken
/// pulsing. A longer gap means the timer task was held off long enough for
/// the gate to sag, and the precharge count starts again.
///
/// 10 ms, from the hardware: the gate discharges through R34 x C23 = 100 ms,
/// so a 10 ms pause costs under 10% of the gate voltage. It must NOT be set
/// near the tick period: esp_timer callbacks are routinely a millisecond or
/// two late (flash writes, BLE, and badly so under QEMU), and treating that
/// jitter as an outage keeps resetting the count until entries time out with
/// `entry_no_gap`. A first version used three half periods and did exactly
/// that.
pub const MAX_TICK_GAP_US: u32 = 10_000;

/// Shared between the safety loop (renews) and the timer callback (emits).
///
/// Times are the low 32 bits of the microsecond clock and compared with
/// wrapping arithmetic. (32-bit, because the target has no native 64-bit
/// atomics.) A wrapped compare is only meaningful over short spans, so an
/// expired permission is DISARMED the first time a tick sees it expired, and
/// a remaining time longer than a whole permit is treated as expired too:
/// nothing can come back to life when the 32-bit clock wraps.
///
/// Concurrency: `renew` is called only by the serial engine; `cancel` may be
/// called by any task that applies outputs; `tick` runs in the timer task.
/// Every race is resolved toward NOT pulsing and NOT precharged.
pub struct PulseBudget {
    armed: AtomicBool,
    expiry_us: AtomicU32,
    level: AtomicBool,
    last_tick_us: AtomicU32,
    edges_left: AtomicU32,
    unbroken_edges: AtomicU32,
}

impl PulseBudget {
    pub const fn new() -> Self {
        PulseBudget {
            armed: AtomicBool::new(false),
            expiry_us: AtomicU32::new(0),
            level: AtomicBool::new(false),
            last_tick_us: AtomicU32::new(0),
            edges_left: AtomicU32::new(0),
            unbroken_edges: AtomicU32::new(0),
        }
    }

    /// Renew the permission until `now_us + PERMIT_US`. Only the supervised
    /// safety loop may call this.
    pub fn renew(&self, now_us: u32) {
        self.expiry_us.store(now_us.wrapping_add(PERMIT_US), Ordering::Release);
        self.edges_left.store(PERMIT_EDGES, Ordering::Release);
        self.armed.store(true, Ordering::Release);
    }

    /// Withdraw the permission now. Safe to call from anywhere outputs are
    /// applied; the next timer tick drives the pin low. `precharged` is false
    /// from the moment this returns, whatever a concurrent tick does.
    pub fn cancel(&self) {
        self.armed.store(false, Ordering::Release);
        self.unbroken_edges.store(0, Ordering::Release);
    }

    /// Called by the timer every `PULSE_HALF_PERIOD_US`. Returns the level to
    /// drive on RELAY_PULSE. Without a live permission the answer is low.
    pub fn tick(&self, now_us: u32) -> bool {
        let since_last_tick = now_us.wrapping_sub(self.last_tick_us.swap(now_us, Ordering::AcqRel));
        // A timer that has not run for longer than a whole permit cannot
        // trust the 32-bit expiry compare (it aliases after a full wrap), so
        // such a gap kills the permission outright; a healthy loop renews it
        // within 5 ms.
        let armed = self.armed.load(Ordering::Acquire) && since_last_tick <= PERMIT_US;
        let remaining = self.expiry_us.load(Ordering::Acquire).wrapping_sub(now_us);
        let in_time = armed && remaining != 0 && remaining <= PERMIT_US;
        let live = in_time
            && self
                .edges_left
                .fetch_update(Ordering::AcqRel, Ordering::Acquire, |left| left.checked_sub(1))
                .is_ok();
        if !live {
            // Expired. Stay dead until the loop renews. (A renewal landing
            // between the loads above and this store is lost; the loop renews
            // again within 5 ms, and losing it only stops pulses.)
            self.armed.store(false, Ordering::Release);
        }

        let level = live && !self.level.load(Ordering::Acquire);
        self.level.store(level, Ordering::Release);

        if !live {
            self.unbroken_edges.store(0, Ordering::Release);
        } else if since_last_tick > MAX_TICK_GAP_US {
            // The timer was held off: this is the first edge of a new run.
            self.unbroken_edges.store(1, Ordering::Release);
        } else {
            // Compare-and-swap so a concurrent `cancel` (which zeroes the
            // count) is not overwritten by a stale increment.
            let edges = self.unbroken_edges.load(Ordering::Acquire);
            let _ = self.unbroken_edges.compare_exchange(
                edges,
                edges.saturating_add(1),
                Ordering::AcqRel,
                Ordering::Acquire,
            );
        }
        level
    }

    /// True once the timer has emitted `PRECHARGE_EDGES` edges in a row with
    /// no interruption, the permission is still armed, AND the latest edge is
    /// recent: i.e. the Q3 gate has had time to charge and is still being fed
    /// right now. The recency check is what catches a timer that has stopped
    /// running, before it has run again to notice the gap itself.
    pub fn precharged(&self, now_us: u32) -> bool {
        self.armed.load(Ordering::Acquire)
            && self.unbroken_edges.load(Ordering::Acquire) >= PRECHARGE_EDGES
            && now_us.wrapping_sub(self.last_tick_us.load(Ordering::Acquire)) <= MAX_TICK_GAP_US
    }
}

impl Default for PulseBudget {
    fn default() -> Self {
        Self::new()
    }
}
