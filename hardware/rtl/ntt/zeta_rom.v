// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// ML-KEM Zeta ROM — Montgomery-domain zetas (128 entries)
// =============================================================================
// Standard Kyber NTT/INTT: forward and inverse both use the SAME zeta table.
// FWD: k=1→127 (increasing), INV: k=127→1 (decreasing).
// No separate inverse zeta table is needed.
// =============================================================================


`include "params.vh"

module zeta_rom (
    input  wire        clk,
    input  wire [6:0]  addr,      // 0..127
    output reg  [12:0] data       // zeta[addr]
);
    reg [12:0] zeta_mem [0:127];

    initial begin
                $readmemh("sim/zetas_mont.mem", zeta_mem);
    end

    always @(posedge clk) begin
        data <= zeta_mem[addr];
    end

endmodule
