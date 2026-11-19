// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IAavePool, IPoolAddressesProvider, IPriceOracleSentinel} from "./interfaces/IAavePool.sol";
import {IPilotFactory} from "./interfaces/IPilotFactory.sol";
import {RiskLib} from "./RiskLib.sol";

/// @notice A single owner's same-USDC lending position and permissionless protection policy.
/// @dev This contract does not guarantee zero loss. Pool insolvency, pauses and USDC risks remain.
contract PilotAccount is Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    enum MarketStatus { Active, Frozen, Paused, LtvZero, Inactive }
    enum ProfitMode { Save, Compound }

    struct Snapshot {
        uint256 collateral;
        uint256 debt;
        uint256 reserve;
        uint256 equity;
        uint256 invested;
        int256 netDeposits;
        int256 lifetimeProfit;
        uint256 hfBps;
        uint256 leverageBps;
        MarketStatus status;
        ProfitMode profitMode;
        uint256 maxTip;
        uint256 lastProtectAt;
        bool liquidationsAllowed;
    }

    uint256 public constant HARD_MAX_LEVERAGE_BPS = 20000;
    uint256 private constant MIN_RESERVE_STEP = 10000;
    uint256 private constant BPS = 10000;
    address public owner;
    IPilotFactory public factory;
    IAavePool public pool;
    IERC20 public asset;
    IERC20 public aToken;
    IERC20 public debtToken;
    /// @notice Principal baseline of supplied equity (collateral minus debt), excluding reserve.
    uint256 public invested;
    /// @notice Signed cumulative owner inflows less outflows, including reserve funding.
    int256 public netDeposits;
    ProfitMode public profitMode;
    uint256 public maxTip;
    uint256 public lastProtectAt;
    RiskLib.RiskParams private _risk;

    error OwnerOnly();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidTarget(uint256 target, uint256 minimum, uint256 maximum);
    error InvalidToken();
    error PoolUnavailable();
    error MarketPaused();
    error MarketNotActive();
    error BorrowingDisabled();
    error BreakerActive();
    error HealthTooLow(uint256 observedBps, uint256 requiredBps);
    error NothingToProtect();
    error Healthy();
    error CooldownActive(uint256 nextEligibleAt);
    error BalanceMismatch(address token, uint256 expected, uint256 observed);
    error PoolAmountMismatch(uint256 requested, uint256 returned);
    error TipTooHigh(uint256 amount, uint256 cap);
    error NoProgress();

    event Deposited(uint256 amount);
    event ReserveFunded(uint256 amount);
    event Withdrawn(uint256 amount);
    event Protected(uint8 tier, uint256 hfBefore, uint256 hfAfter, uint256 amount, address indexed caller);
    event ProtectionSkipped(string reason);
    event ProfitHarvested(ProfitMode mode, uint256 amount);
    event ProfitModeChanged(ProfitMode mode);
    event Boosted(uint256 targetBps, uint256 leverageBps);
    event Deleveraged(uint256 targetBps, uint256 leverageBps);
    event ExitedToEarn(uint256 repaid);
    event TipPaid(address indexed caller, uint256 amount);
    event RiskParamsAdopted(RiskLib.RiskParams params);

    modifier onlyOwner() {
        if (msg.sender != owner) revert OwnerOnly();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    /// @notice Called atomically by the factory after cloning; pool and asset are pinned forever.
    function initialize(address owner_, address factory_) external initializer nonReentrant {
        if (owner_ == address(0) || factory_.code.length == 0 || msg.sender != factory_) revert InvalidAddress();
        owner = owner_;
        factory = IPilotFactory(factory_);
        RiskLib.RiskParams memory p = factory.riskParams();
        RiskLib.validate(p);
        _risk = p;
        address asset_ = factory.asset();
        address pool_ = factory.pool();
        if (asset_.code.length == 0 || pool_.code.length == 0) revert InvalidAddress();
        asset = IERC20(asset_);
        pool = IAavePool(pool_);
        IAavePool.ReserveDataLegacy memory r = _readReserve();
        if (r.aTokenAddress.code.length == 0 || r.variableDebtTokenAddress.code.length == 0
            || r.aTokenAddress == asset_ || r.variableDebtTokenAddress == asset_
            || r.aTokenAddress == r.variableDebtTokenAddress) revert PoolUnavailable();
        aToken = IERC20(r.aTokenAddress);
        debtToken = IERC20(r.variableDebtTokenAddress);
        // Tips are opt-in; the initial user cap is zero.
    }

    function riskParams() external view returns (RiskLib.RiskParams memory) { return _risk; }

    /// @notice Explicitly opt in to the factory's current defaults after local validation.
    function adoptFactoryParams() external onlyOwner nonReentrant {
        RiskLib.RiskParams memory p = factory.riskParams();
        RiskLib.validate(p);
        _risk = p;
        emit RiskParamsAdopted(p);
    }

    function deposit(uint256 amount) external onlyOwner nonReentrant {
        if (marketStatus() != MarketStatus.Active) revert MarketNotActive();
        _pull(amount);
        invested += amount;
        netDeposits += amount.toInt256();
        _supply(amount);
        emit Deposited(amount);
    }

    function fundReserve(uint256 amount) external onlyOwner nonReentrant {
        _pull(amount);
        netDeposits += amount.toInt256();
        emit ReserveFunded(amount);
    }

    /// @notice Reserve-only withdrawals remain possible even while the pool is paused or unavailable.
    function withdraw(uint256 amount) external onlyOwner nonReentrant {
        if (amount == 0) revert InvalidAmount();
        uint256 reserve = asset.balanceOf(address(this));
        netDeposits -= amount.toInt256();
        if (amount > reserve) {
            _notPaused();
            uint256 withdrawn = amount - reserve;
            (uint256 coll, uint256 debt) = _balances();
            uint256 collateralAfter = coll > withdrawn ? coll - withdrawn : 0;
            bool deleveraged;
            if (debt != 0 && debt > collateralAfter / 2) {
                // x = 2 * debt - coll + withdrawn, capped to debt.
                uint256 x = collateralAfter <= debt ? debt : debt - (collateralAfter - debt);
                deleveraged = _repayATokens(x >= debt ? type(uint256).max : x) != 0;
            }
            _withdrawPool(withdrawn);
            invested = invested > withdrawn ? invested - withdrawn : 0;
            (coll, debt) = _balances();
            if (debt != 0) {
                uint256 hf = _health();
                if (hf < _risk.tier1Bps) revert HealthTooLow(hf, _risk.tier1Bps);
            }
            if (deleveraged) emit Deleveraged(HARD_MAX_LEVERAGE_BPS, _leverage(coll, debt));
        }
        asset.safeTransfer(owner, amount);
        emit Withdrawn(amount);
    }

    function withdrawAll() external onlyOwner nonReentrant {
        _notPaused();
        (, uint256 debt) = _balances();
        if (debt != 0) _exit();
        (, debt) = _balances();
        if (debt != 0) revert HealthTooLow(_health(), type(uint256).max);
        uint256 beforeBalance = asset.balanceOf(address(this));
        uint256 withdrawn = pool.withdraw(address(asset), type(uint256).max, address(this));
        uint256 amount = asset.balanceOf(address(this));
        if (amount != beforeBalance + withdrawn) revert BalanceMismatch(address(asset), beforeBalance + withdrawn, amount);
        uint256 remainingCollateral = aToken.balanceOf(address(this));
        if (remainingCollateral != 0) revert BalanceMismatch(address(aToken), 0, remainingCollateral);
        invested = 0;
        netDeposits -= amount.toInt256();
        asset.safeTransfer(owner, amount);
        emit Withdrawn(amount);
    }

    function setProfitMode(ProfitMode mode) external onlyOwner nonReentrant {
        profitMode = mode;
        if (mode == ProfitMode.Compound) {
            (uint256 coll, uint256 debt) = _balances();
            invested = _equity(coll, debt);
        }
        emit ProfitModeChanged(mode);
    }

    function setMaxTip(uint256 amount) external onlyOwner nonReentrant {
        if (amount > _risk.maxTipCap) revert TipTooHigh(amount, _risk.maxTipCap);
        maxTip = amount;
    }

    /// @notice Bounded variable-rate same-asset looping, never more than 2x requested leverage.
    function boostTo(uint256 targetBps) external onlyOwner nonReentrant {
        RiskLib.RiskParams memory p = _risk;
        if (targetBps < BPS || targetBps > p.maxLeverageBps || targetBps > HARD_MAX_LEVERAGE_BPS) {
            revert InvalidTarget(targetBps, BPS, Math.min(p.maxLeverageBps, HARD_MAX_LEVERAGE_BPS));
        }
        if (_breakerOn()) revert BreakerActive();
        uint256 config = _readReserve().configuration;
        if (_status(config) != MarketStatus.Active) revert MarketNotActive();
        if ((config & (uint256(1) << 58)) == 0) revert BorrowingDisabled();
        uint256 ltv = uint16(config);
        for (uint256 i; i < 10; ++i) {
            (uint256 coll, uint256 debt) = _balances();
            uint256 want = Math.mulDiv(_equity(coll, debt), targetBps, BPS);
            uint256 limit = Math.mulDiv(coll, ltv, BPS);
            if (want <= coll || limit <= debt) break;
            uint256 amount = Math.min(want - coll, Math.mulDiv(limit - debt, 95, 100));
            if (amount == 0) break;
            uint256 beforeBalance = asset.balanceOf(address(this));
            pool.borrow(address(asset), amount, 2, 0, address(this));
            uint256 observed = asset.balanceOf(address(this));
            if (observed != beforeBalance + amount) revert BalanceMismatch(address(asset), beforeBalance + amount, observed);
            _supply(amount);
        }
        uint256 hf = _health();
        if (hf < uint256(p.tier1Bps) + 1000) revert HealthTooLow(hf, uint256(p.tier1Bps) + 1000);
        (uint256 c, uint256 d) = _balances();
        emit Boosted(targetBps, _leverage(c, d));
    }

    /// @notice Repay using collateral, without borrowing, swaps or flash loans.
    function deleverageTo(uint256 targetBps) external onlyOwner nonReentrant {
        if (targetBps < BPS || targetBps > HARD_MAX_LEVERAGE_BPS) {
            revert InvalidTarget(targetBps, BPS, HARD_MAX_LEVERAGE_BPS);
        }
        _notPaused();
        for (uint256 i; i < 10; ++i) {
            (uint256 coll, uint256 debt) = _balances();
            if (debt == 0 || _leverage(coll, debt) <= targetBps) break;
            uint256 wanted = Math.mulDiv(_equity(coll, debt), targetBps, BPS);
            uint256 amount = Math.min(debt, coll - wanted);
            if (amount == 0 || _repayATokens(amount) == 0) break;
        }
        (uint256 c, uint256 d) = _balances();
        if (d != 0 && _leverage(c, d) > targetBps) {
            uint256 required = targetBps == BPS ? type(uint256).max
                : Math.mulDiv(targetBps, uint16(_readReserve().configuration >> 16), targetBps - BPS, Math.Rounding.Ceil);
            revert HealthTooLow(_health(), required);
        }
        emit Deleveraged(targetBps, _leverage(c, d));
    }

    function emergencyExit() external onlyOwner nonReentrant {
        _notPaused();
        _exit();
    }

    /// @notice Non-position tokens can only be rescued to the owner, never an arbitrary recipient.
    function rescue(address token, address to) external onlyOwner nonReentrant {
        if (to != owner || token == address(0)) revert InvalidAddress();
        if (token == address(asset) || token == address(aToken) || token == address(debtToken)) revert InvalidToken();
        IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));
    }

    /// @notice Permissionless risk reduction; the breaker does not block this function.
    function protect() external nonReentrant {
        IAavePool.ReserveDataLegacy memory r = _readReserve();
        MarketStatus status = _status(r.configuration);
        if (status == MarketStatus.Paused) revert MarketPaused();
        (uint256 coll, uint256 debt) = _balances();
        if (debt == 0) revert NothingToProtect();
        uint256 hf = _healthWith(coll, debt, r.configuration);
        RiskLib.RiskParams memory p = _risk;
        if (hf >= p.tier1Bps) revert Healthy();
        if (hf > p.tier3Bps) {
            if (lastProtectAt != 0 && block.timestamp < lastProtectAt + p.cooldown) {
                revert CooldownActive(lastProtectAt + p.cooldown);
            }
            uint256 bonus = uint16(r.configuration >> 32);
            uint256 loss = Math.mulDiv(debt, 5000, BPS);
            loss = Math.mulDiv(loss, bonus > BPS ? bonus - BPS : 0, BPS);
            loss = Math.mulDiv(loss, _pLiq(hf, p), BPS);
            if (loss <= _tip(p.maxTipCap) + p.fixedCost) {
                emit ProtectionSkipped("uneconomic");
                return;
            }
        }
        (uint8 tier, uint256 amount) = _protectAction(hf, coll, debt, r.configuration, status, p);
        if (amount == 0) {
            emit ProtectionSkipped("no action");
            return;
        }
        uint256 afterHf = _health();
        lastProtectAt = block.timestamp;
        uint256 tip = _tip(p.maxTipCap);
        if (tip != 0) {
            asset.safeTransfer(msg.sender, tip);
            emit TipPaid(msg.sender, tip);
        }
        emit Protected(tier, hf, afterHf, amount, msg.sender);
    }

    function _protectAction(
        uint256 hf, uint256 coll, uint256 debt, uint256 config, MarketStatus status,
        RiskLib.RiskParams memory p
    ) private returns (uint8 tier, uint256 amount) {
        if (hf <= p.tier3Bps) {
            tier = 3;
            amount = _exit();
        } else {
            uint256 reserve = asset.balanceOf(address(this));
            uint256 lt = uint16(config >> 16);
            uint256 needed;
            if (hf >= p.tier2Bps && status == MarketStatus.Active && reserve != 0) {
                uint256 wanted = Math.mulDiv(debt, p.targetBps, lt, Math.Rounding.Ceil);
                needed = wanted > coll ? wanted - coll : 0;
                uint256 step = Math.min(needed, reserve);
                if (step >= MIN_RESERVE_STEP) {
                    asset.forceApprove(address(pool), step);
                    try pool.supply(address(asset), step, address(this), 0) {
                        amount = step;
                        invested += amount;
                    } catch {}
                    asset.forceApprove(address(pool), 0);
                }
                tier = 1;
            } else {
                tier = 2;
                if (reserve != 0) {
                    uint256 wantedDebt = Math.mulDiv(coll, lt, p.targetBps);
                    needed = debt > wantedDebt ? debt - wantedDebt : 0;
                    uint256 step = Math.min(needed, reserve);
                    if (step >= MIN_RESERVE_STEP) {
                        asset.forceApprove(address(pool), step);
                        try pool.repay(address(asset), step, 2, address(this)) returns (uint256 paid) {
                            if (paid > step) revert PoolAmountMismatch(step, paid);
                            amount = paid;
                            invested += amount;
                        } catch {}
                        asset.forceApprove(address(pool), 0);
                    }
                }
            }
            uint256 currentHf = _health();
            if (currentHf < p.tier1Bps || (amount < needed && currentHf < p.targetBps)) {
                // Recompute the remaining shortfall from post-reserve collateral and debt.
                uint256 reduced = _selfDeleverage(p.targetBps, lt);
                if (reduced != 0) {
                    amount += reduced;
                    tier = 4;
                }
            }
        }
        if (amount != 0) {
            (, uint256 remainingDebt) = _balances();
            if (remainingDebt != 0 && _health() <= hf) revert NoProgress();
        }
    }

    /// @dev Ceil rounding avoids leaving HF just below the target by one USDC micro-unit.
    function _selfDeleverage(uint256 target, uint256 lt) private returns (uint256) {
        (uint256 coll, uint256 debt) = _balances();
        uint256 wanted = Math.mulDiv(debt, target, 1);
        uint256 current = Math.mulDiv(coll, lt, 1);
        if (wanted <= current || debt == 0) return 0;
        uint256 x = Math.ceilDiv(wanted - current, target - lt);
        return _repayATokens(Math.min(x, Math.min(debt, coll)));
    }

    /// @notice Save moves profit to reserve; Compound checkpoints it as invested capital.
    function harvest() external nonReentrant {
        if (_breakerOn()) revert BreakerActive();
        _notPaused();
        (uint256 coll, uint256 debt) = _balances();
        uint256 equity = _equity(coll, debt);
        uint256 profit = equity > invested ? equity - invested : 0;
        if (profit < 10000) return;
        if (profitMode == ProfitMode.Compound) {
            invested = equity;
            emit ProfitHarvested(profitMode, profit);
            return;
        }
        uint256 available = coll;
        if (debt != 0) {
            uint256 threshold = uint256(_risk.tier1Bps) + 1000;
            uint256 lt = uint16(_readReserve().configuration >> 16);
            if (lt == 0 || _health() < threshold) return;
            uint256 required = Math.mulDiv(debt, threshold, lt, Math.Rounding.Ceil);
            available = coll > required ? coll - required : 0;
        }
        uint256 amount = Math.min(profit, available);
        if (amount == 0) return;
        _withdrawPool(amount);
        if (debt != 0) {
            uint256 hf = _health();
            uint256 threshold = uint256(_risk.tier1Bps) + 1000;
            if (hf < threshold) revert HealthTooLow(hf, threshold);
        }
        emit ProfitHarvested(profitMode, amount);
    }

    function marketStatus() public view returns (MarketStatus) { return _status(_readReserve().configuration); }

    /// @notice Sentinel discovery deliberately fails open for display, not as permission to borrow.
    function liquidationsAllowed() public view returns (bool) {
        try pool.ADDRESSES_PROVIDER() returns (address provider) {
            if (provider == address(0)) return true;
            try IPoolAddressesProvider(provider).getPriceOracleSentinel() returns (address sentinel) {
                if (sentinel == address(0)) return true;
                try IPriceOracleSentinel(sentinel).isLiquidationAllowed() returns (bool allowed) { return allowed; }
                catch { return true; }
            } catch { return true; }
        } catch { return true; }
    }

    function snapshot() external view returns (Snapshot memory s) {
        (s.collateral, s.debt) = _balances();
        s.reserve = asset.balanceOf(address(this));
        s.equity = _equity(s.collateral, s.debt);
        s.invested = invested;
        s.netDeposits = netDeposits;
        s.lifetimeProfit = s.equity.toInt256() + s.reserve.toInt256() - netDeposits;
        s.hfBps = s.debt == 0 ? type(uint16).max : _health();
        s.leverageBps = _leverage(s.collateral, s.debt);
        s.status = marketStatus();
        s.profitMode = profitMode;
        s.maxTip = maxTip;
        s.lastProtectAt = lastProtectAt;
        s.liquidationsAllowed = liquidationsAllowed();
    }

    /// @dev Factory failures block discretionary actions only; protection and exits never call this.
    function _breakerOn() private view returns (bool) {
        try factory.breakerOn() returns (bool on) { return on; }
        catch { return true; }
    }

    function _readReserve() private view returns (IAavePool.ReserveDataLegacy memory r) {
        try pool.getReserveData(address(asset)) returns (IAavePool.ReserveDataLegacy memory data) { r = data; }
        catch { revert PoolUnavailable(); }
        if (uint16(r.configuration >> 16) > BPS || uint16(r.configuration) > uint16(r.configuration >> 16)
            || uint16(r.configuration >> 32) < BPS) revert PoolUnavailable();
        if (address(aToken) != address(0)
            && (r.aTokenAddress != address(aToken) || r.variableDebtTokenAddress != address(debtToken))) revert PoolUnavailable();
    }

    function _status(uint256 config) private pure returns (MarketStatus) {
        if ((config & (uint256(1) << 60)) != 0) return MarketStatus.Paused;
        if ((config & (uint256(1) << 56)) == 0) return MarketStatus.Inactive;
        if ((config & (uint256(1) << 57)) != 0) return MarketStatus.Frozen;
        if (uint16(config) == 0) return MarketStatus.LtvZero;
        return MarketStatus.Active;
    }

    function _notPaused() private view {
        if (marketStatus() == MarketStatus.Paused) revert MarketPaused();
    }

    function _balances() private view returns (uint256 coll, uint256 debt) {
        try aToken.balanceOf(address(this)) returns (uint256 value) { coll = value; }
        catch { revert PoolUnavailable(); }
        try debtToken.balanceOf(address(this)) returns (uint256 value) { debt = value; }
        catch { revert PoolUnavailable(); }
    }

    function _health() private view returns (uint256) {
        (uint256 coll, uint256 debt) = _balances();
        return _healthWith(coll, debt, _readReserve().configuration);
    }

    function _healthWith(uint256 coll, uint256 debt, uint256 config) private view returns (uint256) {
        if (debt == 0) return type(uint256).max;
        uint256 local = Math.mulDiv(coll, uint16(config >> 16), debt);
        try pool.getUserAccountData(address(this)) returns (uint256, uint256, uint256, uint256, uint256, uint256 hf) {
            return Math.min(local, hf / 1e14);
        } catch { revert PoolUnavailable(); }
    }

    function _pull(uint256 amount) private {
        if (amount == 0) revert InvalidAmount();
        uint256 beforeBalance = asset.balanceOf(address(this));
        asset.safeTransferFrom(owner, address(this), amount);
        uint256 observed = asset.balanceOf(address(this));
        if (observed != beforeBalance + amount) revert BalanceMismatch(address(asset), beforeBalance + amount, observed);
    }

    function _supply(uint256 amount) private {
        asset.forceApprove(address(pool), amount);
        pool.supply(address(asset), amount, address(this), 0);
        asset.forceApprove(address(pool), 0);
    }

    function _repay(uint256 amount) private returns (uint256 paid) {
        if (amount == 0) return 0;
        asset.forceApprove(address(pool), amount);
        paid = pool.repay(address(asset), amount, 2, address(this));
        asset.forceApprove(address(pool), 0);
        if (paid > amount) revert PoolAmountMismatch(amount, paid);
    }

    function _repayATokens(uint256 amount) private returns (uint256 paid) {
        paid = pool.repayWithATokens(address(asset), amount, 2);
        if (paid > amount) revert PoolAmountMismatch(amount, paid);
    }

    function _withdrawPool(uint256 amount) private {
        uint256 beforeBalance = asset.balanceOf(address(this));
        uint256 returned = pool.withdraw(address(asset), amount, address(this));
        if (returned != amount) revert PoolAmountMismatch(amount, returned);
        uint256 observed = asset.balanceOf(address(this));
        if (observed != beforeBalance + amount) revert BalanceMismatch(address(asset), beforeBalance + amount, observed);
    }

    function _exit() private returns (uint256 repaid) {
        repaid = _repayATokens(type(uint256).max);
        emit ExitedToEarn(repaid);
    }

    function _tip(uint256 cap) private view returns (uint256) {
        return Math.min(maxTip, Math.min(cap, asset.balanceOf(address(this))));
    }

    function _pLiq(uint256 hf, RiskLib.RiskParams memory p) private pure returns (uint256) {
        for (uint256 i; i < 4; ++i) { if (hf < p.pBreakBps[i]) return p.pLiqBps[i]; }
        return p.pLiqBps[4];
    }

    function _equity(uint256 coll, uint256 debt) private pure returns (uint256) { return coll > debt ? coll - debt : 0; }
    function _leverage(uint256 coll, uint256 debt) private pure returns (uint256) {
        if (debt == 0) return BPS;
        return coll > debt ? Math.mulDiv(coll, BPS, coll - debt) : type(uint256).max;
    }
}
