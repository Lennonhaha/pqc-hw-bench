#!/usr/bin/env python3
"""bench_sw.py — CPU 软件基线基准（liboqs speed）
阶段 1 交付物：调用 liboqs speed_kem/speed_sig，解析输出为统一 JSON/CSV。

用法:
    python scripts/bench_sw.py --alg ML-KEM-768
    python scripts/bench_sw.py --all                # 全部 KEM + 全部签名
    python scripts/bench_sw.py --duration 5         # 每操作测 5 秒 (默认 3)

输出:
    results/raw/kem-<alg>-<date>.json
    results/raw/sw-baseline-<date>.csv   (汇总)
"""
import argparse
import csv
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "results" / "raw"

KEM_ALGS = ["ML-KEM-512", "ML-KEM-768", "ML-KEM-1024"]
SIG_ALGS = ["ML-DSA-44", "ML-DSA-65", "ML-DSA-87"]


def resolve_tests_dir(explicit: str | None) -> Path:
    """定位 liboqs speed 可执行文件目录，优先级:
    1. --tests-dir 参数
    2. 环境变量 LIBOQS_TESTS_DIR
    3. PATH 中的 speed_kem/speed_sig
    4. 常见源码编译位置 (./liboqs/build*/tests)
    """
    if explicit:
        p = Path(explicit)
        if p.is_dir():
            return p
        raise SystemExit(f"!! --tests-dir 不存在: {p}")
    env = os.environ.get("LIBOQS_TESTS_DIR")
    if env:
        p = Path(env)
        if p.is_dir():
            return p
        print(f"!! 环境变量 LIBOQS_TESTS_DIR 无效: {env}，尝试其他方式")
    # PATH 探测
    for exe in ("speed_kem", "speed_sig"):
        found = shutil.which(exe)
        if found:
            return Path(found).parent
    # 常见源码布局探测: <parent>/liboqs*/build*/tests (源码树) 或 <parent>/liboqs-build*/tests (构建树)
    # 取最新修改的（避免旧 build 残留）
    parents = [ROOT.parent, ROOT.parent.parent, Path.home()]
    seen = set()
    for base in parents:
        for pat in ("liboqs*/build*/tests", "liboqs*/build/tests", "liboqs-build*/tests"):
            for cand in sorted(base.glob(pat)):
                if cand.is_dir() and cand not in seen:
                    seen.add(cand)
    if seen:
        return max(seen, key=lambda p: p.stat().st_mtime)
    raise SystemExit(
        "!! 找不到 liboqs tests 目录。请用 --tests-dir 指定或设置 LIBOQS_TESTS_DIR\n"
        "   参考 docs/setup.md 编译 liboqs 后指向 <build>/tests"
    )

# liboqs 0.16 表格式（新）:
# ML-KEM-768                           |            |                |                 |            |
# keygen                               |      19063 |          5.000 |         262.288 |    441.901 |
# 算法行后跟 op 行; op 行第 4 列 = Time(us) mean
OP_RE = re.compile(
    r"^\s*(?P<op>keygen|keypair|encaps|decaps|sign|verify)\s+\|\s*"
    r"\d+\s+\|\s+[0-9.]+\s+\|\s+(?P<val>[0-9.]+)\s+\|\s+"
)
ALG_RE = re.compile(r"^\s*(?P<alg>ML-(?:KEM|DSA)-\d+)\s*\|?\s*$")

# 旧版行格式兼容 (liboqs <0.15): "ML-KEM-768 | keygen | median | 12.34 | us/op"
OLD_RE = re.compile(
    r"^\s*(?P<alg>ML-(?:KEM|DSA)[-\w]+)\s*\|\s*"
    r"(?P<op>keygen|keypair|encaps|decaps|sign|verify)\s*\|\s*"
    r"(?:median|avg)\s*\|\s*"
    r"(?P<val>[0-9.]+)\s*\|\s*us/op"
)


def run_speed(exe: Path, alg: str, duration: int) -> str:
    cmd = [str(exe), "-d", str(duration), alg]
    print(f"  > {' '.join(cmd)}")
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    return r.stdout + r.stderr


def parse(text: str, alg: str) -> list[dict]:
    rows = []
    cur_alg = alg
    for line in text.splitlines():
        m = OLD_RE.match(line)
        if m:
            d = m.groupdict()
            d["stat"] = "mean"
            d["unit"] = "us/op"
            d["val"] = float(d["val"])
            rows.append(d)
            continue
        am = ALG_RE.match(line)
        if am:
            cur_alg = am.group("alg")
            continue
        om = OP_RE.match(line)
        if om:
            rows.append(
                {
                    "alg": cur_alg,
                    "op": om.group("op"),
                    "stat": "mean",
                    "val": float(om.group("val")),
                    "unit": "us/op",
                }
            )
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--alg", help="单算法 (如 ML-KEM-768)")
    ap.add_argument("--all", action="store_true", help="全部算法")
    ap.add_argument("--duration", type=int, default=3)
    ap.add_argument("--tests-dir", help="liboqs tests 目录 (默认: 环境变量 LIBOQS_TESTS_DIR / PATH / 自动探测)")
    args = ap.parse_args()

    tests_dir = resolve_tests_dir(args.tests_dir)

    RAW.mkdir(parents=True, exist_ok=True)
    today = date.today().isoformat()
    all_rows = []

    targets = []
    if args.all:
        targets = KEM_ALGS + SIG_ALGS
    elif args.alg:
        targets = [args.alg]
    else:
        ap.error("需 --alg 或 --all")

    for alg in targets:
        exe = tests_dir / ("speed_kem.exe" if "KEM" in alg else "speed_sig.exe")
        if not exe.exists():
            # 非 Windows 平台无 .exe 后缀
            exe = tests_dir / ("speed_kem" if "KEM" in alg else "speed_sig")
        if not exe.exists():
            print(f"!! 缺少 {exe} — 请先编译 liboqs (见 docs/setup.md)")
            sys.exit(2)
        rows = parse(run_speed(exe, alg, args.duration), alg)
        if not rows:
            print(f"!! {alg}: 无法解析输出")
            continue
        all_rows += rows
        kind = "kem" if "KEM" in alg else "sig"
        out = RAW / f"{kind}-{alg}-{today}.json"
        out.write_text(
            json.dumps(
                {
                    "schema": "pqc-hw-bench/result-v0.1",
                    "platform": "x86-64",
                    "impl": "liboqs-0.16.0 (gcc 15.2.0, AVX2)",
                    "alg": alg,
                    "ops": rows,
                    "date": today,
                    "duration_s": args.duration,
                },
                indent=2,
            ),
            encoding="utf-8",
        )
        print(f"  [OK] {out.name}: {len(rows)} ops")
        for r in rows:
            print(f"    {r['op']:<10} {r['stat']:<6} {r['val']:>12.2f} {r['unit']}")

    # CSV 汇总
    if all_rows:
        csv_path = RAW / f"sw-baseline-{today}.csv"
        with open(csv_path, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=["alg", "op", "stat", "val", "unit"])
            w.writeheader()
            w.writerows(all_rows)
        print(f"\n汇总: {csv_path}")


if __name__ == "__main__":
    main()
