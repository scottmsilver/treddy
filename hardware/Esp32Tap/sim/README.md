# Esp32Tap Rev E behavioral simulations

These twelve ngspice decks are behavioral regression evidence for the Rev E
circuits. Eleven model Rev E parts. The twelfth, `harness_supply_drop`, models a
Micro-Fit pigtail harness that Rev E no longer has; it is kept as historical
regression evidence only and supports no Rev E claim. None of the decks is a
product certification, and none replaces production-hardware measurements.

The manifest key `rev_b_values` in `assertions.json` is a legacy name for the
shared component-value block; it is pinned by tests and was not renamed.

## Reproduce

From the repository root:

```bash
python3 hardware/Esp32Tap/sim/run_simulations.py \
  --host-ngspice /usr/bin/ngspice \
  --docker-image ngspice-cached:latest
```

The default is three complete repetitions. The runner requires:

- host `ngspice-42`;
- Docker `ngspice-39`;
- local image `ngspice-cached:latest` with immutable ID
  `sha256:6cb6c92d8ddfedc8857bec3884eb9dea6af1a28fac3524446abbc8bef4c1d0ae`.

It runs both engines with init files disabled (`ngspice -n`), executes Docker
by the inspected immutable image ID, keeps Docker offline with a read-only
bind mount, rejects a different engine major or image ID, and treats simulator
output as untrusted input.
Missing, duplicate, malformed, non-finite, or out-of-range measures fail.
Host/Docker and repeat-to-repeat values must agree within each measure's
absolute and relative tolerances in `assertions.json`.

## Result summary

Fresh runs on 2026-11-11 produced the same declared values on ngspice 42 and
39. Representative host values are:

