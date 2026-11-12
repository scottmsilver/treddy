# Esp32Tap Rev E — handoff and advice for Claude

**Status: HOLD. Do not submit an order, add the design to a production cart,
authorize substitutions, or pay. Do not connect an Emulate-capable build to
the treadmill.**

Claude: preserve the distinction between repository evidence, vendor evidence,
and physical evidence. A passing model is not an assembled-treadmill result.

## Rev E facts that must not regress

- The finished board is **95.0 × 58.0 mm**, four layers, on the modeled
  `JLC04161H-7628` stack.
- U1 is fully inside the finished outline (no antenna overhang, no carrier
  panel). Its locked body-to-edge margins are **3.25 mm and 3.30 mm**. The
  antenna-band keepout is split: inner and bottom layers forbid tracks, vias
  and fills; the front layer forbids fills and vias but allows the U1 pad
  fan-out stubs. The fixture keepout is emitted 0.30 mm inset.
- KiCad DRC does **not** police rule-area track/via intrusions in this
  project, so `gen_pcb.py`'s grid router blocks the keepout itself
  and `test_no_track_or_via_copper_inside_antenna_keepouts` audits the
  finished board. A fresh KiCad 10.0.5 DRC with all severities and schematic
  parity reports 0 violations; the previously committed `drc.rpt` claimed 0
  while 10.0.5 reported 8. The UART probe pads
  TP1/TP2 live beside U1's east pad column for this reason — at their old
  west-edge home the U0TXD/U0RXD links had to cross the antenna strip.
- J1/J2 are the identical right-angle **SMT Molex 44144-0003** (441440003,
  LCSC `C585890`) 8P8C RJ45 jack, placed by standard top-side reflow, edge-mounted with the mating opening facing off
  a short board edge — Rev E: J1 (CONSOLE) off the left edge and J2
  (MOTOR) off the right edge. There is no separate pigtail harness and no
  mechanical keying between console and motor; CONSOLE/MOTOR silkscreen is
  the only differentiator.
- The treadmill cable's +8 V conductors are the board's only power source.
  USB-C is native USB data plus VBUS presence detection only. It cannot power
  VIN, +3V3, +5V_RLY, or K1. **USB alone cannot power or program Rev E.**
  Programming requires USB data and **current-limited +8 V bench power**.
- USB is not galvanically isolated. Measure host-to-treadmill ground potential
  and connection current and review bonding/isolation before simultaneous
  treadmill and host attachment.
- K1 pole A transfers CONS6/MOT6/TX_DRV; pole B reports armature state. Pole B
  cannot prove pole A is unwelded. `TREAD_OK` hardware-gates both
  `RELAY_CMD` and `TX_ENABLE`.
- **K1 now needs three things:** `TREAD_OK`, `RELAY_CMD` static high, and
  `RELAY_PULSE` (U1 IO8, via R35) toggling. Q3 (AO3400A) is in series with
  Q1's emitter (Q1.2 -> `RELAY_RTN` -> Q3 drain; source to GND). Q3's gate is
  fed only through C22 and the D8 (BAT54S) charge pump, with R34 and C23 as the
  hold. `RELAY_GATE` (U6 output to U5 enable and Q1 base via R9) is unchanged.
  This closes two review findings: a single stuck U6 output could hold K1 on,
  and a hung MCU holding static pins could keep the board driving the motor
  line. Calculated, NOT measured: gate about 2.55 V at 1 kHz (2.33 V at 500 Hz; the AO3400A on-resistance is specified at 2.5 V); one stray edge
  moves the gate about 0.27 V (below the 0.65 V minimum threshold); release
  roughly 50-150 ms after toggling stops (R34 x C23 = 100 ms time constant; not a guaranteed deadline). The
  `sim/` models agree in order of magnitude and are also not measurements.
  **Firmware requirement, not implemented (bd `precor-9_3x-4uv`):** IO8 must
  be toggled from the watchdog-supervised safety task as a 1 kHz square wave or faster, and
  must NOT be driven by LEDC/hardware PWM or a free-running timer, because
  those keep running when the task hangs. Until then the board cannot transfer
  the relay (it stays in bypass/Proxy, the safe direction). The liveness
  switch is not single-fault tolerant on its own: a C22 short, R34 open, C23
  open or Q3 drain-source short each defeats it, and each needs a second fault
  to matter. Open bench item: scope Q1 base/emitter/collector when the pulses
  stop with `RELAY_GATE` high (BC817 reverse VBE limit is 5 V).
