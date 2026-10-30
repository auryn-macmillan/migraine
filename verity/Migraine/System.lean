import Contracts.Common
import Verity.Core
import Verity.Macro

namespace Migraine.System

open Verity hiding pure bind
open Verity.EVM.Uint256
open Verity.Stdlib.Math

/-!
# `MigraineSystem` — closed-system model of the deployed contract

The reference model in `Migraine.lean` isolates the redeemer's arithmetic core
as a two-slot state machine. It deliberately does *not* model the token
ledgers, so it cannot express conservation, no-custody, or recipient-safety
properties about the real system.

This module models the *whole system the contract participates in*: the
redeemer logic of `src/Migraine.sol` with the two standard ERC-20 ledgers it
touches inlined into a single state. The redeemer itself remains stateless —
its configuration lives in slots 0–4 (written once by `deploy`, never
again; see the immutability proofs) and the token balances/allowances live in
slots 5–8, written only by the inlined `transferFrom` logic.

Trust boundary (identical to the rest of Verity):
* `transferFrom` below is the exact semantics of OpenZeppelin v5.1.0
  `ERC20._spendAllowance` + `ERC20._update` for a standard ERC-20:
  allowance check with the max-uint256 infinite-approval rule, balance check,
  checked recipient addition (which cannot fire for a standard token because
  supply fits in a word), debit, credit, conditional allowance debit, and the
  self-transfer no-op. Non-standard tokens (fee-on-transfer, reentrant
  callbacks) are outside the model, exactly as they are outside the Solidity
  SafeERC20 assumptions.
* `mulDiv512Down?` is Verity's model of `Math.mulDiv(_, _, _, Floor)`:
  full 512-bit intermediate precision, `none` exactly when the quotient
  overflows (Solidity `Panic(0x11)`), divisor zero mapped to `none`.
