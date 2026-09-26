# ProEm - Open Source Protocol Emulator

ProEm is an open-source protocol emulator ASIC: a chip that lets an RP2040 speak many serial protocols through one piece of
hardware. The RP2040 describes a frame in a few instruction bytes; the chip runs it at up to one
bit per clock, with exact timing, and sends back what it received plus a status for every frame.

Target: IHP SG13G2 130 nm through [Tiny Tapeout](https://tinytapeout.com) (6 × 4 tiles), 50 MHz.
Built for the [Jane Street protocol emulator ASIC competition](https://blog.janestreet.com/protocol-emulator-asic-competition/).

![Architecture](docs/protocol_emulator_architecture.png)

## At a glance

| | |
| --- | --- |
| Channels | 2 independent channels, A and B, running at the same time |
| Host link | UART in with auto-baud, UART out at a rate set by `LINK` (down to 4 clocks per bit) |
| Verified at pin level | UART, SPI (controller and target), I2C controller, PS/2, 10BASE-T receive, Manchester transmit, USB low speed receive and transmit |
| Logic | 12,031 IHP SG13G2 cells, about half of the 6 × 4 tile budget |
| Timing | 6.6 ns worst path at 1.08 V, 125 °C (20 ns budget at 50 MHz) |
| Instruction set | ISA v0.4, see [docs/protocol_emulator_isa.pdf](docs/protocol_emulator_isa.pdf) |

## How it works

* **Host side.** A UART receiver with auto-baud feeds a control unit that decodes ISA
  instructions into registered configuration writes. A return path sends received data, a status
  per frame and link events back on a second UART.
* **Input pipeline.** Every input pin passes through two synchroniser flops and one register.
* **Two channels.** Each has a host FIFO for write data, a *frame chain* (START, up to six headers,
  MAIN, END, watchdog, frame buffer), an entry dispatcher, and a *line codec*:
  * tick source: SYNC (clock pin edge), ASYNC / RECOVER (bit timer that re-centres on edges),
    GENERATE (drives SCK / SCL, with clock stretching);
  * decoder: NRZ, NRZI, NRZI on the USB pair, Manchester, bit unstuffing;
  * encoder: the same codes, stuff insertion, I2C START / Sr / STOP, USB end of packet,
    open drain, chip select.

The [design reference](docs/protocol_emulator_design.pdf) explains every block and gives the exact
instruction bytes for each standard.

## Repository layout

```
rtl/
  top/              protocol_emulator.sv       top level
                    protocol_emulator_inst.sv  instantiation template
  core/             emulator_channel, control_unit, line_codec, entry_dispatch, return_path
    frame_chain/    frame_chain and its blocks (START, headers, router, MAIN, END, watchdog)
  primitives/       uart_rx, uart_tx, host_fifo, frame_buffer
  files.f           file list in compile order
sim/                pin-level test bench (bench.h) and one test per standard (t_*.cpp)
scripts/            run.sh (all tests + synthesis), sta.sh (timing check)
docs/               design reference and ISA spec (PDF + LaTeX), architecture diagram
  diagram/          diagram generator (make_diagram.py) and its fonts (SIL OFL)
.github/workflows/  CI: runs every test on each push
```

Module hierarchy:

```
protocol_emulator                      rtl/top
├── uart_rx                            rtl/primitives
├── control_unit                       rtl/core
├── emulator_channel (A and B)         rtl/core
│   ├── host_fifo                      rtl/primitives
│   ├── line_codec                     rtl/core
│   ├── frame_chain                    rtl/core/frame_chain
│   │   ├── first_counter, header_counter (x6), start_router
│   │   ├── main_counter, end_counter, watchdog
│   │   └── frame_buffer               rtl/primitives
│   └── entry_dispatch                 rtl/core
└── return_path                        rtl/core
    └── uart_tx                        rtl/primitives
```

Every file starts with a header: file, module, type (top level, core RTL or primitive), place in
the hierarchy, submodules, author, and a description line.

## Running the tests

Needs Linux, macOS or WSL on Windows, with `g++`, Python 3 and Yosys:

```sh
pip install yowasp-yosys          # or install Yosys from your package manager
bash scripts/run.sh               # every test, then synthesis
SKIP_SYNTH=1 bash scripts/run.sh  # tests only
LIBERTY=path/to/sg13g2_stdcell_typ.lib bash scripts/run.sh                       # area in IHP cells
LIBERTY=path/to/sg13g2_stdcell_slow_1p08V_125C.lib bash scripts/sta.sh           # timing
```

Every test resets the chip, sends `0x55` for auto-baud, programs it with instruction bytes on
`rx_serial`, drives or models the real protocol lines at the pins, and decodes the results from
`tx_serial`.

| Test | What it covers |
| --- | --- |
| `t_control` | auto-baud, error flags, `HALT`, `CLEAR`, `LINK`, watchdog, START alignment, dropped `DATA` |
| `t_uart` | UART receive from a sender 2 % off rate, transmit on the other channel |
| `t_spi` | SPI controller full duplex against a slave model; SPI target against a master model |
| `t_i2c` | I2C controller on an open-drain bus: write, read with repeated START, clock stretching, NACK |
| `t_ps2` | PS/2 device to host |
| `t_ethernet` | 10BASE-T receive from a jittered Manchester line, CRC checked; overflow reporting |
| `t_manchester` | Manchester transmit decoded by the other channel |
| `t_usb` | USB low speed receive (stuffing, SE1 and stuff errors), transmit, and loopback |
| `t_random` | 1,800 random programs in both bit orders |

## Regenerating the diagram

```sh
pip install playwright && python -m playwright install chromium
python docs/diagram/make_diagram.py      # writes docs/protocol_emulator_architecture.png
```

## Status and limits

All tests pass. Known limits are listed in the design reference; the main ones are the return
link bandwidth (full-size Ethernet frames overflow and are reported), 8-entry transmit packets,
and no I2C target mode yet. Still to do: the Tiny Tapeout wrapper and pin map, and a Quartus
compile (so far checked with Yosys and Verilator).

## Licence

Apache-2.0, see [LICENSE](LICENSE).

Paul Vincent Bezzina
