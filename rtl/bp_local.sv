// =============================================================================
// bp_local.sv -- Yeh & Patt 2-level local-history predictor (PAp family)
// =============================================================================

module bp_local
    import bp_pkg::*;
(
    input  logic                      clk,
    input  logic                      rst_n,

    input  logic                      lookup_valid_i,
    input  logic [PC_WIDTH-1:0]       lookup_pc_i,
    output logic                      pred_taken_o,
    output logic [LOC_LH_W-1:0]       lh_snapshot_o,

    input  logic                      update_valid_i,
    input  logic [PC_WIDTH-1:0]       update_pc_i,
    input  logic                      update_taken_i,
    input  logic [LOC_LH_W-1:0]       update_lh_snapshot_i
);

    (* ram_style = "distributed" *)
    logic [LOC_LH_W-1:0] lht [0:LOC_LHT_N-1];

    (* ram_style = "distributed" *)
    logic [1:0] pht [0:LOC_PHT_N-1];

    function automatic logic [LOC_LHT_IDX-1:0] lht_idx(input logic [PC_WIDTH-1:0] pc);
        lht_idx = pc[LOC_LHT_IDX+1 : 2];
    endfunction

    function automatic logic [LOC_PHT_IDX-1:0] pht_idx(
            input logic [PC_WIDTH-1:0] pc,
            input logic [LOC_LH_W-1:0] lh);
        logic [LOC_PHT_IDX-1:0] tmp;
        if (LOC_PHT_IDX <= LOC_LH_W)
            tmp = lh[LOC_PHT_IDX-1:0];
        else
            tmp = { pc[LOC_PHT_IDX-LOC_LH_W+1 : 2], lh };
        pht_idx = tmp;
    endfunction

    logic [LOC_LH_W-1:0] lh_read;
    logic [1:0]          ctr_read;

    assign lh_read        = lht[lht_idx(lookup_pc_i)];
    assign ctr_read       = pht[pht_idx(lookup_pc_i, lh_read)];
    assign pred_taken_o   = lookup_valid_i & ctr_read[1];
    assign lh_snapshot_o  = lh_read;

    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < LOC_LHT_N; i = i + 1) lht[i] <= '0;
            for (i = 0; i < LOC_PHT_N; i = i + 1) pht[i] <= 2'b01;
        end
        else if (update_valid_i) begin
            lht[lht_idx(update_pc_i)]
                <= {lht[lht_idx(update_pc_i)][LOC_LH_W-2:0], update_taken_i};
            pht[pht_idx(update_pc_i, update_lh_snapshot_i)]
                <= sat2_update(pht[pht_idx(update_pc_i, update_lh_snapshot_i)],
                               update_taken_i);
        end
    end

endmodule