# Esp32Tap Rev E vendor procedure

**Status: HOLD. Do not submit, add to a production cart, authorize a
substitution, or pay.** This is a future review procedure, not purchase
authorization.

## Exact review inputs

| Vendor input | File |
|---|---|
| PCB fabrication | `kicad/Esp32Tap-gerbers.zip` |
| Assembly BOM | `bom/BOM.csv` |
| Placement | `bom/CPL-positions.csv` |
| Enclosure | Current approved base/lid files only after enclosure review |

Regenerate and run:

```bash
make -C hardware/Esp32Tap clean-check
make -C hardware/Esp32Tap check
python3 hardware/Esp32Tap/tools/check_jlc_stock.py --refresh
git diff --check
```

Record hashes for the current ZIP, BOM, CPL, stock snapshot, and approved
enclosure files. Never mix generations or edit generated CSVs.

## PCB/PCBA preview

Require the preview and quote to show:

- 95.0 × 58.0 mm, four layers, vendor 1.6 mm selection;
- `JLC04161H-7628`, 1 oz outer / 0.5 oz inner, green mask, white legend,
  ENIG, lead-free top-side Standard PCBA;
- controlled impedance for 90 Ω USB on L1/L2, using the generated
  0.2906/0.2000 mm controlled geometry;
- J1 and J2 as the identical Molex 44144-0003 (441440003, LCSC `C585890`)
  right-angle SMD 8P8C RJ45 jack, machine-placed by standard top-side reflow
  with exact package, orientation, and mating-opening direction; both are
  `Extended`-class parts, so confirm live Standard PCBA placement support in
  the quote. Live stock for C585890 is the thinnest of the 46 parts (64 units
  at the 2026-11-12 refresh, 2 needed per board);
- J3 under the same standard reflow. Its four S1 plated mechanical stakes are
  part of the stock footprint (with paste apertures and thermal spokes); do
  not request or quote manual/wave soldering, a through-hole step, or a
  pigtail harness;
- the exact DNP/populated set and no unreviewed substitutions;
- "Confirm production files" enabled and no vendor-added order legend;
- an IPC-6012 Class 2 commitment to at least **20 µm average PTH/via barrel
  copper**, confirmed in the live quote/DFM response;
- confirmation that the generated 1.4/1.0 mm GND vias, plated J3 slots, and
  the U1 antenna keepout are accepted unchanged;
- the three board fiducials FID1-FID3 (1 mm copper, 2 mm mask) at board-local
  (6.0, 2.0), (6.0, 50.0), (69.2, 41.2) recognized, in addition to any rail
  fiducials.

U1 is fully on-board with 3.25/3.30 mm margins (no antenna overhang), so no
antenna carrier is needed. Keep metal and tooling out of the antenna keepout.

## Operator-observed JLC quote tool, 2026-11-12 (not vendor-signed)

Recorded by the operator from the JLC quote tool; not a vendor-signed result
and not a production-file approval. The Gerber archive `a22659b7...` (the
current `kicad/Esp32Tap-gerbers.zip`) parsed as 4-layer, 58 x 95 mm. Options
used: Epoxy Filled & Capped via covering plus Horizontal Electroless Copper
Plating, ENIG, minimum via 0.2 mm (0.3/0.35 mm), Standard PCBA top side, and
Edge Rails/Fiducials Added by JLCPCB (the tool reported 95 x 70 mm with rails).
Bare-board total USD 83.98 for 5: base 8.00, via covering 17.37, via plating
3.39, ENIG 17.40, 0.2 mm via 17.37, 4-wire Kelvin test 16.98, material 3.47.
Nothing was added to a cart. Re-check the price in the tool at the time of
any real order.

The assembly steps were then run signed in, with `bom/BOM.csv` and the
corrected `bom/CPL-positions.csv`:

- JLC confirmed 82 of 82 BOM lines. It left J1, J2 (C585890) and U1
  (C2913198) as "No Part Selected" on every upload even though the BOM names
  them; selecting each by its LCSC number in JLC's part search fixes it. The
  cause on JLC's side is unknown.
