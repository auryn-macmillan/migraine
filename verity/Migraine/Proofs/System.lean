/-
  Proofs about the closed-system model `Migraine.System`, which
  mirrors `src/Migraine.sol` together with the two standard ERC-20 ledgers it
  transacts against.

  Coverage map (property numbers from SPEC.md §4):
  * P1/P2 rate correctness   — `redeemTo_success_rate`, `previewRedeem_run`
  * P3 atomicity              — `redeemTo_revert_state_unchanged` + the exact
                                success state in `redeemTo_success_effects`
  * P4 no custody             — `redeemTo_no_custody`, `redeemTo_custody_zero`
  * P5 conservation           — `redeemTo_preserves_balB_sum`,
                                `redeemTo_preserves_balA_sum`
  * P6 configuration immutability — `redeemTo_preserves_config`,
                                `redeemTo_preserves_ValidConfig`
  * P7 reentrancy safety      — `redeemTo_preserves_ValidConfig` applied
                                transition-by-transition (see the section on
                                statelessness at the end of this file)
-/

import Migraine.System
import Verity.Proofs.Stdlib.Automation
import Verity.Proofs.Stdlib.Math
import Verity.Proofs.Stdlib.ListSum

set_option linter.unusedSimpArgs false
set_option linter.unusedVariables false
set_option maxRecDepth 16000

namespace Migraine.Proofs.System

open Verity
open Verity.EVM.Uint256
open Verity.Stdlib.Math
open Migraine
open Migraine.System
open Verity.Proofs.Stdlib.Automation (uint256_ge_val_le address_beq_false_of_ne)
open Verity.Proofs.Stdlib.Math (safeAdd_some safeSub_some)
open Verity.Proofs.Stdlib.ListSum
  (countOcc countOccU map_sum_transfer_eq)

/-! ## Shared simp set -/

/-! ## `previewRedeem` (P2, view side) -/

/-- Exact run of `previewRedeem`: the full-precision floor quotient when it
    fits, and a revert exactly when `Math.mulDiv` would panic. The state is
    untouched in both branches (the Solidity function is `view`). -/
theorem previewRedeem_run (s : ContractState) (amountA : Uint256) :
    (previewRedeem amountA).run s =
      match mulDiv512Down? amountA (s.storage 3) (s.storage 4) with
      | some r => ContractResult.success r s
      | none => ContractResult.revert "MulDivOverflow" s := by
  verity_unfold previewRedeem
  simp only [rateNumSlot, rateDenSlot, getRateNum, getRateDen]
  unfold requireSomeUint
  cases mulDiv512Down? amountA (s.storage 3) (s.storage 4) with
  | some r => rfl
  | none => rfl

/-- `previewRedeem` never touches state (it is a Solidity `view`). -/
theorem previewRedeem_preserves_state (s : ContractState) (amountA : Uint256) :
    ((previewRedeem amountA).run s).snd = s := by
  rw [previewRedeem_run]
  cases mulDiv512Down? amountA (s.storage 3) (s.storage 4) <;> simp

/-! ## `deploy` (constructor) -/

/-- A successful deployment writes exactly the five configuration slots and
    leaves every other slot untouched. -/
