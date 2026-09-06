// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// ntt_core_pipe2.v — FIBEMATE NTT Pipeline v5.2
// =============================================================================
// v5.2 变更: 缝合硬件防护子模块 (fault_protect + hw_monitor + lfsr256_prng)
// v5.1 变更: S_BFLY 后不等待 bf_valid, 独立 WritebackFSM, stage_cnt<3'd6
// 底核: ntt_core.v 最小侵入式流水化
// =============================================================================


`include "params.vh"

module ntt_core_pipe2 (
    input  wire        clk, rst_n, start, mode,
    output reg         done,
    output wire [2:0]  dbg_state,
    output wire [7:0]  dbg_len, dbg_idx,
    output wire [2:0]  dbg_stage,
    output reg  [7:0]  ram_addr_a, ram_addr_b,
    output reg  [7:0]  ram_waddr,     // 独立写地址
    output reg         ram_wen,
    output reg  [12:0] ram_din,
    input  wire [12:0] ram_dout_a, ram_dout_b,

    // ── 背压: 等 wrapper bf_ready ──
    input  wire        bf_ready,
    // ── butterfly 完成脉冲 (暴露给外部 wrapper) ──
    output wire        bf_valid_out,

    // ── v5.2 硬件防护端口 ──
    output wire        fault_alert,
    output wire [3:0]  fault_type,
    output wire        hw_alert_pulse,
    output wire [31:0] status_reg_0,
    output wire [31:0] status_reg_1,
    output wire [31:0] status_reg_2,
    output wire [31:0] status_reg_3,
    input  wire        led_int0,
    input  wire        uart_tx,
    output wire [3:0]  led
);

    assign bf_valid_out = bf_valid;  // 暴露给 ntt_core_pipe2_v5_2 的 wrapper

    // =====================================================================
    // 核心运算逻辑 (v5.1 原版, 不变)
    // =====================================================================

    // ── 状态机 ──
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
    reg [8:0] bf_launched, bf_completed;
    // ── BF 背压追踪: 等 wrapper bf_ready 才发下一发 ──
    reg        bf_inflight;

    localparam AQ_DEPTH=8;
    reg [7:0]  aq_a [0:AQ_DEPTH-1], aq_b [0:AQ_DEPTH-1];
    reg [2:0]  aq_wr_ptr, aq_rd_ptr;

    // Writeback FSM
    localparam WB_IDLE=0, WB_A=1, WB_B=2;
    reg [1:0]  wb_state;
    reg [7:0]  wb_addr_a_r, wb_addr_b_r;
    reg [12:0] wb_data_a_r, wb_data_b_r;

    localparam SCALE_N_INV = 13'd64;
    reg s_in_scale;
    reg [7:0] scale_idx;

    assign dbg_state=state; assign dbg_len=len;
    assign dbg_idx=idx;   assign dbg_stage=stage_cnt;

    // =====================================================================
    // 主 FSM (v5.1 原版, 不变)
    // =====================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_IDLE; done<=0;
            ram_addr_a<=0; ram_addr_b<=0;
            bf_start<=0; bf_a_in<=0; bf_b_in<=0; bf_z<=0;
            len<=128; len_inc<=0; k<=0; idx<=0; start_addr<=0; stage_cnt<=0;
            zeta_addr<=0; s_in_scale<=0; scale_idx<=0;
            bf_launched<=0; bf_completed<=0;
            bf_inflight<=0;
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
                    // ── 背压修复: 等 wrapper bf_ready 且无 in-flight ──
                    if (bf_ready && !bf_inflight) begin
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
                        bf_inflight <= 1'b1;
                        aq_a[aq_wr_ptr] <= s_in_scale ? scale_idx : start_addr[7:0]+idx;
                        aq_b[aq_wr_ptr] <= s_in_scale ? 8'd0 : start_addr[7:0]+idx+len;
                        aq_wr_ptr  <= aq_wr_ptr+1;
                        bf_launched <= bf_launched+1;
                    end
                    // bf_valid 到达时清除 in-flight (bf_valid 脉冲触发)
                    if (bf_valid) bf_inflight <= 1'b0;
                    state <= S_NEXT;
                end

                S_NEXT: begin
                    if (s_in_scale) begin
                        if (scale_idx < 8'd255) begin
                            scale_idx<=scale_idx+1; state<=S_LOAD;
                        end else state<=S_NEXT2;
                    end else if (idx < len-1) begin
                        idx<=idx+1; state<=S_LOAD;
                    end else state<=S_NEXT2;
                end

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

    // =====================================================================
    // 独立写回 FSM (v5.1 原版, 不变)
    // =====================================================================
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

    // =====================================================================
    // v5.2 子模块集成
    // =====================================================================

    // ── 运行状态信号 ──
    wire ntt_active;
    reg  done_pulse;
    assign ntt_active = (state != S_IDLE) && (state != S_DONE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) done_pulse <= 0;
        else done_pulse <= done;
    end

    // ── 周期计数 ──
    reg [15:0] cycle_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cycle_cnt <= 0;
        else if (start)
            cycle_cnt <= 0;
        else if (ntt_active)
            cycle_cnt <= cycle_cnt + 1;
    end

    // ── LFSR256 PRNG (掩码随机源) ──
    wire [12:0] prng_mask;
    wire        prng_ready;
    reg  [31:0] prng_seed_ctr;
    reg         prng_seeded;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin prng_seed_ctr <= 0; prng_seeded <= 0; end
        else if (!prng_seeded) begin
            prng_seed_ctr <= prng_seed_ctr + 1;
            if (prng_seed_ctr == 32'd250) prng_seeded <= 1;
        end
    end

    lfsr_prng u_prng (
        .clk        (clk),
        .rst_n      (rst_n),
        .seed_valid (prng_seeded && (prng_seed_ctr[2:0] == 3'd0)),
        .seed_val   (prng_seed_ctr),
        .next_mask  (1'b1),
        .mask       (prng_mask),
        .mask_ready (prng_ready)
    );

    // ── Fault Protect (L1/L2/L3) ──
    wire fp_fault_alert;
    wire [3:0] fp_fault_type;

    ntt_fault_protect u_fault (
        .clk           (clk),
        .rst_n         (rst_n),
        .ram_waddr     (ram_waddr),
        .ram_wen       (ram_wen),
        .ram_wdata     (ram_din),
        .ntt_active    (ntt_active),
        .ntt_done      (done_pulse),
        .bf_mismatch   (1'b0),          // TODO: REMO 双蝶形比对
        .remo_pass1_sum(13'd0),
        .remo_pass2_sum(13'd0),
        .remo_valid    (1'b0),
        .fault_alert   (fp_fault_alert),
        .fault_type    (fp_fault_type),
        .cycle_count   (cycle_cnt)
    );

    // ── Hw Monitor (状态寄存器 + LED + hw_alert) ──
    hw_monitor u_hw (
        .clk             (clk),
        .rst_n           (rst_n),
        .fault_alert     (fp_fault_alert),
        .fault_type      (fp_fault_type),
        .ntt_cycle_count (cycle_cnt),
        .ntt_done        (done_pulse),
        .led_int0        (led_int0),
        .uart_tx         (uart_tx),
        .status_reg_0    (status_reg_0),
        .status_reg_1    (status_reg_1),
        .status_reg_2    (status_reg_2),
        .status_reg_3    (status_reg_3),
        .hw_alert_pulse  (hw_alert_pulse),
        .led             (led)
    );

    assign fault_alert = fp_fault_alert;
    assign fault_type  = fp_fault_type;

endmodule
