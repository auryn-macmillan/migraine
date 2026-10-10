# Plain-Language Specification — `Migraine`

## 1. Purpose

`Migraine` is a small, immutable, trust-minimised smart contract that
lets **anyone** exchange one ERC-20 token (`tokenA`) for another (`tokenB`) at a
**fixed rate**, in exactly **one direction**. The token being received by users
(`tokenB`) does **not** live in the redeemer contract; it lives in a separate
**vault wallet** (e.g. a Gnosis Safe). The redeemer contract is a pure
orchestrator: it never custodies tokens, not even for a single block.

## 2. Actors

| Actor | Description |
| --- | --- |
| **Redeemer (user)** | Any address. Holds `tokenA`, wants `tokenB`. Must approve `Migraine` to pull `tokenA`. |
| **Vault wallet** | A separate contract account (e.g. Gnosis Safe) that holds the `tokenB` inventory and receives all `tokenA`. Must approve `Migraine` to pull `tokenB`. |
| **`Migraine`** | This contract. Holds no tokens at any point. Immutable parameters. No owner, no admin, no pause. |

## 3. Configuration (set once at deployment, immutable forever)

| Parameter | Meaning |
| --- | --- |
| `tokenA` | The ERC-20 users give. |
| `tokenB` | The ERC-20 users receive. |
| `wallet` | The vault wallet address that holds `tokenB` and receives `tokenA`. Must not be `tokenA`, `tokenB`, the zero address, or the redeemer itself. |
| `rateNumerator` | Numerator of the fixed exchange rate. Non-zero. |
| `rateDenominator` | Denominator of the fixed exchange rate. Non-zero. |

The exchange rate is `rateNumerator / rateDenominator`, interpreted in the
**smallest units** of each token:

```
amountB = floor(amountA * rateNumerator / rateDenominator)
```

For example, to exchange at 1 `tokenA` = 2.5 `tokenB` where both tokens have 18
decimals, use `rateNumerator = 25`, `rateDenominator = 10`.

## 4. Functional requirements

### FR-1 — Redeem
`redeem(uint256 amountA) external returns (uint256 amountB)`

When a user calls `redeem(amountA)`:

1. Revert if `amountA == 0`.
2. Compute `amountB = floor(amountA * rateNumerator / rateDenominator)`.
3. Revert if `amountB == 0` (dust that would produce nothing).
4. Transfer exactly `amountA` of `tokenA` **from the user to the vault wallet**.
5. Transfer exactly `amountB` of `tokenB` **from the vault wallet to the user**.
6. Emit `Redeemed(user, user, amountA, amountB)`.

The two transfers are atomic: either both succeed or the whole transaction
reverts, so a user can never give `tokenA` without receiving `tokenB`.

### FR-2 — Preview
`previewRedeem(uint256 amountA) view returns (uint256 amountB)`

Return exactly the `amountB` that `redeem(amountA)` would pay, using the same
full-precision, floor-rounded formula. This is a pure read used by the UI.

### FR-3 — One-way only
There is **no** function anywhere in the contract that exchanges `tokenB` back
for `tokenA`, and no way to change the direction, the rate, the tokens, or the
wallet after deployment. The ABI contains a single state-changing method:
`redeem`.

### FR-4 — No custody
At the end of every successful call, and at every instant in between, the
`Migraine` contract's balance of `tokenA` and of `tokenB` is zero. It
only ever moves tokens directly between the user and the vault wallet.

## 5. Preconditions and revert conditions

| Condition | Result |
| --- | --- |
| `amountA == 0` | Revert `ZeroAmount()` |
| `amountB == 0` after rounding | Revert `ZeroOutput()` |
| User has not approved `tokenA` (or insufficient allowance/balance) | Revert (via `SafeERC20`, propagated) |
| Vault wallet has not approved `tokenB` (or insufficient allowance) | Revert (via `SafeERC20`, propagated) |
| Vault wallet holds less `tokenB` than `amountB` | Revert (via `SafeERC20`, propagated) |
| Reentrant call while a `redeem` is in flight | Revert `ReentrancyGuardReentrantCall()` |

## 6. Constructor validation

Deployment reverts if any of the following hold:

- `tokenA == address(0)` or `tokenB == address(0)` → `ZeroAddress()`
- `tokenA == tokenB` → `IdenticalTokens()`
- `wallet == address(0)` → `ZeroWallet()`
- `wallet == address(this)` → `WalletIsSelf()` (would break the no-custody rule)
- `rateNumerator == 0` or `rateDenominator == 0` → `InvalidRate()`

## 7. Safety properties (desired invariants)

These are the properties the formal specification (Verity/Lean) and the tests
target.

- **P1 (Rate correctness).** For every successful `redeem(amountA)`, the caller
  receives exactly `floor(amountA * rateNumerator / rateDenominator)` of `tokenB`.
- **P2 (Direction / no reverse).** No reachable code path lets any caller obtain
  `tokenA` from the vault wallet, nor exchange `tokenB` for `tokenA`.
- **P3 (Atomicity / no free lunch).** A caller cannot receive `tokenB` without
  paying `amountA` of `tokenA`; the two transfers commit together or not at all.
- **P4 (No custody).** `tokenA.balanceOf(redeemer) == 0` and
  `tokenB.balanceOf(redeemer) == 0` after every call.
- **P5 (Conservation).** Summed across all successful redemptions, the `tokenA`
  credited to the vault wallet equals the `amountA` values supplied by users,
  and the `tokenB` debited from the vault wallet equals the corresponding
  `amountB` values.
- **P6 (Immutability).** After construction, `tokenA`, `tokenB`, `wallet`,
  `rateNumerator`, `rateDenominator` cannot change.
- **P7 (Reentrancy-safe).** A malicious token cannot cause a nested `redeem` to
  execute.

## 8. Explicit non-goals / assumptions

- **Standard ERC-20s.** The contract assumes tokens that transfer exactly the
  requested amount (no fee-on-transfer, no rebasing). Fee-on-transfer tokens
  would break exact-amount accounting; they are out of scope.
- **Inventory funding is operational, not on-chain.** "Enough `tokenB` to cover
  the entire `tokenA` supply" is guaranteed by (a) funding the vault wallet and
  (b) the vault wallet's ERC-20 allowance to the redeemer. The allowance is the
  effective on-chain cap: the redeemer can never pay out more `tokenB` than the
  vault wallet has approved.
- **No owner, no pause, no upgrades.** Deliberately immutable and
  permissionless; there is no privileged role to compromise.
- **Rounding favours the vault.** `amountB` is rounded down, so dust accrues to
  the vault wallet, never to the redeemer.

## 9. Interface summary

```
constructor(address tokenA, address tokenB, address wallet,
            uint256 rateNumerator, uint256 rateDenominator)

function redeem(uint256 amountA) external returns (uint256 amountB)
function previewRedeem(uint256 amountA) external view returns (uint256 amountB)

// immutable public getters
function tokenA() external view returns (address)
function tokenB() external view returns (address)
function wallet() external view returns (address)
function rateNumerator() external view returns (uint256)
function rateDenominator() external view returns (uint256)

event Redeemed(address indexed redeemer, address indexed recipient,
               uint256 amountA, uint256 amountB)
```
