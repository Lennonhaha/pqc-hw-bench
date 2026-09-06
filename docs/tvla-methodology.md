# 预硅功耗侧信道评估方法论（TVLA / ADLA）

<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

> 本文档定义 pqc-hw-bench 的**预硅（pre-silicon）功耗侧信道评估**方法：
> 在 RTL 仿真层面用 toggle-count 功耗模型 + 统计检验，探测硬件数据通路
> 是否存在**输入值依赖**的功耗泄露。B1 为单模式原型，B2+B3 为完整可复现
> 流水线（双模式 fwd/inv + 一键编排 + CI 回归门禁）。

## 1. 背景与定位

真实功耗侧信道测量需要物理平台（ChipWhisperer、示波器、电流探针等）。
本框架无物理平台，采用 **Telescope 式预硅评估**（Liu/Schaumont, ACM
AsiaCCS 2025）路径：RTL 行为仿真 + toggle 统计 + 统计检验。这不是物理
测量的替代，而是在**流片/上板前**尽早发现数据通路级值依赖泄露的低成本
筛选手段。

### 为什么 toggle count 能代理功耗

CMOS 动态功耗主项为 `P = α·C·V²·f`，其中 α（翻转率）正比于信号
Hamming Distance（HD）：`HD(v0, v1) = popcount(v0 ⊕ v1)`。因此每周期
累加关键数据通路信号的 HD，是动态功耗的标准代理（业界通用 HW/HD 模型）。

## 2. 评估对象与信号

| 项 | 值 |
|---|---|
| DUT | `tensor_ntt_scheduler`（USE_PIPE=1）→ `ntt_core_pipe` |
| 变换 | ML-KEM (FIPS 203) NTT：正变换（FWD）/ 逆变换（INV） |
| 素数域 | Z_q, q = 3329（13-bit 系数） |
| 监测信号 | 写回总线 `ram_din`、蝶形输出 `bf_a_out/bf_b_out`、RAM 读总线 `ram_dout_a/b` |

## 3. 实验设计（TVLA 问法）

标准 TVLA fixed-vs-random 测**秘密依赖**；本框架的 DUT 是公开数据
NTT 变换（ML-KEM 中 NTT 输入为多项式，可能含秘密系数）。因此采用
**同分布异值**设计：

- **A 组**：均匀伪随机系数 U[0, 3328]，种子 0xA11CE
- **B 组**：均匀伪随机系数 U[0, 3328]，种子 0xC0FFEE
- **问题**：两组输入**分布相同、取值不同**。若 toggle 计数分布出现显著
  差异 → 数据通路功耗**值依赖**（潜在泄露信号）；无差异 → 干净基线。

每组 N 次完整 NTT 变换，每次输出总 toggle 计数。仿真确定性（无噪声），
因此**组内 stdev 反映输入值多样性而非测量噪声**——这正是值依赖检测的
用武之地。

## 4. 统计检验

### 4.1 Welch t-test（TVLA 口径）

$$t = \frac{\bar{x}_A - \bar{x}_B}{\sqrt{s_A^2/n_A + s_B^2/n_B}}$$

判定：`|t| < 4.5` → PASS（业界 TVLA 惯例阈值，对应显著性 ≈ 3.4×10⁻⁶）。

### 4.2 两样本 Anderson-Darling（ADLA 口径）

TVLA 只比较均值，对**同均值异方差/异分布**盲区（shuffling/random jitter
防护可制造此类盲区）。ADLA 检验完整 CDF 相等（Mikulec/Breier/Hou,
arXiv 2603.18647, 2026）：

$$A^2 = \frac{1}{n_1 n_2} \sum_{i=1}^{n-1} \frac{(n M_i - n_1 i)^2}{i(n-i)}$$

其中 $M_i$ = A 组中 ≤ 合并排序样本第 i 个值的观测数。判定：
`A² < 11.99` → PASS（与 TVLA |t|>4.5 同显著性标定）。

## 5. 工具链与复现

| 组件 | 工具 |
|---|---|
| RTL 仿真 | iverilog 12.0（`hardware/sim/tb_ntt_toggle_tvla.v`） |
| 向量生成 | `scripts/gen_ntt_vectors.py` |
| 一键流水线 | `scripts/run_tvla_sim.py` |
| 统计分析 | `scripts/analyze_toggle.py`（纯 stdlib，无外部依赖） |

### 一键复现

```bash
# 完整测量（128 runs/组 × 2 模式）
python scripts/run_tvla_sim.py --runs 128 --mode fwd
python scripts/run_tvla_sim.py --runs 128 --mode inv

# CI 冒烟（32 runs/组）
python scripts/run_tvla_sim.py --ci --mode fwd
python scripts/run_tvla_sim.py --ci --mode inv
```

退出码：`0` = 全 PASS；`1` = 基础设施错误；`2` = 检出泄露（门禁失败）。

### 管道阶段

1. **gen**：`gen_ntt_vectors.py` 写 `sim/vectors_{A,B}.mem`（fwd）或
   `sim/inv/vectors_{A,B}.mem`（inv），ASCII hex，每行 256 系数
2. **compile**：iverilog 编译 testbench + 8 个 RTL 源（见脚本 RTL_SOURCES）
3. **sim**：vvp 输出 `TOGGLE <grp> <run> <count>` 到 `sim/toggle_raw.txt`
4. **analyze**：双统计量 → `results/raw/ntt-toggle-tvla-{fwd,inv}-b2b3.json`

## 6. CI 回归门禁

`.github/workflows/tvla-regression.yml`：push 触及 RTL/TVLA 管道文件时，
Ubuntu 安装 iverilog，跑 fwd + inv 双模式 `--ci` 冒烟。任何 FAIL（退出码 2）
使构建失败——防止 RTL 改动悄悄引入值依赖功耗泄露。

## 7. 结果解读

| 结果 | 含义 | 行动 |
|---|---|---|
| TVLA PASS + ADLA PASS | 数据通路 toggle 功耗与输入值无关（当前模型下无泄露） | 基线干净 |
| TVLA FAIL | 均值差异 → 强值依赖信号 | 查数据通路分支/乘加时序 |
| TVLA PASS + ADLA FAIL | 同均值异分布 → 疑似 shuffling/jitter 掩盖 | 深入 CDF 差异分析 |

**已知边界**（诚实声明）：
- HD toggle 模型不含静态功耗、电压/频率缩放、工艺偏差
- 只评估数据通路值依赖，不含电磁辐射/故障注入维度
- 预硅结果**不能替代**流片后的物理 TVLA 测量

## 8. 测量记录

| 日期 | 模式 | runs | TVLA \|t\| | ADLA A² | 结果 |
|---|---|---|---|---|---|
| 2026-09-06 | fwd (B1) | 128 | 0.657 | 0.753 | PASS/PASS |
| 2026-09-07 | fwd (B2) | 128 | 0.657 | 0.753 | PASS/PASS |
| 2026-09-07 | inv (B2) | 128 | 1.108 | 2.122 | PASS/PASS |

原始报告：`results/raw/ntt-toggle-tvla-{fwd,inv}-b2b3.json`。
