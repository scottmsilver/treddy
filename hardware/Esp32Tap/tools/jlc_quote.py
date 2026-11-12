#!/usr/bin/env python3
"""Get a JLCPCB board-plus-assembly quote for Rev E without ordering anything.

Drives JLC's own quote pages in a browser, because JLC has no public quote
API for assembly: upload the Gerber archive, pick the board options, turn on
Standard assembly, upload the BOM and placement file, select any part JLC did
not match by its LCSC number, capture the placement preview, and read the
price. By default it stops on the last page and saves nothing: `guarded_click`
refuses any control whose text looks like cart, order or pay, and the
"SAVE TO CART" button is disabled in the page as soon as it appears.

`quote --save-to-cart --max-total USD` goes one step further and saves the
order to the account's cart, for the account owner to review and pay for. It
does so only if JLC raised no warning, every part is confirmed, the total is
at or under the limit given, and `jlc_rotation_check.py` passes on the preview
just captured. It never opens the cart's checkout, orders or pays.

Runs under a Python that has `camoufox` installed (not the system Python).
The session lives in a browser profile directory, so you sign in once:

    python tools/jlc_quote.py login            # opens a window; sign in yourself
    python tools/jlc_quote.py quote --out DIR  # headless from then on

`quote` writes DIR/quote.json (charges, matched parts, warnings), DIR/quote.png
and DIR/tile*.png + tile*.json, which `jlc_rotation_check.py` turns into a
per-part pin-1 verdict. Exit status is non-zero if JLC left a part unmatched,
warned that placements are offset from the board, or charged for hand
soldering.

This tool handles no password. If the saved session has expired it says so
and stops; run `login` again.
"""

from __future__ import annotations

import argparse
import asyncio
import csv
import json
import math
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JLC_QUOTE_URL = os.environ.get("JLC_QUOTE_URL", "https://cart.jlcpcb.com/quote")
PROFILE_DIR = Path(os.environ.get("JLC_PROFILE_DIR", Path.home() / ".cache" / "jlc-quote" / "profile"))

GERBERS = ROOT / "kicad" / "Esp32Tap-gerbers.zip"
BOM = ROOT / "bom" / "BOM.csv"
CPL = ROOT / "bom" / "CPL-positions.csv"

# Board options, by the quote page's own labels. See ORDERING.md for why.
BOARD_OPTIONS = (
    'text="Epoxy Filled & Capped"',
    'button:visible:text-is("ENIG")',
    'button:visible:has-text("0.2mm/(0.3/0.35mm)")',
)

# The customs description JLC requires before an order can be saved, by the
# page's own labels (the first is JLC's spelling).
PRODUCT_DESCRIPTION = ("Reserch\\Education\\DIY\\Entertainment", "DIY - HS Code 902300")
# The page writes the label in mixed case and upper-cases it with a style.
SAVE_TO_CART_LABEL = re.compile(r"^\s*save to cart\s*$", re.IGNORECASE)
# jlc_rotation_check.py needs KiCad's pcbnew, which lives in the system Python.
PCBNEW_PYTHON = os.environ.get("JLC_PCBNEW_PYTHON", "/usr/bin/python3")

FORBIDDEN = re.compile(r"cart|pay|checkout|place\s+order|submit|buy", re.IGNORECASE)

# Placement preview capture: four views that together cover the board, in
# Gerber millimetres (board spans X 100..195, Y -155..-97).
TILE_CENTRES = ((127, -113), (168, -113), (127, -137), (168, -137))
CANVAS_CENTRE = (495, 626)

