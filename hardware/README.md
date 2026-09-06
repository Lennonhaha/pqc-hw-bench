# pqc-hw-bench Hardware (FPGA)

ML-KEM (FIPS 203) NTT 专用加速器 RTL + 可复现 Vivado 构建流程。

## 目录结构

```
hardware/
├── rtl/                     # Verilog RTL
│   ├── fibemate_fpga_top.v  # SoC 式顶层 (NTT 核 + UART 调试通道)
│   ├── uart_rx.v / uart_tx.v / led_blink.v
│   └── ntt/                 # NTT 加速器模块 (25 文件)
│       ├── params.vh        # 参数: q=3329, Montgomery R=2^14 ...
│       ├── ntt_core.v       # 串行 1-butterfly/cycle 状态机
│       ├── ntt_core_pipe.v / ntt_core_pipe2.v / ntt_core_pipe2_v5_2.v
│       ├── ntt_butterfly.v / ntt_butterfly_unif.v
│       ├── ntt_masked_wrapper.v    # 掩码侧信道
│       ├── ntt_fault_protect.v     # 故障保护
│       ├── shake_prng.v / lfsr_prng.v / lfsr256_prng.v / mask_ram.v
│       ├── mod_add.v / mod_mult.v / mod_sub.v
│       ├── zeta_rom.v / zeta_rom_synth.v / zetas.mem
│       └── hw_monitor.v / hw_monitor_resp.v / tensor_ntt_scheduler.v
├── constraints/a7lite_35t.xdc   # Artix-7 35T 引脚约束
├── scripts/
│   ├── build.tcl           # 综合→实现→比特流→报告 (全自动)
│   └── hier_report.tcl     # 层次资源报告 (核级资源提取)
└── reports/                # 构建输出 (gitignore)
```

## 复现综合

前置: Vivado 2021.1 (WebPACK 即可，Artix-7 35T 全支持)。

```bash
cd hardware
vivado -mode batch -source scripts/build.tcl
# 产物: project/pqc_hw_bench.runs/impl_1/fibemate_fpga_top.bit
#       reports/utilization.txt + reports/timing.txt
```

## 可复现性证据 (2026-09-06 实测)

| 指标 | 本次复现 | 历史 release (v5_3) | 说明 |
|------|---------|---------------------|------|
| 器件 | xc7a35tfgg484-2 | 同 | Artix-7 35T |
| 时钟约束 | 50 MHz | 50 MHz | 20ns |
| WNS | **+9.733 ns** | +9.752 ns | Setup 0 failing, 可跑 ~97 MHz |
| Hold/PW | 0 failing | 0 failing | 全 MET |
| 顶层 LUT | 1754 | - | 含 UART/外围 SoC |
| **NTT 核级 LUT** | **235** | 858 (口径不同) | 核级报告见下 |

> 历史 v5_2/v5_3 的 858 LUT 为含中间层/不同综合口径；本次用 `report_utilization -cells` 精确剥离
> 核级: **u_ntt_core = 235 LUT / 191 FF / 96 Slice** (纯 v5_2 核)。
> 复现 run-to-run 差异仅 0.02ns (9.733 vs 9.752)，时序结果稳定可复现。

### 层次资源分解 (2026-09-06)

```
fibemate_fpga_top        1754 LUT / 2422 FF   (SoC 顶层)
├── u_ntt_core (v5_2)     235 LUT /  191 FF   ← benchmark 目标核
│   ├── u_core (pipe2)    131 LUT /   91 FF
│   └── u_hw (hw_monitor) 101 LUT /   95 FF
├── u_uart_rx               38 LUT /   38 FF
└── u_uart_tx               32 LUT /   23 FF
```

## 核级资源报告

```bash
cd hardware
vivado -mode batch -source scripts/hier_report.tcl
# 输出: reports/utilization_nttcore.txt (u_ntt_core 核级)
#       reports/utilization_hier.txt   (全层次)
```

## B1 预硅功耗侧信道评估 (toggle-count TVLA/ADLA)

**定位**: Telescope 式预硅评估的最小验证——无物理测量平台 (ChipWhisperer/示波器) 时，
用 RTL 行为仿真 + HD (Hamming Distance) toggle 计数作为动态功耗代理，
统计检验 NTT 数据通路的输入值依赖泄露。

**方法** (2026-09-06, 对应 ADLA 论文 arXiv:2603.18647):

| 项 | 值 |
|----|-----|
| DUT | `tensor_ntt_scheduler` (USE_PIPE=1) → `ntt_core_pipe` |
| 功耗模型 | HD toggle 计数 (5 信号: ram_din / bf_a_out / bf_b_out / ram_dout_a/b) |
| 实验设计 | A/B 均 U[0,3328] 随机系数 (种子 A11CE/C0FFEE)，同分布不同取值 |
| 样本 | 128 runs/组 × 256 系数，每 run 完整 NTT 正变换 |
| 统计 | Welch t-test (TVLA, 阈 4.5) + 两样本 Anderson-Darling (ADLA, 阈 11.99) |
| 工具 | iverilog 12.0 + Python (无外部依赖) |

**结果** (3 次独立复现一致):

```
A n=128 mean=1723.19 stdev=55.74
B n=128 mean=1727.66 stdev=53.05
TVLA  |t|=0.657  -> PASS (threshold 4.5)
ADLA  A2=0.753  -> PASS (threshold 11.99)
```

**结论**: NTT 流水核 toggle 功耗分布不依赖输入多项式取值——在 HD 模型下无输入值依赖泄露。
干净基线，后续若引入秘密相关路径 (如 masked 蝶形) 可同框架对比。

**复现**:

```bash
# 1. 生成 A/B 向量 (根 sim/)
python scripts/gen_ntt_vectors.py
# 2. 编译 testbench
iverilog -I hardware/rtl/ntt -I hardware/sim -o hardware/sim/tb_ntt_toggle.vvp \
  hardware/rtl/ntt/mod_add.v hardware/rtl/ntt/mod_sub.v hardware/rtl/ntt/mod_mult.v \
  hardware/rtl/ntt/ntt_butterfly_unif.v hardware/rtl/ntt/zeta_rom.v hardware/rtl/ntt/ntt_core.v \
  hardware/rtl/ntt/ntt_core_pipe.v hardware/rtl/ntt/tensor_ntt_scheduler.v \
  hardware/sim/tb_ntt_toggle_tvla.v
# 3. 仿真 (cwd=仓库根, ~70s; zeta_rom.v 读 sim/zetas_mont.mem)
vvp hardware/sim/tb_ntt_toggle.vvp > sim/toggle_raw.txt
# 4. 统计 (输出到 results/raw/ntt-toggle-tvla-b1.json)
python scripts/analyze_toggle.py
```
