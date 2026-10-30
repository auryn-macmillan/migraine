// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Migraine} from "../src/Migraine.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockSafeWallet} from "./mocks/MockSafeWallet.sol";
import {ReentrantOnceERC20} from "./mocks/ReentrantOnceERC20.sol";
import {MockFalseReturnERC20, MockNoReturnERC20} from "./mocks/MockNonStandardERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TestBase} from "./utils/TestBase.sol";

contract MigraineTest is TestBase {
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
        vm.expectRevert(Migraine.ZeroAddress.selector);
        new Migraine(IERC20(address(0)), IERC20(address(tokenB)), vault, 1, 1);
    }

    function test_Constructor_RevertsOnZeroTokenB() public {
        vm.expectRevert(Migraine.ZeroAddress.selector);
        new Migraine(IERC20(address(tokenA)), IERC20(address(0)), vault, 1, 1);
    }

    function test_Constructor_RevertsOnIdenticalTokens() public {
        vm.expectRevert(Migraine.IdenticalTokens.selector);
        new Migraine(IERC20(address(tokenA)), IERC20(address(tokenA)), vault, 1, 1);
    }

    function test_Constructor_RevertsOnZeroWallet() public {
        vm.expectRevert(Migraine.ZeroWallet.selector);
        new Migraine(IERC20(address(tokenA)), IERC20(address(tokenB)), address(0), 1, 1);
    }

    function test_Constructor_RevertsOnZeroRateNumerator() public {
        vm.expectRevert(Migraine.InvalidRate.selector);
        new Migraine(IERC20(address(tokenA)), IERC20(address(tokenB)), vault, 0, 1);
    }

    function test_Constructor_RevertsOnZeroRateDenominator() public {
        vm.expectRevert(Migraine.InvalidRate.selector);
        new Migraine(IERC20(address(tokenA)), IERC20(address(tokenB)), vault, 1, 0);
    }

    function test_Constructor_RevertsOnWalletIsSelf() public {
        // The wallet cannot be the redeemer itself.
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(Migraine.WalletIsSelf.selector);
        new Migraine(IERC20(address(tokenA)), IERC20(address(tokenB)), predicted, 1, 1);
    }

    function test_Constructor_RevertsOnWalletIsTokenA() public {
        vm.expectRevert(Migraine.InvalidWallet.selector);
        new Migraine(IERC20(address(tokenA)), IERC20(address(tokenB)), address(tokenA), 1, 1);
    }

    function test_Constructor_RevertsOnWalletIsTokenB() public {
        vm.expectRevert(Migraine.InvalidWallet.selector);
        new Migraine(IERC20(address(tokenA)), IERC20(address(tokenB)), address(tokenB), 1, 1);
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
        Migraine r = new Migraine(IERC20(address(tokenA)), IERC20(address(tokenB)), vault, 5, 1e12);
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
    // redeemTo
    // ---------------------------------------------------------------------

    function test_RedeemTo_SendsTokenBToRecipient() public {
        uint256 amountA = 100e18;
        uint256 amountB = amountA * RATE_NUM / RATE_DEN;

        _fundVault(1_000e18);
        _fundUser(alice, amountA);

        // tokenA comes from the caller (alice), tokenB goes to bob.
        vm.expectEmit(true, true, true, true, address(redeemer));
        emit Redeemed(alice, bob, amountA, amountB);

        vm.prank(alice);
        uint256 got = redeemer.redeemTo(amountA, bob);

        assertEq(got, amountB);
        assertEq(tokenA.balanceOf(alice), 0);
        assertEq(tokenA.balanceOf(vault), amountA);
        assertEq(tokenB.balanceOf(alice), 0);
        assertEq(tokenB.balanceOf(bob), amountB);
        assertEq(tokenA.balanceOf(address(redeemer)), 0);
        assertEq(tokenB.balanceOf(address(redeemer)), 0);
    }

    function test_RedeemTo_SelfMatchesRedeem() public {
        uint256 amountA = 40e18;
        uint256 amountB = amountA * RATE_NUM / RATE_DEN;

        _fundVault(1_000e18);
        _fundUser(alice, amountA);

        vm.expectEmit(true, true, true, true, address(redeemer));
        emit Redeemed(alice, alice, amountA, amountB);

        vm.prank(alice);
        uint256 got = redeemer.redeemTo(amountA, alice);

        assertEq(got, amountB);
        assertEq(tokenB.balanceOf(alice), amountB);
    }

    function test_RedeemTo_RevertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(Migraine.ZeroAmount.selector);
        redeemer.redeemTo(0, alice);
    }

    function test_RedeemTo_RevertsOnZeroOutput() public {
        // Rate 1/2 makes a 1-unit redemption round down to zero tokenB.
        Migraine r = new Migraine(IERC20(address(tokenA)), IERC20(address(tokenB)), vault, 1, 2);
        vm.prank(alice);
        vm.expectRevert(Migraine.ZeroOutput.selector);
        r.redeemTo(1, alice); // 1 * 1 / 2 = 0
    }

    function test_RedeemTo_RevertsOnInvalidRecipient() public {
        address[5] memory bad = [address(0), address(redeemer), address(tokenA), address(tokenB), vault];
        for (uint256 i; i < bad.length; ++i) {
            vm.expectRevert(abi.encodeWithSelector(Migraine.InvalidRecipient.selector, bad[i]));
            redeemer.redeemTo(10e18, bad[i]);
        }
    }

    // ---------------------------------------------------------------------
    // redeem: reverts
    // ---------------------------------------------------------------------

    function test_Redeem_RevertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(Migraine.ZeroAmount.selector);
        redeemer.redeem(0);
    }

    function test_Redeem_RevertsOnZeroOutput() public {
        // Rate 1/2 makes a 1-unit redemption round down to zero tokenB.
        Migraine r = new Migraine(IERC20(address(tokenA)), IERC20(address(tokenB)), vault, 1, 2);
        _fundVault(1_000e18);
        vm.prank(alice);
        vm.expectRevert(Migraine.ZeroOutput.selector);
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
    // Reentrancy is harmless (the contract is stateless and has no guard)
    // ---------------------------------------------------------------------

    function test_Reentrancy_HarmsNothing() public {
        ReentrantOnceERC20 malicious = new ReentrantOnceERC20();
        MockERC20 honest = new MockERC20("Honest", "HON", 18);
        Migraine r = new Migraine(IERC20(address(malicious)), IERC20(address(honest)), vault, RATE_NUM, RATE_DEN);

        address sink = makeAddr("reentrantSink");
        uint256 nestedA = 10e18;
        uint256 outerA = 100e18;
        malicious.configure(address(r), nestedA, sink);

        // The malicious token redeems on its own behalf, once, during the outer transfer.
        malicious.mint(address(malicious), nestedA);
        vm.prank(address(malicious));
        malicious.approve(address(r), type(uint256).max);

        malicious.mint(alice, outerA);
        vm.prank(alice);
        malicious.approve(address(r), type(uint256).max);

        honest.mint(vault, 1_000e18);
        vm.prank(vault);
        honest.approve(address(r), type(uint256).max);

        uint256 nestedB = nestedA * RATE_NUM / RATE_DEN;
        uint256 outerB = outerA * RATE_NUM / RATE_DEN;

        vm.prank(alice);
        uint256 got = r.redeem(outerA);
        assertEq(got, outerB);

        // Both redemptions settled correctly, and nothing was extracted for free.
        assertEq(malicious.balanceOf(vault), outerA + nestedA);
        assertEq(honest.balanceOf(alice), outerB);
        assertEq(honest.balanceOf(sink), nestedB);
        assertEq(honest.balanceOf(vault), 1_000e18 - outerB - nestedB);
        assertEq(malicious.balanceOf(address(malicious)), 0);
        // No custody.
        assertEq(malicious.balanceOf(address(r)), 0);
        assertEq(honest.balanceOf(address(r)), 0);
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

    function testFuzz_RedeemTo_Accounting(uint256 amountA, address recipient) public {
        amountA = bound(amountA, 1, 1e30);
        uint256 amountB = Math.mulDiv(amountA, RATE_NUM, RATE_DEN);
        vm.assume(amountB > 0);
        vm.assume(
            recipient != address(0) && recipient != address(redeemer) && recipient != address(tokenA)
                && recipient != address(tokenB) && recipient != vault
        );

        _fundVault(amountB);
        _fundUser(alice, amountA);

        vm.prank(alice);
        uint256 got = redeemer.redeemTo(amountA, recipient);

        assertEq(got, amountB);
        assertEq(tokenA.balanceOf(vault), amountA);
        assertEq(tokenB.balanceOf(recipient), amountB);
        assertEq(tokenA.balanceOf(address(redeemer)), 0);
        assertEq(tokenB.balanceOf(address(redeemer)), 0);
    }

    // ---------------------------------------------------------------------
    // Math.mulDiv overflow (512-bit product, quotient must fit uint256)
    // ---------------------------------------------------------------------

    /// @dev Largest amountA whose payout floor(amountA * 3 / 2) still fits in uint256:
    ///      floor((2^257 - 1) / 3); the payout is exactly type(uint256).max.
    uint256 private constant MAX_SAFE_AMOUNT_A =
        77194726158210796949047323339125271902179989777093709359638389338608753093290;

    function test_PreviewRedeem_MaxSafeAmountPayoutIsMaxUint() public view {
        assertEq(redeemer.previewRedeem(MAX_SAFE_AMOUNT_A), type(uint256).max);
    }

    function test_PreviewRedeem_RevertsOnMulDivOverflow() public {
        // One wei past the boundary: floor((a+1) * 3 / 2) = 2^256 + 1 overflows uint256.
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("Panic(uint256)")), uint256(0x11)));
        redeemer.previewRedeem(MAX_SAFE_AMOUNT_A + 1);
    }

    function test_Redeem_RevertsOnMulDivOverflow() public {
        // Overflow must revert before any transfer is attempted, not wrap to a small payout.
        _fundUser(alice, type(uint256).max);
        _fundVault(type(uint256).max);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("Panic(uint256)")), uint256(0x11)));
        redeemer.redeem(type(uint256).max);

        // Nothing moved.
        assertEq(tokenA.balanceOf(vault), 0);
        assertEq(tokenB.balanceOf(alice), 0);
    }

    // ---------------------------------------------------------------------
    // Contract recipients and the vault-as-caller self-transfer path
    // ---------------------------------------------------------------------

    function test_RedeemTo_ContractRecipient() public {
        uint256 amountA = 100e18;
        uint256 amountB = amountA * RATE_NUM / RATE_DEN;
        address walletRecipient = address(new MockSafeWallet(alice));

        _fundVault(amountB);
        _fundUser(alice, amountA);

        vm.prank(alice);
        uint256 got = redeemer.redeemTo(amountA, walletRecipient);

        assertEq(got, amountB);
        assertEq(tokenB.balanceOf(walletRecipient), amountB);
        assertEq(tokenA.balanceOf(vault), amountA);
    }

    function test_RedeemTo_VaultAsCallerPaysRecipient() public {
        // The vault redeeming its own tokenA: tokenA moves wallet -> wallet (self-transfer,
        // a no-op in ERC-20) and tokenB pays out to the (non-vault) recipient.
        uint256 amountA = 100e18;
        uint256 amountB = amountA * RATE_NUM / RATE_DEN;

        _fundVault(amountB);
        tokenA.mint(vault, amountA);
        vm.prank(vault);
        tokenA.approve(address(redeemer), type(uint256).max);

        vm.prank(vault);
        uint256 got = redeemer.redeemTo(amountA, bob);

        assertEq(got, amountB);
        assertEq(tokenA.balanceOf(vault), amountA); // unchanged: self-transfer
        assertEq(tokenB.balanceOf(bob), amountB);
        assertEq(tokenB.balanceOf(vault), 0);
    }

    // ---------------------------------------------------------------------
    // Non-standard ERC-20 return semantics (SafeERC20 boundary)
    // ---------------------------------------------------------------------

    function test_Redeem_RevertsWhenTokenAFalseReturn() public {
        MockFalseReturnERC20 falsey = new MockFalseReturnERC20();
        Migraine r = new Migraine(IERC20(address(falsey)), IERC20(address(tokenB)), vault, RATE_NUM, RATE_DEN);

        falsey.mint(alice, 100e18);
        vm.prank(alice);
        falsey.approve(address(r), type(uint256).max);
        tokenB.mint(vault, 1_000e18);
        vm.prank(vault);
        tokenB.approve(address(r), type(uint256).max);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(falsey)));
        r.redeem(100e18);

        // Whole tx reverted: the lying token's internal transfer never persisted.
        assertEq(falsey.balanceOf(alice), 100e18);
        assertEq(falsey.balanceOf(vault), 0);
    }

    function test_Redeem_RevertsWhenTokenBFalseReturn_Atomically() public {
        // Leg A (honest token) succeeds first; the false-return B leg reverts
        // the whole transaction — stateless contract + revert = atomic rollback.
        MockFalseReturnERC20 falseyB = new MockFalseReturnERC20();
        Migraine r = new Migraine(IERC20(address(tokenA)), IERC20(address(falseyB)), vault, RATE_NUM, RATE_DEN);

        tokenA.mint(alice, 100e18);
        vm.prank(alice);
        tokenA.approve(address(r), type(uint256).max);
        falseyB.mint(vault, 150e18);
        vm.prank(vault);
        falseyB.approve(address(r), type(uint256).max);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(falseyB)));
        r.redeem(100e18);

        assertEq(tokenA.balanceOf(alice), 100e18); // leg A rolled back
        assertEq(tokenA.balanceOf(vault), 0);
    }

    function test_Redeem_SucceedsWithLegacyNoReturnTokens() public {
        // USDT-style tokens with no return values: SafeERC20 accepts them.
        MockNoReturnERC20 legacyA = new MockNoReturnERC20();
        MockNoReturnERC20 legacyB = new MockNoReturnERC20();
        Migraine r = new Migraine(IERC20(address(legacyA)), IERC20(address(legacyB)), vault, RATE_NUM, RATE_DEN);

        legacyA.mint(alice, 100e18);
        vm.prank(alice);
        legacyA.approve(address(r), type(uint256).max);
        legacyB.mint(vault, 1_000e18);
        vm.prank(vault);
        legacyB.approve(address(r), type(uint256).max);

        vm.prank(alice);
        uint256 got = r.redeem(100e18);

        assertEq(got, 150e18);
        assertEq(legacyA.balanceOf(alice), 0);
        assertEq(legacyA.balanceOf(vault), 100e18);
        assertEq(legacyB.balanceOf(alice), 150e18);
        assertEq(legacyB.balanceOf(vault), 1_000e18 - 150e18);
    }

    function test_Redeem_MaxAllowanceNotConsumed() public {
        // OZ ERC-20 skips allowance decrement at MAX_UINT256 — the exact
        // modelled behaviour behind `redeemTo_success_run`'s non-MAX premise.
        _fundUser(alice, 100e18); // approves type(uint256).max
        _fundVault(1_000e18);

        vm.prank(alice);
        redeemer.redeem(100e18);

        assertEq(tokenA.allowance(alice, address(redeemer)), type(uint256).max);
        assertEq(tokenB.allowance(vault, address(redeemer)), type(uint256).max);
    }
}