VIEW_HELPERS = r"""
(() => {
  const c = document.querySelector('canvas');
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const move = (x, y) => {
    c.dispatchEvent(new PointerEvent('pointermove', {clientX: x, clientY: y, bubbles: true, pointerId: 1, pointerType: 'mouse'}));
    c.dispatchEvent(new MouseEvent('mousemove', {clientX: x, clientY: y, bubbles: true}));
  };
  const readout = () => {
    const e = [...document.querySelectorAll('*')].find(e => e.children.length < 3 && /^X:\s*-?[\d.]+mm/.test((e.innerText || '').trim()));
    return e ? e.innerText.match(/X:\s*(-?[\d.]+)mm\s*Y:\s*(-?[\d.]+)mm/) : null;
  };
  // Screen = scale * millimetres + offset, from the viewer's own cursor readout.
  const transform = async () => {
    const pts = [];
    for (const [x, y] of [[100, 300], [800, 900]]) {
      move(x, y); await sleep(250);
      const m = readout(); if (!m) return null;
      pts.push([x, y, +m[1], +m[2]]);
    }
    const sx = (pts[1][0] - pts[0][0]) / (pts[1][2] - pts[0][2]);
    const sy = (pts[1][1] - pts[0][1]) / (pts[1][3] - pts[0][3]);
    return {sx, sy, ox: pts[0][0] - sx * pts[0][2], oy: pts[0][1] - sy * pts[0][3]};
  };
  const wheel = async (x, y, d) => {
    c.dispatchEvent(new WheelEvent('wheel', {deltaY: d, clientX: x, clientY: y, bubbles: true, cancelable: true}));
    await sleep(250);
  };
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  window.__jlcTile = async (mmX, mmY, C) => {
    window.scrollTo(0, 0);
    document.querySelector('i[class*=adapt-window-icon]').click();
    await sleep(1200);
    for (let i = 0; i < 3; i++) await wheel(C[0], C[1], -120);
    // A zoom out about P followed by a zoom in about Q pans by (P - Q) / 2.
    for (let j = 0; j < 12; j++) {
      const t = await transform(); if (!t) return null;
      const d = [C[0] - (t.sx * mmX + t.ox), C[1] - (t.sy * mmY + t.oy)];
      if (Math.hypot(d[0], d[1]) < 6) break;
      await wheel(clamp(C[0] + d[0], 20, 970), clamp(C[1] + d[1], 270, 980), 120);
      await wheel(clamp(C[0] - d[0], 20, 970), clamp(C[1] - d[1], 270, 980), -120);
    }
    const t = await transform();
    move(5, 255);
    return t;
  };
})()
"""


class QuoteError(RuntimeError):
    pass


def bom_lcsc_by_reference() -> dict[str, str]:
    mapping: dict[str, str] = {}
    with BOM.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            for reference in row["Designator"].split(","):
                mapping[reference.strip()] = row["LCSC Part #"].strip()
    return mapping


async def guarded_click(page, selector: str, **kwargs) -> None:
    locator = page.locator(selector).first
    text = (await locator.inner_text(timeout=15000)).strip() if await locator.count() else selector
    if FORBIDDEN.search(text) or FORBIDDEN.search(selector):
        raise QuoteError(f"refusing to click {text!r}: this tool only quotes")
    await locator.click(**kwargs)


async def disable_ordering(page) -> None:
    await page.evaluate("""() => {
        for (const b of document.querySelectorAll('button')) {
            if (/cart|pay|order now/i.test(b.innerText)) { b.disabled = true; b.style.pointerEvents = 'none'; }
        }
    }""")


async def body_text(page) -> str:
    return await page.evaluate("document.body.innerText")


async def require_signed_in(page) -> None:
    if "passport.jlcpcb.com" in page.url:
        raise QuoteError("the saved JLC session has expired: run `jlc_quote.py login` and sign in")
    if "updated our Terms" in await body_text(page):
        raise QuoteError("JLC is asking you to accept updated terms: run `jlc_quote.py login`, accept them, then retry")


async def open_browser(headed: bool):
    from camoufox.async_api import AsyncCamoufox

    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    PROFILE_DIR.chmod(0o700)
    return AsyncCamoufox(
        headless=False if headed else "virtual",
        os="linux",
        persistent_context=True,
        user_data_dir=str(PROFILE_DIR),
        viewport={"width": 1400, "height": 1000},
    )


async def login() -> int:
    async with await open_browser(headed=True) as context:
        page = context.pages[0] if context.pages else await context.new_page()
        await page.goto("https://jlcpcb.com/user-center/", wait_until="domcontentloaded")
        print("Sign in in the browser window. This command exits once you are signed in.")
        await page.wait_for_url(lambda url: "passport.jlcpcb.com" not in url, timeout=600_000)
        await page.wait_for_timeout(3000)
        print("Signed in; session saved in", PROFILE_DIR)
    return 0


