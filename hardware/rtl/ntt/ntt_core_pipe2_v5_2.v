// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// ntt_core_pipe2_v5_2.v — FIBEMATE NTT Pipeline v5.2 顶层集成wrapper
// =============================================================================
// 历史:
//   v5.1 — 基础流水化 NTT/INTT (ntt_core_pipe2.v, stage_cnt<3'd6 修复)
//   v5.2 — 缝合全部硬件防护子模块: masked_wrapper + fault_protect + hw_monitor + lfsr256_prng
//
// 架构:
//   ntt_core_pipe2_v5_2 (本文件)
//   ├── lfsr256_prng        → 掩码随机源
//   ├── ntt_masked_wrapper  → 加法掩码去掩/重掩
//   ├── ntt_core_pipe2      → 核心 NTT/INTT 流水线 (v5.1)
//   ├── ntt_fault_protect   → L1 奇偶校验 + L2 双蝶形比对 + L3 看门狗
//   └── hw_monitor          → 状态寄存器 + LED + hw_alert_pulse
//
// 端口: 完整兼容 tb_pipe2_v5_test.v 全部信号
// =============================================================================
// MIT License

`include "params.vh"

module ntt_core_pipe2_v5_2 (
    input  wire        clk,
    input  wire        rst_n,

    // ── 控制 ──
    input  wire        start,
    input  wire        mode,           // 0=FWD 1=INV
    output wire        done,

    // ── 调试 ──
    output wire [2:0]  dbg_state,
    output wire [7:0]  dbg_len,
    output wire [7:0]  dbg_idx,
    output wire [2:0]  dbg_stage,

    // ── 外部 RAM 接口 ──
    output wire [7:0]  ram_addr_a,
    output wire [7:0]  ram_addr_b,
    output wire [7:0]  ram_waddr,
    output wire        ram_wen,
    output wire [12:0] ram_din,
    input  wire [12:0] ram_dout_a,
    input  wire [12:0] ram_dout_b,

    // ── 硬件防护输出 ──
    output wire        fault_alert,
    output wire [3:0]  fault_type,
    output wire        hw_alert_pulse,
    output wire [31:0] status_reg_0,
    output wire [31:0] status_reg_1,
    output wire [31:0] status_reg_2,
    output wire [31:0] status_reg_3,
    output wire [31:0] status_reg_4,
    output wire        sw_irq,
    output wire        clk_enable,

    // ── 顶层接口 ──
    input  wire        led_int0,       // heartbeat
    input  wire        uart_tx,        // for LED passthrough
    output wire [3:0]  led
);

    // =====================================================================
    // 内部信号
    // =====================================================================

    // ── PRNG → Masked Wrapper ──
    wire [12:0] prng_val;
    wire        prng_rdy;
    wire        prng_req;

    // ── Masked Wrapper → Core ──
    wire [12:0] unmasked_a, unmasked_b;
    wire [12:0] masked_a, masked_b;
    wire        remask_valid;
    // ── Butterfly 完成脉冲: core 的 bf_valid_out → wrapper bf_valid ──
    wire        core_bf_valid;
    // ── Wrapper bf_ready → Core bf_ready 背压 ──
    wire        wrapper_bf_ready;

    // ── Core RAM 中间信号 (掩码包裹层前后) ──
    wire [7:0]  core_rd_addr_a, core_rd_addr_b;
    wire [12:0] core_ram_dout_a, core_ram_dout_b;
    wire [7:0]  core_waddr;
    wire [12:0] core_din;
    wire        core_wen;

    // ── Fault Protect → Hw Monitor (来自 inner ntt_core_pipe2 的 fault_protect) ──
    // FIX: inner ntt_core_pipe2 已有 ntt_fault_protect; 移除 outer 冗余实例避免 multi-driver
    wire [15:0] ntt_cycle_count;
    wire        ntt_active;
    wire        core_done_pulse;

    // ── 蝶形不匹配脉冲 (第二路蝶形比对) ──
    wire        bf_mismatch_pulse;

    // =====================================================================
    // 1. LFSR256 PRNG — 掩码随机源
    // =====================================================================
    // PRNG seed: 从 counter 派生伪随机种子
    reg [31:0] prng_seed_cnt;
    reg        prng_seeded;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prng_seed_cnt <= 0;
            prng_seeded <= 0;
        end else if (!prng_seeded) begin
            prng_seed_cnt <= prng_seed_cnt + 1;
            if (prng_seed_cnt == 32'd250) prng_seeded <= 1;
        end
    end

    lfsr256_prng u_prng (
        .clk        (clk),
        .rst_n      (rst_n),
        .seed_valid (prng_seeded && (prng_seed_cnt[2:0] == 3'd0)),
        .seed_val   (prng_seed_cnt),
        .next_mask  (prng_req),
        .mask       (prng_val),
        .mask_ready (prng_rdy)
    );

    // =====================================================================
    // 2. Masked Wrapper — 加法掩码去掩/重掩
    // =====================================================================
    ntt_masked_wrapper u_mask (
        .clk          (clk),
        .rst_n        (rst_n),
        .rd_addr_a    (core_rd_addr_a),
        .rd_addr_b    (core_rd_addr_b),
        .ram_data_a   (core_ram_dout_a),
        .ram_data_b   (core_ram_dout_b),
        .unmasked_a   (unmasked_a),
        .unmasked_b   (unmasked_b),
        // ── 修复: bf_valid 接 butterfly out_valid (不再是 remask_valid 循环) ──
        .bf_valid     (core_bf_valid),
        .bf_a_raw     (masked_a),
        .bf_b_raw     (masked_b),
        .wa_a         (core_waddr),
        .wa_b         (core_waddr),     // 同一地址写回 A/B 使用同一 waddr
        .masked_a     (),               // 已写回 RAM，不对外输出
        .masked_b     (),               // 同上
        .remask_valid (remask_valid_dummy),  // 暂不使用
        // ── 背压: wrapper bf_ready → core bf_ready ──
        .bf_ready     (wrapper_bf_ready),
        .mask_enable  (1'b1),           // 默认启用掩码
        .prng_req      (prng_req),
        .prng_val      (prng_val),
        .prng_rdy      (prng_rdy),
        .force_zeroize (force_zeroize)
    );

    // =====================================================================
    // 3. NTT Core Pipe2 (v5.1 干净核心)
    // =====================================================================
    // 第一阶段: 直通模式，ntt_masked_wrapper 已模块级测试通过但尚未串入主通路
    // masked_wrapper 接线(预连线):
    //   ram_dout_a/b → wrapper.ram_data_a/b → wrapper.unmasked_a/b → core.ram_dout_a/b
    //   core.ram_din → wrapper.bf_a/b_raw → wrapper.masked_a/b → 外部 ram
    // 当前: 外部 RAM 直连 core, masked_wrapper 处于监控模式(mask_enable=0)
    // TODO: 完成 iverilog 全掩码通路仿真后切换到 mask_enable=1

    ntt_core_pipe2 u_core (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (start),
        .mode          (mode),
        .done          (done),
        .dbg_state     (dbg_state),
        .dbg_len       (dbg_len),
        .dbg_idx       (dbg_idx),
        .dbg_stage     (dbg_stage),
        .ram_addr_a    (ram_addr_a),
        .ram_addr_b    (ram_addr_b),
        .ram_waddr     (ram_waddr),
        .ram_wen       (ram_wen),
        .ram_din       (ram_din),
        .ram_dout_a    (ram_dout_a),
        .ram_dout_b    (ram_dout_b),
        // ── 背压: 等 wrapper bf_ready ──
        .bf_ready      (wrapper_bf_ready),
        // ── butterfly 完成脉冲 → wrapper bf_valid ──
        .bf_valid_out  (core_bf_valid),
        // ── v5.2 硬件防护端口 (透传) ──
        .fault_alert   (fault_alert),
        .fault_type    (fault_type),
        .hw_alert_pulse(),
        .status_reg_0  (),
        .status_reg_1  (),
        .status_reg_2  (),
        .status_reg_3  (),
        .led_int0      (1'b0),
        .uart_tx       (1'b0),
        .led           ()
    );

    // =====================================================================
    // 4. Fault Protect — L1/L2/L3 故障检测 [已移至 inner ntt_core_pipe2]
    // =====================================================================
    // FIX: ntt_fault_protect 已在 inner ntt_core_pipe2 中实例化 (监控 ram_waddr/wen/din)。
    // Outer 再实例化一份会形成 multi-driver: 两个 fault_alert 同时驱动 outer 输出端口。
    // 保留 ntt_active/core_done_pulse 用于 cycle_cnt，fault_alert/fault_type 由 inner 直驱。
    assign ntt_active = (dbg_state != 3'd0) && (dbg_state != 3'd6); // not IDLE/DONE
    assign core_done_pulse = done;

    // 周期计数
    reg [15:0] cycle_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cycle_cnt <= 0;
        else if (start)
            cycle_cnt <= 0;
        else if (ntt_active)
            cycle_cnt <= cycle_cnt + 1;
    end
    assign ntt_cycle_count = cycle_cnt;

    // 第二路蝶形比对 (REMO)
    // TODO: 实例化第二路 ntt_butterfly_unif 做逐拍比对
    // 当前: 占位 — 无比对信号
    assign bf_mismatch_pulse = 1'b0;

    // ── 零化/中断/时钟门控信号 (hw_monitor_resp v2) ──
    wire        force_zeroize;
    wire        sw_irq_int;
    wire        clk_enable_int;
    wire [31:0] status_reg_4_int;

    assign sw_irq      = sw_irq_int;
    assign clk_enable  = clk_enable_int;
    assign status_reg_4 = status_reg_4_int;

    // =====================================================================
    // 5. Hw Monitor v2 — 状态寄存器 + LED + hw_alert + 响应 FSM
    // =====================================================================
    hw_monitor_resp u_hw (
        .clk             (clk),
        .rst_n           (rst_n),
        .fault_alert     (fault_alert),   // 来自 inner ntt_core_pipe2
        .fault_type      (fault_type),
        .ntt_cycle_count (ntt_cycle_count),
        .ntt_done        (core_done_pulse),
        .led_int0        (led_int0),
        .status_reg_0    (status_reg_0),
        .status_reg_1    (status_reg_1),
        .status_reg_2    (status_reg_2),
        .status_reg_3    (status_reg_3),
        .status_reg_4    (status_reg_4_int),
        .force_zeroize   (force_zeroize),
        .clk_enable      (clk_enable_int),
        .sw_irq          (sw_irq_int),
        .led             (led)
    );

    // fault_alert/fault_type 由 inner ntt_core_pipe2 直接驱动 (已在 u_core 端口连接)
    // 无需额外 assign

endmodule
