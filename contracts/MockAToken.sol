// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {MockIndexedToken} from "./MockIndexedToken.sol";

/// @notice Demo-only indexed, nontransferable USDC supply receipt.
contract MockAToken is MockIndexedToken {
    constructor(address pool_) MockIndexedToken("Demo supplied USDC", "maUSDC", pool_, false) {}
}