- Standard PCBA for 5 boards: USD 186.17 (setup 25.75, stencil 8.27,
  components 76.50, feeder loading for Extended parts 71.30, SMT assembly
  3.84, packaging 0.51). No hand-soldering or manual-assembly charge.
- Total for 5 assembled boards before shipping and tax: **USD 270.15**
  (83.98 board + 186.17 assembly), about USD 54 per board.
- JLC's price for the RJ45 jack at this quantity is USD 1.53 each, not the
  0.35 in `design.py`; the BOM cost column is a catalog estimate, the quote
  is the price.

Two defects in the placement file were found in JLC's preview and fixed at
the source (`design.jlc_cpl_placement`):

- **Coordinates.** The file was measured from the board corner while the
  Gerbers use KiCad's absolute origin, so JLC drew every part off the board
  and offered to "automatically align" them. Placements are now in Gerber
  coordinates (x, -y) and JLC shows no offset warning.
- **Rotations.** JLC's models for 11 parts are turned 90 or 180 degrees from
  KiCad's zero (K1, U2-U7, Q1-Q3, D8). `design.JLC_ROTATION_OFFSET_DEG`
  carries a per-part correction. With it, JLC's pin-1 marker sits on pad 1
  for K1, U1-U7, Q1-Q3, D8, J1 and J2, and JLC's cathode mark is on pad 1 of
  D1 and D3 (checked by `tools/jlc_rotation_check.py`); LED1, LED2 and J3
  were checked by eye in the same preview.

This is JLC's preview, which JLC itself labels "for reference only". It is
not their production DFM result and not a built board.

### Repeating the quote

`tools/jlc_quote.py` drives the same pages unattended and stops at the price.
It cannot save to the cart, order or pay. It needs a Python with `camoufox`
and a signed-in browser profile (`jlc_quote.py login`, once, by hand; the
tool never handles the password).

```bash
<camoufox python> tools/jlc_quote.py quote --out /tmp/jlc   # quote.json, quote.png, tile*.png
python3 tools/jlc_rotation_check.py /tmp/jlc                 # pin-1 verdict per part
```

Run both after any change to the BOM, a part number, a footprint or a
placement, and whenever `JLC_ROTATION_OFFSET_DEG` is touched.

## Order options to select (upload procedure)

Keep HOLD: this is the procedure for a future owner-authorized review, not
authorization to order. Do not pay on the strength of any preview.

1. **Assembly type: Standard PCBA**, top side only, lead-free. In the upload
   step, add `kicad/Esp32Tap-gerbers.zip`, then `bom/BOM.csv` and
   `bom/CPL-positions.csv` from the same generation.
