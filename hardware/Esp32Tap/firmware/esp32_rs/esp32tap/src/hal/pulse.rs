//! RELAY_PULSE (IO8) toggler for the Rev E relay liveness switch.
//!
//! All of the policy is in `safety_core::liveness`: what the level is, when
//! the pulses stop, how long they may outlive the last refill. This file only
//! owns the timer and the pin.
//!
//! WHY AN esp_timer AND NOT LEDC/RMT/MCPWM: those peripherals keep generating
//! edges after the firmware that started them has hung, and the whole point of
//! the hardware switch is that a hung safety loop CANNOT keep K1 closed. Here
//! an edge is emitted only under a permission that expires 20 ms after the
//! WDT-supervised serial engine last renewed it (`renew`), so the pulses stop
//! within 20 ms of that loop stopping, whatever else is still running.
//!
//! The timer runs all the time. Without a live permission it writes the pin
//! low on every tick, which is the idle state, so there is no start/stop path
//! to get wrong.
//!
//! WHAT THIS DEPENDS ON, beyond the task matrix in `tasks/mod.rs`: the
//! callback runs in the IDF esp_timer task (priority 22, above every
//! application task), which this firmware does not spawn or supervise. If
//! that task is starved or delayed, edges are late or missing; a stale
//! permission is still dead when it runs again, and the precharge count
//! restarts. So its failure direction is pulses stopping, never pulses
//! continuing.
//!
//! NOT PROVEN: nothing here has run on hardware (there is no board), and the
//! QEMU image cannot observe a charge pump. What the host tests prove is the
//! budget arithmetic; the edge timing on a real pin needs a scope.

use crate::hal::{gpio, Esp32Clock};
use safety_core::liveness::{PulseBudget, PULSE_HALF_PERIOD_US};

static BUDGET: PulseBudget = PulseBudget::new();

/// Low 32 bits of the microsecond clock; `PulseBudget` compares with wrapping
/// arithmetic.
fn now_us() -> u32 {
    Esp32Clock::new().now().get() as u32
}

// SAFETY: an `unsafe extern "C" fn` only because that is the callback type
// esp_timer takes. It ignores its argument (registered as null), runs in the
// esp_timer task, and calls two safe functions: an atomic update and a GPIO
// level write for a fixed, valid pin.
unsafe extern "C" fn on_tick(_arg: *mut core::ffi::c_void) {
    gpio::drive_relay_pulse(BUDGET.tick(now_us()));
}

/// Configure the pin low and start the 500 us tick. False if either fails;
/// the caller halts in Proxy, where the relay is released in hardware.
pub fn init() -> bool {
    if !gpio::configure_relay_pulse() {
        return false;
    }
    // Zero-init then assign, for the same reason as `gpio_config_t`: IDF adds
    // fields to this struct across versions.
    let mut args: esp_idf_sys::esp_timer_create_args_t = Default::default();
    args.callback = Some(on_tick);
    args.name = c"relay_pulse".as_ptr();
    // A late callback must not be replayed as a burst of catch-up edges.
    args.skip_unhandled_events = true;
    let mut handle: esp_idf_sys::esp_timer_handle_t = core::ptr::null_mut();
    // SAFETY: `esp_timer_create` copies `args` and writes one handle through
    // the pointer; both are live locals for the whole call. `on_tick` is a
    // 'static fn that touches only a 'static atomic and a GPIO register.
    // esp_timer is initialised before app_main. `esp_timer_start_periodic`
    // takes the handle that `esp_timer_create` just returned successfully.
    unsafe {
        esp_idf_sys::esp_timer_create(&args, &mut handle) == esp_idf_sys::ESP_OK
            && esp_idf_sys::esp_timer_start_periodic(handle, PULSE_HALF_PERIOD_US as u64) == esp_idf_sys::ESP_OK
    }
}

/// Renew the pulse permission for another 20 ms. Called by the supervised
/// serial engine on every pass, and by nothing else: this call IS the
/// liveness signal.
pub fn renew() {
    BUDGET.renew(now_us());
}

/// Withdraw the permission now. Called wherever outputs are applied in a mode
/// that does not want pulses, from any task.
pub fn cancel() {
    BUDGET.cancel();
}

/// True once 30 ms of uninterrupted edges have actually been emitted, i.e.
/// the Q3 gate has had time to charge and K1 may be commanded.
pub fn precharged() -> bool {
    BUDGET.precharged(now_us())
}
