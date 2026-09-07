# pqc-hw-bench 基准报告 — 2026Q3

> 生成日期: 2026-09-07 · 数据版本: 见各原始文件 `commit` 字段

## 1. 概述

本报告汇总 PQC 硬件加速的算力效率基准测试结果, 统一方法测量
ML-KEM / ML-DSA 在 FPGA 与 CPU 上的延迟、吞吐、资源与能效,
并量化为「每美元算力 / 每瓦特性能」的经济成本模型。

- CPU 基线算法总数: **95** 个 (liboqs 0.16.0 AVX2)
- FPGA 目标: Artix-7 35T, NTT 专用加速器
- 预硅功耗评估: 双模式 (fwd/inv) TVLA/ADLA

## 2. CPU 软件基线 (liboqs 0.16.0 AVX2, 均值 μs/op)

聚焦 NIST 标准化算法族 (FIPS 203/204):

| 算法 | decaps | encaps | keygen | keypair | sign | verify |
|------|---|---|---|---|---|
| ML-DSA-44 | — | — | — | 407.37 | 794.03 | 100.64 |
| ML-DSA-44-extmu | — | — | — | 384.91 | 640.99 | 83.50 |
| ML-DSA-65 | — | — | — | 489.86 | 1048.22 | 158.35 |
| ML-DSA-65-extmu | — | — | — | 430.89 | 774.47 | 143.16 |
| ML-DSA-87 | — | — | — | 649.01 | 1095.29 | 248.95 |
| ML-DSA-87-extmu | — | — | — | 540.77 | 906.29 | 229.74 |
| ML-KEM-1024 | 76.53 | 461.85 | 406.77 | — | — | — |
| ML-KEM-512 | 34.81 | 327.55 | 278.91 | — | — | — |
| ML-KEM-768 | 47.12 | 379.74 | 345.35 | — | — | — |


> 完整算法清单 (含 Classic-McEliece/Falcon/FrodoKEM/HQC/Kyber/NTRU/MAYO/cross/sntrup)
> 见 `results/raw/summary-*.csv`。

## 3. FPGA 硬件 (Artix-7 35T, NTT 加速器)

| 指标 | 值 |
|---|---|
| 器件 | xc7a35tfgg484-2 (Artix-7 35T) |
| 工具 | Vivado 2021.1 (WebPACK) |
| 时钟约束 | 50 MHz |
| WNS (Setup) | **+9.733 ns** (0 failing) |
| 可运行上限 | ~97 MHz |
| 顶层 LUT / FF | 1754 / 2422 |
| **NTT 核 LUT / FF** | **235 / 191** |

> 核级资源经 `report_utilization -cells u_ntt_core` 精确剥离。
> 复现: `cd hardware && vivado -mode batch -source scripts/build.tcl`

## 4. 预硅功耗 TVLA / ADLA (toggle-count 模型)

| 套件 | 模式 | TVLA |t| | ADLA A² | 结果 |
|---|---|---|---|---|
| ntt-toggle-tvla-b1 | — | -0.657 | 0.753 | PASS/PASS |
| ntt-toggle-tvla-fwd | fwd | -0.657 | 0.753 | PASS/PASS |
| ntt-toggle-tvla-inv | inv | 1.108 | 2.122 | PASS/PASS |


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
