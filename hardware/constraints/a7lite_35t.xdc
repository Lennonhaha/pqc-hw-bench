# Copyright 2026 Liu Tianhe (Lennonhaha)
# SPDX-License-Identifier: CERN-OHL-P-2.0
# =============================================================================
# A7-Lite-35T ?????? (XDC) ???????? v4 ??BOARD_SETUP.md ??????
# =============================================================================
# ???: A7-Lite (??????) | ????? XC7A35T-2FGG484
#
# ??????: ?????? README.md ????????(U18=CLK, C12/B12/T21/U21=LED, B9/A9=UART)
# ??????: ?????Vivado ???????????FGG484 I/O
#
# ??? v4??5 (2026-06-22):
#   - ???: R4 ??U18?????50MHz ????????#   - LED[0:3]: K1/K2/L1/L6 ??C12/B12/T21/U21????????LED ?????#   - UART: M2/N2 ??B9/A9?????USB-JTAG ????????#   - ???: v4 ?????? BOARD_SETUP.md ??????????????????
#
# ??? v5??6 (2026-06-22):
#   - UART: B9/A9 ??M18/N20??MOD1 ???????????? ntt_debug_b[0:1]??#   - ???: B9/A9 ??PCB ?????FT4232H(USB-JTAG???)?????PMOD
#   - ??? CH340G ??????: TXD??20(FPGA RX)  RXD??18(FPGA TX)
# =============================================================================

# ???? ??? 50MHz ????  ???: kisek/fpga_a7-lite_led (GitHub) ??J19 (?????
set_property PACKAGE_PIN J19 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]

# LED: PMOD I/O: M18/R17/U20/V20
set_property PACKAGE_PIN M18 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]
set_property PACKAGE_PIN R17 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]
set_property PACKAGE_PIN U20 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]
set_property PACKAGE_PIN V20 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]

# UART: uart_tx → N19 (PMOD1 pin1, verified with external CH340 → COM6)
# uart_rx → T19 (PMOD1 pin2)
set_property PACKAGE_PIN N19 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]
set_property PACKAGE_PIN T19 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]

# ???? NTT ?????? A??3 pins, ????????? FGG484 I/O?????
set_property PACKAGE_PIN N17 [get_ports {ntt_debug_a[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_a[0]}]
set_property PACKAGE_PIN P17 [get_ports {ntt_debug_a[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_a[1]}]
set_property PACKAGE_PIN P19 [get_ports {ntt_debug_a[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_a[2]}]
set_property PACKAGE_PIN R19 [get_ports {ntt_debug_a[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_a[3]}]
set_property PACKAGE_PIN R18 [get_ports {ntt_debug_a[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_a[4]}]
set_property PACKAGE_PIN T18 [get_ports {ntt_debug_a[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_a[5]}]
set_property PACKAGE_PIN W21 [get_ports {ntt_debug_a[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_a[6]}]
set_property PACKAGE_PIN W22 [get_ports {ntt_debug_a[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_a[7]}]
set_property PACKAGE_PIN F13 [get_ports {ntt_debug_a[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_a[8]}]
set_property PACKAGE_PIN F14 [get_ports {ntt_debug_a[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_a[9]}]
set_property PACKAGE_PIN E13 [get_ports {ntt_debug_a[10]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_a[10]}]
set_property PACKAGE_PIN E14 [get_ports {ntt_debug_a[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_a[11]}]
set_property PACKAGE_PIN D14 [get_ports {ntt_debug_a[12]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_a[12]}]

# ???? NTT ?????? B?? pins??0:1]=UART???, [2:5]=LED????????
# [0:5] ???????????IOSTANDARD ?????DRC
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_b[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_b[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_b[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_b[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_b[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_b[5]}]
set_property PACKAGE_PIN V22 [get_ports {ntt_debug_b[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_b[6]}]
set_property PACKAGE_PIN W20 [get_ports {ntt_debug_b[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_b[7]}]
set_property PACKAGE_PIN H14 [get_ports {ntt_debug_b[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_b[8]}]
set_property PACKAGE_PIN G13 [get_ports {ntt_debug_b[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_b[9]}]
set_property PACKAGE_PIN C15 [get_ports {ntt_debug_b[10]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_b[10]}]
set_property PACKAGE_PIN D15 [get_ports {ntt_debug_b[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_b[11]}]
set_property PACKAGE_PIN B15 [get_ports {ntt_debug_b[12]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ntt_debug_b[12]}]

# ???? NTT ?????? ????
set_property PACKAGE_PIN D17 [get_ports ntt_done]
set_property IOSTANDARD LVCMOS33 [get_ports ntt_done]

# ---- 新增端口约束（修复 DRC NSTD-1/UCIO-1）----
# N19 unused (was conflicting with uart_tx)
# ntt_done_fwd -> W19 (adj接 V20/led[3])
set_property PACKAGE_PIN W19 [get_ports ntt_done_fwd]
set_property IOSTANDARD LVCMOS33 [get_ports ntt_done_fwd]
# ntt_done_inv -> Y18 (PMOD2 邻近)
set_property PACKAGE_PIN Y18 [get_ports ntt_done_inv]
set_property IOSTANDARD LVCMOS33 [get_ports ntt_done_inv]

# ---- ntt_debug_b[0:5] 缺 PACKAGE_PIN，补齐避免 UCIO-1 ----
# 注：这些是内部 debug 信号，用作占位，实际布线由 router 决定
set_property PACKAGE_PIN T20 [get_ports {ntt_debug_b[0]}]
set_property PACKAGE_PIN V18 [get_ports {ntt_debug_b[1]}]
set_property PACKAGE_PIN V19 [get_ports {ntt_debug_b[2]}]
set_property PACKAGE_PIN Y19 [get_ports {ntt_debug_b[3]}]
set_property PACKAGE_PIN AA18 [get_ports {ntt_debug_b[4]}]
set_property PACKAGE_PIN AA19 [get_ports {ntt_debug_b[5]}]

# ???? ?????? ????
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]

set_property MARK_DEBUG true [get_nets core_done]
set_property MARK_DEBUG true [get_nets u_ntt_core/u_core/fault_alert]
set_property MARK_DEBUG true [get_nets inv_pass_flag]
set_property MARK_DEBUG true [get_nets load_done]
set_property MARK_DEBUG true [get_nets boot_done_reg_n_0]
