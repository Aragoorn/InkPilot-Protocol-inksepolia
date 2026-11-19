// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {TestUSDC} from "../TestUSDC.sol";

contract TestUSDCTest is Test {
    TestUSDC t;
    address alice = address(0xA11CE);

    function setUp() public { t = new TestUSDC(); }

    function test_FaucetMintsOncePerCooldown() public {
        assertEq(t.decimals(), 6);
        vm.startPrank(alice);
        t.faucet();
        assertEq(t.balanceOf(alice), 1_000e6);
        vm.expectRevert(abi.encodeWithSelector(TestUSDC.FaucetCooldown.selector, block.timestamp + 6 hours));
        t.faucet();
        vm.warp(block.timestamp + 6 hours);
        t.faucet();
        assertEq(t.balanceOf(alice), 2_000e6);
        vm.stopPrank();
    }
}
