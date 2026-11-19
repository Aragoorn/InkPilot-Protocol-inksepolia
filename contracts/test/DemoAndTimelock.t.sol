// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DemoTydroPool} from "../DemoTydroPool.sol";
import {PilotTimelock} from "../PilotTimelock.sol";
import {MockERC20} from "../test-helpers/MockERC20.sol";

contract DemoAndTimelockTest is Test {
    DemoTydroPool pool;
    MockERC20 usdc;

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC", 6);
        pool = new DemoTydroPool(address(usdc));
    }

    function test_AnyoneCanFreezeButNotCallOwnerFunctions() public {
        vm.prank(address(0xBEEF));
        pool.demoSetFrozen(true);
        assertTrue(pool.frozen());
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        pool.setFrozen(false);
        assertEq(pool.owner(), address(pool));
    }

    function test_AccrualIsBounded() public {
        vm.expectRevert(abi.encodeWithSelector(DemoTydroPool.AccrualTooLarge.selector, 2_001, 2_000));
        pool.demoAccrue(0, 2_001);
        pool.demoAccrue(0, 500);
    }

    function test_TimelockEnforcesDelay() public {
        address[] memory p = new address[](1);
        p[0] = address(this);
        PilotTimelock t = new PilotTimelock(48 hours, p, p, address(0));
        assertEq(t.getMinDelay(), 48 hours);
        vm.expectRevert();
        t.schedule(address(pool), 0, "", bytes32(0), bytes32(0), 1 hours);
        t.schedule(address(pool), 0, "", bytes32(0), bytes32(0), 48 hours);
    }
}
