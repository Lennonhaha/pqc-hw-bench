# 层次资源报告 — 提取 ntt_core 核级资源 (用于 benchmark 对比)
puts "=== Instance-level utilization (u_ntt_core) ==="
open_project project/pqc_hw_bench.xpr
open_run impl_1
report_utilization -hierarchical -file reports/utilization_hier.txt
# 直接打印 u_ntt_core 的资源
set inst [get_cells u_ntt_core]
if {[llength $inst] > 0} {
    puts "u_ntt_core found"
    report_utilization -cells u_ntt_core -file reports/utilization_nttcore.txt
} else {
    puts "u_ntt_core NOT found (name changed?)"
    puts "Top-level instances:"
    puts [get_cells -hier -filter {PRIMITIVE_TYPE =~ "*.LUT*"} -quiet]
}
puts "=== Done ==="
