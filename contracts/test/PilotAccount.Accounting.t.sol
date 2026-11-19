// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {InkPilotBase} from "./InkPilotBase.t.sol";
import {PilotAccount} from "../PilotAccount.sol";

/// @dev withdraw() leverage-cap behaviour and invested / profit / harvest accounting.
contract PilotAccountAccountingTest is InkPilotBase {
    // ------------------------------------------- withdraw leverage-cap regression

    /// @dev 200 collateral / 100 debt, withdraw 30 -> must auto-deleverage so leverage stays <= 2x.
    function test_Withdraw_AutoDeleveragesToKeepLeverageAtMostTwoX() public {
        _boost2x(100 * U);
        assertEq(_coll(), 200 * U);
        assertEq(_debt(), 100 * U);
        uint256 bal = usdc.balanceOf(alice);

        vm.expectEmit(false, false, false, true, address(acct));
        emit PilotAccount.Deleveraged(20000, 20000);
        vm.expectEmit(false, false, false, true, address(acct));
        emit PilotAccount.Withdrawn(30 * U);
        vm.prank(alice);
        acct.withdraw(30 * U);

        assertEq(usdc.balanceOf(alice), bal + 30 * U);
        assertEq(_coll(), 140 * U);
        assertEq(_debt(), 70 * U);
        assertLe(acct.snapshot().leverageBps, 20000, "leverage never above 2x after withdraw");
        assertGe(_hf(), 13000);
    }

    function test_Withdraw_StillWorksWhenInterestDriftPutLeverageAboveCap() public {
        _boost2x(100 * U);
        _accrueBorrow(1000); // debt 110, coll 200 -> leverage 2.22x
        assertGt(acct.snapshot().leverageBps, 20000);
        uint256 bal = usdc.balanceOf(alice);
        vm.prank(alice);
        acct.withdraw(30 * U);
        assertEq(usdc.balanceOf(alice), bal + 30 * U, "owner is paid");
        assertLe(acct.snapshot().leverageBps, 20000, "drift corrected on the way out");
        assertGt(_debt(), 0);
    }

    function test_Withdraw_FromReserveDoesNotTouchLeveragedPosition() public {
        _fund(50 * U);
        _boost2x(100 * U);
        vm.prank(alice);
        acct.withdraw(50 * U);
        assertEq(_coll(), 200 * U);
        assertEq(_debt(), 100 * U);
    }

    function test_Withdraw_FullEquityUnwindsDebtFirst() public {
        _boost2x(100 * U);
        uint256 bal = usdc.balanceOf(alice);
        vm.prank(alice);
        acct.withdraw(100 * U);
        assertEq(usdc.balanceOf(alice), bal + 100 * U);
        assertEq(_debt(), 0);
        assertEq(_coll(), 0);
    }

    function test_Withdraw_RevertsIfHfWouldEndBelowTier1() public {
        _boost2x(100 * U);
        pool.setLtv(6000, 6000); // 2x position now has HF 12000 < tier1 13000
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PilotAccount.HealthTooLow.selector, 12000, 13000));
        acct.withdraw(30 * U);
        assertEq(_coll(), 200 * U, "reverted atomically");
        assertEq(_debt(), 100 * U);
    }

    function testFuzz_Withdraw_LeverageNeverAboveCapAndOwnerPaid(uint256 dep, uint256 drift, uint256 w) public {
        dep = bound(dep, 10 * U, 100_000 * U);
        drift = bound(drift, 0, 1500);
        _boost2x(dep);
        _accrueBorrow(drift);
        uint256 equity = _coll() - _debt();
        w = bound(w, 1, (equity * 9) / 10);
        uint256 bal = usdc.balanceOf(alice);
        vm.prank(alice);
        acct.withdraw(w);
        assertEq(usdc.balanceOf(alice), bal + w);
        PilotAccount.Snapshot memory s = acct.snapshot();
        assertLe(s.leverageBps, 20000);
        if (s.debt != 0) assertGe(s.hfBps, 13000);
    }

    // ------------------------------------------------- invested / profit accounting

    /// @dev Regression: funding then withdrawing the reserve must not make principal look like profit.
    function test_Invested_ReserveFundThenWithdrawThenHarvestIsNotProfit() public {
        _deposit(1000 * U);
        _fund(100 * U);
        vm.prank(alice);
        acct.withdraw(100 * U); // reserve only
        assertEq(acct.invested(), 1000 * U);
        assertEq(_reserve(), 0);
        acct.harvest();
        assertEq(_reserve(), 0, "no principal treated as profit");
        assertEq(_coll(), 1000 * U);
        assertEq(acct.invested(), 1000 * U);
    }

    function test_Invested_OnlyRealYieldIsHarvestedAfterReserveRoundTrip() public {
        _deposit(1000 * U);
        _fund(100 * U);
        pool.accrueDemo(500, 0); // +50 yield
        vm.prank(alice);
        acct.withdraw(100 * U);
        vm.expectEmit(false, false, false, true, address(acct));
        emit PilotAccount.ProfitHarvested(PilotAccount.ProfitMode.Save, 50 * U);
        acct.harvest();
        assertEq(_reserve(), 50 * U, "exactly the yield");
        assertApproxEqAbs(_coll(), 1000 * U, 2, "aToken burn rounds up");
    }

    function test_Invested_PoolWithdrawReducesBaseline() public {
        _deposit(1000 * U);
        vm.prank(alice);
        acct.withdraw(400 * U);
        assertEq(acct.invested(), 600 * U);
        acct.harvest();
        assertEq(_coll(), 600 * U);
        assertEq(_reserve(), 0);
    }

    function test_Invested_ProtectSupplyIsNotProfit() public {
        _boost2x(1000 * U);
        _accrueBorrow(2800);
        _fund(400 * U);
        _protect(); // supplies 320 from reserve
        assertEq(acct.invested(), 1320 * U);
        acct.harvest();
        assertEq(_reserve(), 80 * U, "harvest moved nothing");
    }

    function test_Harvest_SaveModeMovesProfitToReserve() public {
        _deposit(1000 * U);
        pool.accrueDemo(500, 0);
        vm.expectEmit(false, false, false, true, address(acct));
        emit PilotAccount.ProfitHarvested(PilotAccount.ProfitMode.Save, 50 * U);
        vm.prank(keeper); // permissionless
        acct.harvest();
        assertEq(_reserve(), 50 * U);
        assertApproxEqAbs(_coll(), 1000 * U, 2, "aToken burn rounds up");
        assertEq(usdc.balanceOf(keeper), 0, "caller gets nothing");
        assertEq(acct.invested(), 1000 * U, "principal baseline not reduced");

        acct.harvest(); // nothing left to harvest
        assertEq(_reserve(), 50 * U);
    }

    function test_Harvest_CompoundModeKeepsProfitInvested() public {
        _deposit(1000 * U);
        vm.prank(alice);
        acct.setProfitMode(PilotAccount.ProfitMode.Compound);
        pool.accrueDemo(500, 0);
        vm.expectEmit(false, false, false, true, address(acct));
        emit PilotAccount.ProfitHarvested(PilotAccount.ProfitMode.Compound, 50 * U);
        acct.harvest();
        assertEq(_reserve(), 0, "profit stays in the pool");
        assertEq(_coll(), 1050 * U);
        assertEq(acct.invested(), 1050 * U, "checkpointed as principal");
    }

    function test_Harvest_BelowMinimumProfitIsNoop() public {
        _deposit(10 * U);
        pool.accrueDemo(1, 0); // +0.01% on 10 USDC = 1000 units < 10000
        acct.harvest();
        assertEq(_reserve(), 0);
    }

    function test_Harvest_WithDebtOnlyTakesProfitKeepingHealth() public {
        _boost2x(1000 * U);
        pool.accrueDemo(500, 0); // coll 2100, debt 1000 -> profit 100
        acct.harvest();
        assertEq(_reserve(), 100 * U);
        assertGe(_hf(), 14000);
    }

    function test_Harvest_SkippedWhenHfBelowSafeThreshold() public {
        _boost2x(1000 * U);
        pool.accrueDemo(5000, 9000); // coll 3000, debt 1900: equity 1100 > invested but HF ~12631
        assertLt(_hf(), 14000);
        acct.harvest();
        assertEq(_reserve(), 0);
        assertEq(_coll(), 3000 * U);
    }

    function test_Snapshot_LifetimeProfitTracksInterest() public {
        _deposit(1000 * U);
        pool.accrueDemo(500, 0);
        assertEq(acct.snapshot().lifetimeProfit, int256(50 * U));
        acct.harvest();
        assertApproxEqAbs(acct.snapshot().lifetimeProfit, int256(50 * U), 2, "harvest moves profit, does not create it");
    }
}
