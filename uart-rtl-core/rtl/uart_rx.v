// =============================================================================
// uart_rx.v
// UART Receiver (8 data bits, no parity, 1 stop bit -- "8N1")
//
// Watches the rx line for a falling edge (start bit), confirms it at the
// bit's midpoint to reject glitches, then samples each of the 8 data bits
// at its midpoint using the 16x baud_tick for accurate alignment even if
// the incoming edge is not perfectly synchronized to our clock.
// =============================================================================

`timescale 1ns/1ps

module uart_rx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       baud_tick,   // 16x baud rate tick from baud_gen
    input  wire       rx,          // serial input line (idles high)
    output reg  [7:0] rx_data,     // last byte received
    output reg        rx_valid     // 1 clk-cycle pulse when rx_data is new
);

    localparam IDLE      = 2'd0,
               START_BIT = 2'd1,
               DATA_BITS = 2'd2,
               STOP_BIT  = 2'd3;

    reg [1:0] state;
    reg [3:0] tick_cnt;
    reg [2:0] bit_idx;
    reg [7:0] shift_reg;

    // 2-flip-flop synchronizer: rx is an asynchronous external input,
    // so it must be synchronized into the clk domain before use to
    // avoid metastability.
    reg rx_sync0, rx_sync1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync0 <= 1'b1;
            rx_sync1 <= 1'b1;
        end else begin
            rx_sync0 <= rx;
            rx_sync1 <= rx_sync0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            tick_cnt  <= 4'd0;
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
            rx_data   <= 8'd0;
            rx_valid  <= 1'b0;
        end else begin
            rx_valid <= 1'b0;   // default: rx_valid is a single-cycle pulse

            case (state)
                // Wait for the line to fall low (candidate start bit).
                IDLE: begin
                    tick_cnt <= 4'd0;
                    if (rx_sync1 == 1'b0) begin
                        state <= START_BIT;
                    end
                end

                // Confirm the start bit at its midpoint (8 of 16 ticks in).
                // This rejects short glitches that are not a real start bit.
                START_BIT: begin
                    if (baud_tick) begin
                        if (tick_cnt == 4'd7) begin
                            if (rx_sync1 == 1'b0) begin
                                tick_cnt <= 4'd0;
                                bit_idx  <= 3'd0;
                                state    <= DATA_BITS;
                            end else begin
                                state <= IDLE;  // false start, go back to waiting
                            end
                        end else begin
                            tick_cnt <= tick_cnt + 4'd1;
                        end
                    end
                end

                // Sample each data bit at its midpoint, LSB first.
                DATA_BITS: begin
                    if (baud_tick) begin
                        if (tick_cnt == 4'd15) begin
                            tick_cnt <= 4'd0;
                            shift_reg[bit_idx] <= rx_sync1;
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

                // Land at the midpoint of the stop bit, latch the received
                // byte and pulse rx_valid, then return to idle.
                STOP_BIT: begin
                    if (baud_tick) begin
                        if (tick_cnt == 4'd15) begin
                            tick_cnt <= 4'd0;
                            rx_data  <= shift_reg;
                            rx_valid <= 1'b1;
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
