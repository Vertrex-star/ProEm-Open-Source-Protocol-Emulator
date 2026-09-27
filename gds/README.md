# ProEm layout (GDS) and results

This folder holds the finished layout of ProEm and the numbers behind it: how much space it
takes, how it relates to the Jane Street protocol emulator challenge, and its power and
performance.

| File | What it is |
| --- | --- |
| `tt_um_vertrex_star_proem.gds` | The layout (GDSII); open it in [KLayout](https://www.klayout.de/build.html) |
| `tt_um_vertrex_star_proem.lef` | The block's outline and pin positions |
| `images/` | Pictures of the layout (see [Images of the chip](#images-of-the-chip)) |

The layout was built on 26 September 2026 with the Tiny Tapeout flow (LibreLane 3.0.5) on the
IHP SG13G2 130 nm process, 6 x 2 tiles, 50 MHz. It is a reference build: the Jane Street entry
will be rebuilt on their CMOS5L template at 6 x 4 tiles once they release it (see
[Jane Street challenge](#jane-street-challenge)). The chip has not been fabricated yet.

## Summary

| | |
| --- | --- |
| Top module | `tt_um_vertrex_star_proem` |
| Process | IHP SG13G2 130 nm (reference build) |
| Size | 6 x 2 Tiny Tapeout tiles; 1289.28 x 313.74 um |
| Logic | 13,144 cells after synthesis; 17,135 after place and route |
| Space used | 72 % of the core area |
| Clock | 50 MHz; timing met at every corner |
| Power | About 8 mW at 50 MHz |
| Checks | 0 routing errors; Magic and KLayout DRC clean; LVS clean; Tiny Tapeout precheck passed |

## Space

| | |
| --- | --- |
| Die | 1289.28 x 313.74 um = 404,500 um² |
| Core (area available for cells) | 392,988 um² |
| Standard cells after place and route | 282,716 um² |
| Utilisation | 72 % |
| Fill and decap cells | 15,195 |

Where the cell area goes:

| Cell class | Count | Area (um²) | Share |
| --- | ---: | ---: | ---: |
| Flip-flops | 2,206 | 108,069 | 38 % |
| Combinational logic | 10,327 | 108,006 | 38 % |
| Timing repair buffers (2,868 of them fix hold time) | 4,346 | 57,560 | 20 % |
| Clock tree | 257 | 5,596 | 2 % |
| Inverters, buffers, antenna diodes | 633 | 3,485 | 1 % |
| **Total** | **17,769** | **282,716** | **100 %** |

Main blocks (synthesis estimates):

| Block | Area (um²) |
| --- | ---: |
| One channel (frame chain, line codec, host FIFO, dispatcher) | 96,000 |
| Frame chain alone | 73,000 |
| Line codec | 14,400 |
| Control unit | 19,800 |
| UART receiver with auto-baud | 7,700 |
| Return path with UART transmitter | 5,300 |

6 x 2 is the smallest Tiny Tapeout size that fits: 4 x 2 tiles give about 260,000 um² of core,
which is less than the cells alone.

## Jane Street challenge

The [Jane Street protocol emulator ASIC competition](https://blog.janestreet.com/protocol-emulator-asic-competition/)
(announced 10 September 2026; deadline 18 January 2027) asks for a chip that can speak real
protocols, built on IHP's CMOS5L process through Tiny Tapeout at 6 x 4 tiles.

| Challenge point | ProEm today |
| --- | --- |
| Required: UART, SPI, I2C | All three; SPI as controller and target; I2C controller with clock stretching |
| Stretch: low-speed USB | Receive and transmit, with bit stuffing and end of packet |
| Stretch: 10 Mbit Ethernet | Receive (Manchester decoded on chip); transmit needs a 40 or 60 MHz clock |
| Extra | PS/2; two channels running at the same time; auto-baud host link |
| Area: 6 x 4 tiles maximum | Needs only 6 x 2; at 6 x 4 it would use about 30 to 35 % of the area |
| Process: CMOS5L | Same 84 standard cells as SG13G2, one fewer metal layer; no RTL change needed; rebuild once the template arrives |
| Full RTL to GDS with timing closure | Done on SG13G2 (this folder) |
| Verification | Pin-level tests for every standard; 1,800 random programs; cocotb on RTL and gate level |

How it differs from the brief: the brief describes a tiny CPU running firmware. ProEm instead
lets the host describe a frame (START, headers, MAIN, END) and does line coding (NRZI,
Manchester, bit stuffing, I2C conditions) in hardware; every bit has exact timing and both
channels run in parallel. Planned additions before the deadline:

* a branch unit, so a frame can change direction on a received bit; this adds I2C target mode,
  SWD and CAN arbitration for about 3 % more area;
* formal proofs (SymbiYosys) on the FIFOs, frame buffer and UART.

Jane Street pay to fabricate the winning designs, so the entry does not need a paid Tiny
Tapeout submission.

## Power

Estimated by OpenROAD on the routed layout with extracted wiring, at 50 MHz:

| Corner | Flip-flops | Logic | Clock tree | Total |
| --- | ---: | ---: | ---: | ---: |
| Typical: 1.20 V, 25 °C | 5.94 mW | 0.32 mW | 1.94 mW | **8.2 mW** |
| Slow: 1.08 V, 125 °C | 4.73 mW | 0.26 mW | 1.51 mW | 6.5 mW |
| Fast: 1.32 V, -40 °C | 7.24 mW | 0.41 mW | 2.49 mW | 10.1 mW |

* About 7 mA from the 1.2 V core supply; leakage is about 0.01 mW.
* 96 % of the power is the clock reaching the 2,206 flip-flops; the logic itself uses about 4 %.
  Idle and busy power are therefore nearly the same.
* Heat: well under 1 °C of self-heating in a normal package; no cooling concerns.
* Power grid: worst voltage drop 0.35 mV on VPWR and 0.65 mV on VGND; 0 violations.
* This is a vectorless estimate (default switching rates). A vector-based estimate from the
  gate-level tests, or a current measurement on the real chip, would refine it.

## Performance

Timing after routing, with extracted wiring, at a 50 MHz (20 ns) clock:

| Corner | Setup slack | Hold slack | Maximum clock |
| --- | ---: | ---: | ---: |
| Typical: 1.20 V, 25 °C | 11.0 ns | 0.31 ns | 111 MHz |
| Slow: 1.08 V, 125 °C | 5.9 ns | 0.63 ns | 71 MHz |
| Fast: 1.32 V, -40 °C | 13.0 ns | 0.12 ns | 167 MHz |

0 setup, hold, slew and capacitance violations at every corner.

Protocol speeds at 50 MHz:

| Standard | Speed |
| --- | --- |
| UART | Any common baud rate, up to a few Mbaud |
| SPI controller | SCK = 50 MHz / (2 x DIV); tested to 6.25 MHz |
| I2C controller | Tested from 1 MHz to 6.25 MHz SCL; covers 100 kHz, 400 kHz and 1 MHz modes |
| USB low speed | 1.5 Mbit/s |
| 10BASE-T | 10 Mbit/s receive |
| PS/2 | Full speed |

Host links: instructions in at up to about 7 Mbaud; results out at up to 12.5 Mbaud, which is
about 5 Mbit/s of returned data. The return link, not the logic, is the limit: full-size
Ethernet frames arrive faster than they can be returned and are reported as overflow. Pad and
pin multiplexer speed limits for the shuttle have not been checked.

## Checks

| Check | Result |
| --- | --- |
| Verilator lint | 0 errors |
| Detailed routing | 0 violations |
| Antenna | 0 violations |
| Magic DRC | 0 errors |
| IHP KLayout DRC | 0 errors |
| LVS (Netgen) | Circuits match |
| Tiny Tapeout precheck | 10 of 10 passed |
| cocotb, gate level | 3 of 3 passed |

## Images of the chip

These are pictures of the finished layout that would be sent for fabrication; the chip itself
has not been made yet.

### Whole block

![Whole layout, 6 x 2 tiles](images/layout_full.png)

1289 x 314 um. Red and blue are the lower metal layers inside and between the cells; yellow and
green are the upper routing layers; the regular vertical stripes are the power straps. The
lighter strip on the right is unused space filled with filler cells.

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
3. For IHP layer names and colours: File, Load Layer Properties, and choose `sg13g2.lyp` from
   `ihp-sg13g2/libs.tech/klayout/tech/` in the
   [IHP Open PDK](https://github.com/IHP-GmbH/IHP-Open-PDK).
4. Press `*` to show the inside of every cell.