async def select_unmatched_parts(page, lcsc_by_reference: dict[str, str]) -> list[dict[str, str]]:
    """JLC leaves some rows 'No Part Selected' even with an LCSC number. Pick exactly that number."""
    from playwright.async_api import TimeoutError as PlaywrightTimeout

    chosen = []
    unmatched = page.locator('tr:has-text("No Part Selected")')
    for _ in range(40):
        if await unmatched.count() == 0:
            return chosen
        row = unmatched.first
        reference = (await row.locator("td").first.inner_text()).strip().split(",")[0].strip()
        lcsc = lcsc_by_reference.get(reference)
        if not lcsc:
            raise QuoteError(f"JLC did not match {reference} and the BOM has no LCSC number for it")
        await row.get_by_text("Search", exact=True).first.click()
        dialog = page.locator(".el-dialog:visible")
        search = dialog.locator('input[placeholder="Search within results"]')
        # The dialog first runs its own search on the BOM comment, and its
        # result (usually empty) replaces whatever a query typed meanwhile
        # returned. There is no signal for when that first search is done, and
        # a reused dialog still shows the previous part's results, so ask
        # again until the row for this exact part is listed. Searching is
        # idempotent; selecting happens once, below, after the row is checked.
        result = dialog.locator(f'tr:has-text("{lcsc}")').last
        for _ in range(10):
            await search.fill(lcsc)
            await search.press("Enter")
            try:
                await result.wait_for(timeout=4000)
                break
            except PlaywrightTimeout:
                continue
        else:
            raise QuoteError(f"{reference}: JLC's part search never listed {lcsc}")
        result_text = " ".join((await result.inner_text()).split())
        if not re.search(rf"\b{re.escape(lcsc)}\b", result_text):
            raise QuoteError(f"{reference}: search for {lcsc} returned {result_text[:120]!r}")
        await result.get_by_text("Select", exact=True).click()
        await dialog.wait_for(state="hidden", timeout=30000)
        # The table redraws a moment after the dialog closes; wait for this
        # row to stop saying it has no part before looking for the next one.
        before = await unmatched.count()
        try:
            await page.wait_for_function(
                "n => [...document.querySelectorAll('tr')].filter(r => r.innerText.includes('No Part Selected')).length < n",
                arg=before, timeout=8000)
        except PlaywrightTimeout:
            continue  # the selection did not take; the loop tries this row again
        chosen.append({"reference": reference, "lcsc": lcsc, "jlc_row": result_text[:300]})
    raise QuoteError("parts are still unmatched after 40 attempts")


async def scrape_parts(page) -> list[list[str]]:
    return await page.evaluate("""() => [...document.querySelectorAll('tr')]
        .map(r => [...r.querySelectorAll('td')].map(c => c.innerText.trim().replace(/\\s+/g, ' ')))
        .filter(r => r.length > 5)""")


def parse_charges(text: str) -> dict[str, float]:
    """'Label: | $1.23' pairs between 'Charge Details' and the order button."""
    start = text.find("Charge Details")
    end = text.find("SAVE TO CART", start)
    lines = [line.strip() for line in text[start:end].splitlines() if line.strip()]
    charges: dict[str, float] = {}
    for label, value in zip(lines, lines[1:]):
        match = re.fullmatch(r"\$([\d,]+\.\d\d)", value)
        if match and not label.startswith("$"):
            charges[label.rstrip(": ")] = float(match.group(1).replace(",", ""))
    return charges


def charge_problems(charges: dict[str, float]) -> list[str]:
    problems = [
        f"JLC charges {label}: ${value:.2f}"
        for label, value in charges.items()
        if re.search(r"hand|manual", label, re.IGNORECASE) and value > 0
    ]
    if "Total Price" not in charges:
        problems.append("no total price was found on the quote page")
    return problems


def charge_warnings(result: dict) -> None:
    result["warnings"].extend(charge_problems(result.get("charges", {})))


def cart_refusal(result: dict, max_total: float, rotation_status: int) -> str | None:
    """Why this quote must not be saved to the cart, or None if it may be."""
    # Judged from the charges as they are now, not from warnings recorded
    # earlier: the price is read again just before saving.
    warnings = list(dict.fromkeys(result["warnings"] + charge_problems(result.get("charges", {}))))
    if warnings:
        return "JLC raised warnings: " + "; ".join(warnings)
    if not math.isfinite(max_total):
        return f"the limit {max_total} is not a number"
    confirmed, detected = result.get("parts_confirmed"), result.get("parts_detected")
    if not detected or confirmed != detected:
        return f"parts confirmed {confirmed} of {detected}"
    total = result["charges"]["Total Price"]
    if total > max_total:
        return f"total ${total:.2f} is over the limit ${max_total:.2f}"
    if rotation_status != 0:
        return "jlc_rotation_check.py did not pass on the captured preview"
    return None


