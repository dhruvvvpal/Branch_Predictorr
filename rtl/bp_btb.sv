// =============================================================================
// bp_btb.sv -- 32-entry direct-mapped Branch Target Buffer
// =============================================================================

module bp_btb
    import bp_pkg::*;
(
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic                    lookup_valid_i,
    input  logic [PC_WIDTH-1:0]     lookup_pc_i,
    output logic                    btb_hit_o,
    output logic [PC_WIDTH-1:0]     btb_target_o,
    output logic                    btb_is_branch_o,

    input  logic                    update_valid_i,
    input  logic                    update_is_branch_i,
    input  logic [PC_WIDTH-1:0]     update_pc_i,
    input  logic [PC_WIDTH-1:0]     update_target_i
);

    (* ram_style = "distributed" *)
    logic                       valid_arr   [0:BTB_ENTRIES-1];
    (* ram_style = "distributed" *)
    logic                       isbr_arr    [0:BTB_ENTRIES-1];
    (* ram_style = "distributed" *)
    logic [BTB_TAG_W-1:0]       tag_arr     [0:BTB_ENTRIES-1];
    (* ram_style = "distributed" *)
    logic [PC_WIDTH-3:0]        target_arr  [0:BTB_ENTRIES-1];

    function automatic logic [BTB_IDX_W-1:0] idx(input logic [PC_WIDTH-1:0] pc);
        idx = pc[BTB_IDX_W+1 : 2];
    endfunction

    function automatic logic [BTB_TAG_W-1:0] tag(input logic [PC_WIDTH-1:0] pc);
        tag = pc[PC_WIDTH-1 : BTB_IDX_W+2];
    endfunction

    logic [BTB_IDX_W-1:0] l_idx;
    assign l_idx           = idx(lookup_pc_i);
    assign btb_hit_o       = lookup_valid_i &
                             valid_arr[l_idx] &
                             (tag_arr[l_idx] == tag(lookup_pc_i));
    assign btb_target_o    = {target_arr[l_idx], 2'b00};
    assign btb_is_branch_o = isbr_arr[l_idx];

    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < BTB_ENTRIES; i = i + 1) begin
                valid_arr[i]  <= 1'b0;
                isbr_arr[i]   <= 1'b0;
                tag_arr[i]    <= '0;
                target_arr[i] <= '0;
            end
        end
        else if (update_valid_i) begin
            valid_arr [idx(update_pc_i)]  <= 1'b1;
            isbr_arr  [idx(update_pc_i)]  <= update_is_branch_i;
            tag_arr   [idx(update_pc_i)]  <= tag(update_pc_i);
            target_arr[idx(update_pc_i)]  <= update_target_i[PC_WIDTH-1:2];
        end
    end

endmodule