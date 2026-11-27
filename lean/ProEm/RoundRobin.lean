/-
ProEm - Open Source Protocol Emulator
File: lean/ProEm/RoundRobin.lean
Description: The return path's round-robin arbiter, generalised to n sources and proved fair: a source that keeps asking
is served within n - 1 grants to others. return_path_formal proves the 3-source RTL matches this arbiter.
-/

namespace ProEm.RoundRobin

/-- Search p at i, i+1, ..., i+len-1 and return the first index where it holds. -/
def firstFrom (p : Nat → Bool) : Nat → Nat → Option Nat
  | _, 0 => none
  | i, len + 1 => if p i then some i else firstFrom p (i + 1) len

theorem firstFrom_spec (p : Nat → Bool) :
    ∀ (len i k : Nat), firstFrom p i len = some k → i ≤ k ∧ k < i + len ∧ p k = true
  | 0, i, k, h => by simp [firstFrom] at h
  | len + 1, i, k, h => by
      unfold firstFrom at h
      by_cases hp : p i
      · simp [hp] at h; subst h; exact ⟨Nat.le_refl _, by omega, hp⟩
      · simp [hp] at h
        have := firstFrom_spec p len (i + 1) k h
        exact ⟨by omega, by omega, this.2.2⟩

/-- If p holds at j in the window, the search finds an index no later than j. -/
theorem firstFrom_found (p : Nat → Bool) :
    ∀ (len i j : Nat), i ≤ j → j < i + len → p j = true → ∃ k, firstFrom p i len = some k ∧ k ≤ j
  | 0, i, j, h1, h2, _ => by omega
  | len + 1, i, j, h1, h2, hj => by
      unfold firstFrom
      by_cases hp : p i
      · exact ⟨i, by simp [hp], h1⟩
      · simp only [hp]
        have hij : i ≠ j := by intro e; subst e; simp [hp] at hj
        exact firstFrom_found p len (i + 1) j (by omega) (by omega) hj

/-- How many places after the turn pointer t source s sits, going round n sources. -/
def dist (n t s : Nat) : Nat := (s + n - t) % n

/-- The arbiter: from the turn pointer t, the offset of the first source asking (req), if any. -/
def grantOffset (n : Nat) (req : Nat → Bool) (t : Nat) : Option Nat :=
  firstFrom (fun k => req ((t + k) % n)) 0 n

/-- The source granted. -/
def granted (n t k : Nat) : Nat := (t + k) % n

/-- After granting source g, the pointer moves just past it. -/
def nextTurn (n g : Nat) : Nat := (g + 1) % n

/-- A value below 2n reduces mod n by at most one subtraction. -/
theorem modfact (x n : Nat) (h : x < 2 * n) : (x < n ∧ x % n = x) ∨ (n ≤ x ∧ x % n = x - n) := by
  by_cases hx : x < n
  · exact Or.inl ⟨hx, Nat.mod_eq_of_lt hx⟩
  · refine Or.inr ⟨by omega, ?_⟩
    rw [Nat.mod_eq_sub_mod (by omega)]
    exact Nat.mod_eq_of_lt (by omega)

/-- Going dist(t, s) places on from t lands on s. -/
theorem granted_dist (n t s : Nat) (ht : t < n) (hs : s < n) : granted n t (dist n t s) = s := by
  unfold granted dist
  have h1 := modfact (s + n - t) n (by omega)
  generalize (s + n - t) % n = a at *
  have h2 := modfact (t + a) n (by omega)
  generalize (t + a) % n = b at *
  omega

/-- A source that is asking is at least as near as the source granted. -/
theorem offset_le_dist (n : Nat) (req : Nat → Bool) (t s : Nat) (ht : t < n) (hs : s < n)
    (hreq : req s = true) : ∃ k, grantOffset n req t = some k ∧ k ≤ dist n t s := by
  have hd : dist n t s < n := Nat.mod_lt _ (by omega)
  apply firstFrom_found _ n 0 (dist n t s) (Nat.zero_le _) (by omega)
  show req (granted n t (dist n t s)) = true
  rw [granted_dist n t s ht hs]; exact hreq

/-- **Key step.** If someone other than s is granted, s moves strictly nearer the front: its distance drops by the
grant's offset plus one. -/
theorem dist_next (n t s k : Nat) (ht : t < n) (hs : s < n) (hk : k ≤ dist n t s)
    (hne : granted n t k ≠ s) : dist n (nextTurn n (granted n t k)) s = dist n t s - k - 1 := by
  have hdl : dist n t s < n := Nat.mod_lt _ (by omega)
  unfold dist nextTurn granted at *
  have h4 := modfact (s + n - t) n (by omega)
  generalize (s + n - t) % n = a at *
  have h1 := modfact (t + k) n (by omega)
  generalize (t + k) % n = g at *
  have h2 := modfact (g + 1) n (by omega)
  generalize (g + 1) % n = g1 at *
  have h3 := modfact (s + n - g1) n (by omega)
  generalize (s + n - g1) % n = b at *
  omega

