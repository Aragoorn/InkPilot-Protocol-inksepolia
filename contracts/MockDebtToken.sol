// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {MockIndexedToken} from "./MockIndexedToken.sol";

/// @notice Demo-only indexed, nontransferable variable USDC debt receipt.
contract MockDebtToken is MockIndexedToken {
    constructor(address pool_) MockIndexedToken("Demo variable USDC debt", "mdUSDC", pool_, true) {}
}
