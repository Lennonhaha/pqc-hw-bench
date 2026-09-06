// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// ML-KEM NTT 统一蝶形单元 — Unif-BU v4 (正确数据/result 对齐)
// =============================================================================
//
// 核心对账:
//   数据路径: S0→S1→S2→S2b→S3→S4→S5→S6(输出) = 7 拍
//   乘法路径: S2b 给 mod_mult; mod_mult 2-cycle; 
//             result 在 S5 时钟沿产出(NB) → S5 不捕获
//             S6 时钟沿捕获 mul_res_reg ← 稳定一周期
//             S7 时钟沿使用 mul_res_reg 计算输出
//
// 为什么不能少? 
//   S3/S4 处 mod_mult.result 还未稳定(NB竞态), 必须等到 S6 再捕获.
//   数据同时需要对齐, 故总计 S0..S6 = 7 级寄存器, latency=7.
//
// =============================================================================
// MIT License


`include "params.vh"

module ntt_butterfly_unif (
    input  wire        clk, rst_n, mode,
    input  wire [12:0] a_in, b_in, z,
    input  wire        valid,
    output wire [12:0] a_out, b_out,
    output wire        out_valid
);

    // ═════════════ S0 ═════════════
    reg [12:0] a0, b0, z0; reg m0, v0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) {a0,b0,z0,m0,v0} <= 0;
        else        {a0,b0,z0,m0,v0} <= {a_in,b_in,z,mode,valid};
    end

    wire [12:0] diff;  mod_sub u_d (.a(b0), .b(a0), .result(diff));  // b - a (FIPS 203 GS Inverse 蠖峰舰)
    wire [12:0] sum_ab; mod_add u_s (.a(a0), .b(b0), .result(sum_ab));

    // ═════════════ S1 ═════════════
    reg [12:0] ms_a1, ms_b1, a1, s1; reg m1, v1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) {ms_a1,ms_b1,a1,s1,m1,v1} <= 0;
        else begin
            ms_a1 <= m0 ? diff : b0;
            ms_b1 <= z0;
            a1 <= a0; s1 <= sum_ab;
            m1 <= m0; v1 <= v0;
        end
    end

    // ═════════════ S2 ═════════════
    reg [12:0] ms_a2, ms_b2, a2, s2; reg m2, v2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) {ms_a2,ms_b2,a2,s2,m2,v2} <= 0;
        else begin
            ms_a2 <= ms_a1; ms_b2 <= ms_b1;
            a2 <= a1; s2 <= s1;
            m2 <= m1; v2 <= v1;
        end
    end

    // ═════════════ S2b: 三级寄存 → mod_mult ═════════════
    reg [12:0] m_a, m_b, a2b, s2b; reg m2b, v2b;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) {m_a,m_b,a2b,s2b,m2b,v2b} <= 0;
        else begin
            m_a <= ms_a2; m_b <= ms_b2;
            a2b <= a2; s2b <= s2;
            m2b <= m2; v2b <= v2;
        end
    end

    wire [12:0] mul_raw;
    mod_mult u_m (.clk(clk), .rst_n(rst_n), .a(m_a), .b(m_b), .valid(v2b), .result(mul_raw));

    // ═════════════ S3: 数据对齐 (不捕获 mul_raw) ═════════════
    reg [12:0] a3, s3; reg m3, v3;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) {a3,s3,m3,v3} <= 0;
        else        {a3,s3,m3,v3} <= {a2b,s2b,m2b,v2b};
    end

    // ═════════════ S4: 数据对齐 (不捕获 mul_raw) ═════════════
    reg [12:0] a4, s4; reg m4, v4;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) {a4,s4,m4,v4} <= 0;
        else        {a4,s4,m4,v4} <= {a3,s3,m3,v3};
    end

    // ═════════════ S5: 数据对齐 + 捕获 result ═════════════
    // 此时 mul_raw 已由 mod_mult 在一周期前产出(NB), 此处为稳定值
    reg [12:0] a5, s5, mul_res; reg m5, v5;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) {a5,s5,mul_res,m5,v5} <= 0;
        else        {a5,s5,mul_res,m5,v5} <= {a4,s4,mul_raw,m4,v4};
    end

    // ═════════════ S6: 输出 (组合 + 寄存) ═════════════
    wire [12:0] a_comb, b_comb;
    mod_add u_ao (.a(a5), .b(mul_res), .result(a_comb));
    mod_sub u_bo (.a(a5), .b(mul_res), .result(b_comb));

    reg [12:0] oa, ob; reg ov;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin oa<=0; ob<=0; ov<=0; end
        else if (v5) begin
            oa <= m5 ? s5 : a_comb;
            ob <= m5 ? mul_res : b_comb;
            ov <= 1'b1;
        end else ov <= 1'b0;
    end

    assign a_out=oa; assign b_out=ob; assign out_valid=ov;
endmodule