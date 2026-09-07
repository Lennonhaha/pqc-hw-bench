#!/usr/bin/env python3
"""report.py — 生成完整基准报告 (Markdown)

读取已采集的数据, 生成 reports/benchmark-YYYYQN.md:
  - CPU 软件基线 (results/raw/summary-*.csv)
  - FPGA 硬件资源与时序 (hardware/reports/ 的 Vivado 报告, 常量引用)
  - 预硅功耗 TVLA/ADLA (results/raw/ntt-toggle-tvla-*.json)
  - 算力成本模型 (框架, 见 docs/cost-model.md)

用法:
    python scripts/report.py            # 生成当前季度报告
    python scripts/report.py --quarter 2026Q3
"""
import argparse
import csv
import json
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "results" / "raw"
REPORTS = ROOT / "reports"

# ── 硬件资源 (2026-09-06 Vivado 实测, 来源 hardware/reports/utilization_nttcore.txt) ──
# 硬编码为常量: 从 Vivado 报告文本解析脆弱且这些值是稳定的复现结果。
HW = {
    "device": "xc7a35tfgg484-2 (Artix-7 35T)",
    "tool": "Vivado 2021.1 (WebPACK)",
    "clock_mhz": 50.0,
    "wns_ns": 9.733,           # Setup worst slack, 0 failing endpoints
    "max_freq_mhz": 97.0,      # 由 WNS 反推的可运行上限
    "top_lut": 1754,
    "top_ff": 2422,
    "ntt_core_lut": 235,
    "ntt_core_ff": 191,
    "ntt_core_slice": 96,
}

# 聚焦展示的算法族
FOCUS_PREFIX = ("ML-KEM", "ML-DSA")


