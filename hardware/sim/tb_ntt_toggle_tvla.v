// SPDX-License-Identifier: CERN-OHL-P-2.0
// Copyright 2026 Liu Tianhe (Lennonhaha)
// =============================================================================
// tb_ntt_toggle_tvla.v — B1: NTT toggle-count power model + TVLA/ADLA front-end
//
// Method (Telescope-style pre-silicon assessment):
//   Dynamic power proxy = Hamming Distance (bit toggles) on core data-path
//   signals, accumulated per NTT run. Two input groups (A=fixed patterns,
//   B=pseudo-random coeffs) are fed through the same NTT pipeline; the
//   resulting per-run toggle distributions are compared statistically by the
//   Python analyzer (Welch t-test + Anderson-Darling).
//
// Signals monitored (hierarchical refs into tensor_ntt_scheduler -> ntt_core_pipe):
//   - u_sched.gen_core_pipe.u_ntt_pipe.ram_din     : writeback data bus (core -> RAM)
//   - u_sched.gen_core_pipe.u_ntt_pipe.bf_a_out    : butterfly output A
//   - u_sched.gen_core_pipe.u_ntt_pipe.bf_b_out    : butterfly output B
//   - u_sched.ram_dout_a_w           : RAM read data A  (scheduler level)
//   - u_sched.ram_dout_b_w           : RAM read data B  (scheduler level)
//
// Usage: vvp tb_ntt_toggle_tvla.vvp < vectors file order A then B
//   Each input line = 256 hex coeffs; per line one full NTT is run and the
//   total toggle count is printed as: TOGGLE <group> <run> <count>
// =============================================================================
`timescale 1ns / 1ps

module tb_ntt_toggle_tvla;
    localparam CLK_PERIOD = 10;
    localparam N = 256;
    localparam RUNS_A = 128;
    localparam RUNS_B = 128;

    reg clk, rst_n;
    integer cycle;

    // ── scheduler interface ──
    reg         s_start, s_mode;
    wire        s_done;
    wire [3:0]  s_busy;
    reg         s_load_en;
    reg  [3:0]  s_load_poly, s_load_size;
    reg  [7:0]  s_load_addr;
    reg  [12:0] s_load_data;
    reg  [3:0]  s_read_poly;
    reg  [7:0]  s_read_addr;
    wire [12:0] s_read_data;
    wire [2:0]  s_dbg_state;

    // ── DUT: pipelined NTT via tensor scheduler ──
    tensor_ntt_scheduler #(.NUM_POLYS(1), .USE_PIPE(1)) u_sched (
        .clk(clk), .rst_n(rst_n),
        .start_i(s_start), .mode_i(s_mode), .done_o(s_done),
        .busy_poly(s_busy),
        .load_en(s_load_en), .load_poly(s_load_poly),
        .load_addr(s_load_addr), .load_data(s_load_data),
        .load_size(s_load_size),
        .read_poly(s_read_poly), .read_addr(s_read_addr),
        .read_data(s_read_data), .dbg_state(s_dbg_state)
    );

    // ── toggle accumulators ──
    // Hierarchical paths: u_sched.gen_core_pipe.u_ntt_pipe.* (USE_PIPE=1)
    integer tog_total;          // per-run total (all monitored signals)
    integer tog_wb;             // writeback bus
    integer tog_bfa, tog_bfb;   // butterfly outputs
    integer tog_rda, tog_rdb;   // RAM read buses
    reg [12:0] prev_wb, prev_bfa, prev_bfb, prev_rda, prev_rdb;
    reg started;

    // HD (popcount of 13-bit xor) as integer function
    function integer hd13;
        input [12:0] a;
        integer i, cnt;
        begin
            cnt = 0;
            for (i = 0; i < 13; i = i + 1)
                if (a[i]) cnt = cnt + 1;
            hd13 = cnt;
        end
    endfunction

    // ── per-cycle toggle accumulation (only while NTT busy) ──
    always @(posedge clk) begin
        if (!rst_n) begin
            prev_wb <= 0; prev_bfa <= 0; prev_bfb <= 0;
            prev_rda <= 0; prev_rdb <= 0;
        end else if (started) begin
            tog_wb  = tog_wb  + hd13(u_sched.gen_core_pipe.u_ntt_pipe.ram_din ^ prev_wb);
            tog_bfa = tog_bfa + hd13(u_sched.gen_core_pipe.u_ntt_pipe.bf_a_out ^ prev_bfa);
            tog_bfb = tog_bfb + hd13(u_sched.gen_core_pipe.u_ntt_pipe.bf_b_out ^ prev_bfb);
            tog_rda = tog_rda + hd13(u_sched.ram_dout_a_w ^ prev_rda);
            tog_rdb = tog_rdb + hd13(u_sched.ram_dout_b_w ^ prev_rdb);
            prev_wb  <= u_sched.gen_core_pipe.u_ntt_pipe.ram_din;
            prev_bfa <= u_sched.gen_core_pipe.u_ntt_pipe.bf_a_out;
            prev_bfb <= u_sched.gen_core_pipe.u_ntt_pipe.bf_b_out;
            prev_rda <= u_sched.ram_dout_a_w;
            prev_rdb <= u_sched.ram_dout_b_w;
        end
    end

    // ── clock ──
    initial begin clk = 0; forever #(CLK_PERIOD/2) clk = ~clk; end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycle <= 0; else cycle <= cycle + 1;
    end

    // ── vector file handle ──
    integer vf;
    reg [12:0] coeffs [0:N-1];
    integer addr, run, errors, v;

    // ── main ──
    initial begin
        $display("[B1] NTT toggle-count TVLA front-end");
        $display("[B1] Monitored: ram_din, bf_a_out, bf_b_out, ram_dout_a, ram_dout_b");

        rst_n = 0; s_start = 0; s_mode = 0; s_load_en = 0;
        s_load_poly = 0; s_load_addr = 0; s_load_data = 0; s_load_size = 1;
        s_read_poly = 0; s_read_addr = 0;
        tog_total = 0; tog_wb = 0; tog_bfa = 0; tog_bfb = 0;
        tog_rda = 0; tog_rdb = 0; started = 0; errors = 0;

        #(CLK_PERIOD * 5); rst_n = 1; #(CLK_PERIOD * 2);

        // ================= GROUP A =================
        vf = $fopen("sim/vectors_A.mem", "r");
        if (vf == 0) begin
            $display("[FATAL] cannot open sim/vectors_A.mem");
            $finish;
        end
        for (run = 0; run < RUNS_A; run = run + 1) begin
            // read one line of 256 coeffs
            for (addr = 0; addr < N; addr = addr + 1) begin
                v = $fscanf(vf, "%h", coeffs[addr]);
                if (v != 1) begin
                    $display("[FATAL] short read at A run %0d addr %0d", run, addr);
                    $finish;
                end
            end
            run_ntt_and_count(run, 65);  // 'A'
        end
        $fclose(vf);

        // ================= GROUP B =================
        vf = $fopen("sim/vectors_B.mem", "r");
        if (vf == 0) begin
            $display("[FATAL] cannot open sim/vectors_B.mem");
            $finish;
        end
        for (run = 0; run < RUNS_B; run = run + 1) begin
            for (addr = 0; addr < N; addr = addr + 1) begin
                v = $fscanf(vf, "%h", coeffs[addr]);
                if (v != 1) begin
                    $display("[FATAL] short read at B run %0d addr %0d", run, addr);
                    $finish;
                end
            end
            run_ntt_and_count(run, 66);  // 'B'
        end
        $fclose(vf);

        $display("[DONE] %0d runs complete. errors=%0d", RUNS_A + RUNS_B, errors);
        $finish;
    end

    // ── run one full NTT and emit toggle count ──
    task run_ntt_and_count;
        input integer run;
        input [7:0] grp_ch;   // 65='A' or 66='B'
        integer load_i;
        begin
            // load polynomial
            for (load_i = 0; load_i < N; load_i = load_i + 1) begin
                @(posedge clk);
                s_load_en <= 1;
                s_load_poly <= 0;
                s_load_addr <= load_i[7:0];
                s_load_data <= coeffs[load_i];
            end
            @(posedge clk); s_load_en <= 0;
            #(CLK_PERIOD * 2);

            // reset toggle accumulators
            tog_wb = 0; tog_bfa = 0; tog_bfb = 0;
            tog_rda = 0; tog_rdb = 0;
            prev_wb <= 0; prev_bfa <= 0; prev_bfb <= 0;
            prev_rda <= 0; prev_rdb <= 0;

            // start NTT (forward)
            @(posedge clk);
            s_mode <= 0;
            started <= 1;
            s_start <= 1;
            @(posedge clk); s_start <= 0;

            wait (s_done);
            @(posedge clk);
            started <= 0;

            tog_total = tog_wb + tog_bfa + tog_bfb + tog_rda + tog_rdb;
            if (grp_ch == 65)
                $display("TOGGLE A %0d %0d", run, tog_total);
            else
                $display("TOGGLE B %0d %0d", run, tog_total);
        end
    endtask

    // watchdog
    initial begin #(CLK_PERIOD * 2000000); $display("[TIMEOUT]"); $finish; end
endmodule
