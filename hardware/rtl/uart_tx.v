// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// UART 发送器 — 8N1, 可配置波特率
// =============================================================================


module uart_tx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115_200
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  data,       // 待发送字节
    input  wire        send,       // 发送脉冲 (1 clk)
    output reg         tx,         // TX 线
    output reg         idle        // 空闲标志
);
    localparam BIT_PERIOD = CLK_FREQ / BAUD_RATE;

    reg [31:0] bit_cnt;
    reg [3:0]  bit_idx;      // 0=start, 1-8=data, 9=stop
    reg [7:0]  tx_data;      // 锁存的数据

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx       <= 1'b1;   // 空闲高电平
            idle     <= 1'b1;
            bit_cnt  <= 0;
            bit_idx  <= 0;
            tx_data  <= 0;
        end else begin
            if (idle && send) begin
                idle    <= 1'b0;
                tx_data <= data;
                bit_cnt <= 0;
                bit_idx <= 0;
                tx      <= 1'b0;   // 起始位
            end else if (!idle) begin
                if (bit_cnt < BIT_PERIOD - 1) begin
                    bit_cnt <= bit_cnt + 1;
                end else begin
                    bit_cnt <= 0;
                    if (bit_idx < 8) begin
                        bit_idx <= bit_idx + 1;
                        tx      <= tx_data[bit_idx];  // 数据位 LSB first
                    end else if (bit_idx == 8) begin
                        bit_idx <= bit_idx + 1;
                        tx      <= 1'b1;   // 停止位
                    end else begin
                        idle  <= 1'b1;
                        tx    <= 1'b1;
                    end
                end
            end
        end
    end

endmodule