// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// tensor_ntt_scheduler.v — 张量调度 NTT 顶层 (v2, 支持流水化内核)
// =============================================================================
//
// USE_PIPE = 0: 例化 ntt_core (原版, 12 cycles/BF)
// USE_PIPE = 1: 例化 ntt_core_pipe (流水版, 4 cycles/BF)
// =============================================================================


`include "params.vh"

module tensor_ntt_scheduler
#(
    parameter NUM_POLYS   = 9,
    parameter POLY_WIDTH  = 4,
    parameter N           = 256,
    parameter ADDR_WIDTH  = 8,
    parameter DATA_WIDTH  = 13,
    parameter USE_PIPE    = 0       // 0=ntt_core, 1=ntt_core_pipe
)(
    input  wire                     clk, rst_n,
    input  wire                     start_i, mode_i,
    output reg                      done_o,
    output reg  [POLY_WIDTH-1:0]    busy_poly,
    input  wire                     load_en,
    input  wire [POLY_WIDTH-1:0]    load_poly, load_size,
    input  wire [ADDR_WIDTH-1:0]    load_addr,
    input  wire [DATA_WIDTH-1:0]    load_data,
    input  wire [POLY_WIDTH-1:0]    read_poly,
    input  wire [ADDR_WIDTH-1:0]    read_addr,
    output wire [DATA_WIDTH-1:0]    read_data,
    output wire [2:0]               dbg_state
);

    // ═══ RAM ═══
    reg [DATA_WIDTH-1:0] poly_ram [0:NUM_POLYS*N-1];
    integer load_flat;
    always @(posedge clk) if (load_en) begin
        load_flat = load_poly * N + load_addr;
        poly_ram[load_flat] <= load_data;
    end

    // ═══ 读端口 ═══
    reg [ADDR_WIDTH+POLY_WIDTH-1:0] read_flat_a, read_flat_b;
    wire [DATA_WIDTH-1:0] ram_dout_a_w = poly_ram[read_flat_a];
    wire [DATA_WIDTH-1:0] ram_dout_b_comb = poly_ram[read_flat_b];
    reg  [DATA_WIDTH-1:0] ram_dout_b_w;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ram_dout_b_w <= 0;
        else       ram_dout_b_w <= ram_dout_b_comb;
    end

    // ═══ 写回 ═══
    wire core_wen;
    wire [ADDR_WIDTH-1:0] core_waddr_a;
    wire [DATA_WIDTH-1:0] core_wdata;
    integer write_flat_int;

    always @(posedge clk) if (core_wen) begin
        write_flat_int = busy_poly * N + core_waddr_a;
        poly_ram[write_flat_int] <= core_wdata;
    end

    // ═══ 读出 ═══
    assign read_data = poly_ram[read_poly * N + read_addr];

    // ═══ NTT 内核 ═══
    wire core_start, core_done;
    wire [7:0] core_ram_addr_a, core_ram_addr_b;
    wire core_ram_wen;
    wire [12:0] core_ram_din;

    generate
        if (USE_PIPE == 0) begin : gen_core
            ntt_core u_ntt (
                .clk(clk), .rst_n(rst_n),
                .start(core_start), .mode(mode_i), .done(core_done),
                .dbg_state(), .dbg_len(), .dbg_idx(), .dbg_stage(),
                .ram_addr_a(core_ram_addr_a), .ram_addr_b(core_ram_addr_b),
                .ram_wen(core_ram_wen), .ram_din(core_ram_din),
                .ram_dout_a(ram_dout_a_w), .ram_dout_b(ram_dout_b_w)
            );
        end else begin : gen_core_pipe
            ntt_core_pipe u_ntt_pipe (
                .clk(clk), .rst_n(rst_n),
                .start(core_start), .mode(mode_i), .done(core_done),
                .dbg_state(), .dbg_len(), .dbg_idx(), .dbg_stage(),
                .ram_addr_a(core_ram_addr_a), .ram_addr_b(core_ram_addr_b),
                .ram_wen(core_ram_wen), .ram_din(core_ram_din),
                .ram_dout_a(ram_dout_a_w), .ram_dout_b(ram_dout_b_w)
            );
        end
    endgenerate

    assign core_wen    = core_ram_wen;
    assign core_waddr_a = core_ram_addr_a;
    assign core_wdata  = core_ram_din;

    // ═══ 调度 FSM ═══
    localparam S_IDLE=0, S_START=1, S_WAIT=2, S_NEXT=3, S_DONE=4;
    reg [2:0] state;
    reg [POLY_WIDTH-1:0] poly_idx, load_size_reg;
    assign dbg_state = state;
    assign core_start = (state == S_START);

    always @(*) begin
        read_flat_a = poly_idx * N + core_ram_addr_a;
        read_flat_b = poly_idx * N + core_ram_addr_b;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; done_o <= 0; poly_idx <= 0;
            busy_poly <= 0; load_size_reg <= 0;
        end else begin
            done_o <= 0; busy_poly <= poly_idx;
            case (state)
                S_IDLE: begin
                    poly_idx <= 0;
                    if (start_i) begin load_size_reg <= load_size; state <= S_START; end
                end
                S_START: state <= S_WAIT;
                S_WAIT: begin
                    if (core_done) begin
                        if (poly_idx < load_size_reg - 1) state <= S_NEXT;
                        else state <= S_DONE;
                    end
                end
                S_NEXT: begin poly_idx <= poly_idx + 1; state <= S_START; end
                S_DONE: begin done_o <= 1'b1; state <= S_IDLE; end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule