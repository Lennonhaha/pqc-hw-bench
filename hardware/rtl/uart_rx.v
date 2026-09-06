// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// UART 接收器 — 8N1, 16x 过采样, 假启动位过滤
// =============================================================================
//
// 设计要点:
//   - 半 bit 周期采样 start bit 中心，过滤毛刺假启动
//   - 全 bit 周期采样 8 个数据位中心 (LSB first)
//   - 停止位校验 (rx=1 才输出 data_valid)
//   - data_valid 为单周期脉冲
// =============================================================================

module uart_rx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115_200
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        rx,          // RX 线
    output reg  [7:0]  data,        // 接收到的字节
    output reg         data_valid,  // 单周期脉冲
    output wire        busy         // 接收中标志
);
    localparam BIT_PERIOD = CLK_FREQ / BAUD_RATE;  // ~434

    localparam S_IDLE    = 3'd0;
    localparam S_START   = 3'd1;
    localparam S_RECEIVE = 3'd2;
    localparam S_STOP    = 3'd3;

    reg [2:0]  state;
    reg [2:0]  bit_idx;
    reg [15:0] bit_cnt;   // 最大 434, 16-bit 够用
    reg [7:0]  shift_reg;

    assign busy = (state != S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            bit_idx    <= 0;
            bit_cnt    <= 0;
            shift_reg  <= 0;
            data       <= 0;
            data_valid <= 0;
        end else begin
            data_valid <= 1'b0;  // 默认清零，仅在 STOP 成功时拉高

            case (state)
                S_IDLE: begin
                    if (rx == 1'b0) begin
                        state   <= S_START;
                        bit_cnt <= 0;
                    end
                end

                S_START: begin
                    // 等待半个 bit 周期，在 start bit 中心采样
                    if (bit_cnt < (BIT_PERIOD >> 1) - 1) begin
                        bit_cnt <= bit_cnt + 1;
                    end else begin
                        if (rx == 1'b0) begin  // 有效起始位
                            state   <= S_RECEIVE;
                            bit_idx <= 0;
                            bit_cnt <= 0;
                        end else begin  // 毛刺，返回 IDLE
                            state <= S_IDLE;
                        end
                    end
                end

                S_RECEIVE: begin
                    if (bit_cnt < BIT_PERIOD - 1) begin
                        bit_cnt <= bit_cnt + 1;
                    end else begin
                        bit_cnt   <= 0;
                        shift_reg[bit_idx] <= rx;  // LSB first
                        if (bit_idx < 7) begin
                            bit_idx <= bit_idx + 1;
                        end else begin
                            state <= S_STOP;
                        end
                    end
                end

                S_STOP: begin
                    if (bit_cnt < BIT_PERIOD - 1) begin
                        bit_cnt <= bit_cnt + 1;
                    end else begin
                        if (rx == 1'b1) begin  // 有效停止位
                            data       <= shift_reg;
                            data_valid <= 1'b1;
                        end
                        // 即使停止位无效也不锁存，静默丢弃
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
