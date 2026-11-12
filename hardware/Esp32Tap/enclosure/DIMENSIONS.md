# Esp32Tap Rev E enclosure dimensions and modeled validation

**Status: HOLD.** The CAD and checked-in meshes pass deterministic model
validation. Actual board/connector fit, delivered plug/latch/extraction
clearance, installed bend clearance, RF performance, material acceptance,
and enclosure supply remain physical or vendor gates.

The source is `esp32tap_case.scad`. Both meshes are rendered with hard
warnings using the immutable image:

```text
openscad/openscad@sha256:147e48525bec392bcf628d7a6d5ea4ccac71b16251952328f86e1061cbf47c37
```

Run `python3 validate_enclosure.py` from this directory to inspect the live
KiCad board, render both parts again, compare canonical triangle hashes, and
run the mesh and functional probes.

## Print material

Order from JLC3DP as **MJF nylon (PA12)**, not SLA resin (the thin lip and
posts are brittle in resin). Plastic only: no metallic or conductive finish
(2.4 GHz antenna inside).

## Hardware you must supply (JLC does not)

JLC prints the two plastic parts only. No screws, inserts or washers are
included.

| Qty | Part | Thread / length | Head | Where |
|---:|---|---|---|---|
| 2 | **Nylon** screw | M3 × 10 mm | countersunk (flat), 90° | Lid, the two **top** posts (nearest the ESP32 antenna) |
| 2 | Steel screw | M3 × 10 mm | countersunk (flat) | Lid, the two **bottom** posts (nearest the USB-C edge) |
| 3 | Screw (steel) | M2.5 × 5 mm | pan | PCB mounting holes MH1, MH2, MH3 into the base posts |
| 2–4 (optional) | Cable tie, ≤3 mm wide | n/a | n/a | Mounting ears |

Notes:

- Lid screws: 3.0 mm lid plus 7.0 mm into a 10 mm deep Ø2.5 pilot; the
  countersink is Ø6.4 mm × 1.8 mm. The lid holes are Ø3.4 mm clearance.
- Nylon on the top posts: the top-right lid post is about 13.5 mm from the
  ESP32 antenna edge, so a steel screw there sits in the antenna's near
  field. Nylon M3 does not cut its own thread in a Ø2.5 pilot reliably:
  run a steel M3 in once to form the thread, remove it, then fit the nylon
  screw (do not over-torque nylon).
- M2.5 × 5: 1.6 mm through the PCB, 3.4 mm into the 4.0 mm pilot. A longer
  screw bottoms out in the pilot. The nearest M2.5 screw (MH2) is about
  21 mm from the antenna.

## Inspector-bound geometry

Coordinates use the PCB outline minimum as `(0, 0)`.

| Item | Inspector-derived value |
|---|---|
| Board | 95.0 × 58.0 × 1.6 mm |
| J1 footprint anchor / body width | (11.9, 40.0) / 15.48 mm |
| J2 footprint anchor / body width | (83.1, 40.0) / 15.48 mm |
| J3 USB-C center | (83.6, 54.2) mm |
| SW1 / SW2 centers | (42.0, 7.0) / (91.0, 20.0) mm |
| U1 physical antenna edge | 3.3 mm inside board Y=0 |
| U1 antenna span | X=69.0…87.0 mm |
| Mounting centers | (20.0, 6.0), (48.0, 6.0), (92.0, 55.0) mm |

J1 and J2 are the identical Molex 0441440003 right-angle SMD 8P8C RJ45 jack
(LCSC C585890), so their body widths (and every RJ45 dimension below) are
the same value; Rev E places one jack per short edge (J1 left, J2 right),
both centred on the same Y=40 axis with each mating face FLUSH with its
board edge (the body extends inboard from the edge). The mounting locations
reproduce the versioned inspection report exactly; this is modeled
geometry, not delivered fit evidence.

## Shell and access geometry

