// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title TestUSDC
/// @notice TESTNET ONLY. A valueless 6-decimal token with a public faucet, used when no official test USDC
///         exists on the target testnet. Never deploy this to a network where the token could carry value.
contract TestUSDC is ERC20 {
    uint256 public constant FAUCET_AMOUNT = 1_000e6;
    uint256 public constant COOLDOWN = 6 hours;

    mapping(address => uint256) public lastClaim;

    error FaucetCooldown(uint256 nextClaimAt);

    constructor() ERC20("InkPilot Test USDC", "tUSDC") {}

    function decimals() public pure override returns (uint8) { return 6; }

    /// @notice Mints FAUCET_AMOUNT to the caller, once per COOLDOWN.
    function faucet() external {
        uint256 last = lastClaim[msg.sender];
        if (last != 0 && block.timestamp < last + COOLDOWN) revert FaucetCooldown(last + COOLDOWN);
        lastClaim[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);
    }
}
