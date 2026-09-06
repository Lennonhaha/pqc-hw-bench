// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// ML-KEM NTT 双向蝶形运算单元 — Forward + Inverse (2026-05-18)
// =============================================================================
//
// mode=0 (Forward, Cooley-Tukey):
//   A' = A + z * B   (mod q)
//   B' = A - z * B   (mod q)
//
// mode=1 (Inverse, Gentleman-Sande):
//   A' = A + B        (mod q)
//   B' = z * (B - A)  (mod q)    ← 使用 FORWARD zeta，不取逆！
//
// Pipeline (4-cycle latency):
//   S0: 输入打拍 (a_r, b_r, z_r, mode_r, valid_r)
//   S1: mod_mult S1 / a_fwd_d1 / sum_d0
//   S2: mod_mult S2 / a_fwd_d2 / sum_d1
//   S3: 计算 + 输出 (a_fwd_d3 / sum_d2 对齐 mod_mult result)
//   S4: 寄存器输出
//
// 参考: kyber-py / FIPS 203 Algorithm 5 & 6
// =============================================================================
// MIT License


`include "params.vh"

module ntt_butterfly (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        mode,         // 0=Forward NTT, 1=Inverse NTT
    input  wire [12:0] a_in,
    input  wire [12:0] b_in,
    input  wire [12:0] z,            // zeta (forward zeta, shared by both modes)
    input  wire        valid,
    output wire [12:0] a_out,        // A' 输出
    output wire [12:0] b_out,        // B' 输出
    output wire        out_valid     // 输出有效 (延迟 4 周期)
);

    // ── S0: 输入寄存器 ──
    reg [12:0] a_r, b_r, z_r;
    reg        mode_r;
    reg        valid_r, valid_r1, valid_r2, valid_r3;
    reg        mode_r1,  mode_r2,  mode_r3;

    // ── Forward 数据路径 ──
    reg [12:0] a_fwd_d1, a_fwd_d2, a_fwd_d3;   // A 对齐延迟
    wire [12:0] bw_fwd;                          // z * B (mod_mult output)

    // ── Inverse 数据路径 ──
    reg  [12:0] sum_d0, sum_d1, sum_d2;          // A + B 对齐延迟
    wire [12:0] bw_inv;                           // z * (B-A) (mod_mult output)

    // ── mod_mult: 输入根据 mode 切换 ──
    // Forward: mod_mult(B, z)    Inverse: mod_mult(B-A, z)
    wire [12:0] diff_b_minus_a;  // B - A
    wire [12:0] mul_a = mode_r ? diff_b_minus_a : b_r;
    wire [12:0] mul_b = z_r;
    wire [12:0] mul_result;

    // ── 组合逻辑: 差与和 (延迟 0) ──
    mod_sub u_diff_mod (
        .a     (b_r),
        .b     (a_r),
        .result(diff_b_minus_a)
    );

    wire [12:0] sum_ab;
    mod_add u_sum_mod (
        .a     (a_r),
        .b     (b_r),
        .result(sum_ab)
    );

    // ── 组合逻辑: Forward 输出 ──
    wire [12:0] a_fwd_out, b_fwd_out;
    mod_add u_fwd_add (.a(a_fwd_d3), .b(mul_result), .result(a_fwd_out));
    mod_sub u_fwd_sub (.a(a_fwd_d3), .b(mul_result), .result(b_fwd_out));

    // ── mod_mult 实例化 ──
    mod_mult u_mul (
        .clk   (clk),
        .rst_n (rst_n),
        .a     (mul_a),
        .b     (mul_b),
        .valid (valid_r),
        .result(mul_result)
    );

    // ── 主流水线 ──
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_r  <= 0; b_r <= 0; z_r <= 0; mode_r  <= 0;
            valid_r <= 0; valid_r1 <= 0; valid_r2 <= 0; valid_r3 <= 0;
            mode_r1 <= 0; mode_r2  <= 0; mode_r3  <= 0;
            a_fwd_d1 <= 0; a_fwd_d2 <= 0; a_fwd_d3 <= 0;
            sum_d0 <= 0; sum_d1 <= 0; sum_d2 <= 0;
        end else begin
            // S0: 输入打拍
            a_r    <= a_in;
            b_r    <= b_in;
            z_r    <= z;
            mode_r <= mode;
            valid_r <= valid;

            // 控制流水线
            valid_r1 <= valid_r;
            valid_r2 <= valid_r1;
            valid_r3 <= valid_r2;
            mode_r1  <= mode_r;
            mode_r2  <= mode_r1;
            mode_r3  <= mode_r2;

            // S1-S3: Forward 数据路径 (A 打 3 拍对齐 mod_mult 延迟)
            a_fwd_d1 <= a_r;
            a_fwd_d2 <= a_fwd_d1;
            a_fwd_d3 <= a_fwd_d2;

            // S1-S3: Inverse 数据路径 (sum = A+B 打 3 拍对齐 mod_mult 延迟)
            sum_d0   <= sum_ab;
            sum_d1   <= sum_d0;
            sum_d2   <= sum_d1;
        end
    end

    // ── 输出寄存器 ──
    reg [12:0] out_a, out_b;
    reg        out_v;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_a <= 0; out_b <= 0; out_v <= 0;
        end else begin
            if (valid_r3) begin
                if (!mode_r3) begin
                    out_a <= a_fwd_out;
                    out_b <= b_fwd_out;
                end else begin
                    out_a <= sum_d2;
                    out_b <= mul_result;
                end
                out_v <= 1'b1;
            end else begin
                out_v <= 1'b0;
            end
        end
    end

    assign a_out     = out_a;
    assign b_out     = out_b;
    assign out_valid = out_v;

endmodule


// =============================================================================
// 模加器 (mod q = 3329, 组合逻辑)
// =============================================================================
module mod_add (
    input  wire [12:0] a,
    input  wire [12:0] b,
    output wire [12:0] result
);
    localparam Q = 13'd3329;
    wire [13:0] sum_wide = {1'b0, a} + {1'b0, b};
    wire [13:0] sum_sub  = sum_wide - Q;
    // if sum >= q, subtract q
    assign result = sum_sub[13] ? sum_wide[12:0] : sum_sub[12:0];
endmodule


// =============================================================================
// 模减器 (mod q = 3329, 组合逻辑)
// =============================================================================
module mod_sub (
    input  wire [12:0] a,
    input  wire [12:0] b,
    output wire [12:0] result
);
    localparam Q = 13'd3329;
    wire [13:0] diff_wide = {1'b0, a} - {1'b0, b};
    wire [13:0] diff_add  = diff_wide + Q;
    // if diff < 0, add q
    assign result = diff_wide[13] ? diff_add[12:0] : diff_wide[12:0];
endmodule