/-
  Exact success-path proof for the closed-system `redeemTo`
  (`Contracts.Migraine.System`): the full post-state of a successful
  redemption — payout at the floor rate quotient, token A pulled caller →
  wallet, token B pushed wallet → recipient, both allowances consumed, the
  `Redeemed` event appended. Proves SPEC P1/P2 (rate) and the positive half
  of P3 (the exact effects the negative half in `Proofs/System.lean`
  complements); the conservation, no-custody, and config-immutability
  corollaries (P4–P6) follow in the last section.

  Structure: `chain_shape` drives the `do`-chain over abstract intermediate
  states with each intermediate result pinned as a raw-application
  equality (one `verity_unfold` + one `simp only` — anything bigger hits
  the kernel deterministic timeout); `redeemTo_success_run` instantiates
  the pins via the upstream `transferFrom_unfold_other` +
  `Contract.eq_of_run_success`.
-/
import Contracts.Migraine.System
import Contracts.Migraine.Proofs.System
import Verity.Proofs.Stdlib.Automation
import Verity.Proofs.Stdlib.Math
import Verity.Proofs.Stdlib.ListSum

set_option autoImplicit false
set_option maxRecDepth 16000
set_option linter.unusedVariables false
set_option linter.missingDocs false
set_option linter.unusedSimpArgs false

open Verity
open Verity.EVM.Uint256
open Verity.Stdlib.Math
open Contracts.Migraine.System

open Verity.Proofs.Stdlib.Automation (address_beq_false_of_ne)

namespace Contracts.Migraine.Proofs.RedeemTo

/-- The `Redeemed` event appended by `redeemTo`, exactly as `emitEvent`
    puts it in `state.events`. -/
def evState (s : ContractState) (sender recipient : Address)
    (amountA amountB : Uint256) : ContractState :=
  { s with events := s.events ++
      [{ name := "Redeemed", args := [amountA, amountB],
         indexedArgs := [addressToWord sender, addressToWord recipient] }] }

/-- State after leg A of `redeemTo` (token A: sender → wallet). Mirrors
    `transferFrom_unfold_other`'s post-state shape exactly. -/
def S1 (s : ContractState) (sender wallet : Address) (amountA : Uint256) :
    ContractState :=
  { ((s.writeMap2 allowASlot.slot sender s.thisAddress
        (EVM.Uint256.sub (s.storageMap2 allowASlot.slot sender s.thisAddress) amountA)).writeMap
        balASlot.slot sender
        (EVM.Uint256.sub (s.storageMap balASlot.slot sender) amountA)).writeMap
        balASlot.slot wallet
        (EVM.Uint256.add (s.storageMap balASlot.slot wallet) amountA) with
    knownAddresses := fun slotIdx =>
      if slotIdx == balASlot.slot then
        ((s.knownAddresses slotIdx).insert sender).insert wallet
      else s.knownAddresses slotIdx }

/-- Full `redeemTo` post-state: post-leg-A state plus the token-B leg
    `transferFrom balBSlot allowBSlot wallet recipient amountB`. -/
def finalState (s0 : ContractState) (wallet recipient : Address)
    (amountB : Uint256) : ContractState :=
  { ((s0.writeMap2 allowBSlot.slot wallet s0.thisAddress
        (EVM.Uint256.sub (s0.storageMap2 allowBSlot.slot wallet s0.thisAddress) amountB)).writeMap
        balBSlot.slot wallet
        (EVM.Uint256.sub (s0.storageMap balBSlot.slot wallet) amountB)).writeMap
        balBSlot.slot recipient
        (EVM.Uint256.add (s0.storageMap balBSlot.slot recipient) amountB) with
    knownAddresses := fun slotIdx =>
      if slotIdx == balBSlot.slot then
        ((s0.knownAddresses slotIdx).insert wallet).insert recipient
      else s0.knownAddresses slotIdx }

