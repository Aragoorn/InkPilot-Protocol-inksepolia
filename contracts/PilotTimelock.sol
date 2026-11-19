// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title PilotTimelock
/// @notice Owner of PilotFactory. Every upgrade and parameter change must be scheduled and wait at least
///         the minimum delay (48 hours in the InkPilot deployment) before it can be executed, so users can exit.
///         Production: proposers and cancellers must be a 3-of-5 multisig with publicly known signers.
contract PilotTimelock is TimelockController {
    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        TimelockController(minDelay, proposers, executors, admin)
    {}
}
