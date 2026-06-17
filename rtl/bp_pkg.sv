// =============================================================================
// bp_pkg.sv  --  Branch-Predictor Subsystem: shared parameters & types
// Project   :  RV32I 5-stage pipeline with swappable branch predictors
// Target    :  Xilinx Zynq-7000 xc7z010-1clg400c (Digilent Zybo Z7-10)
// -----------------------------------------------------------------------------
// All sizing knobs live here so the full CPI-vs-area sweep is done by editing
// ONE file and re-synthesising.
// =============================================================================

package bp_pkg;

    localparam int unsigned XLEN     = 32;
    localparam int unsigned PC_WIDTH = 32;

    typedef enum logic [1:0] {
        PRED_BIMODAL = 2'b00,
        PRED_GSHARE  = 2'b01,
        PRED_LOCAL   = 2'b10,
        PRED_STATIC  = 2'b11
    } pred_sel_e;

    // ----------------------------------------------------------------
    // Sweep-point selector.  Uncomment EXACTLY ONE.
    // Totals shown are for ALL three predictors instantiated in parallel
    // (since the hot-swap MUX keeps them all present).
    // ----------------------------------------------------------------
    //`define BP_SIZE_S    //  ~  800 LUTs total --  toy size
    `define BP_SIZE_M    //  ~ 3000 LUTs total --  DEFAULT, fits Zybo Z7-10
    //`define BP_SIZE_L    //  ~ 8000 LUTs total --  needs block RAM inference
    //`define BP_SIZE_XL   //  ~28000 LUTs total --  does NOT fit Zybo Z7-10

`ifdef BP_SIZE_S
    localparam int unsigned BIM_IDX_W   = 6;    //   64 x 2-bit
    localparam int unsigned GSH_IDX_W   = 6;
    localparam int unsigned GSH_GHR_W   = 6;
    localparam int unsigned LOC_LHT_IDX = 3;    //    8 x 4-bit LHT
    localparam int unsigned LOC_LH_W    = 4;
    localparam int unsigned LOC_PHT_IDX = 4;    //   16 x 2-bit PHT
`elsif BP_SIZE_M
    localparam int unsigned BIM_IDX_W   = 8;    //  256 x 2-bit
    localparam int unsigned GSH_IDX_W   = 8;
    localparam int unsigned GSH_GHR_W   = 8;
    localparam int unsigned LOC_LHT_IDX = 5;    //   32 x 6-bit LHT
    localparam int unsigned LOC_LH_W    = 6;
    localparam int unsigned LOC_PHT_IDX = 6;    //   64 x 2-bit PHT
`elsif BP_SIZE_L
    localparam int unsigned BIM_IDX_W   = 10;   // 1024 x 2-bit
    localparam int unsigned GSH_IDX_W   = 10;
    localparam int unsigned GSH_GHR_W   = 10;
    localparam int unsigned LOC_LHT_IDX = 6;    //   64 x 8-bit LHT
    localparam int unsigned LOC_LH_W    = 8;
    localparam int unsigned LOC_PHT_IDX = 8;    //  256 x 2-bit PHT
`elsif BP_SIZE_XL
    localparam int unsigned BIM_IDX_W   = 12;
    localparam int unsigned GSH_IDX_W   = 12;
    localparam int unsigned GSH_GHR_W   = 12;
    localparam int unsigned LOC_LHT_IDX = 7;
    localparam int unsigned LOC_LH_W    = 10;
    localparam int unsigned LOC_PHT_IDX = 10;
`endif

    localparam int unsigned BIM_ENTRIES = 1 << BIM_IDX_W;
    localparam int unsigned GSH_ENTRIES = 1 << GSH_IDX_W;
    localparam int unsigned LOC_LHT_N   = 1 << LOC_LHT_IDX;
    localparam int unsigned LOC_PHT_N   = 1 << LOC_PHT_IDX;

    localparam int unsigned BTB_IDX_W   = 5;               // 32 entries
    localparam int unsigned BTB_ENTRIES = 1 << BTB_IDX_W;
    localparam int unsigned BTB_TAG_W   = PC_WIDTH - BTB_IDX_W - 2;
    localparam int unsigned BTB_ENTRY_W = 1 + 1 + BTB_TAG_W + (PC_WIDTH-2);

    function automatic logic [1:0] sat2_update(input logic [1:0] cur,
                                               input logic taken);
        begin
            if (taken)
                sat2_update = (cur == 2'b11) ? 2'b11 : (cur + 2'b01);
            else
                sat2_update = (cur == 2'b00) ? 2'b00 : (cur - 2'b01);
        end
    endfunction

endpackage : bp_pkg