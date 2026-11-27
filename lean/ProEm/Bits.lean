/-
ProEm - Open Source Protocol Emulator
File: lean/ProEm/Bits.lean
Description: MAIN's data format, proved for every frame length: a frame's bits split into host entries of up to 8 bits
and sent as plain numbers (MSB first or LSB first) decode back to exactly the bits on the line, and splitting a host bit
stream into frames of BITS bits loses and repeats nothing. main_counter_formal proves the RTL produces these entries.
-/

namespace ProEm.Bits

/-! ## Splitting a bit stream into pieces -/

/-- Split l into pieces of n (the last may be shorter). MAIN reading: n = 8, one host entry per piece. MAIN writing:
n = BITS, one frame per piece. -/
def chunk (n : Nat) (hn : 0 < n) : List α → List (List α)
  | [] => []
  | x :: xs =>
      have : ((x :: xs).drop n).length < (x :: xs).length := by
        simp only [List.length_drop, List.length_cons]; omega
      (x :: xs).take n :: chunk n hn ((x :: xs).drop n)
termination_by l => l.length

/-- Nothing is lost, repeated or reordered: the pieces put back together are the original stream. -/
theorem flatten_chunk (n : Nat) (hn : 0 < n) : ∀ (l : List α), (chunk n hn l).flatten = l
  | [] => by simp [chunk]
  | x :: xs => by
      rw [chunk, List.flatten_cons, flatten_chunk n hn ((x :: xs).drop n), List.take_append_drop]
termination_by l => l.length
decreasing_by simp only [List.length_drop, List.length_cons]; omega

/-- Every piece has between 1 and n elements. -/
theorem chunk_length_bounds (n : Nat) (hn : 0 < n) :
    ∀ (l : List α) (c : List α), c ∈ chunk n hn l → 0 < c.length ∧ c.length ≤ n
  | [], c, h => by simp [chunk] at h
  | x :: xs, c, h => by
      rw [chunk] at h
      rcases List.mem_cons.mp h with h | h
      · subst h; simp only [List.length_take, List.length_cons]; omega
      · exact chunk_length_bounds n hn ((x :: xs).drop n) c h
termination_by l => l.length
decreasing_by simp only [List.length_drop, List.length_cons]; omega

/-- Every piece except the last is full (exactly n elements). -/
theorem chunk_full_except_last (n : Nat) (hn : 0 < n) :
    ∀ (l : List α) (i : Nat) (hi : i + 1 < (chunk n hn l).length), ((chunk n hn l)[i]).length = n
  | [], i, hi => by simp [chunk] at hi
  | x :: xs, i, hi => by
      have hrest : (x :: xs).length > n ∨ (x :: xs).length ≤ n := by omega
      rcases hrest with hgt | hle
      · cases i with
        | zero => simp only [chunk, List.getElem_cons_zero, List.length_take]; omega
        | succ i =>
            simp only [chunk, List.getElem_cons_succ]
            apply chunk_full_except_last n hn ((x :: xs).drop n) i
            simpa [chunk] using hi
      · exfalso
        have hd : (x :: xs).drop n = [] := List.drop_eq_nil_of_le hle
        simp [chunk, hd, chunk] at hi
termination_by l => l.length
decreasing_by simp only [List.length_drop, List.length_cons]; omega

/-! ## Plain numbers, MSB first and LSB first -/

