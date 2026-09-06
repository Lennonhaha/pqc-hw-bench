#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# SPDX-License-Identifier: MIT
# =============================================================================
# run_tvla_sim.py — One-shot pre-silicon power side-channel TVLA/ADLA pipeline
#
# B3 orchestration: vectors -> iverilog compile -> vvp simulation ->
# toggle log -> Welch t-test + ADLA -> JSON report + exit-code gate.
#
# Pipeline stages (all reproducible, deterministic):
#   1. gen_ntt_vectors.py --runs N --mode fwd|inv
#      (writes sim/vectors_{A,B}.mem or sim/inv/vectors_{A,B}.mem)
#   2. iverilog compile of hardware/sim/tb_ntt_toggle_tvla.v
#      (+DEFINE MODE_INV when --mode inv, +DEFINE RUNS_A/B when runs != 128)
#   3. vvp run -> sim/toggle_raw.txt (TOGGLE <grp> <run> <count> lines)
#   4. analyze_toggle.py --raw ... --mode ... -> results/raw/<suite>.json
#
# Exit codes: 0 = all PASS, 1 = infra error, 2 = leakage detected (FAIL).
#
# CLI:
#   python scripts/run_tvla_sim.py [--runs 128] [--mode fwd|inv]
#                                  [--iverilog C:/iverilog/bin] [--keep-logs]
#   python scripts/run_tvla_sim.py --ci          # smoke: 32 runs, keep logs
#
# Requires: iverilog + vvp on PATH (or --iverilog <bin dir>).
# =============================================================================
import argparse
import json
import os
import subprocess
import sys

BASE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(BASE)

RTL_DIR = os.path.join(REPO, "hardware", "rtl", "ntt")
SIM_DIR = os.path.join(REPO, "hardware", "sim")
VEC_DIR = os.path.join(REPO, "sim")
TB = os.path.join(SIM_DIR, "tb_ntt_toggle_tvla.v")

# RTL sources required for the USE_PIPE=1 path (verified compile set, B1):
#   scheduler instantiates ntt_core_pipe (generate USE_PIPE=1) and ntt_core
#   (USE_PIPE=0 branch must resolve). butterfly_unif references mod_* and zeta_rom.
# Do NOT add alternative implementations (ntt_core_pipe2, *_nobom, zeta_rom_synth,
# ntt_butterfly.v) — they redeclare the same module names and break compilation.
RTL_SOURCES = [
    "mod_add.v",
    "mod_sub.v",
    "mod_mult.v",
    "ntt_butterfly_unif.v",
    "zeta_rom.v",
    "ntt_core.v",
    "ntt_core_pipe.v",
    "tensor_ntt_scheduler.v",
]


def find_iverilog(iverilog_dir=None):
    """Locate iverilog/vvp executables."""
    if iverilog_dir:
        ic = os.path.join(iverilog_dir, "iverilog" + (".exe" if os.name == "nt" else ""))
        vp = os.path.join(iverilog_dir, "vvp" + (".exe" if os.name == "nt" else ""))
        if os.path.exists(ic) and os.path.exists(vp):
            return ic, vp
        print(f"[FATAL] iverilog/vvp not found in {iverilog_dir}")
        sys.exit(1)
    for exe in ("iverilog",):
        for p in os.environ.get("PATH", "").split(os.pathsep):
            cand = os.path.join(p, exe + (".exe" if os.name == "nt" else ""))
            if os.path.exists(cand):
                ic = cand
                vp = os.path.join(p, "vvp" + (".exe" if os.name == "nt" else ""))
                if os.path.exists(vp):
                    return ic, vp
                print(f"[FATAL] found iverilog at {cand} but no vvp beside it")
                sys.exit(1)
    print("[FATAL] iverilog not found on PATH; pass --iverilog <bin dir>")
    sys.exit(1)


