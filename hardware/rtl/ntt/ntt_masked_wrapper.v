// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// ntt_masked_wrapper.v (v4) — pending-latch + PRNG 握手 + force_zeroize
// =============================================================================
// v4 变更 (2026-07-15):
//   (4) force_zeroize 端口: 断言时零化所有 mask_ram 地址 + 复位 FSM
//       hw_monitor_resp ZEROIZE 状态驱动, 至少保持 512 拍 (50MHz=10.24µs)
//
// v3 变更 (2026-07-06):
//   (1) bf_valid→pending latch: 单拍脉冲被 latch, wrapper 自己节奏消费
//   (2) PRNG 握手: RS_GEN_A/B 中保持 prng_req=1, 解决 rejection 死锁
//   (3) bf_ready = RS_IDLE && !pending (防止双 latch)
//
// v2 特性 (保留):
//   去掩: combinational (mod_sub via mask_ram) — 0 周期
//   重掩: RS_IDLE→RS_GEN_A→RS_GEN_B→RS_OUT — 最少 4 周期 (等两遍 PRNG)
//   remask_valid 在 RS_OUT 断言
// =============================================================================

`include "params.vh"

module ntt_masked_wrapper (
    input  wire clk, rst_n,

    // ── 去掩 (combinational, S_LOAD→S_BFLY 之间) ──
    input  wire [7:0]  rd_addr_a, rd_addr_b,
    input  wire [12:0] ram_data_a, ram_data_b,
    output wire [12:0] unmasked_a, unmasked_b,  // → BF input

    // ── 重掩输入 (来自 BF 输出 + 地址队列) ──
    input  wire        bf_valid,
    input  wire [12:0] bf_a_raw, bf_b_raw,
    input  wire [7:0]  wa_a, wa_b,

    // ── 重掩输出 (→ Writeback FSM) ──
    output wire [12:0] masked_a, masked_b,
    output wire        remask_valid,

    // ── 背压: wrapper 可以接受下一个 bf_valid ──
    output wire        bf_ready,

    // ── 控制 ──
    input  wire mask_enable,

    // ── PRNG ──
    output reg  prng_req,
    input  wire [12:0] prng_val,
    input  wire prng_rdy,

    // ── 零化 (来自 hw_monitor_resp) ──
    input  wire        force_zeroize
);

    // ===================================================================
    // Mask RAM (256×13 dual-read, single-write)
    // ===================================================================
    wire [12:0] mram_a, mram_b;

    mask_ram u_mram (
        .clk(clk),
        .raddr_a(rd_addr_a), .rdata_a(mram_a),
        .raddr_b(rd_addr_b), .rdata_b(mram_b),
        .wen(mram_wen), .waddr(mram_waddr), .wdata(mram_wdata)
    );

    // ===================================================================
    // 去掩: raw = ram - mask (combinational)
    // ===================================================================
    wire [12:0] sub_a, sub_b;
    mod_sub u_usub_a (.a(ram_data_a), .b(mram_a), .result(sub_a));
    mod_sub u_usub_b (.a(ram_data_b), .b(mram_b), .result(sub_b));
    assign unmasked_a = mask_enable ? sub_a : ram_data_a;
    assign unmasked_b = mask_enable ? sub_b : ram_data_b;

    // ===================================================================
    // 重掩: masked = raw + new_mask (combinational)
    // ===================================================================
    reg  [12:0] mask_new_a_r, mask_new_b_r;
    reg  [12:0] bf_a_latched, bf_b_latched;
    reg  [7:0]  wa_a_latched, wa_b_latched;

    wire [12:0] add_a, add_b;
    mod_add u_uadd_a (.a(bf_a_latched), .b(mask_new_a_r), .result(add_a));
    mod_add u_uadd_b (.a(bf_b_latched), .b(mask_new_b_r), .result(add_b));
    assign masked_a = mask_enable ? add_a : bf_a_latched;
    assign masked_b = mask_enable ? add_b : bf_b_latched;

    // ===================================================================
    // pending latch — 核心修复
    // ===================================================================
    // bf_valid 是单拍脉冲 (from butterfly_unif.out_valid edge detection).
    // wrapper 需要 ~4 cycles 处理一个 BF (等两遍 PRNG).
    // pending flag latch 住脉冲，wrapper 用自己的节奏消费。
    // bf_ready = RS_IDLE && !bf_start_req: 确保收到 BF_START 后不再接受下一发
    // bf_start_req: BF_START 已到但尚未进入 READ_B（等 PRNG handshake）

    reg pending;        // 1 = bf_valid pulse latched, not yet consumed
    reg bf_start_req;  // 1 = BF_START received, waiting to enter READ_B

    // ── 背压: IDLE 且无任何未完成操作时才接受新 BF_START ──
    // bf_start_req: BF_START 已到但尚未进入 REMASK 流水线
    // pending: bf_valid 已到但 REMASK 流水线尚未完成
    assign bf_ready = (rs == RS_IDLE) && !bf_start_req && !pending;

    // ===================================================================
    // 重掩流水线: IDLE → READ_B → GEN_A → GEN_B → OUTPUT
    //
    // BF_START 握手协议:
    //   1. Core 拉高 BF_START (在 bf_ready 高时)
    //   2. Wrapper: bf_ready 立即拉低 (通知 core 别再发)
    //      BF_START 在本周期被 latch → bf_start_req=1
    //   3. Core 看到 bf_ready 低 → 拉低 BF_START
    //   4. Wrapper: bf_start_req 保持 (等待进入 REMASK)
    //   5. Wrapper 进入 READ_B (等 BF_START 下降后)
    //      → 进入 GEN_A 开始取掩码 → 完成 REMASK
    //   6. 返回 IDLE → bf_start_req=0, bf_ready=1 → core 可发下一发
    //
    // bf_valid 处理 (但terfly 结果返回):
    //   - 在 IDLE 时被 pending latch 住，进入 REMASK 流水线
    // ===================================================================
    localparam RS_IDLE=0, RS_READ_B=1, RS_GEN_A=2, RS_GEN_B=3, RS_OUT=4;
    localparam RS_WIDTH=3;
    reg [RS_WIDTH-1:0] rs;
    reg       remask_valid_r;

    // 掩码 RAM 写回
    reg        mram_wen;
    reg  [7:0] mram_waddr;
    reg  [12:0] mram_wdata;

    assign remask_valid = remask_valid_r;

    // ===================================================================
    // 零化地址计数器
    // ===================================================================
    reg [8:0] zz_addr;  // 9-bit: 0..511 (mem_a 256 + mem_b 256)
    wire zz_done;
    assign zz_done = (zz_addr >= 9'd511);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rs <= RS_IDLE;
            pending <= 1'b0;
            prng_req <= 1'b0;
            mask_new_a_r <= 13'd0;
            mask_new_b_r <= 13'd0;
            bf_a_latched <= 13'd0;
            bf_b_latched <= 13'd0;
            wa_a_latched <= 8'd0;
            wa_b_latched <= 8'd0;
            remask_valid_r <= 1'b0;
            mram_wen <= 1'b0;
            mram_waddr <= 8'd0;
            mram_wdata <= 13'd0;
            bf_start_req <= 1'b0;
            zz_addr <= 9'd0;
        end else begin
            prng_req <= 1'b0;
            mram_wen <= 1'b0;
            remask_valid_r <= 1'b0;

            // ════════════════════════════════════════════════
            // force_zeroize: 无条件零化 mask_ram
            // 遍历 512 个地址 (mem_a 0..255, mem_b 0..255)
            // 写入 wdata=0, 强制复位 FSM
            // ════════════════════════════════════════════════
            if (force_zeroize) begin
                rs          <= RS_IDLE;
                pending     <= 1'b0;
                bf_start_req <= 1'b0;
                mram_wen    <= 1'b1;
                mram_wdata  <= 13'd0;
                mram_waddr  <= zz_addr[7:0];
                zz_addr     <= zz_addr + 1;
                // zz_addr[7:0] 循环覆盖 0..255;
                // zz_addr 达到 511 后, hw_monitor_resp 在 ZEROIZE 保持足够拍后
                // 释放 force_zeroize → 这里正常退出
                prng_req    <= 1'b0;
                remask_valid_r <= 1'b0;
            end else begin
                zz_addr <= 9'd0;  // 零化完成后复位计数器

            // ── pending latch: 捕获 bf_valid 脉冲 ──
            if (bf_valid && !pending && rs == RS_IDLE) begin
                bf_a_latched <= bf_a_raw;
                bf_b_latched <= bf_b_raw;
                wa_a_latched <= wa_a;
                wa_b_latched <= wa_b;
                pending <= 1'b1;
            end

            // ── BF_START 握手: 收到则 latch, 等 bf_ready 拉低后再处理 ──

            case (rs)
                RS_IDLE: begin
                    // bf_start_req 清零: 进入 IDLE 即表示上一发已处理完
                    bf_start_req <= 1'b0;

                    // bf_valid (butterfly 结果) 优先: 捕获并进入 REMASK
                    if (pending) begin
                        if (mask_enable) begin
                            prng_req <= 1'b1;
                            rs <= RS_GEN_A;
                        end else begin
                            // bypass: 不需要掩码, 直接输出
                            remask_valid_r <= 1'b1;
                            pending <= 1'b0;
                        end
                    end
                    // bf_start (新 butterfly): 握手等待
                    // bf_ready 立即拉低 (见上面 assign)，core 看到后拉低 BF_START
                end

                RS_READ_B: begin
                    // bf_start_req 在这里不清零（保持 BF_START 已被接收的标志）
                    // 进入 RS_GEN_A 后才清零
                    // 如果 pending 也来了（bf_valid 在 BF_START 之后到达），
                    // 先完成当前 BF 的 REMASK，再处理 pending
                    if (pending) begin
                        // 当前 BF 的 REMASK 已完成（进入 RS_IDLE），
                        // 但 pending 已在 IDLE 被 latch 并立即进入这里
                        // → 直接开始 pending 的 REMASK（mask 已足够）
                        if (mask_enable) begin
                            prng_req <= 1'b1;
                            rs <= RS_GEN_A;
                        end else begin
                            remask_valid_r <= 1'b1;
                            pending <= 1'b0;
                        end
                    end
                    // bf_start_req 在进入 RS_GEN_A 时清零
                end

                RS_GEN_A: begin
                    bf_start_req <= 1'b0;  // 清除握手标志: BF_START 已处理
                    prng_req <= 1'b1;      // hold until rdy (no rejection deadlock)
                    if (prng_rdy) begin
                        mask_new_a_r <= prng_val;
                        rs <= RS_GEN_B;
                    end
                end

                RS_GEN_B: begin
                    prng_req <= 1'b1;  // hold until rdy
                    if (prng_rdy) begin
                        mask_new_b_r <= prng_val;
                        remask_valid_r <= 1'b1;
                        // 写回 mask_a → mask_ram
                        mram_wen   <= 1'b1;
                        mram_waddr <= wa_a_latched;
                        mram_wdata <= mask_new_a_r;
                        rs <= RS_OUT;
                    end
                end

                RS_OUT: begin
                    // 写回 mask_b → mask_ram, 清除 pending
                    mram_wen   <= 1'b1;
                    mram_waddr <= wa_b_latched;
                    mram_wdata <= mask_new_b_r;
                    pending <= 1'b0;
                    rs <= RS_IDLE;
                end

                default: rs <= RS_IDLE;
            endcase
            end  // else: not force_zeroize
        end
    end

endmodule