/-- A run of the arbiter: reqs i is who is asking at the i-th grant; turn i is the pointer before it. Each grant moves
the pointer past the winner (if nobody asks, nothing is granted and the pointer stays). -/
def turn (n : Nat) (reqs : Nat → Nat → Bool) (t0 : Nat) : Nat → Nat
  | 0 => t0
  | i + 1 =>
      match grantOffset n (reqs i) (turn n reqs t0 i) with
      | some k => nextTurn n (granted n (turn n reqs t0 i) k)
      | none => turn n reqs t0 i

theorem turn_lt (n : Nat) (reqs : Nat → Nat → Bool) (t0 : Nat) (h0 : t0 < n) :
    ∀ i, turn n reqs t0 i < n
  | 0 => h0
  | i + 1 => by
      have hpos : 0 < n := by omega
      simp only [turn]
      split
      · exact Nat.mod_lt _ hpos
      · exact turn_lt n reqs t0 h0 i

/-- **Fairness, for any number of sources.** If source s keeps asking, then within dist(t0, s) ≤ n - 1 grants to others
it is served: the grant at some step i ≤ dist t0 s goes to s. For ProEm's three sources (channel A, channel B, link
flags) that is the "never more than two other messages first" property of return_path_formal. -/
theorem fair (n : Nat) (reqs : Nat → Nat → Bool) (t0 s : Nat) (h0 : t0 < n) (hs : s < n)
    (hask : ∀ i, reqs i s = true) :
    ∃ i, i ≤ dist n t0 s ∧ ∃ k, grantOffset n (reqs i) (turn n reqs t0 i) = some k ∧
      granted n (turn n reqs t0 i) k = s := by
  -- Strong induction on the distance of s from the pointer at step j, for every starting step j.
  suffices h : ∀ d j, dist n (turn n reqs t0 j) s = d →
      ∃ i, j ≤ i ∧ i ≤ j + d ∧ ∃ k, grantOffset n (reqs i) (turn n reqs t0 i) = some k ∧
        granted n (turn n reqs t0 i) k = s by
    obtain ⟨i, _, hi, rest⟩ := h (dist n t0 s) 0 (by simp [turn])
    exact ⟨i, by omega, rest⟩
  intro d
  induction d using Nat.strongRecOn with
  | ind d ih =>
    intro j hd
    have htj := turn_lt n reqs t0 h0 j
    obtain ⟨k, hk, hkd⟩ := offset_le_dist n (reqs j) (turn n reqs t0 j) s htj hs (hask j)
    by_cases hg : granted n (turn n reqs t0 j) k = s
    · exact ⟨j, Nat.le_refl _, by omega, k, hk, hg⟩
    · have hnext : turn n reqs t0 (j + 1) = nextTurn n (granted n (turn n reqs t0 j) k) := by
        simp [turn, hk]
      have hd' := dist_next n (turn n reqs t0 j) s k htj hs hkd hg
      rw [← hnext, hd] at hd'
      have hlt : d - k - 1 < d := by
        have : dist n (turn n reqs t0 j) s ≥ k + 1 := by
          by_cases e : k = dist n (turn n reqs t0 j) s
          · exfalso; apply hg
            rw [e]; exact granted_dist n _ s htj hs
          · omega
        omega
      obtain ⟨i, hi1, hi2, rest⟩ := ih (d - k - 1) hlt (j + 1) hd'
      exact ⟨i, by omega, by omega, rest⟩

/-- The return path's case: three sources, so a waiting source sees at most two other grants first. -/
theorem fair_three (reqs : Nat → Nat → Bool) (t0 s : Nat) (h0 : t0 < 3) (hs : s < 3)
    (hask : ∀ i, reqs i s = true) :
    ∃ i, i ≤ 2 ∧ ∃ k, grantOffset 3 (reqs i) (turn 3 reqs t0 i) = some k ∧
      granted 3 (turn 3 reqs t0 i) k = s := by
  obtain ⟨i, hi, rest⟩ := fair 3 reqs t0 s h0 hs hask
  have : dist 3 t0 s < 3 := Nat.mod_lt _ (by decide)
  exact ⟨i, by omega, rest⟩

end ProEm.RoundRobin
