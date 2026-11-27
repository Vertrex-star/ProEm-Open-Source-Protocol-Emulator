/-
ProEm - Open Source Protocol Emulator
File: lean/ProEm/Router.lean
Description: start_router's carry chain, proved for any number of blocks: a block starts exactly when every running
block before it has succeeded, MAIN starts when all have, nothing after the first unconfigured header ever starts,
and only one block is ever waiting at a time.
-/

/-!
# The start router (src/core/frame_chain/start_router.sv), for any number of blocks

The RTL is a generate loop. Each input is a function from block number to Bool, so the proofs hold for every
`blocks` parameter, not just the 7 in the chip.

* `ended i`   : some header from 1 to i is unconfigured (the list stops there)
* `running i` : block i takes part in this run (block 0, the start block, always does)
* `carry i`   : the last running block at or before i has succeeded
* `enable i`  : block i is switched on
-/

namespace ProEm.Router

variable (succ cfg act : Nat → Bool)

def ended : Nat → Bool
  | 0 => false
  | i + 1 => ended i || !cfg (i + 1)

def running : Nat → Bool
  | 0 => true
  | i + 1 => act (i + 1) && !ended cfg (i + 1)

def carry : Nat → Bool
  | 0 => succ 0
  | i + 1 => if running cfg act (i + 1) then succ (i + 1) else carry i

def enable : Nat → Bool
  | 0 => true
  | i + 1 => carry succ cfg act i && running cfg act (i + 1)

/-- main_enable is carry[blocks-1]. -/
def mainEnable (blocks : Nat) : Bool := carry succ cfg act (blocks - 1)

/-- Only switched-on blocks can succeed (a block that is off holds its success flag low). This is the one assumption
about the rest of the chain. -/
def SuccessNeedsEnable : Prop := ∀ j, succ j = true → enable succ cfg act j = true

theorem enable_running (i : Nat) (h : enable succ cfg act i = true) : running cfg act i = true := by
  cases i with
  | zero => rfl
  | succ i => simp [enable] at h; exact h.2

/-- The carry means every running block so far has succeeded, not just the last one. -/
theorem carry_iff (hs : SuccessNeedsEnable succ cfg act) :
    ∀ i, carry succ cfg act i = true ↔ ∀ j, j ≤ i → running cfg act j = true → succ j = true := by
  intro i
  induction i with
  | zero =>
      constructor
      · intro h j hj _; have : j = 0 := by omega
        subst this; exact h
      · intro h; exact h 0 (Nat.le_refl 0) rfl
  | succ i ih =>
      by_cases hr : running cfg act (i + 1) = true
      · simp only [carry, hr, ite_true]
        constructor
        · intro h j hj hrj
          by_cases hji : j = i + 1
          · subst hji; exact h
          · have he := hs (i + 1) h
            simp [enable] at he
            exact (ih.mp he.1) j (by omega) hrj
        · intro h; exact h (i + 1) (Nat.le_refl _) hr
      · have hr' : running cfg act (i + 1) = false := by simpa using hr
        simp only [carry, hr', ite_false, Bool.false_eq_true]
        constructor
        · intro h j hj hrj
          by_cases hji : j = i + 1
          · subst hji; rw [hr'] at hrj; contradiction
          · exact (ih.mp h) j (by omega) hrj
        · intro h; exact ih.mpr (fun j hj hrj => h j (by omega) hrj)

/-- A block is switched on exactly when it is running and every running block before it has succeeded. -/
theorem enable_iff (hs : SuccessNeedsEnable succ cfg act) (i : Nat) :
    enable succ cfg act (i + 1) = true ↔
      running cfg act (i + 1) = true ∧ ∀ j, j ≤ i → running cfg act j = true → succ j = true := by
  simp only [enable, Bool.and_eq_true]
  rw [carry_iff succ cfg act hs i]
  exact And.comm

/-- MAIN starts exactly when every running block has succeeded. -/
theorem main_iff (hs : SuccessNeedsEnable succ cfg act) (blocks : Nat) :
    mainEnable succ cfg act blocks = true ↔
      ∀ j, j < blocks ∨ j = 0 → running cfg act j = true → succ j = true := by
  unfold mainEnable
  rw [carry_iff succ cfg act hs]
  constructor
  · intro h j hj; exact h j (by omega)
  · intro h j hj; exact h j (by omega)

theorem ended_mono (i : Nat) : ∀ k, i ≤ k → ended cfg i = true → ended cfg k = true := by
  intro k hk h
  induction k with
  | zero => have : i = 0 := by omega
            subst this; exact h
  | succ k ih =>
      by_cases hik : i = k + 1
      · subst hik; exact h
      · simp [ended, ih (by omega)]

theorem ended_of_unconfigured (j : Nat) (hj : 0 < j) (h : cfg j = false) : ended cfg j = true := by
  cases j with
  | zero => omega
  | succ j => simp [ended, h]

/-- The first unconfigured header ends the list: no block after it is ever switched on. -/
theorem nothing_after_end (j k : Nat) (hj : 0 < j) (hc : cfg j = false) (hk : j ≤ k) :
    enable succ cfg act k = false := by
  cases k with
  | zero => omega
  | succ k =>
      have he : ended cfg (k + 1) = true := ended_mono cfg j (k + 1) hk (ended_of_unconfigured cfg j hj hc)
      simp [enable, running, he]

/-- Skipped headers (outside the run's group) are never switched on. -/
theorem inactive_off (k : Nat) (h : act (k + 1) = false) : enable succ cfg act (k + 1) = false := by
  simp [enable, running, h]

/-- At most one block is ever waiting (switched on but not yet succeeded): the chain runs one block at a time. -/
theorem one_waiting (hs : SuccessNeedsEnable succ cfg act) (i k : Nat) (hik : i < k)
    (hi : enable succ cfg act i = true) (hk : enable succ cfg act k = true) : succ i = true := by
  cases k with
  | zero => omega
  | succ k =>
      have := (enable_iff succ cfg act hs k).mp hk
      exact this.2 i (by omega) (enable_running succ cfg act i hi)

end ProEm.Router