/-- Chain shape for `redeemTo`: with the guards pinned true by plain Prop
    facts, the rate reads pinned, and both `transferFrom` legs pinned (in raw
    application form, which is exactly how the unfolded `Bind` chain renders
    them) at the concrete event-emission post-state, the whole do-chain
    succeeds and lands in the pinned end state.

    Driving the chain with one `verity_unfold` + `simp only` pass — after
    unfolding the event-state def uniformly with `at *` so the pins match
    syntactically — keeps every kernel defeq check small enough to finish. -/
theorem chain_shape
    (amountA amountB : Uint256) (recipient : Address)
    (num den : Uint256)
    (t0 t1 t2 : ContractState)
    (h_posA : amountA > 0) (h_posB : amountB > 0)
    (h_num : t0.storage rateNumSlot.slot = num)
    (h_den : t0.storage rateDenSlot.slot = den)
    (hP : mulDiv512Down? amountA num den = some amountB)
    (h_recipient_ne_zero : recipient ≠ 0)
    (h_recipient_ne_this : recipient ≠ t0.thisAddress)
    (h_recipient_ne_tokenA : recipient ≠
      wordToAddress (t0.storageWords (StorageKey.addr tokenASlot.slot)))
    (h_recipient_ne_tokenB : recipient ≠
      wordToAddress (t0.storageWords (StorageKey.addr tokenBSlot.slot)))
    (h_recipient_ne_wallet : recipient ≠
      wordToAddress (t0.storageWords (StorageKey.addr walletSlot.slot)))
    (hTF1 : transferFrom balASlot allowASlot t0.sender
        (wordToAddress (t0.storageWords (StorageKey.addr walletSlot.slot)))
        amountA { t0 with events := t0.events ++
          [{ name := "Redeemed", args := [amountA, amountB],
             indexedArgs := [addressToWord t0.sender, addressToWord recipient] }] }
        = @ContractResult.success Unit () t1)
    (hTF2 : transferFrom balBSlot allowBSlot
        (wordToAddress (t0.storageWords (StorageKey.addr walletSlot.slot)))
        recipient amountB t1 = @ContractResult.success Unit () t2) :
        (redeemTo amountA recipient).run t0 =
        @ContractResult.success Uint256 amountB t2 := by
  verity_unfold redeemTo
  simp only [getTokenA, getTokenB, getWallet, getRateNum, getRateDen,
    Contracts.contractAddress, Verity.contractAddress,
    getStorage, getStorageAddr, emitEvent,
    requireSomeUint, Verity.require, Verity.pure, Verity.bind, Bind.bind,
    Pure.pure,
    ContractState.storage_unfold, ContractState.storageAddr_unfold,
    ContractState.readSlot,
    ContractState.readAddrSlot, pure_run,
    bne, Bool.not_eq_true', beq_iff_eq, decide_eq_true_eq,
    beq_eq_false_iff_ne, Ne, not_false_eq_true,
    ite_true, ite_false, reduceIte,
    h_num, h_den, h_posA, h_posB, hP,
    h_recipient_ne_zero, h_recipient_ne_this, h_recipient_ne_tokenA,
    h_recipient_ne_tokenB, h_recipient_ne_wallet,
    hTF1, hTF2]

/-- **`redeemTo` success path (full post-state).** Under standard
    preconditions (positive amounts, recipient outside the blacklist,
    sufficient allowances and balances, non-infinite allowances, no
    overflow), `redeemTo` succeeds, pays exactly the floor quotient
    `amountB`, moves token A caller → wallet and token B wallet → recipient,
    consuming both allowances and appending the `Redeemed` event. -/
