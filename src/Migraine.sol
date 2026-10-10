// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Migraine
/// @notice One-way, fixed-rate, permissionless redemption of `tokenA` for `tokenB`.
/// @dev The contract never holds tokens. `tokenA` is pulled from the caller into a
///      separate vault wallet, and `tokenB` is pushed from that wallet to the caller.
///      The vault wallet must approve this contract for `tokenB`, and callers must
///      approve it for `tokenA`. All configuration is immutable.
contract Migraine is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Token users give up. Pulled from the caller to the vault wallet.
    IERC20 public immutable tokenA;

    /// @notice Token users receive. Pulled from the vault wallet to the caller.
    IERC20 public immutable tokenB;

    /// @notice Vault wallet (e.g. a Gnosis Safe) holding `tokenB` and receiving `tokenA`.
    address public immutable wallet;

    /// @notice Numerator of the fixed rate: `amountB = amountA * rateNumerator / rateDenominator`.
    uint256 public immutable rateNumerator;

    /// @notice Denominator of the fixed rate. Must be non-zero.
    uint256 public immutable rateDenominator;

    /// @notice Emitted on every successful redemption.
    /// @param redeemer Caller that supplied `tokenA`.
    /// @param recipient Address that received `tokenB` (always `redeemer`).
    /// @param amountA Amount of `tokenA` paid by the caller.
    /// @param amountB Amount of `tokenB` received by the caller.
    event Redeemed(address indexed redeemer, address indexed recipient, uint256 amountA, uint256 amountB);

    /// @notice A required address was the zero address.
    error ZeroAddress();
    /// @notice `tokenA` and `tokenB` were the same address.
    error IdenticalTokens();
    /// @notice The vault wallet was the zero address.
    error ZeroWallet();
    /// @notice The vault wallet was this contract, which would violate the no-custody rule.
    error WalletIsSelf();
    /// @notice A rate component was zero.
    error InvalidRate();
    /// @notice Redemption amount was zero.
    error ZeroAmount();
    /// @notice The computed payout rounded down to zero.
    error ZeroOutput();

    /// @param tokenA_ Token given by users. Must be non-zero and distinct from `tokenB_`.
    /// @param tokenB_ Token received by users. Must be non-zero and distinct from `tokenA_`.
    /// @param wallet_ Vault wallet. Must be non-zero and not this contract.
    /// @param rateNumerator_ Non-zero numerator of the fixed rate.
    /// @param rateDenominator_ Non-zero denominator of the fixed rate.
    constructor(IERC20 tokenA_, IERC20 tokenB_, address wallet_, uint256 rateNumerator_, uint256 rateDenominator_) {
        if (address(tokenA_) == address(0) || address(tokenB_) == address(0)) revert ZeroAddress();
        if (address(tokenA_) == address(tokenB_)) revert IdenticalTokens();
        if (wallet_ == address(0)) revert ZeroWallet();
        if (wallet_ == address(this)) revert WalletIsSelf();
        if (rateNumerator_ == 0 || rateDenominator_ == 0) revert InvalidRate();

        tokenA = tokenA_;
        tokenB = tokenB_;
        wallet = wallet_;
        rateNumerator = rateNumerator_;
        rateDenominator = rateDenominator_;
    }

    /// @notice Preview the `tokenB` payout for a given `tokenA` input.
    /// @dev Uses full 512-bit intermediate precision and rounds down. Reverts on quotient overflow.
    /// @param amountA Amount of `tokenA` to redeem.
    /// @return amountB Amount of `tokenB` that `redeem(amountA)` would pay.
    function previewRedeem(uint256 amountA) public view returns (uint256 amountB) {
        amountB = Math.mulDiv(amountA, rateNumerator, rateDenominator);
    }

    /// @notice Redeem `amountA` of `tokenA` for `tokenB` at the fixed rate.
    /// @dev Pulls `tokenA` from `msg.sender` into `wallet`, then pushes `tokenB` from
    ///      `wallet` to `msg.sender`. Atomic: both transfers succeed or the call reverts.
    ///      Guarded against reentrancy via `nonReentrant`.
    /// @param amountA Amount of `tokenA` to redeem.
    /// @return amountB Amount of `tokenB` paid out.
    function redeem(uint256 amountA) external nonReentrant returns (uint256 amountB) {
        if (amountA == 0) revert ZeroAmount();

        amountB = Math.mulDiv(amountA, rateNumerator, rateDenominator);
        if (amountB == 0) revert ZeroOutput();

        // 1. Move tokenA from the redeemer into the vault wallet.
        tokenA.safeTransferFrom(msg.sender, wallet, amountA);

        // 2. Move tokenB from the vault wallet to the redeemer.
        // The `from` address is the immutable, deployment-fixed vault wallet, not an
        // attacker-controlled parameter. The spendable amount is bounded by the ERC-20
        // allowance the vault wallet itself has granted this contract.
        // forge-lint: disable-next-line(arbitrary-send-erc20)
        tokenB.safeTransferFrom(wallet, msg.sender, amountB);

        // Safe to emit after the external calls: `nonReentrant` prevents reordering.
        // forge-lint: disable-next-line(reentrancy-events)
        emit Redeemed(msg.sender, msg.sender, amountA, amountB);
    }
}
