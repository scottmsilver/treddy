"""The rotation checker must not report a pass it has not earned."""

from __future__ import annotations

import importlib.util
from pathlib import Path

TOOL = Path(__file__).resolve().parents[1] / "tools" / "jlc_rotation_check.py"
spec = importlib.util.spec_from_file_location("jlc_rotation_check", TOOL)
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


def _diode(x: float, y: float = 0.0) -> dict:
    return {"centre": (x, y), "pads": {"1": [(x + 2.0, y)], "2": [(x - 2.0, y)]}, "box": (x - 3.0, y - 1.5, x + 3.0, y + 1.5)}


def _sot23(x: float, y: float = 0.0) -> dict:
    pads = {"1": [(x - 0.94, y - 0.95)], "2": [(x - 0.94, y + 0.95)], "3": [(x + 0.94, y)]}
    return {"centre": (x, y), "pads": pads, "box": (x - 1.6, y - 1.5, x + 1.6, y + 1.5)}


def _mark(x: float, y: float, kind: str) -> dict:
    return {"x": x, "y": y, "kind": kind}


def test_mark_at_pad_1_is_ok_and_at_another_pad_is_wrong() -> None:
    parts = {"D1": _diode(0.0), "Q1": _sot23(20.0)}
    good = check.verdicts(parts, [_mark(2.1, 0.0, "minus"), _mark(18.5, -0.95, "dot")], ["D1", "Q1"])
    assert good["D1"][0] == "OK" and good["Q1"][0] == "OK"
    bad = check.verdicts(parts, [_mark(-2.1, 0.0, "minus"), _mark(21.5, 0.95, "dot")], ["D1", "Q1"])
    assert bad["D1"][0] == "WRONG" and bad["Q1"][0] == "WRONG"
    assert "add 180" in bad["Q1"][1]


def test_quarter_turned_diode_is_wrong_not_ok() -> None:
    # The cathode mark of a diode turned 90 degrees sits midway between pads.
    result = check.verdicts({"D1": _diode(0.0)}, [_mark(0.0, -2.0, "minus")], ["D1"])
    assert result["D1"][0] == "WRONG"
    assert "add 270" in result["D1"][1] or "add 90" in result["D1"][1]


def test_a_mark_between_two_orientations_is_ambiguous() -> None:
    result = check.verdicts({"D1": _diode(0.0)}, [_mark(1.5, -1.5, "minus")], ["D1"])
    assert result["D1"][0] == "AMBIGUOUS"


def test_a_neighbours_mark_cannot_vouch_for_a_part() -> None:
    # Q2 is reversed and JLC's dot for it was not detected. Q1's own dot is
    # close to Q2's pad 1, and must still count only for Q1.
    parts = {"Q1": _sot23(0.0), "Q2": _sot23(3.3)}
    result = check.verdicts(parts, [_mark(1.55, -0.95, "dot")], ["Q1", "Q2"])
    assert result["Q2"][0] == "UNCHECKED"


def test_a_capture_with_no_marks_fails(monkeypatch, capsys) -> None:
    parts = {reference: _sot23(10.0 * index) for index, reference in enumerate(sorted(check.EXPECTED_MARKED))}
    monkeypatch.setattr(check, "board_pads", lambda: parts)
    monkeypatch.setattr(check, "marks", lambda directory: [])

    class Design:
        COMPONENTS = {reference: ("v", "lib", "fp", "C1", "Basic") for reference in parts}
        DNP: set[str] = set()

    monkeypatch.setitem(__import__("sys").modules, "design", Design)
    assert check.check(Path("unused")) == 1
    assert "MISSING" in capsys.readouterr().out
