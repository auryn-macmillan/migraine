/-
  Formal specifications for the `Migraine` reference model.

  The two accounting slots are fixed:
    slot 0 = `remainingInventoryB`
    slot 1 = `totalRedeemedA`
-/

import Verity.Specs.Common
import Verity.Macro
import Verity.EVM.Uint256
import Verity.Stdlib.Math
import Contracts.Migraine.Migraine

namespace Contracts.Migraine.Spec

open Verity
open Verity.Specs
open Verity.EVM.Uint256
open Verity.Stdlib.Math
open Contracts.Migraine

/-- The payout formula at the immutable rate: `floor(amountA * num / den)`. -/
def payout (amountA : Uint256) : Uint256 :=
  mulDivDown amountA rateNumerator rateDenominator

/-- Every uint256 slot other than the two accounting slots is untouched. -/
def storageUnchangedExceptAccounting (s s' : ContractState) : Prop :=
  ∀ slotIdx : Nat, slotIdx ≠ 0 → slotIdx ≠ 1 → s'.storage slotIdx = s.storage slotIdx

/-- Frame for `redeem`: only the two accounting slots may change; all address
    storage, mapping storage and the call context are preserved. -/
def sameStorageExceptAccounting (s s' : ContractState) : Prop :=
  storageUnchangedExceptAccounting s s' ∧
  Specs.sameStorageAddr s s' ∧
  Specs.sameStorageMap s s' ∧
  Specs.sameContext s s'

/--
`redeem amountA` debits the remaining inventory by `payout amountA`, credits
`totalRedeemedA` by `amountA`, and changes nothing else.
-/
def redeem_spec (amountA : Uint256) (s s' : ContractState) : Prop :=
  s'.storage 0 = sub (s.storage 0) (payout amountA) ∧
  s'.storage 1 = add (s.storage 1) amountA ∧
  sameStorageExceptAccounting s s'

/-- `preview amountA` returns exactly the fixed-rate payout. -/
def preview_spec (amountA : Uint256) (result : Uint256) (s : ContractState) : Prop :=
  result = payout amountA

/-! ## Conservation / safety properties (targets for the proofs) -/

/-- After a successful redemption the inventory has fallen by exactly the previewed amount. -/
def redeem_conserves_inventory (amountA : Uint256) (s s' : ContractState) : Prop :=
  preview_spec amountA (sub (s.storage 0) (s'.storage 0)) s

/-- The inventory can never increase as a result of a redemption. -/
def inventory_never_increases (s s' : ContractState) : Prop :=
  (s'.storage 0 : Nat) ≤ (s.storage 0 : Nat)

/-- Total redeemed `tokenA` is monotone. -/
def redeemed_monotone (s s' : ContractState) : Prop :=
  (s.storage 1 : Nat) ≤ (s'.storage 1 : Nat)

end Contracts.Migraine.Spec
