import Contracts.Common

namespace Contracts

open Verity hiding pure bind
open Verity.EVM.Uint256
open Verity.Stdlib.Math

/-!
# `Migraine` — reference model

The deployed Solidity contract (`src/Migraine.sol`) is *stateless*: it
moves `tokenA` from the caller to an immutable vault wallet and `tokenB` from
that wallet back to the caller using two `transferFrom` calls. External-call
mechanics sit on Verity's documented trust boundary, so that they can be
isolated from the proof surface this model exposes the *provable core* of the
redeemer as an explicit two-slot state machine:

* `remainingInventoryB` — the vault's authorised `tokenB` inventory (the
  on-chain analogue is the ERC-20 allowance the vault grants the redeemer).
* `totalRedeemedA` — cumulative `tokenA` redeemed (the on-chain analogue is the
  vault's `tokenA` balance).

`redeem` performs the fixed-rate payout with checked, conservation-preserving
accounting:
1. reject a zero input,
2. compute `amountB = floor(amountA * rateNumerator / rateDenominator)`,
3. reject a zero output (dust that would round to nothing),
4. require the inventory to cover `amountB`,
5. debit the inventory by `amountB` and credit `totalRedeemedA` by `amountA`.

The rate is a pair of compile-time constants, mirroring the Solidity
`immutable` values: it can never be changed after deployment.

See `../README.md` for the exact correspondence to the Solidity contract and
the trust-boundary split.
-/
verity_contract Migraine where
  storage
    remainingInventoryB : Uint256 := slot 0
    totalRedeemedA       : Uint256 := slot 1

  constants
    rateNumerator   : Uint256 := 25
    rateDenominator : Uint256 := 10

  constructor (initialInventory : Uint256) := do
    setStorage remainingInventoryB initialInventory
    setStorage totalRedeemedA 0

  -- Preview the token B payout for a token A input at the fixed rate.
  function preview (amountA : Uint256) : Uint256 := do
    return (mulDivDown amountA rateNumerator rateDenominator)

  -- One-way redemption: token A in, token B out, at the immutable rate.
  function redeem (amountA : Uint256) : Unit := do
    require (amountA > 0) "ZeroAmount"
    let amountB := mulDivDown amountA rateNumerator rateDenominator
    require (amountB > 0) "ZeroOutput"
    let inventory ← getStorage remainingInventoryB
    require (inventory >= amountB) "InsufficientInventory"
    let newInventory ← requireSomeUint (safeSub inventory amountB) "Inventory underflow"
    let redeemed ← getStorage totalRedeemedA
    let newRedeemed ← requireSomeUint (safeAdd redeemed amountA) "Redeemed overflow"
    setStorage remainingInventoryB newInventory
    setStorage totalRedeemedA newRedeemed

end Contracts