theorem redeemTo_success_run
    (s : ContractState) (amountA amountB : Uint256)
    (wallet num den recipient : Address)
    (h_num : s.storage rateNumSlot.slot = num)
    (h_den : s.storage rateDenSlot.slot = den)
    (h_amountB : mulDiv512Down? amountA num den = some amountB)
    (h_posA : amountA > 0)
    (h_posB : amountB > 0)
    (h_recipient_nonzero : recipient ≠ 0)
    (h_recipient_ne_this : recipient ≠ s.thisAddress)
    (h_recipient_ne_tokenA : recipient ≠ s.storageAddr tokenASlot.slot)
    (h_recipient_ne_tokenB : recipient ≠ s.storageAddr tokenBSlot.slot)
    (h_recipient_ne_wallet : recipient ≠ wallet)
    (h_tokA : s.storageAddr tokenASlot.slot ≠ 0)
    (h_tokB : s.storageAddr tokenBSlot.slot ≠ 0)
    (h_wallet : s.storageAddr walletSlot.slot = wallet)
    (h_allowA : s.storageMap2 allowASlot.slot s.sender s.thisAddress ≥ amountA)
    (h_notMaxA : s.storageMap2 allowASlot.slot s.sender s.thisAddress ≠ MAX_UINT256)
    (h_balA : s.storageMap balASlot.slot s.sender ≥ amountA)
    (h_neA : s.sender ≠ wallet)
    (h_noOvfA : (s.storageMap balASlot.slot wallet : Nat) + (amountA : Nat) ≤ MAX_UINT256)
    (h_allowB : s.storageMap2 allowBSlot.slot wallet s.thisAddress ≥ amountB)
    (h_notMaxB : s.storageMap2 allowBSlot.slot wallet s.thisAddress ≠ MAX_UINT256)
    (h_balB : s.storageMap balBSlot.slot wallet ≥ amountB)
    (h_neB : wallet ≠ recipient)
    (h_noOvfB : (s.storageMap balBSlot.slot recipient : Nat) + (amountB : Nat) ≤ MAX_UINT256) :
    (redeemTo amountA recipient).run s =
      ContractResult.success amountB
        (finalState (S1 (evState s s.sender recipient amountA amountB) s.sender wallet amountA)
          wallet recipient amountB) := by
  -- The wallet read in the raw `storageWords` form the unfolded chain uses.
  have h_walletW : wordToAddress (s.storageWords (StorageKey.addr walletSlot.slot)) = wallet := by
    show s.storageAddr walletSlot.slot = wallet
    exact h_wallet
  -- Leg A on the event-extended state (event update touches no storage).
  have h_wallet_ev : wordToAddress
      ((evState s s.sender recipient amountA amountB).storageWords
        (StorageKey.addr walletSlot.slot)) = wallet := by
    simp [evState]; exact h_walletW
  have h_ne_wallet_ev : recipient ≠
      wordToAddress ((evState s s.sender recipient amountA amountB).storageWords
        (StorageKey.addr walletSlot.slot)) := by
    rw [h_wallet_ev]; exact h_recipient_ne_wallet
  have h_wordA : recipient ≠
      wordToAddress (s.storageWords (StorageKey.addr tokenASlot.slot)) := by
    show recipient ≠ s.storageAddr tokenASlot.slot; exact h_recipient_ne_tokenA
  have h_wordB : recipient ≠
      wordToAddress (s.storageWords (StorageKey.addr tokenBSlot.slot)) := by
    show recipient ≠ s.storageAddr tokenBSlot.slot; exact h_recipient_ne_tokenB
  have hTF1 : transferFrom balASlot allowASlot s.sender
        (wordToAddress (s.storageWords (StorageKey.addr walletSlot.slot)))
        amountA { s with events := s.events ++
          [{ name := "Redeemed", args := [amountA, amountB],
             indexedArgs := [addressToWord s.sender, addressToWord recipient] }] }
        = @ContractResult.success Unit ()
          (S1 (evState s s.sender recipient amountA amountB) s.sender wallet amountA) := by
    rw [h_walletW]
    exact Contract.eq_of_run_success
      (Proofs.System.transferFrom_unfold_other
        (evState s s.sender recipient amountA amountB)
        balASlot allowASlot s.sender wallet amountA h_allowA h_notMaxA h_balA h_neA h_noOvfA)
  -- Leg B preconditions pass through the event update and leg A
  -- (both touch only events and token-A slots).
  have h_allowB_S1 :
      (S1 (evState s s.sender recipient amountA amountB) s.sender wallet amountA).storageMap2
        allowBSlot.slot wallet s.thisAddress ≥ amountB := by
    simp [S1, evState, ContractState.storage, ContractState.storageMap2,
      ContractState.writeMap, ContractState.writeMap2]; exact h_allowB
  have h_notMaxB_S1 :
      (S1 (evState s s.sender recipient amountA amountB) s.sender wallet amountA).storageMap2
        allowBSlot.slot wallet s.thisAddress ≠ MAX_UINT256 := by
    simp [S1, evState, ContractState.storage, ContractState.storageMap2,
      ContractState.writeMap, ContractState.writeMap2]; exact h_notMaxB
  have h_balB_S1 :
      (S1 (evState s s.sender recipient amountA amountB) s.sender wallet amountA).storageMap
        balBSlot.slot wallet ≥ amountB := by
    simp [S1, evState, ContractState.storage, ContractState.storageMap,
      ContractState.writeMap, ContractState.writeMap2]; exact h_balB
  have h_noOvfB_S1 :
      ((S1 (evState s s.sender recipient amountA amountB) s.sender wallet amountA).storageMap
        balBSlot.slot recipient : Nat) + (amountB : Nat) ≤ MAX_UINT256 := by
    simp [S1, evState, ContractState.storage, ContractState.storageMap,
      ContractState.writeMap, ContractState.writeMap2]; exact h_noOvfB
  -- Leg B: wallet → recipient on the post-leg-A state. The wallet read is
  -- still the one from `s` (leg A touches only token-A slots and events).
  have hTF2 : transferFrom balBSlot allowBSlot
        (wordToAddress (s.storageWords (StorageKey.addr walletSlot.slot)))
        recipient amountB
        (S1 (evState s s.sender recipient amountA amountB) s.sender wallet amountA)
        = @ContractResult.success Unit ()
          (finalState (S1 (evState s s.sender recipient amountA amountB) s.sender wallet amountA)
            wallet recipient amountB) := by
    rw [h_walletW]
    exact Contract.eq_of_run_success
      (Proofs.System.transferFrom_unfold_other
        (S1 (evState s s.sender recipient amountA amountB) s.sender wallet amountA)
        balBSlot allowBSlot wallet recipient amountB
        h_allowB_S1 h_notMaxB_S1 h_balB_S1 h_neB h_noOvfB_S1)
  -- Close: the verified chain shape at the concrete states.
  exact chain_shape amountA amountB recipient num den s
    (S1 (evState s s.sender recipient amountA amountB) s.sender wallet amountA)
    (finalState (S1 (evState s s.sender recipient amountA amountB) s.sender wallet amountA)
      wallet recipient amountB)
    h_posA h_posB h_num h_den h_amountB
    h_recipient_nonzero h_recipient_ne_this h_wordA
    h_wordB h_ne_wallet_ev hTF1 hTF2



