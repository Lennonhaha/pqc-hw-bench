# Copyright 2026 Liu Tianhe (Lennonhaha)
# SPDX-License-Identifier: CERN-OHL-P-2.0
# =============================================================================
# Vivado 构建脚本 (Tcl) — E:\fpga\fibemate
# =============================================================================
# 用法：vivado -mode batch -source scripts/build.tcl
# 必须在项目根目录执行 (E:\fpga\fibemate)
# =============================================================================

set project_name    fibemate_fpga
set project_dir     [file normalize "."]
set part_name       xc7a35tfgg484-2
set top_module      fibemate_fpga_top

puts "Project dir: $project_dir"

# 删除旧项目
if {[file exists $project_dir/project]} {
    file delete -force $project_dir/project
}

# 创建项目
create_project -force $project_name $project_dir/project -part $part_name

# 添加源文件
# 手动指定文件列表（对齐 project_v5 成功合成记录），避免 ntt_core_pipe2_nobom.v 冲突
add_files -norecurse {
  rtl/ntt/params.vh
  rtl/ntt/hw_monitor.v
  rtl/ntt/hw_monitor_resp.v
  rtl/led_blink.v
  rtl/ntt/lfsr256_prng.v
  rtl/ntt/lfsr_prng.v
  rtl/ntt/mask_ram.v
  rtl/ntt/mod_add.v
  rtl/ntt/mod_mult.v
  rtl/ntt/mod_sub.v
  rtl/ntt/ntt_butterfly_unif.v
  rtl/ntt/ntt_core_pipe2.v
  rtl/ntt/ntt_core_pipe2_v5_2.v
  rtl/ntt/ntt_fault_protect.v
  rtl/ntt/ntt_masked_wrapper.v
  rtl/ntt/shake_prng.v
  rtl/ntt/zeta_rom_synth.v
  rtl/uart_tx.v
  rtl/fibemate_fpga_top.v
}

# 添加约束
add_files -fileset constrs_1 -norecurse constraints/a7lite_35t.xdc

# 设置顶层
set_property top $top_module [current_fileset]

# 综合
puts "\n========================================="
puts " Running Synthesis..."
puts "=========================================\n"
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "Synthesis status: $synth_status"

if {$synth_status ne "synth_design Complete!"} {
    puts "ERROR: Synthesis failed!"
    exit 1
}

# 实现
puts "\n========================================="
puts " Running Implementation..."
puts "=========================================\n"
launch_runs impl_1 -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "Implementation status: $impl_status"

if {$impl_status ne "route_design Complete!"} {
    puts "ERROR: Implementation failed!"
    exit 1
}

# 生成比特流
puts "\n========================================="
puts " Generating Bitstream..."
puts "=========================================\n"
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1

# 报告
open_run impl_1
report_utilization -file reports/utilization.txt
report_timing_summary -file reports/timing.txt

puts "\n========================================="
puts " BUILD COMPLETE"
puts " Bitstream: project/$project_name.runs/impl_1/$top_module.bit"
puts "=========================================\n"
