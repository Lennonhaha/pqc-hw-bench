// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// hw_monitor.v (v5.1) — 硬件安全监视器 (HW→SW 信号桥)
// =============================================================================
// 功能: 收集故障计数器、生成状态寄存器、驱动 LED/告警信号
//
// status_reg:
//   status_reg_0 [31:0] — fault_count(16) + alert_count(16)
//   status_reg_1 [31:0] — {bf_mismatch_errs(8), parity_errs(8), remo_errs(8), cycle_errs(8)}
//   status_reg_2 [31:0] — last_fault_cycle (低 16 bits)
//   status_reg_3 [31:0] — alert_count (32-bit copy)
//
// 输出: hw_alert_pulse (1 cycle), LED [3:0] = {heartbeat,fault,alert,pass}
// =============================================================================

module hw_monitor (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        fault_alert,
    input  wire [3:0]  fault_type,         // {bf_mismatch, parity, remo, cycle}
    input  wire [15:0] ntt_cycle_count,
    input  wire        ntt_done,

    input  wire        led_int0,           // heartbeat signal from top
    input  wire        uart_tx,            // UART TX for physical pin hunting

    output reg  [31:0] status_reg_0,
    output wire [31:0] status_reg_1,
    output reg  [31:0] status_reg_2,
    output reg  [31:0] status_reg_3,
    output reg         hw_alert_pulse,
    output reg  [3:0]  led                 // [0]=heartbeat|uart_tx [1]=fault [2]=alert [3]=pass
);

    reg [15:0] fault_count;
    reg [15:0] alert_count;
    reg [7:0]  bf_mismatch_errs;
    reg [7:0]  parity_errs;
    reg [7:0]  remo_errs;
    reg [7:0]  cycle_errs;
    reg [15:0] last_fault_cycle;

    // heartbeat counter
    reg [23:0] hb_cnt;
    wire hb_toggle;
    assign hb_toggle = (hb_cnt == 24'd12_000_000); // ~1Hz @ 25MHz/2

    assign status_reg_1 = {bf_mismatch_errs, parity_errs, remo_errs, cycle_errs};

    // uart_tx ORed into led[0] so any PMOD1 pin carrying UART lights the LED
    wire led0_combine;
    assign led0_combine = led_int0 | uart_tx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fault_count       <= 16'd0;
            alert_count       <= 16'd0;
            bf_mismatch_errs  <= 8'd0;
            parity_errs       <= 8'd0;
            remo_errs         <= 8'd0;
            cycle_errs        <= 8'd0;
            last_fault_cycle  <= 16'd0;
            hw_alert_pulse    <= 1'b0;
            hb_cnt            <= 24'd0;
            led               <= 4'b0000;
            status_reg_0      <= 32'd0;
            status_reg_2      <= 32'd0;
            status_reg_3      <= 32'd0;
        end else begin
            hw_alert_pulse <= 1'b0;

            // 心跳 + UART overlay on led[0]
            if (hb_cnt >= 24'd12_000_000) begin
                hb_cnt <= 24'd0;
                led[0] <= ~led[0] | uart_tx;  // XOR-like: heartbeat flips but UART wins
            end else begin
                hb_cnt <= hb_cnt + 1;
                led[0] <= led0_combine;
            end

            // 故障采集
            if (fault_alert) begin
                fault_count <= fault_count + 1;
                last_fault_cycle <= ntt_cycle_count;

                if (fault_type[3])  // bf_mismatch
                    bf_mismatch_errs <= bf_mismatch_errs + 1;
                if (fault_type[2])  // parity
                    parity_errs <= parity_errs + 1;
                if (fault_type[1])  // remo
                    remo_errs <= remo_errs + 1;
                if (fault_type[0])  // cycle
                    cycle_errs <= cycle_errs + 1;

                hw_alert_pulse <= 1'b1;
                alert_count    <= alert_count + 1;

                led[1] <= 1'b1;   // fault LED on
                led[3] <= 1'b0;   // pass LED off
            end

            // NTT 完成: 复位 pass/fault LEDs
            if (ntt_done) begin
                if (fault_count == 16'd0) begin
                    led[3] <= 1'b1;   // pass LED on
                    led[1] <= 1'b0;
                end
            end

            // 状态寄存器更新
            status_reg_0 <= {fault_count, alert_count};
            status_reg_2 <= {16'd0, last_fault_cycle};
            status_reg_3 <= {16'd0, alert_count};
        end
    end

endmodule
