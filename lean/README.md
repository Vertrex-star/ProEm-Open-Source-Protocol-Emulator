# ProEm Lean proofs

Machine-checked proofs, in Lean 4, of four properties ProEm's design depends on. They hold for **every size**, not
only the sizes in the chip: any CRC width and polynomial, any number of arbiter sources, any frame length, any number of
frame blocks.

The SymbiYosys proofs in `formal/` and these proofs do different jobs. The SBY proofs show the RTL behaves like a
small reference model, at the sizes the chip has. The Lean proofs show that the reference model itself has the property
we actually want, at every size. Together they close the gap where a harness could faithfully check the wrong thing.

## Building

Lean core only, no Mathlib, so it builds in under a minute:

```
cd lean
lake build
```

`elan` installs the toolchain named in `lean-toolchain` (Lean 4.36.0) on first use. A successful build means every
theorem is checked. Nothing uses `sorry`: every main theorem depends only on Lean's three standard axioms (`propext`,
`Quot.sound`, `Classical.choice`), which `#print axioms` confirms.

## What is proved

| File | Main theorem | In plain words | RTL link |
|---|---|---|---|
| `ProEm/Crc.lean` | `detects_single_bit_error` | For every width w ≥ 1, every polynomial with its constant term set, every start value and every message, flipping any one bit changes the CRC. | `crc_unit_formal` proves the RTL steps exactly this register (widths 1 to 16). |
| | `feed_xor`, `residue_zero` | The CRC is linear in (start value, message), and a message followed by its own CRC, MSB first, leaves the register at zero. | Basis of the check (`good`) and append paths. |
| `ProEm/RoundRobin.lean` | `fair`, `fair_three` | With n sources and a pointer that moves just past each grant, a source that keeps asking is served within n − 1 grants to others; for ProEm's 3 (A, B, link flags) that is at most 2. | `return_path_formal` proves the 2-others bound on the RTL. |
| `ProEm/Bits.lean` | `decode_entries`, `entries_wellformed` | A frame of any length, split into host entries of up to 8 bits and sent as plain numbers MSB or LSB first, decodes back to exactly the bits on the line. Every entry is 1–8 bits and its value fits. | `main_counter_formal` proves MAIN produces these entries. |
| | `write_frames`, `write_frames_full` | Splitting the host's bit stream into frames of BITS bits drops and repeats nothing; every frame but the last is exactly BITS long. | MAIN writing. |
| `ProEm/Router.lean` | `enable_iff`, `main_iff`, `nothing_after_end`, `one_waiting` | For any number of blocks: a block starts exactly when every running block before it has succeeded, MAIN starts when all have, nothing after the first unconfigured header ever starts, and only one block is waiting at a time. | The model is a line-for-line transcription of `start_router.sv`; `start_router_formal` checks the RTL at 7 blocks. |

## Limits

- The link from RTL to these models is the SBY proofs plus, for the router, reading the code side by side. Lean does
  not read SystemVerilog.
- The CRC theorem covers single-bit errors. Burst and multi-bit guarantees depend on the polynomial chosen and are not
  proved here.
- `one_waiting` and the router theorems assume only switched-on blocks can succeed (`SuccessNeedsEnable`), which each
  block's own SBY proof establishes.
