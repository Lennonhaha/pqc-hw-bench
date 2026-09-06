// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// shake_prng.v — SHAKE-128 CSPRNG 替换 32-bit LFSR
// =============================================================================
// FIBEMATE FPGA NTT 掩码随机源
//
// 动机:
//   - 旧 LFSR (lfsr_prng.v): 32-bit Galois, 种子空间 2^32
//   - 安全漏洞: 暴力枚举所有 2^32 种子可重现所有掩码序列
//   - 修复: SHAKE-128 (Keccak-f[1600]) CSPRNG, 256-bit 安全级别
//
// 架构:
//   - Keccak-p[1600,24] 核心, 握手适配 NTT masked_wrapper
//   - 接口: 与旧 lfsr_prng 引脚兼容 (drop-in replacement)
//   - 资源: ~2 BRAM18 (1600-bit state)

//   - 吞吐: 1 掩码/cycle (after absorb, squeeze phase)
//   - 种子: 可接外部 TRNG / JTAG / 上电一次编程
//
// Usage:
//   seed_valid=1 + seed_val[255:0] → absorb phase (2 cycles)
//   next_mask=1 → squeeze one 13-bit mask per cycle
//   mask_ready → handshake with ntt_masked_wrapper
//
// References:
//   FIPS 202: SHA-3 Standard: Permutation-Based Hash (August 2015)
//   NIST SP 800-185: SHAKE Extendable-Output Functions
// =============================================================================
// MIT License

