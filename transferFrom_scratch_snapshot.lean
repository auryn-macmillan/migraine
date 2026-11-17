import Contracts.Migraine.System
import Verity.Proofs.Stdlib.Automation
import Verity.Proofs.Stdlib.Math
import Verity.Proofs.Stdlib.ListSum

open Verity
open Verity.EVM.Uint256
open Verity.Stdlib.Math
open Verity.Proofs.Stdlib.Automation (uint256_ge_val_le address_beq_false_of_ne)
open Verity.Proofs.Stdlib.Math (safeAdd_some safeSub_some)
open Contracts.Migraine
open Contracts.Migraine.System

/-! Scratch: validate `transferFrom_unfold_other` (parameterized over the
balance/allowance slots) before integrating into System.lean -/

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
  have h_balance' := uint256_ge_val_le h_bal
  have h_safe := safeAdd_some (s.storageMap balSlot.slot dstAddr) amount h_no_overflow
  have h_beq_false : (s.storageMap2 allowSlot.slot srcAddr s.thisAddress == Core.Uint256.ofNat MAX_UINT256) = false :=
    beq_false_of_ne h_not_max
  have h_bal' : s.storageWords (StorageKey.map balSlot.slot srcAddr) ≥ amount := h_bal
  have h_safe' : safeAdd (s.storageWords (StorageKey.map balSlot.slot dstAddr)) amount =
      some (s.storageWords (StorageKey.map balSlot.slot dstAddr) + amount) := h_safe
  verity_unfold transferFrom
  simp only [Contracts.contractAddress, Verity.contractAddress, getMapping, getMapping2,
    setMapping, setMapping2, ContractState.readMap, ContractState.readMap2,
        ContractState.writeMap, ContractState.writeMap2, requireSomeUint, Verity.require,
        Verity.pure, Verity.bind, Bind.bind, Pure.pure, Contract.run, bne,
    Bool.not_eq_true',
    ContractState.storageMap, StorageKey.map_ne_map2,
    h_allow, h_bal, h_bal', h_ne, h_not_max, h_beq_false, beq_iff_eq, decide_eq_true_eq, ite_true, ite_false,
    h_safe, h_safe', HAdd.hAdd]
  congr 1
  congr 1
  funext slotIdx
  split <;> simp [*]