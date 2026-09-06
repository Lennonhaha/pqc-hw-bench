#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# SPDX-License-Identifier: MIT
# =============================================================================
# gen_ntt_vectors.py — Generate NTT input vector sets for toggle-count TVLA (B1)
#
# Produces: sim/vectors_A.mem, sim/vectors_B.mem
#   Format: one run per line, 256 hex values (13-bit coeffs), space separated
#   A group: deterministic pseudo-random coeffs, seed A (same dist as B)
#   B group: deterministic pseudo-random coeffs, seed B
#   TVLA design: both groups uniform in [0,3328]; any toggle-count
#   distribution difference is input-VALUE dependence (leakage signal).
# =============================================================================
import os

Q = 3329
N = 256
RUNS_PER_GROUP = 128  # total sim runs per group (each = 1 full NTT)

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "sim")
os.makedirs(OUT_DIR, exist_ok=True)


def xorshift64(seed):
    x = seed
    while True:
        x ^= (x << 13) & 0xFFFFFFFFFFFFFFFF
        x ^= x >> 7
        x ^= (x << 17) & 0xFFFFFFFFFFFFFFFF
        yield x & 0xFFFFFFFFFFFFFFFF


def gen_group_a(seed=0xA11CE):
    """Group A: deterministic pseudo-random coefficients in [0, Q-1] (seed A).
    Same distribution as B — only the actual coefficient values differ.
    TVLA question: does toggle count depend on input VALUES (same distribution)?"""
    rng = xorshift64(seed)
    runs = []
    for r in range(RUNS_PER_GROUP):
        poly = []
        for i in range(N):
            v = next(rng)
            poly.append(v % Q)
        runs.append(poly)
    return runs


def gen_group_b(seed=0xC0FFEE):
    """Group B: deterministic pseudo-random coefficients (seed B)."""
    rng = xorshift64(seed)
    runs = []
    for r in range(RUNS_PER_GROUP):
        poly = []
        for i in range(N):
            v = next(rng)
            poly.append(v % Q)
        runs.append(poly)
    return runs


def write_mem(path, runs):
    with open(path, "w", encoding="ascii") as f:
        for poly in runs:
            f.write(" ".join("%04X" % c for c in poly) + "\n")
    print(f"[OK] {path}: {len(runs)} runs x {N} coeffs")


def main():
    write_mem(os.path.join(OUT_DIR, "vectors_A.mem"), gen_group_a())
    write_mem(os.path.join(OUT_DIR, "vectors_B.mem"), gen_group_b())
    # Sanity: verify values in range
    for fn in ("vectors_A.mem", "vectors_B.mem"):
        with open(os.path.join(OUT_DIR, fn), "r", encoding="ascii") as f:
            for line in f:
                vals = [int(x, 16) for x in line.split()]
                assert len(vals) == N, f"{fn}: expected {N} coeffs"
                assert all(0 <= v < Q for v in vals), f"{fn}: coeff out of range"
    print("[OK] All vectors in range [0, 3328]")


if __name__ == "__main__":
    main()
