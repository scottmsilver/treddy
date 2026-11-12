# Esp32Tap Rev E engineering review

**Status: HOLD.** This report is not authorization to fabricate, pay, deploy,
or operate a treadmill.

## Executive conclusion

Rev E is internally coherent under the checked repository models:

- 95 × 58 mm four-layer PCB;
- U1 fully inside the board with 3.25/3.30 mm margins and its stock all-layer
  manufacturer keepout intact;
- J1/J2 are the identical Molex 44144-0003 (`441440003`, LCSC C585890)
  right-angle SMD 8P8C RJ45 jack, placed by standard top-side reflow,
  board-mounted with the mating opening facing off the board edge — no
  external pigtail harness and no mechanical keying between console and
  motor;
- serial +8 V as the only board power source and USB as data-only;
- hardware-qualified relay and TX permissions, plus a relay liveness switch
  (Q3) that needs a toggling `RELAY_PULSE`;
- cycle-free, via-free, closely matched native USB routing;
- exact 2 A emitted-copper trace-union analysis with independent GND-via
  envelope;
- exact schematic/PCB/BOM/CPL/fabrication parity;
- twelve repeated dual-engine behavioral simulation decks.

This closes repository-detectable consistency defects. It does not close
vendor, firmware, or physical safety work.

## Safety and power architecture

```text
J1/J2 RJ45 serial +8 V pass-through
        |
        +-- F1 -- D1 -- VIN -- U2 ------------------------- +3V3
                         |                                   |
                         +-- D3 clamp                        +-- U6 gates
                         +-- U4 voltage window                   |
                         +-- U5 gated relay supply               +-- U7 TX

RELAY_GATE = RELAY_CMD AND TREAD_OK
TX_GATE    = TX_ENABLE AND TREAD_OK
K1 energized = RELAY_GATE (U5 and Q1) AND RELAY_PULSE toggling (Q3)
```

Q3 (AO3400A) is in series with Q1's emitter. Its gate is fed only through C22
and the D8 charge pump from `RELAY_PULSE` (U1 IO8, via R35), with R34 and C23
as the hold. K1 therefore needs three things: `TREAD_OK`, `RELAY_CMD` static
high, and `RELAY_PULSE` toggling. This closes two review findings: a single
stuck U6 output could hold K1 on, and a hung MCU holding static pins could
keep the board driving the motor line. Calculated, not measured: gate about
2.55 V at a 1 kHz square wave (2.33 V at 500 Hz); one stray edge moves the gate about 0.27 V,
below the 0.65 V minimum threshold; release roughly 50-150 ms after toggling
stops (not a guaranteed deadline). The switch alone is not single-fault tolerant:
a C22 short, R34 open, C23 open or Q3 drain-source short each defeats it, and
each needs a second fault to matter. Bench: scope Q1 base/emitter/collector when
pulses stop with `RELAY_GATE` high (BC817 reverse VBE limit 5 V). The pulse firmware is
implemented in `firmware/esp32_rs` but unproven on hardware (bd
`precor-9_3x-4uv` stays open until bench proof): a 500 us `esp_timer` callback
toggles IO8 at 1 kHz only while the supervised serial engine keeps renewing a
permission that expires 20 ms after the last renewal; it is not LEDC/RMT/PWM.
Nothing has run on a board, and QEMU cannot observe the charge pump.

R33 (1 MΩ, `TREAD_OK` to `UV_SENSE`) adds about 0.5 V of undervoltage
hysteresis; nominal UV is about 5.9 V falling and 6.4 V rising (calculated and
simulated; an earlier 6.31/6.85 V figure in this report was wrong).
D5-D7 are 5 V standoff Nexperia PESD5V0S1BA,115 parts because the serial line
voltage has never been measured. SW1/SW2 pad numbering was corrected to rows
(the old numbering would have shorted EN and IO0 to GND); not yet proven on
hardware.

USB VBUS ends in protection, bypass, discharge, and presence detection. It has
no local-power path. U3 pin 5 is unconnected: tied to the VBUS sense net it let
the ESP32 D+ pull-up leak onto that net and could assert `VBUS_PRESENT_N` with
no cable. The USB and treadmill grounds are common, so safe
simultaneous attachment remains a bench gate.

The relay's feedback pole is an armature proxy, not direct continuity sensing
of the transfer pole. Contact operation, release, bounce, weld behavior, and
fault-to-stable-NC time remain unsupported.

## PCB power disposition

The exact 2 A trace-union solve gives:

- +8 V: 17.313 mΩ;
- conservative explicit-copper GND (In1.Cu strips counted, plane still ignored): 25.151 mΩ;
- combined loop drop: **84.929 mV** (layer-aware copper thickness: 35 µm outer, 15.2 µm inner).

Coincident trace primitives are treated as one physical copper union, while
geometrically separate branches remain parallel. Duplicate coincident
intended vias fail validation.

At the worst exact +8 V case, maximum via current is 0.827864 A, barrel rise
is 7.482581 °C, and I²R is 0.685491 mW. The trace model does not solve In1
plane current sharing, so every 1.4/1.0 mm GND via receives a separate
full-2.0-A envelope: 12.273573 °C and 1.600310 mW at 20 µm plating.

