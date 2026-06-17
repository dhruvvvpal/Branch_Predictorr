// =============================================================================
// rv32i_core_stub.sv  --  ILA-FRIENDLY STUB / PLACEHOLDER core
// -----------------------------------------------------------------------------
//   This is NOT a real RV32I processor.  It generates synthetic but READABLE
//   branch traffic for board bring-up and ILA capture.
//
//   Changes vs previous stub (for ILA readability):
//     - Slower event rate (1 event per 100 cycles instead of 1 per 8)
//       so the ILA's 1024-depth buffer captures ~30 branches of real
//       structure instead of noise.
//     - Deterministic PC sweep (not LFSR), so consecutive ILA captures
//       look the same and you can correlate them with switch position.
//     - mark_debug attribute on every signal of interest so Vivado's
//       "Set Up Debug" wizard picks them up automatically.
//     - A clean "event" pulse signal that makes a perfect ILA trigger.
//
//   When V-FRONT is integrated, DELETE this file and remove from sources.
// =============================================================================

module rv32i_core_top
    import bp_pkg::*;
(
    input  logic                     clk,
    input  logic                     rst_n,

    // IF taps
    output logic                     if_valid_o,
    output logic [PC_WIDTH-1:0]      if_pc_o,
    output logic                     if_is_cond_branch_o,

    // from BP
    input  logic                     bp_predict_taken_i,
    input  logic                     bp_btb_hit_i,
    input  logic [PC_WIDTH-1:0]      bp_btb_target_i,
    input  logic [GSH_GHR_W-1:0]     bp_ghr_snap_i,
    input  logic [LOC_LH_W-1:0]      bp_lh_snap_i,

    // EX taps
    output logic                     ex_valid_o,
    output logic                     ex_is_cond_branch_o,
    output logic                     ex_is_jump_o,
    output logic [PC_WIDTH-1:0]      ex_pc_o,
    output logic [PC_WIDTH-1:0]      ex_target_o,
    output logic                     ex_taken_o,
    output logic                     ex_mispredict_o,
    output logic [GSH_GHR_W-1:0]     ex_ghr_snap_o,
    output logic [LOC_LH_W-1:0]      ex_lh_snap_o
);

    // -------------------------------------------------------------------
    // Program: 8 PCs with mixed branch behaviours
    //   slot 0-1 : always taken      (easy for all predictors)
    //   slot 2-3 : always not-taken  (easy)
    //   slot 4   : alternating TNTN  (bimodal fails, gshare/local win)
    //   slot 5   : TTNT repeating    (bimodal ~75%, two-level ~100%)
    //   slot 6-7 : 3-of-4 taken      (bimodal biases taken, all win eventually)
    // -------------------------------------------------------------------
    localparam int unsigned N_SLOTS = 8;

    logic [PC_WIDTH-1:0] prog_pc [0:N_SLOTS-1];
    initial begin
        prog_pc[0] = 32'h0000_1000;
        prog_pc[1] = 32'h0000_1100;
        prog_pc[2] = 32'h0000_2000;
        prog_pc[3] = 32'h0000_2100;
        prog_pc[4] = 32'h0000_3000;
        prog_pc[5] = 32'h0000_4000;
        prog_pc[6] = 32'h0000_5000;
        prog_pc[7] = 32'h0000_5100;
    end

    // -------------------------------------------------------------------
    // Event pacing: one branch every 100 cycles = 500,000 branches/sec
    // ILA buffer of 1024 samples covers ~10 branches at this rate.
    // Bump THROTTLE up if you want fewer, better-spaced events.
    // -------------------------------------------------------------------
    localparam int THROTTLE = 100;
    (* mark_debug = "true" *) logic tick;
    logic [$clog2(THROTTLE)-1:0] thr_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            thr_cnt <= '0;
            tick    <= 1'b0;
        end else if (thr_cnt == THROTTLE-1) begin
            thr_cnt <= '0;
            tick    <= 1'b1;
        end else begin
            thr_cnt <= thr_cnt + 1'b1;
            tick    <= 1'b0;
        end
    end

    // -------------------------------------------------------------------
    // Slot round-robin + repetition counter (so each slot is visited many
    // times before moving to the next -> predictors have time to train).
    // -------------------------------------------------------------------
    (* mark_debug = "true" *) logic [3:0]  rep_cnt;   // 0..15 per slot
    (* mark_debug = "true" *) logic [2:0]  slot;      // 0..7

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rep_cnt <= '0;
            slot    <= '0;
        end else if (tick) begin
            if (rep_cnt == 4'd15) begin
                rep_cnt <= '0;
                slot    <= slot + 1'b1;
            end else begin
                rep_cnt <= rep_cnt + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------
    // Per-slot pattern decoder: returns "should be taken this iteration"
    // -------------------------------------------------------------------
    logic actual_taken;
    always_comb begin
        case (slot)
            3'd0, 3'd1: actual_taken = 1'b1;                   // always T
            3'd2, 3'd3: actual_taken = 1'b0;                   // always N
            3'd4:       actual_taken = rep_cnt[0];             // TNTN
            3'd5:       actual_taken = (rep_cnt[1:0] != 2'd3); // TTNT
            3'd6, 3'd7: actual_taken = (rep_cnt[1:0] != 2'd0); // NTTT
            default:    actual_taken = 1'b0;
        endcase
    end

    (* mark_debug = "true" *) logic [PC_WIDTH-1:0] pc_if;
    assign pc_if = prog_pc[slot];

    // -------------------------------------------------------------------
    // 2-stage delay: IF -> "ID" -> "EX".  Snapshots travel with the insn.
    // -------------------------------------------------------------------
    typedef struct packed {
        logic                      valid;
        logic [PC_WIDTH-1:0]       pc;
        logic                      actual_taken;
        logic                      predicted;
        logic [GSH_GHR_W-1:0]      ghr_snap;
        logic [LOC_LH_W-1:0]       lh_snap;
    } stage_t;

    (* mark_debug = "true" *) stage_t if_id, id_ex;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id <= '0;
            id_ex <= '0;
        end else begin
            if_id.valid        <= tick;
            if_id.pc           <= pc_if;
            if_id.actual_taken <= actual_taken;
            if_id.predicted    <= bp_predict_taken_i;
            if_id.ghr_snap     <= bp_ghr_snap_i;
            if_id.lh_snap      <= bp_lh_snap_i;
            id_ex              <= if_id;
        end
    end

    // -------------------------------------------------------------------
    // Drive IF outputs to BP  (visible to ILA)
    // -------------------------------------------------------------------
    (* mark_debug = "true" *) logic if_valid_dbg;
    (* mark_debug = "true" *) logic if_is_cond_branch_dbg;

    assign if_valid_dbg          = tick;
    assign if_is_cond_branch_dbg = tick;
    assign if_valid_o            = if_valid_dbg;
    assign if_pc_o               = pc_if;
    assign if_is_cond_branch_o   = if_is_cond_branch_dbg;

    // -------------------------------------------------------------------
    // Drive EX outputs (visible to ILA)
    // -------------------------------------------------------------------
    (* mark_debug = "true" *) logic ex_mispredict_dbg;
    assign ex_mispredict_dbg = id_ex.valid && (id_ex.predicted != id_ex.actual_taken);

    assign ex_valid_o          = id_ex.valid;
    assign ex_is_cond_branch_o = id_ex.valid;
    assign ex_is_jump_o        = 1'b0;
    assign ex_pc_o             = id_ex.pc;
    assign ex_target_o         = id_ex.pc + 32'h80;
    assign ex_taken_o          = id_ex.actual_taken;
    assign ex_mispredict_o     = ex_mispredict_dbg;
    assign ex_ghr_snap_o       = id_ex.ghr_snap;
    assign ex_lh_snap_o        = id_ex.lh_snap;

endmodule