// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice Factory proxy with a dedicated artifact. Pass encoded initialize calldata.
contract PilotProxy is ERC1967Proxy {
    constructor(address implementation, bytes memory data) payable ERC1967Proxy(implementation, data) {}
}
