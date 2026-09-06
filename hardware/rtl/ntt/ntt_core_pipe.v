// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// ntt_core_pipe.v — Pipelined NTT Core v3.1 (分离 ram_waddr 读写地址)
// =============================================================================
// Fix: ram_addr_a/b 仅用于读, ram_waddr 仅用于写。
// 消除 b_pend 写地址被 S_LOAD 读地址覆盖的竞态。
// 4 cycles/BF: S_LOAD → S_WAIT → S_PREP → S_BFLY
// 环形地址队列: 8项, 无移位竞态
// =============================================================================


`include "params.vh"

module ntt_core_pipe (
    input  wire        clk, rst_n, start, mode,
    output reg         done,
    output wire [2:0]  dbg_state,
    output wire [7:0]  dbg_len, dbg_idx,
    output wire [2:0]  dbg_stage,
    output reg  [7:0]  ram_addr_a, ram_addr_b,
    output reg  [7:0]  ram_waddr,      // 独立写地址
    output reg         ram_wen,
    output reg  [12:0] ram_din,
    input  wire [12:0] ram_dout_a, ram_dout_b
);

    localparam S_IDLE=0, S_LOAD=1, S_WAIT=2, S_PREP=3, S_BFLY=4, S_NEXT=5, S_DONE=6;
    reg [2:0] state;
    reg [7:0] len, idx;    reg len_inc;
    reg [6:0] k;           reg [8:0] start_addr;  reg [2:0] stage_cnt;

    wire [12:0] bf_a_out, bf_b_out;
    wire        bf_valid;
    reg  [12:0] bf_a_in, bf_b_in, bf_z;
    reg         bf_start, bf_mode;
    wire [12:0] zeta_out;
    reg  [6:0]  zeta_addr;

    ntt_butterfly_unif u_bf (.clk(clk), .rst_n(rst_n),
        .mode(bf_mode), .valid(bf_start),
        .a_in(bf_a_in), .b_in(bf_b_in), .z(bf_z),
        .a_out(bf_a_out), .b_out(bf_b_out), .out_valid(bf_valid));
    zeta_rom u_zeta (.addr(zeta_addr), .data(zeta_out));

    // 环形地址队列
    localparam AQ_DEPTH = 8;
    reg [7:0]  aq_a [0:AQ_DEPTH-1], aq_b [0:AQ_DEPTH-1];
    reg [2:0]  bf_wr_ptr, bf_rd_ptr;
    reg [8:0]  bf_launched, bf_completed;

    // B' pending
    reg         b_pend;
    reg [7:0]   b_pend_addr;
    reg [12:0]  b_pend_val;

    localparam SCALE_N_INV = 13'd128;
    reg s_in_scale;
    reg [7:0] scale_idx;

    assign dbg_state=state; assign dbg_len=len;
    assign dbg_idx=idx;   assign dbg_stage=stage_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_IDLE; done<=0;
            ram_addr_a<=0; ram_addr_b<=0; ram_waddr<=0;
            ram_wen<=0; ram_din<=0; bf_start<=0;
            len<=128; len_inc<=0; k<=0; idx<=0; start_addr<=0; stage_cnt<=0;
            zeta_addr<=0; s_in_scale<=0; scale_idx<=0;
            bf_wr_ptr<=0; bf_rd_ptr<=0; bf_launched<=0; bf_completed<=0;
            b_pend<=0; b_pend_addr<=0; b_pend_val<=0;
        end else begin
            done<=1'b0; ram_wen<=1'b0; bf_start<=1'b0;

            // ── 写回 (仅用 ram_waddr, 不影响 ram_addr_a/b 读地址) ──
            if (b_pend) begin
                ram_waddr <= b_pend_addr;
                ram_din   <= b_pend_val;
                ram_wen   <= 1'b1;
                b_pend    <= 1'b0;
            end

            // ── bf_valid: 写 A', 备 B' ──
            if (bf_valid) begin
                ram_waddr <= aq_a[bf_rd_ptr];
                ram_din   <= bf_a_out;
                ram_wen   <= 1'b1;
                if (!b_pend) begin
                    b_pend_addr <= aq_b[bf_rd_ptr];
                    b_pend_val  <= bf_b_out;
                    b_pend      <= 1'b1;
                end
                bf_rd_ptr    <= bf_rd_ptr + 1;
                bf_completed <= bf_completed + 1;
            end

            case (state)
                S_IDLE: if (start) begin
                    s_in_scale<=0; scale_idx<=0; stage_cnt<=0;
                    bf_wr_ptr<=0; bf_rd_ptr<=0; bf_launched<=0; bf_completed<=0;
                    b_pend<=0; b_pend_addr<=0; b_pend_val<=0;
                    if (mode) begin len<=2; len_inc<=1; k<=127; end
                    else      begin len<=128; len_inc<=0; k<=1; end
                    idx<=0; start_addr<=0; bf_mode<=mode; state<=S_LOAD;
                end

                S_LOAD: begin
                    // ★ 仅设读地址 (不影响 ram_waddr, 不冲突)
                    ram_addr_a <= s_in_scale ? 0 : start_addr[7:0] + idx;
                    ram_addr_b <= s_in_scale ? scale_idx : start_addr[7:0] + idx + len;
                    zeta_addr  <= s_in_scale ? 0 : k;
                    state <= S_WAIT;
                end

                S_WAIT: state <= S_PREP;

                S_PREP: begin
                    bf_a_in <= s_in_scale ? 13'd0 : ram_dout_a;
                    bf_b_in <= ram_dout_b;
                    bf_z    <= s_in_scale ? SCALE_N_INV : zeta_out;
                    bf_mode <= s_in_scale ? 1'b0 : mode;
                    bf_start <= 1'b1;
                    // 写回地址存入环形队列
                    aq_a[bf_wr_ptr] <= s_in_scale ? scale_idx : start_addr[7:0] + idx;
                    aq_b[bf_wr_ptr] <= s_in_scale ? 8'd0 : start_addr[7:0] + idx + len;
                    bf_wr_ptr  <= bf_wr_ptr + 1;
                    bf_launched <= bf_launched + 1;
                    state <= S_BFLY;
                end

                S_BFLY: begin
                    if (s_in_scale) begin
                        if (scale_idx < 8'd255) begin
                            scale_idx<=scale_idx+1; state<=S_LOAD;
                        end else state<=S_NEXT;
                    end else if (idx < len-1) begin
                        idx<=idx+1; state<=S_LOAD;
                    end else state<=S_NEXT;
                end

                S_NEXT: begin
                    if (bf_launched == bf_completed && !b_pend) begin
                        idx<=0;
                        if (s_in_scale) begin
                            s_in_scale<=0; state<=S_DONE;
                        end else if (start_addr + {1'b0,len,1'b0} < 9'd256) begin
                            start_addr<=start_addr+{1'b0,len,1'b0};
                            if (len_inc) k<=k-7'd1; else k<=k+7'd1;
                            state<=S_LOAD;
                        end else begin
                            stage_cnt<=stage_cnt+1;
                            if (len_inc) k<=k-7'd1; else k<=k+7'd1;
                            if (stage_cnt<3'd6) begin
                                if (len_inc) len<=len<<1; else len<=len>>1;
                                start_addr<=0; state<=S_LOAD;
                            end else begin
                                if (mode) begin s_in_scale<=1; scale_idx<=0; state<=S_LOAD; end
                                else state<=S_DONE;
                            end
                        end
                    end
                end

                S_DONE: begin done<=1'b1; state<=S_IDLE; end
                default: state<=S_IDLE;
            endcase
        end
    end

endmodule