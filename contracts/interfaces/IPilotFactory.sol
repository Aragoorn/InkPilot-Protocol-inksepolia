// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RiskLib} from "../RiskLib.sol";

/// @notice Shared ABI for immutable accounts and their governance configuration.
interface IPilotFactory {
    /// @notice Defaults for new accounts; existing accounts opt in via adoptFactoryParams().
    function riskParams() external view returns (RiskLib.RiskParams memory);
    function breakerOn() external view returns (bool);
    function asset() external view returns (address);
    function pool() external view returns (address);
}

interface IPilotAccountInitializer {
    function initialize(address owner, address factory) external;
}
