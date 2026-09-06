// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// hw_monitor_resp.v (v2) — 硬件安全监视器 + 故障响应 FSM
// =============================================================================
// v2 新增 (2026-07-15):
//   (1) 三级响应 FSM: MONITOR → WARN → TRIP → ZEROIZE → RECOVER
//   (2) force_zeroize 输出 → 驱动 mask_ram 零化 + 重掩 FSM 复位
//   (3) sw_irq 输出 → CPU 中断通知
//   (4) clk_enable 输出 → NTT 时钟门控（TRIP 后关断）
//   (5) 可配置阈值 (WARN_THRESH, TRIP_THRESH)
//   (6) 状态寄存器扩展为 5 个 (含 resp_state)
//
// 响应策略（三级联动）:
//   MONITOR: 正常检测，计数累积。错误数 < WARN_THRESH
//   WARN:    单类型错误 ≥ WARN_THRESH 或总错误 ≥ WARN_THRESH×2
//             → hw_alert_pulse 改为 3 拍拉伸，LED 闪烁加速 4×
//   TRIP:    总错误 ≥ TRIP_THRESH 或 alert_count ≥ 4
//             → force_zeroize 断言，clk_enable 低电平，sw_irq 置位
//   ZEROIZE: hold force_zeroize 最少 16 拍，等待 mask_ram 清零传播
//   RECOVER: 释放 force_zeroize，复位故障计数器，返回 MONITOR
//
// 零化范围:
//   - mask_ram (256×13): 全部写 0 → unmask=ram XOR mask = ram (无破坏性)
//   - ntt_masked_wrapper: 重掩 FSM → RS_IDLE, pending=0
//   - ntt_core_pipe2: 流水线 flush (通过复位 NTT 子模块)
// =============================================================================
// MIT License

