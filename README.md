# FixedRateRedeemer

A small, immutable, permissionless on-chain exchange: anyone can redeem
**token A** for **token B** at a **fixed rate**, in one direction only. The
token B inventory lives in a separate vault wallet (e.g. a Gnosis Safe), and the
redeemer contract never holds any tokens itself.

This repository contains four deliverables:

| Artifact | Location | Description |
| --- | --- | --- |
| Plain-language spec | [`SPEC.md`](./SPEC.md) | Requirements, invariants, assumptions. |
| Solidity contract + tests | [`src/`](./src), [`test/`](./test), [`script/`](./script) | Implementation, unit/integration/fuzz/invariant tests, deploy script. |
| Verity (Lean) formalization | [`verity/`](./verity) | Formal specification, reference model and machine-checked proofs. |
| Web frontend | [`web/`](./web) | Static UI to preview and execute redemptions. |

## How it works

```
             token A  ─────────────────────────────▶  ┌───────────────┐
   user ────────────────────────────────────────▶     │ vault wallet  │
     ▲                                               │ (e.g. Gnosis  │
     │            token B                            │   Safe)       │
     └───────────────────────────────────────────    └───────────────┘
                    FixedRateRedeemer (never holds tokens)
```

1. The user approves `FixedRateRedeemer` to spend `tokenA`.
2. The vault wallet approves `FixedRateRedeemer` to spend `tokenB` (its
   allowance is the hard on-chain cap).
3. The user calls `redeem(amountA)`:
   - `amountB = floor(amountA * rateNumerator / rateDenominator)`
   - `tokenA.transferFrom(user, vault, amountA)`
   - `tokenB.transferFrom(vault, user, amountB)`
   Both transfers commit atomically.

`tokenA`, `tokenB`, `wallet`, `rateNumerator` and `rateDenominator` are
`immutable`: they are fixed at deployment and can never change. There is no
owner, no pause and no way to run the exchange in reverse.

## Layout

```
src/FixedRateRedeemer.sol          the contract
script/Deploy.s.sol                deployment script (env-var configured)
test/
  FixedRateRedeemer.t.sol          unit + fuzz tests
  FixedRateRedeemerIntegration.t.sol   end-to-end lifecycle with a contract vault
  FixedRateRedeemerInvariant.t.sol     stateful invariant tests
  mocks/                           MockERC20, MockSafeWallet, ReentrantERC20
  utils/TestBase.sol               shared fixture
web/                               static frontend (ethers v6)
verity/                            Verity formal specification + proofs
SPEC.md                            plain-language specification
```

## Build & test

Requires [Foundry](https://book.getfoundry.sh/).

```bash
forge install            # install forge-std + openzeppelin (already vendored as submodules)
forge build
forge test               # unit + integration + fuzz
forge fmt --check
forge lint
```

The test suite covers:

- constructor validation and immutables,
- `previewRedeem` math (including 18→6 decimal mismatch and floor rounding),
- the happy path, exact allowance consumption, multiple users,
- zero-amount / zero-output / missing-approval / insufficient-balance reverts,
- reentrancy protection against a hostile ERC-20,
- stateful invariants: no custody, inventory conservation, rate never favours
  the redeemer.

## Deploy

```bash
export TOKEN_A=0x...
export TOKEN_B=0x...
export VAULT_WALLET=0x...        # a Gnosis Safe address
export RATE_NUMERATOR=25         # amountB = amountA * 25 / 10
export RATE_DENOMINATOR=10
forge script script/Deploy.s.sol --rpc-url "$RPC_URL" --broadcast
```

### Vault wallet checklist

Before users can redeem, the vault wallet must:

1. hold enough `tokenB` to cover the entire redeemable supply of `tokenA`, and
2. execute an ERC-20 `approve(FixedRateRedeemer, allowance)` transaction on
   `tokenB`.

The allowance is the effective cap: the redeemer can never pay out more `tokenB`
than the vault has approved. Choose an allowance equal to
`maxTokenA * rateNumerator / rateDenominator`.

## Frontend

```bash
cd web
python3 -m http.server 8080   # then open http://localhost:8080
```

Set the deployed address in `web/config.js`. See [`web/README.md`](./web/README.md).

## Formal verification (Verity)

[Verity](https://veritylang.com/) is a Lean 4 framework for writing smart
contracts that compile to EVM bytecode with machine-checked correctness proofs.
Because the deployed contract's behaviour hinges on external ERC-20 calls and
atomic token movement, the Verity artifact models the **provable accounting
core** — the fixed-rate payout, the inventory debit, the cumulative-redeemed
credit and the guard ordering — as a two-slot state machine, and proves that
every successful redemption debits the inventory by exactly the previewed payout
and preserves all other state.

See [`verity/README.md`](./verity/README.md) for what is proven, what sits on
Verity's trusted boundary, and how to build it inside a Verity checkout.

## Security notes and assumptions

- **Standard ERC-20s only.** Exact-amount accounting assumes no fee-on-transfer
  or rebasing tokens.
- **Vault inventory is operational.** The contract cannot inspect `tokenA`'s
  total supply or `tokenB` balances of the vault; the "full supply is
  redeemable" guarantee is provided by funding the vault and approving an
  adequate allowance.
- **No admin surface.** Immutable parameters and no owner means there is nothing
  to pause, upgrade, or compromise.
- **Rounding favours the vault.** Payouts round down; dust accrues to the vault.
- Reentrancy is blocked by OpenZeppelin's `ReentrancyGuard`.

## License

MIT (see [`LICENSE`](./LICENSE)).
