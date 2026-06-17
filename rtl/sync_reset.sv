// =============================================================================
// sync_reset.sv -- async-assert, sync-deassert reset synchroniser
// =============================================================================
module sync_reset #(
    parameter int STAGES = 3
) (
    input  logic clk,
    input  logic arst_n_i,  // asynchronous active-low reset in
    output logic rst_n_o    // synchronised active-low reset out
);
    (* ASYNC_REG = "TRUE" *) logic [STAGES-1:0] sync_ff;

    always_ff @(posedge clk or negedge arst_n_i) begin
        if (!arst_n_i) sync_ff <= '0;
        else           sync_ff <= {sync_ff[STAGES-2:0], 1'b1};
    end

    assign rst_n_o = sync_ff[STAGES-1];
endmodule