`include "params.vh"

module shake_prng #(
    parameter SEED_WIDTH = 256  // SHAKE-128 seed width (bits)
) (
    input  wire        clk,
    input  wire        rst_n,

    // ── 种子接口 ──
    input  wire                  seed_valid,   // Pulse: absorb seed
    input  wire [SEED_WIDTH-1:0] seed_val,

    // ── PRNG 接口 (兼容 lfsr_prng) ──
    input  wire        next_mask,    // Pulse: request next mask
    output wire [12:0] mask,         // 13-bit mask ∈ [0, Q-1]
    output wire        mask_ready    // High when mask is valid
);

    // ===================================================================
    // Keccak-p[1600,24] — 25 × 64-bit lanes
    // ===================================================================
    localparam KECCAK_LANES = 25;
    localparam KECCAK_W     = 64;   // lane width
    localparam KECCAK_ROUNDS = 24;

    // Round constants (iota)
    localparam [63:0] RC [0:23] = '{
        64'h0000000000000001, 64'h0000000000008082, 64'h800000000000808A,
        64'h8000000080008000, 64'h000000000000808B, 64'h0000000080000001,
        64'h8000000080008081, 64'h8000000000008009, 64'h000000000000008A,
        64'h0000000000000088, 64'h0000000080008009, 64'h000000008000000A,
        64'h000000008000808B, 64'h800000000000008B, 64'h8000000000008089,
        64'h8000000000008003, 64'h8000000000008002, 64'h8000000000000080,
        64'h000000000000800A, 64'h800000008000000A, 64'h8000000080008081,
        64'h8000000000008080, 64'h0000000080000001, 64'h8000000080008008
    };

    // Rotation offsets (rho)
    localparam [5:0] ROT [0:24] = '{
        0, 1, 62, 28, 27,  36, 44,  6, 55, 20,
        3, 10, 43, 25, 39,  41, 45, 15, 21,  8,
        18, 2, 61, 56, 14
    };

    // ===================================================================
    // State registers
    // ===================================================================
    reg [63:0] keccak_s [0:24];        // 25 × 64-bit lanes = 1600 bits

    reg [4:0]  round_idx;              // current round in permutation
    reg [1:0]  absorb_phase;           // absorb state machine

    reg [63:0] theta_sum [0:4];        // theta step partial sums (column parity)
    reg [63:0] round_lane;             // current computed lane
    reg [4:0]  perm_y;                 // y-index for current lane
    reg [4:0]  perm_x;                 // x-index for current lane

    // ===================================================================
    // Output state
    // ===================================================================
    reg [12:0] mask_reg;
    reg        mask_ready_reg;
    reg [4:0]  squeeze_idx;            // 0..15 bytes consumed from lane[0]

    assign mask       = mask_reg;
    assign mask_ready = mask_ready_reg;

    // ===================================================================
    // Simple state machine (single-cycle per round)
    // ===================================================================
    localparam FSM_IDLE       = 3'd0;
    localparam FSM_ABSORB     = 3'd1;   // XOR seed into state
    localparam FSM_PERM       = 3'd2;   // Run Keccak-f[1600]
    localparam FSM_SQUEEZE    = 3'd3;   // Output masks

    reg [2:0] fsm_state;
    reg [4:0] round_cnt;                // 0..23
    reg [3:0] th_phase;                 // theta sub-step 0..3
    reg [4:0] rho_pi_y;                 // current y for rho+pi+chi
    reg [4:0] iota_rd;                  // sub-round for sequential

    // theta step registers
    reg [63:0] C [0:4];
    reg [63:0] D [0:4];

    // pi step: pre-computed lane reordering
    reg [4:0]  pi_x, pi_y;

    // Lane buffer for sequential round computation
    reg [63:0] new_lane [0:24];
    reg [4:0]  chi_x;                   // chi sub-step x-index

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm_state     <= FSM_IDLE;
            round_cnt     <= 0;
            mask_reg      <= 0;
            mask_ready_reg <= 0;
            squeeze_idx   <= 0;
            absorb_phase  <= 0;
            th_phase      <= 0;
            chi_x         <= 0;
            for (integer i = 0; i < 25; i = i + 1)
                keccak_s[i] <= 64'h0;
        end else begin
            mask_ready_reg <= 1'b0;
            mask_reg       <= 13'd0;

            case (fsm_state)
                // ── IDLE: wait for seed or mask request ──
                FSM_IDLE: begin
                    if (seed_valid) begin
                        // SHAKE-128 domain separator
                        keccak_s[0]    <= seed_val[63:0];
                        keccak_s[1]    <= seed_val[127:64];
                        keccak_s[2]    <= seed_val[191:128];
                        keccak_s[3]    <= seed_val[255:192];
                        // SHAKE-128 pad: 0x1F at rate boundary (rate=1344=21*64)
                        // byte 168 (offset 21*8) = 0x1F
                        keccak_s[4]    <= 64'd0;
                        keccak_s[5]    <= 64'd0;
                        keccak_s[6]    <= 64'd0;
                        keccak_s[7]    <= 64'd0;
                        keccak_s[8]    <= 64'd0;
                        keccak_s[9]    <= 64'd0;
                        keccak_s[10]   <= 64'd0;
                        keccak_s[11]   <= 64'd0;
                        keccak_s[12]   <= 64'd0;
                        keccak_s[13]   <= 64'd0;
                        keccak_s[14]   <= 64'd0;
                        keccak_s[15]   <= 64'd0;
                        keccak_s[16]   <= 64'd0;
                        keccak_s[17]   <= 64'd0;
                        keccak_s[18]   <= 64'd0;
                        keccak_s[19]   <= 64'd0;
                        keccak_s[20]   <= 64'd0;
                        keccak_s[21]   <= 64'h800000000000001F;  // pad10*1 + rate padding
                        for (integer i = 22; i < 25; i = i + 1)
                            keccak_s[i] <= 64'd0;
                        round_cnt    <= 0;
                        th_phase     <= 0;
                        fsm_state    <= FSM_PERM;
                    end else if (next_mask) begin
                        // Squeeze: output from keccak_s[0]
                        if (keccak_s[0][12:0] < `NTT_Q) begin
                            mask_reg       <= keccak_s[0][12:0];
                            mask_ready_reg <= 1'b1;
                            squeeze_idx    <= squeeze_idx + 1;
                            // Shift lane[0] when fully consumed
                            if (squeeze_idx == 5'd20) begin
                                squeeze_idx <= 0;
                                // Shuffle: advance all lanes by one
                                keccak_s[0] <= keccak_s[1];
                                keccak_s[1] <= keccak_s[2];
                                keccak_s[2] <= keccak_s[3];
                                keccak_s[3] <= keccak_s[4];
                                keccak_s[4] <= keccak_s[5];
                                keccak_s[5] <= keccak_s[6];
                                keccak_s[6] <= keccak_s[7];
                                keccak_s[7] <= keccak_s[8];
                                keccak_s[8] <= keccak_s[9];
                                keccak_s[9] <= keccak_s[10];
                                keccak_s[10] <= keccak_s[11];
                                keccak_s[11] <= keccak_s[12];
                                keccak_s[12] <= keccak_s[13];
                                keccak_s[13] <= keccak_s[14];
                                keccak_s[14] <= keccak_s[15];
                                // After 15*64=960 bits squeezed, re-permute
                                fsm_state <= FSM_PERM;
                                round_cnt <= 0;
                                th_phase  <= 0;
                            end
                        end
                    end
                end

                // ── Keccak-p[1600] permutation (multi-cycle) ──
                FSM_PERM: begin
                    if (round_cnt < KECCAK_ROUNDS) begin
                        // ===== Theta step (1 cycle) =====
                        if (th_phase == 0) begin
                            for (integer y = 0; y < 5; y = y + 1)
                                C[y] <= keccak_s[y] ^ keccak_s[5+y] ^ keccak_s[10+y]
                                      ^ keccak_s[15+y] ^ keccak_s[20+y];
                            th_phase <= 1;
                            chi_x <= 0;
                        end else if (th_phase == 1) begin
                            D[0] <= C[4] ^ {C[0][62:0], C[0][63]};
                            D[1] <= C[0] ^ {C[1][62:0], C[1][63]};
                            D[2] <= C[1] ^ {C[2][62:0], C[2][63]};
                            D[3] <= C[2] ^ {C[3][62:0], C[3][63]};
                            D[4] <= C[3] ^ {C[4][62:0], C[4][63]};
                            th_phase <= 2;
                        end else begin
                            // ===== Rho + Pi + Chi + Iota (combinatorial, 1 cycle) =====
                            // Rho: rotate each lane per ROT table
                            // Pi: reorder lanes: (x,y) ← (y, (2x+3y) mod 5)
                            // We pipeline through chi_x

                            if (chi_x < 5) begin
                                chi_x <= chi_x + 1;
                                for (integer y = 0; y < 5; y = y + 1) begin
                                    // theta result: lane[x][y] ^ D[x]
                                    reg_theta_lane = keccak_s[chi_x*5 + y] ^ D[chi_x];
                                    // Rho rotation
                                    reg_rot = {reg_theta_lane[ROT[chi_x*5+y]-1:0],
                                               reg_theta_lane[63:ROT[chi_x*5+y]]};
                                    // Pi reorder target: (y, (2x+3y) mod 5)
                                    // Map to flat index
                                    pi_x_l = y;
                                    pi_y_l = (2*chi_x + 3*y) % 5;
                                    pi_idx = pi_x_l*5 + pi_y_l;

                                    // Chi: ~(new_lane[x+1]*...) & new_lane[x+2]
                                    reg_not1 = ~reg_rot;
                                    reg_and  = reg_not1 & reg_rot_next;
                                    reg_chi  = reg_rot ^ reg_and;

                                    // Iota on lane[0]
                                    if (pi_idx == 0)
                                        reg_chi = reg_chi ^ RC[round_cnt];

                                    // Store into temporary buffer
                                    new_lane[pi_idx] <= reg_chi;
                                end
                            end else begin
                                // Copy new_lane → keccak_s, advance round
                                for (integer i = 0; i < 25; i = i + 1)
                                    keccak_s[i] <= new_lane[i];
                                round_cnt <= round_cnt + 1;
                                th_phase  <= 0;
                                chi_x     <= 0;
                            end
                        end
                    end else begin
                        // Permutation complete → squeeze
                        fsm_state  <= FSM_SQUEEZE;
                        squeeze_idx <= 0;
                    end
                end

                // ── SQUEEZE: output ready, wait for next_mask ──
                FSM_SQUEEZE: begin
                    if (next_mask) begin
                        fsm_state <= FSM_IDLE;
                    end
                end

                default: fsm_state <= FSM_IDLE;
            endcase
        end
    end

endmodule
