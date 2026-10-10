// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {FixedRateRedeemer} from "../src/FixedRateRedeemer.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockSafeWallet} from "./mocks/MockSafeWallet.sol";

/// @notice End-to-end lifecycle with a real contract vault wallet (Safe-like).
contract FixedRateRedeemerIntegrationTest is Test {
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    MockSafeWallet internal safe;
    FixedRateRedeemer internal redeemer;

    address internal safeOwner;
    address internal alice;
    address internal bob;
    address internal carol;

    uint256 internal constant RATE_NUM = 2; // 1 tokenA -> 2 tokenB
    uint256 internal constant RATE_DEN = 1;

    event Redeemed(address indexed redeemer, address indexed recipient, uint256 amountA, uint256 amountB);

    function setUp() public {
        tokenA = new MockERC20("Token A", "AAA", 18);
        tokenB = new MockERC20("Token B", "BBB", 18);

        safeOwner = makeAddr("safeOwner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");

        safe = new MockSafeWallet(safeOwner);
        redeemer =
            new FixedRateRedeemer(IERC20(address(tokenA)), IERC20(address(tokenB)), address(safe), RATE_NUM, RATE_DEN);
    }

    function _stockSafe(uint256 amountB) internal {
        tokenB.mint(address(safe), amountB);
    }

    function _approveSafe(uint256 allowance) internal {
        vm.prank(safeOwner);
        safe.approveToken(address(tokenB), address(redeemer), allowance);
    }

    function _giveA(address user, uint256 amountA) internal {
        tokenA.mint(user, amountA);
        vm.prank(user);
        tokenA.approve(address(redeemer), type(uint256).max);
    }

    function test_E2E_FullLifecycle() public {
        _stockSafe(1_000e18);
        _approveSafe(type(uint256).max);

        _giveA(alice, 100e18);
        _giveA(bob, 50e18);

        vm.expectEmit(true, true, true, true, address(redeemer));
        emit Redeemed(alice, alice, 100e18, 200e18);
        vm.prank(alice);
        assertEq(redeemer.redeem(100e18), 200e18);

        vm.expectEmit(true, true, true, true, address(redeemer));
        emit Redeemed(bob, bob, 50e18, 100e18);
        vm.prank(bob);
        assertEq(redeemer.redeem(50e18), 100e18);

        // tokenA accumulated in the Safe, tokenB paid out of the Safe.
        assertEq(tokenA.balanceOf(address(safe)), 150e18);
        assertEq(tokenB.balanceOf(address(safe)), 700e18);
        assertEq(tokenA.balanceOf(alice), 0);
        assertEq(tokenB.balanceOf(alice), 200e18);
        assertEq(tokenB.balanceOf(bob), 100e18);

        // The redeemer never holds anything.
        assertEq(tokenA.balanceOf(address(redeemer)), 0);
        assertEq(tokenB.balanceOf(address(redeemer)), 0);
    }

    function test_E2E_InventoryCoversEntireSupply() public {
        // Three users hold the entire 400e18 supply of tokenA.
        uint256 supplyA = 400e18;
        _giveA(alice, 100e18);
        _giveA(bob, 100e18);
        _giveA(carol, 200e18);

        // Safe is stocked to cover the entire supply: 400e18 * 2 = 800e18 tokenB.
        _stockSafe(800e18);
        _approveSafe(type(uint256).max);

        vm.prank(alice);
        redeemer.redeem(100e18);
        vm.prank(bob);
        redeemer.redeem(100e18);
        vm.prank(carol);
        redeemer.redeem(200e18);

        // Supply fully redeemed: Safe holds all tokenA and exactly zero tokenB.
        assertEq(tokenA.balanceOf(address(safe)), supplyA);
        assertEq(tokenB.balanceOf(address(safe)), 0);

        // A late redemption can no longer be served.
        _giveA(alice, 1e18);
        vm.prank(alice);
        vm.expectRevert();
        redeemer.redeem(1e18);
    }

    function test_E2E_AllowanceIsTheEffectiveCap() public {
        _stockSafe(1_000e18);
        // Safe only authorises 300e18 tokenB.
        _approveSafe(300e18);

        _giveA(alice, 100e18); // would need 200e18 -> ok
        vm.prank(alice);
        redeemer.redeem(100e18);

        assertEq(tokenB.balanceOf(alice), 200e18);

        // Next redemption of 100e18 needs another 200e18 but only 100e18 allowance remains.
        _giveA(alice, 100e18);
        assertEq(tokenB.balanceOf(address(safe)), 800e18); // plenty of balance...
        vm.prank(alice);
        vm.expectRevert(); // ...but the allowance cap blocks it
        redeemer.redeem(100e18);
    }

    function test_E2E_TokenANeverTouchesRedeemer() public {
        _stockSafe(1_000e18);
        _approveSafe(type(uint256).max);
        _giveA(alice, 10e18);

        for (uint256 i; i < 5; ++i) {
            _giveA(alice, 10e18);
            vm.prank(alice);
            redeemer.redeem(10e18);
            assertEq(tokenA.balanceOf(address(redeemer)), 0);
            assertEq(tokenB.balanceOf(address(redeemer)), 0);
        }
    }

    function test_E2E_VaultIsSelfIsRejected() public {
        // Address of the redeemer is not yet known when constructing; simulate by
        // deploying with a placeholder and asserting a direct self reference fails.
        address self = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(FixedRateRedeemer.WalletIsSelf.selector);
        new FixedRateRedeemer(IERC20(address(tokenA)), IERC20(address(tokenB)), self, 1, 1);
    }
}
