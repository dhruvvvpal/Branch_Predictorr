// =============================================================================
// uart_tx.sv -- 8N1 UART transmitter, parameterised baud divisor
// -----------------------------------------------------------------------------
// At 50 MHz sys clock, DIVISOR = 50_000_000 / 115_200 = 434.
// Assert start_i with data_i for one cycle; busy_o high until byte sent.
// =============================================================================
module uart_tx #(
    parameter int CLK_HZ  = 50_000_000,
    parameter int BAUD    = 115_200
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start_i,
    input  logic [7:0]  data_i,
    output logic        busy_o,
    output logic        tx_o
);
    localparam int DIVISOR = CLK_HZ / BAUD;

    typedef enum logic [1:0] { IDLE, START, DATA, STOP } state_e;
    state_e           state_q;
    logic [$clog2(DIVISOR)-1:0] baud_cnt;
    logic [3:0]       bit_idx;
    logic [7:0]       shift_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q  <= IDLE;
            baud_cnt <= '0;
            bit_idx  <= '0;
            shift_q  <= '0;
            tx_o     <= 1'b1;
            busy_o   <= 1'b0;
        end else begin
            case (state_q)
                IDLE: begin
                    tx_o   <= 1'b1;
                    busy_o <= 1'b0;
                    if (start_i) begin
                        shift_q  <= data_i;
                        state_q  <= START;
                        baud_cnt <= '0;
                        busy_o   <= 1'b1;
                    end
                end
                START: begin
                    tx_o <= 1'b0;
                    if (baud_cnt == DIVISOR-1) begin
                        baud_cnt <= '0;
                        bit_idx  <= 4'd0;
                        state_q  <= DATA;
                    end else baud_cnt <= baud_cnt + 1'b1;
                end
                DATA: begin
                    tx_o <= shift_q[0];
                    if (baud_cnt == DIVISOR-1) begin
                        baud_cnt <= '0;
                        shift_q  <= {1'b0, shift_q[7:1]};
                        if (bit_idx == 4'd7) state_q <= STOP;
                        else                 bit_idx <= bit_idx + 1'b1;
                    end else baud_cnt <= baud_cnt + 1'b1;
                end
                STOP: begin
                    tx_o <= 1'b1;
                    if (baud_cnt == DIVISOR-1) begin
                        baud_cnt <= '0;
                        state_q  <= IDLE;
                    end else baud_cnt <= baud_cnt + 1'b1;
                end
            endcase
        end
    end
endmodule
