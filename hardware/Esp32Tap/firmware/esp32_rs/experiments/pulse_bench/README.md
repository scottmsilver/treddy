# pulse_bench

Bench firmware for the "IO8 Pulse Bench Rig": a bare ESP32-S3 dev board plus
the Rev E relay-liveness charge pump on a breadboard (R35 560 ohm, C22 100 nF,
two Schottky diodes, C23 1 uF, R34 100 kohm). It is not the product firmware.

It measures what an emulator cannot:

- the longest gap between RELAY_PULSE edges with Wi-Fi running,
- how long a 4 KB flash sector erase holds off the pulse timer and the 5 ms
  loop (ESP-IDF suspends other tasks during a flash operation),
- the gate-node voltage at the end of each such stall, read on GPIO4,
- the steady gate voltage and the time to charge from cold.

Wiring: GPIO8 to the pump input, GPIO4 to the gate node, 3V3 and GND.

## Build and flash

```bash
# build (pinned IDF image, same as experiments/wdt_qemu_control)
docker run --rm -v "$PWD":/project -w /project -u $(id -u):$(id -g) -e HOME=/tmp \
  espressif/idf:release-v5.5 idf.py build

# flash and watch, with the board on PORT (for example /dev/ttyACM0)
docker run --rm -it --device=PORT -v "$PWD":/project -w /project \
  espressif/idf:release-v5.5 idf.py -p PORT flash monitor
```

Every line it prints starts with `BENCH`. After a start-up block it prints one
line every 5 s:

```
BENCH t=5s gate_mv now=.. min5s=.. min=.. | tick_gap_us max5s=.. max=.. late=..
  | loop_gap_us max5s=.. max=.. | erase n=.. last_ms=.. max_ms=..
  | stall last_ms=.. max_ms=.. gate_after_mv last=.. min=..
```

`stall` is the longest time the 5 ms loop was held off, and `gate_after_mv` is
the gate voltage read the moment it ran again, which is the lowest point of
that stall. Compare with the simulation in `sim/decks/liveness_firmware_trace.cir`
(2.63 V steady; 1.74 V after a 45 ms stall; 1.06 V after 100 ms).

## Limits

- The flash chip on a dev board may not be the one in the module JLC fits, and
  erase time is a property of the chip. Note the module marking.
- Wi-Fi runs as an idle access point and Bluetooth is off, so the radio load is
  lighter than the product's.
- The pulse permission here is a C port of `safety_core::liveness::PulseBudget`.
  The Rust original is what ships and what is tested.
- Breadboard diodes and capacitors are not the board's parts, so absolute gate
  voltages will differ by a few hundred millivolts. Stall durations will not.
- This build has never run on hardware. It compiles; treat its first output as
  a check of the rig as much as of the board.
