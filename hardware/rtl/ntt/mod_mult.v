// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// Montgomery 模乘器 — ML-KEM 专用 (q = 3329)
// =============================================================================
// 算法：Montgomery reduction for 13-bit modulus
//   1. t = a * b                    (26-bit 乘积)
//   2. m = (t * qinv) mod 2^14     (低 14-bit)
//   3. u = (t + m * q) >> 14       (Montgomery 归约)
//   4. if u >= q: u = u - q
//
// q   = 3329 = 0xD01
// qinv = -q^{-1} mod 2^14 = 3327
// 流水线: 2 周期
// =============================================================================


`include "params.vh"

module mod_mult (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [12:0] a,
    input  wire [12:0] b,
    input  wire        valid,
    output reg  [12:0] result
);

    localparam Q     = `NTT_Q;
    localparam Q_INV = `NTT_Q_INV;
    localparam SHIFT = `NTT_SHIFT;

    // ── Stage 1: 乘法 ──
    wire [25:0] t_raw;
    reg  [25:0] t;
    reg         valid_d1;

    assign t_raw = {13'b0, a} * {13'b0, b};   // 26-bit 乘积

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            t        <= 0;
            valid_d1 <= 0;
        end else begin
            t        <= t_raw;
            valid_d1 <= valid;
        end
    end

    // ── Stage 2: Montgomery 归约 ──
    wire [27:0] m_q;   // m * q

    // m = (t * Q_INV) mod 2^14
    wire [13:0] m = (t[13:0] * Q_INV[13:0]);   // 取低 14-bit

    // u = (t + m * q) >> 14
    assign m_q = {14'b0, m} * {15'b0, Q};

    wire [26:0] u_raw;
    assign u_raw = (t + m_q) >> SHIFT;

    // 修正: if u >= q, u = u - q
    wire [12:0] u_corrected;
    assign u_corrected = (u_raw >= Q) ? (u_raw - Q) : u_raw[12:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            result <= 0;
        else if (valid_d1)
            result <= u_corrected;
    end

endmodule