Twenty micrometres is the IPC-6012 Class 2 average PTH copper basis cited by
JLC, not measured delivered copper. The live quote/DFM must confirm it.
Complete installed drop, ambient temperature, airflow, solder joints, RJ45
terminations, treadmill source impedance, and transients remain unsupported.

## USB disposition

USB stays on F.Cu with zero signal vias. The controlled sections use
0.2906 mm traces and a 0.2000 mm edge gap. Exact shortest paths are:

| Side | D− | D+ | Skew |
|---|---:|---:|---:|
| A | 55.9528786214 mm | 55.8729617233 mm | 0.0799168981 mm |
| B | 54.9528786214 mm | 54.8729617233 mm | 0.0799168981 mm |

Production stack/impedance, native USB ROM/reset attachment, enumeration,
unplug behavior, eye margin, and USB/treadmill return current remain open.

## Interfaces and manufacturing

J1/J2 are two instances of Molex 44144-0003 (`441440003`), a right-angle SMD
8P8C RJ45 jack (LCSC `C585890`), edge-mounted with the mating opening facing off a short
board edge (Rev E: J1 off X=0, J2 off X=95, one jack per enclosure end)
so a standard RJ45 plug reaches through the enclosure wall
aperture. There is no separate pigtail harness to quote or qualify; the
treadmill cable plugs directly into the assembled board. Because J1 and J2
are mechanically identical, console/motor differentiation is silkscreen and
housing color only — RJ45 single-open 2 A behavior remains unqualified.

J1, J2 and J3 are all standard top-side reflow parts. J3's four plated S1
holes are mechanical stakes in the stock footprint (now with paste apertures
and thermal spokes); no manual/wave operation is requested.

U1 is fully on-board with the locked margins above. Three open manufacturing
items are recorded honestly, not solved:

- 41 via drills still touch pasted SMD pads; they were not rerouted. The
  order must select JLC's paid "Epoxy Filled & Capped" via covering (JLC states
  it is free only on 6+ layers; eligible holes up to 0.5 mm; price only from
  the quote tool). bd `precor-9_3x-ilf`.
- The board is 58 mm on one axis; JLC Standard PCBA needs 70 x 70 mm minimum
  plus rails and fiducials. The order needs JLC-added rails to reach 70 mm
  (or a 2-up panel), with routed tabs away from C2, C7, F1, D1, D3 and R5.
  Those parts were not moved. bd `precor-9_3x-idr`.
- RJ45 footprint pad 1 verified by eye as Molex circuit 1 (SD-44144-001 rev
  H9 sheet 2); bd `precor-9_3x-192` closed. A built board still has to confirm
  supply polarity and the pin-3/pin-6 taps.
- CPL rotations are raw KiCad angles with no JLC correction table; every
  polarized or multi-pin part must be checked in JLC's placement preview
  before paying. bd `precor-9_3x-f5y`.

The enclosure closes with screws only (snap latches deleted), in MJF nylon
PA12; the owner supplies the screws listed in `enclosure/DIMENSIONS.md`.

The existing operator-observed online JLCDFM JSON is preserved as historical
evidence bound to an older archive. A new live review must use the current
exact 13-member ZIP together with its exact BOM, CPL, and placement preview.

## Simulation and evidence boundary

Eight decks run three times on host ngspice 42 and pinned Docker ngspice 39:
input protection, treadmill permission, safety truth table, relay drive,
VBUS presence, averaged buck, UART taps, and harness supply drop. The last
models the removed Micro-Fit harness and is historical only. The VIN decks
use 26 uF effective capacitance (22 uF worst corner) for the Rev E 43.2 uF
nominal input bank. The relay-drive and truth-table decks include the Q3
liveness switch as a behavioral model; its timing is a model output, not a
measurement. The treadmill-permission UV corners are divider-only and do not
include R33.

The exact unsupported list remains `RJ45_SINGLE_OPEN_2A`,
`MINIMUM_VIN`, `SOURCE_IMPEDANCE`, `AMBIENT_THERMAL`,
`TRANSIENT_RESPONSE`, `COMPLETE_INSTALLED_DROP`, `USB_RETURN_CURRENT`, `ESD`,
`RF`, and `SWITCHING_LOOP`. The simulation manifest additionally keeps
device thermal/leakage, real surge/rail behavior, relay contact motion,
native-USB channel behavior, regulator switching/EMI, real UART integrity,
and physical enclosure/RF effects unsupported.

The host firmware model is not production ESP-IDF firmware and cannot prove
GPIO timing, watchdog release, brownout behavior, security, radio coexistence,
or treadmill safety.

## Recommendation

Keep HOLD. The next allowed actions are read-only/live vendor reviews of the
current exact ZIP/BOM/CPL, 20 µm barrel plating, standard-reflow J3 stakes,
rails/panel to 70 mm, filled-and-capped vias, placement rotations, and
enclosure quote. Purchase requires owner authorization
after those reviews. First treadmill contact remains Proxy-only with relay
energization compiled out; Emulate requires a later explicit gate.
