// =============================================================================
// uart_tx.v
// UART Transmitter (8 data bits, no parity, 1 stop bit -- "8N1")
//
// Serializes tx_data onto the tx line one bit at a time, framed as:
//   [ start bit (0) ][ 8 data bits, LSB first ][ stop bit (1) ]
// Each bit is held for 16 baud_tick pulses (16x oversampled bit period).
// =============================================================================

`timescale 1ns/1ps

module uart_tx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       baud_tick,   // 16x baud rate tick from baud_gen
    input  wire       tx_start,    // pulse high for >=1 clk to begin a frame
    input  wire [7:0] tx_data,     // byte to transmit, sampled when tx_start fires
    output reg        tx,          // serial output line (idles high)
    output reg        tx_busy      // high while a frame is in progress
);

    localparam IDLE      = 2'd0,
               START_BIT = 2'd1,
               DATA_BITS = 2'd2,
               STOP_BIT  = 2'd3;

    reg [1:0] state;
    reg [3:0] tick_cnt;   // counts 0-15 within the current bit period
    reg [2:0] bit_idx;    // index of the data bit currently being sent (0-7)
    reg [7:0] shift_reg;  // holds the byte being shifted out

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            tx        <= 1'b1;   // idle line level is high
            tx_busy   <= 1'b0;
            tick_cnt  <= 4'd0;
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
        end else begin
            case (state)
                // Wait for a request to send a byte.
                IDLE: begin
                    tx <= 1'b1;
                    if (tx_start) begin
                        shift_reg <= tx_data;
                        tx_busy   <= 1'b1;
                        tick_cnt  <= 4'd0;
                        state     <= START_BIT;
                    end else begin
                        tx_busy <= 1'b0;
                    end
                end

                // Drive the line low for one full bit period.
                START_BIT: begin
                    tx <= 1'b0;
                    if (baud_tick) begin
                        if (tick_cnt == 4'd15) begin
                            tick_cnt <= 4'd0;
                            bit_idx  <= 3'd0;
                            state    <= DATA_BITS;
                        end else begin
                            tick_cnt <= tick_cnt + 4'd1;
                        end
                    end
                end

                // Shift out 8 data bits, LSB first.
                DATA_BITS: begin
                    tx <= shift_reg[bit_idx];
                    if (baud_tick) begin
                        if (tick_cnt == 4'd15) begin
                            tick_cnt <= 4'd0;
                            if (bit_idx == 3'd7) begin
                                state <= STOP_BIT;
                            end else begin
                                bit_idx <= bit_idx + 3'd1;
                            end
                        end else begin
                            tick_cnt <= tick_cnt + 4'd1;
                        end
                    end
                end

                // Drive the line high for one full bit period, then return to idle.
                STOP_BIT: begin
                    tx <= 1'b1;
                    if (baud_tick) begin
                        if (tick_cnt == 4'd15) begin
                            tick_cnt <= 4'd0;
                            tx_busy  <= 1'b0;
                            state    <= IDLE;
                        end else begin
                            tick_cnt <= tick_cnt + 4'd1;
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
