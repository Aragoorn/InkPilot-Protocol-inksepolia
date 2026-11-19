// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {InkPilotBase} from "./InkPilotBase.t.sol";
import {MockERC20} from "../test-helpers/MockERC20.sol";
import {PilotFactory} from "../PilotFactory.sol";
import {PilotAccount} from "../PilotAccount.sol";
import {PilotProxy} from "../PilotProxy.sol";
import {RiskLib} from "../RiskLib.sol";

contract PilotFactoryV2 is PilotFactory {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract PilotFactoryTest is InkPilotBase {
    function _initData(address o, address impl, address pl, address as_, address g) internal pure returns (bytes memory) {
        return abi.encodeCall(PilotFactory.initialize, (o, impl, pl, as_, g));
    }

    function _ownableErr(address who) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, who);
    }

    // ------------------------------------------------------------ initialize

    function test_Initialize_SetsState() public view {
        assertEq(factory.owner(), factoryOwner);
        assertEq(factory.guardian(), guardian);
        assertEq(factory.pool(), address(pool));
        assertEq(factory.asset(), address(usdc));
        assertEq(factory.accountImplementation(), address(accountImpl));
        assertEq(factory.allAccounts(), 1);
        assertFalse(factory.breakerOn());
        RiskLib.RiskParams memory p = factory.riskParams();
        RiskLib.RiskParams memory d = _defaults();
        assertEq(p.tier1Bps, d.tier1Bps);
        assertEq(p.tier2Bps, d.tier2Bps);
        assertEq(p.tier3Bps, d.tier3Bps);
        assertEq(p.targetBps, d.targetBps);
        assertEq(p.maxLeverageBps, d.maxLeverageBps);
        assertEq(p.cooldown, d.cooldown);
        assertEq(p.fixedCost, d.fixedCost);
        assertEq(p.maxTipCap, d.maxTipCap);
    }

    function test_Initialize_RevertsZeroOwner() public {
        vm.expectRevert(PilotFactory.InvalidAddress.selector);
        new PilotProxy(address(factoryImpl), _initData(address(0), address(accountImpl), address(pool), address(usdc), guardian));
    }

    function test_Initialize_RevertsZeroGuardian() public {
        vm.expectRevert(PilotFactory.InvalidAddress.selector);
        new PilotProxy(address(factoryImpl), _initData(factoryOwner, address(accountImpl), address(pool), address(usdc), address(0)));
    }

    function test_Initialize_RevertsAccountImplWithoutCode() public {
        vm.expectRevert(PilotFactory.InvalidAddress.selector);
        new PilotProxy(address(factoryImpl), _initData(factoryOwner, bob, address(pool), address(usdc), guardian));
    }

    function test_Initialize_RevertsPoolWithoutCode() public {
        vm.expectRevert(PilotFactory.InvalidAddress.selector);
        new PilotProxy(address(factoryImpl), _initData(factoryOwner, address(accountImpl), bob, address(usdc), guardian));
    }

    function test_Initialize_RevertsAssetWithoutCode() public {
        vm.expectRevert(PilotFactory.InvalidAddress.selector);
        new PilotProxy(address(factoryImpl), _initData(factoryOwner, address(accountImpl), address(pool), bob, guardian));
    }

    function test_Initialize_RevertsNon6Decimals() public {
        MockERC20 t18 = new MockERC20("X", "X", 18);
        vm.expectRevert(PilotFactory.InvalidDecimals.selector);
        new PilotProxy(address(factoryImpl), _initData(factoryOwner, address(accountImpl), address(pool), address(t18), guardian));
    }

    function test_Initialize_CannotBeCalledTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        factory.initialize(alice, address(accountImpl), address(pool), address(usdc), guardian);
    }

    function test_Implementation_InitializersDisabled() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        factoryImpl.initialize(alice, address(accountImpl), address(pool), address(usdc), guardian);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        accountImpl.initialize(alice, address(factory));
    }

    // --------------------------------------------------------- createAccount

    function test_CreateAccount_StoresAndEmitsReferrer() public {
        address predicted = Clones.predictDeterministicAddress(address(accountImpl), bytes32(uint256(uint160(bob))), address(factory));
        vm.expectEmit(true, true, true, false, address(factory));
        emit PilotFactory.AccountCreated(bob, predicted, alice);
        vm.prank(bob);
        address a = factory.createAccount(alice);
        assertEq(a, predicted);
        assertEq(factory.accountOf(bob), a);
        assertEq(factory.allAccounts(), 2);
        PilotAccount pa = PilotAccount(a);
        assertEq(pa.owner(), bob);
        assertEq(address(pa.factory()), address(factory));
        assertEq(address(pa.pool()), address(pool));
        assertEq(address(pa.asset()), address(usdc));
        assertEq(address(pa.aToken()), address(pool.aToken()));
        assertEq(address(pa.debtToken()), address(pool.debtToken()));
        assertEq(pa.maxTip(), 0);
    }

    function test_CreateAccount_SelfReferrerIsZeroed() public {
        address predicted = Clones.predictDeterministicAddress(address(accountImpl), bytes32(uint256(uint160(bob))), address(factory));
        vm.expectEmit(true, true, true, false, address(factory));
        emit PilotFactory.AccountCreated(bob, predicted, address(0));
        vm.prank(bob);
        factory.createAccount(bob);
    }

    function test_CreateAccount_OnePerOwner() public {
        vm.prank(alice);
        vm.expectRevert(PilotFactory.AccountAlreadyExists.selector);
        factory.createAccount(address(0));
    }

    function test_CreateAccount_AccountsAreIndependent() public {
        vm.prank(bob);
        PilotAccount b = PilotAccount(factory.createAccount(address(0)));
        assertTrue(address(b) != address(acct));
        assertEq(b.owner(), bob);
        assertEq(acct.owner(), alice);
    }

    function test_AccountInitialize_OnlyFactoryCanInit() public {
        address clone = Clones.clone(address(accountImpl));
        vm.expectRevert(PilotAccount.InvalidAddress.selector);
        PilotAccount(clone).initialize(bob, address(factory));
    }

    function test_AccountInitialize_CannotReinitialize() public {
        vm.prank(address(factory));
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        acct.initialize(bob, address(factory));
    }

    // ------------------------------------------------------ account impl/guardian

    function test_SetAccountImplementation_OnlyOwnerAndNeedsCode() public {
        PilotAccount newImpl = new PilotAccount();
        vm.prank(alice);
        vm.expectRevert(_ownableErr(alice));
        factory.setAccountImplementation(address(newImpl));

        vm.prank(factoryOwner);
        vm.expectRevert(PilotFactory.InvalidAddress.selector);
        factory.setAccountImplementation(bob);

        vm.expectEmit(true, false, false, false, address(factory));
        emit PilotFactory.AccountImplementationChanged(address(newImpl));
        vm.prank(factoryOwner);
        factory.setAccountImplementation(address(newImpl));
        assertEq(factory.accountImplementation(), address(newImpl));

        // New accounts use the new implementation; the old account is untouched.
        address predicted = Clones.predictDeterministicAddress(address(newImpl), bytes32(uint256(uint160(bob))), address(factory));
        vm.prank(bob);
        assertEq(factory.createAccount(address(0)), predicted);
        assertEq(acct.owner(), alice);
    }

    function test_SetGuardian() public {
        vm.prank(alice);
        vm.expectRevert(_ownableErr(alice));
        factory.setGuardian(bob);

        vm.prank(factoryOwner);
        vm.expectRevert(PilotFactory.InvalidAddress.selector);
        factory.setGuardian(address(0));

        vm.expectEmit(true, false, false, false, address(factory));
        emit PilotFactory.GuardianChanged(bob);
        vm.prank(factoryOwner);
        factory.setGuardian(bob);
        assertEq(factory.guardian(), bob);

        // old guardian loses power
        vm.prank(guardian);
        vm.expectRevert(PilotFactory.GuardianOnly.selector);
        factory.setBreaker(true);
    }

    // --------------------------------------------------------------- breaker

    function test_Breaker_OnlyGuardian() public {
        vm.prank(factoryOwner);
        vm.expectRevert(PilotFactory.GuardianOnly.selector);
        factory.setBreaker(true);
        vm.prank(alice);
        vm.expectRevert(PilotFactory.GuardianOnly.selector);
        factory.setBreaker(true);
    }

    function test_Breaker_OnOffAndEvent() public {
        vm.expectEmit(false, false, false, true, address(factory));
        emit PilotFactory.BreakerChanged(true, block.timestamp);
        vm.prank(guardian);
        factory.setBreaker(true);
        assertTrue(factory.breakerOn());
        assertEq(factory.breakerSetAt(), block.timestamp);

        vm.prank(guardian);
        factory.setBreaker(false);
        assertFalse(factory.breakerOn());
    }

    function test_Breaker_ExpiresAfterSevenDays() public {
        vm.prank(guardian);
        factory.setBreaker(true);
        skip(7 days - 1);
        assertTrue(factory.breakerOn());
        skip(1);
        assertFalse(factory.breakerOn());
    }

    function test_Breaker_GuardianCanRenewAfterExpiry() public {
        vm.prank(guardian);
        factory.setBreaker(true);
        skip(7 days + 1);
        assertFalse(factory.breakerOn());
        vm.prank(guardian);
        factory.setBreaker(true);
        assertTrue(factory.breakerOn());
        skip(7 days - 1);
        assertTrue(factory.breakerOn());
    }

    // ------------------------------------------------------------- ownership

    function test_Ownership_TwoStep() public {
        vm.prank(factoryOwner);
        factory.transferOwnership(bob);
        assertEq(factory.owner(), factoryOwner, "owner unchanged until accepted");
        assertEq(factory.pendingOwner(), bob);

        vm.prank(alice);
        vm.expectRevert(_ownableErr(alice));
        factory.acceptOwnership();

        vm.prank(bob);
        factory.acceptOwnership();
        assertEq(factory.owner(), bob);
        assertEq(factory.pendingOwner(), address(0));

        // old owner is powerless
        vm.prank(factoryOwner);
        vm.expectRevert(_ownableErr(factoryOwner));
        factory.setGuardian(alice);
    }

    function test_Ownership_PendingOwnerCannotActBeforeAccept() public {
        vm.prank(factoryOwner);
        factory.transferOwnership(bob);
        vm.prank(bob);
        vm.expectRevert(_ownableErr(bob));
        factory.setGuardian(alice);
    }

    function test_Ownership_RenounceDisabled() public {
        vm.prank(factoryOwner);
        vm.expectRevert(PilotFactory.RenounceDisabled.selector);
        factory.renounceOwnership();
        assertEq(factory.owner(), factoryOwner);

        vm.prank(alice);
        vm.expectRevert(_ownableErr(alice));
        factory.renounceOwnership();
    }

    // --------------------------------------------------------------- upgrade

    function test_Upgrade_OnlyOwner() public {
        PilotFactoryV2 v2 = new PilotFactoryV2();
        vm.prank(alice);
        vm.expectRevert(_ownableErr(alice));
        UUPSUpgradeable(address(factory)).upgradeToAndCall(address(v2), "");
        vm.prank(guardian);
        vm.expectRevert(_ownableErr(guardian));
        UUPSUpgradeable(address(factory)).upgradeToAndCall(address(v2), "");
    }

    function test_Upgrade_OwnerPreservesStateAndAccounts() public {
        PilotFactoryV2 v2 = new PilotFactoryV2();
        vm.prank(factoryOwner);
        UUPSUpgradeable(address(factory)).upgradeToAndCall(address(v2), "");
        assertEq(PilotFactoryV2(address(factory)).version(), 2);
        assertEq(factory.owner(), factoryOwner);
        assertEq(factory.accountOf(alice), address(acct));
        assertEq(factory.allAccounts(), 1);
        assertEq(factory.guardian(), guardian);
        assertEq(factory.pool(), address(pool));
        assertEq(factory.riskParams().tier1Bps, 13000);
        // factory still functional
        vm.prank(bob);
        factory.createAccount(address(0));
        assertEq(factory.allAccounts(), 2);
    }

    function test_Upgrade_RejectsNonUUPSImplementation() public {
        vm.prank(factoryOwner);
        vm.expectRevert();
        UUPSUpgradeable(address(factory)).upgradeToAndCall(address(usdc), "");
    }

    function test_Upgrade_ExistingAccountKeepsOwnRiskParams() public {
        RiskLib.RiskParams memory before_ = acct.riskParams();
        PilotFactoryV2 v2 = new PilotFactoryV2();
        vm.prank(factoryOwner);
        UUPSUpgradeable(address(factory)).upgradeToAndCall(address(v2), "");
        RiskLib.RiskParams memory after_ = acct.riskParams();
        assertEq(abi.encode(before_), abi.encode(after_));
        assertEq(acct.owner(), alice);
        assertEq(address(acct.pool()), address(pool));
    }

    // ------------------------------------------------- risk param isolation

    function _newParams() internal pure returns (RiskLib.RiskParams memory p) {
        p = _defaults();
        p.tier1Bps = 14000;
        p.tier2Bps = 12500;
        p.tier3Bps = 11500;
        p.targetBps = 15500;
        p.maxLeverageBps = 15000;
        p.cooldown = 120;
    }

    function test_ExistingAccountKeepsParamsAfterSetRiskParams() public {
        RiskLib.RiskParams memory old = acct.riskParams();
        vm.prank(factoryOwner);
        factory.setRiskParams(_newParams());
        assertEq(factory.riskParams().tier1Bps, 14000);
        assertEq(abi.encode(acct.riskParams()), abi.encode(old));
        assertEq(acct.riskParams().tier1Bps, 13000);

        // brand-new account gets the new defaults
        vm.prank(bob);
        PilotAccount b = PilotAccount(factory.createAccount(address(0)));
        assertEq(b.riskParams().tier1Bps, 14000);
        assertEq(b.riskParams().maxLeverageBps, 15000);
    }

    function test_AdoptFactoryParams_OwnerOnlyAndCopies() public {
        vm.prank(factoryOwner);
        factory.setRiskParams(_newParams());

        vm.prank(bob);
        vm.expectRevert(PilotAccount.OwnerOnly.selector);
        acct.adoptFactoryParams();

        RiskLib.RiskParams memory np = _newParams();
        vm.expectEmit(false, false, false, true, address(acct));
        emit PilotAccount.RiskParamsAdopted(np);
        vm.prank(alice);
        acct.adoptFactoryParams();
        assertEq(abi.encode(acct.riskParams()), abi.encode(np));
    }

    function test_AccountEnforcesAdoptedLeverageCap() public {
        vm.prank(factoryOwner);
        factory.setRiskParams(_newParams());
        // before adoption the old 2x cap holds
        _deposit(100 * U);
        vm.prank(alice);
        acct.adoptFactoryParams();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PilotAccount.InvalidTarget.selector, 16000, 10000, 15000));
        acct.boostTo(16000);
    }
}
