// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {InkPilotBase} from "./InkPilotBase.t.sol";
import {PilotFactory} from "../PilotFactory.sol";
import {RiskLib} from "../RiskLib.sol";

/// @dev Every bound of RiskLib.validate, exercised through PilotFactory.setRiskParams (owner only).
contract PilotFactoryRiskTest is InkPilotBase {
    function _expectInvalid(RiskLib.RiskParams memory p, uint8 field) internal {
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(RiskLib.InvalidRiskParams.selector, field));
        factory.setRiskParams(p);
    }

    function test_SetRiskParams_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, alice));
        factory.setRiskParams(_defaults());
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, guardian));
        factory.setRiskParams(_defaults());
    }

    function test_SetRiskParams_ValidEmitsAndStores() public {
        RiskLib.RiskParams memory p = _defaults();
        p.tier1Bps = 14000;
        p.tier2Bps = 12500;
        p.targetBps = 16000;
        p.cooldown = 300;
        p.maxTipCap = 2_000_000;
        vm.expectEmit(false, false, false, true, address(factory));
        emit PilotFactory.RiskParamsChanged(p);
        vm.prank(factoryOwner);
        factory.setRiskParams(p);
        assertEq(abi.encode(factory.riskParams()), abi.encode(p));
    }

    function test_SetRiskParams_AcceptsExactBoundaries() public {
        RiskLib.RiskParams memory p = _defaults();
        p.tier3Bps = 10500; // tier3 minimum
        p.tier1Bps = 20000; // tier1 maximum
        p.tier2Bps = 15000;
        p.targetBps = 30000; // target maximum
        p.maxLeverageBps = 20000;
        p.cooldown = 1 hours;
        p.maxTipCap = 5_000_000;
        p.fixedCost = 1_000_000;
        p.pLiqBps = [uint16(10000), 10000, 10000, 10000, 10000];
        vm.prank(factoryOwner);
        factory.setRiskParams(p);
        assertEq(factory.riskParams().tier1Bps, 20000);

        p.maxLeverageBps = 10000; // leverage minimum
        p.cooldown = 0;
        p.maxTipCap = 0;
        p.fixedCost = 0;
        vm.prank(factoryOwner);
        factory.setRiskParams(p);
        assertEq(factory.riskParams().maxLeverageBps, 10000);
    }

    function test_Bound1_Tier3BelowMinimum() public {
        RiskLib.RiskParams memory p = _defaults();
        p.tier3Bps = 10499;
        _expectInvalid(p, 1);
    }

    function test_Bound2_Tier1AboveMaximum() public {
        RiskLib.RiskParams memory p = _defaults();
        p.tier1Bps = 20001;
        _expectInvalid(p, 2);
    }

    function test_Bound3_Tier3NotBelowTier2() public {
        RiskLib.RiskParams memory p = _defaults();
        p.tier3Bps = p.tier2Bps;
        _expectInvalid(p, 3);
        p.tier3Bps = p.tier2Bps + 1;
        _expectInvalid(p, 3);
    }

    function test_Bound4_Tier2NotBelowTier1() public {
        RiskLib.RiskParams memory p = _defaults();
        p.tier2Bps = p.tier1Bps;
        _expectInvalid(p, 4);
    }

    function test_Bound5_Tier1NotBelowTarget() public {
        RiskLib.RiskParams memory p = _defaults();
        p.targetBps = p.tier1Bps;
        _expectInvalid(p, 5);
    }

    function test_Bound6_TargetAboveMaximum() public {
        RiskLib.RiskParams memory p = _defaults();
        p.targetBps = 30001;
        _expectInvalid(p, 6);
    }

    function test_Bound7_LeverageOutOfRange() public {
        RiskLib.RiskParams memory p = _defaults();
        p.maxLeverageBps = 9999;
        _expectInvalid(p, 7);
        p.maxLeverageBps = 20001;
        _expectInvalid(p, 7);
    }

    function test_Bound8_CooldownTooLong() public {
        RiskLib.RiskParams memory p = _defaults();
        p.cooldown = 1 hours + 1;
        _expectInvalid(p, 8);
    }

    function test_Bound9_TipCapTooHigh() public {
        RiskLib.RiskParams memory p = _defaults();
        p.maxTipCap = 5_000_001;
        _expectInvalid(p, 9);
    }

    function test_Bound10_FixedCostTooHigh() public {
        RiskLib.RiskParams memory p = _defaults();
        p.fixedCost = 1_000_001;
        _expectInvalid(p, 10);
    }

    function test_Bound11to13_BreakpointOrder() public {
        RiskLib.RiskParams memory p = _defaults();
        p.pBreakBps[1] = p.pBreakBps[0];
        _expectInvalid(p, 11);

        p = _defaults();
        p.pBreakBps[2] = p.pBreakBps[1];
        _expectInvalid(p, 12);

        p = _defaults();
        p.pBreakBps[3] = p.pBreakBps[2] - 1;
        _expectInvalid(p, 13);
    }

    function test_Bound14_LiquidationProbabilityAbove100pct() public {
        RiskLib.RiskParams memory p = _defaults();
        p.pLiqBps[0] = 10001;
        _expectInvalid(p, 14);
    }

    function test_Bound19to22_ProbabilityMonotonic() public {
        RiskLib.RiskParams memory p = _defaults();
        p.pLiqBps[0] = 1000; // < pLiq[1]=1500
        _expectInvalid(p, 19);

        p = _defaults();
        p.pLiqBps[2] = 2000; // > pLiq[1]
        _expectInvalid(p, 20);

        p = _defaults();
        p.pLiqBps[3] = 600; // > pLiq[2]=500
        _expectInvalid(p, 21);

        p = _defaults();
        p.pLiqBps[4] = 200; // > pLiq[3]=150
        _expectInvalid(p, 22);
    }

    /// @dev Fuzz: whatever the owner submits, if it is accepted then the stored params respect every documented bound.
    function testFuzz_SetRiskParams_AcceptedParamsAreWithinBounds(
        uint16 t1, uint16 t2, uint16 t3, uint16 tg, uint16 lev, uint32 cd, uint96 fc, uint96 tc
    ) public {
        RiskLib.RiskParams memory p = _defaults();
        p.tier1Bps = t1;
        p.tier2Bps = t2;
        p.tier3Bps = t3;
        p.targetBps = tg;
        p.maxLeverageBps = lev;
        p.cooldown = cd;
        p.fixedCost = fc;
        p.maxTipCap = tc;
        vm.prank(factoryOwner);
        try factory.setRiskParams(p) {
            RiskLib.RiskParams memory s = factory.riskParams();
            assertGe(s.tier3Bps, 10500);
            assertLe(s.tier1Bps, 20000);
            assertLt(s.tier3Bps, s.tier2Bps);
            assertLt(s.tier2Bps, s.tier1Bps);
            assertLt(s.tier1Bps, s.targetBps);
            assertLe(s.targetBps, 30000);
            assertGe(s.maxLeverageBps, 10000);
            assertLe(s.maxLeverageBps, 20000);
            assertLe(s.cooldown, 1 hours);
            assertLe(s.maxTipCap, 5_000_000);
            assertLe(s.fixedCost, 1_000_000);
        } catch {
            // rejected params must leave the stored defaults intact
            assertEq(factory.riskParams().tier1Bps, 13000);
        }
    }
}
