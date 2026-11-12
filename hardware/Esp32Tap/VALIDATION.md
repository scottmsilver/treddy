# Esp32Tap Rev E validation record

**Status: HOLD.** Passing repository gates establish internal consistency
under declared models, not vendor acceptance or physical treadmill behavior.

**Evidence date:** 2026-11-11 (documents and simulations); the stock snapshot carries its own refresh date

## Canonical repository gate

```bash
make -C hardware/Esp32Tap clean-check
make -C hardware/Esp32Tap check
git diff --check
```

The declared engines include KiCad/pcbnew (a fresh DRC with all severities
and schematic parity ran on 10.0.5), host ngspice 42, pinned
offline Docker ngspice 39, and three repetitions of every simulation deck.

## Evidence ledger

| Area | Result | Repository-supported statement |
|---|---|---|
| Schematic | PASS | Typed Rev E schematic; ERC policy clean |
| PCB | PASS | 95 × 58 mm, four layers, exact net/pad parity; KiCad 10.0.5 DRC with all severities and schematic parity: 0 violations (the earlier committed report claimed 0 while 10.0.5 reported 8) |
| Antenna | PASS | U1 fully on-board; 3.25/3.30 mm margins; split keepout (inner/bottom: no tracks, vias, fills; front: no fills or vias, U1 fan-out stubs allowed), router-blocked and audited |
| USB | PASS | F.Cu-only, no signal vias, cycle-free planar topology, both A/B paths matched |
| Power | PASS under model | Exact 2 A trace-union solve plus conservative independent GND-via envelope |
| Assembly | PASS | Design↔schematic↔PCB↔BOM↔CPL identity and placement parity |
| Fabrication | PASS | Exact deterministic 13-member package |
| Simulations | PASS under models | Eight decks × three runs on host 42 and Docker 39; includes the behavioral Q3 liveness model; `harness_supply_drop` is a retired historical deck |
| Firmware | Host reference only | Safety state-machine and manifest policy tests |

## Board geometry and routing

- Finished outline: 95.0 × 58.0 mm.
- U1 body-to-finished-edge margins: 3.25 and 3.30 mm.
- J1/J2: identical Molex 44144-0003 (441440003, LCSC C585890) right-angle SMD
  8P8C RJ45 jacks placed by standard top-side reflow, edge-mounted with the mating opening facing off a short
  board edge (Rev E: J1 off X=0, J2 off X=95); no external pigtail
  hardware. There is no mechanical keying
  between the console and motor interfaces — CONSOLE/MOTOR silkscreen plus
  housing color are the only differentiator.
- USB shortest paths:
  D− A/B 55.9528786214/54.9528786214 mm,
  D+ A/B 55.8729617233/54.8729617233 mm.
- D+/D− per-side skew: 0.0799168981 mm (gate 0.5 mm).
- Controlled USB geometry: 0.2906 mm width and 0.2000 mm edge gap.

## Exact PCB power model

At 2.0 A the emitted-copper planar-union solve gives:

| Quantity | Result |
|---|---:|
| +8 V resistance | 17.313 mΩ |
| Conservative explicit-copper GND resistance | 25.151 mΩ |
| Supply-plus-return drop | 84.929 mV |
| +8 V maximum via current | 0.827864 A |
| +8 V maximum via rise | 7.482581 °C |
| +8 V maximum via I²R | 0.685491 mW |
| Maximum track rise (either net) | 6.660685 °C |

The graph splits intersections and collinear overlaps, unions coincident
same-layer copper, preserves distinct parallel routes, and rejects duplicate
intended via occurrences.

In1 plane sharing is not solved exactly. Therefore each 1.4/1.0 mm GND via is
also qualified independently at the full 2.0 A using 20 µm barrel plating:
12.273573 °C rise and 1.600310 mW I²R. This is a conservative envelope, not
an installed thermal result. The 20 µm assumption is the IPC-6012 Class 2
average-hole-copper basis described by JLC; live quote/DFM confirmation is
mandatory.

## Eight-deck ngspice evidence

`input_protection`, `tread_permission`, `safety_truth_table`,
`relay_drive_release`, `vbus_present`, `buck_averaged`, `uart_taps`, and
`harness_supply_drop` each run three times on both engines. Representative
supported values remain recorded in `sim/README.md`; `sim/assertions.json` is
the pass/fail authority. Changes on 2026-11-11: the VIN decks now use the Rev E
input capacitance (26 uF effective, 22 uF worst corner, from 43.2 uF nominal),
and `relay_drive_release` / `safety_truth_table` model the Q3 liveness switch
(K1 drives only with `TREAD_OK`, `RELAY_CMD` and a live pulse; U6 stuck high
with no pulses and Q1 shorted with no pulses both leave K1 off). The pump timing
is a behavioral model output, not a measurement. `tread_permission` does not
include R33. `harness_supply_drop` models the removed pigtail harness.

