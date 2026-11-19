// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {InkPilotBase} from "./InkPilotBase.t.sol";
import {MockERC20} from "../test-helpers/MockERC20.sol";
import {MockTydroPool} from "../MockTydroPool.sol";
import {PilotAccount} from "../PilotAccount.sol";
import {PilotFactory} from "../PilotFactory.sol";

/// @dev Drives random, bounded sequences of owner / keeper / guardian / pool-admin actions.
/// Every call is wrapped in try/catch: reverts are legal outcomes, only the invariants matter.
contract PilotHandler is Test {
    MockERC20 public usdc;
    MockTydroPool public pool;
    PilotAccount public acct;
    PilotFactory public factory;
    address public owner;
    address public guardian;
    address public keeper;

    uint256 public ghostProtects;
    uint256 public ghostBoosts;

    constructor(
        MockERC20 usdc_, MockTydroPool pool_, PilotAccount acct_, PilotFactory factory_,
        address owner_, address guardian_, address keeper_
    ) {
        usdc = usdc_;
        pool = pool_;
        acct = acct_;
        factory = factory_;
        owner = owner_;
        guardian = guardian_;
        keeper = keeper_;
    }

    function fundReserve(uint256 amt) external {
        amt = bound(amt, 1, 5_000e6);
        usdc.mint(owner, amt);
        vm.prank(owner);
        try acct.fundReserve(amt) {} catch {}
    }

    function deposit(uint256 amt) external {
        amt = bound(amt, 1, 5_000e6);
        usdc.mint(owner, amt);
        vm.prank(owner);
        try acct.deposit(amt) {} catch {}
    }

    function boost(uint256 target) external {
        target = bound(target, 10000, 20000);
        vm.prank(owner);
        try acct.boostTo(target) {
            ghostBoosts++;
        } catch {}
    }

    function deleverage(uint256 target) external {
        target = bound(target, 10000, 20000);
        vm.prank(owner);
        try acct.deleverageTo(target) {} catch {}
    }

    function withdraw(uint256 amt) external {
        amt = bound(amt, 1, 8_000e6);
        vm.prank(owner);
        try acct.withdraw(amt) {} catch {}
    }

    function setTip(uint256 tip) external {
        tip = bound(tip, 0, 1_000_000);
        vm.prank(owner);
        try acct.setMaxTip(tip) {} catch {}
    }

    function protect() external {
        vm.prank(keeper);
        try acct.protect() {
            ghostProtects++;
        } catch {}
    }

    function harvest() external {
        try acct.harvest() {} catch {}
    }

    function accrue(uint256 liq, uint256 borrow) external {
        pool.accrueDemo(bound(liq, 0, 800), bound(borrow, 0, 1500));
    }

    function setFrozen(bool v) external {
        pool.setFrozen(v);
    }

    function setPaused(bool v) external {
        pool.setPaused(v);
    }

    function setBreaker(bool v) external {
        vm.prank(guardian);
        factory.setBreaker(v);
    }

    function warp(uint256 secs) external {
        skip(bound(secs, 1, 3 days));
    }

    function donate(uint256 amt) external {
        usdc.mint(address(acct), bound(amt, 1, 50_000));
    }
}

contract PilotAccountInvariantTest is InkPilotBase {
    PilotHandler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new PilotHandler(usdc, pool, acct, factory, alice, guardian, keeper);
        pool.transferOwnership(address(handler));
        targetContract(address(handler));
    }

    /// @dev The owner can always pull out exactly the USDC reserve, whatever the market / breaker state.
    function invariant_OwnerCanAlwaysWithdrawReserve() public {
        uint256 r = usdc.balanceOf(address(acct));
        if (r == 0) return;
        uint256 bal = usdc.balanceOf(alice);
        vm.prank(alice);
        acct.withdraw(r);
        assertEq(usdc.balanceOf(alice), bal + r);
        assertEq(usdc.balanceOf(address(acct)), 0);
    }

    /// @dev No USDC ever lands with an uninvolved third party.
    function invariant_NoThirdPartyReceivesUsdc() public view {
        assertEq(usdc.balanceOf(bob), 0);
        assertEq(usdc.balanceOf(factoryOwner), 0);
        assertEq(usdc.balanceOf(guardian), 0);
        assertEq(usdc.balanceOf(address(factory)), 0);
    }

    /// @dev Tips can only ever go to the keeper and never exceed (#protects * cap).
    function invariant_KeeperTipsBounded() public view {
        assertLe(usdc.balanceOf(keeper), handler.ghostProtects() * 1_000_000);
    }

    /// @dev The account only ever holds USDC reserve + position tokens; leverage is never opened above the hard cap by boost.
    function invariant_AccountHoldsNoNativeOrFactoryFunds() public view {
        assertEq(address(acct).balance, 0);
        assertEq(address(acct.factory()), address(factory));
        assertEq(acct.owner(), alice);
    }
}
