#!/usr/bin/env python3
"""Check part rotations against JLCPCB's own placement preview.

`jlc_quote.py quote --out DIR` captures the preview as four calibrated views.
JLC draws a magenta dot beside pin 1 of each part model, and a magenta minus
and plus on diodes and LEDs. This reads those marks, converts them to board
millimetres, and compares them with the KiCad board:

- a part with three or more pads: JLC's dot must be nearest to pad 1;
- a two-pad part that JLC marks with a minus: the minus must be at pad 1
  (the cathode in KiCad's diode and LED footprints).

Exit status is non-zero if any part is wrong or ambiguous, or if a part JLC
is known to mark comes back with no mark. Parts JLC draws no mark for
(resistors, capacitors, switches, the USB-C connector, and the LEDs, whose
marks are too small to read) are listed as not checked. Needs the system Python (pcbnew) with Pillow and numpy.

    python3 tools/jlc_rotation_check.py DIR
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

MAGENTA_MIN_PIXELS = 25
CANVAS_TOP_PX = 258  # the page header and toolbar sit above the preview
DUPLICATE_MM = 0.35  # the same mark seen in two overlapping views


def board_pads() -> dict[str, dict]:
    import pcbnew

    board = pcbnew.LoadBoard(str(ROOT / "kicad" / "Esp32Tap.kicad_pcb"))
    parts = {}
    for footprint in board.GetFootprints():
        centre = footprint.GetPosition()
        pads: dict[str, list[tuple[float, float]]] = {}
        for pad in footprint.Pads():
            position = pad.GetPosition()
            pads.setdefault(pad.GetNumber(), []).append((pcbnew.ToMM(position.x), pcbnew.ToMM(position.y)))
        # The courtyard is the part's outline; the general bounding box also
        # takes in silkscreen text and overlaps the neighbours.
        box = footprint.GetCourtyard(pcbnew.F_CrtYd).BBox()
        if box.GetWidth() <= 0:
            box = footprint.GetBoundingBox(False)
        parts[footprint.GetReference()] = {
            "centre": (pcbnew.ToMM(centre.x), pcbnew.ToMM(centre.y)),
            "pads": pads,
            "box": (pcbnew.ToMM(box.GetLeft()), pcbnew.ToMM(box.GetTop()), pcbnew.ToMM(box.GetRight()), pcbnew.ToMM(box.GetBottom())),
        }
    return parts


def blobs(mask) -> list[list[tuple[int, int]]]:
    """Connected groups of set pixels (8-connected)."""
    import numpy as np

    seen = np.zeros(mask.shape, dtype=bool)
    groups = []
    for y, x in zip(*np.nonzero(mask)):
        if seen[y, x]:
            continue
        stack, group = [(int(y), int(x))], []
        seen[y, x] = True
        while stack:
            cy, cx = stack.pop()
            group.append((cy, cx))
            for ny in (cy - 1, cy, cy + 1):
                for nx in (cx - 1, cx, cx + 1):
                    if 0 <= ny < mask.shape[0] and 0 <= nx < mask.shape[1] and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
        groups.append(group)
    return groups


def marks(directory: Path) -> list[dict]:
    """Magenta marks in KiCad millimetres, each classed as dot, minus or plus."""
    import numpy as np
    from PIL import Image

    found: list[dict] = []
    tiles = sorted(directory.glob("tile*.png"))
    if not tiles:
        raise SystemExit(f"no tile*.png in {directory}: run jlc_quote.py quote first")
    for tile in tiles:
        transform = json.loads(tile.with_suffix(".json").read_text())
        image = np.array(Image.open(tile).convert("RGB")).astype(int)
        mask = (image[:, :, 0] > 230) & (image[:, :, 1] < 40) & (image[:, :, 2] > 230)
        mask[:CANVAS_TOP_PX, :] = False
        mask[:, 985:] = False
        for group in blobs(mask):
            if len(group) < MAGENTA_MIN_PIXELS:
                continue
            ys = [p[0] for p in group]
            xs = [p[1] for p in group]
            if min(xs) < 3 or max(xs) > 980 or min(ys) < CANVAS_TOP_PX + 2 or max(ys) > image.shape[0] - 4:
                continue  # cut off by the edge of the view
            width, height = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
            fill = len(group) / (width * height)
            aspect = max(width, height) / min(width, height)
            kind = "minus" if aspect >= 2 else ("plus" if fill < 0.6 else "dot")
            x_mm = (sum(xs) / len(xs) - transform["ox"]) / transform["sx"]
            y_mm = -((sum(ys) / len(ys) - transform["oy"]) / transform["sy"])  # KiCad y points down
            if not any(math.hypot(x_mm - m["x"], y_mm - m["y"]) < DUPLICATE_MM for m in found):
                found.append({"x": x_mm, "y": y_mm, "kind": kind})
    return found


# Parts JLC drew a pin-1 or cathode mark for on 2026-11-12. If any of these
# comes back unchecked the capture or the mark detection has broken, and that
# must not read as a pass.
EXPECTED_MARKED = frozenset(
    "D1 D3 D8 J1 J2 K1 Q1 Q2 Q3 U1 U2 U3 U4 U5 U6 U7".split()
)
# JLC puts its mark beside pin 1, so seen from the part's centre it lies in
# the same direction as pad 1. More than this far off and the model is turned.
# A quarter-turned diode is 90 degrees off; a reversed one, 180.
ANGLE_TOLERANCE_DEG = 40.0


def _box_distance(mark: dict, box: tuple[float, float, float, float]) -> float:
    left, top, right, bottom = box
    dx = max(left - mark["x"], 0.0, mark["x"] - right)
    dy = max(top - mark["y"], 0.0, mark["y"] - bottom)
    return math.hypot(dx, dy)


def verdicts(parts: dict[str, dict], all_marks: list[dict], populated: list[str]) -> dict[str, tuple[str, str]]:
    """reference -> (OK | WRONG | AMBIGUOUS | UNCHECKED, detail)."""
    # Each mark belongs to exactly one part: the one whose outline it is in or
    # nearest to. Without this a neighbour's mark can vouch for a reversed part.
    owned: dict[str, list[dict]] = {reference: [] for reference in populated}
    for mark in all_marks:
        # A mark inside two outlines (a small part under a module's keep-out)
        # belongs to the smaller one.
        def claim(reference: str) -> tuple[float, float]:
            left, top, right, bottom = parts[reference]["box"]
            return _box_distance(mark, parts[reference]["box"]), (right - left) * (bottom - top)

        owner = min(populated, key=claim)
        owned[owner].append(mark)

    result: dict[str, tuple[str, str]] = {}
    for reference in populated:
        part = parts[reference]
        pads = [(number, x, y) for number, places in part["pads"].items() if number for x, y in places]
        wanted = "minus" if len({number for number, _, _ in pads}) == 2 else "dot"
        candidates = [mark for mark in owned[reference] if mark["kind"] == wanted]
        if "1" not in part["pads"] or len(pads) < 2 or not candidates:
            result[reference] = ("UNCHECKED", "no JLC mark")
            continue

        cx, cy = part["centre"]
        p1x, p1y = part["pads"]["1"][0]
        want = math.degrees(math.atan2(-(p1y - cy), p1x - cx))

        def off_by(mark: dict) -> float:
            have = math.degrees(math.atan2(-(mark["y"] - cy), mark["x"] - cx))
            return (want - have + 180.0) % 360.0 - 180.0

        mark = min(candidates, key=lambda candidate: abs(off_by(candidate)))
        error = off_by(mark)
        turn = round(error / 90.0) * 90 % 360
        if abs(error) <= ANGLE_TOLERANCE_DEG:
            result[reference] = ("OK", f"JLC {wanted} in the direction of pad 1 ({error:+.0f} deg)")
        elif turn == 0 or abs(error - round(error / 90.0) * 90) > ANGLE_TOLERANCE_DEG:
            result[reference] = ("AMBIGUOUS", f"JLC {wanted} is {error:+.0f} deg from pad 1")
        else:
            result[reference] = ("WRONG", f"JLC {wanted} is {error:+.0f} deg from pad 1; add {turn} to the part's JLC_ROTATION_OFFSET_DEG")
    return result


def check(directory: Path) -> int:
    import design

    parts = board_pads()
    populated = sorted(
        reference
        for reference, component in design.COMPONENTS.items()
        if reference not in design.DNP and component[4] != "none" and reference in parts
    )
    result = verdicts(parts, marks(directory), populated)
    bad = 0
    for reference in populated:
        state, detail = result[reference]
        if state == "UNCHECKED" and reference in EXPECTED_MARKED:
            state, detail = "MISSING", "JLC drew a mark for this part before; none was found now"
        if state != "UNCHECKED":
            print(f"{reference:5} {state:9} {detail}")
        bad += state not in ("OK", "UNCHECKED")
    unchecked = [reference for reference in populated if result[reference][0] == "UNCHECKED" and reference not in EXPECTED_MARKED]
    print(f"not checked (JLC draws no pin-1 mark): {' '.join(unchecked)}")
    print(f"{'FAIL' if bad else 'PASS'}: {bad} not OK")
    return 1 if bad else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    raise SystemExit(check(Path(sys.argv[1])))
