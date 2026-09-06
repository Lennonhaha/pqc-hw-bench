// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// ntt_core_pipe2.v — 基于 ntt_core.v 的最小侵入式流水化改造
// =============================================================================
// 变更: (1) S_BFLY 后直接进入下一蝶形 S_LOAD,不等待 bf_valid
//       (2) 添加独立 WritebackFSM 异步处理 bf_valid→A'/B' 写回
//       (3) S_NEXT 等待 in_flight==0 才推进组/级
//       (4) 添加 ram_waddr 分离读写地址
// 其余所有时序与原版一致; Forward/Inverse/stage 逻辑不变
// =============================================================================


`include "params.vh"

module ntt_core_pipe2 (
    input  wire        clk, rst_n, start, mode,
    output reg         done,
    output wire [2:0]  dbg_state,
    output wire [7:0]  dbg_len, dbg_idx,
    output wire [2:0]  dbg_stage,
    output reg  [7:0]  ram_addr_a, ram_addr_b,
    output reg  [7:0]  ram_waddr,     // 独立写地址(与原版ram_addr_a复用不同)
    output reg         ram_wen,
    output reg  [12:0] ram_din,
    input  wire [12:0] ram_dout_a, ram_dout_b
);

    // ── 状态机 (与原版 S_IDLE→S_LOAD→S_WAIT→S_BFLY→S_NEXT→S_DONE 相同) ──
    localparam S_IDLE=0, S_LOAD=1, S_WAIT=2, S_BFLY=3, S_NEXT=4, S_NEXT2=5, S_DONE=6;
    reg [2:0] state;
    reg [7:0] len, idx;    reg len_inc;
    reg [6:0] k;           reg [8:0] start_addr;  reg [2:0] stage_cnt;

    // ── 蝶形接口 ──
    wire [12:0] bf_a_out, bf_b_out;
    wire        bf_valid;
    reg  [12:0] bf_a_in, bf_b_in, bf_z;
    reg         bf_start, bf_mode;
    wire [12:0] zeta_out;
    reg  [6:0]  zeta_addr;

    ntt_butterfly_unif u_bf (.clk(clk),.rst_n(rst_n),
        .mode(bf_mode),.valid(bf_start),
        .a_in(bf_a_in),.b_in(bf_b_in),.z(bf_z),
        .a_out(bf_a_out),.b_out(bf_b_out),.out_valid(bf_valid));
    zeta_rom u_zeta (.addr(zeta_addr),.data(zeta_out));

    // ── 流水线追踪 ──
    reg [8:0] bf_launched, bf_completed;  // 已发起 / 已完成 BF 数

    // 环形写回地址队列 (8深, 匹配 7-cycle BF latency)
    localparam AQ_DEPTH=8;
    reg [7:0]  aq_a [0:AQ_DEPTH-1], aq_b [0:AQ_DEPTH-1];
    reg [2:0]  aq_wr_ptr, aq_rd_ptr;

    // Writeback FSM
    localparam WB_IDLE=0, WB_A=1, WB_B=2;
    reg [1:0]  wb_state;
    reg [7:0]  wb_addr_a_r, wb_addr_b_r;
    reg [12:0] wb_data_a_r, wb_data_b_r;

    localparam SCALE_N_INV = 13'd64;   // Mont(256^{-1}) = R * 256^{-1} mod 3329 (FIPS 203 §4.3)
    reg s_in_scale;
    reg [7:0] scale_idx;

    assign dbg_state=state; assign dbg_len=len;
    assign dbg_idx=idx;   assign dbg_stage=stage_cnt;

    // ==========================================================================
    // 主 FSM (保持原版时序, S_BFLY 后不等待 bf_valid, 直接进入下一蝶形)
    // ==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_IDLE; done<=0;
            ram_addr_a<=0; ram_addr_b<=0;
            bf_start<=0; bf_a_in<=0; bf_b_in<=0; bf_z<=0;
            len<=128; len_inc<=0; k<=0; idx<=0; start_addr<=0; stage_cnt<=0;
            zeta_addr<=0; s_in_scale<=0; scale_idx<=0;
            bf_launched<=0; bf_completed<=0;
            aq_wr_ptr<=0; aq_rd_ptr<=0;
        end else begin
            done<=1'b0; bf_start<=1'b0;

            case (state)
                S_IDLE: if (start) begin
                    s_in_scale<=0; scale_idx<=0; stage_cnt<=0;
                    bf_launched<=0; bf_completed<=0;
                    aq_wr_ptr<=0; aq_rd_ptr<=0;
                    if (mode) begin len<=2; len_inc<=1; k<=127; end
                    else      begin len<=128; len_inc<=0; k<=1; end
                    idx<=0; start_addr<=0; bf_mode<=mode; state<=S_LOAD;
                end

                S_LOAD: begin
                    ram_addr_a <= s_in_scale ? 0 : start_addr[7:0]+idx;
                    ram_addr_b <= s_in_scale ? scale_idx : start_addr[7:0]+idx+len;
                    zeta_addr  <= s_in_scale ? 0 : k;
                    state <= S_WAIT;
                end

                S_WAIT: state <= S_BFLY;

                S_BFLY: begin
                    // 与原版完全一致的蝶形发起逻辑
                    if (s_in_scale) begin
                        bf_a_in <= 13'd0;
                        bf_b_in <= ram_dout_b;
                        bf_z    <= SCALE_N_INV;
                        bf_mode <= 1'b0;
                    end else begin
                        bf_a_in <= ram_dout_a;
                        bf_b_in <= ram_dout_b;
                        bf_z    <= zeta_out;
                    end
                    bf_start <= 1'b1;
                    // ★ 存写回地址到环形队列 ★
                    aq_a[aq_wr_ptr] <= s_in_scale ? scale_idx : start_addr[7:0]+idx;
                    aq_b[aq_wr_ptr] <= s_in_scale ? 8'd0 : start_addr[7:0]+idx+len;
                    aq_wr_ptr  <= aq_wr_ptr+1;
                    bf_launched <= bf_launched+1;
                    // ★ 直接进入步进逻辑 (原版进入 S_WRITE 忙等) ★
                    state <= S_NEXT;
                end

                // ── 步进 (原版 S_WRITE→S_NEXT→S_NEXT2 压缩为此状态) ──
                S_NEXT: begin
                    if (s_in_scale) begin
                        if (scale_idx < 8'd255) begin
                            scale_idx<=scale_idx+1; state<=S_LOAD;
                        end else state<=S_NEXT2;
                    end else if (idx < len-1) begin
                        idx<=idx+1; state<=S_LOAD;
                    end else state<=S_NEXT2;
                end

                // ── 等待所有飞行中 BF 完成 ──
                S_NEXT2: begin
                    if (bf_launched == bf_completed && wb_state==WB_IDLE) begin
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

    // ==========================================================================
    // 独立写回 FSM (异步于主 FSM, 仅响应 bf_valid)
    // ==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_state<=WB_IDLE; ram_wen<=0; ram_waddr<=0; ram_din<=0;
            wb_addr_a_r<=0; wb_addr_b_r<=0;
            wb_data_a_r<=0; wb_data_b_r<=0;
        end else begin
            ram_wen<=1'b0;
            case (wb_state)
                WB_IDLE: begin
                    if (bf_valid) begin
                        // 捕获结果 + 写回地址
                        wb_addr_a_r <= aq_a[aq_rd_ptr];
                        wb_addr_b_r <= aq_b[aq_rd_ptr];
                        wb_data_a_r <= bf_a_out;
                        wb_data_b_r <= bf_b_out;
                        aq_rd_ptr <= aq_rd_ptr+1;
                        wb_state <= WB_A;
                    end
                end

                WB_A: begin
                    ram_waddr <= wb_addr_a_r;
                    ram_din   <= wb_data_a_r;
                    ram_wen   <= 1'b1;
                    wb_state <= WB_B;
                end

                WB_B: begin
                    ram_waddr <= wb_addr_b_r;
                    ram_din   <= wb_data_b_r;
                    ram_wen   <= 1'b1;
                    bf_completed <= bf_completed+1;
                    wb_state <= WB_IDLE;
                end
            endcase
        end
    end

endmodule