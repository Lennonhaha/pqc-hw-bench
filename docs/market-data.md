# 市场数据与来源 (Market Data & Sources)

> 本文件记录 pqc-hw-bench README 与报告中引用的市场数据及其出处。
> 原则：每条数据可溯源，不虚构。货币主用 USD，国内场景括号标注 CNY（汇率 ~7.18）。

## 1. 后量子 TLS 硬件加速器市场

| 数据 | 值 | 出处 |
|------|-----|------|
| 2025 年市场规模 | $1.2B | Research and Markets: "Post-Quantum Cryptography (TLS) Hardware Acceleration Market" |
| 2030E 市场规模 | $4.16B | 同上 |
| CAGR | 28.2% | 同上 |

**状态**: 二手市场研究报告数据（付费报告摘要），引用时标注来源与年份，供趋势参考非精确预测。

## 2. PQC 迁移监管驱动

| 数据 | 值 | 出处 |
|------|-----|------|
| NIST 迁移要求 | 2030 前完成联邦系统 PQC 迁移 | NIST IR 8547 (2024-11) transition roadmap |
| 美国行政令 | EO 14411 (2025-08) | "Strengthening and Promoting Innovation in the Nation's Cybersecurity" |
| 欧盟 | CSA (Cyber Resilience Act) / ETSI | 欧盟委员会网络安全立法框架 |

**状态**: 公开官方文件可核验。EO 14411 原文 whitehouse.gov 可查。

## 3. "现在收集、以后解密" (HNDL)

| 数据 | 值 | 出处 |
|------|-----|------|
| HNDL 列为国家安全威胁 | NSM-10 (2025-07) | 美国国家安全备忘录 10 (National Security Memorandum on Promoting U.S. Leadership in Quantum Computing) |
| 归因 | 敌手收集密文待量子计算机破解 | 同上 |

**状态**: 官方文件，whitehouse.gov 可查。

## 4. CME 算力期货

| 数据 | 值 | 出处 |
|------|-----|------|
| GPU 算力期货上线 | 2026-09-08 | CME Group 公告 |
| 合约标的 | 算力 (H100 等效小时) | CME Hashprice / compute futures 系列 |

**状态**: CME 官网公告可查。算力期货为成本模型提供市场化定价锚点。

## 5. 竞品/相关框架定位

| 项目 | 定位 | 来源 |
|------|------|------|
| PQC-LEO | x86/ARM 软件 + TLS 基准，**不覆盖 FPGA** | arXiv:2603.06149, IEEE TPS-ISA 2025 |
| pqm4 | Cortex-M4 嵌入式 PQC 基准 | github.com/mupq/pqm4 |
| PQC-HA | TaPaSCo + HLS 硬件加速器 | 学术论文 (HLS 路径) |
| ParallelNTT | Artix-7 NTT 加速器 (GLSVLSI 2025) | 学术论文 |

**状态**: 各项目仓库/论文可核验。

## 6. 方法论参照（行业碎片化证据）

| 引用 | 要点 | 出处 |
|------|------|------|
| 2026 PQC 基准综述 | 测试方法/平台/指标多样 → 结果不可比 | 综述论文 (见 docs/research.md) |
| ML-DSA 基准研究 | 拒绝采样致执行时间方差 → 需最坏情况指标 | 学术论文 (见 docs/research.md) |
| 能效缺口 | 功耗/能效指标报告不足 | 2026 IoT PQC 综述 |

---

## 使用规范

1. **报告中引用格式**: `[数据] (来源, 年份)`，详细来源列本文件。
2. **货币**: 主用 USD；国内/政企场景括号标 CNY（汇率 7.18 为 2026-09 参考值，注明日期）。
3. **市场预测数据**: 属二手研究，标注 "据 Research and Markets 2025 报告" 而非绝对事实。
4. **本文件同步维护**: 新增引用必先加出处，禁止无源数据进 README/报告。