/-! ## Corollaries: exact effects, no custody, conservation, immutability
    (P1/P3–P6 read off the success path)

`postState` is the success post-state produced by `redeemTo_success_run`;
each corollary is a statement about that post-state, so it applies to any
run the main theorem shows successful. -/

/-- The success post-state of a redemption: event append, leg A
    (token A: sender → wallet), leg B (token B: wallet → recipient). -/
abbrev postState (s : ContractState) (sender wallet recipient : Address)
    (amountA amountB : Uint256) : ContractState :=
  finalState (S1 (evState s sender recipient amountA amountB)
    sender wallet amountA) wallet recipient amountB

/-- A positive `BEq` test between two mapped ledger keys forces the slot
    components to be equal. -/
private theorem key_slot_of_beq {s1 s2 : Nat} {a1 a2 : Address}
    (h : (StorageKey.map s1 a1 == StorageKey.map s2 a2) = true) : s1 = s2 := by
  rw [beq_iff_eq, StorageKey.map.injEq] at h
  exact h.1

/-- A positive `BEq` test between two mapped ledger keys forces the address
    components to be equal. -/
private theorem key_addr_of_beq {s1 s2 : Nat} {a1 a2 : Address}
    (h : (StorageKey.map s1 a1 == StorageKey.map s2 a2) = true) : a1 = a2 := by
  rw [beq_iff_eq, StorageKey.map.injEq] at h
  exact h.2

