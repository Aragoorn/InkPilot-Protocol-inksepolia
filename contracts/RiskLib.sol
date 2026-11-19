// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Shared risk configuration and bounds enforced independently by factory and accounts.
library RiskLib {
    struct RiskParams {
        uint16 tier1Bps;
        uint16 tier2Bps;
        uint16 tier3Bps;
        uint16 targetBps;
        uint16 maxLeverageBps;
        uint32 cooldown;
        uint96 fixedCost;
        uint96 maxTipCap;
        uint16[4] pBreakBps;
        uint16[5] pLiqBps;
    }

    /// @dev Field codes: 1 tier3 minimum, 2 tier1 maximum, 3 tier3/tier2 order,
    /// 4 tier2/tier1 order, 5 tier1/target order, 6 target maximum, 7 leverage,
    /// 8 cooldown, 9 tip cap, 10 fixed cost, 11-13 breakpoint order,
    /// 14-18 liquidation probability bounds, 19-22 probability order.
    error InvalidRiskParams(uint8 field);

    function validate(RiskParams memory p) internal pure {
        if (p.tier3Bps < 10500) revert InvalidRiskParams(1);
        if (p.tier1Bps > 20000) revert InvalidRiskParams(2);
        if (p.tier3Bps >= p.tier2Bps) revert InvalidRiskParams(3);
        if (p.tier2Bps >= p.tier1Bps) revert InvalidRiskParams(4);
        if (p.tier1Bps >= p.targetBps) revert InvalidRiskParams(5);
        if (p.targetBps > 30000) revert InvalidRiskParams(6);
        if (p.maxLeverageBps < 10000 || p.maxLeverageBps > 20000) revert InvalidRiskParams(7);
        if (p.cooldown > 1 hours) revert InvalidRiskParams(8);
        if (p.maxTipCap > 5000000) revert InvalidRiskParams(9);
        if (p.fixedCost > 1000000) revert InvalidRiskParams(10);
        for (uint8 i = 1; i < 4; ++i) {
            if (p.pBreakBps[i] <= p.pBreakBps[i - 1]) revert InvalidRiskParams(10 + i);
        }
        for (uint8 i; i < 5; ++i) {
            if (p.pLiqBps[i] > 10000) revert InvalidRiskParams(14 + i);
            if (i < 4 && p.pLiqBps[i] < p.pLiqBps[i + 1]) revert InvalidRiskParams(19 + i);
        }
    }
}
