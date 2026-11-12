# Esp32Tap Rev E

**Status: HOLD.** Do not submit fabrication, authorize substitutions, pay, or
connect an Emulate-capable build to a treadmill until the applicable vendor,
firmware, harness, and bench gates are closed.

Esp32Tap sits inline between the console and motor-controller serial cables of
a Precor 9.31. In Proxy mode a normally closed relay preserves the passive
console path. Emulate mode transfers that path to a hardware-gated ESP32-S3
transmitter. The treadmill safety key remains authoritative; this board is not
a certified functional-safety controller.

## Rev E architecture

- J1/J2 are both the identical Molex 44144-0003 (441440003, LCSC C585890)
  right-angle SMD 8P8C RJ45 jack, placed by standard top-side reflow (no
  through-hole RJ45, no wave or manual solder step), edge-mounted with the
  mating opening facing off a short board edge: J1 (CONSOLE) off the left
  edge, J2 (MOTOR) off the right edge, so the board reads console → motor left
  to right. There is no pigtail harness and no mechanical keying between
  console and motor; CONSOLE/MOTOR silkscreen is the only differentiator. The
  ESP32 module is fully on-board (no antenna overhang, no carrier panel).
- The treadmill cable's +8 V rails are the only board power input and pass
  directly between J1/J2. F1/D1 protect only the local branch.
- USB-C is native data and VBUS-presence sensing only. USB cannot energize the
  board or relay; programming needs current-limited serial +8 V bench power.
- K1 needs three things at once: `TREAD_OK`, `RELAY_CMD` static high, and
  `RELAY_PULSE` (U1 IO8) toggling. `TREAD_OK` also gates the motor TX buffer.
  `RELAY_GATE` (U6 output to U5 enable and the Q1 base) is unchanged; Q3, in
  series with Q1's emitter, is fed only by a charge pump from `RELAY_PULSE`.
  Calculated, not measured: the relay releases roughly 50-150 ms after
  toggling stops (not a guaranteed deadline), and one stray edge cannot turn
  Q3 on. The switch alone is not single-fault tolerant (C22 short, R34 open,
  C23 open or Q3 drain-source short each defeat it; each needs a second fault). The pulse
  firmware is implemented in `firmware/esp32_rs` but unproven on hardware (bd
  `precor-9_3x-4uv` stays open until bench proof): a 500 µs `esp_timer`
  callback toggles IO8 (1 kHz) only while the WDT-supervised serial engine keeps
  renewing a permission (every 5 ms pass; it expires 20 ms after the last
  renewal), so a hung safety loop stops the pulses within 20 ms. It is
  deliberately not LEDC/RMT/hardware PWM. Pulses are wanted only in
  EntryWaitGap, EntryWaitFeedback, Emulating and ExitWaitGap, so in Proxy a
  stuck `RELAY_GATE` still cannot energize K1.
- K1 uses one transfer pole and one armature-feedback pole; feedback does not
  prove transfer-contact continuity.
- U3 (USBLC6-2SC6) pin 5 is unconnected. Tied to the VBUS sense net it let the
  ESP32 D+ pull-up leak onto that net and could assert `VBUS_PRESENT_N` with
  no cable.
- D5-D7 are Nexperia PESD5V0S1BA,115 (LCSC C19224), 5 V standoff, because the
  treadmill serial line voltage has never been measured.
- R33 (1 MΩ, `TREAD_OK` to `UV_SENSE`) adds about 0.5 V of undervoltage
  hysteresis. Nominal UV is about 5.9 V falling and 6.4 V rising
  (calculated and simulated).
- SW1/SW2 (Alps SKRPACE010) pad numbering was corrected to rows (pad 1 = both
  top lands, pad 2 = both bottom lands). The old column numbering would have
  shorted EN and IO0 to GND through the switch body. Not yet proven on
  hardware.
- Three board-only fiducials FID1-FID3, and all stock footprints pinned in
  `tools/footprint_sources/stock` (`MANIFEST.json` sha256) so a KiCad library
  update can no longer make the board unreproducible.

## Package map

| Path | Purpose |
|---|---|
| `tools/design.py` | Electrical source of truth |
| `kicad/Esp32Tap.kicad_sch` | Generated typed schematic |
| `kicad/Esp32Tap.kicad_pcb` | Generated 95 × 58 mm four-layer PCB |
| `bom/BOM.csv` / `bom/CPL-positions.csv` | Exact assembly inputs |
| `kicad/Esp32Tap-gerbers.zip` | Deterministic 13-member fabrication archive |
| `kicad/models/` | Committed RJ45 jack 3D model (STEP + WRL, LCSC C585890) |
| `sim/` | Eight ngspice decks (one retired) and dual-engine assertion runner |
| `firmware/PLAN.md` | Production firmware and bench contract |
| `firmware/safety_model.py` | Host reference, not flashable firmware |
| `ORDERING.md` | HOLD-state vendor review procedure |
| `AI-HANDOFF.md` | Concise continuation brief |

Do not repair generated hardware or assembly outputs by hand.

## Locked board facts

