# ProEm - Open Source Protocol Emulator

ProEm is an open-source protocol emulator ASIC: a chip that lets an RP2040 speak many serial protocols through one piece of
hardware. The RP2040 describes a frame in a few instruction bytes; the chip runs it at up to one
bit per clock, with exact timing, and sends back what it received plus a status for every frame.

Target: IHP SG13G2 130 nm through [Tiny Tapeout](https://tinytapeout.com) (6 × 2 tiles), 50 MHz.
Top module for Tiny Tapeout: `tt_um_vertrex_star_proem`.
Built for the [Jane Street protocol emulator ASIC competition](https://blog.janestreet.com/protocol-emulator-asic-competition/).

![Architecture](docs/protocol_emulator_architecture.png)

## At a glance

| | |
| --- | --- |
| Channels | 2 independent channels, A and B, running at the same time |
| Host link | UART in with auto-baud, UART out at a rate set by `LINK` (down to 4 clocks per bit) |
| Verified at pin level | UART, SPI (controller and target), I2C controller, PS/2, 10BASE-T receive, Manchester transmit, USB low speed receive and transmit |
| Logic | 13,144 cells after synthesis, 17,135 after place and route (72 % of the 6 × 2 core area) |
| Timing | Closed after routing at all three corners: 14.1 ns worst path at 1.08 V, 125 °C (20 ns budget) |
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
info.yaml           Tiny Tapeout project file: title, tiles, source list, pin names
src/
  top/              tt_um_vertrex_star_proem.sv  Tiny Tapeout top level (pin map)
                    protocol_emulator.sv         chip core
                    protocol_emulator_inst.sv    instantiation template
  core/             emulator_channel, control_unit, line_codec, entry_dispatch, return_path
    frame_chain/    frame_chain and its blocks (START, headers, router, MAIN, END, watchdog)
  primitives/       uart_rx, uart_tx, host_fifo, frame_buffer
  files.f           file list in compile order
  config.json       LibreLane settings used by the Tiny Tapeout GDS flow
test/               cocotb test (tb.v, test.py), runs on RTL and on the gate-level netlist
sim/                pin-level test bench (bench.h) and one test per standard (t_*.cpp)
scripts/            run.sh (all tests + synthesis), sta.sh (timing check)
gds/                the layout (GDS, LEF), layout images and a results summary
docs/               design reference and ISA spec (PDF + LaTeX), architecture diagram,
                    info.md (Tiny Tapeout datasheet page), layout renders
  diagram/          diagram generator (make_diagram.py) and its fonts (SIL OFL)
.github/workflows/  gds (Tiny Tapeout GDS, precheck, gate-level test, viewer), test (cocotb),
                    docs (datasheet check), sim (every pin-level test)
```

Module hierarchy:

```
tt_um_vertrex_star_proem                   src/top
└── protocol_emulator                      src/top
    ├── uart_rx                            src/primitives
    ├── control_unit                       src/core
    ├── emulator_channel (A and B)         src/core
    │   ├── host_fifo                      src/primitives
    │   ├── line_codec                     src/core
    │   ├── frame_chain                    src/core/frame_chain
    │   │   ├── first_counter, header_counter (x6), start_router
    │   │   ├── main_counter, end_counter, watchdog
    │   │   └── frame_buffer               src/primitives
    │   └── entry_dispatch                 src/core
    └── return_path                        src/core
        └── uart_tx                        src/primitives
```

Every file starts with a header: file, module, type (top level, core RTL or primitive), place in
the hierarchy, submodules, author, and a description line.

## Tiny Tapeout

The chip is packaged as a Tiny Tapeout project for the IHP SG13G2 shuttle (`info.yaml`,
`src/config.json`, top module `tt_um_vertrex_star_proem`). Every push runs the `gds` workflow,
which builds the layout with LibreLane, runs the Tiny Tapeout precheck and the cocotb test on the
gate-level netlist, and publishes a 3D viewer.

### Pin map

| Pin | Direction | Use |
| --- | --- | --- |
| `ui[0]` | in | RX: instructions from the host (the first byte after reset must be `0x55`) |
| `ui[7:1]` | in | unused |
| `uo[0]` | out | TX: data and status to the host |
| `uo[1]` | out | BAUD_LOCKED |
| `uo[3:2]` | out | ARMED for channels B and A |
| `uo[5:4]` | out | HOST_FULL for channels B and A |
| `uo[7:6]` | out | SELECT (chip select) for channels B and A |
| `uio[0]`, `uio[1]`, `uio[2]` | in/out | pins 0 to 2, driven by channel A: data (TX, MOSI, SDA, D+), pair (D-), clock (SCK, SCL) |
| `uio[3]`, `uio[4]`, `uio[5]` | in/out | pins 3 to 5, driven by channel B, same order |
| `uio[7:6]` | in | pins 6 and 7 |

The `PIN` fields in the instructions count the `uio` pads, and every pad is read back, so open-drain
lines (I2C, USB) work on a single pad. A channel only drives its pads when `OUT` enables them.

### Layout

![Layout](docs/layout_full.png)

The GDS file, pictures of the layout and a summary of space, power, performance and the Jane Street
challenge are in [gds/](gds/README.md).

Hardened locally with the same flow the `gds` workflow uses (LibreLane 3.0.5, IHP PDK at the commit
the shuttle pins, `src/config.json` unchanged):

| | |
| --- | --- |
| Tiles | 6 × 2, 1289.28 × 313.74 µm |
| Cells | 13,144 after synthesis; 17,135 after place and route, not counting fill (includes 2,868 hold buffers and 257 clock tree cells) |
| Utilisation | 72 % of the core area |
| Routing | 0 violations after detailed routing, 0 antenna violations |
| Sign-off checks | Magic DRC 0 errors, LVS clean (netgen: circuits match uniquely), IHP KLayout DRC clean; Tiny Tapeout precheck passed (all 10 checks) |
| Setup slack at 50 MHz | 11.0 ns typical, 5.9 ns slow (1.08 V, 125 °C), 13.0 ns fast |
| Hold slack | 0.31 ns typical, 0.63 ns slow, 0.12 ns fast |
| Maximum clock | 71 MHz at the slow corner, 111 MHz typical |

4 × 2 tiles (268,000 µm²) is smaller than the cell area alone, so 6 × 2 is the smallest size that
fits. The GitHub run is the one that counts for submission.

### Running the cocotb test

```sh
pip install -r test/requirements.txt   # cocotb, pytest; also needs Icarus Verilog
cd test && make -B                     # RTL
make -B GATES=yes                      # gate level, after copying the netlist from the gds run
```

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

All tests pass, and the design places, routes and meets timing on 6 × 2 Tiny Tapeout tiles.
Known limits are listed in the design reference; the main ones are the return link bandwidth
(full-size Ethernet frames overflow and are reported), 8-entry transmit packets, and no I2C target
mode yet. Still to do: a Quartus compile (so far checked with Yosys, Verilator and Icarus).

## Licence

Apache-2.0, see [LICENSE](LICENSE).

Paul Vincent Bezzina
