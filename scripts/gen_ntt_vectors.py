#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# SPDX-License-Identifier: MIT
# =============================================================================
# gen_ntt_vectors.py — Generate NTT input vector sets for toggle-count TVLA
#
# Produces: sim/vectors_A.mem, sim/vectors_B.mem
#   Format: one run per line, 256 hex values (13-bit coeffs), space separated
#   A group: deterministic pseudo-random coeffs, seed A (same dist as B)
#   B group: deterministic pseudo-random coeffs, seed B
#   TVLA design: both groups uniform in [0,3328]; any toggle-count
#   distribution difference is input-VALUE dependence (leakage signal).
#
# CLI: python gen_ntt_vectors.py [--runs N] [--mode fwd|inv] [--outdir DIR]
#   Defaults: --runs 128 --mode fwd --outdir <repo>/sim
#   INV mode stores the vector file under sim/inv/ (same A/B split).
# =============================================================================
import argparse
import os

Q = 3329
N = 256

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def xorshift64(seed):
    x = seed
    while True:
        x ^= (x << 13) & 0xFFFFFFFFFFFFFFFF
        x ^= x >> 7
        x ^= (x << 17) & 0xFFFFFFFFFFFFFFFF
        yield x & 0xFFFFFFFFFFFFFFFF


def gen_group(seed, runs):
    """Deterministic pseudo-random coefficients in [0, Q-1]."""
    rng = xorshift64(seed)
    out = []
    for _ in range(runs):
        poly = [next(rng) % Q for _ in range(N)]
        out.append(poly)
    return out


def write_mem(path, runs):
    with open(path, "w", encoding="ascii") as f:
        for poly in runs:
            f.write(" ".join("%04X" % c for c in poly) + "\n")
    print(f"[OK] {path}: {len(runs)} runs x {N} coeffs")


def main():
    ap = argparse.ArgumentParser(description="Generate NTT TVLA A/B vectors")
    ap.add_argument("--runs", type=int, default=128, help="runs per group (default 128)")
    ap.add_argument("--mode", choices=["fwd", "inv"], default="fwd")
    ap.add_argument("--outdir", default=None, help="override output dir (default <repo>/sim[/inv])")
    args = ap.parse_args()

    if args.outdir:
        out_dir = args.outdir
    else:
        out_dir = os.path.join(REPO, "sim")
        if args.mode == "inv":
            out_dir = os.path.join(out_dir, "inv")
    os.makedirs(out_dir, exist_ok=True)

    write_mem(os.path.join(out_dir, "vectors_A.mem"), gen_group(0xA11CE, args.runs))
    write_mem(os.path.join(out_dir, "vectors_B.mem"), gen_group(0xC0FFEE, args.runs))

    # sanity: values in range
    for fn in ("vectors_A.mem", "vectors_B.mem"):
        with open(os.path.join(out_dir, fn), "r", encoding="ascii") as f:
            for line in f:
                vals = [int(x, 16) for x in line.split()]
                assert len(vals) == N, f"{fn}: expected {N} coeffs"
                assert all(0 <= v < Q for v in vals), f"{fn}: coeff out of range"
    print(f"[OK] All vectors in range [0, 3328] (mode={args.mode}, runs={args.runs})")


if __name__ == "__main__":
    main()
