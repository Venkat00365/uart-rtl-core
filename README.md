# Configurable UART RTL Core with Self-Checking Verification

A parameterized 8N1 UART transmitter/receiver core written in synthesizable
Verilog, verified with a self-checking testbench in Icarus Verilog, with
waveform evidence captured in GTKWave.

## 1. Overview

This project implements a UART (Universal Asynchronous Receiver/Transmitter)
core from scratch: a baud-rate generator, an FSM-based transmitter, and an
FSM-based receiver with input synchronization and mid-bit sampling.

It was built to demonstrate practical RTL design skills for core
ECE/VLSI/FPGA roles: clocked FSM design, parameterization, metastability-safe
input handling, and a proper verification flow, rather than just "code that
compiles."

UART is one of the most widely used serial protocols in embedded systems —
it shows up in microcontroller debug consoles, sensor modules, GPS/Bluetooth
modules, and inter-board communication — so this core is a realistic,
directly reusable building block, not a toy exercise.

## 2. Features

- Standard **8N1** framing: 1 start bit, 8 data bits (LSB first), 1 stop bit
- **Parameterized** clock frequency and baud rate (`CLK_FREQ`, `BAUD_RATE`)
- **16x oversampled** receiver with mid-bit sampling for reliable data
  recovery even with small clock/phase offsets
- **2-flip-flop synchronizer** on the RX input to avoid metastability from an
  asynchronous external signal
- Glitch rejection on the start bit (re-confirmed at its midpoint before a
  frame is accepted)
- `tx_busy` flag with correct "reject new start while busy" behavior
- Self-contained internal loopback top module (`uart_top`) for fully
  automated self-verification with no external stimulus modeling needed
- Self-checking testbench with automatic PASS/FAIL reporting and a final
  summary — no manual waveform inspection required to know the design works

## 3. Architecture

```text
                        uart_top
        +----------------------------------------------+
        |                                                |
        |   +-----------+          baud_tick             |
        |   | baud_gen  |------------------+-----------+ |
        |   +-----------+                  |           | |
        |                                  v           v |
tx_start --------------------------> +-----------+  +-----------+
tx_data  --------------------------->| uart_tx   |  | uart_rx   |
        |                            +-----------+  +-----------+
        |                                  |              ^
        |                                  |  serial_line |
        |                                  +--------------+
        |                                  |
        |                                  v
        +----------------------------------+---> serial_line (observable)
        |
tx_busy  <--------------------------- uart_tx.tx_busy
rx_data  <--------------------------- uart_rx.rx_data
rx_valid <--------------------------- uart_rx.rx_valid
```

- **baud_gen** — divides the system clock down to a tick that pulses at 16x
  the target baud rate. Both TX and RX derive all of their bit-timing from
  this single tick, so they always agree on bit boundaries.
- **uart_tx** — a 4-state FSM (`IDLE -> START_BIT -> DATA_BITS -> STOP_BIT`)
  that shifts `tx_data` onto `serial_line`, one bit per 16 ticks.
- **uart_rx** — a 4-state FSM that watches `serial_line` for a falling edge,
  confirms it's a real start bit at its midpoint, then samples each
  subsequent bit at its midpoint using the same 16x tick reference.
- **uart_top** — wires TX's serial output directly to RX's serial input
  (internal loopback), so the whole datapath is exercised and checked in one
  self-contained core.

## 4. Design Details

- **Clock & reset**: single clock domain, active-low asynchronous reset
  (`rst_n`), synchronous release, used consistently across all modules.
- **Baud generation**: `DIVISOR = CLK_FREQ / (BAUD_RATE * 16)`. Default
  parameters (`CLK_FREQ = 1,843,200`, `BAUD_RATE = 9600`) give an exact
  integer divisor of 12 — a classic UART reference clock combination chosen
  specifically because it divides evenly, so there's zero long-term baud
  error in real hardware (many designs pick clocks for exactly this reason).
- **TX FSM**: holds each bit for a full 16-tick period counted by `tick_cnt`.
  `bit_idx` walks the 8 data bits LSB first via `shift_reg[bit_idx]`.
- **RX FSM**: detects a falling edge in `IDLE`, waits 8 ticks (half a bit
  period) to land on the start bit's midpoint and re-checks the line is
  still low (rejects short glitches), then samples each of the 8 data bits
  16 ticks apart — which lands exactly on each bit's midpoint — and finally
  samples the stop bit's midpoint before declaring `rx_valid`.
- **Synchronizer**: `rx_sync0`/`rx_sync1` form a standard 2-FF synchronizer
  so the asynchronous `rx` input is never used directly in FSM logic.
- **Important timing note**: `rx_valid` pulses at the *midpoint* of the stop
  bit (for fast turnaround to the next byte), which is *before* `uart_tx`
  finishes driving the full stop-bit period and clears `tx_busy`. Anything
  that waits for a byte to arrive and then wants to immediately send another
  should wait for `tx_busy == 0`, not just `rx_valid`, before asserting the
  next `tx_start` — this is exactly the kind of framing subtlety that is
  worth being able to explain in an interview.