- **Other Rev E changes (2026-11-11, owner-approved after a design review):**
  SW1/SW2 pad numbering corrected to rows (the old column numbering would
  have shorted EN and IO0 to GND; not yet proven on hardware); D5-D7 are
  Nexperia PESD5V0S1BA,115 (C19224) 5 V standoff because the serial line
  voltage was never measured; R33 1 MΩ adds about 0.45 V of undervoltage
  hysteresis (nominal UV about 6.31 V falling, 6.85 V rising, calculated); U3
  pin 5 is unconnected (tied to the VBUS sense net it let the ESP32 D+ pull-up
  assert `VBUS_PRESENT_N` with no cable); J3 shell stakes have paste
  apertures and thermal spokes; fiducials FID1-FID3 added; stock footprints
  pinned in `tools/footprint_sources/stock` (`MANIFEST.json` sha256); the late
  nets are routed in a second pass that may use F.Cu. Enclosure: screws-only
  closure, LED1 hole at (93.0, 13.0), 0.4 mm/side lid lip clearance, MJF
  nylon PA12; the owner supplies 2 nylon M3x10 countersunk, 2 steel M3x10
  countersunk, 3 steel M2.5x5 pan head (`enclosure/DIMENSIONS.md`).
  `firmware/esp32_rs/partitions_esp32tap.csv` now exists and is not yet
  verified against a real build.

`tools/design.py` is the electrical source of truth. Change generated hardware
only through its generators; never hand-edit PCB nets, BOM/CPL rows, or
Gerbers.

## Exact repository evidence

- The exact 2 A PCB trace-union solve is **84.929 mV** supply-plus-return:
  +8 V is 17.313 mΩ and the conservative explicit-copper GND return
  (dedicated In1.Cu strips; the plane itself is still ignored) is
  25.151 mΩ. Rev E spans the full board (J2 moved to the right edge);
  the model is layer-aware (35 µm outer, 15.2 µm inner copper). These come
  from `_power_proof` in `tests/test_generated_artifacts.py` (pinned there to
  0.017313 / 0.025151 / 0.084929), re-run on 2026-11-11.
- The +8 V solve's maximum via current is **0.827864 A**; its conservative
  IPC-2221 internal-barrel rise is **7.482581 °C** and I²R is
  **0.685491 mW**.
- Every intended GND stitching via is 1.4/1.0 mm. Because the In1 plane is not
  solved exactly, each is independently qualified at the full 2.0 A:
  **12.273573 °C** rise and **1.600310 mW** I²R using a conservative
  **20 µm** barrel. JLC's live quote/DFM must confirm IPC-6012 Class 2
  20 µm average hole copper; the repository does not prove delivered plating.
- USB shortest paths are:
  D− A/B = 55.9528786214/54.9528786214 mm and
  D+ A/B = 55.8729617233/54.8729617233 mm. Per-side D+/D− skew is
  0.0799168981 mm (gate 0.5 mm). Signals stay on F.Cu with zero signal vias; controlled
  sections use 0.2906 mm copper and 0.2000 mm edge gap.
- The simulation gate has **eight decks**. Each runs three times on host
  ngspice 42 and pinned offline Docker ngspice 39. `harness_supply_drop`
  models the removed Micro-Fit pigtail harness and is historical only. The
  VIN decks use 26 uF effective capacitance (22 uF worst corner), from C1 22 +
  C2 10 + C3 10 + C15 1 + 0.2 uF = 43.2 uF nominal; the `buck_averaged` source
  peak moved 1.909 A -> 0.465 A as a result (`sim/README.md`).
- The fabrication export has exactly 13 deterministic members, and the
  assembly audit binds design, schematic, PCB, BOM, CPL, DNP state, package,
  position, side, and rotation.

These are model and consistency results. They do not establish complete
installed voltage drop, temperature, vendor acceptance, or treadmill safety.

## Firmware contract

`firmware/safety_model.py` is an executable **host reference**, not production
firmware. Production behavior must preserve:

- one owner tuple `(transport, concrete handle, generation)`;
- only that owner may mutate motion or renew liveness;
- **one 4 s manual total-silence lease**, with no reconnect grace;
- complete valid parsed frame freshness at **1.5 s**;
- due deadlines before operations at the same timestamp;
- zero command → idle-low → TX enable → qualified gap → relay command →
  stable Emulate feedback → first complete zero frame;
- complete zero frame → qualified gap → relay off → stable bypass feedback →
  TX off → owner release;
- immediate fail-closed action for TREAD_OK loss, stale console, lease expiry,
  emergency stop, brownout, reset, WDT, or `BOTH_CLOSED`;
- feedback qualification from real continuously stable GPIO samples, not a
  timer alone.

GPIO7 is `VBUS_PRESENT_N`: LOW means VBUS present.
Espressif's stock self-powered TinyUSB VBUS-monitor input is active-high;
production firmware needs a reviewed inversion/attach strategy. A physical
STOP whose encoded value was already zero is not universally detectable from a
value-change parser unless captures establish a separate wire event.

Every Emulate-capable ESP-IDF build also needs the `RELAY_PULSE` (IO8)
liveness toggle described above, or K1 cannot energize.

