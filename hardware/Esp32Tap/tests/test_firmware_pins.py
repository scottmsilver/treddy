"""The Rust firmware's pin table must agree with the board.

``firmware/esp32_rs/esp32tap/src/pins.rs`` says it is checked against
``design.py``, but the only pin checker the firmware build runs reads the
legacy C++ ``pins.hpp``. This test is the check for the Rust table: every
``K_<NET>`` constant must name a net with exactly one U1 pad, carry that pad's
GPIO number, and have the right direction in ``design.PIN_TYPES``.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import design  # noqa: E402

PINS_RS = ROOT / "firmware" / "esp32_rs" / "esp32tap" / "src" / "pins.rs"
OUTPUT_NETS = {"RELAY_CMD", "RELAY_PULSE", "TX_ENABLE", "ESP_TX", "STATUS_LED"}
INPUT_NETS = {"TREAD_OK_MCU", "K1_NC_FB", "K1_NO_FB", "VBUS_PRESENT_N", "CONS_RX", "PIN3_RX"}


def rust_pins() -> dict[str, int]:
    text = PINS_RS.read_text(encoding="utf-8")
    return {name: int(value) for name, value in re.findall(r"pub const K_(\w+): u32 = (\d+);", text)}


def board_gpio(net: str) -> tuple[str, int]:
    pads = [pad for ref, pad in design.NETS[net] if ref == "U1"]
    assert len(pads) == 1, f"net {net} has {len(pads)} U1 pads"
    match = re.search(r"IO(\d+)", design.COMPONENTS["U1"][7][pads[0]])
    assert match, f"U1 pad {pads[0]} is not a GPIO"
    return pads[0], int(match.group(1))


def test_every_rust_pin_constant_matches_the_board() -> None:
    pins = rust_pins()
    assert set(pins) == OUTPUT_NETS | INPUT_NETS
    for net, gpio in pins.items():
        pad, expected = board_gpio(net)
        assert gpio == expected, f"K_{net} = {gpio}, but the board routes {net} to U1 pad {pad} = GPIO{expected}"
        direction = design.PIN_TYPES[("U1", pad)]
        assert direction == ("output" if net in OUTPUT_NETS else "input"), f"{net}: U1 pad {pad} is {direction}"


def test_relay_pulse_is_gpio8_and_reaches_only_the_pump_resistor() -> None:
    assert rust_pins()["RELAY_PULSE"] == 8
    assert sorted(design.NETS["RELAY_PULSE"]) == [("R35", "1"), ("U1", "12")]


def test_no_safety_output_is_a_strapping_pin() -> None:
    strapping = {0, 3, 45, 46}
    for net in OUTPUT_NETS:
        assert rust_pins()[net] not in strapping, f"{net} is on a strapping pin"