2. **Rails to at least 70 mm.** The board is 95 x 58 mm and JLC Standard
   PCBA needs 70 x 70 mm minimum plus rails and fiducials. Choose JLC-added
   rails (edge rails, per
   <https://jlcpcb.com/help/article/how-to-add-edge-rails-fiducials-for-pcb-assembly-order>)
   wide enough that the 58 mm axis reaches at least 70 mm, or use a 2-up
   panel. Ask that routed tabs avoid the parts near the bottom edge: C2, C7,
   F1, D1, D3 and R5. Those parts were not moved. Require a dimensioned
   drawing of rails, tabs, depanel method, delivered outline, and edge
   dressing. bd `precor-9_3x-idr`.
3. **Via covering: Epoxy Filled & Capped.** 41 via drills still touch pasted
   SMD pads and were not rerouted, so plain tented vias are not acceptable.
   JLC states this option is free only on 6+ layers; eligible holes are
   0.5 mm or smaller. This board is 4 layers, so expect an extra charge and
   read the price only from the quote tool. Do not invent a figure. bd
   `precor-9_3x-ilf`.
4. **Confirm parts placement.** Enable "Confirm Parts Placement" (and
   "Confirm production files") so a JLC engineer shows the placement preview
   before production.
5. **RJ45 pad 1 orientation: verified by eye** against Molex SD-44144-001 rev H9
   sheet 2 (circuit 1 is the leftmost contact land in the component-side layout,
   matching footprint pad 1 at x = -4.45); bd `precor-9_3x-192` closed. This
   is not a vendor result; a built board still has to confirm supply polarity
   and the pin-3/pin-6 taps.
6. **Check every rotation in the preview.** `bom/CPL-positions.csv` carries
   KiCad angles plus the per-part corrections in
   `design.JLC_ROTATION_OFFSET_DEG`, verified against JLC's preview on
   2026-11-12 (see above). Re-run `tools/jlc_rotation_check.py` on a fresh
   quote before ordering, and look at LED1, LED2, J3, SW1 and SW2 yourself:
   JLC draws no machine-readable mark for those. Any mismatch returns to
   `design.py` and regeneration; do not edit the CPL by hand.
7. **Stack and impedance.** Select the 4-layer `JLC04161H-7628` stack with
   controlled impedance for USB; confirm 20 µm Class 2 hole copper.

The operator-observed `vendor/JLC-DFM-REVIEW.json` is bound to an older exact
archive. Preserve it; do not treat it as approval of current bytes.
Upload the current exact ZIP for a new live review, then verify the same BOM,
CPL, and placement preview.

Useful live references:

- <https://jlcpcb.com/capabilities/pcb-capabilities/>
- <https://jlcpcb.com/pcb-impedance-calculator/>
- <https://jlcpcb.com/help/article/multi-layer-pcb-standard-laminated-structures>
- <https://jlcpcb.com/capabilities/pcb-assembly-capabilities>
- <https://jlcpcb.com/help/article/how-to-add-edge-rails-fiducials-for-pcb-assembly-order>
- <https://jlcpcb.com/blog/pcb-pth>
- <https://www.ipc.org/TOC/IPC-6012F-TOC.pdf>

## BOM and placement review

Confirm every populated designator's exact code, model, package, class,
quantity, side, position, and rotation. In particular:

- J1/J2 are the two identical board-mounted RJ45 jacks — there is no
  separate connector family or off-board harness to reconcile, and no
  mechanical keying between them; CONSOLE/MOTOR silkscreen plus housing
  color are the only differentiator;
- K1 is `G6K-2F-Y-TR DC5`;
- U1 is `ESP32-S3-WROOM-1-N8`, fully inside the finished edge;
- C13/C14 and mechanical/test items remain excluded as generated;
- J3's USB opening direction and S1 stake geometry are unchanged.

Any vendor rotation, footprint, or substitution proposal stops the review and
returns to source/regeneration.

## Enclosure quote

Keep enclosure purchasing open until the current 95 × 58 board-derived
geometry, including the J1/J2 RJ45 wall apertures, is approved. Quote
nonconductive material, no scaling/hollowing, critical apertures and posts,
shrink/warp, support removal, screw fit, and installed RF clearance. Local
mesh checks are not vendor acceptance.

## Release conditions

Before purchase, obtain and archive:

1. live current-archive CAM/DFM and stack/impedance acceptance;
2. exact BOM/CPL placement acceptance, including Standard PCBA placement
   confirmation for both RJ45 jacks;
3. 20 µm Class 2 barrel-plating confirmation;
4. rails/panel-to-70-mm drawing, J1/J2/J3 standard top-side reflow
   confirmation (no wave/manual line item), and Epoxy Filled & Capped via
   covering with its quoted price;
5. placement-rotation preview checked for every part listed above;
6. exact enclosure quote/drawings (the owner supplies the screws listed in
   `enclosure/DIMENSIONS.md`);
7. owner authorization for the specified verification quantity.

After arrival, follow `README.md`, `VALIDATION.md`, and `firmware/PLAN.md`.
USB alone cannot power Rev E. First treadmill contact is Proxy-only.
