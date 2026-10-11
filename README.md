# Migraine

[![CI](https://github.com/auryn-macmillan/migraine/actions/workflows/ci.yml/badge.svg)](https://github.com/auryn-macmillan/migraine/actions/workflows/ci.yml)
[![coverage](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fauryn-macmillan%2Fmigraine%2Fbadges%2Fcoverage.json)](https://github.com/auryn-macmillan/migraine/actions/workflows/ci.yml)

> *Migraine* — because migrating from token A to token B is normally such a pain.

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
                    Migraine (never holds tokens)
```

1. The user approves `Migraine` to spend `tokenA`.
2. The vault wallet approves `Migraine` to spend `tokenB` (its
   allowance is the hard on-chain cap).
3. The user calls `redeem(amountA)` (or `redeemTo(amountA, to)` to send `tokenB`
   to someone else):
   - `amountB = floor(amountA * rateNumerator / rateDenominator)`
   - `tokenA.transferFrom(user, vault, amountA)`
   - `tokenB.transferFrom(vault, recipient, amountB)`
   Both transfers commit atomically.

`tokenA`, `tokenB`, `wallet`, `rateNumerator` and `rateDenominator` are
`immutable`: they are fixed at deployment and can never change. There is no
owner, no pause and no way to run the exchange in reverse.

## Layout

```
src/Migraine.sol          the contract
script/Deploy.s.sol                deployment script (env-var configured)
test/
  Migraine.t.sol          unit + fuzz tests
  MigraineIntegration.t.sol   end-to-end lifecycle with a contract vault
  MigraineInvariant.t.sol     stateful invariant tests
  mocks/                           MockERC20, MockSafeWallet, ReentrantOnceERC20
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

- constructor validation (including wallet-is-a-token) and immutables,
- `previewRedeem` math (including 18→6 decimal mismatch and floor rounding),
- `redeem` and `redeemTo` happy paths, explicit recipients, exact allowance
  consumption, multiple users,
- zero-amount / zero-output / invalid-recipient / missing-approval /
  insufficient-balance reverts,
- harmless reentrancy: a reentrant ERC-20 cannot extract value or break the
  no-custody property (the contract is stateless and has no guard),
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
2. execute an ERC-20 `approve(Migraine, allowance)` transaction on
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

## Continuous integration

[`.github/workflows/ci.yml`](./.github/workflows/ci.yml) runs on every push and
pull request:

- **Foundry** — `forge fmt --check`, `forge build`, `forge lint` and the full
  unit/integration/fuzz/invariant test suite. Coverage is generated with
  `forge coverage`; [`scripts/coverage-badge.sh`](./scripts/coverage-badge.sh)
  derives the `src/` line-coverage percentage and, on `main`, publishes it to a
  `badges` branch that backs the coverage badge above (`src/Migraine.sol` is
  currently 100% line/branch/function covered).
- **Verity** — installs the Lean toolchain, clones Verity at a pinned revision,
  overlays the `Migraine` model via `scripts/ci-verity.sh`, builds the
  proofs (`lake build Contracts.Migraine.Proofs.Correctness`), fails on
  any `sorry`/`admit`, registers the compiler model and emits
  `Migraine.yul` as a build artifact.

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
- **Stateless / reentrancy-harmless.** The contract holds no mutable state, so no
  reentrancy guard is used: a reentrant token can only trigger additional,
  independent redemptions (bounded by the same allowances/balances) and cannot
  corrupt state or extract value. `Redeemed` is emitted before the external calls
  (checks-effects-interactions), so it is never a false success signal; with a
  reentrant token, log ordering can nest, so off-chain consumers should not assume
  strictly sequential events.

## Token due diligence (before choosing the pair)

Because `tokenA` and `tokenB` are fixed at deployment and the contract assumes
standard, exact-transfer ERC-20s, verify both tokens up front:

- **No transfer fees / rebasing / hook-based amounts.** Fee-on-transfer or
  rebasing tokens break the exact-amount accounting (the vault would absorb the
  shortfall on `tokenA`, or users would receive less `tokenB`).
- **Upgradeability.** Prefer non-upgradeable tokens; a proxy admin can change
  transfer behaviour after deployment.
- **Blocklists / pausability / mint authority.** A token that can freeze the
  vault wallet, pause transfers, or mint unlimited supply changes the risk
  profile materially.
- **ERC-777 / receive hooks.** Confirm the vault wallet can receive `tokenA`; an
  ERC-777 `tokenA` requires the Safe to implement `tokensReceived`.
- **Decimals.** Confirm `tokenA`/`tokenB` decimals and set `rateNumerator` /
  `rateDenominator` for the **smallest units** (both tokens are used in raw base
  units; a decimal mismatch must be absorbed into the rate).

## Pre-deployment checklist

1. Deploy with the intended `tokenA`, `tokenB`, vault `wallet`, and rate.
2. Fund the vault wallet with `tokenB` to cover the entire redeemable `tokenA`
   supply, and have the vault approve `Migraine` for that amount.
3. Run the invariant/property suite against a **fork of the real token pair** to
   catch decimal or token-quirk surprises.
4. Do a **canary redemption** with a small `tokenA` amount and a small vault
   allowance first; confirm `tokenA` lands in the vault and `tokenB` reaches the
   recipient.
5. Only then raise the vault allowance to the full inventory.

## License

MIT (see [`LICENSE`](./LICENSE)).