async def save_to_cart(page, out: Path, result: dict, max_total: float) -> None:
    rotation = subprocess.run(
        [PCBNEW_PYTHON, str(ROOT / "tools" / "jlc_rotation_check.py"), str(out)],
        capture_output=True, text=True, check=False)
    (out / "rotation_check.txt").write_text(rotation.stdout, encoding="utf-8")
    refusal = cart_refusal(result, max_total, rotation.returncode)
    if refusal:
        raise QuoteError("not saving to the cart: " + refusal)

    category, item = PRODUCT_DESCRIPTION
    await page.locator('input[placeholder="Select"]:visible').first.click()
    await page.locator(".el-cascader-node:visible", has_text=category).first.click()
    await page.locator(".el-cascader-node:visible", has_text=item).first.click()
    await page.wait_for_timeout(1500)
    result["product_description"] = list(PRODUCT_DESCRIPTION)
    # The price can change between reading it and saving; read it again.
    result["charges"] = parse_charges(await body_text(page))
    refusal = cart_refusal(result, max_total, 0)
    if refusal:
        raise QuoteError("not saving to the cart: " + refusal)
    await page.screenshot(path=str(out / "before_save.png"), full_page=True)

    # The one deliberate click on an ordering control in this tool.
    button = page.locator("button:visible", has_text=SAVE_TO_CART_LABEL)
    if await button.count() != 1:
        raise QuoteError(f"expected one SAVE TO CART button, found {await button.count()}")
    await button.click()
    await page.wait_for_timeout(15000)
    result["after_save_url"] = page.url
    await page.screenshot(path=str(out / "after_save.png"), full_page=True)
    (out / "after_save.txt").write_text(page.url + "\n\n" + await body_text(page), encoding="utf-8")
    result["saved_to_cart"] = True


async def quote(out: Path, quantity: int, headed: bool, cpl: Path = CPL, max_total: float | None = None) -> int:
    out.mkdir(parents=True, exist_ok=True)
    for path in (GERBERS, BOM, cpl):
        if not path.is_file():
            raise QuoteError(f"missing {path}")
    result: dict = {"quantity": quantity, "warnings": []}
    async with await open_browser(headed) as context:
        page = context.pages[0] if context.pages else await context.new_page()
        page.set_default_timeout(45000)
        try:
            await run_quote_flow(page, out, quantity, result, cpl, keep_ordering=max_total is not None)
            if max_total is not None:
                await save_to_cart(page, out, result, max_total)
        except Exception:
            # What the page looked like is the only useful evidence of a
            # selector or flow change on JLC's side.
            await page.screenshot(path=str(out / "failure.png"), full_page=True)
            (out / "failure.txt").write_text(page.url + "\n\n" + await body_text(page), encoding="utf-8")
            raise
    return report(out, result)