* External-call mechanics (`safeTransferFrom`'s low-level call) are replaced
  by the inlined ledger semantics; this is the documented Verity boundary for
  cross-contract composition.

Everything provable about the deployed contract's *logic* is proved here:
rate correctness (P1/P2), atomicity (P3), no-custody (P4), conservation
(P5), configuration immutability (P6), and reentrancy safety via statelessness
(P7) — see `Proofs/System.lean`.
-/

/-! ## Storage layout -/

/-- Token A address (config; slot 0). -/
def tokenASlot : StorageSlot Address := ⟨0⟩
/-- Token B address (config; slot 1). -/
def tokenBSlot : StorageSlot Address := ⟨1⟩
/-- Vault wallet address (config; slot 2). -/
def walletSlot : StorageSlot Address := ⟨2⟩
/-- Rate numerator (config; slot 3). -/
def rateNumSlot : StorageSlot Uint256 := ⟨3⟩
/-- Rate denominator (config; slot 4). -/
def rateDenSlot : StorageSlot Uint256 := ⟨4⟩
/-- Token A balances (ledger; slot 5). -/
def balASlot : StorageSlot (Address → Uint256) := ⟨5⟩
/-- Token A allowances, `owner ↦ spender ↦ amount` (ledger; slot 6).
    The redeemer is always the spender, mirroring the real system where the
    spender key is `address(this)`. -/
def allowASlot : StorageSlot (Address → Address → Uint256) := ⟨6⟩
/-- Token B balances (ledger; slot 7). -/
def balBSlot : StorageSlot (Address → Uint256) := ⟨7⟩
/-- Token B allowances (ledger; slot 8); spender is the redeemer. -/
def allowBSlot : StorageSlot (Address → Address → Uint256) := ⟨8⟩

/-- The five configuration slots, written only by `constructor`. -/
def configSlots : List Nat := [0, 1, 2, 3, 4]

/-- Every slot the system may ever write. -/
def systemSlots : List Nat := [0, 1, 2, 3, 4, 5, 6, 7, 8]

/-! ## Configuration accessors -/

def getTokenA : Contract Address := getStorageAddr tokenASlot
def getTokenB : Contract Address := getStorageAddr tokenBSlot
def getWallet : Contract Address := getStorageAddr walletSlot
def getRateNum : Contract Uint256 := getStorage rateNumSlot
def getRateDen : Contract Uint256 := getStorage rateDenSlot

/-! ## Well-formed configurations -/

/-- A state whose configuration is exactly what a successful `deploy`
    call produces: distinct non-zero tokens, a non-zero wallet that is neither
    a token nor the contract itself, and a rate with non-zero components.

    On-chain these are enforced by the constructor's `require`s; the wallet
    can never be the redeemer because `address(this)` is not known to be the
    wallet at construction time and `WalletIsSelf` rejects it explicitly. -/
def ValidConfig (s : ContractState) : Prop :=
  let tokenA := s.storageAddr 0
  let tokenB := s.storageAddr 1
  let wallet := s.storageAddr 2
  tokenA ≠ 0 ∧ tokenB ≠ 0 ∧ tokenA ≠ tokenB ∧
  wallet ≠ 0 ∧ wallet ≠ s.thisAddress ∧ wallet ≠ tokenA ∧ wallet ≠ tokenB ∧
  s.storage 3 ≠ 0 ∧ s.storage 4 ≠ 0

/-! ## Operations -/

/-- Mirrors the `Migraine` constructor (`deploy`), check for check, in source order:
    `ZeroAddress`, `IdenticalTokens`, `ZeroWallet`, `WalletIsSelf`,
    `InvalidWallet`, `InvalidRate`, then the five immutable writes. -/
def deploy (tokenA tokenB wallet : Address) (num den : Uint256) : Contract Unit := do
  require (tokenA != 0) "ZeroAddress"
  require (tokenB != 0) "ZeroAddress"
  require (tokenA != tokenB) "IdenticalTokens"
  require (wallet != 0) "ZeroWallet"
  let thisAddr ← contractAddress
  require (wallet != thisAddr) "WalletIsSelf"
  require (wallet != tokenA) "InvalidWallet"
  require (wallet != tokenB) "InvalidWallet"
  require (num != 0) "InvalidRate"
  require (den != 0) "InvalidRate"
  setStorageAddr tokenASlot tokenA
  setStorageAddr tokenBSlot tokenB
  setStorageAddr walletSlot wallet
  setStorage rateNumSlot num
  setStorage rateDenSlot den

/-- Mirrors `previewRedeem`: full-precision floor payout, reverting exactly
    when `Math.mulDiv` would panic (quotient overflow). Returns 0 for inputs
    `redeemTo` would reject, exactly like the Solidity view. -/
def previewRedeem (amountA : Uint256) : Contract Uint256 := do
  let num ← getStorage rateNumSlot
  let den ← getStorage rateDenSlot
  requireSomeUint (mulDiv512Down? amountA num den) "MulDivOverflow"

/-- Standard ERC-20 `transferFrom(from, to, amount)` with the redeemer as
    spender, mirroring OpenZeppelin v5.1.0 `_spendAllowance` + `_update`:
    allowance check (max-uint256 = infinite approval, never decremented),
    balance check, self-transfer no-op, checked recipient add, debit, credit.

    The checked recipient add mirrors the model's arithmetic safety; for a
    standard ERC-20 it can never fire because total supply fits in a word. -/
def transferFrom (balSlot : StorageSlot (Address → Uint256))
    (allowSlot : StorageSlot (Address → Address → Uint256))
    (srcAddr dstAddr : Address) (amount : Uint256) : Contract Unit := do
  let spender ← contractAddress
  let currentAllowance ← getMapping2 allowSlot srcAddr spender
  require (currentAllowance >= amount) "ERC20InsufficientAllowance"
  if currentAllowance != MAX_UINT256 then
    setMapping2 allowSlot srcAddr spender (sub currentAllowance amount)
  let fromBalance ← getMapping balSlot srcAddr
  require (fromBalance >= amount) "ERC20InsufficientBalance"
  if srcAddr == dstAddr then
    pure ()
  else
    let toBalance ← getMapping balSlot dstAddr
    let newToBalance ← requireSomeUint (safeAdd toBalance amount) "ERC20BalanceOverflow"
    setMapping balSlot srcAddr (sub fromBalance amount)
    setMapping balSlot dstAddr newToBalance

/-- Mirrors `redeemTo(amountA, to)` statement for statement, in source order:
    `ZeroAmount`, full-precision payout (`MulDivOverflow` on panic),
    `ZeroOutput`, the five-way recipient blacklist, the `Redeemed` event
    (checks-effects-interactions), then the two `transferFrom` calls —
    token A from the caller into the wallet, token B from the wallet to the
    recipient. -/
def redeemTo (amountA : Uint256) (recipient : Address) : Contract Uint256 := do
  let sender ← msgSender
  let thisAddr ← contractAddress
  let tokenA ← getTokenA
  let tokenB ← getTokenB
  let wallet ← getWallet
  let num ← getRateNum
  let den ← getRateDen
  require (amountA > 0) "ZeroAmount"
  let amountB ← requireSomeUint (mulDiv512Down? amountA num den) "MulDivOverflow"
  require (amountB > 0) "ZeroOutput"
  require (recipient != 0) "InvalidRecipient"
  require (recipient != thisAddr) "InvalidRecipient"
  require (recipient != tokenA) "InvalidRecipient"
  require (recipient != tokenB) "InvalidRecipient"
  require (recipient != wallet) "InvalidRecipient"
  emitEvent "Redeemed" [amountA, amountB] [addressToWord sender, addressToWord recipient]
  transferFrom balASlot allowASlot sender wallet amountA
  transferFrom balBSlot allowBSlot wallet recipient amountB
  return amountB

/-- Mirrors `redeem(amountA)`: `redeemTo` to the caller. -/
def redeem (amountA : Uint256) : Contract Uint256 := do
  let sender ← msgSender
  redeemTo amountA sender

end Migraine.System