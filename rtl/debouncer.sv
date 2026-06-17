// =============================================================================
// debouncer.sv -- simple ~10 ms debouncer for slide switches / push-buttons
// -----------------------------------------------------------------------------
// At 50 MHz, DEB_BITS = 19 gives ~10.5 ms settling time.
// =============================================================================
module debouncer #(
    parameter int DEB_BITS = 19
) (
    input  logic clk,
    input  logic rst_n,
    input  logic in_i,
    output logic out_o
);
    logic [1:0]             sync_ff;
    logic [DEB_BITS-1:0]    cnt;
    logic                   stable_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_ff  <= 2'b00;
            cnt      <= '0;
            stable_q <= 1'b0;
        end else begin
            sync_ff <= {sync_ff[0], in_i};
            if (sync_ff[1] != stable_q) begin
                cnt <= cnt + 1'b1;
                if (&cnt) begin
                    stable_q <= sync_ff[1];
                    cnt      <= '0;
                end
            end else begin
                cnt <= '0;
            end
        end
    end

    assign out_o = stable_q;
endmodule
