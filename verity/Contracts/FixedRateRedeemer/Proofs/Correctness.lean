/-
  Correctness properties for the `FixedRateRedeemer` reference model:
  guard behaviour and well-formedness.
-/

import Contracts.FixedRateRedeemer.Proofs.Basic
import Verity.Proofs.Stdlib.Automation

set_option linter.unusedSimpArgs false
set_option linter.unusedVariables false

namespace Contracts.FixedRateRedeemer.Proofs.Correctness

open Verity
open Verity.EVM.Uint256
open Verity.Stdlib.Math
open Contracts.FixedRateRedeemer
open Contracts.FixedRateRedeemer.Spec
open Contracts.FixedRateRedeemer.Proofs
open Contracts.FixedRateRedeemer.Invariants

/-! ## Guard behaviour -/

/-- A zero input always reverts. -/
theorem redeem_reverts_zero_amount (s : ContractState) (amountA : Uint256)
    (h_zero : amountA = 0) :
    ∃ msg, (redeem amountA).run s = ContractResult.revert msg s := by
  subst h_zero
  verity_unfold redeem
  simp [remainingInventoryB, totalRedeemedA, Verity.require, Verity.bind, Bind.bind,
    Contract.run, decide_eq_false_iff_not]

/-- An input whose payout rounds down to zero reverts. -/
theorem redeem_reverts_zero_output (s : ContractState) (amountA : Uint256)
    (h_nonzero : amountA > 0) (h_zero : payout amountA = 0) :
    ∃ msg, (redeem amountA).run s = ContractResult.revert msg s := by
  have h_zero' : (amountA * rateNumerator) / rateDenominator = 0 := by
    simpa [payout, mulDivDown] using h_zero
  verity_unfold redeem
  simp [remainingInventoryB, totalRedeemedA, Verity.require, Verity.bind, Bind.bind,
    Contract.run, h_nonzero, h_zero']

/-- Redemption reverts when the vault inventory cannot cover the payout. -/
theorem redeem_reverts_insufficient_inventory (s : ContractState) (amountA : Uint256)
    (h_nonzero : amountA > 0) (h_output : payout amountA > 0)
    (h_inv : ¬ (s.storage 0 >= payout amountA)) :
    ∃ msg, (redeem amountA).run s = ContractResult.revert msg s := by
  have h_output' : (amountA * rateNumerator) / rateDenominator > 0 := by
    simpa [payout, mulDivDown] using h_output
  have h_inv' : ¬ ((s.storage 0 : Uint256) >= (amountA * rateNumerator) / rateDenominator) := by
    simpa [payout, mulDivDown] using h_inv
  verity_unfold redeem
  simp [remainingInventoryB, totalRedeemedA, Verity.require, Verity.bind, Bind.bind,
    Contract.run, h_nonzero, h_output', h_inv']

/-! ## Well-formedness -/

/-- A successful redemption preserves well-formedness of the context. -/
theorem redeem_preserves_wellformedness (s : ContractState) (amountA : Uint256)
    (h_wf : WellFormedState s)
    (h_nonzero : amountA > 0)
    (h_output : payout amountA > 0)
    (h_inv : s.storage 0 >= payout amountA)
    (h_no_overflow : (s.storage 1 : Nat) + (amountA : Nat) ≤ MAX_UINT256) :
    let s' := ((redeem amountA).run s).snd
    WellFormedState s' := by
  dsimp only
  have h := redeem_meets_spec s amountA h_nonzero h_output h_inv h_no_overflow
  simp only [redeem_spec, sameStorageExceptAccounting] at h
  obtain ⟨_, _, _, _, _, h_ctx⟩ := h
  refine ⟨?_, ?_⟩
  · rw [h_ctx.1]
    exact h_wf.sender_nonzero
  · rw [h_ctx.2.1]
    exact h_wf.contract_nonzero

end Contracts.FixedRateRedeemer.Proofs.Correctness
