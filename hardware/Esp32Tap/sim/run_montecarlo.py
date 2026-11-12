#!/usr/bin/env python3
"""Monte Carlo of the Rev E liveness charge pump (R35, C22, D8, C23, R34, Q3).

Standard library only.  It draws every tolerance from a stated distribution,
writes a small ngspice deck per draw, runs `ngspice -n -b` on the host and
collects four figures: steady gate voltage, pickup time, release time and the
peak gate voltage from a single stray edge.

The distributions are uniform across each tolerance band (log-uniform for the
diode leakage multiplier).  Uniform is wider than a real production
distribution, so it is a conservative choice for tails.  Everything here is a
simple model: no figure it prints is a bench measurement.

The seed is fixed and the summary contains no timestamps, so two runs give a
byte-identical montecarlo_summary.json.

Usage: python3 run_montecarlo.py [--n 300] [--seed 20260712] [--out FILE]
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import math
import random
import re
import subprocess
import sys
import tempfile
from pathlib import Path

SIM_DIR = Path(__file__).resolve().parent
NGSPICE = "/usr/bin/ngspice"

N_RUNS = 300
SEED = 20260712

# ---------------------------------------------------------------------------
# Tolerance bands (see decks/liveness_corners.cir ASSUMPTIONS for sources).
# ---------------------------------------------------------------------------
VDD_RANGE = (3.0, 3.6)            # MCU supply / pin high level
PIN_DROOP_MAX = 0.4               # pin high = VDD - U(0, 0.4), low = U(0, 0.4)
FREQ_RANGE = (950.0, 1050.0)      # 1 kHz +/- 5 %
DUTY_RANGE = (0.40, 0.60)
R_TOL = 0.01                      # R34, R35
C22_RANGE = (70.5e-9, 126.5e-9)   # 100 nF total low/high (tol, X7R, bias, age)
C23_RANGE = (0.557e-6, 1.265e-6)  # 1 uF total low/high (tol, X5R, bias, age)
VT25_RANGE = (0.65, 1.45)         # AO3400A Vgs(th) at 25 C, datasheet
VT_TEMPCO = -3.0e-3               # V per C, assumption
TEMP_RANGE = (-20.0, 70.0)
VF_SPREAD = 0.020                 # +/- V part-to-part Vf around typical
IL_MULT_RANGE = (1.0, 10.0)       # leakage multiplier on typical, log-uniform
IGSS_MAX = 100e-9                 # AO3400A Igss max
CISS = 630e-12                    # AO3400A Ciss typ

# BAT54S typical anchors read from the Diodes Inc BAT54/A/C/S datasheet
# (DS11005 Rev 35-2) Fig 1 at 0.1 mA and 1 mA, Fig 2 reverse current at ~3 V.
# (temp C, Vf@0.1mA, Vf@1mA, IR@3V in A)
VF_ANCHORS = ((-20.0, 0.31, 0.37), (25.0, 0.22, 0.31), (70.0, 0.15, 0.21))
IL_25C = 0.07e-6
IL_TEMP_E_FOLD = 14.7  # C per e-fold, from 0.06 uA (25 C) -> 2.1 uA (75 C)

# Requirements (see REPORT.md).
Q3_FULL_ON_MARGIN = 0.5      # gate must clear the threshold by this (model's full-on point)
VT_MAX_COLD = 1.45 + VT_TEMPCO * (-20.0 - 25.0)  # 1.585 V at -20 C
PICKUP_LIMIT_S = 0.015
RELEASE_TEST_BOUND_S = 0.2
FIRMWARE_STOP_S = 0.020
EDGE_MARGIN_V = 0.1

T_STOP = 0.200
T_END = 0.500


def interp(points, x):
    xs = [p[0] for p in points]
    x = min(max(x, xs[0]), xs[-1])
    for (x0, *y0), (x1, *y1) in zip(points, points[1:]):
        if x <= x1:
            w = (x - x0) / (x1 - x0)
            return [a + w * (b - a) for a, b in zip(y0, y1)]
    return list(points[-1][1:])


def diode_fit(vf_a, vf_b):
    """Return (Is, N) at SPICE's 27 C so that Vf=vf_a at 0.1 mA and vf_b at
    1 mA with Rs = 4 ohm.  N absorbs the real junction temperature."""
    rs = 4.0
    a = vf_a - rs * 1e-4
    b = vf_b - rs * 1e-3
    n_vt = (b - a) / math.log(10.0)
    n = n_vt / 0.025852
    i_s = 1e-3 / math.exp(b / n_vt)
    return i_s, n, rs


def fmt(x):
    return f"{x:.9g}"


def build_deck(p, *, tran_end=T_END):
    """Deck with three pumps: run/stop held low, run/stop held high, and a
    pin that steps high once and stays."""
    i_s, n, rs = diode_fit(p["vf_a"], p["vf_b"])
    period = 1.0 / p["f"]
    pw = period * p["duty"]
    lines = [
        "montecarlo single draw",
        ".include models/behavioral.inc",
        f".model DMC D(Is={fmt(i_s)} N={fmt(n)} Rs={fmt(rs)} Cjo=10p)",
        ".subckt DSCH a k params: IL=1u",
        "D1 a k DMC",
        "BL a k I={-IL*0.5*(1+tanh((v(k)-v(a))/0.05))}",
        ".ends DSCH",
        ".subckt MCPUMP pin gate params: R35=560 R34=100k C22=100n C23=1u RG=26meg",
        "R35 pin pump_in {R35}",
        "C22 pump_in pump_ac {C22}",
        "XD8A 0 pump_ac DSCH params: IL=" + fmt(p["il"]),
        "XD8B pump_ac gate DSCH params: IL=" + fmt(p["il"]),
        "C23 gate 0 {C23}",
        "R34 gate 0 {R34}",
        f"CGQ gate 0 {fmt(CISS)}",
        "RGQ gate 0 {RG}",
        ".ends MCPUMP",
        f"VSQ sq 0 PULSE({fmt(p['vl'])} {fmt(p['vh'])} 10m 1u 1u {fmt(pw)} {fmt(period)})",
        f"VENV env 0 PULSE(1 0 {fmt(T_STOP)} 1u 1u 10 20)",
        f"BPL pin_l 0 V=v(sq)*v(env)+{fmt(p['vl'])}*(1-v(env))",
        f"BPH pin_h 0 V=v(sq)*v(env)+{fmt(p['vh'])}*(1-v(env))",
        f"VSTEP pin_s 0 PULSE({fmt(p['vl'])} {fmt(p['vh'])} 10m 1u 1u 10 20)",
    ]
    params = (
        f"params: R35={fmt(p['r35'])} R34={fmt(p['r34'])} "
        f"C22={fmt(p['c22'])} C23={fmt(p['c23'])} RG={fmt(p['rg'])}"
    )
    for tag in ("l", "h", "s"):
        lines.append(f"XP{tag.upper()} pin_{tag} g_{tag} MCPUMP {params}")
    mid = (p["vl"] + p["vh"]) / 2
    vt = p["vt"]
    lines += [
        f".tran 2u {fmt(tran_end)} 0 5u",
        ".meas tran gate_min_v MIN v(g_l) FROM=0.18 TO=0.2",
        f".meas tran pickup_s TRIG v(sq) VAL={fmt(mid)} RISE=1 TARG v(g_l) VAL={fmt(vt)} RISE=1",
        f".meas tran release_low_s TRIG v(env) VAL=0.5 TD=0.199 FALL=1 TARG v(g_l) VAL={fmt(vt)} TD=0.199 FALL=1",
        f".meas tran release_high_s TRIG v(env) VAL=0.5 TD=0.199 FALL=1 TARG v(g_h) VAL={fmt(vt)} TD=0.199 FALL=1",
        ".meas tran edge_peak_v MAX v(g_s) FROM=0 TO=0.6",
        ".end",
    ]
    return "\n".join(lines) + "\n"


def run_deck(deck_text):
    with tempfile.NamedTemporaryFile("w", suffix=".cir", delete=False) as handle:
        handle.write(deck_text)
        path = Path(handle.name)
    try:
        done = subprocess.run(
            [NGSPICE, "-n", "-b", str(path)],
            cwd=SIM_DIR,
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
    finally:
        path.unlink(missing_ok=True)
    out = done.stdout + done.stderr
    result = {}
    for name in (
        "gate_min_v", "pickup_s", "release_low_s", "release_high_s", "edge_peak_v",
    ):
        m = re.search(
            rf"^{name}\s*=\s*([-+0-9.eE]+|nan|-nan|inf)", out, re.MULTILINE
        )
        if m is None or not math.isfinite(float(m.group(1))):
            result[name] = None
        else:
            result[name] = float(m.group(1))
    return result


def draw(rng):
    t = rng.uniform(*TEMP_RANGE)
    vt25 = rng.uniform(*VT25_RANGE)
    vdd = rng.uniform(*VDD_RANGE)
    (va, vb) = interp(VF_ANCHORS, t)
    off = rng.uniform(-VF_SPREAD, VF_SPREAD)
    il_typ = IL_25C * math.exp((t - 25.0) / IL_TEMP_E_FOLD)
    il = il_typ * math.exp(rng.uniform(math.log(IL_MULT_RANGE[0]), math.log(IL_MULT_RANGE[1])))
    igss = rng.uniform(1e-9, IGSS_MAX)
    return {
        "temp_c": t,
        "vdd": vdd,
        "vh": vdd - rng.uniform(0.0, PIN_DROOP_MAX),
        "vl": rng.uniform(0.0, PIN_DROOP_MAX),
        "f": rng.uniform(*FREQ_RANGE),
        "duty": rng.uniform(*DUTY_RANGE),
        "r34": 100e3 * rng.uniform(1 - R_TOL, 1 + R_TOL),
        "r35": 560.0 * rng.uniform(1 - R_TOL, 1 + R_TOL),
        "c22": rng.uniform(*C22_RANGE),
        "c23": rng.uniform(*C23_RANGE),
        "vf_a": va + off,
        "vf_b": vb + off,
        "il": il,
        "rg": 2.6 / igss,
        "vt25": vt25,
        "vt": vt25 + VT_TEMPCO * (t - 25.0),
    }


def percentile(sorted_values, q):
    """Linear-interpolated percentile, q in [0, 100]."""
    if not sorted_values:
        return None
    pos = (len(sorted_values) - 1) * q / 100.0
    lo = int(math.floor(pos))
    hi = int(math.ceil(pos))
    return sorted_values[lo] + (sorted_values[hi] - sorted_values[lo]) * (pos - lo)


def stats(values):
    """min/p1/median/p99/max, treating None (never crossed) as +infinity
    for time-like figures is done by the caller; here None entries are
    counted separately."""
    finite = sorted(v for v in values if v is not None)
    keys = ("min", "p01", "median", "p99", "max")
    if not finite:
        return {**{k: None for k in keys}, "count_missing": len(values)}
    out = {
        "min": finite[0],
        "p01": percentile(finite, 1),
        "median": percentile(finite, 50),
        "p99": percentile(finite, 99),
        "max": finite[-1],
        "count_missing": len(values) - len(finite),
    }
    return {k: (round(v, 9) if isinstance(v, float) else v) for k, v in out.items()}


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--n", type=int, default=N_RUNS)
    parser.add_argument("--seed", type=int, default=SEED)
    parser.add_argument("--out", type=Path, default=SIM_DIR / "montecarlo_summary.json")
    args = parser.parse_args(argv)

    rng = random.Random(args.seed)
    draws = [draw(rng) for _ in range(args.n)]
    decks = [build_deck(d) for d in draws]
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        results = list(pool.map(run_deck, decks))

    rows = []
    for d, r in zip(draws, results):
        rel_low = r["release_low_s"]
        rel_high = r["release_high_s"]
        rels = [x for x in (rel_low, rel_high) if x is not None]
        # release never crossing inside the window is the worst outcome
        release = max(rels) if rels else None
        rows.append({**d, **r, "release_s": release})

    def column(name):
        return [row[name] for row in rows]

    # Requirements (counted per draw; a missing crossing counts as a violation).
    def count(pred):
        return sum(1 for row in rows if pred(row))

    violations = {
        "A_steady_gate_below_vt_plus_0p5v_of_that_draw": count(
            lambda r: r["gate_min_v"] is None or r["gate_min_v"] < r["vt"] + Q3_FULL_ON_MARGIN
        ),
        "A_steady_gate_below_fixed_2p085v_(1.585V_cold_max_threshold_+0.5V)": count(
            lambda r: r["gate_min_v"] is None or r["gate_min_v"] < VT_MAX_COLD + Q3_FULL_ON_MARGIN
        ),
        "A_steady_gate_below_that_draws_own_vt": count(
            lambda r: r["gate_min_v"] is None or r["gate_min_v"] < r["vt"]
        ),
        "B_pickup_over_15ms": count(
            lambda r: r["pickup_s"] is None or r["pickup_s"] > PICKUP_LIMIT_S
        ),
        "B_pickup_over_30ms_firmware_precharge": count(
            lambda r: r["pickup_s"] is None or r["pickup_s"] > 0.030
        ),
        # A draw whose gate never reaches its own threshold has no release
        # time; it is counted under A and B, not here.
        "C_release_over_0p2s": count(
            lambda r: r["release_s"] is not None and r["release_s"] > RELEASE_TEST_BOUND_S
        ),
        "C_release_plus_20ms_over_0p2s": count(
            lambda r: r["release_s"] is not None
            and r["release_s"] + FIRMWARE_STOP_S > RELEASE_TEST_BOUND_S
        ),
        "D_single_edge_peak_within_0p1v_of_that_draws_vt": count(
            lambda r: r["edge_peak_v"] is None or r["edge_peak_v"] > r["vt"] - EDGE_MARGIN_V
        ),
        "D_single_edge_peak_above_that_draws_vt": count(
            lambda r: r["edge_peak_v"] is None or r["edge_peak_v"] >= r["vt"]
        ),
    }

    summary = {
        "seed": args.seed,
        "n": args.n,
        "distributions": (
            "uniform across each tolerance band; diode leakage multiplier "
            "log-uniform 1..10 on the typical value; see decks/liveness_corners.cir"
        ),
        "temperature_range_c": list(TEMP_RANGE),
        "figures": {
            "steady_gate_min_v": stats(column("gate_min_v")),
            "pickup_s": stats(column("pickup_s")),
            "release_s_worst_of_held_low_and_high": stats(column("release_s")),
            "single_edge_peak_v": stats(column("edge_peak_v")),
        },
        "requirement_violations": violations,
        "requirements": {
            "A": "steady gate >= that draw's Q3 threshold + 0.5 V (model full-on point); also counted against the fixed 2.085 V",
            "B": "pickup <= 15 ms (half the firmware's 30 ms precharge); 30 ms also counted",
            "C": "no formal requirement; counted against the existing 0.2 s test bound, with and without the firmware's 20 ms",
            "D": "single-edge peak <= that draw's Q3 threshold - 0.1 V; also counted against the threshold itself",
        },
    }
    args.out.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
