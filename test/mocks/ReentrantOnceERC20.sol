// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IMigraine {
    function redeemTo(uint256 amountA, address to) external returns (uint256 amountB);
}

/// @notice Malicious ERC-20 that re-enters the redeemer exactly once during the
///         first `transferFrom`, then proceeds normally. Used to show that a
///         reentrant token cannot extract value or break the no-custody property
///         (the redeemer is stateless and has no reentrancy guard).
contract ReentrantOnceERC20 is ERC20 {
    address public target;
    uint256 public reenterAmount;
    address public reenterRecipient;

    bool private _hasReentered;

    constructor() ERC20("Reentrant Once", "RONCE") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function configure(address target_, uint256 reenterAmount_, address reenterRecipient_) external {
        target = target_;
        reenterAmount = reenterAmount_;
        reenterRecipient = reenterRecipient_;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (target != address(0) && !_hasReentered) {
            _hasReentered = true;
            IMigraine(target).redeemTo(reenterAmount, reenterRecipient);
        }
        return super.transferFrom(from, to, amount);
    }
}
