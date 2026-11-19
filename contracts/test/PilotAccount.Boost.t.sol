// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {InkPilotBase} from "./InkPilotBase.t.sol";
import {PilotAccount} from "../PilotAccount.sol";
import {RiskLib} from "../RiskLib.sol";

/// @dev boostTo / deleverageTo / emergencyExit, market-status gates and the guardian breaker.
contract PilotAccountBoostTest is InkPilotBase {
    // ------------------------------------------------------------------ boost

    function test_BoostTo_MaxLeverageLoopsToTwoX() public {
        _deposit(100 * U);
        vm.expectEmit(false, false, false, true, address(acct));
        emit PilotAccount.Boosted(20000, 20000);
        vm.prank(alice);
        acct.boostTo(20000);
        assertEq(_coll(), 200 * U);
        assertEq(_debt(), 100 * U);
        assertEq(_hf(), 16000);
        assertEq(acct.snapshot().leverageBps, 20000);
        assertEq(usdc.allowance(address(acct), address(pool)), 0);
        assertEq(_reserve(), 0, "borrowed funds are all resupplied");
    }

    function test_BoostTo_PartialTarget() public {
        _deposit(100 * U);
        vm.prank(alice);
        acct.boostTo(15000);
        assertEq(_coll(), 150 * U);
        assertEq(_debt(), 50 * U);
    }

    function test_BoostTo_OneXIsNoop() public {
        _deposit(100 * U);
        vm.prank(alice);
        acct.boostTo(10000);
        assertEq(_debt(), 0);
        assertEq(_coll(), 100 * U);
    }

    function test_BoostTo_RejectsAboveHardCap() public {
        _deposit(100 * U);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PilotAccount.InvalidTarget.selector, 20001, 10000, 20000));
        acct.boostTo(20001);
        assertEq(_debt(), 0);
    }

    function test_BoostTo_RejectsBelowOneX() public {
        _deposit(100 * U);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PilotAccount.InvalidTarget.selector, 9999, 10000, 20000));
        acct.boostTo(9999);
    }

    function test_BoostTo_RejectsAboveAccountMaxLeverageParam() public {
        RiskLib.RiskParams memory p = _defaults();
        p.maxLeverageBps = 15000;
        vm.prank(factoryOwner);
        factory.setRiskParams(p);
        vm.prank(bob);
        PilotAccount b = PilotAccount(factory.createAccount(address(0)));
        usdc.mint(bob, 100 * U);
        vm.startPrank(bob);
        usdc.approve(address(b), type(uint256).max);
        b.deposit(100 * U);
        vm.expectRevert(abi.encodeWithSelector(PilotAccount.InvalidTarget.selector, 15001, 10000, 15000));
        b.boostTo(15001);
        b.boostTo(15000);
        vm.stopPrank();
    }

    function test_BoostTo_RequiresHfAtLeastTier1Plus1000() public {
        _deposit(100 * U);
        // lower the threshold so a 2x loop leaves HF = 2 * 6900 = 13800 < 14000
        pool.setLtv(6500, 6900);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PilotAccount.HealthTooLow.selector, 13800, 14000));
        acct.boostTo(20000);
        assertEq(_debt(), 0, "reverted atomically");
    }

    function test_BoostTo_HfAfterAlwaysMeetsMinimum() public {
        _deposit(100 * U);
        vm.prank(alice);
        acct.boostTo(20000);
        assertGe(_hf(), uint256(factory.riskParams().tier1Bps) + 1000);
    }

    function test_BoostTo_BlockedByBreaker() public {
        _deposit(100 * U);
        vm.prank(guardian);
        factory.setBreaker(true);
        vm.prank(alice);
        vm.expectRevert(PilotAccount.BreakerActive.selector);
        acct.boostTo(20000);
    }

    function test_BoostTo_AllowedAgainAfterBreakerExpires() public {
        _deposit(100 * U);
        vm.prank(guardian);
        factory.setBreaker(true);
        skip(7 days);
        vm.prank(alice);
        acct.boostTo(20000);
        assertEq(_debt(), 100 * U);
    }

    function test_BoostTo_BlockedWhenFrozen() public {
        _deposit(100 * U);
        pool.setFrozen(true);
        vm.prank(alice);
        vm.expectRevert(PilotAccount.MarketNotActive.selector);
        acct.boostTo(20000);
    }

    function test_BoostTo_BlockedWhenLtvZero() public {
        _deposit(100 * U);
        pool.setLtv(0, 8000);
        assertEq(uint8(acct.marketStatus()), uint8(PilotAccount.MarketStatus.LtvZero));
        vm.prank(alice);
        vm.expectRevert(PilotAccount.MarketNotActive.selector);
        acct.boostTo(20000);
        assertEq(_debt(), 0);
    }

    function test_BoostTo_BlockedWhenPaused() public {
        _deposit(100 * U);
        pool.setPaused(true);
        vm.prank(alice);
        vm.expectRevert(PilotAccount.MarketNotActive.selector);
        acct.boostTo(20000);
    }

    function test_BoostTo_BlockedWhenBorrowingDisabled() public {
        _deposit(100 * U);
        pool.setBorrowingEnabled(false);
        vm.prank(alice);
        vm.expectRevert(PilotAccount.BorrowingDisabled.selector);
        acct.boostTo(20000);
    }

    // --------------------------------------------------- market gates on deposit

    function test_Deposit_BlockedWhenFrozenWithCleanError() public {
        pool.setFrozen(true);
        vm.prank(alice);
        vm.expectRevert(PilotAccount.MarketNotActive.selector);
        acct.deposit(10 * U);
        assertEq(usdc.balanceOf(address(acct)), 0);
    }

    function test_Deposit_BlockedWhenLtvZeroOrPaused() public {
        pool.setLtv(0, 8000);
        vm.prank(alice);
        vm.expectRevert(PilotAccount.MarketNotActive.selector);
        acct.deposit(10 * U);
        pool.setLtv(7500, 8000);
        pool.setPaused(true);
        vm.prank(alice);
        vm.expectRevert(PilotAccount.MarketNotActive.selector);
        acct.deposit(10 * U);
    }

    function test_FundReserve_StillWorksWhenFrozenOrPaused() public {
        pool.setFrozen(true);
        _fund(10 * U);
        pool.setPaused(true);
        _fund(5 * U);
        assertEq(_reserve(), 15 * U);
    }

    // -------------------------------------------------------------- deleverage

    function test_DeleverageTo_PartialAndFull() public {
        _boost2x(100 * U);
        vm.expectEmit(false, false, false, true, address(acct));
        emit PilotAccount.Deleveraged(15000, 15000);
        vm.prank(alice);
        acct.deleverageTo(15000);
        assertEq(_coll(), 150 * U);
        assertEq(_debt(), 50 * U);

        vm.prank(alice);
        acct.deleverageTo(10000);
        assertEq(_debt(), 0);
        assertEq(_coll(), 100 * U);
    }

    function test_DeleverageTo_InvalidTargetAndPaused() public {
        _boost2x(100 * U);
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(PilotAccount.InvalidTarget.selector, 9999, 10000, 20000));
        acct.deleverageTo(9999);
        vm.expectRevert(abi.encodeWithSelector(PilotAccount.InvalidTarget.selector, 20001, 10000, 20000));
        acct.deleverageTo(20001);
        vm.stopPrank();
        pool.setPaused(true);
        vm.prank(alice);
        vm.expectRevert(PilotAccount.MarketPaused.selector);
        acct.deleverageTo(10000);
    }

    function test_DeleverageTo_WorksWhenFrozenAndBreakerOn() public {
        _boost2x(100 * U);
        pool.setFrozen(true);
        vm.prank(guardian);
        factory.setBreaker(true);
        vm.prank(alice);
        acct.deleverageTo(10000);
        assertEq(_debt(), 0);
    }

    function test_EmergencyExit_RepaysAllDebtWithATokens() public {
        _boost2x(100 * U);
        _accrueBorrow(1000);
        vm.expectEmit(false, false, false, true, address(acct));
        emit PilotAccount.ExitedToEarn(110 * U);
        vm.prank(alice);
        acct.emergencyExit();
        assertEq(_debt(), 0);
        assertEq(_coll(), 90 * U);
    }

    function test_EmergencyExit_RevertsWhenPaused() public {
        _boost2x(100 * U);
        pool.setPaused(true);
        vm.prank(alice);
        vm.expectRevert(PilotAccount.MarketPaused.selector);
        acct.emergencyExit();
    }

    // ----------------------------------------------------------------- breaker

    function test_Breaker_BlocksHarvestButNeverExitPaths() public {
        _boost2x(100 * U);
        _fund(50 * U);
        vm.prank(guardian);
        factory.setBreaker(true);

        vm.expectRevert(PilotAccount.BreakerActive.selector);
        acct.harvest();

        // withdraw (reserve + pool leg)
        uint256 bal = usdc.balanceOf(alice);
        vm.prank(alice);
        acct.withdraw(60 * U);
        assertEq(usdc.balanceOf(alice), bal + 60 * U);

        // emergencyExit
        vm.prank(alice);
        acct.emergencyExit();
        assertEq(_debt(), 0);

        // withdrawAll
        vm.prank(alice);
        acct.withdrawAll();
        assertEq(_coll(), 0);
    }

    function test_Breaker_NeverBlocksProtect() public {
        _boost2x(100 * U);
        _fund(100 * U);
        _accrueBorrow(2800); // HF 12500
        vm.prank(guardian);
        factory.setBreaker(true);
        assertTrue(factory.breakerOn());
        uint256 hfBefore = _hf();
        _protect();
        assertGt(_hf(), hfBefore);
    }

    function test_Breaker_NeverBlocksTier3Exit() public {
        _boost2x(100 * U);
        _accrueBorrow(4600);
        vm.prank(guardian);
        factory.setBreaker(true);
        _protect();
        assertEq(_debt(), 0);
    }

    function test_Breaker_NeverBlocksWithdrawAllWithDebt() public {
        _boost2x(100 * U);
        vm.prank(guardian);
        factory.setBreaker(true);
        uint256 bal = usdc.balanceOf(alice);
        vm.prank(alice);
        acct.withdrawAll();
        assertEq(usdc.balanceOf(alice), bal + 100 * U);
    }
}
