# Esp32Tap Rev E release ledger

**Status: HOLD.** This file intentionally answers whether the exact package may
advance. It does not authorize an order or payment.

## Repository-closeable gates

| Gate | State | Evidence |
|---|---|---|
| Electrical source and pin maps | PASS | `tools/design.py`, design tests |
| Typed schematic and ERC | PASS | generated schematic, normalized `erc.rpt` |
| Four-layer PCB and parity DRC | PASS | inspector/validator; `drc.rpt` reports 0 violations from a fresh KiCad 10.0.5 run with all severities and schematic parity |
| USB route and antenna-band keepout | PASS | PCB semantic tests; inner/bottom layers forbid tracks, vias and fills, the front layer forbids fills and vias and allows the U1 pad fan-out stubs |
| BOM/CPL/DNP/placement parity | PASS | exporter assembly audit |
| Exact deterministic fabrication package | PASS | 13-member export and reproduction gate |
| Dual-engine behavioral simulations | PASS within declared models | nine decks, three repeats, two ngspice majors; one deck (`harness_supply_drop`) is a retired historical model |
| Enclosure source/mesh/fit checks | PASS geometrically | pinned render and functional probes |
| Host firmware safety contract | PASS as reference only | safety model and manifest-builder tests; does not implement `RELAY_PULSE` |
| Recent exact-page part identity/stock | PASS at snapshot time | BOM-bound sanitized snapshot, refreshed 2026-11-12: all 46 distinct parts listed in stock; C585890 (the RJ45 jack, 2 per board) is the thinnest at 64 units |

These rows mean the repository artifacts are mutually consistent. They do not
mean a physical board has passed.

## Open vendor gates

| Gate | State | Required evidence |
|---|---|---|
| Exact-archive online PCB DFM | OPEN | The retained operator record is bound to a superseded archive. Upload the current exact ZIP and record SHA-bound raw counts |
| Production CAM acceptance | OPEN | JLC production-file review with no unapproved edits |
| Production stack and USB impedance | OPEN | JLC confirmation against `JLC04161H-7628` |
| Epoxy filled and capped vias | OPEN | 41 via drills still touch pasted SMD pads and were not rerouted. The order must select JLC's paid "Epoxy Filled & Capped" via covering (JLC states it is free only on 6+ layers; eligible holes up to 0.5 mm). Price comes only from the quote tool |
| Standard PCBA rails / panel to 70 mm | OPEN | The board is 58 mm on one axis; JLC Standard PCBA needs at least 70 x 70 mm with rails and fiducials. Needs JLC-added rails wide enough to reach 70 mm, or a 2-up panel, with routed tabs kept away from C2, C7, F1, D1, D3 and R5 near the bottom edge. Those parts were not moved |
| SMT-only reflow confirmation | OPEN | J1, J2 and J3 placed by standard top-side reflow, confirmed by JLC; no wave, manual solder or pigtail line item |
| BOM/CPL placement | OPEN | Exact-part resolution and visual placement review |
| Placement rotation preview | OPEN | CPL rotations are raw KiCad angles with no JLC correction table. Check every polarized or multi-pin part in JLC's placement preview before paying (see `ORDERING.md`) |
| Substitutions | OPEN | None, or a new engineering review |
| Enclosure material/mesh DFM | OPEN | JLC3DP acceptance without scaling or geometry changes; owner supplies the screws listed in `enclosure/DIMENSIONS.md` |
| Current quote | OPEN | Fresh quote tied to artifact hashes |

The operator-recorded online DFM result in `vendor/JLC-DFM-REVIEW.json` is not
a vendor-signed result, is not independent proof of upload provenance, and is
bound to a superseded archive, not the current one. No design was added to a
cart, no order was submitted, no production files were authorized, and no
payment was made.

## Open firmware gates

- Production ESP-IDF application implementing `firmware/PLAN.md`.
- `RELAY_PULSE` (IO8) liveness toggle, bd issue `precor-9_3x-4uv`: implemented
  in `firmware/esp32_rs` (500 us `esp_timer` toggle, permission renewed by the
  WDT-supervised serial engine, expiry 20 ms, not LEDC/RMT/PWM), unproven on
  hardware. The issue stays open until bench proof: edge timing on the real pin
  under load, the charge pump and K1 release, and the `esp_timer` task as a
  dependency outside the supervised-task matrix.
- Active-low VBUS attach strategy reviewed against ROM/reset behavior.
- Exact sdkconfig, application, bootloader, partition table
  (`firmware/esp32_rs/partitions_esp32tap.csv`, not yet verified against a real
  build), and `bundle_sha256`.
- 2 s task watchdog with immediate silent reset and no debug/halt path.
- Brownout threshold selected below the measured production minimum +3V3.
- WSS/BLE/executor ownership, deadlines, radio coexistence, and security
  implemented on the target.

The host model is a contract, not a firmware deliverable.

## Open physical gates

- Treadmill serial line voltage level and the +8 V rail under load (both
  unmeasured; bd `precor-9_3x-3pb`). D5-D7 are 5 V standoff parts chosen
  because the line level is unknown.
- Treadmill rail envelope, input current, surge/noise, startup, brownout, and
  thermal characterization.
- Converter switching waveform, ripple, loop response, and EMI.
- Unpowered serial loading and live edge/timing measurements.
- Relay operate/release/bounce/weld behavior and stable-NC timing under every
  fault, including Q3 liveness pickup and release after `RELAY_PULSE` stops
  (calculated roughly 50-150 ms, not a guaranteed deadline), the gate level at
  1 kHz (calculated about 2.55 V), and stray-edge immunity (calculated about
  0.27 V). The liveness switch is not single-fault tolerant alone (C22 short,
  R34 open, C23 open, Q3 drain-source short; each needs a second fault).
- Scope Q1 base, emitter and collector when the pulses stop with `RELAY_GATE`
  high (BC817 reverse VBE limit is 5 V).
- RJ45 pad 1 orientation: verified by eye against Molex SD-44144-001 rev H9
  sheet 2 (circuit 1 is the leftmost contact land in the component-side layout,
  matching footprint pad 1 at x = -4.45); bd `precor-9_3x-192` closed. A built
  board still has to confirm supply polarity and the pin-3/pin-6 taps.
- SW1/SW2 pad numbering (corrected to rows; an earlier column numbering would
  have held the module in reset) confirmed on a built board.
- R33 undervoltage hysteresis (calculated about 6.31 V falling, 6.85 V rising).
- Native USB attach, reset, enumeration, hot-unplug, and signal integrity,
  including no false `VBUS_PRESENT_N` with the cable absent (U3 pin 5 is now
  unconnected).
- 1,000 contact-observed transitions with no MOT6 byte/frame splice.
- Three-hour load/thermal and Wi-Fi/BLE coexistence runs.
- Enclosure connector, screw, mounting, resin, clearance, and RF checks.
- Proxy-only first treadmill contact and separately authorized Emulate test.

## Decision

The design may be described as ready for read-only vendor review and a possible
owner-authorized verification prototype after that review. It may not be
described as physically proven, production safe, or cleared for treadmill
operation.

Keep HOLD until the owner reviews the vendor results and explicitly decides
whether to accept the unavoidable pre-prototype physical unknowns. Regardless
of that prototype decision, production operation remains blocked until every
applicable firmware and bench gate is evidenced.
