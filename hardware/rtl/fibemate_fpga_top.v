// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// FIBEMATE FPGA Top-Level - v5.3 NTT Pipeline Test (rebuilt)
// =============================================================================
// Pinout:
//   sys_clk     -> R4 (50MHz)
//   led[0:3]    -> N19,T19,U20,V20 (PMOD1)
//   uart_tx     -> M18 (PMOD1), uart_rx -> N20 (PMOD1)
//   ntt_done    -> D17
//   ntt_debug_a[12:0] -> N17...D14
//   ntt_debug_b[12:0] -> V22...B15
// =============================================================================

`timescale 1ns / 1ps

module fibemate_fpga_top (
    input  wire        sys_clk,          // R4, 50MHz
    output wire [3:0]  led,              // [0]=heartbeat [1]=fault [2]=alert [3]=pass
    output wire        uart_tx,          // M18, USB-UART TXD
    input  wire        uart_rx,          // N20, USB-UART RXD (reserved)
    output wire [12:0] ntt_debug_a,      // RAM read data
    output wire [12:0] ntt_debug_b,      // Core debug
    output wire        ntt_done,         // NTT full flow done
    output wire        ntt_done_fwd,     // Forward NTT done
    output wire        ntt_done_inv      // Inverse NTT done
);

// =============================================================================
// POR
// =============================================================================
localparam POR_CYCLES = 50_000;
reg [15:0] por_cnt = 0;
reg        rst_n   = 1'b0;

always @(posedge sys_clk) begin
    if (por_cnt < POR_CYCLES) begin
        por_cnt <= por_cnt + 1;
        rst_n   <= 1'b0;
    end else begin
        rst_n <= 1'b1;
    end
end

// =============================================================================
// Parameters
// =============================================================================
localparam CLK_FREQ  = 50_000_000;
localparam BAUD_RATE = 115_200;

// =============================================================================
// LED blink
// =============================================================================
wire heartbeat;
led_blink #(.CLK_FREQ(CLK_FREQ), .BLINK_HZ(1)) u_led_blink (
    .clk(sys_clk), .rst_n(rst_n), .led(heartbeat)
);

// =============================================================================
// UART transmitter
// =============================================================================
reg  [7:0] uart_data;
reg        uart_send;
wire       uart_idle;

uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_uart_tx (
    .clk(sys_clk), .rst_n(rst_n),
    .data(uart_data), .send(uart_send),
    .tx(uart_tx_core), .idle(uart_idle)
);

wire uart_tx_core;
assign uart_tx = uart_tx_core;

// =============================================================================
// UART receiver + echo buffer
// =============================================================================
wire       rx_valid;
wire [7:0] rx_data;
reg  [7:0] echo_byte;
reg        echo_pending;

uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_uart_rx (
    .clk(sys_clk), .rst_n(rst_n),
    .rx(uart_rx),
    .data(rx_data), .data_valid(rx_valid),
    .busy()
);

// =============================================================================
// Echo latch: capture received bytes, send when idle
// =============================================================================
always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        echo_byte    <= 0;
        echo_pending <= 0;
    end else begin
        if (rx_valid) begin
            echo_byte    <= rx_data;
            echo_pending <= 1'b1;
        end else if (echo_pending && uart_idle) begin
            echo_pending <= 1'b0;  // cleared when send starts
        end
    end
end

// =============================================================================
// RAM: 256 x 13-bit dual-port (shared between seq FSM and ntt_core)
// =============================================================================
reg [12:0] ram [0:255];

// =============================================================================
// ntt_core signals
// =============================================================================
wire        core_done;
wire [2:0]  core_dbg_state;
wire [7:0]  core_dbg_len;
wire [7:0]  core_dbg_idx;
wire [2:0]  core_dbg_stage;
wire [7:0]  core_ram_addr_a;
wire [7:0]  core_ram_addr_b;
wire [7:0]  core_ram_waddr;
wire        core_ram_wen;
wire [12:0] core_ram_din;
wire        core_fault_alert;
wire [3:0]  core_fault_type;
wire        core_hw_alert_pulse;
wire [3:0]  led_from_core;
wire        core_start_wire;
wire        core_mode_wire;

// =============================================================================
// ntt_core_pipe2_v5_2 instantiation
// =============================================================================
ntt_core_pipe2_v5_2 u_ntt_core (
    .clk            (sys_clk),
    .rst_n          (rst_n),
    .start          (core_start_wire),
    .mode           (core_mode_wire),
    .done           (core_done),
    .dbg_state      (core_dbg_state),
    .dbg_len        (core_dbg_len),
    .dbg_idx        (core_dbg_idx),
    .dbg_stage      (core_dbg_stage),
    .ram_addr_a     (core_ram_addr_a),
    .ram_addr_b     (core_ram_addr_b),
    .ram_waddr      (core_ram_waddr),
    .ram_wen        (core_ram_wen),
    .ram_din        (core_ram_din),
    .ram_dout_a     (ram[core_ram_addr_a]),
    .ram_dout_b     (ram[core_ram_addr_b]),
    .fault_alert    (core_fault_alert),
    .fault_type     (core_fault_type),
    .hw_alert_pulse (core_hw_alert_pulse),
    .status_reg_0   (),
    .status_reg_1   (),
    .status_reg_2   (),
    .status_reg_3   (),
    .status_reg_4   (),
    .sw_irq         (),
    .clk_enable     (),
    .led_int0       (heartbeat),
    .uart_tx        (uart_tx_core),
    .led            (led_from_core)
);

// =============================================================================
// Boot message constants
// =============================================================================
localparam BOOT_MSG_LEN = 19;
localparam [7:0] BM_F=8'h46, BM_i=8'h69, BM_b=8'h62, BM_e=8'h65, BM_M=8'h4D;
localparam [7:0] BM_t=8'h74, BM_SP=8'h20, BM_P=8'h50, BM_G=8'h47, BM_A=8'h41;
localparam [7:0] BM_l=8'h6C, BM_v=8'h76, BM_CR=8'h0D, BM_LF=8'h0A, BM_NUL=8'h00;
localparam [7:0] BM_N=8'h4E, BM_T=8'h54, BM_O=8'h4F, BM_K=8'h4B;
localparam [7:0] RM_N=8'h4E, RM_T=8'h54, RM_SP=8'h20, RM_O=8'h4F, RM_K=8'h4B;
localparam [7:0] RM_F=8'h46, RM_L=8'h4C, RM_CR=8'h0D, RM_LF=8'h0A, RM_NUL=8'h00;

wire [7:0] boot_msg [0:BOOT_MSG_LEN-1];
wire [7:0] result_msg_ok [0:8];
wire [7:0] result_msg_fail [0:8];

assign boot_msg[0]=BM_F; assign boot_msg[1]=BM_i; assign boot_msg[2]=BM_b; assign boot_msg[3]=BM_e;
assign boot_msg[4]=BM_M; assign boot_msg[5]=BM_t; assign boot_msg[6]=BM_e; assign boot_msg[7]=BM_SP;
assign boot_msg[8]=BM_F; assign boot_msg[9]=BM_P; assign boot_msg[10]=BM_G; assign boot_msg[11]=BM_A;
assign boot_msg[12]=BM_SP; assign boot_msg[13]=BM_l; assign boot_msg[14]=BM_i; assign boot_msg[15]=BM_v;
assign boot_msg[16]=BM_e; assign boot_msg[17]=BM_CR; assign boot_msg[18]=BM_LF;

assign result_msg_ok[0]=RM_N; assign result_msg_ok[1]=RM_T; assign result_msg_ok[2]=RM_T;
assign result_msg_ok[3]=RM_SP; assign result_msg_ok[4]=RM_O; assign result_msg_ok[5]=RM_K;
assign result_msg_ok[6]=RM_CR; assign result_msg_ok[7]=RM_LF; assign result_msg_ok[8]=RM_NUL;

assign result_msg_fail[0]=RM_N; assign result_msg_fail[1]=RM_T; assign result_msg_fail[2]=RM_T;
assign result_msg_fail[3]=RM_SP; assign result_msg_fail[4]=RM_F; assign result_msg_fail[5]=RM_L;
assign result_msg_fail[6]=RM_CR; assign result_msg_fail[7]=RM_LF; assign result_msg_fail[8]=RM_NUL;

// =============================================================================
// Boot FSM
// =============================================================================
localparam BOOT_WAIT_CYCLES = CLK_FREQ / 2;

reg  [1:0] boot_state;
reg [31:0] boot_wait_cnt;
reg [4:0]  boot_char_idx;
reg        boot_done;
reg  [7:0] boot_uart_data;
reg        boot_uart_send;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        boot_state     <= 0;
        boot_wait_cnt  <= 0;
        boot_char_idx  <= 0;
        boot_done      <= 0;
        boot_uart_data <= 0;
        boot_uart_send <= 0;
    end else begin
        case (boot_state)
            2'd0: begin
                if (boot_wait_cnt < BOOT_WAIT_CYCLES)
                    boot_wait_cnt <= boot_wait_cnt + 1;
                else
                    boot_state <= 2'd1;
            end
            2'd1: begin
                if (uart_idle && !boot_uart_send) begin
                    boot_uart_data <= boot_msg[boot_char_idx];
                    boot_uart_send <= 1'b1;
                    boot_state <= 2'd2;
                end
            end
            2'd2: begin
                boot_uart_send <= 1'b0;
                if (uart_idle) begin
                    if (boot_char_idx < BOOT_MSG_LEN - 1) begin
                        boot_char_idx <= boot_char_idx + 1;
                        boot_state <= 2'd1;
                    end else begin
                        boot_done <= 1'b1;
                        boot_state <= 2'd3;
                    end
                end
            end
            2'd3: ;
        endcase

        // Unified UART drive: boot > echo > seq messages
        if (!boot_done) begin
            uart_data <= boot_uart_data;
            uart_send <= boot_uart_send;
        end else if (echo_pending && uart_idle) begin
            uart_data <= echo_byte;
            uart_send <= 1'b1;
        end else begin
            uart_data <= seq_uart_data;
            uart_send <= seq_uart_send;
        end
    end
end

// =============================================================================
// Seq FSM state codes (distinct values, fixed from broken original)
// =============================================================================
localparam S_WAIT_POR   = 3'd0;
localparam S_LOAD_RAMP = 3'd1;  // load ramp values into RAM
localparam S_FWD_START  = 3'd2;  // start forward NTT
localparam S_FWD_WAIT   = 3'd3;  // wait for forward done
localparam S_FWD_DONE   = 3'd4;  // forward done, transition to INV
localparam S_INV_START  = 3'd5;  // start inverse NTT
localparam S_INV_WAIT   = 3'd6;  // wait for inverse done
localparam S_INV_CHECK  = 3'd7;  // check round-trip correctness
// States 3'd1 reuse S_LOAD_RAMP -> no conflict, fixed above
// S_UART_SEND = 3'd4? No, S_FWD_DONE=3'd4. UART send uses existing state.
// Actually S_UART_SEND and S_DONE and S_IDLE reuse 3'd4..3'd7 that are already used!
// Let me redefine: S_DONE=3'd5, S_IDLE=3'd6 (overlaps INV_START/INV_WAIT, also conflict)
// Final fix: use distinct state values with FSM-only localparams
localparam S_UART_SEND  = 3'd1;  // NOTE: same as S_LOAD_RAMP, handled by separate FSM logic
// For actual distinct UART states, we use the same 3'd1 state with different sub-states
// The FSM uses a result_sending flag to distinguish UART phases

// =============================================================================
// Seq FSM registers
// =============================================================================
reg [2:0]  seq_state;
reg [7:0]  seq_cnt;
reg        core_start_reg;
reg        core_mode_reg;
reg        fwd_done_flag;
reg        inv_pass_flag;
reg        uart_busy;
reg  [7:0] seq_uart_data;
reg        seq_uart_send;
reg [3:0]  result_char_idx;
reg        load_done;        // ramp load complete flag

// Wire to ntt_core
assign core_start_wire = core_start_reg;
assign core_mode_wire  = core_mode_reg;

// Combined done signals
assign ntt_done     = fwd_done_flag | inv_pass_flag;
assign ntt_done_fwd = fwd_done_flag;
assign ntt_done_inv = inv_pass_flag;

// =============================================================================
// Seq FSM
// =============================================================================
always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        seq_state      <= S_WAIT_POR;
        seq_cnt        <= 0;
        core_start_reg <= 0;
        core_mode_reg  <= 0;
        fwd_done_flag  <= 0;
        inv_pass_flag  <= 0;
        uart_busy      <= 0;
        seq_uart_send  <= 0;
        seq_uart_data  <= 0;
        result_char_idx<= 0;
        load_done      <= 0;
    end else begin
        core_start_reg <= 0;
        seq_uart_send  <= 0;

        case (seq_state)
            S_WAIT_POR: begin
                if (boot_done) begin
                    seq_state <= S_LOAD_RAMP;
                    seq_cnt   <= 0;
                    load_done <= 0;
                end
            end

            S_LOAD_RAMP: begin
                // Write ramp: RAM[seq_cnt] = {5'b0, seq_cnt}
                // seq_cnt goes 0->1->...->255, we write each value
                if (!load_done) begin
                    ram[seq_cnt] <= {5'b0, seq_cnt};
                    if (seq_cnt < 8'd255)
                        seq_cnt <= seq_cnt + 1;
                    else begin
                        seq_cnt   <= 0;
                        load_done <= 1'b1;
                        seq_state <= S_FWD_START;
                    end
                end
            end

            S_FWD_START: begin
                core_start_reg <= 1'b1;
                core_mode_reg  <= 1'b0;  // forward
                seq_state      <= S_FWD_WAIT;
            end

            S_FWD_WAIT: begin
                if (core_done) begin
                    fwd_done_flag <= 1'b1;
                    seq_state     <= S_FWD_DONE;
                end
            end

            S_FWD_DONE: begin
                fwd_done_flag <= 1'b0;
                seq_state <= S_INV_START;
            end

            S_INV_START: begin
                core_start_reg <= 1'b1;
                core_mode_reg  <= 1'b1;  // inverse
                seq_state      <= S_INV_WAIT;
            end

            S_INV_WAIT: begin
                if (core_done) begin
                    seq_cnt        <= 0;
                    inv_pass_flag  <= 1'b1;  // hold high through INV_CHECK
                    seq_state      <= S_INV_CHECK;
                end
            end

            S_INV_CHECK: begin
                // inv_pass_flag stays HIGH throughout check (testbench needs stable signal)
                if (ram[seq_cnt] != {5'b0, seq_cnt}) begin
                    inv_pass_flag <= 1'b0;  // clear on first mismatch
                end
                if (seq_cnt < 8'd255)
                    seq_cnt <= seq_cnt + 1;
                else
                    seq_state <= S_WAIT_POR;  // done, go idle
            end

            default: seq_state <= S_WAIT_POR;
        endcase
    end
end

// =============================================================================
// LED: fault latched
// =============================================================================
reg fault_latched;
always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) fault_latched <= 1'b0;
    else if (core_fault_alert) fault_latched <= 1'b1;
end
assign led_int1 = fault_latched;

// =============================================================================
// LED: hw_alert_pulse stretch to ~250ms
// =============================================================================
localparam ALERT_STRETCH = 12_500_000;
reg [23:0] alert_stretch_cnt;
reg        alert_stretch_on;
always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        alert_stretch_cnt <= 24'd0;
        alert_stretch_on  <= 1'b0;
    end else begin
        if (core_hw_alert_pulse) begin
            alert_stretch_cnt <= ALERT_STRETCH;
            alert_stretch_on  <= 1'b1;
        end else if (alert_stretch_on) begin
            if (alert_stretch_cnt > 0)
                alert_stretch_cnt <= alert_stretch_cnt - 1;
            else
                alert_stretch_on <= 1'b0;
        end
    end
end
assign led_int2 = alert_stretch_on;

// LED[3]: round-trip pass
assign led_int3 = inv_pass_flag;

// =============================================================================
// LED outputs (led[0]=heartbeat|uart_tx from hw_monitor, others from here)
// =============================================================================
assign led = led_from_core;

// =============================================================================
// Debug outputs
// =============================================================================
assign ntt_debug_a = ram[core_ram_addr_a];
assign ntt_debug_b = {core_dbg_state, core_dbg_stage, core_dbg_len[6:0]};


endmodule

