// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MockTydroPool} from "./MockTydroPool.sol";

/// @title DemoTydroPool
/// @notice TESTNET-ONLY. A demo stand-in for a Tydro (Aave V3) pool whose stress switches are open to
///         everyone so anybody can try "market frozen" and "interest drift" in the app.
///         It is NOT Tydro, holds no real value, and must never be used in production.
contract DemoTydroPool is MockTydroPool {
    uint256 public constant MAX_DEMO_ACCRUAL_BPS = 2_000; // 20 percent per call

    error AccrualTooLarge(uint256 bps, uint256 max);

    constructor(address usdc) MockTydroPool(usdc) {
        // The pool owns itself, so only the demo wrappers below can reach the owner-only switches.
        _transferOwnership(address(this));
    }

    function demoSetFrozen(bool value) external { this.setFrozen(value); }

    /// @notice Makes borrowers' debt grow faster than supply, which lowers health factors.
    function demoAccrue(uint256 liquidityBps, uint256 borrowBps) external {
        if (liquidityBps > MAX_DEMO_ACCRUAL_BPS) revert AccrualTooLarge(liquidityBps, MAX_DEMO_ACCRUAL_BPS);
        if (borrowBps > MAX_DEMO_ACCRUAL_BPS) revert AccrualTooLarge(borrowBps, MAX_DEMO_ACCRUAL_BPS);
        this.accrueDemo(liquidityBps, borrowBps);
    }
}