def run(cmd, cwd, log_path=None):
    print(f"[RUN ] {' '.join(cmd)}")
    if log_path:
        with open(log_path, "w", encoding="utf-8", errors="replace") as lf:
            r = subprocess.run(cmd, cwd=cwd, stdout=lf, stderr=subprocess.STDOUT)
    else:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
        if r.stdout:
            print(r.stdout)
        if r.stderr:
            print(r.stderr, file=sys.stderr)
    return r.returncode


def main():
    ap = argparse.ArgumentParser(description="B3 pre-silicon TVLA pipeline")
    ap.add_argument("--runs", type=int, default=128)
    ap.add_argument("--mode", choices=["fwd", "inv"], default="fwd")
    ap.add_argument("--iverilog", default=None, help="iverilog bin dir (auto-detect if omitted)")
    ap.add_argument("--keep-logs", action="store_true", help="keep sim logs (default remove on success)")
    ap.add_argument("--ci", action="store_true", help="CI smoke mode: 32 runs, keep logs, smaller sim")
    args = ap.parse_args()

    runs = 32 if args.ci else args.runs
    mode = args.mode
    iverilog, vvp = find_iverilog(args.iverilog)

    # ---- stage 0: env sanity ----
    if not os.path.exists(TB):
        print(f"[FATAL] testbench not found: {TB}")
        sys.exit(1)

    # ---- stage 1: vectors ----
    r = run([sys.executable, os.path.join(BASE, "gen_ntt_vectors.py"),
             "--runs", str(runs), "--mode", mode], REPO)
    if r != 0:
        print("[FAIL] vector generation"); sys.exit(1)

    # ---- stage 2: compile ----
    vec_sub = os.path.join("inv") if mode == "inv" else ""
    vvp_out = os.path.join(SIM_DIR, "tb_ntt_toggle.vvp")
    defines = []
    if mode == "inv":
        defines.append("-DMODE_INV")
    if runs != 128:
        defines.append(f"-DRUNS_A={runs}")
        defines.append(f"-DRUNS_B={runs}")
    srcs = [os.path.join(RTL_DIR, s) for s in RTL_SOURCES]
    inc = ["-I", RTL_DIR]
    cmd = [iverilog, "-o", vvp_out, *defines, *inc, TB, *srcs]
    r = run(cmd, REPO, log_path=os.path.join(SIM_DIR, "compile.log"))
    if r != 0:
        print("[FAIL] iverilog compile (see hardware/sim/compile.log)")
        sys.exit(1)

    # ---- stage 3: simulate ----
    raw_path = os.path.join(REPO, "sim", "toggle_raw.txt")
    r = run([vvp, vvp_out], REPO, log_path=raw_path)
    if r != 0:
        print("[FAIL] vvp simulation (see sim/toggle_raw.txt)")
        sys.exit(1)
    # count TOGGLE lines as sanity
    tog = 0
    with open(raw_path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("TOGGLE"):
                tog += 1
    print(f"[OK  ] {tog} TOGGLE measurements captured")
    if tog != runs * 2:
        print(f"[FAIL] expected {runs*2} TOGGLE lines, got {tog}")
        sys.exit(1)

    # ---- stage 4: analyze ----
    suite = f"ntt-toggle-tvla-{mode}"
    out_json = os.path.join(REPO, "results", "raw", f"{suite}-b2b3.json")
    ana = [sys.executable, os.path.join(BASE, "analyze_toggle.py"),
           "--raw", raw_path, "--out", out_json,
           "--suite", suite, "--mode", mode]
    r = run(ana, REPO)
    if r != 0:
        print(f"[FAIL] leakage detected or analysis error (exit {r})")
        sys.exit(r)

    # ---- cleanup intermediate sim artifacts (unless --keep-logs/--ci) ----
    if not args.keep_logs and not args.ci:
        for f in (os.path.join(SIM_DIR, "compile.log"), vvp_out,
                  os.path.join(REPO, "sim", "toggle_raw.txt")):
            if os.path.exists(f):
                os.remove(f)
        print("[OK  ] intermediate logs cleaned (use --keep-logs to retain)")

    print(f"[DONE] {suite} PASS — report: {out_json}")
    sys.exit(0)


if __name__ == "__main__":
    main()
