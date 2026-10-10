// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Minimal Safe-like vault wallet: holds tokens and can execute arbitrary
///         calls (including ERC-20 approvals) on behalf of its owner.
/// @dev Mimics the Gnosis Safe execution model closely enough for integration tests:
///      the owner authorises a call, the wallet makes it, and the wallet owns the
///      resulting state (balances / allowances).
contract MockSafeWallet {
    address public owner;

    error NotOwner();
    error CallFailed();

    constructor(address owner_) {
        owner = owner_;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @notice Execute an arbitrary call from the wallet.
    function execute(address target, uint256 value, bytes calldata data)
        external
        onlyOwner
        returns (bytes memory result)
    {
        bool ok;
        (ok, result) = target.call{value: value}(data);
        if (!ok) revert CallFailed();
    }

    /// @notice Convenience helper: approve `spender` to spend `amount` of `token`.
    function approveToken(address token, address spender, uint256 amount) external onlyOwner {
        IERC20(token).approve(spender, amount);
    }

    receive() external payable {}
}
