// =============================================================================
// FIBEMATE FPGA — ML-KEM NTT 全局参数
// =============================================================================
// ML-KEM (FIPS 203) 数论变换 (NTT) 核心常数
// 
// 数学背景:
//   ML-KEM 运行在素数域 Z_q = Z_3329 上
//   NTT 使用 ψ = 17 作为 256 次本原单位根 (ψ^256 ≡ 1 mod q)
// 
// Montgomery 模乘:
//   R = 2^14 = 16384 (> q = 3329, 14-bit Montgomery 域)
//   R·R^{-1} ≡ 1 mod q  →  R^{-1} = 676 (Montgomery 常数)
//   q·q^{-1} ≡ -1 mod R  →  q^{-1} = 3327 (Montgomery 归约因子)
//   验证: 3329 × 3327 mod 16384 = 16383 ≡ -1 mod 16384 ✓
//
// 蝶形运算 (Cooley-Tukey):
//   A' = (A + B×W) mod q
//   B' = (A - B×W) mod q
//   在 Montgomery 域: B×W = MontMul(B, W) = B × W × 676 mod q
//   因此: A' = (A + MontMul(B,W)) mod q
//
// 参考:
//   FIPS 203: ML-KEM (August 2024)
//   NIST PQ Standardization — Round 3 Submission
// =============================================================================
// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================

// ── ML-KEM 素数域参数 ──
`define NTT_Q         13'd3329   // ML-KEM 模数 q
`define NTT_Q_BITS    12         // 位宽 (0..3328, 需要 12 位 0-4095)

// ── Montgomery 常数 ──
`define NTT_Q_INV     14'd3327   // -q^{-1} mod 2^14 (归约因子)
                                 // ⚠️ 不是 q^{-1} mod 2^14 = 13057!
                                 // Montgomery 归约需要 负逆 而非 正逆
`define NTT_R         14'd16384  // Montgomery R = 2^14
`define NTT_SHIFT     4'd14      // 归约移位位数
`define NTT_R_INV     13'd676    // R^{-1} mod q (MontMul 输出校正)

// ── NTT 变换参数 ──
`define NTT_PSI       13'd17     // ψ = 17 (256次本原单位根, ψ^256 ≡ 1 mod 3329)
                                 // ML-KEM 所有安全级(512/768/1024)共用
`define NTT_N         9'd256     // 多项式度数 n = 256
`define NTT_LOG_N     4'd8       // log2(256) = 8

// ── 位反转查找表 (8-bit br(i) for i=0..255) ──
// 在 NTT 蝶形调度中使用 bit_reverse(i) 重排系数
`define NTT_BR_WIDTH  8          // 位反转位宽

// ── 流水线参数 ──
// 蝶形运算: 4 周期延迟 (see ntt_butterfly.v)
//   Stage 0..S6 (7 cycle latency, see ntt_butterfly_unif.v)
`define NTT_BF_LATENCY 7

// ── ML-KEM-768 特有参数 ──
`define MLKEM_K        3          // k=3 for ML-KEM-768
`define MLKEM_ETA1     2          // η₁=2
`define MLKEM_ETA2     2          // η₂=2
`define MLKEM_DU       10         // d_u=10
`define MLKEM_DV       4          // d_v=4
`define MLKEM_D        12         // 共享密钥比特数 d=12
