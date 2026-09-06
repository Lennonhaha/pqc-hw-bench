# hardware/ 资产来源与许可追溯 (Provenance)

## 来源

`hardware/` 目录下的 Verilog RTL 源自 FIBEMATE 项目主仓库
（https://github.com/Lennonhaha/fibemate，GPL-3.0-only 整体许可）
的 `fpga/rtl/` 与 `fpga/constraints/`、`fpga/scripts/` 子目录。

## 许可追溯要点

FIBEMATE 主仓 `fpga/rtl/` 下 26 个 Verilog 文件，19 个文件头已声明：

```verilog
// Copyright 2026 FIBEMATE
// SPDX-License-Identifier: MIT
```

7 个文件无 SPDX 头（ntt_core.v / hw_monitor_resp.v / ntt_butterfly.v /
lfsr256_prng.v / ntt_masked_wrapper.v / shake_prng.v /
fibemate_fpga_vio_wrapper.v）。

**关键法律事实**：
1. FIBEMATE 全部代码由本项目作者（刘天和 / Lennonhaha / liuguowei1983）
   独立编写，无第三方贡献者。
2. 文件级 `SPDX-License-Identifier: MIT` 是作者对单文件的明确授权声明。
   根据 SPDX 规范与版权法，文件级许可证头可独立于仓库级许可证成立。
3. 作者将本仓库 `hardware/` 下文件**重新授权为 CERN-OHL-P-2.0**
   （作者对自有版权作品的再授权，合法且无争议）。

## 决策记录

| 日期 | 决策 |
|---|---|
| 2026-09-06 | 作者（刘天和）决定：从 FIBEMATE 主仓提取 NTT 加速器 RTL，作为独立项目 pqc-hw-bench 的 hardware/ 资产，重新授权为 CERN-OHL-P-2.0 |

## 提取清单（待执行）

从主仓拷贝至本仓库时逐文件核对：
- [ ] fpga/rtl/ntt/*.v（21 个）→ hardware/rtl/ntt/
- [ ] fpga/rtl/fibemate_fpga_top.v → hardware/rtl/
- [ ] fpga/rtl/uart_*.v / led_blink.v → hardware/rtl/ (如需)
- [ ] fpga/constraints/a7lite_35t.xdc → hardware/constraints/
- [ ] fpga/scripts/build.tcl → hardware/scripts/

每个文件头改为：

```verilog
// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
```

## 原主仓参考

- 主仓提交: 见 FIBEMATE fpga/ 目录 git 历史
- 器件: XC7A35T-FGG484-2 (Artix-7)
- 参考报告: 主仓 fpga/releases/v4/（timing/utilization .rpt）
