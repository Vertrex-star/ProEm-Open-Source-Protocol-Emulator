/-
ProEm - Open Source Protocol Emulator
File: lean/ProEm/Crc.lean
Description: The CRC register of crc_unit, as stepped by the reference model in formal/crc_unit_formal.sv, proved for every
width and every polynomial: it is linear, a message followed by its own CRC leaves the register at zero, and with a
polynomial that has its constant term it detects every single-bit error.
-/

namespace ProEm.Crc

variable {w : Nat}

/-- The polynomial term added on a step: the polynomial when the feedback bit is 1, zero otherwise. -/
def sel (c : Bool) (poly : BitVec w) : BitVec w := if c then poly else 0#w

/-- One bit into the CRC register: the reference model's step. The feedback is the register's top bit XOR the new bit;
the register shifts left (dropping its top bit, which is the reference model's mask) and takes the polynomial if the
feedback is 1. -/
def step (poly : BitVec w) (r : BitVec w) (b : Bool) : BitVec w :=
  (r <<< 1) ^^^ sel (r.msb ^^ b) poly

/-- A list of bits fed one after another, first bit first. crc_unit feeds up to 8 of these per clock;
crc_unit_formal proves that the RTL's 8-bit-per-clock update equals this, at every width from 1 to 16. -/
def feed (poly : BitVec w) (r : BitVec w) (bits : List Bool) : BitVec w :=
  bits.foldl (step poly) r

theorem getLsbD_sel (c : Bool) (poly : BitVec w) (i : Nat) :
    (sel c poly).getLsbD i = (c && poly.getLsbD i) := by
  cases c <;> simp [sel]

@[simp] theorem feed_nil (poly r : BitVec w) : feed poly r [] = r := rfl

@[simp] theorem feed_cons (poly r : BitVec w) (b : Bool) (bs : List Bool) :
    feed poly r (b :: bs) = feed poly (step poly r b) bs := rfl

theorem feed_append (poly r : BitVec w) (xs ys : List Bool) :
    feed poly r (xs ++ ys) = feed poly (feed poly r xs) ys := by
  simp [feed, List.foldl_append]

/-! ## Linearity -/

theorem msb_xor' (a c : BitVec w) : (a ^^^ c).msb = (a.msb ^^ c.msb) := by
  simp [BitVec.msb_eq_getLsbD_last, BitVec.getLsbD_xor]

/-- One step is linear in the register and the input bit together. -/
theorem step_xor (poly a c : BitVec w) (x y : Bool) :
    step poly (a ^^^ c) (x ^^ y) = step poly a x ^^^ step poly c y := by
  apply BitVec.eq_of_getLsbD_eq
  intro i _
  simp only [step, BitVec.getLsbD_xor, BitVec.getLsbD_shiftLeft, getLsbD_sel, msb_xor']
  cases a.msb <;> cases c.msb <;> cases x <;> cases y <;>
    cases (decide (i < w)) <;> cases (decide (i < 1)) <;>
    cases a.getLsbD (i - 1) <;> cases c.getLsbD (i - 1) <;> cases poly.getLsbD i <;> rfl

/-- Feeding is linear: the CRC of the XOR of two equal-length inputs, from the XOR of two starting registers, is the XOR
of their CRCs. -/
theorem feed_xor (poly : BitVec w) :
    ∀ (a c : BitVec w) (xs ys : List Bool), xs.length = ys.length →
      feed poly (a ^^^ c) (List.zipWith (· ^^ ·) xs ys) = feed poly a xs ^^^ feed poly c ys
  | a, c, [], [], _ => by simp [feed]
  | a, c, x :: xs, y :: ys, h => by
      simp only [List.zipWith_cons_cons, feed_cons]
      rw [step_xor]
      exact feed_xor poly _ _ xs ys (by simpa using h)
  | _, _, [], _ :: _, h => by simp at h
  | _, _, _ :: _, [], h => by simp at h

/-! ## A message followed by its own CRC leaves zero -/

/-- The register's top n bits, top bit first: what crc_unit appends to a frame (crc_out, top aligned, sent MSB first). -/
def msbBits : Nat → BitVec w → List Bool
  | 0, _ => []
  | n + 1, r => r.msb :: msbBits n (r <<< 1)

theorem length_msbBits (n : Nat) (r : BitVec w) : (msbBits n r).length = n := by
  induction n generalizing r with
  | zero => rfl
  | succ n ih => simp [msbBits, ih]

/-- Feeding the register its own top bit cancels the feedback, so the register just shifts. -/
theorem step_msb (poly r : BitVec w) : step poly r r.msb = r <<< 1 := by
  simp [step, sel]

theorem feed_msbBits (poly : BitVec w) (n : Nat) (r : BitVec w) :
    feed poly r (msbBits n r) = r <<< n := by
  induction n generalizing r with
  | zero => simp [msbBits, feed]
  | succ n ih =>
      simp only [msbBits, feed_cons, step_msb, ih]
      rw [← BitVec.shiftLeft_add, Nat.add_comm]

/-- For every width and every polynomial: after any message, feeding the register's own value top bit first leaves the
register at zero. This is why a frame with ProEm's appended CRC checks to a zero residue (with inversion off). -/
theorem residue_zero (poly r : BitVec w) : feed poly r (msbBits w r) = 0#w := by
  rw [feed_msbBits]
  exact BitVec.shiftLeft_eq_zero (Nat.le_refl w)

/-! ## Every single-bit error is detected -/

theorem step_zero_false (poly : BitVec w) : step poly 0#w false = 0#w := by
  apply BitVec.eq_of_getLsbD_eq
  intro i _
  simp [step, sel]

theorem feed_zero_zeros (poly : BitVec w) (k : Nat) : feed poly 0#w (List.replicate k false) = 0#w := by
  induction k with
  | zero => rfl
  | succ k ih => simp [List.replicate_succ, step_zero_false, ih]

theorem step_zero_true (poly : BitVec w) : step poly 0#w true = poly := by
  apply BitVec.eq_of_getLsbD_eq
  intro i _
  simp [step, sel]

/-- With the polynomial's constant term set, a non-zero register never becomes zero on a 0 input bit. -/
theorem step_false_ne_zero (poly r : BitVec w) (hw : 0 < w) (hp : poly.getLsbD 0 = true) (hr : r ≠ 0#w) :
    step poly r false ≠ 0#w := by
  intro h
  have hbit : ∀ i, i < w → (step poly r false).getLsbD i = false := by
    intro i _; rw [h]; simp
  cases hm : r.msb with
  | true =>
      have := hbit 0 hw
      simp [step, sel, hm, BitVec.getLsbD_xor, BitVec.getLsbD_shiftLeft, hp] at this
  | false =>
      apply hr
      apply BitVec.eq_of_getLsbD_eq
      intro i hi
      simp only [BitVec.getLsbD_zero]
      by_cases htop : i = w - 1
      · rw [BitVec.msb_eq_getLsbD_last] at hm; subst htop; exact hm
      · have h1 := hbit (i + 1) (by omega)
        simp [step, sel, hm, BitVec.getLsbD_shiftLeft] at h1
        have : i + 1 < w := by omega
        simpa [this] using h1

theorem feed_zeros_ne_zero (poly : BitVec w) (hw : 0 < w) (hp : poly.getLsbD 0 = true) :
    ∀ (k : Nat) (r : BitVec w), r ≠ 0#w → feed poly r (List.replicate k false) ≠ 0#w
  | 0, r, hr => hr
  | k + 1, r, hr => by
      simp only [List.replicate_succ, feed_cons]
      exact feed_zeros_ne_zero poly hw hp k _ (step_false_ne_zero poly r hw hp hr)

/-- The pattern with a single 1 at position j, among n bits. -/
def single (n j : Nat) : List Bool := List.replicate j false ++ true :: List.replicate (n - j - 1) false

theorem length_single (n j : Nat) (hj : j < n) : (single n j).length = n := by
  simp [single]; omega

theorem single_zero (n : Nat) : single (n + 1) 0 = true :: List.replicate n false := by
  simp [single]

theorem single_succ (n j : Nat) : single (n + 1) (j + 1) = false :: single n j := by
  simp only [single, List.replicate_succ, List.cons_append]
  have : n + 1 - (j + 1) - 1 = n - j - 1 := by omega
  rw [this]

theorem zipWith_xor_false (l : List Bool) :
    List.zipWith (· ^^ ·) l (List.replicate l.length false) = l := by
  induction l with
  | nil => rfl
  | cons x xs ih => simp [List.replicate_succ, ih]

/-- Flipping bit j of a message is the same as XORing it with the single-1 pattern. -/
theorem set_eq_zipWith (m : List Bool) (j : Nat) (hj : j < m.length) :
    m.set j (!m[j]) = List.zipWith (· ^^ ·) m (single m.length j) := by
  induction m generalizing j with
  | nil => simp at hj
  | cons x xs ih =>
      cases j with
      | zero =>
          rw [List.length_cons, single_zero, List.zipWith_cons_cons, zipWith_xor_false]
          simp
      | succ j =>
          have hj' : j < xs.length := by simpa using hj
          rw [List.length_cons, single_succ, List.zipWith_cons_cons]
          simp only [List.getElem_cons_succ, List.set_cons_succ, Bool.xor_false]
          rw [ih j hj']

/-- The CRC of the single-1 pattern from a zero register is never zero. -/
theorem feed_single_ne_zero (poly : BitVec w) (hw : 0 < w) (hp : poly.getLsbD 0 = true) (n j : Nat) :
    feed poly 0#w (single n j) ≠ 0#w := by
  simp only [single, feed_append, feed_zero_zeros, feed_cons, step_zero_true]
  apply feed_zeros_ne_zero poly hw hp
  intro h; rw [h] at hp; simp at hp

/-- **Main CRC theorem.** For every register width w ≥ 1, every polynomial with its constant term set, every starting
value and every message, flipping any single bit of the message changes the CRC. ProEm's CRC unit (widths 1 to 16)
therefore detects every single-bit error; crc_unit_formal proves the RTL computes exactly this register. -/
theorem detects_single_bit_error (poly init : BitVec w) (hw : 0 < w) (hp : poly.getLsbD 0 = true)
    (m : List Bool) (j : Nat) (hj : j < m.length) :
    feed poly init (m.set j (!m[j])) ≠ feed poly init m := by
  intro h
  have hlin := feed_xor poly init 0#w m (single m.length j) (length_single m.length j hj).symm
  rw [BitVec.xor_zero, ← set_eq_zipWith m j hj, h] at hlin
  have hz : feed poly 0#w (single m.length j) = 0#w := by
    have h2 := congrArg (fun x => feed poly init m ^^^ x) hlin
    rw [← BitVec.xor_assoc, BitVec.xor_self, BitVec.zero_xor] at h2
    exact h2.symm
  exact feed_single_ne_zero poly hw hp m.length j hz

/-! ## A check at the chip's own sizes

CRC-16/CCITT (polynomial 0x1021), as ProEm configures it for several standards: the residue theorem, evaluated. -/
example : feed 0x1021#16 0xBEEF#16 (msbBits 16 0xBEEF#16) = 0#16 := residue_zero _ _

end ProEm.Crc
