// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// 模加器 (mod q = 3329, 组合逻辑) — shared by all butterfly units
// =============================================================================
`include "params.vh"


module mod_add (
    input  wire [12:0] a,
    input  wire [12:0] b,
    output wire [12:0] result
);
    localparam Q = `NTT_Q;
    wire [13:0] sum_wide = {1'b0, a} + {1'b0, b};
    wire [13:0] sum_sub  = sum_wide - Q;
    // if sum >= q, subtract q
    assign result = sum_sub[13] ? sum_wide[12:0] : sum_sub[12:0];
endmodule