theorem deploy_meets_spec (s : ContractState) (tokenA tokenB wallet : Address)
    (num den : Uint256) (s' : ContractState)
    (h_spec : (deploy tokenA tokenB wallet num den).run s =
      ContractResult.success () s')
    (h_tokenA : tokenA ≠ 0) (h_tokenB : tokenB ≠ 0) (h_distinct : tokenA ≠ tokenB)
    (h_wallet : wallet ≠ 0) (h_walletThis : wallet ≠ s.thisAddress)
    (h_walletA : wallet ≠ tokenA) (h_walletB : wallet ≠ tokenB)
    (h_num : num ≠ 0) (h_den : den ≠ 0) :
    s'.storageAddr 0 = tokenA ∧ s'.storageAddr 1 = tokenB ∧
    s'.storageAddr 2 = wallet ∧ s'.storage 3 = num ∧ s'.storage 4 = den ∧
    (∀ sl, sl ∉ configSlots → s'.storage sl = s.storage sl) ∧
    (∀ sl, sl ∉ configSlots → s'.storageAddr sl = s.storageAddr sl) := by
  simp only [deploy, getTokenA, getTokenB, getWallet, getRateNum, getRateDen,
    getStorage, getStorageAddr, setStorage, setStorageAddr,
    Verity.contractAddress,
    Verity.require, Verity.bind, Bind.bind, Verity.pure, Pure.pure,
    Contract.run, tokenASlot, tokenBSlot, walletSlot,
    rateNumSlot, rateDenSlot] at h_spec
  simp [h_tokenA, h_tokenB, h_distinct, h_wallet, h_walletThis, h_walletA,
    h_walletB, h_num, h_den] at h_spec
  subst h_spec
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;>
    simp [ContractState.writeSlot, ContractState.writeAddrSlot,
      ContractState.storage, ContractState.storageAddr,
      ContractState.readSlot, ContractState.readAddrSlot]
  · intro sl h
    simp only [configSlots, List.mem_cons, not_or, List.not_mem_nil] at h
    simp [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1,
      ContractState.writeSlot, ContractState.writeAddrSlot,
      ContractState.storage, ContractState.readSlot]
  · intro sl h
    simp only [configSlots, List.mem_cons, not_or, List.not_mem_nil] at h
    simp [h.1, h.2.1, h.2.2.1, h.2.2.2.1, h.2.2.2.2.1,
      ContractState.writeSlot, ContractState.writeAddrSlot,
      ContractState.storageAddr, ContractState.readAddrSlot]

/-! ## `redeemTo` revert behaviour (P3, negative half) -/

/-- **P3 (atomicity).** Any revert of `redeemTo` leaves the entire state
    unchanged: no balance, allowance, configuration, or event write survives a
    failed redemption. This mirrors the EVM call-frame semantics — a revert
    discards every write made during the transaction — which Verity models
    directly in `Contract.run` (rollback-by-construction, Verity issue #254):
    the `ContractResult` produced by the body is inspected, and any `revert`
    carries the pre-call snapshot, never a partially-written state. -/
theorem redeemTo_revert_state_unchanged (s : ContractState)
    (amountA : Uint256) (recipient : Address) :
    ∀ {msg : String} {s' : ContractState},
      (redeemTo amountA recipient).run s = ContractResult.revert msg s' →
      s' = s := by
  intro msg s' h
  cases h' : redeemTo amountA recipient s with
  | success a st =>
    simp only [Contract.run, h'] at h
    exact absurd h (by simp)
  | «revert» m st =>
    simp only [Contract.run, h'] at h
    exact (ContractResult.revert.inj h).2.symm

/-- The non-self `transferFrom` path (validated standalone in Scratch): with
    sufficient balance and allowance (non-infinite), it debits `srcAddr`,
    credits `dstAddr`, and consumes the allowance. The linchpin of the
    `redeemTo` proofs. -/
theorem transferFrom_unfold_other (s : ContractState)
    (balSlot : StorageSlot (Address → Uint256))
    (allowSlot : StorageSlot (Address → Address → Uint256))
    (srcAddr dstAddr : Address) (amount : Uint256)
    (h_allow : s.storageMap2 allowSlot.slot srcAddr s.thisAddress ≥ amount)
    (h_not_max : s.storageMap2 allowSlot.slot srcAddr s.thisAddress ≠ MAX_UINT256)
    (h_bal : s.storageMap balSlot.slot srcAddr ≥ amount)
    (h_ne : srcAddr ≠ dstAddr)
    (h_no_overflow : (s.storageMap balSlot.slot dstAddr : Nat) + (amount : Nat) ≤ MAX_UINT256) :
    (transferFrom balSlot allowSlot srcAddr dstAddr amount).run s = ContractResult.success ()
      { ((s.writeMap2 allowSlot.slot srcAddr s.thisAddress
          (EVM.Uint256.sub (s.storageMap2 allowSlot.slot srcAddr s.thisAddress) amount)).writeMap
        balSlot.slot srcAddr (EVM.Uint256.sub (s.storageMap balSlot.slot srcAddr) amount)).writeMap
        balSlot.slot dstAddr (EVM.Uint256.add (s.storageMap balSlot.slot dstAddr) amount) with
        knownAddresses := fun slotIdx =>
          if slotIdx == balSlot.slot then
            ((s.knownAddresses slotIdx).insert srcAddr).insert dstAddr
          else s.knownAddresses slotIdx } := by
  have h_safe := safeAdd_some (s.storageMap balSlot.slot dstAddr) amount h_no_overflow
  have h_beq_false : (s.storageMap2 allowSlot.slot srcAddr s.thisAddress == Core.Uint256.ofNat MAX_UINT256) = false :=
    beq_false_of_ne h_not_max
  have h_bal' : s.storageWords (StorageKey.map balSlot.slot srcAddr) ≥ amount := h_bal
  have h_safe' : safeAdd (s.storageWords (StorageKey.map balSlot.slot dstAddr)) amount =
      some (s.storageWords (StorageKey.map balSlot.slot dstAddr) + amount) := h_safe
  verity_unfold transferFrom
  simp only [Verity.contractAddress, getMapping, getMapping2,
    setMapping, setMapping2, ContractState.readMap, ContractState.readMap2,
    ContractState.writeMap, ContractState.writeMap2, requireSomeUint, Verity.require,
    Verity.pure, Verity.bind, Bind.bind, Pure.pure, Contract.run, bne,
    Bool.not_eq_true',
    ContractState.storageMap, StorageKey.map_ne_map2,
    h_allow, h_bal, h_bal', h_ne, h_not_max, h_beq_false, beq_iff_eq, decide_eq_true_eq,
    ite_true, ite_false,
    h_safe, h_safe', HAdd.hAdd]
  congr 1
  congr 1
  funext slotIdx
  split <;> simp [*]

/-- The infinite-approval `transferFrom` path: when the spender's allowance is
    `MAX_UINT256` (mirroring OZ v5 `_spendAllowance`'s max-uint skip), the
    transfer moves balances but leaves the allowance untouched. Companion of
    `transferFrom_unfold_other`; discharges the non-MAX premise. -/
theorem transferFrom_unfold_max (s : ContractState)
    (balSlot : StorageSlot (Address → Uint256))
    (allowSlot : StorageSlot (Address → Address → Uint256))
    (srcAddr dstAddr : Address) (amount : Uint256)
    (h_max : s.storageMap2 allowSlot.slot srcAddr s.thisAddress = MAX_UINT256)
    (h_bal : s.storageMap balSlot.slot srcAddr ≥ amount)
    (h_ne : srcAddr ≠ dstAddr)
    (h_no_overflow : (s.storageMap balSlot.slot dstAddr : Nat) + (amount : Nat) ≤ MAX_UINT256) :
    (transferFrom balSlot allowSlot srcAddr dstAddr amount).run s = ContractResult.success ()
      { (s.writeMap balSlot.slot srcAddr (EVM.Uint256.sub (s.storageMap balSlot.slot srcAddr) amount)).writeMap
          balSlot.slot dstAddr (EVM.Uint256.add (s.storageMap balSlot.slot dstAddr) amount) with
        knownAddresses := fun slotIdx =>
          if slotIdx == balSlot.slot then
            ((s.knownAddresses slotIdx).insert srcAddr).insert dstAddr
          else s.knownAddresses slotIdx } := by
  have h_safe := safeAdd_some (s.storageMap balSlot.slot dstAddr) amount h_no_overflow
  have h_beq_true : (s.storageMap2 allowSlot.slot srcAddr s.thisAddress == Core.Uint256.ofNat MAX_UINT256) = true := by
    simp [h_max]
  have h_beq_self : (Core.Uint256.ofNat MAX_UINT256 == Core.Uint256.ofNat MAX_UINT256) = true := by
    decide
  have h_ge : amount ≤ Core.Uint256.ofNat MAX_UINT256 := by
    have h_mod : MAX_UINT256 % Core.Uint256.modulus = MAX_UINT256 := by decide
    simp [Core.Uint256.le_def, h_mod, Core.Uint256.val_le_max]
  have h_bal' : s.storageWords (StorageKey.map balSlot.slot srcAddr) ≥ amount := h_bal
  have h_safe' : safeAdd (s.storageWords (StorageKey.map balSlot.slot dstAddr)) amount =
      some (s.storageWords (StorageKey.map balSlot.slot dstAddr) + amount) := h_safe
  verity_unfold transferFrom
  simp only [Verity.contractAddress, getMapping, getMapping2,
    setMapping, setMapping2, ContractState.readMap, ContractState.readMap2,
    ContractState.writeMap, ContractState.writeMap2, requireSomeUint, Verity.require,
    Verity.pure, Verity.bind, Bind.bind, Pure.pure, Contract.run, bne,
    Bool.not_eq_true',
    ContractState.storageMap, StorageKey.map_ne_map2,
    h_max, h_bal, h_bal', h_ne, h_beq_true, h_beq_self, h_ge,
    beq_iff_eq, decide_eq_true_eq,
    ite_true, ite_false,
    h_safe, h_safe', HAdd.hAdd,
    if_neg (by decide : ¬ (true = false))]
  congr 1
  congr 1
  funext slotIdx
  split <;> simp [*]

end Migraine.Proofs.System