/-- A positive `BEq` test against a nested-mapping key forces the root slot
    components to be equal. -/
private theorem key2_slot_of_beq {s1 s2 : Nat} {a1 a2 b2 : Address}
    (h : (StorageKey.map s1 a1 == StorageKey.map2 s2 a2 b2) = true) : s1 = s2 := by
  rw [beq_iff_eq] at h
  exact absurd h (by simp)

/-- A positive `BEq` test against a nested-mapping key forces the read
    address to equal the first nested key. -/
private theorem key_addr2_of_beq {s1 s2 : Nat} {a1 a2 b2 : Address}
    (h : (StorageKey.map s1 a1 == StorageKey.map2 s2 a2 b2) = true) : a1 = a2 := by
  rw [beq_iff_eq] at h
  exact absurd h (by simp)

/-- Numeric slot-distinctness facts for the Migraine layout
    (`balA = 5`, `allowA = 6`, `balB = 7`, `allowB = 8`). -/
private theorem slotB_ne_A : balBSlot.slot ≠ balASlot.slot := by decide
private theorem slotB_ne_allowA : balBSlot.slot ≠ allowASlot.slot := by decide
private theorem slotA_ne_B : balASlot.slot ≠ balBSlot.slot := by decide
private theorem slotA_ne_allowB : balASlot.slot ≠ allowBSlot.slot := by decide

/-- Pointwise pass-through: reads of a ledger slot other than the two token
    ledgers (and the two allowance sheets) see the pre-state through both
    legs. -/
private theorem readMap_postState_unchanged (s : ContractState)
    (sender wallet recipient : Address) (amountA amountB : Uint256)
    (ledgerSlot : StorageSlot (Address → Uint256))
    (hA : ledgerSlot.slot ≠ balASlot.slot) (hB : ledgerSlot.slot ≠ balBSlot.slot)
    (hAA : ledgerSlot.slot ≠ allowASlot.slot) (hAB : ledgerSlot.slot ≠ allowBSlot.slot)
    (a : Address) :
    (postState s sender wallet recipient amountA amountB).storageMap ledgerSlot.slot a
      = s.storageMap ledgerSlot.slot a := by
  simp only [postState, S1, finalState, ContractState.storageMap, ContractState.readMap,
    ContractState.writeMap, ContractState.writeMap2, StorageKey.map, StorageKey.map2, evState]
  · split <;> rename_i h
    · exact absurd (key_slot_of_beq h) hB
    · split <;> rename_i h
      · exact absurd (key_slot_of_beq h) hB
      · split <;> rename_i h
        · exact absurd (key2_slot_of_beq h) hAB
        · split <;> rename_i h
          · exact absurd (key_slot_of_beq h) hA
          · split <;> rename_i h
            · exact absurd (key_slot_of_beq h) hA
            · split <;> rename_i h
              · exact absurd (key2_slot_of_beq h) hAA
              · rfl

/-- Reads of the token-B ledger at a non-endpoint address see the pre-state. -/
private theorem readMap_balB_post_other (s : ContractState)
    (sender wallet recipient : Address) (amountA amountB : Uint256)
    (a : Address) (h1 : a ≠ wallet) (h2 : a ≠ recipient) :
    (postState s sender wallet recipient amountA amountB).storageMap balBSlot.slot a
      = s.storageMap balBSlot.slot a := by
  simp only [postState, S1, finalState, ContractState.storageMap, ContractState.readMap,
    ContractState.writeMap, ContractState.writeMap2, StorageKey.map, StorageKey.map2, evState]
  · split <;> rename_i h
    · exact absurd (key_addr_of_beq h) h2
    · split <;> rename_i h
      · exact absurd (key_addr_of_beq h) h1
      · split <;> rename_i h
        · exact absurd (key_addr2_of_beq h) h1
        · split <;> rename_i h
          · exact absurd (key_addr_of_beq h) h1
          · split <;> rename_i h
            · exact absurd (key_slot_of_beq h) slotB_ne_A
            · split <;> rename_i h
              · exact absurd (key2_slot_of_beq h) slotB_ne_allowA
              · rfl

