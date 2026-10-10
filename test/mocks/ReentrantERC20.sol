// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IRedeemTarget {
    function redeem(uint256 amountA) external returns (uint256 amountB);
}

/// @notice Malicious ERC-20 that attempts to re-enter the redeemer during
///         `transferFrom`, used to prove the reentrancy guard holds.
contract ReentrantERC20 is ERC20 {
    address public target;
    uint256 public reenterAmount = 1;

    constructor() ERC20("Reentrant", "RE") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function configure(address target_, uint256 reenterAmount_) external {
        target = target_;
        reenterAmount = reenterAmount_;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (target != address(0)) {
            IRedeemTarget(target).redeem(reenterAmount);
        }
        return super.transferFrom(from, to, amount);
    }
}
