// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// TESTNET ONLY: a demo stand-in, not Tydro, and not for production.
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IAavePool} from "./interfaces/IAavePool.sol";
import {MockAToken} from "./MockAToken.sol";
import {MockDebtToken} from "./MockDebtToken.sol";

/// @notice Single-reserve, manually indexed Aave-shaped testnet demonstrator.
/// @dev No liquidation engine, delegation, automatic accrual or external yield source.
contract MockTydroPool is IAavePool, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    IERC20 public immutable asset;
    MockAToken public immutable aToken;
    MockDebtToken public immutable debtToken;
    uint256 public liquidityIndex = 1e27;
    uint256 public variableBorrowIndex = 1e27;
    uint16 public ltvBps = 7500;
    uint16 public liquidationThresholdBps = 8000;
    uint16 public constant LIQUIDATION_BONUS_BPS = 10500;
    bool public frozen;
    bool public paused;
    bool public borrowingEnabled = true;
    uint40 public lastUpdateTimestamp;

    error InvalidAsset();
    error InvalidAmount();
    error InvalidRecipient();
    error MarketPaused();
    error MarketFrozen();
    error UnsupportedRateMode();
    error DelegationNotSupported();
    error BorrowingDisabled();
    error LtvExceeded();
    error HealthTooLow(uint256 observedBps, uint256 requiredBps);
    error InsufficientLiquidity(uint256 available, uint256 requested);
    error RenounceDisabled();
    error InvalidConfiguration();
    error BalanceMismatch();

    event Supplied(address indexed caller, address indexed user, uint256 amount);
    event Withdrawn(address indexed user, address indexed to, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed caller, address indexed user, uint256 amount, bool withATokens);
    event FrozenChanged(bool frozen);
    event PausedChanged(bool paused);
    event LtvChanged(uint16 ltvBps, uint16 liquidationThresholdBps);
    event BorrowingChanged(bool enabled);
    event DemoAccrued(uint256 liquidityIndex, uint256 variableBorrowIndex);

    constructor(address usdc) Ownable(msg.sender) {
        if (usdc.code.length == 0 || IERC20Metadata(usdc).decimals() != 6) revert InvalidAsset();
        asset = IERC20(usdc);
        aToken = new MockAToken(address(this));
        debtToken = new MockDebtToken(address(this));
        lastUpdateTimestamp = block.timestamp.toUint40();
    }

    modifier available(address asset_) {
        if (asset_ != address(asset)) revert InvalidAsset();
        if (paused) revert MarketPaused();
        _;
    }

    function supply(address asset_, uint256 amount, address onBehalfOf, uint16)
        external override nonReentrant available(asset_)
    {
        if (frozen) revert MarketFrozen();
        if (amount == 0) revert InvalidAmount();
        if (onBehalfOf == address(0) || onBehalfOf == address(this)) revert InvalidRecipient();
        _pull(amount);
        aToken.mint(onBehalfOf, amount);
        emit Supplied(msg.sender, onBehalfOf, amount);
    }

    function withdraw(address asset_, uint256 amount, address to)
        external override nonReentrant available(asset_) returns (uint256 withdrawn)
    {
        if (to == address(0) || to == address(this)) revert InvalidRecipient();
        uint256 coll = aToken.balanceOf(msg.sender);
        withdrawn = amount == type(uint256).max ? coll : amount;
        if (withdrawn > coll) revert InvalidAmount();
        if (withdrawn == 0) return 0;
        uint256 availableLiquidity = asset.balanceOf(address(this));
        if (availableLiquidity < withdrawn) revert InsufficientLiquidity(availableLiquidity, withdrawn);
        aToken.burn(msg.sender, withdrawn);
        uint256 hf = _hf(aToken.balanceOf(msg.sender), debtToken.balanceOf(msg.sender));
        if (hf < 1e18) revert HealthTooLow(hf / 1e14, 10000);
        asset.safeTransfer(to, withdrawn);
        emit Withdrawn(msg.sender, to, withdrawn);
    }

    function borrow(address asset_, uint256 amount, uint256 rateMode, uint16, address onBehalfOf)
        external override nonReentrant available(asset_)
    {
        _variable(rateMode);
        if (frozen) revert MarketFrozen();
        if (!borrowingEnabled) revert BorrowingDisabled();
        if (onBehalfOf != msg.sender) revert DelegationNotSupported();
        if (amount == 0) revert InvalidAmount();
        uint256 availableLiquidity = asset.balanceOf(address(this));
        if (availableLiquidity < amount) revert InsufficientLiquidity(availableLiquidity, amount);
        debtToken.mint(onBehalfOf, amount);
        if (debtToken.balanceOf(onBehalfOf) > Math.mulDiv(aToken.balanceOf(onBehalfOf), ltvBps, 10000)) revert LtvExceeded();
        asset.safeTransfer(msg.sender, amount);
        emit Borrowed(onBehalfOf, amount);
    }

    function repay(address asset_, uint256 amount, uint256 rateMode, address onBehalfOf)
        external override nonReentrant available(asset_) returns (uint256 paid)
    {
        _variable(rateMode);
        paid = Math.min(amount, debtToken.balanceOf(onBehalfOf));
        if (paid == 0) return 0;
        _pull(paid);
        debtToken.burn(onBehalfOf, paid);
        emit Repaid(msg.sender, onBehalfOf, paid, false);
    }

    function repayWithATokens(address asset_, uint256 amount, uint256 rateMode)
        external override nonReentrant available(asset_) returns (uint256 paid)
    {
        _variable(rateMode);
        paid = Math.min(amount, Math.min(aToken.balanceOf(msg.sender), debtToken.balanceOf(msg.sender)));
        if (paid == 0) return 0;
        aToken.burn(msg.sender, paid);
        debtToken.burn(msg.sender, paid);
        emit Repaid(msg.sender, msg.sender, paid, true);
    }

    function getUserAccountData(address user) external view override returns (
        uint256 totalCollateralBase, uint256 totalDebtBase, uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor
    ) {
        uint256 coll = aToken.balanceOf(user);
        uint256 debt = debtToken.balanceOf(user);
        uint256 limit = Math.mulDiv(coll, ltvBps, 10000);
        return (coll * 100, debt * 100, limit > debt ? (limit - debt) * 100 : 0,
            liquidationThresholdBps, ltvBps, _hf(coll, debt));
    }

    function getReserveData(address asset_) external view override returns (ReserveDataLegacy memory r) {
        if (asset_ != address(asset)) revert InvalidAsset();
        r.configuration = uint256(ltvBps) | (uint256(liquidationThresholdBps) << 16)
            | (uint256(LIQUIDATION_BONUS_BPS) << 32) | (uint256(6) << 48) | (uint256(1) << 56)
            | (uint256(frozen ? 1 : 0) << 57) | (uint256(borrowingEnabled ? 1 : 0) << 58)
            | (uint256(paused ? 1 : 0) << 60);
        r.liquidityIndex = liquidityIndex.toUint128();
        r.variableBorrowIndex = variableBorrowIndex.toUint128();
        r.lastUpdateTimestamp = lastUpdateTimestamp;
        r.aTokenAddress = address(aToken);
        r.variableDebtTokenAddress = address(debtToken);
    }

    function ADDRESSES_PROVIDER() external view override returns (address) { return address(this); }
    function getPriceOracleSentinel() external pure returns (address) { return address(0); }

    function renounceOwnership() public override onlyOwner { revert RenounceDisabled(); }

    function setFrozen(bool value) external onlyOwner nonReentrant { frozen = value; emit FrozenChanged(value); }
    function setPaused(bool value) external onlyOwner nonReentrant { paused = value; emit PausedChanged(value); }
    function setBorrowingEnabled(bool value) external onlyOwner nonReentrant {
        borrowingEnabled = value;
        emit BorrowingChanged(value);
    }
    function setLtv(uint16 ltv, uint16 lt) external onlyOwner nonReentrant {
        if (lt > 10000 || ltv > lt) revert InvalidConfiguration();
        ltvBps = ltv;
        liquidationThresholdBps = lt;
        emit LtvChanged(ltv, lt);
    }

    /// @notice Accounting-only interest; demo liquidity must be funded separately with real USDC.
    function accrueDemo(uint256 liquidityBps, uint256 borrowBps) external onlyOwner nonReentrant {
        liquidityIndex = uint256(Math.mulDiv(liquidityIndex, 10000 + liquidityBps, 10000).toUint128());
        variableBorrowIndex = uint256(Math.mulDiv(variableBorrowIndex, 10000 + borrowBps, 10000).toUint128());
        lastUpdateTimestamp = block.timestamp.toUint40();
        emit DemoAccrued(liquidityIndex, variableBorrowIndex);
    }

    function _hf(uint256 coll, uint256 debt) private view returns (uint256) {
        return debt == 0 ? type(uint256).max : Math.mulDiv(coll, uint256(liquidationThresholdBps) * 1e14, debt);
    }
    function _variable(uint256 mode) private pure { if (mode != 2) revert UnsupportedRateMode(); }
    function _pull(uint256 amount) private {
        uint256 beforeBalance = asset.balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), amount);
        if (asset.balanceOf(address(this)) != beforeBalance + amount) revert BalanceMismatch();
    }
}