| Deck | Behavioral evidence |
|---|---|
| `input_protection` | VIN capacitance modeled as 26 uF effective (22 uF in the high-breakdown copies); 8 V VIN = 7.625 V (F1 initial resistance) / 7.600 V (higher documented resistance bound); 16 V and 20 V worst high-breakdown pulse VIN peaks = 12.645 V / 12.531 V; low-breakdown D3 pulse energy = 18.1 mJ / 65.7 mJ; reverse VIN minimum = -0.27 mV |
| `tread_permission` | UV rising corners = 6.224–6.600 V; OV rising corners = 10.300–10.928 V; supervisor startup = 448.9 µs; an intentionally early +3V3 rail waits 364.0 µs; loaded U5 reaches 95% in 1.501 ms; OV disable including the 18 µs propagation corner = 36.1 µs; modeled C16/U5 disable tail to 0.5 V = 2.55 ms |
| `safety_truth_table` | all 16 `(+3V3, TREAD_OK, RELAY_CMD, TX_ENABLE)` rows match `RELAY_GATE = rail AND TREAD_OK AND RELAY_CMD` and `TX_GATE = rail AND TREAD_OK AND TX_ENABLE`; both default LOW. A second 16-row table over `(+3V3, TREAD_OK, RELAY_CMD, PULSE_ALIVE)` gives K1 drive HIGH only in the all-ones row. Fault cases: U6 `RELAY_GATE` stuck high with no pulses, and Q1 shorted with no pulses, both leave K1 drive LOW; Q1 shorted with `RELAY_GATE` low also leaves it LOW. `PULSE_ALIVE` is a behavioral boolean in this deck |
| `relay_drive_release` | 18.79–23.90 mA nominal-corner coil current; approved R9=560 Ω with conservative 2.3 V drive / 1.2 V VBE and resistor tolerances leaves 1.82 mA base current, 4.20 V across the worst-resistance coil, and forced β = 8.83; SMAJ decay to 2 mA = 0.184/0.864/1.628 ms for 0.1/0.5/1 H; Q1 peak = 12.27 V. Q3 liveness switch (simulated charge pump, 1 kHz square wave): gate 2.63 V steady; coil pickup 4.6 ms (0.65 V Q3 threshold) to 9.6 ms (1.45 V); release after the pulses stop held low 60 ms (1.45 V) to 140 ms (0.65 V), 156 ms if held high; one stray 3.3 V edge moves the gate 0.281 V peak, below the 0.65 V minimum threshold; a pin stepped high and held leaves 6.5 mV after 440 ms; a pin held low leaves the gate at 0; Q1 shorted with no pulses leaves 5 nA coil current |
| `liveness_firmware_trace` | The pin waveform comes from the firmware's real pulse-permission code, not an ideal source. Entry: the firmware waits 30.1 ms before commanding K1, by when the gate is at 2.51 V (worst Q3 threshold 1.45 V); coil pickup current 2.5 ms after the command. Safety loop hung while the timer keeps running: coil released 80 ms (1.45 V threshold) to 161 ms (0.65 V) after the last loop pass. Permission withdrawn: 60 to 141 ms. Timer held off 9 ms in every 100 ms: gate never below 2.42 V, coil holds. Loop and timer both stalled as during a flash erase: 45 ms leaves 1.74 V and the coil holds; 100 ms leaves 1.06 V and a 1.45 V-threshold Q3 drops the coil; 400 ms leaves 0.07 V and every part drops. One tick every 10 ms, which the firmware still counts as unbroken: gate peaks at 1.10 V, below the worst threshold |
| `hotplug_ringing` | 44 flat branches plug an ideal 8 V or assumed-9 V step through 0.5/2/5 uH loop inductance and 0.1/0.5 ohm source+cable resistance into F1 (0.11 ohm), D1 and 22/26/43.2 uF of 5 mohm-ESR ceramic, with D3 at 11.1 V breakdown, 12.3 V breakdown, or absent. Worst peak VIN = 12.134 V (9 V, 5 uH, 0.1 ohm, 22 uF; D3 absent and D3 12.3 V give the same value to 4 mV because the ring stays below D3's breakdown); 8 V worst = 10.729 V. D3 only conducts in the 11.1 V-breakdown copy: 1.82 A peak, 0.27 mJ at 9 V / 5 uH / 22 uF, clamping that branch to 11.769 V. Worst D1 forward peak = 25.55 A (9 V, 0.5 uH, 43.2 uF); worst D1 reverse = 7.91 V |
| `board_sequencing` | One connected chain (8 V source, F1/D1/D3, averaged buck, U4 window with R33 fed back through the real divider, TREAD_OK net, U6 AND, U5, Q1/Q3 with the RELAY_PULSE pump, K1 coil with D4) run through 18 scenario copies. Pins held high before power: coil current while TREAD_OK is low = 0 (< 1 µA limit) and the coil starts 4.8 ms after TREAD_OK rises. Normal run: pickup 3.12 ms after RELAY_CMD, release 0.98 ms after it falls, collector peak 11.98 V. 1 V/100 ms ramp with 102 mV ripple: with R33 exactly one TREAD_OK rise (at 6.37 V) and one fall (at 5.91 V) and one coil on/off; without R33 about 4 TREAD_OK transitions (about 11 with a 0.5 mV comparator band), though the coil still switches once. Brownouts while emulating: 6.5 V for 10 and 100 ms does not trip (VIN min 6.21 V); 6.0, 5.0 and 3.0 V for 10 ms and 3.0 V for 100 ms trip, TREAD_OK low 1.02 ms and coil below 2 mA 2.0 ms after the dip starts, and **the coil re-energizes by itself 3.6 ms (6 V, 10 ms) to 6.1 ms (3 V, 100 ms) after VIN returns**; a 3 V / 1 ms dip with 22 µF only dips the coil to 7.3 mA. 12 V step: VIN peak 11.38 V, coil below 2 mA 1.04 ms after the step. Power removed: coil below 2 mA 1.97 ms (20 µs cut) or 12.3 ms (50 ms collapse) after VIN starts to fall, no RELAY_GATE rise and no coil current above 0.1 mA after release. MCU hang with RELAY_CMD high: coil released by Q3 alone in 59.6 / 139.7 / 155.1 ms (1.45 V / 0.65 V held low / 0.65 V held high), RELAY_GATE still 3.27 V |
| `liveness_corners` | Worst-case corners of the Q3 liveness charge pump (explicit stacked tolerances, not measured). A steady gate: -20 C with 3.0 V and a 2.6 V/0.4 V pin = 1.446 V, below the 1.585 V cold maximum threshold, so the model coil carries 5 nA (**FAILS**); rail-to-rail 3.0 V = 2.129 V (0.544 V margin, passes); 25 C 1.641 V, 70 C 1.693 V, 70 C at maximum diode leakage 1.609 V, margins 0.19/0.38/0.29 V against a 0.5 V requirement (**FAIL**; the model coil is still 21.1 mA). B pickup to the highest threshold: 34.9 ms at 25 C (**FAILS** the 30 ms firmware precharge), 24.4 ms at 70 C, 27.5 ms at 70 C with maximum leakage, never at -20 C. C release after the pulses stop (strong pump, large C23/R34, 0.515 V threshold): 184 ms held low, 204 ms held high (**over the 0.2 s bound**), 221/244 ms if the diode leakage is the 25 C typical; plus the firmware 20 ms: 204-264 ms from MCU hang to coil off. D one stray edge: 0.508 V against a 0.515 V lowest threshold (7 mV margin, **FAILS** the 0.1 V margin); 3 consecutive 1.05 kHz edges (0.917 V) cross it, 2 do not; a pin toggling every 10 ms reaches 1.51 V. Q3 gate leakage and capacitance move the cold gate by 0.8 mV. 300-draw Monte Carlo (`run_montecarlo.py`, seed 20260712): steady gate 1.69-2.86 V, pickup 1.2-17.5 ms, release 15-177 ms, single-edge peak 0.11-0.47 V |
| `vbus_present` | active-low `VBUS_PRESENT_N` is 1.65 mV with VBUS and 3.3 V absent; true slow hot-plug corner reaches LOW in 4.083 µs; worst unplug-to-HIGH = 1.912 ms, strictly below 3 ms; modeled dead-rail/GPIO injection = 0 |
| `buck_averaged` | VIN capacitance modeled as 26 uF (22 uF worst corner); 90% startup = 4.634 ms; 450 mA step minimum = 3.233 V; worst modeled VIN = 6.865 V; worst source peak = 0.465 A; input/load energies = 12.93/5.38 mJ |
| `uart_taps` | 10–90% rise = 1.110 µs versus a 104.167 µs bit; one/two-tap unpowered injection = 0.286/0.572 mA |
| `harness_supply_drop` | RETIRED, historical only: the removed Rev C Micro-Fit connectors use the predecessor-authorized 1.35/0.65 A unequal case; opening each individual contact leaves 2.0 A in its surviving Micro-Fit contact; doubling each 10 mΩ contact in turn produces a 1.333333 A maximum branch current. Not a Rev E result |

The machine-readable limits, not this table, decide PASS or failure.

### Changes for Rev E

| Measure | Before | After | Cause |
|---|---|---|---|
| `buck_averaged` `worst_source_peak_a` | 1.909 A | 0.465 A | VIN capacitance corrected from 110/120 uF to 22/26 uF; the peak is mostly inrush into that capacitance. The assertion band moved from 1.5-2.1 A to 0.35-0.6 A. |
| `buck_averaged` `startup_90pct_s` | 4.495 ms | 4.634 ms | same |
| `input_protection` `safe16_d3_energy_j` | 15.5 mJ | 18.1 mJ | same |
| `input_protection` `safe20_d3_energy_j` | 62.1 mJ | 65.7 mJ | same |
| `input_protection` `reverse_vin_min_v` | 2.82 mV | -0.27 mV | same (faster discharge; the band still contains it) |

Rev E VIN capacitance is C1 22 uF + C2 10 uF + C3 10 uF + C15 1 uF + 0.2 uF =
43.2 uF nominal, about 26 uF effective at 7.5 V bias and 22 uF at the worst
corner. The effective values are a datasheet-derating estimate, not a
measurement.

### Q3 liveness switch (behavioral)

`relay_drive_release` simulates the R35, C22, D8, C23, R34 charge pump as a
circuit, with a transparent low-order BAT54S diode model, a smooth-conductance
Q3 with a 0.65-1.45 V threshold sweep, and an ideal 3.3 V, 1 kHz source.
`safety_truth_table` uses a boolean `PULSE_ALIVE` instead. The times above are
model outputs. They are not measured timing, and they do not show that
firmware can generate the pulses.

`liveness_firmware_trace` closes part of that gap. Its pin waveforms are
generated by `firmware/esp32_rs/safety_core/tests/liveness_trace.rs` from the
firmware's own `PulseBudget`, committed as `traces/liveness_firmware.inc`, and
that test fails if the committed trace no longer matches the code. So the
firmware's rules (30 ms precharge, 20 ms permission, cancel on forced Proxy)
are checked against the circuit they were written for. Tick and loop times are
still chosen by the generator, not measured on a chip.

The three "coil holds" minima in this deck are the minimum of a pulsed
waveform over hundreds of milliseconds, and the two ngspice versions differ by
about 0.6 % in that ripple, so those three measures carry a 1 % cross-engine
tolerance. Their pass limit (above 20.5 mA) is unchanged.

Known problem it found (bd `precor-9_3x-dh2`): **a flash erase can open the relay
mid-workout.** ESP-IDF suspends every task for the length of a flash
operation, so the safety loop and the pulse timer both stop; the firmware
checkpoints progress to flash every 30 s while a session runs. The Q3 gate
holds for only about 100 ms. With nominal parts and RELAY_CMD held high: a
45 ms stall (assumed typical 4 KB sector erase) takes the gate to 1.74 V and
the coil holds even with a 1.45 V-threshold Q3; a 100 ms stall takes it to
1.06 V and that coil drops; a 400 ms stall (the worst case the firmware's own
comments budget for) takes it to 0.07 V and every part drops. It fails toward
the console owning the belt, so it is an interrupted workout, not an unsafe
relay. QEMU does not stall tasks on flash, so no firmware gate can see this.
The real erase time of the module's flash is unmeasured.

Known gap it found: the precharge check counts edges, not rate. If the timer
ran 20 times slow for 600 ms (one tick every 10 ms) the firmware would report
the gate precharged while the simulated gate sits at about 1.1 V, too low for
a worst-case Q3. The result is a failed transfer and a return to Proxy, not an
energized relay, so it is an availability gap rather than a safety one.

## Corners and source basis

- F1 uses only fixed 0.11 Ω initial and 0.29 Ω R1max/post-trip resistance
  bounds for
  [Littelfuse 1812L075/24DR](https://www.littelfuse.com/products/fuses-overcurrent-protection/polyswitch-resettable-pptc-devices/surface-mount-polyswitch-resettable-pptc-devices/1812l/1812l075).
  Its 0.75 A hold and 24 V maximum do not define thermal behavior in SPICE.
- D3 uses the [Littelfuse SMBJ10A](https://www.littelfuse.com/assetdocs/tvs-diodes-smbj-series-datasheet?assetguid=ba555e99-a12d-4f72-a0b6-86b06c67171e)
  10 V standoff, 11.1–12.3 V breakdown, 17 V clamp, 35.3 A
  10/1000 µs peak-current, and 600 W pulse ratings. The manifest uses a
  conservative 0.3 J supported-energy bound. Separate low-breakdown and
  high-breakdown/high-clamp branches bound D3 stress and protected VIN.
- U4 corners come from the
  [TI TPS3700 datasheet](https://www.ti.com/lit/ds/symlink/tps3700.pdf):
  396–404 mV rising threshold, 387–400 mV falling threshold, and 450 µs
  maximum startup. R17/R18 and R19/R20 are swept at ±1%; C18/C19 are 1 nF;
  INA+/INB− bias-current bounds are ±25/±15 nA; and unsafe propagation
  includes the 18 µs maximum high-to-low delay.
- U5 uses the [TI TPS709 datasheet](https://www.ti.com/lit/ds/symlink/tps709.pdf)
  1.5 ms maximum EN-to-95%-VOUT startup for outputs above 3.3 V. Its control
  loop, current limit, and thermal behavior are not modeled.
- K1 uses the [Omron G6K data](https://components.omron.com/eu-en/products/relays/G6K)
  5 V/100 mW coil (237 Ω nominal). Coil resistance is swept ±10%.
  Because coil inductance is not a guaranteed data-sheet parameter, the
  0.1/0.5/1 H sweep is an explicit assumption.
- Q1's conservative branch uses the
  [Nexperia BC817-40 data](https://assets.nexperia.com/documents/data-sheet/BC817_SER.pdf)
  1.2 V maximum VBE together with a 2.3 V logic-output proxy. The selected
  560 Ω R9 is exercised at +1% while its 10 kΩ pull-down is at −1%. The
  resulting 1.82 mA base current and 16.11 mA coil current keep forced β at
  8.83, below the data-sheet VCEsat test ratio of 10, while the fixed 0.7 V
  maximum still leaves 4.20 V across the high-resistance coil. Combined-
  temperature saturation and transistor switching remain bench gates.
- D4 uses the
  [Littelfuse SMAJ6.0CA datasheet](https://www.littelfuse.com/assetdocs/tvs-diodes-smaj-datasheet?assetguid=13c2a823-03b8-4d1f-9ddc-9b44670aed9d)
  6 V standoff and 6.67–7.37 V breakdown corners.
- Q2 threshold corners use the selected C8545
  [JSCJ 2N7002 data](https://datasheet.lcsc.com/datasheet/pdf/a141b8bd86b14475955ac8c4d3eea0a8.pdf?productCode=C8545)
  1.0–2.5 V range at 250 µA. C11 is swept 90–110 nF, R29 is swept
  9.9–10.1 kΩ, and VBUS is swept 4.4–5.5 V.
- The buck deck uses the [TI TPS54202](https://www.ti.com/lit/ds/symlink/tps54202.pdf)
  5 ms soft-start and selected 3.3 V network only as an averaged envelope.
  The declared source impedance, capacitor derating, and 82–90% efficiency
  proxies are engineering assumptions.
- The retired `harness_supply_drop` deck keeps its original numeric
  assertions, which were tied to the removed Rev C Micro-Fit pigtail harness
  (430450809/430451010 connectors, Alpha Wire 3051 conductors). Its input
  file, `harness/electrical_limits.json`, no longer exists in the repository.
  Rev E has no such harness, so the deck's values describe no Rev E hardware.
- The Q3 liveness-switch decks use the Nexperia BAT54 family forward-voltage
  anchor (about 0.26 V at 0.1 mA and 0.32 V at 1 mA) and the AO3400A 0.65-1.45
  V gate-threshold range. Those two decks leave gate charge, capacitor
  tolerance, and leakage out; `liveness_corners` adds them.
- `hotplug_ringing` takes its absolute-maximum comparison values from the TI datasheets for the parts on VIN: [TPS54202](https://www.ti.com/lit/ds/symlink/tps54202.pdf) section 5.1, VIN -0.3 to 30 V; [TPS3700](https://www.ti.com/lit/ds/symlink/tps3700.pdf) section 6.1, VDD -0.3 to 20 V; [TPS709](https://www.ti.com/lit/ds/symlink/tps709.pdf) section 6.1, VIN -0.3 to 32 V. The 25 V rating of C1/C2/C3 is the rated voltage written in the BOM (NETLIST.md), not read from the capacitor vendor datasheet. Loop inductance (0.5/2/5 uH, about 1 uH per metre of loop), source+cable resistance (0.1/0.5 ohm), the 9 V upper source and the 10 kohm pre-start load are assumptions, not datasheet or measured values. F1 uses the 0.11 ohm cold value, D3 the existing 11.1/12.3 V models, and VIN capacitance the 22/26/43.2 uF values above with an assumed 5 mohm ESR.
- `board_sequencing` source basis. The subcircuit is built from `tools/design.py` nets and values (where the task brief and the netlist disagree, the netlist wins: RELAY_GATE, not TREAD_OK, enables U5) and reuses `PUMP`, `ESP_Q3`, `ESP_AND_GATE`, `ESP_BIDI_TVS` and the TREAD_OK/U5 delay structure of the earlier decks. The buck UVLO (4.2/3.9 V), the U5 dropout (0.3 V) and EN threshold (1.2 V), the comparator hysteresis (400/393.5 mV nominal) and the Q1 transistor parameters are assumptions, not data-sheet values. It uses `.options reltol=0.01` to run all 18 copies in about 7 s; a default-tolerance trial moved timing results by under 0.1 percent. It is a behavioral model: nothing here is measured, relay contact motion is not modeled (coil current below 2 mA is the only release criterion), and the self re-energizing after a brownout is a model result that depends on the MCU pins staying asserted, which firmware must handle.
- `liveness_corners` stacks tolerances on the Q3 liveness pump. Inputs: the
  [AO3400A data sheet](https://www.aosmd.com/res/data_sheets/AO3400A.pdf)
  (Vgs(th) 0.65-1.45 V at 250 uA, Ciss 630 pF, Igss 100 nA max; Fig 2 puts the
  125 C transfer curve about 0.2 V left of the 25 C one) and the BAT54 family.
  The Nexperia BAT54 data sheet could not be fetched (HTTP 403), so the diode
  points come from the
  [Diodes Incorporated BAT54/A/C/S data sheet](https://www.diodes.com/assets/Datasheets/ds11005.pdf)
  (DS11005 Rev 35-2): Vf at most 0.24 V at 0.1 mA, 0.32 V at 1 mA and 0.40 V at
  10 mA, IR at most 2 uA at 25 V, 25 C, with typical Vf and IR against
  temperature read by eye from its Figs 1 and 2 (Vf at 0.1/1 mA: 0.31/0.37 V at
  -20 C, 0.22/0.31 V at 25 C, 0.15/0.21 V at 70 C; IR at 3 V about 0.06 uA at
  25 C and 2.1 uA at 75 C). The
  [onsemi BAT54L data sheet](https://www.onsemi.com/pdf/datasheet/bat54lt1-d.pdf)
  agrees at 25 C (0.22/0.29 V typical Vf, 0.2 uA typical IR at 25 V). Capacitor
  derating (C22 70.5-126.5 nF, C23 0.557-1.265 uF), the -3 mV/C Q3 threshold
  coefficient, and the 20 mV Vf spread are assumptions; the Samsung curves for
  CL10A105KB8NNNC were not obtained. Four requirements fail in the stacked
  corners; see `liveness_corners` in `assertions.json`.
- `run_montecarlo.py` (300 draws, fixed seed, host ngspice only) writes
  `montecarlo_summary.json`. It is supplementary: it is not part of the
  dual-engine gate, and uniform draws across each tolerance band are an
  assumption, not a measured distribution.

## Explicitly unsupported

The runner prints every unsupported item as `UNSUPPORTED`, never `PASS`.
Important open gates include:

- PTC thermal trip/hold/reset and any pulse beyond selected-device envelopes;
- actual treadmill +8 V range, source impedance, noise, surge repetition, and
  startup capacity;
- TPS54202 loop margin, switch-node ripple, EMI, pulse skipping, and physical
  or vendor-model startup;
- K1 contact operate/release/bounce and contact-measured fault-to-NC timing;
- ESP32 native-USB attach policy, USB enumeration and eye margin;
- dead-board silicon leakage and real UART through-path edges;
- BC817 switching dynamics and a guaranteed combined-temperature saturation
  model;
- RF behavior and all physical enclosure effects;
- R33 undervoltage hysteresis (`tread_permission` UV corners are divider-only);
- measured Q3 pickup and release timing, and real-pin generation of the
  `RELAY_PULSE` toggle.
- RJ45 single-open 2.0 A capability, minimum treadmill VIN, treadmill source
  impedance, installed ambient/thermal behavior, transient response, complete
  installed supply-plus-return drop, and USB return current;
- harness ESD, RF, and switching-loop behavior.

In particular, coil-current decay is not evidence of relay contact motion,
and the zero VBUS-to-dead-domain result follows from the isolated-gate model.
Programming and native-USB attach remain firmware/bench gates.
