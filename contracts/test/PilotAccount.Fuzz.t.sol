// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {InkPilotBase} from "./InkPilotBase.t.sol";
import {PilotAccount} from "../PilotAccount.sol";

/// @dev Fuzz of protect(): progress + fund-flow confinement.
contract PilotAccountProtectFuzzTest is InkPilotBase {
    /// @dev After ANY successful protect that acted: HF improved or debt is zero; and USDC only ever left
    /// the account to the pool or the caller tip (never to the owner, a third party, or beyond the cap).
    function testFuzz_Protect_ProgressAndFundConfinement(
        uint256 dep, uint256 reserveAmt, uint256 drift, uint256 tipSetting, uint8 market
    ) public {
        dep = bound(dep, 1 * U, 20_000 * U);
        reserveAmt = bound(reserveAmt, 0, 30_000 * U);
        drift = bound(drift, 0, 20000);
        tipSetting = bound(tipSetting, 0, 1_000_000);
        _boost2x(dep);
        if (reserveAmt != 0) _fund(reserveAmt);
        vm.prank(alice);
        acct.setMaxTip(tipSetting);
        _accrueBorrow(drift);
        if (market % 3 == 1) pool.setFrozen(true);
        if (market % 3 == 2) pool.setBorrowingEnabled(false); // irrelevant to protect, must not matter

        address third = makeAddr("third");
        uint256 ownerBefore = usdc.balanceOf(alice);
        uint256 thirdBefore = usdc.balanceOf(third);
        uint256 keeperBefore = usdc.balanceOf(keeper);
        uint256 poolBefore = usdc.balanceOf(address(pool));
        uint256 reserveBefore = _reserve();
        uint256 debtBefore = _debt();

        vm.recordLogs();
        vm.prank(keeper);
        try acct.protect() {} catch { return; }
        (bool acted,, uint256 hfB, uint256 hfA,,) = _findProtected(vm.getRecordedLogs(), address(acct));

        uint256 keeperDelta = usdc.balanceOf(keeper) - keeperBefore;
        uint256 poolDelta = usdc.balanceOf(address(pool)) - poolBefore;
        assertEq(usdc.balanceOf(alice), ownerBefore, "owner not paid by protect");
        assertEq(usdc.balanceOf(third), thirdBefore);
        assertEq(reserveBefore - _reserve(), keeperDelta + poolDelta, "outflow == pool + tip");
        assertLe(keeperDelta, acct.riskParams().maxTipCap);
        assertLe(keeperDelta, tipSetting);

        if (acted) {
            assertTrue(_debt() == 0 || hfA > hfB, "hf improved or debt cleared");
        } else {
            assertEq(keeperDelta, 0, "no tip without action");
            assertEq(poolDelta, 0);
        }
    }

    /// @dev Protected(hfBefore, hfAfter) itself must show progress whenever debt remains, with cooldown stamped.
    function testFuzz_Protect_EventShowsProgress(uint256 dep, uint256 reserveAmt, uint256 drift) public {
        dep = bound(dep, 1 * U, 20_000 * U);
        reserveAmt = bound(reserveAmt, 0, 30_000 * U);
        drift = bound(drift, 0, 20000);
        _boost2x(dep);
        if (reserveAmt != 0) _fund(reserveAmt);
        _accrueBorrow(drift);
        vm.recordLogs();
        vm.prank(keeper);
        try acct.protect() {} catch { return; }
        (bool acted,, uint256 hfB, uint256 hfA,,) = _findProtected(vm.getRecordedLogs(), address(acct));
        if (!acted) return;
        assertTrue(_debt() == 0 || hfA > hfB, "hf improved or debt cleared");
        assertEq(acct.lastProtectAt(), block.timestamp);
    }
}
