// =============================================================================
// bp_top.sv -- Branch Predictor Subsystem (drop-in for host CPU)
// -----------------------------------------------------------------------------
// Instantiates BTB + all three direction predictors in parallel.
// DONT_TOUCH removed -- Vivado will optimise unselected update-paths.
// The three predictor *tables* still exist in full because cfg_sel is a
// dynamic input, not a constant, but the update logic for the inactive
// predictors collapses during synthesis, saving several thousand LUTs.
// =============================================================================

module bp_top
    import bp_pkg::*;
(
    input  logic                     clk,
    input  logic                     rst_n,

    input  logic [1:0]               cfg_sel_i,

    input  logic                     if_valid_i,
    input  logic [PC_WIDTH-1:0]      if_pc_i,
    output logic                     predict_taken_o,
    output logic                     btb_hit_o,
    output logic [PC_WIDTH-1:0]      btb_target_o,

    output logic [GSH_GHR_W-1:0]     ghr_snapshot_o,
    output logic [LOC_LH_W-1:0]      lh_snapshot_o,

    input  logic                     if_is_cond_branch_i,

    input  logic                     ex_valid_i,
    input  logic                     ex_is_cond_branch_i,
    input  logic                     ex_is_jump_i,
    input  logic [PC_WIDTH-1:0]      ex_pc_i,
    input  logic [PC_WIDTH-1:0]      ex_target_i,
    input  logic                     ex_taken_i,
    input  logic                     ex_mispredict_i,

    input  logic [GSH_GHR_W-1:0]     ex_ghr_snapshot_i,
    input  logic [LOC_LH_W-1:0]      ex_lh_snapshot_i,

    output logic [31:0]              perf_branches_o,
    output logic [31:0]              perf_mispredicts_o,
    output logic [31:0]              perf_btb_hits_o,
    output logic [31:0]              perf_cycles_o
);

    logic btb_hit_w, btb_isbr_w;
    logic [PC_WIDTH-1:0] btb_tgt_w;

    bp_btb u_btb (
        .clk             (clk),
        .rst_n           (rst_n),
        .lookup_valid_i  (if_valid_i),
        .lookup_pc_i     (if_pc_i),
        .btb_hit_o       (btb_hit_w),
        .btb_target_o    (btb_tgt_w),
        .btb_is_branch_o (btb_isbr_w),
        .update_valid_i  (ex_valid_i & ex_taken_i & (ex_is_cond_branch_i | ex_is_jump_i)),
        .update_is_branch_i (ex_is_cond_branch_i),
        .update_pc_i     (ex_pc_i),
        .update_target_i (ex_target_i)
    );

    assign btb_hit_o    = btb_hit_w;
    assign btb_target_o = btb_tgt_w;

    logic pred_bim_w, pred_gsh_w, pred_loc_w;

    logic upd_bim, upd_gsh, upd_loc;
    assign upd_bim = ex_valid_i & ex_is_cond_branch_i & (cfg_sel_i == PRED_BIMODAL);
    assign upd_gsh = ex_valid_i & ex_is_cond_branch_i & (cfg_sel_i == PRED_GSHARE);
    assign upd_loc = ex_valid_i & ex_is_cond_branch_i & (cfg_sel_i == PRED_LOCAL);

    bp_bimodal u_bim (
        .clk            (clk),
        .rst_n          (rst_n),
        .lookup_valid_i (if_valid_i),
        .lookup_pc_i    (if_pc_i),
        .pred_taken_o   (pred_bim_w),
        .update_valid_i (upd_bim),
        .update_pc_i    (ex_pc_i),
        .update_taken_i (ex_taken_i)
    );

    bp_gshare u_gsh (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .lookup_valid_i        (if_valid_i),
        .lookup_pc_i           (if_pc_i),
        .pred_taken_o          (pred_gsh_w),
        .ghr_snapshot_o        (ghr_snapshot_o),
        .spec_update_i         (if_valid_i & if_is_cond_branch_i & (cfg_sel_i == PRED_GSHARE)),
        .spec_taken_i          (pred_gsh_w),
        .update_valid_i        (upd_gsh),
        .update_mispredict_i   (ex_mispredict_i),
        .update_pc_i           (ex_pc_i),
        .update_taken_i        (ex_taken_i),
        .update_ghr_snapshot_i (ex_ghr_snapshot_i)
    );

    bp_local u_loc (
        .clk                  (clk),
        .rst_n                (rst_n),
        .lookup_valid_i       (if_valid_i),
        .lookup_pc_i          (if_pc_i),
        .pred_taken_o         (pred_loc_w),
        .lh_snapshot_o        (lh_snapshot_o),
        .update_valid_i       (upd_loc),
        .update_pc_i          (ex_pc_i),
        .update_taken_i       (ex_taken_i),
        .update_lh_snapshot_i (ex_lh_snapshot_i)
    );

    always_comb begin
        unique case (cfg_sel_i)
            PRED_BIMODAL: predict_taken_o = pred_bim_w & btb_hit_w & btb_isbr_w;
            PRED_GSHARE : predict_taken_o = pred_gsh_w & btb_hit_w & btb_isbr_w;
            PRED_LOCAL  : predict_taken_o = pred_loc_w & btb_hit_w & btb_isbr_w;
            PRED_STATIC : predict_taken_o = 1'b0;
            default     : predict_taken_o = 1'b0;
        endcase
    end

    logic [31:0] cnt_br, cnt_mis, cnt_btb_hit, cnt_cyc;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_br      <= 32'd0;
            cnt_mis     <= 32'd0;
            cnt_btb_hit <= 32'd0;
            cnt_cyc     <= 32'd0;
        end else begin
            cnt_cyc <= cnt_cyc + 32'd1;
            if (ex_valid_i && ex_is_cond_branch_i) begin
                cnt_br  <= cnt_br + 32'd1;
                if (ex_mispredict_i) cnt_mis <= cnt_mis + 32'd1;
            end
            if (if_valid_i && btb_hit_w) cnt_btb_hit <= cnt_btb_hit + 32'd1;
        end
    end

    assign perf_branches_o    = cnt_br;
    assign perf_mispredicts_o = cnt_mis;
    assign perf_btb_hits_o    = cnt_btb_hit;
    assign perf_cycles_o      = cnt_cyc;

endmodule