async def run_quote_flow(page, out: Path, quantity: int, result: dict, cpl: Path, keep_ordering: bool = False) -> None:
    if True:
        # 1. Bare board.
        await page.goto(JLC_QUOTE_URL, wait_until="load")
        # The upload control ignores a file set before the page script has
        # attached to it, so wait until the page is idle first.
        await page.wait_for_load_state("networkidle")
        await page.wait_for_function("document.body.innerText.includes('Add gerber file')")
        await page.set_input_files("input[type=file]", str(GERBERS))
        await page.wait_for_function("document.body.innerText.includes('Re-Upload')", timeout=120_000)
        await page.wait_for_timeout(4000)
        for option in BOARD_OPTIONS:
            await guarded_click(page, option)
            await page.wait_for_timeout(2500)

        # 2. Standard assembly, top side. The page defaults to quantity 5.
        await guarded_click(page, "div.switch-box")
        await guarded_click(page, 'button:visible:text-is("Standard")')
        await page.wait_for_function("document.body.innerText.includes('Standard PCBA Price')")
        if quantity != 5:
            raise QuoteError("only the page's default quantity of 5 is implemented")
        await guarded_click(page, 'button:visible:has-text("NEXT")')
        await page.wait_for_url(re.compile(r"smt-order|passport"), timeout=60000)
        await page.wait_for_timeout(4000)
        await require_signed_in(page)
        result["order_url"] = page.url

        # 3. BOM and placement file. NEXT does nothing until the page has
        # finished loading the saved board, so wait for it to go idle.
        await page.wait_for_load_state("networkidle")
        await guarded_click(page, 'button:visible:has-text("NEXT")')
        await page.wait_for_function("document.querySelectorAll('input[type=file]').length >= 2")
        uploads = page.locator("input[type=file]")
        await uploads.nth(0).set_input_files(str(BOM))
        await uploads.nth(1).set_input_files(str(cpl))
        await page.wait_for_timeout(3000)
        await guarded_click(page, 'button:visible:has-text("Process BOM")')
        await page.wait_for_function("document.body.innerText.includes('parts detected')", timeout=120_000)
        await page.wait_for_timeout(2000)
        result["selected_by_lcsc"] = await select_unmatched_parts(page, bom_lcsc_by_reference())
        result["parts"] = await scrape_parts(page)
        summary = re.search(r"Total\s+(\d+)\s+parts detected\s+(\d+)\s+Parts confirmed", " ".join((await body_text(page)).split()))
        if summary:
            result["parts_detected"], result["parts_confirmed"] = int(summary.group(1)), int(summary.group(2))
            if summary.group(1) != summary.group(2):
                result["warnings"].append("JLC did not confirm every part")

        # 4. Placement preview.
        await guarded_click(page, 'button:visible:has-text("NEXT")')
        await page.wait_for_selector("canvas", timeout=120_000)
        await page.wait_for_timeout(12000)
        if "offset from the PCB" in await body_text(page):
            result["warnings"].append("JLC reports placements offset from the PCB: the placement file is not in Gerber coordinates")
            await page.locator('text="Cancel" >> visible=true').first.click()
        await page.locator('text="2D" >> visible=true').first.click()
        await page.wait_for_timeout(5000)
        await page.evaluate(VIEW_HELPERS)
        for index, (mm_x, mm_y) in enumerate(TILE_CENTRES):
            transform = await page.evaluate("([x, y, c]) => window.__jlcTile(x, y, c)", [mm_x, mm_y, list(CANVAS_CENTRE)])
            if not transform:
                raise QuoteError("the placement viewer did not report cursor coordinates")
            await page.wait_for_timeout(1500)
            await page.screenshot(path=str(out / f"tile{index}.png"))
            (out / f"tile{index}.json").write_text(json.dumps(transform))
        await page.evaluate("document.querySelector('i[class*=adapt-window-icon]').click()")

        # 5. Price. Read it and stop.
        await guarded_click(page, 'button:visible:has-text("NEXT")')
        await page.wait_for_function("document.body.innerText.includes('Total Price')", timeout=120_000)
        await page.wait_for_timeout(3000)
        if not keep_ordering:
            await disable_ordering(page)
        text = await body_text(page)
        result["charges"] = parse_charges(text)
        await page.screenshot(path=str(out / "quote.png"), full_page=True)


def report(out: Path, result: dict) -> int:
    charge_warnings(result)
    (out / "quote.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    for label, value in result["charges"].items():
        print(f"{label:38} ${value:9.2f}")
    print(f"parts confirmed: {result.get('parts_confirmed')}/{result.get('parts_detected')}; "
          f"selected by LCSC number: {[p['reference'] for p in result['selected_by_lcsc']]}")
    for warning in result["warnings"]:
        print("WARNING:", warning)
    if result.get("saved_to_cart"):
        print("Saved to the JLC cart. Nothing was ordered or paid for: review the cart and check out yourself.")
    else:
        print("Nothing was added to the cart. Now run tools/jlc_rotation_check.py", out)
    return 1 if result["warnings"] else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("login", help="open a window and sign in yourself; the session is saved")
    quote_parser = commands.add_parser("quote", help="run the whole quote flow and stop before the cart")
    quote_parser.add_argument("--out", type=Path, required=True, help="directory for quote.json and captures")
    quote_parser.add_argument("--quantity", type=int, default=5)
    quote_parser.add_argument("--headed", action="store_true", help="show the browser window")
    quote_parser.add_argument("--cpl", type=Path, default=CPL, help="placement file to upload instead of bom/CPL-positions.csv")
    quote_parser.add_argument("--save-to-cart", action="store_true",
                              help="after a clean quote, save the order to the cart (never checks out or pays)")
    quote_parser.add_argument("--max-total", type=float,
                              help="with --save-to-cart: refuse if the total in USD is above this")
    args = parser.parse_args(argv)
    if args.command == "quote":
        if args.save_to_cart != (args.max_total is not None):
            parser.error("--save-to-cart and --max-total go together")
        if args.max_total is not None and not math.isfinite(args.max_total):
            parser.error("--max-total must be a number")
        if args.save_to_cart and args.cpl != CPL:
            parser.error("--save-to-cart only uses the repository's own placement file")
    try:
        if args.command == "login":
            return asyncio.run(login())
        return asyncio.run(quote(args.out, args.quantity, args.headed, args.cpl, args.max_total))
    except QuoteError as error:
        print(f"jlc_quote: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
