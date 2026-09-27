// =============================================================================
// baud_gen.v
// Baud-rate tick generator.
//
// Divides the system clock down to a tick that pulses at 16x the target
// baud rate. Both uart_tx and uart_rx use this 16x tick for internal timing:
// uart_tx counts 16 ticks per bit period, and uart_rx uses the same 16x
// resolution to sample each incoming bit at its midpoint.
// =============================================================================

`timescale 1ns/1ps

module baud_gen #(
    parameter CLK_FREQ  = 1_843_200,  // system clock frequency, Hz
    parameter BAUD_RATE = 9600        // desired UART baud rate
)(
    input  wire clk,
    input  wire rst_n,
    output reg  tick        // 1 clk-cycle-wide pulse at 16x BAUD_RATE
);

    // Number of system clock cycles per 16x tick.
    // Example: 1,843,200 Hz / (9600 * 16) = 12 clocks per tick.
    localparam integer DIVISOR = CLK_FREQ / (BAUD_RATE * 16);

    reg [15:0] count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 16'd0;
            tick  <= 1'b0;
        end else if (count == DIVISOR - 1) begin
            count <= 16'd0;
            tick  <= 1'b1;
        end else begin
            count <= count + 16'd1;
            tick  <= 1'b0;
        end
    end

endmodule
