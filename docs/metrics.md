# 基准指标定义 (metrics.md)

版本: v0.1 (2026-09-06)
状态: 草案 — 待与 liboqs / PQC-LEO 口径对齐后定稿

## 1. 目标算法集（v0.1）

| 算法 | NIST 标准 | 安全级 | 操作 |
|---|---|---|---|
| ML-KEM-512 | FIPS 203 | 1 | keygen / encaps / decaps |
| ML-KEM-768 | FIPS 203 | 3 | keygen / encaps / decaps |
| ML-KEM-1024 | FIPS 203 | 5 | keygen / encaps / decaps |
| ML-DSA-44 | FIPS 204 | 2 | keygen / sign / verify |
| ML-DSA-65 | FIPS 204 | 3 | keygen / sign / verify |
| ML-DSA-87 | FIPS 204 | 5 | keygen / sign / verify |

## 2. 平台维度

| 平台 | 实现 | 说明 |
|---|---|---|
| x86-64 (AVX2) | liboqs 0.15+ | CPU 软件基线 |
| ARM (AArch64) | liboqs 0.15+ | 移动/边缘参照（可选） |
| Artix-7 FPGA | 本仓 hardware/ | NTT 加速器（当前仅 NTT 原语）|
| （未来）RISC-V / DPU | — | 扩展 |

## 3. 测量指标

### 3.1 延迟 (Latency)
- 单次操作耗时的**中位数**（µs），跑 N≥1000 次
- 必须报告: min / p50 / p95 / max
- 时钟源: CPU 用 TSC/clock_gettime；FPGA 用 cycle counter × 时钟周期

### 3.2 吞吐 (Throughput)
- ops/s（每操作吞吐）与 ops/s/W（能效吞吐）
- CPU: 单线程、无并发干扰；记录 CPU 型号 + 频率 + turbo 状态
- FPGA: 连续流水吞吐（非单发延迟倒数，注明是否流水）

### 3.3 资源利用率 (FPGA only)
- LUT / FF / DSP / BRAM（绝对数与器件总量百分比）
- 来源: Vivado `report_utilization`
- 记录器件型号与速度等级（如 xc7a35tfgg484-2）

### 3.4 功耗与能效
- FPGA: 静态 + 动态功耗估算（Vivado Power Report）或板级实测
- CPU: 整机墙功耗（可选，需功率计）或 TDP 标注
- 能效指标: ops/J、µJ/op、J/1000 ops

### 3.5 组合指标（经济模型输入）
- **LUT×延迟** (面积-时间积)
- **ATP** = (LUT + 0.5·FF + 180·DSP + 200·BRAM) × Latency
  （ParallelNTT 论文口径，便于对标学术数据）
- **$/Mops**: 芯片单价 ÷ (Mops/s)（硬件）+ 云实例时价（CPU）
- **W/Mops**: 功耗 ÷ 吞吐

## 4. 数据格式

统一 JSON Schema（v0.1），文件放 `results/raw/<platform>/<alg>-<op>-<date>.json`:

```json
{
  "schema": "pqc-hw-bench/result-v0.1",
  "platform": "artix7-35t | x86-64 | arm64",
  "impl": "liboqs-0.15.0 | fibemate-ntt-v5_2",
  "alg": "ML-KEM-768",
  "op": "keygen | encaps | decaps | sign | verify | ntt_fwd | ntt_inv",
  "unit": "us | ops/s | lut | ff | ...",
  "n_runs": 1000,
  "p50_us": 12.34,
  "p95_us": 13.56,
  "device": "xc7a35tfgg484-2",
  "clock_mhz": 50.0,
  "resources": {"lut": 858, "ff": 618, "dsp": 0, "bram": 0},
  "power_w": 0.15,
  "toolchain": "Vivado 2021.1 | gcc 13.2",
  "date": "2026-09-06",
  "notes": ""
}
```

## 5. 复现要求
- 每个数据点必须有完整环境描述（硬件/工具链/参数），否则不进正式报告
- 外部数据（论文/报告）只进 `docs/references.md`，标注来源与不可复现性
