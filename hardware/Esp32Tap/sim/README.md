# Esp32Tap Rev E behavioral simulations

These nine ngspice decks are behavioral regression evidence for the Rev E
circuits. Eight model Rev E parts. The ninth, `harness_supply_drop`, models a
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
| `liveness_firmware_trace` | The pin waveform comes from the firmware's real pulse-permission code, not an ideal source. Entry: the firmware waits 30.1 ms before commanding K1, by when the gate is at 2.51 V (worst Q3 threshold 1.45 V); coil pickup current 2.5 ms after the command. Safety loop hung while the timer keeps running: coil released 80 ms (1.45 V threshold) to 161 ms (0.65 V) after the last loop pass. Permission withdrawn: 60 to 141 ms. Timer held off 9 ms in every 100 ms: gate never below 2.42 V, coil holds. One tick every 10 ms, which the firmware still counts as unbroken: gate peaks at 1.10 V, below the worst threshold |
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
  V gate-threshold range. Gate charge, capacitor tolerance, and leakage are
  not modeled.

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
