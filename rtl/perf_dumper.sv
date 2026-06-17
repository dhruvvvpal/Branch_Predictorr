// =============================================================================
// perf_dumper.sv -- on rising edge of trigger_i, TXs counters as hex ASCII
// -----------------------------------------------------------------------------
// Format sent per trigger (ASCII, CR/LF):
//   "SEL=x BR=xxxxxxxx MIS=xxxxxxxx BTB=xxxxxxxx CYC=xxxxxxxx\r\n"
// Total 59 bytes.
// =============================================================================
module perf_dumper (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        trigger_i,    // one-cycle pulse on BTN1 press
    input  logic [1:0]  cfg_sel_i,
    input  logic [31:0] br_i,
    input  logic [31:0] mis_i,
    input  logic [31:0] btb_i,
    input  logic [31:0] cyc_i,
    output logic        tx_o
);
    // rising-edge detect
    logic trig_q;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) trig_q <= 1'b0; else trig_q <= trigger_i;
    wire trig_pulse = trigger_i & ~trig_q;

    localparam int MSG_LEN = 59;
    logic [7:0] msg [0:MSG_LEN-1];

    // nibble -> ASCII hex
    function automatic logic [7:0] nib(input logic [3:0] n);
        nib = (n < 4'd10) ? (8'h30 + n) : (8'h57 + n);  // '0'-'9','a'-'f'
    endfunction

    // Latch the snapshot at trigger time so values don't move while we send
    logic [1:0]  s_sel;
    logic [31:0] s_br, s_mis, s_btb, s_cyc;

    // Send state machine
    typedef enum logic [1:0] { S_IDLE, S_LOAD, S_SEND } st_e;
    st_e st_q;
    logic [$clog2(MSG_LEN+1)-1:0] idx;
    logic        uart_start;
    logic [7:0]  uart_data;
    logic        uart_busy;

    uart_tx u_uart (
        .clk(clk), .rst_n(rst_n),
        .start_i(uart_start), .data_i(uart_data),
        .busy_o(uart_busy), .tx_o(tx_o)
    );

    integer k;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st_q       <= S_IDLE;
            idx        <= '0;
            uart_start <= 1'b0;
            uart_data  <= 8'h00;
            s_sel <= 2'b00; s_br <= '0; s_mis <= '0; s_btb <= '0; s_cyc <= '0;
        end else begin
            uart_start <= 1'b0;
            case (st_q)
                S_IDLE: if (trig_pulse) begin
                    s_sel <= cfg_sel_i;
                    s_br  <= br_i;
                    s_mis <= mis_i;
                    s_btb <= btb_i;
                    s_cyc <= cyc_i;
                    st_q  <= S_LOAD;
                end
                S_LOAD: begin
                    // Build fixed message:
                    // "SEL=x BR=xxxxxxxx MIS=xxxxxxxx BTB=xxxxxxxx CYC=xxxxxxxx\r\n"
                    msg[0]=8'h53; msg[1]=8'h45; msg[2]=8'h4C; msg[3]=8'h3D;       // "SEL="
                    msg[4]=nib({2'b00, s_sel}); msg[5]=8'h20;                    // "x "
                    msg[6]=8'h42; msg[7]=8'h52; msg[8]=8'h3D;                    // "BR="
                    msg[9] =nib(s_br[31:28]); msg[10]=nib(s_br[27:24]);
                    msg[11]=nib(s_br[23:20]); msg[12]=nib(s_br[19:16]);
                    msg[13]=nib(s_br[15:12]); msg[14]=nib(s_br[11:8]);
                    msg[15]=nib(s_br[7:4]);   msg[16]=nib(s_br[3:0]);
                    msg[17]=8'h20;
                    msg[18]=8'h4D; msg[19]=8'h49; msg[20]=8'h53; msg[21]=8'h3D;  // "MIS="
                    msg[22]=nib(s_mis[31:28]); msg[23]=nib(s_mis[27:24]);
                    msg[24]=nib(s_mis[23:20]); msg[25]=nib(s_mis[19:16]);
                    msg[26]=nib(s_mis[15:12]); msg[27]=nib(s_mis[11:8]);
                    msg[28]=nib(s_mis[7:4]);   msg[29]=nib(s_mis[3:0]);
                    msg[30]=8'h20;
                    msg[31]=8'h42; msg[32]=8'h54; msg[33]=8'h42; msg[34]=8'h3D;  // "BTB="
                    msg[35]=nib(s_btb[31:28]); msg[36]=nib(s_btb[27:24]);
                    msg[37]=nib(s_btb[23:20]); msg[38]=nib(s_btb[19:16]);
                    msg[39]=nib(s_btb[15:12]); msg[40]=nib(s_btb[11:8]);
                    msg[41]=nib(s_btb[7:4]);   msg[42]=nib(s_btb[3:0]);
                    msg[43]=8'h20;
                    msg[44]=8'h43; msg[45]=8'h59; msg[46]=8'h43; msg[47]=8'h3D;  // "CYC="
                    msg[48]=nib(s_cyc[31:28]); msg[49]=nib(s_cyc[27:24]);
                    msg[50]=nib(s_cyc[23:20]); msg[51]=nib(s_cyc[19:16]);
                    msg[52]=nib(s_cyc[15:12]); msg[53]=nib(s_cyc[11:8]);
                    msg[54]=nib(s_cyc[7:4]);   msg[55]=nib(s_cyc[3:0]);
                    msg[56]=8'h0D; msg[57]=8'h0A;                                 // CR/LF
                    msg[58]=8'h00;                                                // pad
                    idx  <= '0;
                    st_q <= S_SEND;
                end
                S_SEND: begin
                    if (!uart_busy && !uart_start) begin
                        if (idx == MSG_LEN[$clog2(MSG_LEN+1)-1:0] - 1) begin
                            st_q <= S_IDLE;
                        end else begin
                            uart_data  <= msg[idx];
                            uart_start <= 1'b1;
                            idx        <= idx + 1'b1;
                        end
                    end
                end
            endcase
        end
    end
endmodule