| Item | Modeled value |
|---|---|
| Interior cavity | 99.0 × 78.7 × 21.1 mm |
| Outer shell | 104.0 × 83.7 × 23.6 mm |
| Lid | 104.0 × 83.7 × 3.0 mm, plus 1.2 mm registration lip (0.4 mm/side clearance to the inner wall; 0.4 mm/side relief around each lid post) |
| Wall / floor | 2.5 mm |
| PCB under-clearance / headroom | 3.0 / 16.5 mm |
| Antenna void | 15.0 mm plastic/air from the physical antenna edge |
| USB overmold aperture | 12.0 × 8.0 mm, cut through the wall only (0.66 mm to the bottom-right lid post; clear of the MH3 post) |
| Switch access | Ø2.5 mm tool openings at exact SW1/SW2 centers |
| LED light holes | Ø3.2 mm through the lid at the PCB LED1 (93.0, 13.0) and LED2 (41.2, 55.4) centers |
| Connector latch clearance | 6.0 mm modeled straight-access depth |
| Exterior cable bend service envelope | 18.0 mm minimum radius |
| Closure | **Screws only**: 4 × M3 lid screws into the corner posts (Ø2.5 mm pilot, 10 mm deep). There are no snap latches. |
| Board retention | 3 × M2.5 screws into the board posts (Ø2.0 mm pilot, 4.0 mm deep: 3.0 mm post + 1.0 mm into the floor, 1.5 mm of floor remains) |

The enclosure contains no metal in the antenna void. The external 18 mm
bend envelope is a production routing requirement; it is not represented as
proof that a delivered cable fits an installed treadmill.

## RJ45 wall apertures

Both jacks are the identical, unshielded 8P8C part, edge-mounted with the
mating opening facing off a short board edge and the mating face flush
with it, wall + clr = 4.5 mm behind the exterior wall face (Rev E: J1
opens off X=0, J2 off X=95 — see `gen_pcb.py` `PLACE`).
There is no mechanical keying between console and motor any more: both
apertures are identical, straight 16.0 × 14.0 mm openings that clear the
15.48 × 13.4 mm jack body by 0.26 mm on width. CONSOLE/MOTOR silkscreen is
the only differentiator; a mis-plugged cable is a labeling/procedure risk,
not something this CAD rejects.

These apertures are modeled fit only. Delivered plug seating, latch
engagement, and wrong-cable attempts remain open physical evidence.

## RJ45 plug service envelope

The jack (Molex 0441440003 / LCSC C585890) mechanical envelope:

| Item | Value |
|---|---|
| Body width | 15.48 mm |
| Body depth (mating face at the board edge to the inboard rear mechanical-tab cap) | 17.17 mm |
| Body height above board | 13.4 mm |
| Aperture (width × height) | 16.0 × 14.0 mm |
| Latch/extraction clearance | 6.0 mm |
| Cable exit direction | J1: enclosure X-min; J2: enclosure X-max |

Each jack's service volume points outward through its own wall (J1
toward enclosure X-min, J2 toward X-max): each treadmill RJ45 cable exits
outward, then retains an 18 mm minimum bend radius before reaching the
enclosure wall. The service-volume geometry is model
evidence only; delivered plug seating, latch, and extraction checks remain
physical gates.

## Checked mesh evidence

| Mesh | Byte SHA-256 | Canonical geometry SHA-256 | Volume | Bounds |
|---|---|---|---:|---|
| `esp32tap_base.stl` | `11f6544635c570b8d2a8f704f282441f2ebaf4a149c0f5f1fd7abad6948a2028` | `0c2a099b3d88d0329b7672cc62d0f6fef3edd8643ed7e996ebff82b9054ac8c6` | 43,391.435 mm³ | −6…112 × 0…83.7 × 0…23.6 mm |
| `esp32tap_lid.stl` | `62ecd790fd69490a734259c40d039920b7ffe5b4421af2522b1ba29010d5879a` | `b3ae8428f304909a0f7036821f213d971906531d15c10bc9923213541ead732f` | 27,124.620 mm³ | 0…104 × 0…83.7 × 0…4.2 mm |

Both meshes are single positive-volume, watertight, winding-consistent
manifolds with exactly two faces per welded edge. Occupancy and
boundary probes cover the cavity, RJ45 apertures, USB, switches, LED
light holes, mounting posts (including the 4.0 mm pilots), lid posts, the
absence of latch geometry, and the antenna void.
