// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IMockIndexSource {
    function liquidityIndex() external view returns (uint256);
    function variableBorrowIndex() external view returns (uint256);
}

/// @notice Demo-only nontransferable receipt; ERC20 storage contains scaled units.
abstract contract MockIndexedToken is ERC20 {
    uint256 private constant RAY = 1e27;
    address public immutable pool;
    bool private immutable _isDebt;
    error PoolOnly();
    error NonTransferable();
    error InvalidScaledAmount();

    constructor(string memory name_, string memory symbol_, address pool_, bool debt_)
        ERC20(name_, symbol_)
    {
        pool = pool_;
        _isDebt = debt_;
    }

    modifier onlyPool() { if (msg.sender != pool) revert PoolOnly(); _; }
    function decimals() public pure override returns (uint8) { return 6; }
    function index() public view returns (uint256) {
        return _isDebt ? IMockIndexSource(pool).variableBorrowIndex() : IMockIndexSource(pool).liquidityIndex();
    }
    function balanceOf(address user) public view override returns (uint256) {
        return Math.mulDiv(super.balanceOf(user), index(), RAY);
    }
    function totalSupply() public view override returns (uint256) {
        return Math.mulDiv(super.totalSupply(), index(), RAY);
    }
    function scaledBalanceOf(address user) external view returns (uint256) { return super.balanceOf(user); }

    /// @dev Directional rounding never mints excess collateral or understates newly minted debt.
    function mint(address user, uint256 amount) external onlyPool {
        uint256 scaled = Math.mulDiv(amount, RAY, index(), _isDebt ? Math.Rounding.Ceil : Math.Rounding.Floor);
        if (scaled == 0) revert InvalidScaledAmount();
        _mint(user, scaled);
    }

    /// @dev Full balance burns clear all scaled dust; partial burns round conservatively.
    function burn(address user, uint256 amount) external onlyPool {
        uint256 scaled = amount == balanceOf(user) ? super.balanceOf(user)
            : Math.mulDiv(amount, RAY, index(), _isDebt ? Math.Rounding.Floor : Math.Rounding.Ceil);
        if (scaled == 0) revert InvalidScaledAmount();
        _burn(user, scaled);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) revert NonTransferable();
        super._update(from, to, value);
    }
}
