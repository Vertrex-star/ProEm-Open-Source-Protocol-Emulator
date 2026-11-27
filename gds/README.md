# ProEm layout (GDS) and results

This folder holds the layout of ProEm and the numbers behind it: how much space it takes, how it
relates to the Jane Street protocol emulator challenge, and its power and performance.

| File | What it is |
| --- | --- |
| `tt_um_vertrex_star_proem.gds` | The layout (GDSII); open it in [KLayout](https://www.klayout.de/build.html) |
| `tt_um_vertrex_star_proem.lef` | The block's outline and pin positions |
| `images/` | Pictures of the layout (see [Images of the chip](#images-of-the-chip)) |

## Current state: 8 x 4 tiles, ISA v0.7.2

From v0.7.2 (26 November 2026) the project is set to **8 x 4 tiles** in `info.yaml`. The layout is
built by the `gds` GitHub workflow on every push, with the Tiny Tapeout CMOS5L flow (template
branch `cmos5l`, LibreLane 3.1.0.dev3, IHP-Open-PDK `2bbec755`) on IHP SG13CMOS5L 130 nm at
50 MHz. To update this folder after a green run:

1. Open the `gds` run on GitHub and download its `tt_submission` artifact.
2. Copy `tt_um_vertrex_star_proem.gds` and `tt_um_vertrex_star_proem.lef` from its `tt_submission/`
   folder into this folder, replacing the 6 x 4 files of v0.7.1.
3. Fill in the place-and-route figures below from the `GDS_logs` artifact
   (`runs/wokwi/final/metrics.json`): cells, utilisation, slack at each corner, power.
4. Replace `images/layout_full.png` with the `gds_render` artifact's picture.

The design is ISA v0.7.2: v0.7.1 plus the five corrections from the second verification round
(range checks on START, HDR and END lengths, a LINK divider taken per byte, auto-baud from 1
clock per bit, abort winning over complete, and a branch abort keeping MAIN's last finished byte).
The chip has not been fabricated yet.

| | 8 x 4, v0.7.2 | 6 x 4, v0.7.1 (14 October, last routed layout) |
| --- | --- | --- |
| Top module | `tt_um_vertrex_star_proem` | same |
| Process | IHP SG13CMOS5L 130 nm (Metal1 to Metal4 plus TopMetal1) | same |
| Die | 1724.16 x 710.64 um = 1,225,262 um² | 1289.28 x 710.64 um = 916,214 um² |
| Core (area available for cells) | 1,208,173 um² | 902,417 um² |
| Cells after synthesis | 19,003 (301,423 um², LibreLane synthesis of v0.7.2) | 18,969 |
| Cells after place and route | from the `gds` run | 25,612, not counting fill |
| Utilisation | about 32 % expected | 43 % |
| Clock | 50 MHz; timing from the `gds` run | 50 MHz; met at every corner (3.8 ns to spare at the slow corner) |
| Power | from the `gds` run; expected close to 10 mW | about 10.2 mW |
| Checks | the `gds`, `precheck` and `gl_test` jobs | Magic DRC 0 errors, LVS clean, precheck passed locally |

The 8 x 4 die gives the same logic a third more area, so placement and routing are easier and the
slow-corner margin should not shrink. The v0.7.2 changes add 34 cells after synthesis.

Where the cell area went in the 6 x 4 layout of v0.7.1, as a guide to the 8 x 4 one:

| Cell class | Count | Area (um²) | Share |
| --- | ---: | ---: | ---: |
| Flip-flops | 2,763 | 135,356 | 35 % |
| Combinational logic | 15,323 | 158,486 | 41 % |
| Timing repair buffers (most of them fix hold time) | 6,104 | 78,850 | 20 % |
| Clock tree | 362 | 6,984 | 2 % |
| Inverters, buffers, antenna diodes | 1,060 | 5,810 | 2 % |
| **Total** | **25,612** | **385,486** | **100 %** |

## Jane Street challenge

The [Jane Street protocol emulator ASIC competition](https://blog.janestreet.com/protocol-emulator-asic-competition/)
(announced 10 September 2026; deadline 18 January 2027) asks for a chip that can speak real
protocols, built on IHP's CMOS5L process through Tiny Tapeout. The challenge originally set the
size at 6 x 4 tiles; the updated rules allow 8 x 4, which is the size ProEm uses from v0.7.2.
Entries start from the CMOS5L template, and the Tiny Tapeout GitHub Actions
build the GDS and run the precheck; a submission needs a passing GDS build.

| Challenge point | ProEm today |
| --- | --- |
| Required: UART, SPI, I2C | All three; SPI as controller and target; I2C as controller (with clock stretching) and as target |
| Stretch: low-speed USB | Receive and transmit, with bit stuffing and end of packet |
| Stretch: 10 Mbit Ethernet | Receive (Manchester decoded on chip); transmit needs a 40 or 60 MHz clock |
| Extra | PS/2; SWD-style acknowledge handling; CAN-style arbitration; two channels at once; auto-baud host link |
| Programmability | Frames described in instruction bytes, plus `BRANCH` rules that change a frame's direction or abort it from a received field or a read-back mismatch |
| Area | 8 x 4 tiles, as the updated rules allow; about 32 % expected utilisation (v0.7.1 fitted the original 6 x 4 at 43 %) |
| Process: CMOS5L | Built on the CMOS5L template; the `gds` workflow uses the same flow |
| Full RTL to GDS with timing closure | v0.7.1 at 6 x 4: done, met at every corner. v0.7.2 at 8 x 4: from the `gds` workflow |
| Verification | Pin-level tests for every standard, including 16 more in `t_standards`; 1,800 random programs; 600 random branch programs; cocotb on RTL and gate level; a second simulator (Verilator) with 98 % line coverage; sigrok decoding of the standards waveforms; sixteen formal proofs covering every block, with mutation testing of each |

How it differs from the brief: the brief describes a tiny CPU running firmware. ProEm lets the
host describe a frame (START, headers, MAIN, END), does line coding (NRZI, Manchester, bit
stuffing, I2C conditions) in hardware, and reacts within a frame through two branch rules per
channel. Every bit has exact timing and both channels run in parallel.

Jane Street pay to fabricate the winning designs, so the entry does not need a paid Tiny
Tapeout submission.

## Power

Estimated by OpenROAD on the routed 6 x 4 layout of v0.7.1, with extracted wiring, at 50 MHz. The
8 x 4 layout has the same flip-flops and clock tree size, so it should be close; the `gds` run
gives the new figure.

| Corner | Flip-flops | Logic | Clock tree | Total |
| --- | ---: | ---: | ---: | ---: |
| Typical: 1.20 V, 25 °C | 7.37 mW | 0.35 mW | 2.48 mW | **10.2 mW** |
| Slow: 1.08 V, 125 °C | 5.87 mW | 0.28 mW | 1.92 mW | 8.1 mW |
| Fast: 1.32 V, -40 °C | 8.99 mW | 0.45 mW | 3.24 mW | 12.7 mW |

* About 8.5 mA from the 1.2 V core supply; leakage is about 0.04 mW.
* About 96 % of the power is the clock reaching the flip-flops; the logic itself uses about 4 %.
  Idle and busy power are therefore nearly the same.
* This is a vectorless estimate (default switching rates).

## Performance

Timing after routing of the 6 x 4 layout of v0.7.1, at a 50 MHz (20 ns) clock. The `gds` run
gives the 8 x 4 figures.

| Corner | Setup slack | Hold slack | Maximum clock |
| --- | ---: | ---: | ---: |
| Typical: 1.20 V, 25 °C | 9.8 ns | 0.29 ns | 98 MHz |
| Slow: 1.08 V, 125 °C | 3.8 ns | 0.61 ns | 62 MHz |
| Fast: 1.32 V, -40 °C | 12.4 ns | 0.10 ns | 131 MHz |

The CMOS5L flow only enforces the typical corner. Details of how the slow corner was closed are in
[docs/verification_report.pdf](../docs/verification_report.pdf).

Protocol speeds at 50 MHz:

| Standard | Speed |
| --- | --- |
| UART | Any common baud rate, up to a few Mbaud |
| SPI controller | SCK = 50 MHz / (2 x DIV); tested to 6.25 MHz |
| I2C controller | Tested from 1 MHz to 6.25 MHz SCL; covers 100 kHz, 400 kHz and 1 MHz modes |
| I2C target | Tested at 417 kHz and 1 MHz SCL |
| USB low speed | 1.5 Mbit/s |
| 10BASE-T | 10 Mbit/s receive |
| PS/2 | Full speed |
| CAN-style arbitration | Tested at 1 Mbit/s; needs at least 8 clocks per bit |

Host links: instructions in at any rate from 1 clock per bit (v0.7.2) up; results out at up to
12.5 Mbaud (`LINK` 4), which is about 5 Mbit/s of returned data. `DATA` can stream while a frame
runs; a fixed-timing line keeps up when each entry lasts longer on the line than its time on the
instruction link. Pad and pin multiplexer speed limits for the shuttle have not been checked.

## Checks

| Check | v0.7.2, 8 x 4 | v0.7.1, 6 x 4 |
| --- | --- | --- |
| Verilator lint (`-Wall`) | Clean, with reviewed waivers | Clean |
| Pin-level suite (CXXRTL) | All pass, plus auto-baud at 1 clock per bit and the new `cmd_error` range checks | All pass |
| Formal proofs (SymbiYosys) | Sixteen, all proven; mutation testing in the verification report | Six |
| Detailed routing, antenna, DRC, LVS, timing | the `gds` and `precheck` jobs | 0 violations; DRC 0 errors; LVS clean; timing met at every corner |
| cocotb, gate level | the `gl_test` job | 6 of 6 passed |

## Images of the chip

The pictures in `images/` are of the 6 x 4 layout of v0.7.1. Replace them from the 8 x 4 run: the
`gds_render` artifact is a picture of the whole block, the `viewer` job publishes a 3D view, and
KLayout can export close-ups of the new GDS once it is in this folder.

### Whole block (v0.7.1, 6 x 4)

![Whole layout of v0.7.1, 6 x 4 tiles](images/layout_full.png)

1289 x 711 um. Red is the lowest routing metal; yellow and green are the upper routing layers;
the regular green vertical stripes are the power straps.

### Close-up

![Close-up of standard cells](images/layout_closeup.png)

About 40 x 22 um: rows of standard cells (3.78 um tall) with their internal wiring and the
routing above them.

### Tiny Tapeout style

![Layout rendered in the Tiny Tapeout style](images/layout_tinytapeout_style.jpg)

The same layout rendered the way the Tiny Tapeout website shows projects.

## Viewing the GDS

1. Install KLayout from <https://www.klayout.de/build.html>.
2. File, Open, and choose `tt_um_vertrex_star_proem.gds`.
3. For IHP layer names and colours: File, Load Layer Properties, and choose `sg13cmos5l.lyp` from
   `ihp-sg13cmos5l/libs.tech/klayout/tech/` in the
   [IHP Open PDK](https://github.com/IHP-GmbH/IHP-Open-PDK).
4. Press `*` to show the inside of every cell.
