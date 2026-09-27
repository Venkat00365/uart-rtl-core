// =============================================================================
// uart_top.v
// Top-level UART core: integrates the baud generator, transmitter and
// receiver behind a single set of ports.
//
// tx and rx share one internal serial line ("serial_line") so the core is a
// self-contained loopback UART: whatever byte is transmitted comes back out
// on rx_data. This makes the design fully self-verifiable in simulation
// with no external testbench-side serial modeling required. In a real
// system, uart_tx's output and uart_rx's input would instead connect to the
// TX/RX pins of an external UART device (see "Future Improvements" in the
// README for how to split this into independent TX/RX pins).
// =============================================================================

`timescale 1ns/1ps

module uart_top #(
    parameter CLK_FREQ  = 1_843_200,
    parameter BAUD_RATE = 9600
)(
    input  wire       clk,
    input  wire       rst_n,

    // transmit side
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output wire        tx_busy,

    // receive side
    output wire [7:0] rx_data,
    output wire       rx_valid,

    // observable serial line (tx drives it, rx listens to it)
    output wire       serial_line
);

    wire baud_tick;

    baud_gen #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_baud_gen (
        .clk  (clk),
        .rst_n(rst_n),
        .tick (baud_tick)
    );

    uart_tx u_uart_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .baud_tick(baud_tick),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx       (serial_line),
        .tx_busy  (tx_busy)
    );

    uart_rx u_uart_rx (
        .clk      (clk),
        .rst_n    (rst_n),
        .baud_tick(baud_tick),
        .rx       (serial_line),
        .rx_data  (rx_data),
        .rx_valid (rx_valid)
    );

endmodule
