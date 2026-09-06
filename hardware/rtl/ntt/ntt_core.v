// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// ML-KEM NTT 核心变换模块 — 256 点 Forward/Inverse
// =============================================================================
// 算法: FIPS 203 Algorithm 5 (Forward) / Algorithm 6 (Inverse)
//
// 架构: 时序调度，每级蝶形完成后进入下一级
//   - 256 字双口 RAM (in-place)
//   - 每级读取 2×len 个系数，执行 len 个蝶形
//   - Forward: 7 级 (len=128→64→32→16→8→4→2)
//   - Inverse: 7 级 (len=2→4→8→16→32→64→128)
//
// 性能: 每蝶形 4 周期，每级 len 个蝶形
//   Forward: Σ(len×4) = 4×(128+64+...+2) = 4×254 = 1016 cycles + RAM 读写
//   实际约 ~1200 cycles
//
// mode: 0=Forward NTT, 1=Inverse NTT
// done: 高脉冲，变换完成
// =============================================================================
// MIT License


`include "params.vh"

module ntt_core (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,      // 启动脉冲
    input  wire        mode,       // 0=Forward, 1=Inverse
    output reg         done,       // 完成脉冲
    output wire [2:0]   dbg_state,  // 调试: 当前状态
    output wire [7:0]   dbg_len,    // 调试: 当前 len
    output wire [7:0]   dbg_idx,    // 调试: 当前 idx
    output wire [2:0]   dbg_stage,  // 调试: 当前级数
    // RAM 接口 (256×13bit)
    output reg  [7:0] ram_addr_a,
    output reg  [7:0] ram_addr_b,
    output reg         ram_wen,
    output reg [12:0] ram_din,
    input  wire [12:0] ram_dout_a,
    input  wire [12:0] ram_dout_b
);

    // ── 状态机 ──
    localparam S_IDLE  = 3'd0,
               S_LOAD  = 3'd1,  // 读 RAM (设地址)
               S_WAIT  = 3'd2,  // 等 1 拍让 ram_b 稳定
               S_BFLY  = 3'd3,  // 蝶形计算 (等 out_valid)
               S_WRITE = 3'd4,  // 写回 RAM (A')
               S_NEXT  = 3'd5,  // 写 B'
               S_NEXT2 = 3'd6,  // 推进 idx / start_addr / stage
               S_DONE  = 3'd7;
    reg [2:0] state;

    // ── 层级参数 ──
    reg [7:0] len;         // 当前蝶形长度 (Forward:128→2, Inverse:2→128)
    reg       len_inc;     // 0=减半(Forward), 1=加倍(Inverse)
    reg [6:0] k;           // zeta 索引 (forward: 1→127, inverse: 127→1)
    // reg [6:0] k_step;   // (unused — 显式 k±1)

    // ── 组内计数器 ──
    reg [7:0] idx;         // 当前组内偏移 (0..len-1)
    reg [8:0] start_addr;  // 9-bit: 需要 0..256 才能终止循环 (2*len=256 溢出 8-bit!)

    // ── InvNTT scaling (x 128^{-1}; R * 128^{-1} mod Q = 128) ──
    localparam SCALE_N_INV = 13'd64;   // Mont(256^{-1}) = R * 256^{-1} mod 3329 (FIPS 203 搂搂4.3)
    reg        s_in_scale; // 1=正在执行缩放循环
    reg [7:0]  scale_idx;  // 当前缩放的系数索引 0..255

    // ── 蝶形实例 ──
    wire [12:0] bf_a_out, bf_b_out;
    wire        bf_valid;
    reg         bf_mode;
    reg  [12:0] bf_a_in, bf_b_in, bf_z;
    reg         bf_start;

    // ── Zeta ROM ──
    wire [12:0] zeta_out;
    reg  [6:0]  zeta_addr;

    ntt_butterfly_unif u_bf (
        .clk(clk), .rst_n(rst_n),
        .mode(bf_mode), .a_in(bf_a_in), .b_in(bf_b_in), .z(bf_z),
        .valid(bf_start), .a_out(bf_a_out), .b_out(bf_b_out), .out_valid(bf_valid)
    );

    zeta_rom u_zeta (.addr(zeta_addr), .data(zeta_out));

    assign dbg_state = state;
    assign dbg_len   = len;
    assign dbg_idx   = idx;
    assign dbg_stage = stage_cnt;

    // ── 层级计数 ──
    reg [2:0] stage_cnt;  // 0..6 (共 7 级)

    // ── 主状态机 ──
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            done      <= 0;
            ram_addr_a<= 0; ram_addr_b <= 0;
            ram_wen   <= 0; ram_din <= 0;
            bf_start  <= 0;
            len       <= 8'd128;
            len_inc   <= 1'b0;  // Forward: 减半
            k         <= 7'd1;
            idx       <= 0;
            start_addr<= 0;
            stage_cnt <= 0;
            zeta_addr <= 0;
            s_in_scale <= 0;
            scale_idx  <= 0;
        end else begin
            done    <= 1'b0;
            ram_wen <= 1'b0;
            bf_start<= 1'b0;

            case (state)
                // ── 空闲，等启动 ──
                S_IDLE: begin
                    if (start) begin
                        s_in_scale <= 1'b0;
                        scale_idx  <= 0;
                        stage_cnt <= 0;
                        if (mode == 1'b0) begin
                            // Forward: len=128, k=1
                            len     <= 8'd128;
                            len_inc <= 1'b0;
                            k       <= 7'd1;
                        end else begin
                            // Inverse: len=2, k=127
                            len     <= 8'd2;
                            len_inc <= 1'b1;
                            k       <= 7'd127;
                        end
                        idx        <= 0;
                        start_addr <= 0;
                        bf_mode    <= mode;
                        state      <= S_LOAD;
                    end
                end

                // ── 读 RAM + zeta ROM (设地址) ──
                S_LOAD: begin
                    if (s_in_scale) begin
                        // 缩放模式: 读取 scale_idx 位置的系数
                        ram_addr_a <= 0;     // dummy (A=0 in butterfly)
                        ram_addr_b <= scale_idx;
                        zeta_addr  <= 0;     // unused
                    end else begin
                        ram_addr_a <= start_addr[7:0] + idx;
                        ram_addr_b <= start_addr[7:0] + idx + len;
                        zeta_addr  <= k;
                    end
                    state      <= S_WAIT;
                end

                // ── 等 1 拍让 ram_b 稳定 (ram_b 是寄存器) ──
                S_WAIT: begin
                    state <= S_BFLY;
                end

                // ── 蝶形发起 ──
                S_BFLY: begin
                    // ram_dout_a: 组合逻辑, 已稳定
                    // ram_dout_b: 寄存器, S_WAIT 那拍已更新
                    if (s_in_scale) begin
                        // 缩放: A=0, B=coeff, z=64, mode=forward
                        // Forward butterfly: A'=A+MontMul(z,B)=MontMul(64,coeff)
                        bf_a_in <= 13'd0;
                        bf_b_in <= ram_dout_b;
                        bf_z    <= SCALE_N_INV;
                        bf_mode <= 1'b0;   // forward mode
                    end else begin
                        bf_a_in <= ram_dout_a;
                        bf_b_in <= ram_dout_b;
                        bf_z    <= zeta_out;
                    end
                    bf_start <= 1'b1;
                    state    <= S_WRITE;
                end

                // ── 等蝶形输出，写回 ──
                S_WRITE: begin
                    bf_start <= 1'b0;
                    if (bf_valid) begin
                        if (s_in_scale) begin
                            // 缩放: 只写 bf_a_out (MontMul(64, coeff))
                            ram_addr_a <= scale_idx;
                            ram_din    <= bf_a_out;
                            ram_wen    <= 1'b1;
                            state      <= S_NEXT;
                        end else begin
                            // 写回 RAM
                            ram_addr_a <= start_addr[7:0] + idx;
                            ram_din    <= bf_a_out;
                            ram_wen    <= 1'b1;
                            ram_addr_b <= start_addr[7:0] + idx + len;
                            state <= S_NEXT;
                        end
                    end
                end

                // ── 下一组 / 下一级 ──
                S_NEXT: begin
                    ram_wen <= 1'b0;
                    if (s_in_scale) begin
                        // 缩放模式: 跳过 B 写回, 直接进入推进
                        state <= S_NEXT2;
                    end else begin
                        // 写完 A，现在写 B
                        ram_addr_a <= start_addr[7:0] + idx + len;
                        ram_din    <= bf_b_out;
                        ram_wen    <= 1'b1;
                        state      <= S_NEXT2;
                    end
                end

                S_NEXT2: begin
                    ram_wen <= 1'b0;
                    if (s_in_scale) begin
                        // 缩放模式: 推进 scale_idx
                        if (scale_idx < 8'd255) begin
                            scale_idx <= scale_idx + 1;
                            state <= S_LOAD;
                        end else begin
                            s_in_scale <= 1'b0;
                            state <= S_DONE;
                        end
                    end else begin
                        // 推进 idx (组内)
                        if (idx < len - 1) begin
                            idx   <= idx + 1;
                            state <= S_LOAD;
                        end else begin
                            // 本组完成，推进 start_addr (9-bit 防溢出)
                            if (start_addr + {1'b0, len, 1'b0} < 9'd256) begin
                                start_addr <= start_addr + {1'b0, len, 1'b0};
                                idx        <= 0;
                                // 每组完成才推进 k (组内所有蝶形共享同一个 zeta!)
                                if (len_inc)
                                    k <= k - 7'd1;
                                else
                                    k <= k + 7'd1;
                                state      <= S_LOAD;
                            end else begin
                                // 本级完成 — k 也需要递增 (每组一个 zeta)
                                stage_cnt <= stage_cnt + 1;
                                if (len_inc)
                                    k <= k - 7'd1;
                                else
                                    k <= k + 7'd1;
                                if (stage_cnt < 3'd6) begin
                                    // 进入下一级
                                    if (len_inc)
                                        len <= len << 1;
                                    else
                                        len <= len >> 1;
                                    start_addr <= 0;
                                    idx        <= 0;
                                    state      <= S_LOAD;
                                end else begin
                                    // 所有 7 级完成
                                    if (mode == 1'b1) begin
                                        // Inverse NTT: 进入缩放步骤 x n^{-1}
                                        s_in_scale <= 1'b1;
                                        scale_idx  <= 0;
                                        state      <= S_LOAD;
                                    end else begin
                                        // Forward NTT: 直接完成
                                        state <= S_DONE;
                                    end
                                end
                            end
                        end
                    end
                end

                // ── 完成 ──
                S_DONE: begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule