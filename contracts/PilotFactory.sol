// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPilotFactory, IPilotAccountInitializer} from "./interfaces/IPilotFactory.sol";
import {RiskLib} from "./RiskLib.sol";

/// @notice UUPS registry for immutable, individually owned InkPilot clones.
/// @dev Risk parameter changes apply to new accounts; existing owners opt in via adoptFactoryParams().
/// Existing clones never delegate to this implementation.
contract PilotFactory is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuard, IPilotFactory {
    address public override asset;
    address public override pool;
    address public guardian;
    address public accountImplementation;
    mapping(address => address) public accountOf;
    uint256 public allAccounts;
    uint256 public breakerSetAt;
    bool private _breaker;
    RiskLib.RiskParams private _risk;
    uint256[40] private __gap;

    error InvalidAddress();
    error InvalidDecimals();
    error AccountAlreadyExists();
    error GuardianOnly();
    error RenounceDisabled();

    event AccountCreated(address indexed owner, address indexed account, address indexed referrer);
    event AccountImplementationChanged(address indexed implementation);
    event RiskParamsChanged(RiskLib.RiskParams params);
    event GuardianChanged(address indexed guardian);
    event BreakerChanged(bool on, uint256 setAt);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(address initialOwner, address accountImpl, address pool_, address asset_, address guardian_)
        external initializer
    {
        if (initialOwner == address(0) || guardian_ == address(0) || accountImpl.code.length == 0
            || pool_.code.length == 0 || asset_.code.length == 0) revert InvalidAddress();
        if (IERC20Metadata(asset_).decimals() != 6) revert InvalidDecimals();
        __Ownable_init(initialOwner);
        __Ownable2Step_init();
        accountImplementation = accountImpl;
        pool = pool_;
        asset = asset_;
        guardian = guardian_;
        _risk = RiskLib.RiskParams({
            tier1Bps: 13000, tier2Bps: 12000, tier3Bps: 11000, targetBps: 14500,
            maxLeverageBps: 20000, cooldown: 60, fixedCost: 20000, maxTipCap: 1000000,
            pBreakBps: [uint16(10500), 11000, 12000, 13000],
            pLiqBps: [uint16(3000), 1500, 500, 150, 25]
        });
    }

    function riskParams() external view override returns (RiskLib.RiskParams memory) { return _risk; }

    /// @notice The guardian must explicitly renew a breaker after its seven-day lifetime.
    function breakerOn() external view override returns (bool) {
        return _breaker && block.timestamp < breakerSetAt + 7 days;
    }

    /// @notice Creates the caller's account. Never send funds to an account address before
    /// createAccount has been called for that owner; read the real address from accountOf or AccountCreated.
    function createAccount(address referrer) external nonReentrant returns (address account) {
        if (accountOf[msg.sender] != address(0)) revert AccountAlreadyExists();
        account = Clones.cloneDeterministic(accountImplementation, _salt(msg.sender));
        accountOf[msg.sender] = account;
        allAccounts += 1;
        IPilotAccountInitializer(account).initialize(msg.sender, address(this));
        if (referrer == msg.sender) referrer = address(0);
        emit AccountCreated(msg.sender, account, referrer);
    }

    function setAccountImplementation(address implementation) external onlyOwner {
        if (implementation.code.length == 0) revert InvalidAddress();
        accountImplementation = implementation;
        emit AccountImplementationChanged(implementation);
    }

    /// @notice Changes defaults for NEW accounts; existing accounts opt in via adoptFactoryParams().
    function setRiskParams(RiskLib.RiskParams calldata p) external onlyOwner {
        RiskLib.validate(p);
        _risk = p;
        emit RiskParamsChanged(p);
    }

    function setGuardian(address guardian_) external onlyOwner {
        if (guardian_ == address(0)) revert InvalidAddress();
        guardian = guardian_;
        emit GuardianChanged(guardian_);
    }

    function setBreaker(bool on) external {
        if (msg.sender != guardian) revert GuardianOnly();
        _breaker = on;
        if (on) breakerSetAt = block.timestamp;
        emit BreakerChanged(on, breakerSetAt);
    }

    function renounceOwnership() public override onlyOwner { revert RenounceDisabled(); }
    /// @dev The owner MUST be a multisig behind a timelock in production.
    /// Existing accounts are isolated from factory upgrades: code, pool, asset and risk params
    /// are pinned locally, with owner-only parameter adoption. Only discretionary actions read the breaker.
    function _authorizeUpgrade(address) internal override onlyOwner {}
    function _salt(address user) private pure returns (bytes32) { return bytes32(uint256(uint160(user))); }
}
