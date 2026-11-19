// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal Aave V3 legacy ABI; configuration is deliberately a plain uint256.
interface IAavePool {
    struct ReserveDataLegacy {
        uint256 configuration;
        uint128 liquidityIndex;
        uint128 currentLiquidityRate;
        uint128 variableBorrowIndex;
        uint128 currentVariableBorrowRate;
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        uint16 id;
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        uint128 accruedToTreasury;
        uint128 unbacked;
        uint128 isolationModeTotalDebt;
    }

    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function borrow(address asset, uint256 amount, uint256 rateMode, uint16 referralCode, address onBehalfOf) external;
    function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external returns (uint256);
    function repayWithATokens(address asset, uint256 amount, uint256 rateMode) external returns (uint256);
    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralBase, uint256 totalDebtBase, uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor
    );
    function getReserveData(address asset) external view returns (ReserveDataLegacy memory);
    function ADDRESSES_PROVIDER() external view returns (address);
}

interface IPoolAddressesProvider {
    function getPriceOracleSentinel() external view returns (address);
}

interface IPriceOracleSentinel {
    function isBorrowAllowed() external view returns (bool);
    function isLiquidationAllowed() external view returns (bool);
}
