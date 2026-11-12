"""The placement file must be in the coordinates and angles JLC expects."""

from __future__ import annotations

import csv
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import design  # noqa: E402


def _cpl() -> dict[str, dict[str, str]]:
    with (ROOT / "bom" / "CPL-positions.csv").open(newline="", encoding="utf-8") as handle:
        return {row["Designator"]: row for row in csv.DictReader(handle)}


def _gerber_outline() -> tuple[float, float, float, float]:
    with zipfile.ZipFile(ROOT / "kicad" / "Esp32Tap-gerbers.zip") as archive:
        name = next(n for n in archive.namelist() if "Edge_Cuts" in n)
        text = archive.read(name).decode("ascii")
    assert "%FSLAX46Y46*%" in text and "%MOMM*%" in text
    points = [(int(x) / 1e6, int(y) / 1e6) for x, y in re.findall(r"X(-?\d+)Y(-?\d+)D0[12]\*", text)]
    xs, ys = [p[0] for p in points], [p[1] for p in points]
    return min(xs), max(xs), min(ys), max(ys)


def test_every_placement_lies_inside_the_gerber_outline() -> None:
    # JLC overlays the placement file on the Gerbers. A file measured from
    # the board corner put every part outside the outline and made JLC's tool
    # report "component may be offset from the PCB".
    min_x, max_x, min_y, max_y = _gerber_outline()
    # J3's body centre sits just outside the edge; everything else is inside.
    slack = 3.0
    for reference, row in _cpl().items():
        x = float(row["Mid X"].removesuffix("mm"))
        y = float(row["Mid Y"].removesuffix("mm"))
        assert min_x - slack <= x <= max_x + slack, reference
        assert min_y - slack <= y <= max_y + slack, reference


def test_placement_maps_kicad_to_gerber_coordinates_and_adds_the_part_offset() -> None:
    assert design.jlc_cpl_placement("no-such-part", 143.5, 149.5, 90.0) == (143.5, -149.5, 90.0)
    assert design.jlc_cpl_placement("C47190", 130.2, 123.0, 0.0) == (130.2, -123.0, 270.0)
    assert design.jlc_cpl_placement("C8545", 1.0, 2.0, 270.0) == (1.0, -2.0, 90.0)


def test_rotation_offsets_name_parts_the_design_uses() -> None:
    used = {component[3] for component in design.COMPONENTS.values()}
    assert set(design.JLC_ROTATION_OFFSET_DEG) <= used
    assert set(design.JLC_ROTATION_OFFSET_DEG.values()) <= {90, 180, 270}
