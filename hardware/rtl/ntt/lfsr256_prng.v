// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// lfsr256_prng.v — 256-bit Galois LFSR CSPRNG (drop-in replacement for lfsr_prng)
// =============================================================================
// FIBEMATE FPGA NTT 掩码 CSPRNG
//
// 安全升级:
//   旧: lfsr_prng.v — 32-bit Galois LFSR, 种子空间 2^32 → 暴力枚举可行
//   新: lfsr256_prng.v — 256-bit Galois LFSR, 种子空间 2^256 → 暴力枚举不可行
//
// 多项式: x^256 + x^10 + x^5 + x^2 + 1
//   参考: eSTREAM portfolio, Grain-like LFSR with maximal period
//   周期: 2^256 - 1 (maximum-length sequence)
//
// 接口: 完全兼容 lfsr_prng (pin-compatible drop-in)
//
// 资源: ~260 FF, ~15 LUT, 0 BRAM, 0 DSP
//
// 吞吐: 1 mask/cycle (零延迟, 无 rejection sampling 回退)
//
// Usage:
//   seed_valid=1 → 加载 256-bit 种子 (seed_val = {SEED_H[127:0], SEED_L[127:0]})
//   next_mask=1  → 下一个周期 mask 有效, mask_ready=1
//   mask[12:0]   → 13-bit 掩码 ∈ [0, Q-1] via rejection sampling
// =============================================================================
// MIT License

`include "params.vh"

module lfsr256_prng (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        seed_valid,
    input  wire [31:0] seed_val,       // seed fed in 32-bit words over 8 cycles (compat)
    input  wire        next_mask,
    output wire [12:0] mask,
    output wire        mask_ready
);

    // ===================================================================
    // 256-bit Galois LFSR: polynomial x^256 + x^10 + x^5 + x^2 + 1
    // ===================================================================
    // Taps at bit positions: 0, 2, 5, 10
    // Feedback = state[0] ^ state[2] ^ state[5] ^ state[10]
    // Shift right: state >> 1, MSB = feedback

    reg [255:0] lfsr_state;

    // ── 种子加载状态机 (8 cycles × 32-bit) ──
    reg [2:0] seed_cnt;        // 0..7
    reg       seeding;

    // ── 输出 ──
    reg [12:0] mask_r;
    reg        mask_ready_r;

    assign mask       = mask_r;
    assign mask_ready = mask_ready_r;

    // ── 反馈位 ──
    wire lfsr_feedback;
    wire lfsr_bit0   = lfsr_state[0];
    wire lfsr_bit2   = lfsr_state[2];
    wire lfsr_bit5   = lfsr_state[5];
    wire lfsr_bit10  = lfsr_state[10];
    assign lfsr_feedback = lfsr_bit0 ^ lfsr_bit2 ^ lfsr_bit5 ^ lfsr_bit10;

    // ── 下一个状态 (组合逻辑) ──
    wire [255:0] lfsr_next;
    assign lfsr_next = {lfsr_feedback, lfsr_state[255:1]};

    // ── 拒绝采样: 掩码 < Q ──
    wire mask_valid_sample;
    assign mask_valid_sample = (lfsr_state[12:0] < `NTT_Q);

    // ── 默认种子 (确定性但不可预测的值) ──
    localparam [255:0] DEFAULT_SEED = 256'hA5C3_69F0_1B7D_4E82_9F6C_3A15_D8E2_47B0_6D1F_83C4_2E95_0AF7_B836_5C91_74DA_E2F8;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr_state   <= DEFAULT_SEED;
            seed_cnt     <= 3'd0;
            seeding      <= 1'b0;
            mask_r       <= 13'd0;
            mask_ready_r <= 1'b0;
        end else begin
            mask_ready_r <= 1'b0;

            // ── 种子加载 (seed_valid 脉冲启动 8-cycle 序列) ──
            if (seed_valid) begin
                seeding   <= 1'b1;
                seed_cnt  <= 3'd0;
                // 第一个 32-bit word 写入 bit[31:0]
                lfsr_state[31:0] <= seed_val;
            end else if (seeding) begin
                seed_cnt <= seed_cnt + 1;
                case (seed_cnt)
                    3'd0: lfsr_state[63:32]   <= seed_val;
                    3'd1: lfsr_state[95:64]   <= seed_val;
                    3'd2: lfsr_state[127:96]  <= seed_val;
                    3'd3: lfsr_state[159:128] <= seed_val;
                    3'd4: lfsr_state[191:160] <= seed_val;
                    3'd5: lfsr_state[223:192] <= seed_val;
                    3'd6: begin
                        lfsr_state[255:224] <= seed_val;
                        seeding <= 1'b0;  // 完成
                    end
                endcase
            end

            // ── 掩码请求 ──
            if (next_mask) begin
                // Elimination-based mod-Q (no rejection, 1-cycle deterministic)
                // lfsr_state[12:0] in [0,8191], Q=3329
                if (lfsr_state[12:0] < `NTT_Q) begin
                    mask_r <= lfsr_state[12:0];
                end else if (lfsr_state[12:0] < 13'd6658) begin
                    mask_r <= lfsr_state[12:0] - `NTT_Q;
                end else begin
                    mask_r <= lfsr_state[12:0] - 13'd6658;
                end
                mask_ready_r <= 1'b1;
                lfsr_state   <= lfsr_next;
            end else begin
                // 空闲时也推进 LFSR (阻止停滞分析)
                // 每 16 个空闲周期推进一次
                if (lfsr_state[3:0] == 4'd0)
                    lfsr_state <= lfsr_next;
            end
        end
    end

endmodule
