//! RELAY_PULSE liveness permission: the pulses must be impossible to leave on.

use safety_core::liveness::{
    pulse_wanted, PulseBudget, MAX_TICK_GAP_US, PERMIT_EDGES, PERMIT_US, PRECHARGE_EDGES, PULSE_HALF_PERIOD_US,
};
use safety_core::safety::constants::RELAY_FEEDBACK_DEADLINE_US;
use safety_core::safety::controller::SafeMode;

const TICK: u32 = PULSE_HALF_PERIOD_US;

/// Tick from `start` for `count` timer periods; returns the levels.
fn run(budget: &PulseBudget, start: u32, count: u32) -> Vec<bool> {
    (0..count).map(|i| budget.tick(start.wrapping_add(i * TICK))).collect()
}

fn alternates(levels: &[bool]) -> bool {
    levels.windows(2).all(|pair| pair[0] != pair[1])
}

#[test]
fn never_renewed_never_pulses() {
    let budget = PulseBudget::new();
    assert!(run(&budget, 0, 1000).iter().all(|level| !level));
    assert!(!budget.precharged(1000 * TICK));
}

#[test]
fn a_live_permission_toggles_every_tick_starting_with_a_rising_edge() {
    let budget = PulseBudget::new();
    budget.renew(1_000);
    let levels = run(&budget, 1_000, PERMIT_US / TICK);
    assert!(levels[0]);
    assert!(alternates(&levels), "{levels:?}");
}

#[test]
fn pulses_stop_within_the_permit_when_the_loop_stops_renewing() {
    let budget = PulseBudget::new();
    budget.renew(0);
    // The loop hangs at t=0. Sample every tick for a second.
    let levels = run(&budget, 0, 2000);
    let last_high = levels.iter().rposition(|level| *level).unwrap() as u32;
    assert!(last_high * TICK < PERMIT_US, "pulsed until {} us", last_high * TICK);
}

#[test]
fn a_delayed_timer_cannot_spend_an_old_permission() {
    // The defect a callback COUNT has: renew, then the timer task is starved
    // for 30 ms. When it runs again the permission is stale and must be dead,
    // however few callbacks were delivered meanwhile.
    let budget = PulseBudget::new();
    budget.renew(0);
    assert!(budget.tick(0));
    let late = run(&budget, 30_000, 100);
    assert!(late.iter().all(|level| !level), "edges emitted after expiry: {late:?}");
}

#[test]
fn cancel_stops_at_the_next_tick_and_clears_precharge() {
    let budget = PulseBudget::new();
    budget.renew(0);
    run(&budget, 0, 10);
    budget.cancel();
    assert!(!budget.precharged(10 * TICK));
    assert!(run(&budget, 10 * TICK, 100).iter().all(|level| !level));
}

#[test]
fn a_regularly_renewed_permission_never_drops_an_edge() {
    let budget = PulseBudget::new();
    let mut levels = Vec::new();
    // Renew every 10 ticks (the 5 ms loop) for one simulated second.
    for pass in 0..200u32 {
        let now = pass * 10 * TICK;
        budget.renew(now);
        levels.extend(run(&budget, now, 10));
    }
    assert!(alternates(&levels));
}

#[test]
fn permit_outlasts_a_loop_pass_plus_the_feedback_window() {
    let loop_pass_us = 5_000;
    assert!(PERMIT_US as i64 >= loop_pass_us + RELAY_FEEDBACK_DEADLINE_US.get());
}

#[test]
fn pulse_rate_is_one_kilohertz() {
    assert_eq!(1_000_000 / (2 * PULSE_HALF_PERIOD_US), 1000);
}

#[test]
fn precharge_needs_thirty_unbroken_milliseconds_of_edges() {
    assert_eq!(PRECHARGE_EDGES * TICK, 30_000);
    // Model: coil pickup 4.6-9.6 ms after pulses start at 1 kHz.
    assert!(PRECHARGE_EDGES * TICK >= 2 * 9_600);

    let budget = PulseBudget::new();
    let mut now = 0u32;
    for edge in 0..PRECHARGE_EDGES {
        assert!(!budget.precharged(now), "precharged after only {edge} edges");
        if edge % 10 == 0 {
            budget.renew(now);
        }
        budget.tick(now);
        now += TICK;
    }
    assert!(budget.precharged(now));
}

