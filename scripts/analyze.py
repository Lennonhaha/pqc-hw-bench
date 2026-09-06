#!/usr/bin/env python3
"""analyze.py — 数据分析 + 图表（阶段 1）
解析 results/raw 下的 liboqs 基准数据 → 汇总 CSV/Markdown 表 + 对比图。

用法:
    python scripts/analyze.py --summary      # 打印当前全部结果汇总表
    python scripts/analyze.py --plot         # 生成 results/figures/ 图表
"""
import argparse
import csv
import json
import re
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "results" / "raw"
FIG = ROOT / "results" / "figures"

# op 行: "keygen | 19063 | 5.000 | 262.288 | 441.901 | ..."
OP_RE = re.compile(
    r"^\s*(?P<op>keygen|keypair|encaps|decaps|sign|verify)\s*\|\s*"
    r"\d+\s*\|\s*[0-9.]+\s*\|\s*(?P<val>[0-9.]+)\s*\|\s*"
)
# 算法头行: 名字后跟空格+竖线列 (如 "ML-KEM-768                           |            |")
ALG_RE = re.compile(r"^\s*(?P<alg>[A-Za-z][A-Za-z0-9_\-]*(?:-[A-Za-z0-9]+)*)\s+\|")
# 配置信息/表头行前缀（跳过）
SKIP_PREFIX = (
    "Operation", "Speed test", "Started", "Configuration", "Target", "Compiler",
    "OQS", "OpenSSL", "AES:", "SHA-", "CPU", "====", "--",
)


def parse_liboqs_txt(path: Path) -> list[dict]:
    """解析 speed_kem/speed_sig 全量输出的 .txt。返回 [{alg, op, val_us}]"""
    rows = []
    if path.stat().st_size < 100:  # 跳过 0 字节/半截文件
        return rows
    cur_alg = None
    try:
        text = path.read_text(encoding="utf-8-sig")
    except UnicodeDecodeError:
        text = path.read_text(encoding="utf-16")
    for raw in text.splitlines():
        line = raw.rstrip("\r")
        om = OP_RE.match(line)
        if om:
            if cur_alg:
                rows.append(
                    {"alg": cur_alg, "op": om.group("op"), "val_us": float(om.group("val"))}
                )
            continue
        # 非 op 行: 尝试算法头（排除配置信息行）
        if "|" in line and not line.startswith(SKIP_PREFIX):
            m = ALG_RE.match(line)
            if m and ":" not in line.split("|")[0]:
                cur_alg = m.group("alg")
    return rows


def all_raw_texts() -> list[Path]:
    return sorted(RAW.glob("*-all-*.txt"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--summary", action="store_true", help="打印汇总表")
    ap.add_argument("--plot", action="store_true", help="生成图表")
    args = ap.parse_args()

    data = []
    for f in all_raw_texts():
        data += parse_liboqs_txt(f)

    if not data:
        print("!! 无数据: 先跑 software/bench_sw.py 或全量基准生成 results/raw/*-all-*.txt")
        return

    # 汇总 CSV
    FIG.mkdir(parents=True, exist_ok=True)
    today = date.today().isoformat()
    summary_csv = RAW / f"summary-{today}.csv"
    with open(summary_csv, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["alg", "op", "time_us"])
        for r in sorted(data, key=lambda x: (x["alg"], x["op"])):
            w.writerow([r["alg"], r["op"], f"{r['val_us']:.2f}"])

    # 聚焦 ML-KEM / ML-DSA
    focus = [r for r in data if r["alg"].startswith(("ML-KEM", "ML-DSA"))]
    print(f"解析 {len(data)} 条 (聚焦 ML 族 {len(focus)} 条)")
    print(f"{'算法':<16}{'操作':<10}{'耗时(us)':>12}")
    print("-" * 40)
    for r in sorted(focus, key=lambda x: (x["alg"], x["op"])):
        print(f"{r['alg']:<16}{r['op']:<10}{r['val_us']:>12.2f}")

    if args.plot:
        try:
            import matplotlib

            matplotlib.use("Agg")
            import matplotlib.pyplot as plt

            kems = [r for r in data if r["alg"].startswith("ML-KEM")]
            if kems:
                algs = sorted(set(r["alg"] for r in kems))
                ops = ["keygen", "encaps", "decaps"]
                x = range(len(algs))
                width = 0.25
                fig, ax = plt.subplots(figsize=(10, 5))
                for i, op in enumerate(ops):
                    vals = [
                        next(r["val_us"] for r in kems if r["alg"] == a and r["op"] == op)
                        for a in algs
                    ]
                    ax.bar([p + i * width for p in x], vals, width, label=op)
                ax.set_xticks([p + width for p in x])
                ax.set_xticklabels(algs)
                ax.set_ylabel("µs/op")
                ax.set_title("ML-KEM CPU 基线 (liboqs AVX2)")
                ax.legend()
                fig.tight_layout()
                out = FIG / f"mlkem-cpu-baseline-{today}.png"
                fig.savefig(out, dpi=150)
                print(f"图: {out}")
        except ImportError:
            print("!! matplotlib 未装: pip install matplotlib")


if __name__ == "__main__":
    main()