The exact machine-readable unsupported list is:

- `RJ45_SINGLE_OPEN_2A`
- `MINIMUM_VIN`
- `SOURCE_IMPEDANCE`
- `AMBIENT_THERMAL`
- `TRANSIENT_RESPONSE`
- `COMPLETE_INSTALLED_DROP`
- `USB_RETURN_CURRENT`
- `ESD`
- `RF`
- `SWITCHING_LOOP`

Scenario-specific unsupported simulation claims also remain unsupported:
PPTC thermal behavior; vendor diode leakage; out-of-envelope surges; real
treadmill rail/surge timing; regulator current-limit/thermal behavior; gate
propagation/partial-power leakage; RF coupling; relay contact motion and
guaranteed inductance; BC817 transient/combined-temperature saturation;
native USB attach/enumeration/eye margin; switching-loop margin/ripple/EMI;
vendor-model startup; real UART integrity/leakage; and all physical enclosure
effects.

## Current local artifact identity

| Artifact | SHA-256 |
|---|---|
| `kicad/Esp32Tap.kicad_pcb` | `8405b04b9ace391fb98c8290dc2df347d041a8b77d297151eab683e9bfc40b2f` |
| `kicad/Esp32Tap-gerbers.zip` | `a22659b79d96e59ddb3c1b71a8a72e4432c8d52ffe83726e9aaacc3a0b5467bb` |
| `bom/BOM.csv` | `3f1f839403734b5d5d65c05ac7118a2d1a5415a78f418237dbe476052ce706cc` |
| `bom/CPL-positions.csv` | `4420a03e3293327437d6278c4cc408dc4de813e3ce183b8396629886168de9ec` |

These identify repository bytes only. The operator-observed
`vendor/JLC-DFM-REVIEW.json` is bound to an older archive and must not be
presented as review of these bytes.

## Open vendor and physical gates

- live current ZIP/BOM/CPL placement and production CAM review, including
  the Extended-class RJ45 jacks' Standard PCBA placement support;
- stack/impedance and 20 µm barrel-plating confirmation;
- J1/J2/J3 accepted under normal top-side reflow, without manual/wave
  processing; J3's plated mechanical stakes in particular;
- paid "Epoxy Filled & Capped" via covering selected (41 via drills touch
  pasted SMD pads; bd `precor-9_3x-ilf`);
- JLC-added rails or a 2-up panel bringing the 58 mm axis to the 70 mm
  Standard PCBA minimum, tabs away from C2, C7, F1, D1, D3 and R5 (bd
  `precor-9_3x-idr`);
- every polarized or multi-pin part's rotation checked in JLC's placement
  preview (CPL angles are raw KiCad angles; bd `precor-9_3x-f5y`);
- current enclosure quote, material, fit, installed clearance, and RF tests
  for the RJ45 aperture geometry;
- treadmill source, minimum VIN, transient, complete installed drop, ambient,
  current, and thermal measurements;
- RJ45 single-open 2 A qualification;
- relay contact timing/bounce/weld/temperature and 1,000 transitions,
  including Q3 liveness pickup/release (calculated roughly 50-150 ms, not a guaranteed deadline), gate
  level (about 2.55 V at 1 kHz) and stray-edge immunity, a scope of Q1
  base/emitter/collector when pulses stop with `RELAY_GATE` high (BC817 reverse
  VBE limit 5 V), the fact that the switch is not single-fault tolerant alone, which firmware cannot yet exercise
  (`RELAY_PULSE` unimplemented; bd `precor-9_3x-4uv`);
- treadmill serial line level and +8 V under load (bd `precor-9_3x-3pb`);
- RJ45 footprint pad 1 = Molex circuit 1, confirmed by eye (blocking; bd
  `precor-9_3x-192`);
- SW1/SW2 pad numbering, R33 hysteresis, and U3 pin 5 / `VBUS_PRESENT_N`
  behavior confirmed on a built board;
- native USB attach/enumeration/unplug/eye/ground-current tests;
- production ESP-IDF binary, WDT/brownout, security, and safety matrix.

Until those applicable gates are closed and the owner authorizes purchase, the
correct decision remains HOLD.
