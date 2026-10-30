# Verity formalization — `Migraine`

This directory holds a [Verity](https://veritylang.com/) formal specification,
reference model and machine-checked proofs for the `Migraine` contract.
Verity is a Lean 4 EDSL that compiles smart contracts to EVM bytecode and ties
each implementation to a `Prop`-valued specification with a proof.

## Files

```
Contracts/Migraine/
  Migraine.lean              reference model (`verity_contract` block)
  Spec.lean                  formal specification (`redeem_spec`, `preview_spec`, ...)
  Invariants.lean            well-formedness invariant
  System.lean                closed-system model: `redeemTo` with inlined
                             ERC-20 ledgers (token A/B balances + allowances,
                             slots 5-8) and deploy-once config (slots 0-4)
  Proofs/Basic.lean          `redeem_meets_spec`, `preview_meets_spec`, ...
  Proofs/Correctness.lean    guard/revert behaviour, well-formedness
  Proofs/System.lean         closed-system lemmas: deploy meets spec, preview,
                             revert atomicity (revert discards all writes)
  Proofs/RedeemTo.lean       closed-system success path + P1-P6 corollaries
  Proofs/AxiomCheck.lean     `#print axioms` gate for the redeem-path theorems
Contracts/Migraine.lean      module re-export
```

## What is proven

- `redeem_meets_spec` — every **successful** `redeem(amountA)`:
  - debits `remainingInventoryB` by exactly `payout amountA`
    (`= mulDivDown amountA rateNumerator rateDenominator`, i.e. the fixed rate,
    floored),
  - credits `totalRedeemedA` by exactly `amountA`,
  - leaves every other uint256 slot, all address storage, all mapping storage
    and the whole call context unchanged.
- `preview_meets_spec` — `preview(amountA)` returns exactly the fixed-rate
  payout.
- `redeem_debits_preview` — the amount debited from the inventory by `redeem` is
  exactly `preview(amountA)`; the two entrypoints cannot diverge.
- `redeem_reverts_zero_amount`, `redeem_reverts_zero_output`,
  `redeem_reverts_insufficient_inventory` — the guard conditions revert and do
  not mutate state in the model's checks-before-effects ordering.
- `redeem_preserves_wellformedness` — successful redemption preserves context
  well-formedness.

The rate is a pair of compile-time **constants**, mirroring the Solidity
`immutable` parameters: no proof obligation can change them, which is the Lean
statement of P6 (immutability).

## Correspondence to the Solidity contract and the trust boundary

The deployed Solidity contract is **stateless**: `redeem`/`redeemTo` perform two
external `transferFrom` calls (token A from caller to vault, token B from vault
to the recipient). Verity classifies external-call mechanics (`call`/`staticcall`,
returndata plumbing, ECMs) and bytecode immutables as an explicit **trust
boundary** rather than a fully proof-modelled fragment (see the Verity
*Capabilities & Limits* and *Trust Model* pages). To keep the verified surface
meaningful we therefore model the redeemer's *accounting core*:

| Solidity reality | Verity model |
| --- | --- |
| Vault's `tokenB` allowance to the redeemer | `remainingInventoryB` (slot 0) |
| Vault's accumulated `tokenA` balance | `totalRedeemedA` (slot 1) |
| Immutable `rateNumerator` / `rateDenominator` | constants |
| `redeem` / `redeemTo` (recipient selection) | out of scope (same accounting) |
| Two `safeTransferFrom` calls | out of scope (trust boundary) |

The closed system (`System.lean`) lifts the last two rows: it models the
ledgers themselves, so the redemption legs are proof-modelling transfers:

| Solidity reality | Closed-system model |
| --- | --- |
| `tokenA` / `tokenB` / `vaultWallet` / rate | config slots 0-4, written once at deploy |
| `tokenA.balanceOf` / `allowance` (of redeemer) | `balASlot` (5) / `allowASlot` (6) |
| `tokenB.balanceOf` / `allowance` (of vault) | `balBSlot` (7) / `allowBSlot` (8) |
| The two `safeTransferFrom` calls | inlined `transferFrom` legs over those ledgers |

`redeemTo` shares the identical accounting as `redeem` and only changes the
`tokenB` recipient. Because the contract holds no mutable state, no reentrancy
guard is used (or modelled); a reentrant token can only produce additional
independent redemptions.

The theorem therefore establishes the fixed-rate arithmetic and the
conservation/accounting semantics for the idealized model — P1 (rate
correctness) and P6 (immutability as compile-time constants).

## Closed-system proof of `redeemTo` (P1-P6 end to end)

`System.lean` models the contract *with its environment's accounting*: the two
ERC-20 legs are inlined as ledger transfers over slots 5-8 (`tokenA`
balance/allowance, `tokenB` balance/allowance), and the config (token
addresses, vault wallet, rate numerator/denominator) is deploy-once state in
slots 0-4. `Proofs/RedeemTo.lean` then proves, for the real `redeemTo`
statement sequence (guards, floor payout via `mulDiv512Down?`, five-way
recipient blacklist, `Redeemed` event, two `transferFrom` legs):

- `redeemTo_success_run` (P1 + P3 positive half) — under positive amounts,
  sufficient non-MAX allowances and balances, and a recipient off the
  blacklist, `redeemTo` succeeds paying exactly the floored quotient
  `amountB`; token A moves sender -> vault, token B moves vault -> recipient,
  both allowances are consumed, and the `Redeemed` event is appended.
- `redeemTo_success_run_max` — the same success path for `MAX_UINT256`
  ("infinite") approvals: identical payout and balance movements, but neither
  allowance is consumed, matching OpenZeppelin `_spendAllowance` max-skip
  semantics (and the `transferFrom_unfold_max` model branch).
- Exact pointwise balance effects — recipient `+amountB` of token B, vault
  `-amountB +amountA`, sender `-amountA` of token A, every other address
  unchanged on both tokens.
- `no_custody` (P4) — the recipient's token-A balance is untouched; the
  redemption never pushes token A to anyone but the vault.
- `preserves_balA_sum` / `preserves_balB_sum` (P5) — each token's total over
  any address list is conserved up to the transfer endpoints
  (`ListSum.map_sum_transfer_eq`).
- `preserves_config` (P6) — redemption writes no config slot.
- `redeemTo_revert_state_unchanged` (P3, `Proofs/System.lean`) — any revert
  discards every write: rollback-by-construction in the model's
  checks-before-effects ordering.

- `redeem_eq_redeemTo_self` (P2) — `redeem(amountA)` is definitionally
  `redeemTo(amountA, msg.sender)`, so the single proven `redeemTo` path covers
  both entrypoints: there is no second code path and no way for token A to
  flow back toward the redeemer or any reverse direction.
- Idealized-model corollaries (`Proofs/Basic.lean`):
  `redeem_conserves_inventory`, `inventory_never_increases`,
  `redeemed_monotone` — the three SPEC properties previously cited but
  unproven are now derived from `redeem_meets_spec`.

P7 (reentrancy-harmless) remains structural: the contract holds no mutable
state a reentrant call could exploit. All of these are statements about the Verity model, not the
deployed bytecode; the external-call mechanics of the real `safeTransferFrom`
calls stay on Verity's trust boundary.

## Build it inside a Verity checkout

Clone Verity and copy these files in:

```bash
git clone https://github.com/lfglabs-dev/verity.git
cp -r verity/Contracts/Migraine      verity/Contracts/
cp    verity/Contracts/Migraine.lean verity/Contracts/
```

Then register the module (three one-line edits):

1. `lakefile.lean` — add to the `Contracts` library globs:
   ```lean
   .andSubmodules `Contracts.Migraine,
   ```
2. `Contracts.lean` — add:
   ```lean
   import Contracts.Migraine
   ```
3. `Contracts/Specs.lean` — add the import and the generated compiler model:
   ```lean
   import Contracts.Migraine
   -- ...
   def allSpecs : List CompilationModel := [
     -- ...
     Contracts.Migraine.spec,
     -- ...
   ]
   ```

Then verify the proofs and compile the artifact:

```bash
lake build Contracts.Migraine                       # model + all proofs
lake build Contracts.Migraine.Proofs.AxiomCheck     # prints axiom sets: expect only propext/Quot.sound
lake exe verity-compiler --manifest migraine.manifest -o artifacts/yul
grep -r "sorry" Contracts/Migraine/   # should be empty
```

where `migraine.manifest` contains one line:

```
Contracts.Migraine.Migraine
```

This repository was verified against Verity `leanprover/lean4:v4.31.0`: the
whole `Contracts` library builds successfully and the compiler emits
[`artifacts/Migraine.yul`](./artifacts/Migraine.yul). The
generated runtime performs the guards and the fixed-rate math exactly as
specified, e.g. `amountB := div(mul(amountA, 25), 10)`.

> The first `lake build` downloads the pinned Lean toolchain and Mathlib and can
> take 20–45 minutes; subsequent builds are incremental.

## Trust report

Because the reference model emits no external calls, it stays inside the proved
fragment. The *deployed* contract's external calls should be tracked with
`verity-compiler --trust-report` when compiling the full Solidity-equivalent
model; the accounting semantics here carry no `sorry` and no project-level
axioms.