def load_summary() -> list[dict]:
    """读取最新的 summary-*.csv, 返回 [{alg, op, time_us}]"""
    csvs = sorted(RAW.glob("summary-*.csv"))
    if not csvs:
        return []
    rows = []
    with open(csvs[-1], newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            rows.append(
                {
                    "alg": r["alg"],
                    "op": r["op"],
                    "time_us": float(r["time_us"]),
                }
            )
    return rows


def load_tvla() -> list[dict]:
    """读取全部 TVLA JSON, 返回按 (suite, mode) 排序的列表"""
    jsons = sorted(RAW.glob("ntt-toggle-tvla-*.json"))
    out = []
    for p in jsons:
        try:
            out.append(json.loads(p.read_text(encoding="utf-8")))
        except json.JSONDecodeError:
            continue
    return out


def fmt_latency_table(rows: list[dict], alg_prefixes: tuple[str, ...]) -> str:
    """生成聚焦算法族的延迟表 (Markdown)"""
    focus = [r for r in rows if r["alg"].startswith(alg_prefixes)]
    if not focus:
        return "_(暂无数据)_\n"
    algs = sorted(set(r["alg"] for r in focus))
    ops = sorted(set(r["op"] for r in focus))
    header = "| 算法 | " + " | ".join(ops) + " |"
    sep = "|---" + "|".join("---" for _ in ops) + "|"
    lines = [header, sep]
    for a in algs:
        cells = []
        for op in ops:
            hit = next((r for r in focus if r["alg"] == a and r["op"] == op), None)
            cells.append(f"{hit['time_us']:.2f}" if hit else "—")
        lines.append(f"| {a} | " + " | ".join(cells) + " |")
    return "\n".join(lines) + "\n"


def fmt_tvla_table(tvla: list[dict]) -> str:
    if not tvla:
        return "_(暂无数据)_\n"
    lines = [
        "| 套件 | 模式 | TVLA |t| | ADLA A² | 结果 |",
        "|---|---|---|---|---|",
    ]
    for t in tvla:
        mode = t.get("mode", "—")
        s = t["stats"]
        res = f"{s['tvla_result']}/{s['adla_result']}"
        lines.append(
            f"| {t['suite']} | {mode} | {s['tvla_t']:.3f} | {s['adla_a2']:.3f} | {res} |"
        )
    return "\n".join(lines) + "\n"


def quarter_of(d: date) -> str:
    q = (d.month - 1) // 3 + 1
    return f"{d.year}Q{q}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quarter", help="报告季度标签, 如 2026Q3 (默认当前季度)")
    args = ap.parse_args()

    rows = load_summary()
    tvla = load_tvla()

    if not rows:
        print("!! 无 summary CSV — 先跑 scripts/analyze.py 生成")
        return 1

    today = date.today()
    quarter = args.quarter or quarter_of(today)
    REPORTS.mkdir(parents=True, exist_ok=True)
    out = REPORTS / f"benchmark-{quarter}.md"

    focus_lines = fmt_latency_table(rows, FOCUS_PREFIX)
    tvla_lines = fmt_tvla_table(tvla)

    total_alg = len(set(r["alg"] for r in rows))

    report = f"""# pqc-hw-bench 基准报告 — {quarter}

> 生成日期: {today.isoformat()} · 数据版本: 见各原始文件 `commit` 字段

## 1. 概述

本报告汇总 PQC 硬件加速的算力效率基准测试结果, 统一方法测量
ML-KEM / ML-DSA 在 FPGA 与 CPU 上的延迟、吞吐、资源与能效,
并量化为「每美元算力 / 每瓦特性能」的经济成本模型。

- CPU 基线算法总数: **{total_alg}** 个 (liboqs 0.16.0 AVX2)
- FPGA 目标: Artix-7 35T, NTT 专用加速器
- 预硅功耗评估: 双模式 (fwd/inv) TVLA/ADLA

## 2. CPU 软件基线 (liboqs 0.16.0 AVX2, 均值 μs/op)

聚焦 NIST 标准化算法族 (FIPS 203/204):

{focus_lines}

> 完整算法清单 (含 Classic-McEliece/Falcon/FrodoKEM/HQC/Kyber/NTRU/MAYO/cross/sntrup)
> 见 `results/raw/summary-*.csv`。

## 3. FPGA 硬件 (Artix-7 35T, NTT 加速器)

| 指标 | 值 |
|---|---|
| 器件 | {HW['device']} |
| 工具 | {HW['tool']} |
| 时钟约束 | {HW['clock_mhz']:.0f} MHz |
| WNS (Setup) | **+{HW['wns_ns']} ns** (0 failing) |
| 可运行上限 | ~{HW['max_freq_mhz']:.0f} MHz |
| 顶层 LUT / FF | {HW['top_lut']} / {HW['top_ff']} |
| **NTT 核 LUT / FF** | **{HW['ntt_core_lut']} / {HW['ntt_core_ff']}** |

> 核级资源经 `report_utilization -cells u_ntt_core` 精确剥离。
> 复现: `cd hardware && vivado -mode batch -source scripts/build.tcl`

## 4. 预硅功耗 TVLA / ADLA (toggle-count 模型)

{tvla_lines}

> 方法详见 `docs/tvla-methodology.md`。HD (Hamming Distance) toggle 计数作为
> 动态功耗代用指标, Welch t-test (TVLA) + 两样本 Anderson-Darling (ADLA)。

## 5. 算力成本模型 (框架)

当前为框架阶段, 接入点见 `docs/cost-model.md` 与 `docs/metrics.md`:

- **$/Mops** = 芯片单价 ÷ (Mops/s) — 需真实芯片单价 (待调研)
- **W/Mops** = 功耗 ÷ 吞吐 — 需真实功耗数据 (待 ChipWhisperer/板级实测)

## 6. 局限与后续

- 跨平台对比仅 Artix-7 (Zynq/Virtex 待补)
- 真实功耗为估算 (HD toggle 模型), 未接板级实测
- 成本模型未接入真实芯片单价与功耗数据
"""
    out.write_text(report, encoding="utf-8")
    print(f"报告已生成: {out.relative_to(ROOT)}")
    print(f"  CPU 基线 {total_alg} 算法 · TVLA 套件 {len(tvla)} 个")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