#[test]
fn a_pulse_outage_resets_precharge() {
    // The loop is blocked long enough for the permission to lapse; the pump
    // discharges. A later renewal must not inherit the earlier precharge.
    let budget = PulseBudget::new();
    let mut now = 0u32;
    for edge in 0..PRECHARGE_EDGES {
        if edge % 10 == 0 {
            budget.renew(now);
        }
        budget.tick(now);
        now += TICK;
    }
    assert!(budget.precharged(now));
    // 300 ms with no renewal: ticks keep arriving, permission is dead.
    for _ in 0..600 {
        budget.tick(now);
        now += TICK;
    }
    assert!(!budget.precharged(now));
    budget.renew(now);
    budget.tick(now);
    assert!(!budget.precharged(now), "one edge after an outage is not a charged gate");
}

/// Renew every 10 ticks and tick `edges` times from `now`; returns the time after.
fn pulse_for(budget: &PulseBudget, mut now: u32, edges: u32) -> u32 {
    for edge in 0..edges {
        if edge % 10 == 0 {
            budget.renew(now);
        }
        budget.tick(now);
        now = now.wrapping_add(TICK);
    }
    now
}

#[test]
fn a_timer_outage_resets_precharge_even_while_the_loop_keeps_renewing() {
    // The serial engine is healthy and renews on time, but the timer task is
    // held off for 300 ms: no edges, so the pump discharges. The first edge
    // after the outage must not be read as a charged gate.
    let budget = PulseBudget::new();
    let now = pulse_for(&budget, 0, PRECHARGE_EDGES);
    assert!(budget.precharged(now));
    // During the outage itself, before the timer has run again to notice:
    // the loop keeps renewing every 5 ms and asks. The answer must be no.
    let mut during = now.wrapping_add(MAX_TICK_GAP_US);
    for _ in 0..55 {
        during = during.wrapping_add(5_000);
        budget.renew(during);
        assert!(!budget.precharged(during), "precharged with no edge for {} us", during - now);
    }
    let resume = now.wrapping_add(300_000);
    budget.renew(resume);
    budget.tick(resume);
    assert!(!budget.precharged(resume), "precharge survived a 300 ms timer outage");
    // And it takes a full run of edges to earn it back.
    let after = pulse_for(&budget, resume.wrapping_add(TICK), PRECHARGE_EDGES - 3);
    assert!(!budget.precharged(after));
    let done = pulse_for(&budget, after, 10);
    assert!(budget.precharged(done));
}

#[test]
fn ordinary_timer_jitter_does_not_reset_precharge() {
    // Callbacks arriving 2 ms late now and then (flash, BLE, an emulator) are
    // not an outage: the gate barely sags. This is the case a too-strict gap
    // limit turned into entries that never qualified.
    let budget = PulseBudget::new();
    let mut now = 0u32;
    for edge in 0..PRECHARGE_EDGES {
        budget.renew(now);
        budget.tick(now);
        now += if edge % 5 == 0 { 2_500 } else { TICK };
    }
    assert!(budget.precharged(now));
    assert!(MAX_TICK_GAP_US >= 5 * TICK);
    // Physical bound: the gap must stay a small fraction of the 100 ms gate
    // time constant (R34 x C23).
    assert!(MAX_TICK_GAP_US <= 100_000 / 10);
}

#[test]
fn a_tick_gap_at_the_limit_still_counts_as_unbroken() {
    let budget = PulseBudget::new();
    let mut now = 0u32;
    for _ in 0..PRECHARGE_EDGES {
        budget.renew(now);
        budget.tick(now);
        now += MAX_TICK_GAP_US;
    }
    assert!(budget.precharged(now));
}

