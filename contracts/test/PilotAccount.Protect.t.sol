// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {InkPilotBase} from "./InkPilotBase.t.sol";
import {PilotAccount} from "../PilotAccount.sol";
import {IAavePool} from "../interfaces/IAavePool.sol";

/// @dev protect(): tiers, gates, cooldown, tips, dust regression, frozen/paused markets.
/// Fixture: 1000 USDC deposit boosted to 2x -> coll 2000, debt 1000, HF 16000.
///   accrueBorrow(2800) -> debt 1280, HF 12500 (Tier 1 band)
///   accrueBorrow(3913) -> debt ~1391.3, HF ~11500 (Tier 2 band)
///   accrueBorrow(4600) -> debt 1460, HF ~10958 (Tier 3)
contract PilotAccountProtectTest is InkPilotBase {
    function _tier1Band() internal {
        _boost2x(1000 * U);
        _accrueBorrow(2800);
        assertEq(_hf(), 12500);
    }

    function _tier2Band() internal {
        _boost2x(1000 * U);
        _accrueBorrow(3913);
        assertGe(_hf(), 11000 + 1);
        assertLt(_hf(), 12000);
    }

    // ------------------------------------------------------------ revert gates

    function test_Protect_NothingToProtectWhenNoDebt() public {
        _deposit(100 * U);
        vm.expectRevert(PilotAccount.NothingToProtect.selector);
        acct.protect();
    }

    function test_Protect_HealthyReverts() public {
        _boost2x(1000 * U);
        vm.expectRevert(PilotAccount.Healthy.selector);
        acct.protect();
    }

    function test_Protect_HealthyJustAboveTier1() public {
        _boost2x(1000 * U);
        // HF = 2000*8000/debt >= 13000 -> debt <= 1230.76; accrue 23% -> 1230 -> HF 13008
        _accrueBorrow(2300);
        assertGe(_hf(), 13000);
        vm.expectRevert(PilotAccount.Healthy.selector);
        acct.protect();
    }

    // ------------------------------------------------------------------ Tier 1

    function test_Tier1_SupplyFromReserve() public {
        _tier1Band();
        _fund(400 * U);
        vm.expectEmit(true, false, false, true, address(acct));
        emit PilotAccount.Protected(1, 12500, 14500, 320 * U, keeper);
        _protect();
        assertEq(_coll(), 2320 * U);
        assertEq(_debt(), 1280 * U);
        assertEq(_reserve(), 80 * U);
        assertEq(_hf(), 14500);
        assertEq(acct.invested(), 1000 * U + 320 * U, "supplied reserve becomes invested principal");
        assertEq(acct.lastProtectAt(), block.timestamp);
        assertEq(usdc.allowance(address(acct), address(pool)), 0);
    }

    function test_Tier1_PartialReserveThenSelfDeleverage() public {
        _tier1Band();
        _fund(100 * U); // needed is 320
        (bool found, uint8 tier,,, uint256 amount,) = _protectLogged();
        assertTrue(found);
        assertEq(tier, 4, "self-deleverage tail escalates the tier code");
        assertGt(amount, 100 * U);
        assertEq(_reserve(), 0);
        assertGe(_hf(), 14490);
    }

    // ------------------------------------------------------------------ Tier 2

    function test_Tier2_RepayFromReserve() public {
        _tier2Band();
        _fund(400 * U);
        uint256 collBefore = _coll();
        uint256 debtBefore = _debt();
        (bool found, uint8 tier, uint256 hfB, uint256 hfA, uint256 amount,) = _protectLogged();
        assertTrue(found);
        assertEq(tier, 2);
        assertLt(hfB, 12000);
        assertGe(hfA, 14490);
        assertEq(_coll(), collBefore, "tier 2 repays, never supplies");
        assertApproxEqAbs(_debt(), debtBefore - amount, 2, "debt token rounding only");
        assertEq(_reserve(), 400 * U - amount);
    }

    // ---------------------------------------------------------------- Tier 2b

    function test_Tier2b_SelfDeleverageWithEmptyReserve_Tier1Band() public {
        _tier1Band();
        assertEq(_reserve(), 0);
        uint256 collBefore = _coll();
        vm.expectEmit(true, false, false, false, address(acct));
        emit PilotAccount.Protected(4, 12500, 14500, 0, keeper);
        _protect();
        assertLt(_coll(), collBefore);
        assertGe(_hf(), 14490);
        assertGt(_debt(), 0, "partial unwind only; position stays open");
    }

    function test_Tier2b_SelfDeleverageWithEmptyReserve_Tier2Band() public {
        _tier2Band();
        (bool found, uint8 tier,,,,) = _protectLogged();
        assertTrue(found);
        assertEq(tier, 4);
        assertGe(_hf(), 14490);
    }

    // ------------------------------------------------------------------ Tier 3

    function test_Tier3_ExitRepaysAllDebt() public {
        _boost2x(1000 * U);
        _accrueBorrow(4600);
        assertLe(_hf(), 11000);
        (bool found, uint8 tier,, uint256 hfA, uint256 amount,) = _protectLogged();
        assertTrue(found);
        assertEq(tier, 3);
        assertEq(amount, 1460 * U);
        assertEq(hfA, type(uint256).max);
        assertEq(_debt(), 0);
        assertEq(_coll(), 540 * U);
    }

    function test_Tier3_IgnoresEconomicGateForTinyDebt() public {
        _boost2x(1 * U);
        _accrueBorrow(4600);
        _protect();
        assertEq(_debt(), 0);
    }

    function test_Tier3_IgnoresCooldown() public {
        _tier1Band();
        _fund(1000 * U);
        _protect();
        _accrueBorrow(3200); // debt 1689.6 vs coll 2320 -> HF ~10985
        assertLe(_hf(), 11000);
        _protect(); // no warp: tier 3 has no cooldown
        assertEq(_debt(), 0);
    }

    function test_Protect_NoProgressRevertsWhenInsolvent() public {
        _boost2x(1000 * U);
        _accrueBorrow(15000); // debt 2500 > coll 2000
        uint256 debtBefore = _debt();
        vm.expectRevert(PilotAccount.NoProgress.selector);
        acct.protect();
        assertEq(_debt(), debtBefore, "reverted atomically");
        assertEq(_coll(), 2000 * U);
    }

    // ---------------------------------------------------------------- cooldown

    function test_Cooldown_BlocksSecondProtectUntilElapsed() public {
        _tier1Band();
        _fund(1000 * U);
        _protect();
        uint256 t0 = acct.lastProtectAt();
        _accrueBorrow(1500); // debt 1472 -> HF ~12608, Tier 1 band again
        assertLt(_hf(), 13000);
        assertGe(_hf(), 12000);

        vm.expectRevert(abi.encodeWithSelector(PilotAccount.CooldownActive.selector, t0 + 60));
        acct.protect();
        skip(59);
        vm.expectRevert(abi.encodeWithSelector(PilotAccount.CooldownActive.selector, t0 + 60));
        acct.protect();
        skip(1);
        _protect();
        assertGe(_hf(), 14490);
        assertEq(acct.lastProtectAt(), t0 + 60);
    }

    // ----------------------------------------------------------- economic gate

    function test_EconomicGate_TinyDebtSkipped() public {
        _boost2x(1 * U);
        _accrueBorrow(2800);
        assertLt(_hf(), 13000);
        _fund(10 * U);
        vm.prank(alice);
        acct.setMaxTip(500_000);
        uint256 hfBefore = _hf();
        uint256 keeperBal = usdc.balanceOf(keeper);
        vm.expectEmit(false, false, false, true, address(acct));
        emit PilotAccount.ProtectionSkipped("uneconomic");
        _protect();
        assertEq(_hf(), hfBefore);
        assertEq(_reserve(), 10 * U, "nothing moved");
        assertEq(usdc.balanceOf(keeper), keeperBal, "no tip when skipped");
        assertEq(acct.lastProtectAt(), 0);
    }

    function test_EconomicGate_TipRaisesTheBar() public {
        // debt 102.4 -> expectedLoss 38400 > fixedCost 20000 -> acts without a tip ...
        _boost2x(80 * U);
        _accrueBorrow(2800);
        _fund(100 * U);
        uint256 snap = vm.snapshotState();
        _protect();
        assertGt(acct.lastProtectAt(), 0);

        // ... but with a 1 USDC tip the same position is not worth protecting.
        vm.revertToState(snap);
        vm.prank(alice);
        acct.setMaxTip(1_000_000);
        vm.expectEmit(false, false, false, true, address(acct));
        emit PilotAccount.ProtectionSkipped("uneconomic");
        _protect();
        assertEq(acct.lastProtectAt(), 0);
    }

    // --------------------------------------------------------------------- tip

    /// @dev Tips raise the economic bar, so tip tests use a larger position (debt 6400 at HF 12500).
    function _bigTier1Band() internal {
        _boost2x(5000 * U);
        _accrueBorrow(2800); // coll 10000, debt 6400, needed supply 1600
        assertEq(_hf(), 12500);
    }

    function test_Tip_PaidToCallerWhenActionHappened() public {
        _bigTier1Band();
        _fund(2000 * U);
        vm.prank(alice);
        acct.setMaxTip(500_000);
        vm.expectEmit(true, false, false, true, address(acct));
        emit PilotAccount.TipPaid(keeper, 500_000);
        _protect();
        assertEq(usdc.balanceOf(keeper), 500_000);
        assertEq(_reserve(), 400 * U - 500_000);
    }

    function test_Tip_CappedByAccountMaxTipCap() public {
        _bigTier1Band();
        _fund(2000 * U);
        vm.prank(alice);
        acct.setMaxTip(1_000_000); // == cap, the most the owner may set
        _protect();
        assertEq(usdc.balanceOf(keeper), 1_000_000);
    }

    function test_Tip_CappedByRemainingReserve() public {
        _bigTier1Band();
        _fund(1600 * U + 200_000); // 0.2 USDC left after the supply
        vm.prank(alice);
        acct.setMaxTip(1_000_000);
        _protect();
        assertEq(usdc.balanceOf(keeper), 200_000);
        assertEq(_reserve(), 0);
    }

    function test_Tip_ZeroByDefault() public {
        _tier1Band();
        _fund(400 * U);
        _protect();
        assertEq(usdc.balanceOf(keeper), 0);
    }

    function test_Tip_NotPaidWhenProtectReverts() public {
        _boost2x(1000 * U);
        _fund(10 * U);
        vm.prank(alice);
        acct.setMaxTip(500_000);
        vm.prank(keeper);
        vm.expectRevert(PilotAccount.Healthy.selector);
        acct.protect();
        assertEq(usdc.balanceOf(keeper), 0);
    }

    function test_Tip_PaidOnTier3Exit() public {
        _boost2x(1000 * U);
        _fund(5 * U);
        vm.prank(alice);
        acct.setMaxTip(250_000);
        _accrueBorrow(4600);
        _protect();
        assertEq(usdc.balanceOf(keeper), 250_000);
    }

    // ------------------------------------------------------------------- dust

    /// @dev Regression: a 1-unit donation makes reserve != 0 but below the 1-USDC min step.
    /// protect() must still succeed through self-deleverage instead of reverting/skipping.
    function test_Dust_OneUnitDonationInTier1BandStillProtects() public {
        _tier1Band();
        usdc.mint(address(acct), 1);
        assertEq(_reserve(), 1);
        uint256 hfBefore = _hf();
        (bool found, uint8 tier,, uint256 hfA, uint256 amount,) = _protectLogged();
        assertTrue(found, "protect must act, not skip");
        assertEq(tier, 4);
        assertGt(amount, 0);
        assertGt(_hf(), hfBefore);
        assertGe(hfA, 14490);
        assertEq(_reserve(), 1, "dust untouched");
    }

    function test_Dust_OneUnitDonationInTier2BandStillProtects() public {
        _tier2Band();
        usdc.mint(address(acct), 1);
        (bool found, uint8 tier,,,,) = _protectLogged();
        assertTrue(found);
        assertEq(tier, 4);
        assertGe(_hf(), 14490);
    }

    function test_Dust_BelowMinStepReserveIsNotMovedButProtectSucceeds() public {
        _tier1Band();
        usdc.mint(address(acct), 9999);
        _protect();
        assertEq(_reserve(), 9999);
        assertGe(_hf(), 14490);
    }

    // ------------------------------------------------------------ frozen market

    function test_Frozen_SkipsTier1AndStillRepaysFromReserve() public {
        _tier1Band();
        _fund(400 * U);
        pool.setFrozen(true);
        uint256 collBefore = _coll();
        (bool found, uint8 tier,, uint256 hfA, uint256 amount,) = _protectLogged();
        assertTrue(found);
        assertEq(tier, 2, "repay path, not supply");
        assertEq(_coll(), collBefore, "no supply into a frozen reserve");
        assertGt(amount, 0);
        assertGe(hfA, 14490);
        assertEq(_reserve(), 400 * U - amount);
    }

    function test_Frozen_EmptyReserveSelfDeleverages() public {
        _tier1Band();
        pool.setFrozen(true);
        _protect();
        assertGe(_hf(), 14490);
    }

    function test_Frozen_Tier3StillExits() public {
        _boost2x(1000 * U);
        _accrueBorrow(4600);
        pool.setFrozen(true);
        _protect();
        assertEq(_debt(), 0);
    }

    function test_Frozen_WithdrawAndWithdrawAllStillWork() public {
        _deposit(100 * U);
        pool.setFrozen(true);
        vm.prank(alice);
        acct.withdraw(40 * U);
        vm.prank(alice);
        acct.withdrawAll();
        assertEq(_coll(), 0);
    }

    // ------------------------------------------------------------- paused market

    function test_Paused_ProtectRevertsCleanlyWithoutTouchingPool() public {
        _tier1Band();
        _fund(400 * U);
        pool.setPaused(true);
        uint256 coll = _coll();
        uint256 debt = _debt();
        uint256 reserve = _reserve();
        vm.expectCall(address(pool), abi.encodeWithSelector(IAavePool.supply.selector), 0);
        vm.expectCall(address(pool), abi.encodeWithSelector(IAavePool.repay.selector), 0);
        vm.expectCall(address(pool), abi.encodeWithSelector(IAavePool.repayWithATokens.selector), 0);
        vm.expectCall(address(pool), abi.encodeWithSelector(IAavePool.withdraw.selector), 0);
        vm.expectRevert(PilotAccount.MarketPaused.selector);
        acct.protect();
        assertEq(_coll(), coll);
        assertEq(_debt(), debt);
        assertEq(_reserve(), reserve);
        assertEq(acct.lastProtectAt(), 0);
    }

    function test_Paused_ReserveWithdrawStillWorksPoolLegReverts() public {
        _fund(30 * U);
        _deposit(100 * U);
        pool.setPaused(true);
        uint256 bal = usdc.balanceOf(alice);
        vm.prank(alice);
        acct.withdraw(30 * U); // reserve only
        assertEq(usdc.balanceOf(alice), bal + 30 * U);

        vm.prank(alice);
        vm.expectRevert(PilotAccount.MarketPaused.selector);
        acct.withdraw(1 * U); // needs the pool

        vm.prank(alice);
        vm.expectRevert(PilotAccount.MarketPaused.selector);
        acct.withdrawAll();
        vm.expectRevert(PilotAccount.MarketPaused.selector);
        acct.harvest();
    }
}