/-- The value of bits sent LSB first: the first bit is bit 0 (ProEm's "plain number" for LSB-first chains). -/
def valLsb : List Bool → Nat
  | [] => 0
  | b :: bs => b.toNat + 2 * valLsb bs

/-- The bits of v as a len-bit number, bit 0 first. -/
def bitsLsb : Nat → Nat → List Bool
  | 0, _ => []
  | n + 1, v => (v % 2 == 1) :: bitsLsb n (v / 2)

theorem bitsLsb_valLsb : ∀ (l : List Bool), bitsLsb l.length (valLsb l) = l
  | [] => rfl
  | b :: bs => by
      simp only [List.length_cons, valLsb, bitsLsb]
      have h1 : (b.toNat + 2 * valLsb bs) / 2 = valLsb bs := by cases b <;> simp <;> omega
      have h2 : ((b.toNat + 2 * valLsb bs) % 2 == 1) = b := by cases b <;> simp <;> omega
      rw [h1, h2, bitsLsb_valLsb bs]

theorem valLsb_lt : ∀ (l : List Bool), valLsb l < 2 ^ l.length
  | [] => by simp [valLsb]
  | b :: bs => by
      have := valLsb_lt bs
      simp only [valLsb, List.length_cons, Nat.pow_succ]
      cases b <;> simp <;> omega

/-- The value of bits sent MSB first: the first bit is the top bit (ProEm's "plain number" for MSB-first chains). That is
the LSB-first value of the bits in reverse. -/
def valMsb (l : List Bool) : Nat := valLsb l.reverse

/-- The bits of v as a len-bit number, top bit first. -/
def bitsMsb (n v : Nat) : List Bool := (bitsLsb n v).reverse

/-- MSB first is the usual "shift left and add" reading of a bit stream. -/
theorem valMsb_append (l : List Bool) (b : Bool) : valMsb (l ++ [b]) = b.toNat + 2 * valMsb l := by
  simp [valMsb, valLsb]

theorem bitsMsb_valMsb (l : List Bool) : bitsMsb l.length (valMsb l) = l := by
  unfold bitsMsb valMsb
  rw [← List.length_reverse, bitsLsb_valLsb, List.reverse_reverse]

theorem valMsb_lt (l : List Bool) : valMsb l < 2 ^ l.length := by
  unfold valMsb; rw [← List.length_reverse]; exact valLsb_lt _

/-! ## MAIN reading, end to end -/

/-- A host entry: its length (1 to 8) and its value as a plain number. -/
structure Entry where
  len : Nat
  value : Nat
deriving DecidableEq, Repr

/-- The entries MAIN sends for a frame read with bit order msb (true = MSB first). -/
def entries (msb : Bool) (frame : List Bool) : List Entry :=
  (chunk 8 (by decide) frame).map fun c => ⟨c.length, if msb then valMsb c else valLsb c⟩

/-- What the host gets back by decoding the entries. -/
def decode (msb : Bool) (es : List Entry) : List Bool :=
  (es.map fun e => if msb then bitsMsb e.len e.value else bitsLsb e.len e.value).flatten

/-- **Main theorem.** For any frame of any length and either bit order, decoding MAIN's host entries gives back exactly
the bits that were on the line. -/
theorem decode_entries (msb : Bool) (frame : List Bool) : decode msb (entries msb frame) = frame := by
  unfold decode entries
  rw [List.map_map]
  have : ∀ c ∈ chunk 8 (by decide) frame,
      ((fun e : Entry => if msb then bitsMsb e.len e.value else bitsLsb e.len e.value) ∘
        (fun c : List Bool => (⟨c.length, if msb then valMsb c else valLsb c⟩ : Entry))) c = c := by
    intro c _
    cases msb <;> simp [bitsMsb_valMsb, bitsLsb_valLsb]
  rw [List.map_congr_left this]
  simp [flatten_chunk]

/-- Every entry is 1 to 8 bits long, every entry but the frame's last is a full byte, and every value fits its length. -/
theorem entries_wellformed (msb : Bool) (frame : List Bool) :
    ∀ e ∈ entries msb frame, 0 < e.len ∧ e.len ≤ 8 ∧ e.value < 2 ^ e.len := by
  intro e he
  unfold entries at he
  obtain ⟨c, hc, rfl⟩ := List.mem_map.mp he
  have := chunk_length_bounds 8 (by decide) frame c hc
  refine ⟨this.1, this.2, ?_⟩
  cases msb <;> simp [valMsb_lt, valLsb_lt]

/-! ## MAIN writing: frames of BITS bits -/

/-- MAIN writing takes the host's entries as one bit stream and sends it in frames of BITS bits (BITS ≥ 1). The frames,
put back together, are exactly the host's bits: nothing is dropped at a frame end, nothing is sent twice. -/
theorem write_frames (bits : Nat) (hb : 0 < bits) (hostEntries : List (List Bool)) :
    (chunk bits hb hostEntries.flatten).flatten = hostEntries.flatten :=
  flatten_chunk bits hb _

/-- Every frame is exactly BITS bits, except possibly the last, which waits for more host data. -/
theorem write_frames_full (bits : Nat) (hb : 0 < bits) (stream : List Bool) (i : Nat)
    (hi : i + 1 < (chunk bits hb stream).length) : ((chunk bits hb stream)[i]).length = bits :=
  chunk_full_except_last bits hb stream i hi

/-! ## Checks on a concrete frame

These are evaluated when the file is checked (they are tests, not proofs): a 10-bit frame read MSB first comes back as
an 8-bit entry 0xB2 and a 2-bit entry 3, and decodes to the same 10 bits. -/

#guard entries true [true, false, true, true, false, false, true, false, true, true] == [⟨8, 0xB2⟩, ⟨2, 3⟩]
#guard decode true [⟨8, 0xB2⟩, ⟨2, 3⟩] == [true, false, true, true, false, false, true, false, true, true]
#guard entries false [true, false, true, true, false, false, true, false, true, true] == [⟨8, 0x4D⟩, ⟨2, 3⟩]

end ProEm.Bits