#[test]
fn an_expired_permission_never_comes_back_when_the_clock_wraps() {
    // The serial loop renewed once and hung. Sample the dead permission at the
    // points where 32-bit wrapping arithmetic could make it look alive again.
    for later in [1u32 << 31, (1u32 << 31) + 20_001, u32::MAX - 5_000, u32::MAX, 0, 10_000] {
        let budget = PulseBudget::new();
        budget.renew(0);
        assert!(!budget.tick(PERMIT_US + TICK), "should have expired");
        let levels = run(&budget, later, 100);
        assert!(levels.iter().all(|level| !level), "revived at t={later}: {levels:?}");
    }
}

#[test]
fn a_full_clock_wrap_buys_no_more_than_one_permit_of_edges() {
    // Renew, emit one edge, then BOTH the loop and the timer stop for exactly
    // one 32-bit wrap (71.6 minutes). A 32-bit clock cannot see that outage:
    // the stale expiry looks 19.5 ms in the future again. The edge bound is
    // what holds: one renewal never pays for more than PERMIT_EDGES edges, so
    // the pulses still die, for good, inside one permit.
    let budget = PulseBudget::new();
    budget.renew(0);
    assert!(budget.tick(0));
    // Absolute time 2^32 + 500 us is 500 in 32 bits.
    let levels = run(&budget, 500, 10_000);
    let emitted = levels.windows(2).filter(|pair| pair[0] != pair[1]).count() as u32;
    assert!(emitted <= PERMIT_EDGES, "{emitted} edges after a full wrap");
    assert!(levels[PERMIT_EDGES as usize..].iter().all(|level| !level));
}

#[test]
fn one_renewal_never_pays_for_more_than_a_permit_of_edges_however_fast_ticks_arrive() {
    let budget = PulseBudget::new();
    budget.renew(0);
    // A burst of catch-up callbacks all stamped inside the permit window.
    let levels: Vec<bool> = (0..1000).map(|i| budget.tick(i % 10)).collect();
    let high = levels.iter().filter(|level| **level).count() as u32;
    assert!(high <= PERMIT_EDGES / 2 + 1, "{high} high levels from one renewal");
}

#[test]
fn cancel_makes_precharged_false_at_once_even_against_a_concurrent_tick() {
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;
    for _ in 0..200 {
        let budget = Arc::new(PulseBudget::new());
        let start = pulse_for(&budget, 0, PRECHARGE_EDGES);
        assert!(budget.precharged(start));
        let stop = Arc::new(AtomicBool::new(false));
        let ticker = {
            let (budget, stop) = (budget.clone(), stop.clone());
            std::thread::spawn(move || {
                let mut now = PRECHARGE_EDGES * TICK;
                while !stop.load(Ordering::Relaxed) {
                    budget.tick(now);
                    now = now.wrapping_add(TICK);
                }
            })
        };
        budget.cancel();
        let seen_precharged = (0..1000).any(|_| budget.precharged(start));
        stop.store(true, Ordering::Relaxed);
        ticker.join().unwrap();
        assert!(!seen_precharged, "precharged() was true after cancel() returned");
    }
}

#[test]
fn the_clock_wrap_is_harmless() {
    let budget = PulseBudget::new();
    let start = u32::MAX - 3 * TICK;
    budget.tick(start.wrapping_sub(TICK)); // the timer has been running all along
    budget.renew(start);
    let levels = run(&budget, start, 20);
    assert!(alternates(&levels), "{levels:?}");
    // And it still expires on the far side of the wrap.
    assert!(!budget.tick(start.wrapping_add(PERMIT_US + TICK)));
}

#[test]
fn pulses_are_wanted_only_while_the_relay_is_or_will_be_closed() {
    assert!(!pulse_wanted(SafeMode::Proxy));
    assert!(pulse_wanted(SafeMode::EntryWaitGap));
    assert!(pulse_wanted(SafeMode::EntryWaitFeedback));
    assert!(pulse_wanted(SafeMode::Emulating));
    assert!(pulse_wanted(SafeMode::ExitWaitGap));
    assert!(!pulse_wanted(SafeMode::ExitWaitFeedback));
}
