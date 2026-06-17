// =============================================================================
// bp_gshare.sv -- McFarling gshare predictor
// -----------------------------------------------------------------------------
// Speculative GHR advance at prediction time, snapshot+rollback on mispredict.
// =============================================================================

module bp_gshare
    import bp_pkg::*;
(
    input  logic                        clk,
    input  logic                        rst_n,

    input  logic                        lookup_valid_i,
    input  logic [PC_WIDTH-1:0]         lookup_pc_i,
    output logic                        pred_taken_o,
    output logic [GSH_GHR_W-1:0]        ghr_snapshot_o,

    input  logic                        spec_update_i,
    input  logic                        spec_taken_i,

    input  logic                        update_valid_i,
    input  logic                        update_mispredict_i,
    input  logic [PC_WIDTH-1:0]         update_pc_i,
    input  logic                        update_taken_i,
    input  logic [GSH_GHR_W-1:0]        update_ghr_snapshot_i
);

    (* ram_style = "distributed" *)
    logic [1:0] pht [0:GSH_ENTRIES-1];

    logic [GSH_GHR_W-1:0] ghr_q;

    function automatic logic [GSH_IDX_W-1:0] idx(
            input logic [PC_WIDTH-1:0]  pc,
            input logic [GSH_GHR_W-1:0] ghr);
        logic [GSH_IDX_W-1:0] pc_bits;
        logic [GSH_IDX_W-1:0] ghr_bits;
        pc_bits  = pc[GSH_IDX_W+1 : 2];
        ghr_bits = {{(GSH_IDX_W > GSH_GHR_W ? GSH_IDX_W-GSH_GHR_W : 0){1'b0}},
                    ghr[(GSH_IDX_W > GSH_GHR_W ? GSH_GHR_W : GSH_IDX_W)-1 : 0]};
        idx = pc_bits ^ ghr_bits;
    endfunction

    logic [1:0] read_ctr;
    assign read_ctr       = pht[idx(lookup_pc_i, ghr_q)];
    assign pred_taken_o   = lookup_valid_i & read_ctr[1];
    assign ghr_snapshot_o = ghr_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ghr_q <= '0;
        end
        else if (update_valid_i && update_mispredict_i) begin
            ghr_q <= {update_ghr_snapshot_i[GSH_GHR_W-2:0], update_taken_i};
        end
        else if (spec_update_i) begin
            ghr_q <= {ghr_q[GSH_GHR_W-2:0], spec_taken_i};
        end
    end

    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < GSH_ENTRIES; i = i + 1)
                pht[i] <= 2'b01;
        end
        else if (update_valid_i) begin
            pht[idx(update_pc_i, update_ghr_snapshot_i)]
                <= sat2_update(pht[idx(update_pc_i, update_ghr_snapshot_i)],
                               update_taken_i);
        end
    end

endmodule