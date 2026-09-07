# 算力成本模型 (cost-model.md)

> 版本: v0.1 (2026-09-07) · 状态: 框架阶段 — 待接入真实数据

## 1. 目标

把 PQC 硬件加速的工程测量 (延迟/吞吐/资源/功耗) 量化为**经济成本**,
回答三个问题:

1. **每美元算力**: 花 1 美元能买到多少 Mops (每秒百万次操作)?
2. **每瓦特性能**: 每瓦功耗能支撑多少 Mops?
3. **迁移成本**: 从纯软件迁移到 FPGA 加速, 一笔 TLS 加速器部署要花多少钱?

## 2. 核心指标定义

| 指标 | 公式 | 单位 | 输入 |
|---|---|---|---|
| 吞吐 | `ops/s` | ops/s | latency_us 倒数 (流水线) 或实测 |
| **$/Mops** | `芯片单价 ÷ (Mops/s)` | USD/Mops | 芯片单价 + 吞吐 |
| **W/Mops** | `功耗 ÷ (Mops/s)` | W/Mops | 功耗 + 吞吐 |
| **ATP** (面积-时间积) | `(LUT + 0.5·FF + 180·DSP + 200·BRAM) × Latency` | LUT·μs | 资源报告 + 延迟 |

> ATP 权重来自 ParallelNTT 论文口径 (GLSVLSI 2025), 便于与学术数据对标。

## 3. 数据接入点 (哪些已就绪 / 哪些待补)

### 3.1 已就绪 (本地可算)

| 输入 | 来源 | 状态 |
|---|---|---|
| CPU 延迟 (285 算法) | `results/raw/summary-*.csv` | ✅ |
| FPGA 核级资源 (235 LUT/191 FF) | `hardware/reports/utilization_nttcore.txt` | ✅ |
| FPGA 时序 (WNS +9.733ns) | `hardware/reports/timing.txt` | ✅ |
| 功耗代用指标 (HD toggle) | `results/raw/ntt-toggle-tvla-*.json` | ✅ (仅相对值) |

### 3.2 待调研 (外部数据, 当前缺口)

| 输入 | 缺口 | 获取途径 |
|---|---|---|
| 芯片单价 | ❌ 无具体单价 | Artix-7 35T 分销价 (DigiKey/Mouser 公开报价) |
| FPGA 动态功耗 (mW) | ❌ 仅 toggle 相对值 | Vivado Power Report 或板级实测 |
| CPU 功耗 | ❌ 无 | 整机墙插功率计 或 TDP 标注 |
| 云实例时价 | ❌ 无 | AWS/阿里云 GPU/CPU 实例公开定价 |

## 4. 经济模型框架 (占位公式)

```
$ / Mops  =  芯片单价 (USD)   /   (吞吐 Mops/s)
W / Mops  =  功耗 (W)        /   (吞吐 Mops/s)

迁移年化成本 (TCO) =
    硬件采购 (单价 × 台数)
  + 功耗成本 (功耗 × 台数 × 年运行小时 × 电价)
  + 工程 NRE (一次性)
```

## 5. 市场锚点 (来自 docs/market-data.md)

- 后量子 TLS 硬件加速器市场: 2025 $1.2B → 2030E $4.16B (CAGR 28.2%)
- CME 算力期货上线 (2026-09-08) 使「每美元算力」成为可定价资产

## 6. 当前状态与下一步

**状态**: 框架已定义, 指标公式齐备, 但**未接入真实芯片单价与功耗数据**。

**下一步 (P1)**:
1. 调研 Artix-7 35T 分销单价 → 填入 $/Mops
2. Vivado Power Report 提取 NTT 核动态功耗 → 填入 W/Mops
3. 补齐跨平台 (Zynq/Virtex) 后做多器件成本曲线
