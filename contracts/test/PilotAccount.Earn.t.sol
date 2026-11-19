// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {InkPilotBase} from "./InkPilotBase.t.sol";
import {MockERC20} from "../test-helpers/MockERC20.sol";
import {PilotAccount} from "../PilotAccount.sol";

/// @dev Earn-mode flows: deposit, fundReserve, withdraw, withdrawAll, owner access, rescue, setters.
contract PilotAccountEarnTest is InkPilotBase {
    // ---------------------------------------------------------------- deposit

    function test_Deposit_SuppliesToPoolAndTracksAccounting() public {
        uint256 before_ = usdc.balanceOf(alice);
        vm.expectEmit(false, false, false, true, address(acct));
        emit PilotAccount.Deposited(100 * U);
        _deposit(100 * U);
        assertEq(_coll(), 100 * U);
        assertEq(_debt(), 0);
        assertEq(_reserve(), 0);
        assertEq(acct.invested(), 100 * U);
        assertEq(acct.netDeposits(), int256(100 * U));
        assertEq(usdc.balanceOf(alice), before_ - 100 * U);
        // approvals reset to zero after use
        assertEq(usdc.allowance(address(acct), address(pool)), 0);
    }

    function test_Deposit_ZeroReverts() public {
        vm.prank(alice);
        vm.expectRevert(PilotAccount.InvalidAmount.selector);
        acct.deposit(0);
    }

    function test_Deposit_RevertsWithoutAllowance() public {
        vm.prank(alice);
        usdc.approve(address(acct), 0);
        vm.prank(alice);
        vm.expectRevert();
        acct.deposit(1 * U);
    }

    // ------------------------------------------------------------ fundReserve

    function test_FundReserve_HoldsUsdcInAccount() public {
        vm.expectEmit(false, false, false, true, address(acct));
        emit PilotAccount.ReserveFunded(40 * U);
        _fund(40 * U);
        assertEq(_reserve(), 40 * U);
        assertEq(_coll(), 0);
        assertEq(acct.invested(), 0, "reserve is not invested principal");
        assertEq(acct.netDeposits(), int256(40 * U));
    }

    function test_FundReserve_ZeroReverts() public {
        vm.prank(alice);
        vm.expectRevert(PilotAccount.InvalidAmount.selector);
        acct.fundReserve(0);
    }

    // --------------------------------------------------------------- withdraw

    function test_Withdraw_ReserveFirstThenPool() public {
        _fund(50 * U);
        _deposit(100 * U);
        uint256 bal = usdc.balanceOf(alice);

        vm.expectEmit(false, false, false, true, address(acct));
        emit PilotAccount.Withdrawn(30 * U);
        vm.prank(alice);
        acct.withdraw(30 * U);
        assertEq(_reserve(), 20 * U, "served from reserve");
        assertEq(_coll(), 100 * U, "pool untouched");
        assertEq(usdc.balanceOf(alice), bal + 30 * U);
        assertEq(acct.invested(), 100 * U);

        // spans reserve (20) + pool (50)
        vm.prank(alice);
        acct.withdraw(70 * U);
        assertEq(_reserve(), 0);
        assertEq(_coll(), 50 * U);
        assertEq(acct.invested(), 50 * U);
        assertEq(usdc.balanceOf(alice), bal + 100 * U);
        assertEq(acct.netDeposits(), int256(50 * U));
    }

    function test_Withdraw_PoolOnlyWhenNoReserve() public {
        _deposit(100 * U);
        vm.prank(alice);
        acct.withdraw(40 * U);
        assertEq(_coll(), 60 * U);
        assertEq(acct.invested(), 60 * U);
    }

    function test_Withdraw_ZeroReverts() public {
        vm.prank(alice);
        vm.expectRevert(PilotAccount.InvalidAmount.selector);
        acct.withdraw(0);
    }

    function test_Withdraw_MoreThanTotalReverts() public {
        _fund(10 * U);
        _deposit(10 * U);
        vm.prank(alice);
        vm.expectRevert();
        acct.withdraw(21 * U);
    }

    function test_Withdraw_NeverSendsToAnyoneButOwner() public {
        _fund(10 * U);
        _deposit(10 * U);
        vm.prank(alice);
        acct.withdraw(20 * U);
        assertEq(usdc.balanceOf(bob), 0);
        assertEq(usdc.balanceOf(keeper), 0);
        assertEq(usdc.balanceOf(address(acct)), 0);
    }

    // ------------------------------------------------------------- withdrawAll

    function test_WithdrawAll_EarnPlusReserve() public {
        _deposit(100 * U);
        _fund(25 * U);
        uint256 bal = usdc.balanceOf(alice);
        vm.expectEmit(false, false, false, true, address(acct));
        emit PilotAccount.Withdrawn(125 * U);
        vm.prank(alice);
        acct.withdrawAll();
        assertEq(usdc.balanceOf(alice), bal + 125 * U);
        assertEq(_coll(), 0);
        assertEq(_reserve(), 0);
        assertEq(acct.invested(), 0);
        assertEq(acct.netDeposits(), 0);
    }

    function test_WithdrawAll_UnwindsBoostedPosition() public {
        _boost2x(100 * U);
        _accrueBorrow(1000); // debt 110
        uint256 bal = usdc.balanceOf(alice);
        vm.prank(alice);
        acct.withdrawAll();
        assertEq(_debt(), 0);
        assertEq(_coll(), 0);
        assertEq(usdc.balanceOf(alice), bal + 90 * U, "equity = 200 - 110");
        assertEq(acct.invested(), 0);
    }

    function test_WithdrawAll_IncludesInterestEarned() public {
        _deposit(100 * U);
        pool.accrueDemo(500, 0); // +5% supply index
        uint256 bal = usdc.balanceOf(alice);
        vm.prank(alice);
        acct.withdrawAll();
        assertEq(usdc.balanceOf(alice), bal + 105 * U);
    }

    // ------------------------------------------------------------ owner access

    function test_OnlyOwner_EveryOwnerFunction() public {
        vm.startPrank(bob);
        vm.expectRevert(PilotAccount.OwnerOnly.selector);
        acct.deposit(1);
        vm.expectRevert(PilotAccount.OwnerOnly.selector);
        acct.fundReserve(1);
        vm.expectRevert(PilotAccount.OwnerOnly.selector);
        acct.withdraw(1);
        vm.expectRevert(PilotAccount.OwnerOnly.selector);
        acct.withdrawAll();
        vm.expectRevert(PilotAccount.OwnerOnly.selector);
        acct.setProfitMode(PilotAccount.ProfitMode.Compound);
        vm.expectRevert(PilotAccount.OwnerOnly.selector);
        acct.setMaxTip(1);
        vm.expectRevert(PilotAccount.OwnerOnly.selector);
        acct.boostTo(15000);
        vm.expectRevert(PilotAccount.OwnerOnly.selector);
        acct.deleverageTo(10000);
        vm.expectRevert(PilotAccount.OwnerOnly.selector);
        acct.emergencyExit();
        vm.expectRevert(PilotAccount.OwnerOnly.selector);
        acct.rescue(address(usdc), bob);
        vm.expectRevert(PilotAccount.OwnerOnly.selector);
        acct.adoptFactoryParams();
        vm.stopPrank();
    }

    function test_OnlyOwner_FactoryOwnerAndGuardianHaveNoAccess() public {
        vm.prank(factoryOwner);
        vm.expectRevert(PilotAccount.OwnerOnly.selector);
        acct.withdrawAll();
        vm.prank(guardian);
        vm.expectRevert(PilotAccount.OwnerOnly.selector);
        acct.emergencyExit();
    }

    // ------------------------------------------------------------------ rescue

    function test_Rescue_OtherTokenGoesToOwner() public {
        MockERC20 junk = new MockERC20("Junk", "J", 18);
        junk.mint(address(acct), 7 ether);
        vm.prank(alice);
        acct.rescue(address(junk), alice);
        assertEq(junk.balanceOf(alice), 7 ether);
        assertEq(junk.balanceOf(address(acct)), 0);
    }

    function test_Rescue_CannotTakeAssetOrPositionTokens() public {
        _fund(10 * U);
        _boost2x(10 * U);
        address aTok = address(acct.aToken());
        address dTok = address(acct.debtToken());
        vm.startPrank(alice);
        vm.expectRevert(PilotAccount.InvalidToken.selector);
        acct.rescue(address(usdc), alice);
        vm.expectRevert(PilotAccount.InvalidToken.selector);
        acct.rescue(aTok, alice);
        vm.expectRevert(PilotAccount.InvalidToken.selector);
        acct.rescue(dTok, alice);
        vm.stopPrank();
        assertEq(_reserve(), 10 * U);
    }

    function test_Rescue_RecipientMustBeOwnerAndTokenNonZero() public {
        MockERC20 junk = new MockERC20("Junk", "J", 18);
        junk.mint(address(acct), 1 ether);
        vm.startPrank(alice);
        vm.expectRevert(PilotAccount.InvalidAddress.selector);
        acct.rescue(address(junk), bob);
        vm.expectRevert(PilotAccount.InvalidAddress.selector);
        acct.rescue(address(0), alice);
        vm.stopPrank();
    }

    // ----------------------------------------------------------------- setters

    function test_SetMaxTip_BoundedByCap() public {
        vm.prank(alice);
        acct.setMaxTip(1_000_000);
        assertEq(acct.maxTip(), 1_000_000);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PilotAccount.TipTooHigh.selector, 1_000_001, 1_000_000));
        acct.setMaxTip(1_000_001);
    }

    function test_SetProfitMode_EmitsAndCompoundCheckpointsInvested() public {
        _deposit(100 * U);
        pool.accrueDemo(1000, 0); // equity 110
        vm.expectEmit(false, false, false, true, address(acct));
        emit PilotAccount.ProfitModeChanged(PilotAccount.ProfitMode.Compound);
        vm.prank(alice);
        acct.setProfitMode(PilotAccount.ProfitMode.Compound);
        assertEq(uint8(acct.profitMode()), 1);
        assertEq(acct.invested(), 110 * U);
        vm.prank(alice);
        acct.setProfitMode(PilotAccount.ProfitMode.Save);
        assertEq(uint8(acct.profitMode()), 0);
    }

    // ------------------------------------------------------------------- views

    function test_Snapshot_ReflectsPosition() public {
        _fund(5 * U);
        _boost2x(100 * U);
        PilotAccount.Snapshot memory s = acct.snapshot();
        assertEq(s.collateral, 200 * U);
        assertEq(s.debt, 100 * U);
        assertEq(s.reserve, 5 * U);
        assertEq(s.equity, 100 * U);
        assertEq(s.hfBps, 16000);
        assertEq(s.leverageBps, 20000);
        assertEq(uint8(s.status), uint8(PilotAccount.MarketStatus.Active));
        assertTrue(s.liquidationsAllowed);
        assertEq(s.netDeposits, int256(105 * U));
        assertEq(s.lifetimeProfit, 0);
    }

    function test_Snapshot_NoDebtIsMaxHf() public {
        _deposit(10 * U);
        assertEq(acct.snapshot().hfBps, type(uint16).max);
        assertEq(acct.snapshot().leverageBps, 10000);
    }

    function test_MarketStatus_ReflectsPoolFlags() public {
        assertEq(uint8(acct.marketStatus()), uint8(PilotAccount.MarketStatus.Active));
        pool.setFrozen(true);
        assertEq(uint8(acct.marketStatus()), uint8(PilotAccount.MarketStatus.Frozen));
        pool.setFrozen(false);
        pool.setLtv(0, 8000);
        assertEq(uint8(acct.marketStatus()), uint8(PilotAccount.MarketStatus.LtvZero));
        pool.setLtv(7500, 8000);
        pool.setPaused(true);
        assertEq(uint8(acct.marketStatus()), uint8(PilotAccount.MarketStatus.Paused));
    }

    // -------------------------------------------------------------------- fuzz

    function testFuzz_DepositWithdrawRoundTrip(uint256 amount, uint256 reserveAmt) public {
        amount = bound(amount, 1, 500_000 * U);
        reserveAmt = bound(reserveAmt, 0, 400_000 * U);
        uint256 start = usdc.balanceOf(alice);
        _deposit(amount);
        if (reserveAmt != 0) _fund(reserveAmt);
        assertEq(usdc.balanceOf(alice), start - amount - reserveAmt);
        vm.prank(alice);
        acct.withdraw(amount + reserveAmt);
        assertEq(usdc.balanceOf(alice), start, "round trip is lossless");
        assertEq(_coll(), 0);
        assertEq(_reserve(), 0);
        assertEq(acct.netDeposits(), 0);
    }

    function testFuzz_PartialWithdrawConservesFunds(uint256 amount, uint256 reserveAmt, uint256 w) public {
        amount = bound(amount, 1, 500_000 * U);
        reserveAmt = bound(reserveAmt, 0, 400_000 * U);
        _deposit(amount);
        if (reserveAmt != 0) _fund(reserveAmt);
        w = bound(w, 1, amount + reserveAmt);
        uint256 bal = usdc.balanceOf(alice);
        vm.prank(alice);
        acct.withdraw(w);
        assertEq(usdc.balanceOf(alice), bal + w);
        assertEq(_coll() + _reserve(), amount + reserveAmt - w);
        // reserve drained before pool
        if (w <= reserveAmt) assertEq(_coll(), amount);
    }
}
