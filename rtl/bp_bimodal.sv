// =============================================================================
// bp_bimodal.sv -- Bimodal (Smith-style) 2-bit saturating counter predictor
// -----------------------------------------------------------------------------
// Combinational read + synchronous write.  Implemented in distributed LUT RAM.
// Size is controlled by BIM_IDX_W in bp_pkg.sv.
// =============================================================================

module bp_bimodal
    import bp_pkg::*;
(
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic                  lookup_valid_i,
    input  logic [PC_WIDTH-1:0]   lookup_pc_i,
    output logic                  pred_taken_o,

    input  logic                  update_valid_i,
    input  logic [PC_WIDTH-1:0]   update_pc_i,
    input  logic                  update_taken_i
);

    (* ram_style = "distributed" *)
    logic [1:0] pht [0:BIM_ENTRIES-1];

    function automatic logic [BIM_IDX_W-1:0] idx(input logic [PC_WIDTH-1:0] pc);
        idx = pc[BIM_IDX_W+1 : 2];
    endfunction

    logic [1:0] read_ctr;
    assign read_ctr     = pht[idx(lookup_pc_i)];
    assign pred_taken_o = lookup_valid_i & read_ctr[1];

    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < BIM_ENTRIES; i = i + 1)
                pht[i] <= 2'b01;
        end
        else if (update_valid_i) begin
            pht[idx(update_pc_i)] <= sat2_update(pht[idx(update_pc_i)],
                                                 update_taken_i);
        end
    end

endmodule