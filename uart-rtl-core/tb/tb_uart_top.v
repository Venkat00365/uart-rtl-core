// =============================================================================
// tb_uart_top.v
// Self-checking testbench for uart_top.
//
// Drives tx_start/tx_data, waits for the loopback rx_valid pulse, and
// compares rx_data against what was sent. Prints a PASS/FAIL line per test
// and a final summary, then calls $finish automatically.
// =============================================================================

`timescale 1ns/1ps

module tb_uart_top;

    localparam CLK_FREQ   = 1_843_200;
    localparam BAUD_RATE  = 9600;
    localparam CLK_PERIOD = 1_000_000_000 / CLK_FREQ;   // ns, ~542 ns

    reg        clk;
    reg        rst_n;
    reg        tx_start;
    reg  [7:0] tx_data;
    wire       tx_busy;
    wire [7:0] rx_data;
    wire       rx_valid;
    wire       serial_line;

    integer pass_count;
    integer fail_count;
    integer test_num;

    uart_top #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .tx_start   (tx_start),
        .tx_data    (tx_data),
        .tx_busy    (tx_busy),
        .rx_data    (rx_data),
        .rx_valid   (rx_valid),
        .serial_line(serial_line)
    );

    // clock generation
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // waveform dump
    initial begin
        $dumpfile("simulation.vcd");
        $dumpvars(0, tb_uart_top);
    end

    // Sends one byte and checks it comes back correctly via loopback.
    task send_and_check(input [7:0] data, input [23*8:0] label);
        begin
            test_num = test_num + 1;
            @(posedge clk);
            tx_start <= 1'b1;
            tx_data  <= data;
            @(posedge clk);
            tx_start <= 1'b0;

            fork : wait_block
                begin
                    wait (rx_valid == 1'b1);
                    disable wait_block;
                end
                begin
                    #(CLK_PERIOD * 20000);   // generous timeout safety net
                    disable wait_block;
                end
            join

            if (rx_valid && rx_data == data) begin
                $display("Test %0d: %-24s PASS  (sent=0x%02h received=0x%02h)",
                          test_num, label, data, rx_data);
                pass_count = pass_count + 1;
            end else begin
                $display("Test %0d: %-24s FAIL  (sent=0x%02h received=0x%02h rx_valid=%b)",
                          test_num, label, data, rx_data, rx_valid);
                fail_count = fail_count + 1;
            end

            // uart_rx raises rx_valid at the midpoint of the stop bit (for
            // fast turnaround), which is *before* uart_tx finishes driving
            // the full stop-bit period and clears tx_busy. Wait for tx_busy
            // to actually clear before starting the next frame, otherwise a
            // new tx_start would arrive while the core is still busy and be
            // correctly-but-inconveniently ignored.
            if (tx_busy) begin
                wait (tx_busy == 1'b0);
            end
            @(posedge clk);
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        test_num   = 0;
        tx_start   = 1'b0;
        tx_data    = 8'h00;
        rst_n      = 1'b0;

        $display("========================================");
        $display("        UART SIMULATION");
        $display("========================================");

        // Test 1: reset drives the core to a known idle state
        repeat (5) @(posedge clk);
        test_num = test_num + 1;
        if (tx_busy == 1'b0 && serial_line == 1'b1) begin
            $display("Test %0d: %-24s PASS", test_num, "Reset");
            pass_count = pass_count + 1;
        end else begin
            $display("Test %0d: %-24s FAIL", test_num, "Reset");
            fail_count = fail_count + 1;
        end
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // Tests 2-3: basic single-character transmission
        send_and_check(8'h41, "Transmit 'A'");
        send_and_check(8'h42, "Transmit 'B'");

        // Test 4: boundary value - all zeros
        send_and_check(8'h00, "Transmit 0x00");

        // Test 5: boundary value - all ones
        send_and_check(8'hFF, "Transmit 0xFF");

        // Tests 6-7: back-to-back multiple bytes
        send_and_check(8'h48, "Multi-byte 'H'");
        send_and_check(8'h49, "Multi-byte 'I'");

        // Test 8: edge case - a second tx_start arriving while the core is
        // already busy transmitting must be ignored (frame must not restart
        // or corrupt mid-transmission).
        test_num = test_num + 1;
        @(posedge clk);
        tx_start <= 1'b1;
        tx_data  <= 8'h58;          // 'X'
        @(posedge clk);
        tx_start <= 1'b1;           // still asserted
        tx_data  <= 8'h59;          // 'Y' - must be ignored, core is now busy
        @(posedge clk);
        tx_start <= 1'b0;

        wait (rx_valid == 1'b1);
        if (rx_data == 8'h58) begin
            $display("Test %0d: %-24s PASS  (busy correctly ignored new tx_start)",
                      test_num, "Invalid/edge case");
            pass_count = pass_count + 1;
        end else begin
            $display("Test %0d: %-24s FAIL  (unexpected byte 0x%02h)",
                      test_num, "Invalid/edge case", rx_data);
            fail_count = fail_count + 1;
        end

        repeat (20) @(posedge clk);

        $display("----------------------------------------");
        if (fail_count == 0) begin
            $display("ALL %0d TESTS PASSED", pass_count);
        end else begin
            $display("%0d PASSED, %0d FAILED", pass_count, fail_count);
        end
        $display("----------------------------------------");

        $finish;
    end

endmodule