/-- Reads of the token-A ledger at a non-endpoint address see the pre-state. -/
private theorem readMap_balA_post_other (s : ContractState)
    (sender wallet recipient : Address) (amountA amountB : Uint256)
    (a : Address) (h1 : a ≠ sender) (h2 : a ≠ wallet) :
    (postState s sender wallet recipient amountA amountB).storageMap balASlot.slot a
      = s.storageMap balASlot.slot a := by
  simp only [postState, S1, finalState, ContractState.storageMap, ContractState.readMap,
    ContractState.writeMap, ContractState.writeMap2, StorageKey.map, StorageKey.map2, evState]
  · split <;> rename_i h
    · exact absurd (key_slot_of_beq h) slotA_ne_B
    · split <;> rename_i h
      · exact absurd (key_slot_of_beq h) slotA_ne_B
      · split <;> rename_i h
        · exact absurd (key2_slot_of_beq h) slotA_ne_allowB
        · split <;> rename_i h
          · exact absurd (key_addr_of_beq h) h2
          · split <;> rename_i h
            · exact absurd (key_addr_of_beq h) h1
            · split <;> rename_i h
              · exact absurd (key_addr2_of_beq h) h1
              · rfl

/-! ### Exact balance effects (P1 rate + P3 positive half)

Condition order in the unfolded reads (verified against the kernel's goal
print): the `finalState` layer first — `map balB recipient` (add),
`map balB wallet` (sub), `map2 allowB wallet this` (sub) — then the `S1`
layer — `map balA wallet` (add), `map balA sender` (sub),
`map2 allowA sender this` (sub) — then the event-state pass-through. -/

/-- The recipient's token-B balance gains exactly the payout. -/
theorem balB_recipient_post (s : ContractState) (sender wallet recipient : Address)
    (amountA amountB : Uint256) (h_ne : recipient ≠ wallet) :
    (postState s sender wallet recipient amountA amountB).storageMap balBSlot.slot recipient
      = s.storageMap balBSlot.slot recipient + amountB := by
  simp only [postState, S1, finalState, ContractState.storageMap, ContractState.readMap,
    ContractState.writeMap, ContractState.writeMap2, StorageKey.map, StorageKey.map2, evState]
  · split <;> rename_i h
    · refine congrArg (EVM.Uint256.add · amountB) ?_
      · split <;> rename_i h
        · exact absurd (key_slot_of_beq h) slotB_ne_A
        · split <;> rename_i h
          · exact absurd (key_slot_of_beq h) slotB_ne_A
          · split <;> rename_i h
            · exact absurd (key2_slot_of_beq h) slotB_ne_allowA
            · rfl
    · exact absurd h (by simp)

/-- The wallet's token-B balance loses the payout and gains the token-A
    inflow: net `−amountB +amountA` across the two legs. -/
theorem balB_wallet_post (s : ContractState) (sender wallet recipient : Address)
    (amountA amountB : Uint256) (h_ne : wallet ≠ recipient) :
    (postState s sender wallet recipient amountA amountB).storageMap balBSlot.slot wallet
      = s.storageMap balBSlot.slot wallet - amountB := by
  simp only [postState, S1, finalState, ContractState.storageMap, ContractState.readMap,
    ContractState.writeMap, ContractState.writeMap2, StorageKey.map, StorageKey.map2, evState]
  · split <;> rename_i h
    · exact absurd (key_addr_of_beq h) h_ne
    · split <;> rename_i h
      · refine congrArg (EVM.Uint256.sub · amountB) ?_
        · split <;> rename_i h
          · exact absurd (key_slot_of_beq h) slotB_ne_A
          · split <;> rename_i h
            · exact absurd (key_slot_of_beq h) slotB_ne_A
            · split <;> rename_i h
              · exact absurd (key2_slot_of_beq h) slotB_ne_allowA
              · rfl
      · exact absurd h (by simp)

