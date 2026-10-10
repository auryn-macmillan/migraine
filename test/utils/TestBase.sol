// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Migraine} from "../../src/Migraine.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Shared fixture: two mock tokens, an EOA vault, and a redeemer at rate 3/2.
abstract contract TestBase is Test {
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    Migraine internal redeemer;

    address internal vault;
    address internal alice;
    address internal bob;

    uint256 internal constant RATE_NUM = 3;
    uint256 internal constant RATE_DEN = 2;

    event Redeemed(address indexed redeemer, address indexed recipient, uint256 amountA, uint256 amountB);

    function setUp() public virtual {
        tokenA = new MockERC20("Token A", "AAA", 18);
        tokenB = new MockERC20("Token B", "BBB", 6);

        vault = makeAddr("vault");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        redeemer = new Migraine(IERC20(address(tokenA)), IERC20(address(tokenB)), vault, RATE_NUM, RATE_DEN);
    }

    /// @dev Mint `amountB` of tokenB to the vault and grant the redeemer an unlimited allowance.
    function _fundVault(uint256 amountB) internal {
        tokenB.mint(vault, amountB);
        vm.prank(vault);
        tokenB.approve(address(redeemer), type(uint256).max);
    }

    /// @dev Mint `amountA` of tokenA to `user` and grant the redeemer an unlimited allowance.
    function _fundUser(address user, uint256 amountA) internal {
        tokenA.mint(user, amountA);
        vm.prank(user);
        tokenA.approve(address(redeemer), type(uint256).max);
    }
}
