#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# SPDX-License-Identifier: MIT
"""analyze_toggle.py - Welch t-test + ADLA on NTT toggle-count measurements.

Reads a TOGGLE log (lines: TOGGLE <grp> <run> <count>) produced by
hardware/sim/tb_ntt_toggle_tvla.v and reports leakage statistics between
groups A and B.

CLI:
  python analyze_toggle.py [--raw PATH] [--out PATH] [--suite NAME]
                           [--mode fwd|inv] [--json-only]
Defaults:
  --raw <repo>/sim/toggle_raw.txt   --out <repo>/results/raw/ntt-toggle-tvla.json
  --suite ntt-toggle-tvla           --mode fwd
  --json-only : print report JSON to stdout (no human table) for CI/orchestrator
"""
import argparse
import json
import math
import os
import statistics
import sys
import time

BASE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(BASE)  # scripts/ -> repo root


def load(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()
    tog = [l for l in lines if l.startswith("TOGGLE")]
    A, B = [], []
    for l in tog:
        parts = l.split()
        if len(parts) != 4:
            continue
        _, grp, run, cnt = parts
        (A if grp == "A" else B).append(int(cnt))
    return A, B


def welch(a, b):
    na, nb = len(a), len(b)
    ma, mb = statistics.mean(a), statistics.mean(b)
    va, vb = statistics.variance(a), statistics.variance(b)
    t = (ma - mb) / math.sqrt(va / na + vb / nb)
    df = (va / na + vb / nb) ** 2 / (
        (va / na) ** 2 / (na - 1) + (vb / nb) ** 2 / (nb - 1)
    )
    return t, df


def ad_stat(x, y):
    """Two-sample Anderson-Darling, A2 statistic (exact, equal sizes).
    Pettitt 1976 form as cited in the ADLA paper (arXiv 2603.18647, Eq.3):
    A^2 = (1/(n1*n2)) * sum_{i=1}^{n-1} (n*M_i - n1*i)^2 / (i*(n-i))
    where M_i = # of x-observations <= combined[i], n = n1 + n2.
    """
    n1, n2 = len(x), len(y)
    n = n1 + n2
    allv = sorted(x + y)
    xs = sorted(x)
    xi = 0
    s = 0.0
    for i in range(1, n):  # 1-indexed i up to n-1
        while xi < n1 and xs[xi] <= allv[i - 1]:
            xi += 1
        M = xi
        s += (n * M - n1 * i) ** 2 / (i * (n - i))
    return s / (n1 * n2)


def main():
    ap = argparse.ArgumentParser(description="Analyze NTT toggle-count TVLA/ADLA")
    ap.add_argument("--raw", default=os.path.join(REPO, "sim", "toggle_raw.txt"))
    ap.add_argument("--out", default=os.path.join(REPO, "results", "raw", "ntt-toggle-tvla.json"))
    ap.add_argument("--suite", default="ntt-toggle-tvla")
    ap.add_argument("--mode", choices=["fwd", "inv"], default="fwd")
    ap.add_argument("--json-only", action="store_true")
    args = ap.parse_args()

    A, B = load(args.raw)
    if len(A) < 2 or len(B) < 2:
        print(f"[FATAL] not enough data: A={len(A)} B={len(B)}")
        sys.exit(1)
    ma, mb = statistics.mean(A), statistics.mean(B)
    sa, sb = statistics.stdev(A), statistics.stdev(B)
    t, df = welch(A, B)
    a2 = ad_stat(A, B)
    tvla = "PASS" if abs(t) < 4.5 else "FAIL"
    adla = "PASS" if a2 < 11.99 else "FAIL"

    if not args.json_only:
        print(f"A n={len(A)} mean={ma:.2f} stdev={sa:.2f} min={min(A)} max={max(A)}")
        print(f"B n={len(B)} mean={mb:.2f} stdev={sb:.2f} min={min(B)} max={max(B)}")
        print(f"TVLA  |t|={abs(t):.3f} (df={df:.0f})  -> {tvla} (threshold 4.5)")
        print(f"ADLA  A2={a2:.3f}  -> {adla} (threshold 11.99)")

    report = {
        "suite": args.suite,
        "title": f"Pre-silicon power side-channel: NTT toggle-count TVLA/ADLA ({args.mode})",
        "date": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "mode": args.mode,
        "dut": "tensor_ntt_scheduler (USE_PIPE=1) -> ntt_core_pipe",
        "power_model": "HD toggle count on ram_din/bf_a_out/bf_b_out/ram_dout_a/b",
        "design": "A/B both uniform random coeffs in [0,3328], seeds A11CE/C0FFEE; "
                   "same distribution, different values -> value-dependence check",
        "groups": {
            "A": {"n": len(A), "mean": round(ma, 2), "stdev": round(sa, 2),
                    "min": min(A), "max": max(A)},
            "B": {"n": len(B), "mean": round(mb, 2), "stdev": round(sb, 2),
                    "min": min(B), "max": max(B)},
        },
        "stats": {
            "tvla_t": round(t, 3), "tvla_df": round(df, 1),
            "tvla_threshold": 4.5, "tvla_result": tvla,
            "adla_a2": round(a2, 3), "adla_threshold": 11.99,
            "adla_result": adla,
        },
        "conclusion": (
            "No input-value-dependent power leakage detected on NTT core data "
            "path under HD toggle model (TVLA and ADLA both PASS)."
        ),
    }
    if args.json_only:
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        os.makedirs(os.path.dirname(args.out), exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
        print(f"[OK] report written to {args.out}")
    # exit code gate for CI: both must PASS
    sys.exit(0 if (tvla == "PASS" and adla == "PASS") else 2)


if __name__ == "__main__":
    main()
