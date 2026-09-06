// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// LED 闪烁模块 — FPGA 版的 "Hello World"
// =============================================================================


module led_blink #(
    parameter CLK_FREQ  = 50_000_000,   // 时钟频率
    parameter BLINK_HZ  = 1             // 闪烁频率
) (
    input  wire clk,
    input  wire rst_n,
    output reg  led
);
    localparam COUNTER_MAX = CLK_FREQ / (2 * BLINK_HZ) - 1;
    reg [31:0] counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 0;
            led     <= 1'b0;
        end else if (counter >= COUNTER_MAX) begin
            counter <= 0;
            led     <= ~led;
        end else begin
            counter <= counter + 1;
        end
    end
endmodule