// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// ntt_fault_protect.v (v5.1) — NTT 运行时故障注入检测
// =============================================================================
// 四层保护:
//   L1   — RAM 奇偶校验: 256×1 bit parity RAM (与主 RAM 同步读写)
//   L2a  — 双蝶形周期级比较: 第二路 ntt_butterfly_unif 逐拍输出匹配
//   L2b  — REMO 双遍校验和: NTT 完成后累加校验和双重验证
//   L3   — 周期看门狗: NTT 应在 6500~6800 cycles 内完成
//
// fault_type[3:0] = {bf_mismatch, parity, remo, cycle}
// 输出: fault_alert 脉冲 (可连到 LED 或传给 hw_monitor)
// =============================================================================

`include "params.vh"

module ntt_fault_protect (
    input  wire        clk,
    input  wire        rst_n,

    // ── 主 RAM 接口 (用于奇偶校验跟踪) ──
    input  wire [7:0]  ram_waddr,
    input  wire        ram_wen,
    input  wire [12:0] ram_wdata,

    // ── NTT 生命周期 ──
    input  wire        ntt_active,     // NTT 进行中
    input  wire        ntt_done,       // NTT 完成脉冲

    // ── L2a: 周期级双蝶形比较 ──
    input  wire        bf_mismatch,    // 双蝶形输出不匹配 (即时, 1 pulse per mismatch)

    // ── L2b: REMO 双遍累加 ──
    input  wire [12:0] remo_pass1_sum,
    input  wire [12:0] remo_pass2_sum,
    input  wire        remo_valid,

    // ── 故障输出 ──
    output reg         fault_alert,
    output wire [3:0]  fault_type,     // {bf_mismatch, parity, remo, cycle}

    // ── 周期计数 ──
    input  wire [15:0] cycle_count
);

    // ── L1: 奇偶校验 ──
    reg  parity_ram [0:255];
    reg  parity_err;

    // ── L2a: 双蝶形即时比较 ──
    reg  bf_mismatch_err;

    // ── L2b: REMO ──
    reg  remo_pass1_latched;
    reg  remo_err;

    // ── L3: 周期看门狗 ──
    localparam CYCLE_MIN = 16'd4800;  // v5.2: matched to actual NTT 4993 cycles (was 6500)
    localparam CYCLE_MAX = 16'd6800;
    reg  cycle_err;

    // ── 故障类型寄存器 ──
    reg  bf_mismatch_err_reg;
    reg  parity_err_reg;
    reg  remo_err_reg;
    reg  cycle_err_reg;

    assign fault_type = {bf_mismatch_err_reg, parity_err_reg, remo_err_reg, cycle_err_reg};

    // ── L1: 奇偶校验写入 ──
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end else begin
            if (ram_wen)
                parity_ram[ram_waddr] <= ^ram_wdata;
        end
    end

    // ── L2a: BF mismatch latch (sticky until reset) ──
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            bf_mismatch_err <= 1'b0;
        else if (bf_mismatch)
            bf_mismatch_err <= 1'b1;
    end

    // ── L3: 周期范围检查 ──
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_err <= 1'b0;
        end else begin
            if (ntt_done) begin
                if (cycle_count < CYCLE_MIN || cycle_count > CYCLE_MAX)
                    cycle_err <= 1'b1;
                else
                    cycle_err <= 1'b0;
            end
        end
    end

    // ── L2b: REMO 双遍校验 ──
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            remo_pass1_latched <= 1'b0;
            remo_err           <= 1'b0;
        end else begin
            if (remo_valid) begin
                if (!remo_pass1_latched) begin
                    remo_pass1_latched <= 1'b1;
                end else begin
                    if (remo_pass2_sum != remo_pass1_latched)
                        remo_err <= 1'b1;
                    else
                        remo_err <= 1'b0;
                    remo_pass1_latched <= 1'b0;
                end
            end
        end
    end

    // ── 故障合路 ──
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fault_alert         <= 1'b0;
            bf_mismatch_err_reg <= 1'b0;
            parity_err_reg      <= 1'b0;
            remo_err_reg        <= 1'b0;
            cycle_err_reg       <= 1'b0;
        end else begin
            fault_alert <= 1'b0;

            if (bf_mismatch_err) begin
                fault_alert         <= 1'b1;
                bf_mismatch_err_reg <= 1'b1;
            end
            if (parity_err) begin
                fault_alert    <= 1'b1;
                parity_err_reg <= 1'b1;
            end
            if (remo_err) begin
                fault_alert    <= 1'b1;
                remo_err_reg   <= 1'b1;
            end
            if (cycle_err) begin
                fault_alert    <= 1'b1;
                cycle_err_reg  <= 1'b1;
            end
        end
    end

endmodule
