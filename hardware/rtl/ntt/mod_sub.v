// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// 模减器 (mod q = 3329, 组合逻辑) — shared by all butterfly units
// =============================================================================
`include "params.vh"


module mod_sub (
    input  wire [12:0] a,
    input  wire [12:0] b,
    output wire [12:0] result
);
    localparam Q = `NTT_Q;
    wire [13:0] diff_wide = {1'b0, a} - {1'b0, b};
    wire [13:0] diff_add  = diff_wide + Q;
    // if diff < 0, add q
    assign result = diff_wide[13] ? diff_add[12:0] : diff_wide[12:0];
endmodule