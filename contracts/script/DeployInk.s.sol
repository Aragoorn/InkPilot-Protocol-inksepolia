// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {PilotAccount} from "../PilotAccount.sol";
import {PilotFactory} from "../PilotFactory.sol";
import {PilotProxy} from "../PilotProxy.sol";
import {PilotTimelock} from "../PilotTimelock.sol";
import {TestUSDC} from "../TestUSDC.sol";
import {DemoTydroPool} from "../DemoTydroPool.sol";
import {IAavePool} from "../interfaces/IAavePool.sol";

/// @notice Deploys InkPilot to Ink Sepolia (chain 763373) only. It refuses to run on any other chain.
/// Environment (all optional):
///   ASSET              6-decimal stablecoin. If unset, a public-faucet TestUSDC is deployed.
///   POOL               Aave V3 style pool (for example a Tydro test market). If unset, DemoTydroPool is deployed.
///   TIMELOCK_PROPOSER  proposer, canceller and executor of the timelock. Default: shared platform wallet (testnet only).
///   GUARDIAN           circuit breaker key. Default: shared platform wallet (testnet only).
///   TIMELOCK_DELAY     seconds, at least 172800 (48 hours).
/// The broadcaster is whatever key forge is given with --private-key or --account. No key is read here.
contract DeployInk is Script {
    uint256 internal constant INK_SEPOLIA = 763373;
    /// @dev Shared Arc Studio platform wallet. Testnet placeholder only: nobody using this project can sign with it.
    address internal constant PLATFORM_WALLET = 0x5B12Ce46C7194aD57d143bC22847224047b1Ef42;

    function run() external {
        require(block.chainid == INK_SEPOLIA, "DeployInk: Ink Sepolia (763373) only");

        address asset = vm.envOr("ASSET", address(0));
        address pool = vm.envOr("POOL", address(0));
        address proposer = vm.envOr("TIMELOCK_PROPOSER", PLATFORM_WALLET);
        address guardian = vm.envOr("GUARDIAN", PLATFORM_WALLET);
        uint256 delay = vm.envOr("TIMELOCK_DELAY", uint256(48 hours));

        require(pool == address(0) || asset != address(0), "DeployInk: set ASSET when POOL is set");
        require(delay >= 48 hours, "DeployInk: timelock delay below 48 hours");
        require(proposer != address(0) && guardian != address(0), "DeployInk: zero admin");
        if (pool != address(0)) {
            require(pool.code.length > 0 && asset.code.length > 0, "DeployInk: POOL or ASSET has no code");
            require(IAavePool(pool).getReserveData(asset).aTokenAddress != address(0), "DeployInk: asset is not a reserve of POOL");
        }

        vm.startBroadcast();
        if (asset == address(0)) asset = address(new TestUSDC());
        if (pool == address(0)) pool = address(new DemoTydroPool(asset));

        address accountImpl = address(new PilotAccount());
        address factoryImpl = address(new PilotFactory());

        address[] memory team = new address[](1);
        team[0] = proposer;
        address timelock = address(new PilotTimelock(delay, team, team, address(0)));

        bytes memory init = abi.encodeCall(PilotFactory.initialize, (timelock, accountImpl, pool, asset, guardian));
        address proxy = address(new PilotProxy(factoryImpl, init));
        vm.stopBroadcast();

        console2.log("chain id        ", block.chainid);
        console2.log("asset           ", asset);
        console2.log("pool            ", pool);
        console2.log("account impl    ", accountImpl);
        console2.log("factory impl    ", factoryImpl);
        console2.log("timelock        ", timelock);
        console2.log("factory (proxy) ", proxy);
        console2.log("guardian        ", guardian);
        console2.log("proposer        ", proposer);
    }
}
