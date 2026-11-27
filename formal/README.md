# Formal proofs

Formal verification proves a property holds for every possible input sequence, not just the ones a
test happens to try. Each proof here wraps one RTL module, unchanged, in a harness that adds a
small reference model and assertions, then runs [SymbiYosys](https://github.com/YosysHQ/sby) (SBY).
Where possible the reference is written from the ISA, not from the RTL, so a disagreement between
the two fails the proof. The verification report (`docs/verification_report.pdf`) explains the
method and how far each proof can be trusted.

| Module | What is proved | Engine |
| --- | --- | --- |
| `host_fifo` | Occupancy never exceeds the depth; `full` and `empty` are exact; flush empties it; any value written comes out unchanged and in order | `abc pdr` |
| `frame_buffer` | Same as above, plus commit and rollback: rollback discards exactly the uncommitted entries, committed entries survive, and reads only ever see committed entries | `abc pdr` |
| `uart_tx` | Every frame is a start bit, 8 data bits LSB first, and a stop bit, each held for exactly the `clk_ratio` taken when the frame started, for every ratio from 1 to 15, with `clk_ratio` free to change on any clock (as `LINK` can); the line idles high and `tx_ready` is exact | `abc pdr` |
| `uart_rx` | Against a reference host sending `0x55` then any bytes with any gaps: locks to the exact ratio, never passes the `0x55` on, delivers every later byte once, unchanged, in order, with no frame error. With the pin free: one event at a time, never on consecutive clocks, nothing before lock, rate fixed once locked. Ratios 1 to 4 (task `wide`: 1 to 7) | `abc pdr` |
| `control_unit` | Against a second decoder written from the ISA: operand count of every opcode, `cfg_sel` and every field, START's alignment of VALUE, exactly one pulse per instruction on its own chain, DATA length and value, LINE, CLOCK, OUT and LINK kept until rewritten or cleared, `cmd_error` exactly when the ISA says, including the v0.7.2 length ranges (START CYC 0–8, HDR CYC 1–8, END LEN 1–16) | `abc pdr` |
| `return_path` | Every byte handed to the UART is the next byte of the accepted messages in the ISA's two-byte format; handshakes match a round-robin reference arbiter; no source waits behind more than two messages; every link event is reported exactly once. Task `line` also decodes `tx_serial` (bounded, 50 clocks) | `abc pdr`, BMC |
| `entry_dispatch` | With the real `frame_buffer`: every committed entry leaves exactly once, unchanged, in order, on the right port; one entry in flight, no idle clock while one waits; wire entries discarded only between a flush and the next status entry; `frame_mark` exactly once per status entry | `abc pdr` |
| `branch_unit` | The two BRANCH rules behave as the ISA describes: compare with mask and value, hit and miss actions, read-back mismatch and CRC-result sources, rule 0 before rule 1, each rule acts at most once per frame, `stall`, `hit`, `branch_abort` and `line_watch` timing | `abc pdr` |
| `crc_unit` | The 8-bit-per-clock update equals a bit-by-bit CRC of the configured width (1 to 16, any polynomial, any chunk of 1 to 8 bits), kept right aligned; `good` is exactly "register equals residue"; `crc_out` is the register top aligned, inverted when asked; feeding the register its own value top bit first always leaves zero; the configuration outputs match the last write | `abc pdr` |
| `line_codec` | Entry accounting against a reference count: `tx_done` is never pulsed without an outstanding entry, at most four are ever outstanding, and once idle for three clocks every accepted entry has had exactly one `tx_done`, including entries dropped by any pattern of cancels; with DRIVE 00 no output enable is set; open drain only pulls low; the clock output is only enabled when the codec generates the clock | `abc pdr` |
| `start_router` | Against the ISA's ordering rule: headers from 1, the first unconfigured one ends the list, headers outside the group skipped; with in-order success at most one running block waits, and MAIN starts exactly when all have succeeded | `abc pdr` |
| `first_counter` | START from the instruction's point of view: with VALUE aligned as the control unit does it, succeeds exactly when the last CYC bits on its pin equal VALUE in the chain's bit order; condition START; write START; reported value and push | `abc pdr` |
| `header_counter` | Bit-by-bit compare in the chain's order; `fail` on the first wrong bit and never otherwise; ANY returns the received field as a plain number; SEEK waits without failing; write headers push at once | `abc pdr` |
| `main_counter` | One symbolic bit followed end to end. Reading: every bit taken comes back once, in place, in entries of 8 with a short last one, and the frame completes on the BITS-th bit. Writing: host-entry bits leave in order, split at frame ends, BITS per frame. Every entry is zero above its length. A branch abort keeps the finished byte still waiting. BITS 1 to 65535 | k-induction |
| `end_counter` | Succeeds on exactly the tick where the last LEN bits equal PATTERN in the chain's order, not before LEN bits; LEN above 16 behaves as 16 | `abc pdr` |
| `watchdog` | Fires exactly WDOG quiet clocks after the last activity or timeout, repeats while stalled, never with a limit of 0. Full 16-bit range | k-induction |

Every job also has a `cover` task that shows the interesting cases are reachable (the FIFO fills,
a byte arrives at the smallest ratio, a source waits behind two messages, a tracked bit is the last
of a short byte), so a proof cannot pass because its assumptions left nothing to check.

## Helper invariants and peeks

`watchdog` and `main_counter` count to 65,535, which PDR does not get through in reasonable time.
Their harnesses add helper invariants that tie the module's internal registers to the reference
(read with `connect -set` after `flatten` in the `.sby`, since Yosys cannot read hierarchical
names), and k-induction then closes in a few steps. A helper invariant is proved like any other
assertion, so it cannot make a proof pass that should fail. They sit inside `` `ifndef MUTATION ``
so that mutation testing only counts faults caught by the spec properties.

`return_path` also uses `connect` to read the byte stream between `return_path` and its `uart_tx`:
there the spec is written against that interface, and `uart_tx_formal` proves the rest.

## Assumptions

Each `assume` is a promise about the module's surroundings, and each is discharged by another proof
or by a rule the ISA puts on the host. For example, `control_unit` assumes bytes never arrive on two
consecutive clocks, which `uart_rx` proves; `first_counter` assumes VALUE is aligned as the control
unit aligns it, which `control_unit` proves. The full table is in the verification report.

## Mutation testing

`scripts/mutate.py` plants small faults (a stuck, inverted or swapped bit on a cell) in the module
under each proof, one at a time, with Yosys's `mutate` pass. Each fault is killed (the proof fails),
equivalent (proved to change nothing at the outputs), or a gap (it changes behaviour and the proof
still passes). The score per proof is in the verification report.

```sh
python3 scripts/mutate.py                 # every proof, 16 faults each (takes hours)
python3 scripts/mutate.py header_counter  # one proof; results in build/mutate/header_counter/
```

## Size

The proofs use small parameters (4-entry buffers, 4-bit UART ratios). The logic does not depend on
the size, so this covers the same behaviour as the chip's 16-entry buffers. The counters in the
frame chain are proved at the chip's own widths.

## Running

Install the [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) (it includes Yosys,
SBY, yices and ABC), then:

```sh
bash scripts/formal.sh                  # every proof, prove and cover tasks, a few minutes
FORMAL_DEEP=1 bash scripts/formal.sh    # also uart_rx wide and return_path line, about 20 minutes more
cd formal && sby -f uart_tx.sby         # one proof, all its tasks; results in formal/uart_tx_prove/ and uart_tx_cover/
```

A failing proof writes a counterexample waveform, `formal/<name>_prove/engine_0/trace.vcd`, which
opens in GTKWave or Surfer. The `formal` GitHub workflow runs every proof on each push and keeps the
results as an artifact.

## Not yet covered

The integration of the frame chain, the channel and the chip core (covered by the pin-level suite,
sigrok and coverage instead), and the line codec's bit-level timing (covered by every standards
test at the pins). See the verification report for the full list.
