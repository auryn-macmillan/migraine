// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {FixedRateRedeemer} from "../src/FixedRateRedeemer.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ReentrantERC20} from "./mocks/ReentrantERC20.sol";
import {TestBase} from "./utils/TestBase.sol";

contract FixedRateRedeemerTest is TestBase {
    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------

    function test_Constructor_SetsImmutables() public view {
        assertEq(address(redeemer.tokenA()), address(tokenA));
        assertEq(address(redeemer.tokenB()), address(tokenB));
        assertEq(redeemer.wallet(), vault);
        assertEq(redeemer.rateNumerator(), RATE_NUM);
        assertEq(redeemer.rateDenominator(), RATE_DEN);
    }

    function test_Constructor_RevertsOnZeroTokenA() public {
        vm.expectRevert(FixedRateRedeemer.ZeroAddress.selector);
        new FixedRateRedeemer(IERC20(address(0)), IERC20(address(tokenB)), vault, 1, 1);
    }

    function test_Constructor_RevertsOnZeroTokenB() public {
        vm.expectRevert(FixedRateRedeemer.ZeroAddress.selector);
        new FixedRateRedeemer(IERC20(address(tokenA)), IERC20(address(0)), vault, 1, 1);
    }

    function test_Constructor_RevertsOnIdenticalTokens() public {
        vm.expectRevert(FixedRateRedeemer.IdenticalTokens.selector);
        new FixedRateRedeemer(IERC20(address(tokenA)), IERC20(address(tokenA)), vault, 1, 1);
    }

    function test_Constructor_RevertsOnZeroWallet() public {
        vm.expectRevert(FixedRateRedeemer.ZeroWallet.selector);
        new FixedRateRedeemer(IERC20(address(tokenA)), IERC20(address(tokenB)), address(0), 1, 1);
    }

    function test_Constructor_RevertsOnZeroRateNumerator() public {
        vm.expectRevert(FixedRateRedeemer.InvalidRate.selector);
        new FixedRateRedeemer(IERC20(address(tokenA)), IERC20(address(tokenB)), vault, 0, 1);
    }

    function test_Constructor_RevertsOnZeroRateDenominator() public {
        vm.expectRevert(FixedRateRedeemer.InvalidRate.selector);
        new FixedRateRedeemer(IERC20(address(tokenA)), IERC20(address(tokenB)), vault, 1, 0);
    }

    function test_Constructor_RevertsOnWalletIsSelf() public {
        // The wallet cannot be the redeemer itself.
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(FixedRateRedeemer.WalletIsSelf.selector);
        new FixedRateRedeemer(IERC20(address(tokenA)), IERC20(address(tokenB)), predicted, 1, 1);
    }

    // ---------------------------------------------------------------------
    // previewRedeem
    // ---------------------------------------------------------------------

    function test_PreviewRedeem_Basic() public view {
        assertEq(redeemer.previewRedeem(0), 0);
        assertEq(redeemer.previewRedeem(1), 1); // 3/2 -> 1
        assertEq(redeemer.previewRedeem(2), 3); // 3
        assertEq(redeemer.previewRedeem(3), 4); // 4.5 -> 4
        assertEq(redeemer.previewRedeem(10), 15);
    }

    function testFuzz_PreviewRedeem_MatchesFullPrecisionMulDiv(uint256 amountA) public view {
        // Bound so the quotient fits in uint256 (mulDiv would otherwise revert).
        amountA = bound(amountA, 0, type(uint256).max / RATE_NUM);
        assertEq(redeemer.previewRedeem(amountA), Math.mulDiv(amountA, RATE_NUM, RATE_DEN));
    }

    function test_PreviewRedeem_DecimalMismatch() public {
        // 1 tokenA (18 dec) should buy 5 tokenB (6 dec): 1e18 * 5 / 1e12 = 5e6.
        FixedRateRedeemer r = new FixedRateRedeemer(IERC20(address(tokenA)), IERC20(address(tokenB)), vault, 5, 1e12);
        assertEq(r.previewRedeem(1e18), 5e6);
        assertEq(r.previewRedeem(5e17), 25e5); // 2.5 tokenB
    }

    // ---------------------------------------------------------------------
    // redeem: happy paths
    // ---------------------------------------------------------------------

    function test_Redeem_HappyPath() public {
        uint256 amountA = 100e18;
        uint256 amountB = amountA * RATE_NUM / RATE_DEN; // 150e18 raw units

        _fundVault(1_000e18);
        _fundUser(alice, amountA);

        vm.expectEmit(true, true, true, true, address(redeemer));
        emit Redeemed(alice, alice, amountA, amountB);

        vm.prank(alice);
        uint256 got = redeemer.redeem(amountA);

        assertEq(got, amountB);
        assertEq(tokenA.balanceOf(alice), 0);
        assertEq(tokenB.balanceOf(alice), amountB);
        assertEq(tokenA.balanceOf(vault), amountA);
        assertEq(tokenB.balanceOf(vault), 1_000e18 - amountB);
        // No custody.
        assertEq(tokenA.balanceOf(address(redeemer)), 0);
        assertEq(tokenB.balanceOf(address(redeemer)), 0);
    }

    function test_Redeem_ExactFiniteAllowanceConsumed() public {
        uint256 amountA = 10e18;
        uint256 amountB = amountA * RATE_NUM / RATE_DEN;

        tokenB.mint(vault, amountB);
        vm.prank(vault);
        tokenB.approve(address(redeemer), amountB);

        tokenA.mint(alice, amountA);
        vm.prank(alice);
        tokenA.approve(address(redeemer), amountA);

        vm.prank(alice);
        redeemer.redeem(amountA);

        assertEq(tokenA.allowance(alice, address(redeemer)), 0);
        assertEq(tokenB.allowance(vault, address(redeemer)), 0);
    }

    function test_Redeem_MultipleUsers() public {
        _fundVault(1_000e18);

        _fundUser(alice, 100e18);
        _fundUser(bob, 200e18);

        vm.prank(alice);
        redeemer.redeem(100e18);
        vm.prank(bob);
        redeemer.redeem(200e18);

        assertEq(tokenA.balanceOf(vault), 300e18);
        assertEq(tokenB.balanceOf(alice), 150e18);
        assertEq(tokenB.balanceOf(bob), 300e18);
        assertEq(tokenB.balanceOf(vault), 1_000e18 - 450e18);
    }

    // ---------------------------------------------------------------------
    // redeem: reverts
    // ---------------------------------------------------------------------

    function test_Redeem_RevertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(FixedRateRedeemer.ZeroAmount.selector);
        redeemer.redeem(0);
    }

    function test_Redeem_RevertsOnZeroOutput() public {
        // Rate 1/2 makes a 1-unit redemption round down to zero tokenB.
        FixedRateRedeemer r = new FixedRateRedeemer(IERC20(address(tokenA)), IERC20(address(tokenB)), vault, 1, 2);
        _fundVault(1_000e18);
        vm.prank(alice);
        vm.expectRevert(FixedRateRedeemer.ZeroOutput.selector);
        r.redeem(1); // 1 * 1 / 2 = 0
    }

    function test_Redeem_RevertsWithoutTokenAApproval() public {
        _fundVault(1_000e18);
        tokenA.mint(alice, 100e18); // no approval

        vm.prank(alice);
        vm.expectRevert();
        redeemer.redeem(100e18);
    }

    function test_Redeem_RevertsWithoutVaultApproval() public {
        tokenB.mint(vault, 1_000e18); // no approval
        _fundUser(alice, 100e18);

        vm.prank(alice);
        vm.expectRevert();
        redeemer.redeem(100e18);
    }

    function test_Redeem_RevertsWhenVaultInsufficientTokenB() public {
        // Vault approves but is short on balance.
        tokenB.mint(vault, 1e18);
        vm.prank(vault);
        tokenB.approve(address(redeemer), type(uint256).max);
        _fundUser(alice, 100e18);

        vm.prank(alice);
        vm.expectRevert();
        redeemer.redeem(100e18);
    }

    function test_Redeem_RevertsWhenUserInsufficientTokenA() public {
        _fundVault(1_000e18);
        tokenA.mint(alice, 1e18); // less than requested
        vm.prank(alice);
        tokenA.approve(address(redeemer), type(uint256).max);

        vm.prank(alice);
        vm.expectRevert();
        redeemer.redeem(100e18);
    }

    // ---------------------------------------------------------------------
    // Reentrancy
    // ---------------------------------------------------------------------

    function test_Redeem_ReentrancyBlocked() public {
        ReentrantERC20 malicious = new ReentrantERC20();
        MockERC20 honest = new MockERC20("Honest", "HON", 18);

        FixedRateRedeemer r =
            new FixedRateRedeemer(IERC20(address(malicious)), IERC20(address(honest)), vault, RATE_NUM, RATE_DEN);

        malicious.configure(address(r), 1);
        malicious.mint(alice, 100e18);
        vm.prank(alice);
        malicious.approve(address(r), type(uint256).max);

        honest.mint(vault, 1_000e18);
        vm.prank(vault);
        honest.approve(address(r), type(uint256).max);

        vm.prank(alice);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        r.redeem(100e18);
    }

    // ---------------------------------------------------------------------
    // Fuzz accounting
    // ---------------------------------------------------------------------

    function testFuzz_Redeem_Accounting(uint256 amountA) public {
        amountA = bound(amountA, 1, 1e30);
        uint256 amountB = Math.mulDiv(amountA, RATE_NUM, RATE_DEN);
        vm.assume(amountB > 0);

        _fundVault(amountB);
        _fundUser(alice, amountA);

        uint256 vaultABefore = tokenA.balanceOf(vault);
        uint256 vaultBBefore = tokenB.balanceOf(vault);

        vm.prank(alice);
        uint256 got = redeemer.redeem(amountA);

        assertEq(got, amountB);
        assertEq(tokenA.balanceOf(vault), vaultABefore + amountA);
        assertEq(tokenB.balanceOf(vault), vaultBBefore - amountB);
        assertEq(tokenA.balanceOf(alice), 0);
        assertEq(tokenB.balanceOf(alice), amountB);
        assertEq(tokenA.balanceOf(address(redeemer)), 0);
        assertEq(tokenB.balanceOf(address(redeemer)), 0);
    }
}
