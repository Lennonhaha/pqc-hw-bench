# pqc-hw-bench

**Post-Quantum Cryptography Hardware Acceleration — Compute Efficiency Benchmark**

后量子密码（PQC）硬件加速的算力效率基准测试框架：用统一方法论测量
ML-KEM / ML-DSA 在 FPGA 与 CPU 上的延迟、吞吐、资源利用与能效，
并量化为「每美元算力 / 每瓦特性能」的经济成本模型。

> FIBEMATE 生态独立研究项目。回答的问题：PQC 在真实硬件上跑多快、
> 比软件快多少、迁移要花多少钱。

## 为什么做这个

- 后量子 TLS 硬件加速器市场 2025 $1.2B → 2030E $4.16B (CAGR 28.2%)
- PQC 迁移由监管驱动（美/欧），「现在收集、以后解密」威胁迫在眉睫
- 算力金融化（CME 算力期货）使「每美元算力」成为可定价资产
- 现有基准框架（PQC-LEO 等）只覆盖 CPU/网络层，**FPGA 硬件加速器基准是空白**

## 四类产出

| 产出 | 内容 | 使用者 |
|---|---|---|
| 硬件效率基线 | Artix-7 FPGA 上 ML-KEM/ML-DSA 延迟(µs)、吞吐(ops/s)、功耗、资源(LUT/FF/DSP/BRAM) | 芯片/硬件工程师 |
| 软-硬鸿沟量化 | 同条件 CPU (liboqs AVX2) vs FPGA 对比 | CTO/系统架构师 |
| 算力成本模型 | 每美元算力、每瓦特性能，对接算力期货 | CFO/投资分析师 |
| 公平标尺 | 可复现框架，x86/ARM/FPGA/DPU 结果可直接对话 | PQC 社区/标准组织 |

## 目录结构

```
pqc-hw-bench/
├── README.md
├── LICENSE
├── requirements.txt
├── docs/
│   ├── metrics.md        # 指标定义（延迟/吞吐/资源/能效）
│   ├── setup.md          # 环境搭建（Vivado/liboqs/Python）
│   └── cost-model.md     # 经济模型
├── hardware/             # FPGA 硬件（基于 FIBEMATE NTT 加速器适配）
├── software/
│   ├── bench_sw.py       # CPU 基准（liboqs speed）
│   └── fpga_tester.py    # FPGA 通信测试（JTAG/UART）
├── scripts/
│   └── analyze.py        # 数据分析 + 图表
├── results/
│   ├── raw/              # 原始测量数据（JSON/CSV）
│   └── figures/          # 图表
└── reports/
    └── benchmark-YYYYQN.md
```

## 许可证（多许可证分层）

| 目录 | 许可证 |
|---|---|
| `hardware/` (Verilog RTL) | CERN-OHL-P-2.0（宽松硬件许可证，NLnet 认可） |
| `software/` + `scripts/` | MIT（与 liboqs / PQC-LEO 生态一致） |
| `docs/` + `reports/` | CC BY-SA 4.0 |
| 仓库整体 | 见各目录 LICENSE 声明 |

硬件 RTL 来自 FIBEMATE 项目（作者同源，文件级 SPDX 授权），
详见 `docs/provenance.md`。

## 路线图

- **阶段 1（2-3 周）框架搭建**: 指标定义 / CPU 软件基线 / 环境就绪
- **阶段 2（3-4 周）硬件集成**: NTT 性能计数器 / 上位机测试 / 数据采集
- **阶段 3（2-3 周）分析与发布**: 对比报告 / 经济模型 / 开源发布

## 相关项目

- [FIBEMATE](https://github.com/Lennonhaha/fibemate) — 后量子安全消息平台（RTL 来源）
- [PQC-LEO](https://github.com/crt26/PQC-LEO) — CPU/网络 PQC 基准框架（软件方法论参考）
- [liboqs](https://github.com/open-quantum-safe/liboqs) — C 基准实现来源

## 状态

🚧 项目启动中（2026-09-06）