module hw_monitor_resp #(
    parameter  WARN_THRESH   = 3,       // 单类型错误达到 N → WARN
    parameter  TRIP_THRESH   = 8,       // 总错误累计 ≥ N → TRIP
    parameter  ZEROIZE_CYCLES = 512,    // force_zeroize 保持拍数 (≥512 遍历 mask_ram 全部 256×2 地址)
    parameter  RECOVER_HOLD  = 100      // RECOVER 后复位计数器 hold 拍
) (
    input  wire         clk,
    input  wire         rst_n,

    // ── 监视器输入 ──
    input  wire         fault_alert,
    input  wire [3:0]   fault_type,      // {bf_mismatch, parity, remo, cycle}
    input  wire [15:0]  ntt_cycle_count,
    input  wire         ntt_done,

    input  wire         led_int0,        // heartbeat from top

    // ── 响应输出 ──
    output reg          force_zeroize,   // → mask_ram 零化 + FSM 复位
    output reg          clk_enable,      // → NTT 时钟门控
    output reg          sw_irq,          // → CPU 中断 (电平触发)
    output reg  [3:0]   led,             // [0]=heartbeat [1]=warn [2]=trip [3]=pass

    // ── 状态寄存器 (SW 可读) ──
    output wire [31:0]  status_reg_0,    // {fault_count[16], alert_count[16]}
    output wire [31:0]  status_reg_1,    // {bf_mismatch[8], parity[8], remo[8], cycle[8]}
    output wire [31:0]  status_reg_2,    // {resp_state[8], last_fault_cycle[16]}
    output wire [31:0]  status_reg_3,    // {zeroize_count[16], warn_count[16]}
    output wire [31:0]  status_reg_4     // {trip_clks[24], sw_irq_pending[8]}
);

    // ================================================================
    // 响应 FSM 状态
    // ================================================================
    localparam [2:0]
        S_MONITOR = 3'd0,
        S_WARN    = 3'd1,
        S_TRIP    = 3'd2,
        S_ZEROIZE = 3'd3,
        S_RECOVER = 3'd4;

    reg [2:0]  resp_state, resp_state_next;

    // ================================================================
    // 故障计数器
    // ================================================================
    reg [15:0] fault_count;
    reg [15:0] alert_count;
    reg [7:0]  bf_mismatch_errs;
    reg [7:0]  parity_errs;
    reg [7:0]  remo_errs;
    reg [7:0]  cycle_errs;
    reg [15:0] last_fault_cycle;

    reg [15:0] warn_count;       // 进入 WARN 状态计数
    reg [15:0] zeroize_count;    // 零化事件计数
    reg [23:0] trip_clks;        // TRIP 状态保持的时钟数

    // ================================================================
    // 心跳发生器
    // ================================================================
    reg [23:0] hb_cnt;
    wire hb_tick;
    assign hb_tick = (hb_cnt == 24'd12_000_000);
    wire hb_fast;                // WARN 状态下加速 4×
    assign hb_fast = (hb_cnt == 24'd3_000_000);

    // ================================================================
    // 零化计时器
    // ================================================================
    reg [7:0] zz_cnt;

    // ================================================================
    // 状态寄存器连线
    // ================================================================
    assign status_reg_0 = {fault_count, alert_count};
    assign status_reg_1 = {bf_mismatch_errs, parity_errs, remo_errs, cycle_errs};
    assign status_reg_2 = {16'd0, resp_state, 5'd0, last_fault_cycle[10:0]};
    assign status_reg_3 = {zeroize_count, warn_count};
    assign status_reg_4 = {trip_clks, 8'd0};

    // ================================================================
    // FSM 次态逻辑
    // ================================================================
    always @(*) begin
        resp_state_next = resp_state;
        case (resp_state)
            S_MONITOR: begin
                // 单类型错误 ≥ WARN_THRESH 或总错误 ≥ WARN_THRESH×2 → WARN
                if ( (bf_mismatch_errs >= WARN_THRESH) ||
                     (parity_errs       >= WARN_THRESH) ||
                     (remo_errs         >= WARN_THRESH) ||
                     (cycle_errs        >= WARN_THRESH) ||
                     (fault_count       >= (WARN_THRESH * 2)) )
                    resp_state_next = S_WARN;
                // 总错误 ≥ TRIP_THRESH → 直接 TRIP（跳过 WARN）
                if (fault_count >= TRIP_THRESH)
                    resp_state_next = S_TRIP;
            end

            S_WARN: begin
                if (fault_count >= TRIP_THRESH)
                    resp_state_next = S_TRIP;
                if (alert_count >= 4)
                    resp_state_next = S_TRIP;
                // 如果故障自动清零（NTT 成功完成无新故障）→ 回 MONITOR
                if (ntt_done && (fault_count == 0))
                    resp_state_next = S_MONITOR;
            end

            S_TRIP: begin
                // TRIP 保持至少 100 拍确保 CPU 收到 sw_irq
                if (trip_clks >= 24'd100)
                    resp_state_next = S_ZEROIZE;
            end

            S_ZEROIZE: begin
                // 保持 force_zeroize ZEROIZE_CYCLES 拍
                if (zz_cnt >= ZEROIZE_CYCLES)
                    resp_state_next = S_RECOVER;
            end

            S_RECOVER: begin
                // RECOVER 保持 RECOVER_HOLD 拍，等待状态稳定
                if (zz_cnt >= RECOVER_HOLD)
                    resp_state_next = S_MONITOR;
            end
        endcase
    end

    // ================================================================
    // 主时序逻辑
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            resp_state        <= S_MONITOR;
            fault_count       <= 16'd0;
            alert_count       <= 16'd0;
            bf_mismatch_errs  <= 8'd0;
            parity_errs       <= 8'd0;
            remo_errs         <= 8'd0;
            cycle_errs        <= 8'd0;
            last_fault_cycle  <= 16'd0;
            warn_count        <= 16'd0;
            zeroize_count     <= 16'd0;
            trip_clks         <= 24'd0;
            hb_cnt            <= 24'd0;
            zz_cnt            <= 8'd0;
            force_zeroize     <= 1'b0;
            clk_enable        <= 1'b1;
            sw_irq            <= 1'b0;
            led               <= 4'b0000;
        end else begin
            // ── 状态转移 ──
            resp_state <= resp_state_next;

            // ── 心跳 (WARN 状态加速) ──
            if (resp_state == S_WARN) begin
                if (hb_fast) begin
                    hb_cnt <= 24'd0;
                    led[0] <= ~led[0];
                end else begin
                    hb_cnt <= hb_cnt + 1;
                end
            end else begin
                if (hb_tick) begin
                    hb_cnt <= 24'd0;
                    led[0] <= ~led[0];
                end else begin
                    hb_cnt <= hb_cnt + 1;
                end
            end

            // ── 故障采集 (仅在 MONITOR / WARN 状态) ──
            if ((resp_state == S_MONITOR) || (resp_state == S_WARN)) begin
                if (fault_alert) begin
                    fault_count      <= fault_count + 1;
                    last_fault_cycle <= ntt_cycle_count;

                    if (fault_type[3]) bf_mismatch_errs <= bf_mismatch_errs + 1;
                    if (fault_type[2]) parity_errs       <= parity_errs + 1;
                    if (fault_type[1]) remo_errs         <= remo_errs + 1;
                    if (fault_type[0]) cycle_errs        <= cycle_errs + 1;

                    alert_count <= alert_count + 1;
                end

                // NTT 成功完成 → 复位 pass LED
                if (ntt_done && (fault_count == 0)) begin
                    led[3] <= 1'b1;   // pass on
                    led[1] <= 1'b0;
                end
            end

            // ── WARN 状态 ──
            if (resp_state_next == S_WARN) begin
                warn_count <= warn_count + 1;
                if (resp_state != S_WARN) begin
                    led[1] <= 1'b1;   // warn LED on
                    led[3] <= 1'b0;
                end
            end

            // ── TRIP 状态 ──
            if (resp_state_next == S_TRIP) begin
                if (resp_state != S_TRIP) begin
                    // 首次进入 TRIP
                    clk_enable   <= 1'b0;      // 门控 NTT 时钟
                    sw_irq       <= 1'b1;      // 触发 CPU 中断
                    trip_clks    <= 24'd0;
                    led[2]       <= 1'b1;       // trip LED on
                    led[1]       <= 1'b0;
                end else begin
                    trip_clks    <= trip_clks + 1;
                end
            end

            // ── ZEROIZE 状态 ──
            if (resp_state_next == S_ZEROIZE) begin
                force_zeroize <= 1'b1;
                zeroize_count <= zeroize_count + 1;
                if (resp_state != S_ZEROIZE) begin
                    zz_cnt <= 8'd0;
                end else begin
                    zz_cnt <= zz_cnt + 1;
                end
            end

            // ── RECOVER 状态 ──
            if (resp_state_next == S_RECOVER) begin
                force_zeroize <= 1'b0;          // 释放零化
                clk_enable    <= 1'b1;          // 恢复时钟
                sw_irq        <= 1'b0;          // 清除中断
                if (resp_state != S_RECOVER) begin
                    zz_cnt <= 8'd0;
                end else begin
                    zz_cnt <= zz_cnt + 1;
                end
                // 在 RECOVER 末尾复位故障计数器
                if (zz_cnt == (RECOVER_HOLD - 2)) begin
                    fault_count      <= 16'd0;
                    alert_count      <= 16'd0;
                    bf_mismatch_errs <= 8'd0;
                    parity_errs      <= 8'd0;
                    remo_errs        <= 8'd0;
                    cycle_errs       <= 8'd0;
                    led              <= 4'b0001;  // 仅 pass 亮
                end
            end

            // ── NTT 成功完成时清除状态（只在 MONITOR） ──
            if ((resp_state == S_MONITOR) && ntt_done && (fault_count == 0)) begin
                led[3] <= 1'b1;
            end
        end
    end

endmodule