Every Emulate-capable ESP-IDF build needs the exact ESP32-S3 target, a 2 s
panic WDT subscribed to every task that can leave K1 energized, immediate
silent reboot, no debug halt/delay path, and an enabled brownout threshold
below the measured minimum +3V3. Archive the resulting `bundle_sha256`.

## Reproduce before advice

From repository root:

```bash
make -C hardware/Esp32Tap clean-check
make -C hardware/Esp32Tap check
git diff --check
```

The eight simulations run with:

```bash
python3 hardware/Esp32Tap/sim/run_simulations.py \
  --host-ngspice /usr/bin/ngspice \
  --docker-image ngspice-cached:latest
```

Only manifest-listed numeric assertions may say PASS. The exact unsupported
harness list is: `RJ45_SINGLE_OPEN_2A`, `MINIMUM_VIN`, `SOURCE_IMPEDANCE`,
`AMBIENT_THERMAL`, `TRANSIENT_RESPONSE`, `COMPLETE_INSTALLED_DROP`,
`USB_RETURN_CURRENT`, `ESD`, `RF`, and `SWITCHING_LOOP`.

## Gates that remain open

- a live JLC review of the **current exact** ZIP, BOM, CPL, and placement,
  including Standard PCBA placement confirmation for the Extended-class RJ45
  jacks (thinnest stock: C585890, 64 units at the 2026-11-12 refresh, 2 per
  board; all 46 distinct parts were in stock);
- confirmation of the selected stack/impedance and 20 µm Class 2 hole copper;
- J1/J2/J3 under normal top-side reflow—no manual/wave operation is
  requested;
- **filled-and-capped vias:** 41 via drills still touch pasted SMD pads and
  were not rerouted; the order must select JLC's paid "Epoxy Filled & Capped"
  covering (free only on 6+ layers per JLC; eligible holes up to 0.5 mm; price
  only from the quote tool). bd `precor-9_3x-ilf`;
- **Standard PCBA rails:** the board is 58 mm on one axis and JLC Standard
  PCBA needs 70 x 70 mm minimum plus rails and fiducials, so the order needs
  JLC-added rails wide enough to reach 70 mm (or a 2-up panel), with routed
  tabs away from C2, C7, F1, D1, D3 and R5 near the bottom edge. Those parts
  were not moved. bd `precor-9_3x-idr`;
- **placement rotations:** CPL rotations are raw KiCad angles with no JLC
  correction table; check every polarized or multi-pin part in JLC's preview
  before paying. bd `precor-9_3x-f5y`;
- treadmill serial line level and +8 V under load. bd `precor-9_3x-3pb`;
- **blocking:** nobody has confirmed by eye that RJ45 footprint pad 1 is Molex
  circuit 1 (pad dimensions match the Molex SD-44144-001 drawing text only). If
  mirrored, supply polarity and the pin-3/pin-6 taps swap. bd `precor-9_3x-192`;
- enclosure quote, material, physical fit, installed clearance, and RF range
  for the J1/J2 RJ45 wall apertures;
- treadmill +8 V/VIN/source-impedance/transient/load/thermal measurements;
- RJ45 single-open 2 A qualification and complete installed loop drop;
- relay contact timing/bounce/weld/temperature and 1,000 splice-free transfers;
- native USB ROM/reset attach, enumeration, unplug, eye margin, and ground
  current;
- production firmware, security, WDT/brownout evidence, and safety matrix.

The existing operator-observed JLCDFM JSON is bound to an older exact archive.
Preserve it as historical evidence; do not relabel it as review of Rev E's
current bytes. First treadmill contact remains Proxy-only with relay
energization compiled out.

## Superseded or legacy files (do not use as Rev E evidence)

- `bom/REV-C-PART-SELECTION.json` is a Rev C part selection kept beside the Rev E
  BOM. It lists a through-hole TE RJ45 jack and the Micro-Fit connectors.
  It is not a Rev E input and nothing in the repository reads it.
- `evidence/model.json` and `evidence/model/rev-c-enclosure.json` carry
  "Rev C" in the claim and file names. They are the enclosure model record and
  are pinned by `tests/test_enclosure.py` under that name, so the name was not
  changed. Treat "Rev C" there as a legacy label; check the recorded dimensions against `enclosure/DIMENSIONS.md`.
- `sim/decks/harness_supply_drop.cir` and its assertions model the removed
  pigtail harness. Historical only.
- `vendor/JLC-DFM-REVIEW.json` is bound to a superseded archive.
- The `rev_b_values` key in `sim/assertions.json` is a legacy name for the
  shared component-value block (pinned by tests).
- `PREFAB-ADVICE-FOR-CLAUDE.md` is an archived early audit.

Advice in one sentence: preserve HOLD, reproduce the current artifacts, state
model limits exactly, and obtain owner approval before any action that spends
money, changes a part, submits vendor files, or exposes a treadmill to
Emulate-capable hardware.
