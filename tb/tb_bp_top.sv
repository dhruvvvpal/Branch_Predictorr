// =============================================================================
// tb_bp_top.sv  --  FIXED testbench for the branch predictor subsystem
// -----------------------------------------------------------------------------
// Fixes vs previous version:
//   1. Reuses the SAME PC across iterations so predictors can train.
//   2. Pre-loads the BTB so btb_hit is high from iteration 1.
//   3. Reports accuracy ONLY over steady-state (last 80% of iterations),
//      so training-phase mispredicts don't dominate the result.
//   4. Three patterns per predictor: ALWAYS_TAKEN, ALTERNATING (TNTN),
//      TTNT_REPEAT.  The alternating + TTNT cases distinguish predictors.
// =============================================================================
`timescale 1ns/1ps

module tb_bp_top;
    import bp_pkg::*;

    // ---------------- DUT I/O ----------------
    logic clk, rst_n;
    logic [1:0] cfg_sel;

    logic                     if_valid, if_is_cond;
    logic [PC_WIDTH-1:0]      if_pc;
    logic                     pred_taken, btb_hit;
    logic [PC_WIDTH-1:0]      btb_target;
    logic [GSH_GHR_W-1:0]     ghr_snap;
    logic [LOC_LH_W-1:0]      lh_snap;

    logic                     ex_valid, ex_is_cond, ex_is_jump, ex_taken, ex_mis;
    logic [PC_WIDTH-1:0]      ex_pc, ex_target;
    logic [GSH_GHR_W-1:0]     ex_ghr;
    logic [LOC_LH_W-1:0]      ex_lh;

    logic [31:0] perf_br, perf_mis, perf_btb, perf_cyc;

    bp_top DUT (
        .clk(clk), .rst_n(rst_n),
        .cfg_sel_i(cfg_sel),
        .if_valid_i(if_valid),
        .if_pc_i(if_pc),
        .predict_taken_o(pred_taken),
        .btb_hit_o(btb_hit),
        .btb_target_o(btb_target),
        .ghr_snapshot_o(ghr_snap),
        .lh_snapshot_o(lh_snap),
        .if_is_cond_branch_i(if_is_cond),
        .ex_valid_i(ex_valid),
        .ex_is_cond_branch_i(ex_is_cond),
        .ex_is_jump_i(ex_is_jump),
        .ex_pc_i(ex_pc),
        .ex_target_i(ex_target),
        .ex_taken_i(ex_taken),
        .ex_mispredict_i(ex_mis),
        .ex_ghr_snapshot_i(ex_ghr),
        .ex_lh_snapshot_i(ex_lh),
        .perf_branches_o(perf_br),
        .perf_mispredicts_o(perf_mis),
        .perf_btb_hits_o(perf_btb),
        .perf_cycles_o(perf_cyc)
    );

    // ---------------- clock ----------------
    initial clk = 0;
    always #10 clk = ~clk;  // 50 MHz

    // ---------------- helpers ----------------

    task automatic full_reset;
        rst_n <= 1'b0;
        if_valid <= 1'b0; if_is_cond <= 1'b0;
        ex_valid <= 1'b0; ex_is_cond <= 1'b0; ex_is_jump <= 1'b0;
        ex_pc <= '0; ex_target <= '0; ex_taken <= 1'b0; ex_mis <= 1'b0;
        ex_ghr <= '0; ex_lh <= '0;
        if_pc <= '0;
        repeat (10) @(posedge clk);
        rst_n <= 1'b1;
        repeat (3) @(posedge clk);
    endtask

    // Prime the BTB with one taken branch at the given PC.
    task automatic prime_btb(input logic [PC_WIDTH-1:0] pc,
                             input logic [PC_WIDTH-1:0] target);
        @(posedge clk);
        if_valid   <= 1'b1;
        if_pc      <= pc;
        if_is_cond <= 1'b1;
        @(posedge clk);
        if_valid   <= 1'b0;
        if_is_cond <= 1'b0;
        @(posedge clk);
        ex_valid   <= 1'b1;
        ex_is_cond <= 1'b1;
        ex_is_jump <= 1'b0;
        ex_pc      <= pc;
        ex_target  <= target;
        ex_taken   <= 1'b1;
        ex_mis     <= 1'b0;
        @(posedge clk);
        ex_valid   <= 1'b0;
        ex_is_cond <= 1'b0;
        @(posedge clk);
    endtask

    // Drive one branch: IF lookup with snapshot capture, then EX resolution.
    task automatic drive_branch(
            input  logic [PC_WIDTH-1:0]  pc,
            input  logic                 actual_taken,
            input  logic [PC_WIDTH-1:0]  tgt);
        logic                    p;
        logic [GSH_GHR_W-1:0]    g;
        logic [LOC_LH_W-1:0]     l;

        @(posedge clk);
        if_valid   <= 1'b1;
        if_pc      <= pc;
        if_is_cond <= 1'b1;
        #1;
        p = pred_taken;
        g = ghr_snap;
        l = lh_snap;

        @(posedge clk);
        if_valid   <= 1'b0;
        if_is_cond <= 1'b0;

        @(posedge clk);
        ex_valid   <= 1'b1;
        ex_is_cond <= 1'b1;
        ex_is_jump <= 1'b0;
        ex_pc      <= pc;
        ex_target  <= tgt;
        ex_taken   <= actual_taken;
        ex_mis     <= (p != actual_taken);
        ex_ghr     <= g;
        ex_lh      <= l;
        @(posedge clk);
        ex_valid   <= 1'b0;
        ex_is_cond <= 1'b0;
    endtask

    task automatic run_pattern(input string name,
                               input int iters,
                               input logic [31:0] pc,
                               input bit [1:0] mode);
        int    t, warmup;
        int    m_before, b_before;
        int    m_after,  b_after;
        int    br_seen, mis_seen;
        real   acc;
        logic  tk;

        $display("------------------------------------------------------------");
        $display("[%s]  cfg_sel=%0d  iters=%0d  pc=0x%08h",
                 name, cfg_sel, iters, pc);

        full_reset();
        prime_btb(pc, pc + 32'h100);

        warmup = iters / 5;

        for (t = 0; t < warmup; t++) begin
            case (mode)
                2'd0: tk = 1'b1;
                2'd1: tk = t[0];
                2'd2: tk = ((t % 4) != 3);
                default: tk = 1'b1;
            endcase
            drive_branch(pc, tk, pc + 32'h100);
        end

        @(posedge clk);
        b_before = perf_br;
        m_before = perf_mis;

        for (t = warmup; t < iters; t++) begin
            case (mode)
                2'd0: tk = 1'b1;
                2'd1: tk = t[0];
                2'd2: tk = ((t % 4) != 3);
                default: tk = 1'b1;
            endcase
            drive_branch(pc, tk, pc + 32'h100);
        end

        repeat (5) @(posedge clk);
        b_after = perf_br;
        m_after = perf_mis;

        br_seen  = b_after - b_before;
        mis_seen = m_after - m_before;
        acc = (br_seen > 0) ? 100.0 * real'(br_seen - mis_seen) / real'(br_seen) : 0.0;
        $display("[%s] steady-state: branches=%0d mispreds=%0d accuracy=%0.2f%%",
                 name, br_seen, mis_seen, acc);
    endtask

    // ---------------- main stimulus ----------------
    initial begin
        rst_n = 0;
        cfg_sel = 2'b00;
        if_valid = 0; if_is_cond = 0; if_pc = 0;
        ex_valid = 0; ex_is_cond = 0; ex_is_jump = 0;
        ex_pc = 0; ex_target = 0; ex_taken = 0; ex_mis = 0;
        ex_ghr = 0; ex_lh = 0;

        repeat (20) @(posedge clk);

        // -------- Bimodal --------
        cfg_sel = PRED_BIMODAL;
        run_pattern("BIMODAL/ALWAYS_TAKEN", 200, 32'h0000_1000, 2'd0);
        run_pattern("BIMODAL/ALTERNATING",  200, 32'h0000_2000, 2'd1);
        run_pattern("BIMODAL/TTNT_REPEAT",  200, 32'h0000_3000, 2'd2);

        // -------- Gshare --------
        cfg_sel = PRED_GSHARE;
        run_pattern("GSHARE/ALWAYS_TAKEN",  200, 32'h0000_1000, 2'd0);
        run_pattern("GSHARE/ALTERNATING",   200, 32'h0000_2000, 2'd1);
        run_pattern("GSHARE/TTNT_REPEAT",   200, 32'h0000_3000, 2'd2);

        // -------- Local --------
        cfg_sel = PRED_LOCAL;
        run_pattern("LOCAL/ALWAYS_TAKEN",   200, 32'h0000_1000, 2'd0);
        run_pattern("LOCAL/ALTERNATING",    200, 32'h0000_2000, 2'd1);
        run_pattern("LOCAL/TTNT_REPEAT",    200, 32'h0000_3000, 2'd2);

        $display("\n============================================================");
        $display("ALL TESTS DONE  --  expected results:");
        $display("  ALWAYS_TAKEN  : all 3 predictors near 100%%");
        $display("  ALTERNATING   : bimodal ~50%%,  gshare & local near 100%%");
        $display("  TTNT_REPEAT   : bimodal ~75%%,  gshare & local near 100%%");
        $display("============================================================");
        $finish;
    end

    initial begin
        #5_000_000;
        $display("WATCHDOG TRIGGERED");
        $finish;
    end

endmodule