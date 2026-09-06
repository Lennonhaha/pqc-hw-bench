# Copyright 2026 Liu Tianhe (Lennonhaha)
# SPDX-License-Identifier: CERN-OHL-P-2.0
# =============================================================================
# Vivado 烧录脚本 (Tcl) — 稳定版
# =============================================================================
# 用法：vivado -mode batch -source scripts/program.tcl
# =============================================================================

set top_module      fibemate_fpga_top
set bitstream_file  "project/fibemate_fpga.runs/impl_1/$top_module.bit"

puts "Connecting to hardware target..."
open_hw_manager
connect_hw_server -url localhost:3121

# 自动发现 target
set hw_targets [get_hw_targets *]
if {[llength $hw_targets] == 0} {
    puts "ERROR: No hardware targets found. Is FPGA powered and JTAG connected?"
    exit 1
}
puts "Found targets: $hw_targets"
current_hw_target [lindex $hw_targets 0]
open_hw_target

# 自动发现设备
set hw_devices [get_hw_devices]
puts "Detected devices: $hw_devices"
set device [lindex $hw_devices 0]
current_hw_device $device

# 刷新 + 烧录
refresh_hw_device -update_hw_probes false $device
puts "Programming device with $bitstream_file..."
set_property PROGRAM.FILE $bitstream_file $device
program_hw_devices $device

puts "\n========================================="
puts " PROGRAMMING COMPLETE"
puts " End of startup status: HIGH"
puts "=========================================\n"
