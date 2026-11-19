// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {MockERC20} from "../test-helpers/MockERC20.sol";
import {MockTydroPool} from "../MockTydroPool.sol";
import {PilotAccount} from "../PilotAccount.sol";
import {PilotFactory} from "../PilotFactory.sol";
import {PilotProxy} from "../PilotProxy.sol";
import {RiskLib} from "../RiskLib.sol";

/// @dev Shared fixture: USDC(6dp) + MockTydroPool + factory behind PilotProxy + alice's account.
abstract contract InkPilotBase is Test {
    uint256 internal constant U = 1e6;

    MockERC20 internal usdc;
    MockTydroPool internal pool;
    PilotAccount internal accountImpl;
    PilotFactory internal factoryImpl;
    PilotFactory internal factory;
    PilotAccount internal acct;

    address internal factoryOwner = makeAddr("factoryOwner");
    address internal guardian = makeAddr("guardian");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal keeper = makeAddr("keeper");
    address internal lp = makeAddr("lp");

    function setUp() public virtual {
        vm.warp(1_000_000);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        pool = new MockTydroPool(address(usdc));
        accountImpl = new PilotAccount();
        factoryImpl = new PilotFactory();
        bytes memory data = abi.encodeCall(
            PilotFactory.initialize, (factoryOwner, address(accountImpl), address(pool), address(usdc), guardian)
        );
        factory = PilotFactory(address(new PilotProxy(address(factoryImpl), data)));

        // Deep pool liquidity from an unrelated LP so borrows/withdrawals are never liquidity-bound.
        usdc.mint(lp, 10_000_000 * U);
        vm.startPrank(lp);
        usdc.approve(address(pool), type(uint256).max);
        pool.supply(address(usdc), 10_000_000 * U, lp, 0);
        vm.stopPrank();

        vm.prank(alice);
        acct = PilotAccount(factory.createAccount(address(0)));
        usdc.mint(alice, 1_000_000 * U);
        vm.prank(alice);
        usdc.approve(address(acct), type(uint256).max);
    }

    // ---------------------------------------------------------------- helpers

    function _defaults() internal pure returns (RiskLib.RiskParams memory p) {
        p = RiskLib.RiskParams({
            tier1Bps: 13000,
            tier2Bps: 12000,
            tier3Bps: 11000,
            targetBps: 14500,
            maxLeverageBps: 20000,
            cooldown: 60,
            fixedCost: 20000,
            maxTipCap: 1000000,
            pBreakBps: [uint16(10500), 11000, 12000, 13000],
            pLiqBps: [uint16(3000), 1500, 500, 150, 25]
        });
    }

    function _deposit(uint256 amount) internal {
        vm.prank(alice);
        acct.deposit(amount);
    }

    function _fund(uint256 amount) internal {
        vm.prank(alice);
        acct.fundReserve(amount);
    }

    /// @dev Deposit `dep` then loop to 2x: collateral == 2*dep, debt == dep, HF == 16000 bps.
    function _boost2x(uint256 dep) internal {
        _deposit(dep);
        vm.prank(alice);
        acct.boostTo(20000);
    }

    function _accrueBorrow(uint256 bps) internal {
        pool.accrueDemo(0, bps);
    }

    function _coll() internal view returns (uint256) {
        return acct.aToken().balanceOf(address(acct));
    }

    function _debt() internal view returns (uint256) {
        return acct.debtToken().balanceOf(address(acct));
    }

    function _reserve() internal view returns (uint256) {
        return usdc.balanceOf(address(acct));
    }

    function _hf() internal view returns (uint256) {
        return acct.snapshot().hfBps;
    }

    function _protect() internal {
        vm.prank(keeper);
        acct.protect();
    }

    /// @dev Run protect() as `keeper` and decode the Protected event (found == false if none emitted).
    function _protectLogged()
        internal
        returns (bool found, uint8 tier, uint256 hfB, uint256 hfA, uint256 amount, address caller)
    {
        vm.recordLogs();
        vm.prank(keeper);
        acct.protect();
        return _findProtected(vm.getRecordedLogs(), address(acct));
    }

    function _findProtected(Vm.Log[] memory logs, address emitter)
        internal
        pure
        returns (bool found, uint8 tier, uint256 hfB, uint256 hfA, uint256 amount, address caller)
    {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == emitter && logs[i].topics[0] == PilotAccount.Protected.selector) {
                (tier, hfB, hfA, amount) = abi.decode(logs[i].data, (uint8, uint256, uint256, uint256));
                caller = address(uint160(uint256(logs[i].topics[1])));
                return (true, tier, hfB, hfA, amount, caller);
            }
        }
    }
}