/-- The redeemer's token-A balance loses exactly the input amount. -/
theorem balA_sender_post (s : ContractState) (sender wallet recipient : Address)
    (amountA amountB : Uint256) (h_ne : sender ≠ wallet) :
    (postState s sender wallet recipient amountA amountB).storageMap balASlot.slot sender
      = s.storageMap balASlot.slot sender - amountA := by
  simp only [postState, S1, finalState, ContractState.storageMap, ContractState.readMap,
    ContractState.writeMap, ContractState.writeMap2, StorageKey.map, StorageKey.map2, evState]
  · split <;> rename_i h
    · exact absurd (key_slot_of_beq h) slotA_ne_B
    · split <;> rename_i h
      · exact absurd (key_slot_of_beq h) slotA_ne_B
      · split <;> rename_i h
        · exact absurd (key2_slot_of_beq h) slotA_ne_allowB
        · split <;> rename_i h
          · exact absurd (key_addr_of_beq h) h_ne
          · split <;> rename_i h
            · rfl
            · exact absurd h (by simp)

/-- The wallet's token-A balance gains exactly the input amount. -/
theorem balA_wallet_post (s : ContractState) (sender wallet recipient : Address)
    (amountA amountB : Uint256) (h_ne : sender ≠ wallet) :
    (postState s sender wallet recipient amountA amountB).storageMap balASlot.slot wallet
      = s.storageMap balASlot.slot wallet + amountA := by
  simp only [postState, S1, finalState, ContractState.storageMap, ContractState.readMap,
    ContractState.writeMap, ContractState.writeMap2, StorageKey.map, StorageKey.map2, evState]
  · split <;> rename_i h
    · exact absurd (key_slot_of_beq h) slotA_ne_B
    · split <;> rename_i h
      · exact absurd (key_slot_of_beq h) slotA_ne_B
      · split <;> rename_i h
        · exact absurd (key2_slot_of_beq h) slotA_ne_allowB
        · split <;> rename_i h
          · rfl
          · exact absurd h (by simp)

/-- **P4 (no custody).** The recipient's token-A balance is untouched:
    a redemption only moves balances between the two token ledgers. -/
theorem no_custody (s : ContractState) (sender wallet recipient : Address)
    (amountA amountB : Uint256) (h_ne : recipient ≠ wallet) (h_neS : recipient ≠ sender) :
    (postState s sender wallet recipient amountA amountB).storageMap balASlot.slot recipient
      = s.storageMap balASlot.slot recipient :=
  readMap_balA_post_other s sender wallet recipient amountA amountB recipient
    h_neS h_ne

/-- **P4 (strong form).** Any ledger slot other than the two token ledgers
    is untouched by a redemption: there is no third balance sheet the
    contract could use to hold funds. -/
theorem other_slot_unchanged (s : ContractState) (sender wallet recipient : Address)
    (amountA amountB : Uint256)
    (ledgerSlot : StorageSlot (Address → Uint256))
    (hA : ledgerSlot.slot ≠ balASlot.slot) (hB : ledgerSlot.slot ≠ balBSlot.slot)
    (hAA : ledgerSlot.slot ≠ allowASlot.slot) (hAB : ledgerSlot.slot ≠ allowBSlot.slot)
    (a : Address) :
    (postState s sender wallet recipient amountA amountB).storageMap ledgerSlot.slot a
      = s.storageMap ledgerSlot.slot a :=
  readMap_postState_unchanged s sender wallet recipient amountA amountB ledgerSlot hA hB hAA hAB a

/-! ### P5 — conservation over any address list -/

/-- **P5 (token B).** The token-B leg is a plain transfer wallet → recipient:
    over any address list the token-B ledger is conserved up to the two
    endpoints. -/
