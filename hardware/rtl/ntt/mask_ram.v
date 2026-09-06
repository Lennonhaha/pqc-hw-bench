// Copyright 2026 Liu Tianhe (Lennonhaha)
// SPDX-License-Identifier: CERN-OHL-P-2.0
// =============================================================================
// mask_ram.v — 256×13-bit 双读口掩码 RAM
// =============================================================================
// 用途: 存储 NTT 加法掩码 (每系数一个 mask, 共 256 个)
// 读口: 两个独立异步读 (rdata_a, rdata_b) — 支持同时读取两个地址
// 写口: 单口同步写 (waddr + wdata + wen)
// 实现: 分布式 RAM (LUT RAM), 映射为 2×256 深度
// 资源: ~256 LUT (分布式), 可替代为 1 BRAM18 (若时序紧张)
//
// 注: 无 initial 块 (FPGA 合成不依赖). 上电默认掩码 = 0.
//     PRNG 在第一次 NTT 运行前需通过预填充周期加载掩码.
// =============================================================================

module mask_ram (
    input  wire        clk,
    input  wire [7:0]  raddr_a,
    output wire [12:0] rdata_a,
    input  wire [7:0]  raddr_b,
    output wire [12:0] rdata_b,
    input  wire        wen,
    input  wire [7:0]  waddr,
    input  wire [12:0] wdata
);

    reg [12:0] mem_a [0:255];
    reg [12:0] mem_b [0:255];

    // Simulation only: zero-init so unmask=ram[0]-0=ram[0] (no corruption)
    // In FPGA hardware, BRAM/LUT RAM defaults to 0; synthesis ignores initial.
    integer _mi;
    initial begin
        for (_mi = 0; _mi < 256; _mi = _mi + 1) begin
            mem_a[_mi] = 13'd0;
            mem_b[_mi] = 13'd0;
        end
    end

    assign rdata_a = mem_a[raddr_a];
    assign rdata_b = mem_b[raddr_b];

    always @(posedge clk) begin
        if (wen) begin
            mem_a[waddr] <= wdata;
            mem_b[waddr] <= wdata;
        end
    end

endmodule
