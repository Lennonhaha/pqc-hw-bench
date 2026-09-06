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