| Item | Rev E value |
|---|---|
| Finished outline | 95.0 × 58.0 mm |
| Stack | Four layers; modeled 1.59 mm `JLC04161H-7628` |
| Board connectors | J1/J2 both Molex 44144-0003 (`441440003`, LCSC C585890), right-angle SMD 8P8C RJ45, unkeyed, standard top-side reflow; J1 (CONSOLE) on the left short edge, J2 (MOTOR) on the right short edge |
| BOM | 82 line items, 46 distinct LCSC parts, about $8.79 parts per board (generated `bom/BOM.csv`) |
| DRC | Fresh KiCad 10.0.5, all severities and schematic parity: 0 violations. The earlier committed `drc.rpt` claimed 0 while 10.0.5 reported 8 |
| Antenna | U1 fully on-board; 3.25/3.30 mm body margins. Keepout split: inner and bottom layers forbid tracks, vias and fills; the front layer forbids fills and vias and allows the U1 pad fan-out stubs. Fixture keepout emitted 0.30 mm inset |
| USB | F.Cu-only, zero signal vias, 0.2906 mm width / 0.2000 mm controlled edge gap |
| USB paths | D− A/B 55.9528786214/54.9528786214 mm; D+ A/B 55.8729617233/54.8729617233 mm |
| USB per-side skew | 0.0799168981 mm |
| 2 A PCB trace-union drop | 84.929 mV supply plus return (+8 V 17.313 mΩ, explicit-copper GND 25.151 mΩ; layer-aware copper model) |
| +8 via maximum | 0.827864 A; 7.482581 °C rise |
| GND-via envelope | Full 2.0 A in any via; 12.273573 °C and 1.600310 mW at 20 µm plating |

The GND return result is a conservative trace-only solve. The independent
full-current GND-via envelope covers omitted plane sharing; neither result
claims complete installed behavior.

## Reproduce

From repository root:

```bash
make -C hardware/Esp32Tap clean-check
make -C hardware/Esp32Tap check
git diff --check
```

The simulation runner executes twelve decks three times on host ngspice 42 and
pinned Docker ngspice 39. Passing proves only the declared models and artifact
parity. The Q3 liveness switch is simulated as a behavioral charge pump; the
times it reports are model outputs, not measurements.

## Bring-up sequence

1. Inspect identity, polarity, soldering, shorts, NC bypass, and TX isolation.
2. Apply current-limited +8 V at the documented RJ45 power contacts;
   verify VIN, +3V3, relay-off supply state, TREAD_OK, current, and temperature.
3. Establish a reviewed USB/treadmill bonding or isolation setup, then test
   VBUS presence, ROM/reset attach, enumeration, and unplug.
4. Use isolated serial fixtures for line loading, inverted idle, gap capture,
   relay transfer, feedback, and zero-frame ordering.
5. Complete the production firmware manifest and all `firmware/PLAN.md` gates.
6. Make first treadmill contact Proxy-only with relay energization compiled
   out. Emulate is a later, separately authorized test.

The exact unsupported harness claims are `RJ45_SINGLE_OPEN_2A`,
`MINIMUM_VIN`, `SOURCE_IMPEDANCE`, `AMBIENT_THERMAL`,
`TRANSIENT_RESPONSE`, `COMPLETE_INSTALLED_DROP`, `USB_RETURN_CURRENT`, `ESD`,
`RF`, and `SWITCHING_LOOP`.

## Known open items

- Live JLC review of the current archive/BOM/CPL/placement, 20 µm hole copper,
  J3 mechanical-stake reflow, and the enclosure quote remains open.
- 41 via drills still touch pasted SMD pads and were not rerouted. The order
  must select JLC's paid "Epoxy Filled & Capped" via covering (JLC states it
  is free only on 6+ layers; eligible holes up to 0.5 mm; price only from the
  quote tool). bd `precor-9_3x-ilf`.
- The board is 58 mm on one axis; JLC Standard PCBA needs 70 x 70 mm minimum
  plus rails and fiducials. The order needs JLC-added rails wide enough to reach
  70 mm (or a 2-up panel), with routed tabs kept away from C2, C7, F1, D1, D3
  and R5 near the bottom edge. Those parts were not moved. bd `precor-9_3x-idr`.
- CPL rotations are raw KiCad angles with no JLC correction table. Every
  polarized or multi-pin part must be checked in JLC's placement preview
  before paying. bd `precor-9_3x-f5y`.
- Treadmill serial line level and +8 V rail under load are unmeasured. bd
  `precor-9_3x-3pb`.
- `RELAY_PULSE` firmware is implemented, unproven on hardware (nothing has run
  on a board; QEMU cannot observe the charge pump; edge timing on the real pin
  under flash/network/BLE load needs a scope). bd `precor-9_3x-4uv`. Bench: scope
  Q1 base/emitter/collector when the pulses stop with `RELAY_GATE` high (BC817
  reverse VBE limit 5 V).
- Verified by eye: RJ45 footprint pad 1 (x = -4.45) matches Molex circuit 1,
  the leftmost contact land in the component-side layout of SD-44144-001 rev H9
  sheet 2. bd `precor-9_3x-192` is closed. A built board still has to confirm
  supply polarity and the pin-3/pin-6 taps.
- The buck input capacitor C3 was not moved closer to U2 (low-severity review
  note).
- `firmware/esp32_rs/partitions_esp32tap.csv` (nvs 24K, phy_init 4K, factory
  2 MB, storage LittleFS 1 MB) has not been verified against a real build.

The correct decision remains HOLD.
