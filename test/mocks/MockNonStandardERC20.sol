// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice ERC-20 whose `transferFrom` performs the transfer but returns
/// `false` — exercises the SafeERC20 failed-operation guard.
contract MockFalseReturnERC20 is ERC20 {
    constructor() ERC20("Falsey", "FLS") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _transfer(from, to, amount); // state change happens, then lies about it
        return false;
    }
}

/// @notice Legacy ERC-20 (USDT-style): correct accounting, but the
/// transfer/approve functions return nothing. SafeERC20 must accept these.
contract MockNoReturnERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external {
        _move(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "insufficient allowance");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        _move(from, to, amount);
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }

    function _move(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "insufficient balance");
        unchecked {
            balanceOf[from] -= amount;
        }
        balanceOf[to] += amount;
    }
}