theorem preserves_balB_sum (s : ContractState) (sender wallet recipient : Address)
    (amountA amountB : Uint256) (h_ne : wallet ≠ recipient) :
    ∀ addrs : List Address,
      (addrs.map (fun a =>
          (postState s sender wallet recipient amountA amountB).storageMap balBSlot.slot a)).sum
        + Verity.Proofs.Stdlib.ListSum.countOccU wallet addrs * amountB
      = (addrs.map (s.storageMap balBSlot.slot)).sum
        + Verity.Proofs.Stdlib.ListSum.countOccU recipient addrs * amountB := by
  refine Verity.Proofs.Stdlib.ListSum.map_sum_transfer_eq
    (s.storageMap balBSlot.slot)
    (fun a => (postState s sender wallet recipient amountA amountB).storageMap balBSlot.slot a)
    wallet recipient amountB h_ne ?_ ?_ ?_
  · exact balB_wallet_post s sender wallet recipient amountA amountB h_ne
  · exact balB_recipient_post s sender wallet recipient amountA amountB h_ne.symm
  · exact fun a ha hb => readMap_balB_post_other s sender wallet recipient amountA amountB a ha hb

/-- **P5 (token A).** Token A is only ever pulled from the redeemer into the
    wallet: over any address list the token-A ledger is conserved up to the
    two endpoints (post sender lost `amountA`, post wallet gained it). -/
theorem preserves_balA_sum (s : ContractState) (sender wallet recipient : Address)
    (amountA amountB : Uint256) (h_ne : sender ≠ wallet) :
    ∀ addrs : List Address,
      (addrs.map (fun a =>
          (postState s sender wallet recipient amountA amountB).storageMap balASlot.slot a)).sum
        + Verity.Proofs.Stdlib.ListSum.countOccU sender addrs * amountA
      = (addrs.map (s.storageMap balASlot.slot)).sum
        + Verity.Proofs.Stdlib.ListSum.countOccU wallet addrs * amountA := by
  refine Verity.Proofs.Stdlib.ListSum.map_sum_transfer_eq
    (s.storageMap balASlot.slot)
    (fun a => (postState s sender wallet recipient amountA amountB).storageMap balASlot.slot a)
    sender wallet amountA h_ne ?_ ?_ ?_
  · exact balA_sender_post s sender wallet recipient amountA amountB h_ne
  · exact balA_wallet_post s sender wallet recipient amountA amountB h_ne
  · exact fun a ha hb => readMap_balA_post_other s sender wallet recipient amountA amountB a ha hb

/-! ### P6 — configuration immutability -/

/-- **P6.** A redemption writes no configuration: token addresses, wallet,
    and rate slots read back unchanged in the post-state. -/
theorem preserves_config (s : ContractState) (sender wallet recipient : Address)
    (amountA amountB : Uint256) :
    (postState s sender wallet recipient amountA amountB).storageAddr tokenASlot.slot
      = s.storageAddr tokenASlot.slot
    ∧ (postState s sender wallet recipient amountA amountB).storageAddr tokenBSlot.slot
      = s.storageAddr tokenBSlot.slot
    ∧ (postState s sender wallet recipient amountA amountB).storageAddr walletSlot.slot
      = s.storageAddr walletSlot.slot
    ∧ (postState s sender wallet recipient amountA amountB).storage rateNumSlot.slot
      = s.storage rateNumSlot.slot
    ∧ (postState s sender wallet recipient amountA amountB).storage rateDenSlot.slot
      = s.storage rateDenSlot.slot := by
  refine ⟨?_, ?_, ?_, ?_, ?_⟩ <;>
    simp [postState, S1, finalState, ContractState.storage, ContractState.storageAddr,
      ContractState.readSlot, ContractState.readAddrSlot,
      ContractState.writeMap, ContractState.writeMap2, StorageKey.slot, StorageKey.addr,
      evState]

/-! ## `redeem` is `redeemTo` to the caller -/

/-- The `redeem(amountA)` entrypoint is definitionally `redeemTo(amountA,
    msg.sender)`: the two calls produce identical results and post-states
    from any state, so every `redeemTo` theorem (success post-state,
    revert atomicity, conservation) transfers verbatim. -/
theorem redeem_eq_redeemTo_self (s : ContractState) (amountA : Uint256) :
    (redeem amountA).run s = (redeemTo amountA s.sender).run s :=
  bind_run_success msgSender (fun sender => redeemTo amountA sender) s s.sender
    (msgSender_run s)

end Contracts.Migraine.Proofs.RedeemTo
