/-
  Basic correctness proofs for the `FixedRateRedeemer` reference model.

  `redeem_meets_spec` is the load-bearing theorem: every successful redemption
  debits the inventory by exactly the fixed-rate payout, credits the cumulative
  redeemed amount by exactly the input, and leaves all other state untouched.
-/

import Contracts.FixedRateRedeemer.Spec
import Contracts.FixedRateRedeemer.Invariants
import Verity.Proofs.Stdlib.Math
import Verity.Proofs.Stdlib.Automation

set_option linter.unusedSimpArgs false
set_option linter.unusedVariables false

namespace Contracts.FixedRateRedeemer.Proofs

open Verity
open Verity.EVM.Uint256
open Verity.Stdlib.Math
open Verity.Proofs.Stdlib.Math (safeAdd_some safeSub_some)
open Verity.Proofs.Stdlib.Automation (uint256_ge_val_le)
open Contracts.FixedRateRedeemer
open Contracts.FixedRateRedeemer.Spec
open Contracts.FixedRateRedeemer.Invariants

/-! ## preview -/

private theorem preview_run (s : ContractState) (amountA : Uint256) :
    (preview amountA).run s = ContractResult.success (payout amountA) s := by
  verity_unfold preview
  simp [payout, rateNumerator, rateDenominator]

theorem preview_meets_spec (s : ContractState) (amountA : Uint256) :
    let result := ((preview amountA).run s).fst
    preview_spec amountA result s := by
  rw [preview_run s amountA]
  simp [preview_spec, payout]

theorem preview_preserves_state (s : ContractState) (amountA : Uint256) :
    ((preview amountA).run s).snd = s := by
  rw [preview_run s amountA]
  simp

/-! ## redeem -/

/-- Unfold `redeem` on the success path. -/
private theorem redeem_unfold (s : ContractState) (amountA : Uint256)
    (h_nonzero : amountA > 0)
    (h_output : payout amountA > 0)
    (h_inv : s.storage 0 >= payout amountA)
    (h_sub : (payout amountA : Nat) ≤ (s.storage 0 : Nat))
    (h_add : (s.storage 1 : Nat) + (amountA : Nat) ≤ MAX_UINT256) :
    (redeem amountA).run s = ContractResult.success ()
      ((s.writeSlot 0 (sub (s.storage 0) (mulDivDown amountA rateNumerator rateDenominator))).writeSlot
        1 (add (s.storage 1) amountA)) := by
  have h_output' : mulDivDown amountA rateNumerator rateDenominator > 0 := h_output
  have h_inv' : s.storage 0 >= mulDivDown amountA rateNumerator rateDenominator := h_inv
  have h_safe_sub :=
    safeSub_some (s.storage 0) (mulDivDown amountA rateNumerator rateDenominator) h_sub
  have h_safe_add := safeAdd_some (s.storage 1) amountA h_add
  verity_unfold redeem
  simp only [remainingInventoryB, totalRedeemedA,
    Verity.require, Verity.bind, Bind.bind, Verity.pure, Pure.pure, Contract.run,
    h_nonzero, h_output', h_inv', decide_eq_true_eq, ite_true, ite_false]
  unfold requireSomeUint
  rw [h_safe_sub]
  simp only [Verity.pure, Pure.pure, Bind.bind, Contract.run]
  rw [h_safe_add]
  simp only [Verity.pure, Pure.pure, Bind.bind, Contract.run]
  rfl

/-- `redeem` debits the inventory by the fixed-rate payout and credits the
    cumulative redeemed amount, changing nothing else. -/
theorem redeem_meets_spec (s : ContractState) (amountA : Uint256)
    (h_nonzero : amountA > 0)
    (h_output : payout amountA > 0)
    (h_inv : s.storage 0 >= payout amountA)
    (h_no_overflow : (s.storage 1 : Nat) + (amountA : Nat) ≤ MAX_UINT256) :
    let s' := ((redeem amountA).run s).snd
    redeem_spec amountA s s' := by
  rw [redeem_unfold s amountA h_nonzero h_output h_inv (uint256_ge_val_le h_inv) h_no_overflow]
  simp only [ContractResult.snd, redeem_spec, sameStorageExceptAccounting]
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩
  · simp [ContractState.writeSlot, payout]
  · simp [ContractState.writeSlot, payout]
  · intro k h0 h1
    simp [ContractState.writeSlot, ContractState.storage, h0, h1]
  · simp only [Specs.sameStorageAddr, ContractState.storageAddr_writeSlot]
  · simp only [Specs.sameStorageMap, ContractState.storageMap_writeSlot]
  · simp [Specs.sameContext]

/-- The amount debited from the inventory equals the payout extracted from any
    result satisfying `preview_spec` — `redeem` and `preview` cannot diverge. -/
theorem redeem_consistent_with_preview (s : ContractState) (amountA r : Uint256)
    (h_preview : preview_spec amountA r s)
    (h_nonzero : amountA > 0)
    (h_output : payout amountA > 0)
    (h_inv : s.storage 0 >= payout amountA)
    (h_no_overflow : (s.storage 1 : Nat) + (amountA : Nat) ≤ MAX_UINT256) :
    let s' := ((redeem amountA).run s).snd
    s'.storage 0 = sub (s.storage 0) r := by
  have h := redeem_meets_spec s amountA h_nonzero h_output h_inv h_no_overflow
  simp only [redeem_spec, preview_spec] at h h_preview
  dsimp only
  rw [h.1, h_preview]

/-- The accounting slots after a successful redemption, restated directly. -/
theorem redeem_debits_payout (s : ContractState) (amountA : Uint256)
    (h_nonzero : amountA > 0)
    (h_output : payout amountA > 0)
    (h_inv : s.storage 0 >= payout amountA)
    (h_no_overflow : (s.storage 1 : Nat) + (amountA : Nat) ≤ MAX_UINT256) :
    let s' := ((redeem amountA).run s).snd
    s'.storage 0 = sub (s.storage 0) (payout amountA) ∧
    s'.storage 1 = add (s.storage 1) amountA := by
  have h := redeem_meets_spec s amountA h_nonzero h_output h_inv h_no_overflow
  simp only [redeem_spec] at h
  exact ⟨h.1, h.2.1⟩

end Contracts.FixedRateRedeemer.Proofs