## 5. Verification

`tb/tb_uart_top.v` is a self-checking testbench: it drives `tx_start`/
`tx_data`, waits for the loopback `rx_valid`, and automatically compares the
received byte against what was sent — printing PASS/FAIL per test with no
manual waveform reading required.

| # | Test                     | What it checks                                            |
|---|--------------------------|------------------------------------------------------------|
| 1 | Reset                    | Core comes out of reset idle (`tx_busy=0`, line high)      |
| 2 | Transmit 'A' (0x41)      | Basic single-byte transmit/receive                          |
| 3 | Transmit 'B' (0x42)      | Basic single-byte transmit/receive                          |
| 4 | Transmit 0x00            | Boundary value — all data bits low                          |
| 5 | Transmit 0xFF            | Boundary value — all data bits high                         |
| 6 | Multi-byte 'H' (0x48)    | Back-to-back transfer #1                                    |
| 7 | Multi-byte 'I' (0x49)    | Back-to-back transfer #2, right after #1                    |
| 8 | Invalid/edge case        | A second `tx_start` while already busy must be ignored      |

## 6. Simulation Results

Actual terminal output from `vvp` (Icarus Verilog), unedited:

```text
========================================
        UART SIMULATION
========================================
Test 1: Reset                    PASS
Test 2: Transmit 'A'             PASS  (sent=0x41 received=0x41)
Test 3: Transmit 'B'             PASS  (sent=0x42 received=0x42)
Test 4: Transmit 0x00            PASS  (sent=0x00 received=0x00)
Test 5: Transmit 0xFF            PASS  (sent=0xff received=0xff)
Test 6: Multi-byte 'H'           PASS  (sent=0x48 received=0x48)
Test 7: Multi-byte 'I'           PASS  (sent=0x49 received=0x49)
Test 8: Invalid/edge case        PASS  (busy correctly ignored new tx_start)
----------------------------------------
ALL 8 TESTS PASSED
----------------------------------------
```

A copy of this log is saved at `simulation/simulation_output.txt`, and the
full waveform is at `simulation/simulation.vcd`.

**What to look for in GTKWave** (`gtkwave simulation/simulation.vcd`): add
`tb_uart_top.dut.clk`, `rst_n`, `tx_start`, `tx_data`, `serial_line`,
`tx_busy`, `rx_data`, `rx_valid`, and — for the deeper story —
`dut.u_uart_tx.state`, `dut.u_uart_rx.state`, and `dut.u_baud_gen.tick`.
Zoom into one byte transmission and you should see: `tx_start` pulses for
one cycle, `serial_line` drops low (start bit) for exactly 16 `tick` pulses,
then 8 data bit periods matching `tx_data` (LSB first), then `serial_line`
returns high (stop bit), and shortly after, `rx_valid` pulses once with
`rx_data` equal to the original `tx_data`. Take a screenshot of this region
for your README/portfolio — it's the single clearest visual proof the core
works.

## 7. Project Structure

```text
uart-rtl-core/
├── rtl/
│   ├── baud_gen.v
│   ├── uart_tx.v
│   ├── uart_rx.v
│   └── uart_top.v
├── tb/
│   └── tb_uart_top.v
├── simulation/
│   ├── simulation.vcd
│   └── simulation_output.txt
├── README.md
├── LICENSE
└── .gitignore
```

## 8. How to Run

Requires [Icarus Verilog](http://iverilog.icarus.com/) and (optionally)
[GTKWave](https://gtkwave.sourceforge.net/) — both free and open source.

```bash
# Compile RTL + testbench
iverilog -g2001 -o sim/uart_sim rtl/baud_gen.v rtl/uart_tx.v rtl/uart_rx.v rtl/uart_top.v tb/tb_uart_top.v

# Run the simulation (produces the PASS/FAIL log and simulation.vcd)
cd sim && vvp uart_sim

# View the waveform
gtkwave simulation.vcd
```

## 9. Skills Demonstrated

Verilog RTL Design, FSM Design, Synchronous/Asynchronous Reset Handling,
Clock-Domain Synchronization (2-FF synchronizer), UART Protocol
Implementation, Self-Checking Testbench Development, Icarus Verilog, GTKWave
Waveform Analysis, Git/GitHub Project Structuring.

## 10. Future Improvements

- Split the internal loopback into independent `tx`/`rx` top-level pins for
  connection to a real external UART device or FPGA I/O
- Add parity bit support (odd/even) as a configurable option
- Add framing-error and overrun-error detection/flags on the RX side
- Wrap TX/RX data paths with FIFOs for buffered, back-to-back byte streaming
- Add an APB/Wishbone register interface so the core can be memory-mapped
  into an SoC

## License

MIT — see `LICENSE`.
