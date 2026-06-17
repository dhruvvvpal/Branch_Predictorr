// =============================================================================
// zybo_z7_10_top.sv -- SoC top for Digilent Zybo Z7-10 (xc7z010-1clg400c)
// -----------------------------------------------------------------------------
// Drives the 125 MHz input clock into an MMCM to generate 50 MHz core clock.
// Latches SW[1:0] at reset as predictor select, exposes mispredict rate on
// LEDs, and streams counters on UART when BTN1 is pressed.
//
// *** INTEGRATION NOTES for V-FRONT ***
// This file instantiates a placeholder `rv32i_core_top` -- you must replace
// that instantiation with V-FRONT's actual top-level module (see README.md
// in docs/ for the exact wiring instructions).  The only NEW ports you need
// to add to V-FRONT's top are the ones listed in the bp_top connections
// below, all of which are trivially drivable from V-FRONT's existing fetch
// PC, IF/ID pipeline register, and EX-stage branch-resolve logic.
// =============================================================================

module zybo_z7_10_top
    import bp_pkg::*;
(
    // 125 MHz single-ended clock from Ethernet PHY (pin K17)
    input  logic        sysclk,

    // User I/O (Zybo Z7 master XDC)
    input  logic [3:0]  sw,        // G15, P15, W13, T16
    input  logic [3:0]  btn,       // K18, P16, K19, Y16
    output logic [3:0]  led,       // M14, M15, G14, D18

    // UART TX out to Pmod JA pin 1 (N15)
    output logic        ja_tx,

    // Keep the PHY out of reset so the 125 MHz clock is alive
    output logic        eth_rst_b  // E17 -- asserted high
);

    // -----------------------------------------------------------------
    // 1.  Clocking: 125 MHz -> 50 MHz core clock via MMCM primitive
    // -----------------------------------------------------------------
    logic clk_fb, clk_core_unbuf, clk_core, mmcm_locked;

    MMCME2_BASE #(
        .CLKFBOUT_MULT_F (8.0),   // 125 * 8   = 1000 MHz  (VCO)
        .CLKIN1_PERIOD   (8.0),   // 125 MHz   = 8 ns
        .CLKOUT0_DIVIDE_F(20.0),  // 1000 / 20 = 50 MHz
        .DIVCLK_DIVIDE   (1)
    ) u_mmcm (
        .CLKIN1  (sysclk),
        .CLKFBIN (clk_fb),
        .CLKFBOUT(clk_fb),
        .CLKOUT0 (clk_core_unbuf),
        .LOCKED  (mmcm_locked),
        .RST     (1'b0),
        .PWRDWN  (1'b0),
        .CLKOUT1 (), .CLKOUT2 (), .CLKOUT3 (),
        .CLKOUT4 (), .CLKOUT5 (), .CLKOUT6 (),
        .CLKOUT0B(), .CLKOUT1B(), .CLKOUT2B(),
        .CLKOUT3B(), .CLKFBOUTB()
    );

    BUFG u_bufg (.I(clk_core_unbuf), .O(clk_core));

    // Keep Ethernet PHY out of reset (required to keep sysclk alive)
    assign eth_rst_b = 1'b1;

    // -----------------------------------------------------------------
    // 2.  Reset: BTN0 (active-high push-button) + MMCM lock
    // -----------------------------------------------------------------
    logic btn0_deb, rst_async_n, rst_n;

    debouncer u_deb_btn0 (
        .clk(clk_core), .rst_n(1'b1), .in_i(btn[0]), .out_o(btn0_deb)
    );

    assign rst_async_n = mmcm_locked & ~btn0_deb;

    sync_reset #(.STAGES(3)) u_rst_sync (
        .clk     (clk_core),
        .arst_n_i(rst_async_n),
        .rst_n_o (rst_n)
    );

    // -----------------------------------------------------------------
    // 3.  Debounce switches & BTN1
    // -----------------------------------------------------------------
    logic [3:0] sw_deb;
    logic       btn1_deb;

    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_sw_deb
            // SW debouncers are NOT reset by system reset.  This way, sw_deb
            // remains valid the moment reset is released, so cfg_sel latches
            // the correct switch values.
            debouncer u_dsw (.clk(clk_core), .rst_n(1'b1),
                             .in_i(sw[gi]), .out_o(sw_deb[gi]));
        end
    endgenerate

    debouncer u_db_btn1 (.clk(clk_core), .rst_n(rst_n),
                         .in_i(btn[1]), .out_o(btn1_deb));

    // -----------------------------------------------------------------
    // 4.  Latch CFG_SEL on every cycle after reset
    //     This makes the design respond to switch changes AS THEY HAPPEN,
    //     which is more useful for live demonstration than a one-shot
    //     latch.  Internally, the predictor mux reads cfg_sel each cycle.
    // -----------------------------------------------------------------
    (* mark_debug = "true" *) logic [1:0]  cfg_sel;

    always_ff @(posedge clk_core or negedge rst_n) begin
        if (!rst_n) begin
            cfg_sel  <= 2'b00;
        end else begin
            cfg_sel <= sw_deb[1:0];     // continuous tracking
        end
    end

    // -----------------------------------------------------------------
    // 5.  RV32I core + branch predictor subsystem
    //     The signals named core_* are what V-FRONT's top must expose.
    //     See docs/VFRONT_INTEGRATION.md for line-by-line patch guide.
    //
    //     mark_debug attributes below tell Vivado's "Set Up Debug" flow
    //     to expose these signals to the ILA automatically.
    // -----------------------------------------------------------------
    // Wires into bp_top
    (* mark_debug = "true" *) logic                     core_if_valid;
    (* mark_debug = "true" *) logic [PC_WIDTH-1:0]      core_if_pc;
    (* mark_debug = "true" *) logic                     core_if_is_cond_branch;

    (* mark_debug = "true" *) logic                     bp_predict_taken;
    (* mark_debug = "true" *) logic                     bp_btb_hit;
    (* mark_debug = "true" *) logic [PC_WIDTH-1:0]      bp_btb_target;
    (* mark_debug = "true" *) logic [GSH_GHR_W-1:0]     bp_ghr_snap;
    (* mark_debug = "true" *) logic [LOC_LH_W-1:0]      bp_lh_snap;

    (* mark_debug = "true" *) logic                     core_ex_valid;
    (* mark_debug = "true" *) logic                     core_ex_is_cond_branch;
    (* mark_debug = "true" *) logic                     core_ex_is_jump;
    (* mark_debug = "true" *) logic [PC_WIDTH-1:0]      core_ex_pc;
    (* mark_debug = "true" *) logic [PC_WIDTH-1:0]      core_ex_target;
    (* mark_debug = "true" *) logic                     core_ex_taken;
    (* mark_debug = "true" *) logic                     core_ex_mispredict;
    (* mark_debug = "true" *) logic [GSH_GHR_W-1:0]     core_ex_ghr_snap;
    (* mark_debug = "true" *) logic [LOC_LH_W-1:0]      core_ex_lh_snap;

    (* mark_debug = "true" *) logic [31:0] perf_br, perf_mis, perf_btb, perf_cyc;

    bp_top u_bp (
        .clk(clk_core), .rst_n(rst_n),
        .cfg_sel_i             (cfg_sel),
        .if_valid_i            (core_if_valid),
        .if_pc_i               (core_if_pc),
        .predict_taken_o       (bp_predict_taken),
        .btb_hit_o             (bp_btb_hit),
        .btb_target_o          (bp_btb_target),
        .ghr_snapshot_o        (bp_ghr_snap),
        .lh_snapshot_o         (bp_lh_snap),
        .if_is_cond_branch_i   (core_if_is_cond_branch),
        .ex_valid_i            (core_ex_valid),
        .ex_is_cond_branch_i   (core_ex_is_cond_branch),
        .ex_is_jump_i          (core_ex_is_jump),
        .ex_pc_i               (core_ex_pc),
        .ex_target_i           (core_ex_target),
        .ex_taken_i            (core_ex_taken),
        .ex_mispredict_i       (core_ex_mispredict),
        .ex_ghr_snapshot_i     (core_ex_ghr_snap),
        .ex_lh_snapshot_i      (core_ex_lh_snap),
        .perf_branches_o       (perf_br),
        .perf_mispredicts_o    (perf_mis),
        .perf_btb_hits_o       (perf_btb),
        .perf_cycles_o         (perf_cyc)
    );

    // -----------------------------------------------------------------
    // 6.  RV32I core instance
    //     *** REPLACE THIS BLOCK with V-FRONT's actual top-level module.
    //     *** The wiring pattern is shown in docs/VFRONT_INTEGRATION.md.
    //     For the first bring-up, synth will fail at this line, which is
    //     the intended signal to apply the patch.
    // -----------------------------------------------------------------
    rv32i_core_top u_core (
        .clk                  (clk_core),
        .rst_n                (rst_n),
        // to BP
        .if_valid_o           (core_if_valid),
        .if_pc_o              (core_if_pc),
        .if_is_cond_branch_o  (core_if_is_cond_branch),
        // from BP
        .bp_predict_taken_i   (bp_predict_taken),
        .bp_btb_hit_i         (bp_btb_hit),
        .bp_btb_target_i      (bp_btb_target),
        .bp_ghr_snap_i        (bp_ghr_snap),
        .bp_lh_snap_i         (bp_lh_snap),
        // EX feedback to BP
        .ex_valid_o           (core_ex_valid),
        .ex_is_cond_branch_o  (core_ex_is_cond_branch),
        .ex_is_jump_o         (core_ex_is_jump),
        .ex_pc_o              (core_ex_pc),
        .ex_target_o          (core_ex_target),
        .ex_taken_o           (core_ex_taken),
        .ex_mispredict_o      (core_ex_mispredict),
        .ex_ghr_snap_o        (core_ex_ghr_snap),
        .ex_lh_snap_o         (core_ex_lh_snap)
    );

    // -----------------------------------------------------------------
    // 7.  Performance dumper -> UART on BTN1 rising edge
    // -----------------------------------------------------------------
    perf_dumper u_dump (
        .clk(clk_core), .rst_n(rst_n),
        .trigger_i (btn1_deb),
        .cfg_sel_i (cfg_sel),
        .br_i      (perf_br),
        .mis_i     (perf_mis),
        .btb_i     (perf_btb),
        .cyc_i     (perf_cyc),
        .tx_o      (ja_tx)
    );

    // -----------------------------------------------------------------
    // 8.  LED mapping
    //   led[0] = running (heartbeat)
    //   led[1] = echo of cfg_sel bit 0
    //   led[2] = echo of cfg_sel bit 1
    //   led[3] = misprediction indicator (blinks when mis count increments)
    // -----------------------------------------------------------------
    logic [24:0] hb;
    always_ff @(posedge clk_core or negedge rst_n)
        if (!rst_n) hb <= '0; else hb <= hb + 1'b1;

    logic [31:0] perf_mis_q;
    logic        mis_flash;
    always_ff @(posedge clk_core or negedge rst_n) begin
        if (!rst_n) begin perf_mis_q <= '0; mis_flash <= 1'b0; end
        else begin
            perf_mis_q <= perf_mis;
            mis_flash  <= (perf_mis != perf_mis_q);
        end
    end

    assign led[0] = hb[24];
    assign led[1] = cfg_sel[0];
    assign led[2] = cfg_sel[1];
    assign led[3] = mis_flash;

endmodule