# ProEm - Open Source Protocol Emulator

ProEm is an open-source protocol emulator ASIC: a chip that lets an RP2040 speak many serial protocols through one piece of
hardware. The RP2040 describes a frame in a few instruction bytes; the chip runs it at up to one
bit per clock, with exact timing, and sends back what it received plus a status for every frame.

Target: IHP SG13CMOS5L 130 nm through [Tiny Tapeout](https://tinytapeout.com) (6 × 4 tiles, as the Jane Street challenge sets), 50 MHz.
Top module for Tiny Tapeout: `tt_um_vertrex_star_proem`.
Built for the [Jane Street protocol emulator ASIC competition](https://blog.janestreet.com/protocol-emulator-asic-competition/).

![Architecture](docs/protocol_emulator_architecture.png)

## At a glance

| | |
| --- | --- |
| Channels | 2 independent channels, A and B, running at the same time |
| Host link | UART in with auto-baud, UART out at a rate set by `LINK` (down to 4 clocks per bit) |
| Verified at pin level | UART, SPI (controller and target), I2C controller and target, PS/2, 10BASE-T receive, Manchester transmit, USB low speed receive and transmit, SWD-style acknowledge handling, CAN-style arbitration |
| Reacting on chip | `BRANCH` rules change a frame's direction, or abort it, from a field just received or from the line not reading back what the chip drove |
| Long packets | `DATA` streams while a frame runs; fixed-timing lines report an underrun if the data runs out |
| Logic | 15,513 cells after synthesis, 19,737 after place and route (35 % of the 6 × 4 core area) |
| Timing | Closed after routing at all three corners on CMOS5L: 17.4 ns worst path at 1.08 V, 125 °C (20 ns budget) |
| Instruction set | ISA v0.5, see [docs/protocol_emulator_isa.pdf](docs/protocol_emulator_isa.pdf) |

## How it works

* **Host side.** A UART receiver with auto-baud feeds a control unit that decodes ISA
  instructions into registered configuration writes. A return path sends received data, a status
  per frame and link events back on a second UART.
* **Input pipeline.** Every input pin passes through two synchroniser flops and one register.
* **Two channels.** Each has a host FIFO for write data, a *frame chain* (START, up to six headers,
  MAIN, END, watchdog, frame buffer, and a *branch unit* with two rules), an entry dispatcher, and a
  *line codec*:
  * tick source: SYNC (clock pin edge), ASYNC / RECOVER (bit timer that re-centres on edges),
    GENERATE (drives SCK / SCL, with clock stretching);
  * decoder: NRZ, NRZI, NRZI on the USB pair, Manchester, bit unstuffing;
  * encoder: the same codes, stuff insertion, I2C START / Sr / STOP, USB end of packet,
    open drain, chip select;
  * I2C target support: START / STOP detection and SDA timing against an external SCL;
  * read-back check of the driven pad, for arbitration.

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

The chip is packaged as a Tiny Tapeout project on the CMOS5L template (the `cmos5l` branch of
Tiny Tapeout's IHP template), as the Jane Street challenge asks (`info.yaml`, `src/config.json`,
top module `tt_um_vertrex_star_proem`). Every push runs the `gds` workflow, which builds the
layout for IHP SG13CMOS5L with LibreLane, runs the Tiny Tapeout precheck and the cocotb test on
the gate-level netlist, and publishes a 3D viewer. A green `gds` run is what the challenge
needs for a submission.

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

Hardened locally with the same flow the `gds` workflow uses (template branch `cmos5l`,
LibreLane 3.1.0.dev3, IHP-Open-PDK at the commit the workflow installs), at the 6 × 4 tiles the
Jane Street challenge sets:

| | |
| --- | --- |
| Process | IHP SG13CMOS5L 130 nm |
| Tiles | 6 × 4, 1289.28 × 710.64 µm |
| Cells | 15,513 after synthesis; 19,737 after place and route, not counting fill (includes 3,266 hold buffers and 299 clock tree cells) |
| Utilisation | 35 % of the core area; the lower third of the die is free |
| Routing | 0 violations after detailed routing, 0 antenna violations |
| Sign-off checks | Magic DRC 0 errors, LVS clean, Tiny Tapeout precheck pin, boundary and layer checks passed (the full KLayout DRC runs in the `gds` workflow); cocotb gate-level tests 4 of 4 pass |
| Setup slack at 50 MHz | 8.9 ns typical, 2.6 ns slow (1.08 V, 125 °C), 12.5 ns fast |
| Hold slack | 0.28 ns typical, 0.61 ns slow, 0.11 ns fast |
| Maximum clock | 57 MHz at the slow corner, 90 MHz typical |
| Power | about 8.9 mW at 50 MHz (7.0 to 11.0 mW across corners) |

The CMOS5L flow only checks timing at the typical corner. With the template's default settings
the slow corner missed by 1.2 ns, so `src/config.json` limits signal transitions to 0.75 ns
(`MAX_TRANSITION_CONSTRAINT`) and gives the resizer more setup margin; every corner now passes.

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
LIBERTY=path/to/sg13cmos5l_stdcell_typ_1p20V_25C.lib bash scripts/run.sh             # area in IHP cells
LIBERTY=path/to/sg13cmos5l_stdcell_slow_1p08V_125C.lib bash scripts/sta.sh           # timing
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
| `t_i2c_target` | I2C target at 0x42: write, read (branch on R/W), wrong address, repeated START; SCL 417 kHz and 1 MHz |
| `t_branch` | SWD-style acknowledge (OK continues, WAIT and FAULT abort); CAN-style arbitration won and lost |
| `t_stream` | underrun abort; 12-byte UART and 20-byte SPI frames fed while running |
| `t_random_branch` | 600 random branch programs: capture-any header, random rules, actions and run modes |

## Regenerating the diagram

```sh
pip install playwright && python -m playwright install chromium
python docs/diagram/make_diagram.py      # writes docs/protocol_emulator_architecture.png
```

## Status and limits

All tests pass, and the design places, routes and meets timing on 6 × 4 Tiny Tapeout tiles on
the CMOS5L template.
Known limits are listed in the design reference; the main ones are the return link bandwidth
(full-size Ethernet frames overflow and are reported), the instruction link rate when feeding
fast fixed-timing lines, and no CRC generation on chip. Still to do: formal proofs, and a Quartus compile (so far checked with Yosys,
Verilator and Icarus).

## Licence

Apache-2.0, see [LICENSE](LICENSE).

Paul Vincent Bezzina
