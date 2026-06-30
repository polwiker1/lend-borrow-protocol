// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
}

/**
 * @title LendingProtocol
 * @notice Educational lending protocol.
 * @dev This contract intentionally keeps the math simple:
 * - prices come from a mock oracle with 8 decimals;
 * - interest is linear APR, not compound;
 * - supplied liquidity and deposited collateral are separate concepts;
 * - all tokens are treated through their raw ERC20 decimals for study purposes.
 */
contract LendingProtocol is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant PRICE_DECIMALS = 1e8;
    uint256 public constant YEAR = 365 days;
    uint256 public constant MIN_LIQUIDATION_PENALTY = 500;
    uint256 public constant MAX_LIQUIDATION_PENALTY = 1_000;

    struct Market {
        IERC20 token;
        bool isActive;
        uint256 collateralFactor;
        uint256 liquidationThreshold;
        uint256 liquidationPenalty;
        uint256 borrowRate;
        uint256 reserveFactor;
        uint256 totalLiquiditySupplied;
        uint256 totalLiquidityBorrowed;
    }

    struct DebtPosition {
        uint256 principal;
        uint256 lastAccruedAt;
    }

    IPriceOracle public priceOracle;
    address[] public supportedTokens;

    mapping(address => Market) public markets;
    mapping(address => mapping(address => uint256)) public liquidityShares;
    mapping(address => mapping(address => uint256)) public collateralDeposits;
    mapping(address => mapping(address => DebtPosition)) public debts;
    mapping(address => uint256) public totalLiquidityShares;
    mapping(address => uint256) public badDebt;
    mapping(address => uint256) public protocolReserves;

    event MarketAdded(address indexed token, uint256 collateralFactor, uint256 borrowRate, uint256 reserveFactor);
    event MarketUpdated(
        address indexed token,
        uint256 collateralFactor,
        uint256 liquidationThreshold,
        uint256 borrowRate,
        uint256 reserveFactor
    );
    event LiquiditySupplied(address indexed user, address indexed token, uint256 amount, uint256 shares);
    event LiquidityWithdrawn(address indexed user, address indexed token, uint256 amount, uint256 shares);
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralWithdrawn(address indexed user, address indexed token, uint256 amount);
    event Borrowed(address indexed user, address indexed token, uint256 amount);
    event Repaid(address indexed user, address indexed token, uint256 amountPaid);
    event BadDebtRecorded(address indexed user, address indexed token, uint256 amount);
    event ProtocolReserveAccrued(address indexed token, uint256 amount);
    event ProtocolReserveWithdrawn(address indexed token, address indexed to, uint256 amount);
    event Liquidated(
        address indexed liquidator,
        address indexed user,
        address indexed debtToken,
        address collateralToken,
        uint256 debtRepaid,
        uint256 collateralSeized
    );
    event PriceOracleUpdated(address indexed oracle);

    modifier onlyActiveMarket(address token) {
        require(markets[token].isActive, "Market not active");
        _;
    }

    constructor(address oracle_) Ownable(msg.sender) {
        require(oracle_ != address(0), "Invalid oracle");
        priceOracle = IPriceOracle(oracle_);
    }

    function setPriceOracle(address oracle_) external onlyOwner {
        require(oracle_ != address(0), "Invalid oracle");
        priceOracle = IPriceOracle(oracle_);
        emit PriceOracleUpdated(oracle_);
    }

    function addMarket(
        address token,
        uint256 collateralFactor,
        uint256 liquidationThreshold,
        uint256 liquidationPenalty,
        uint256 borrowRate,
        uint256 reserveFactor
    ) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(!markets[token].isActive, "Market exists");
        require(collateralFactor <= BASIS_POINTS, "Bad collateral factor");
        require(liquidationThreshold <= BASIS_POINTS, "Bad threshold");
        require(collateralFactor < liquidationThreshold, "Unsafe parameters");
        require(liquidationPenalty >= MIN_LIQUIDATION_PENALTY, "Bad liquidation penalty");
        require(liquidationPenalty <= MAX_LIQUIDATION_PENALTY, "Bad liquidation penalty");
        require(reserveFactor <= BASIS_POINTS, "Bad reserve factor");
        require(priceOracle.getPrice(token) > 0, "Missing price");

        markets[token] = Market({
            token: IERC20(token),
            isActive: true,
            collateralFactor: collateralFactor,
            liquidationThreshold: liquidationThreshold,
            liquidationPenalty: liquidationPenalty,
            borrowRate: borrowRate,
            reserveFactor: reserveFactor,
            totalLiquiditySupplied: 0,
            totalLiquidityBorrowed: 0
        });

        supportedTokens.push(token);
        emit MarketAdded(token, collateralFactor, borrowRate, reserveFactor);
    }

    function updateMarket(
        address token,
        uint256 collateralFactor,
        uint256 liquidationThreshold,
        uint256 liquidationPenalty,
        uint256 borrowRate,
        uint256 reserveFactor
    ) external onlyOwner onlyActiveMarket(token) {
        require(collateralFactor <= BASIS_POINTS, "Bad collateral factor");
        require(liquidationThreshold <= BASIS_POINTS, "Bad threshold");
        require(collateralFactor < liquidationThreshold, "Unsafe parameters");
        require(liquidationPenalty >= MIN_LIQUIDATION_PENALTY, "Bad liquidation penalty");
        require(liquidationPenalty <= MAX_LIQUIDATION_PENALTY, "Bad liquidation penalty");
        require(reserveFactor <= BASIS_POINTS, "Bad reserve factor");

        Market storage market = markets[token];
        market.collateralFactor = collateralFactor;
        market.liquidationThreshold = liquidationThreshold;
        market.liquidationPenalty = liquidationPenalty;
        market.borrowRate = borrowRate;
        market.reserveFactor = reserveFactor;

        emit MarketUpdated(token, collateralFactor, liquidationThreshold, borrowRate, reserveFactor);
    }

    function supplyLiquidity(address token, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyActiveMarket(token)
    {
        require(amount > 0, "Amount is zero");

        uint256 shares = previewSupplyShares(token, amount);
        require(shares > 0, "Shares are zero");

        markets[token].token.safeTransferFrom(msg.sender, address(this), amount);
        liquidityShares[msg.sender][token] += shares;
        totalLiquidityShares[token] += shares;
        markets[token].totalLiquiditySupplied += amount;

        emit LiquiditySupplied(msg.sender, token, amount, shares);
    }

    function withdrawLiquidity(address token, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyActiveMarket(token)
    {
        require(amount > 0, "Amount is zero");
        require(availableLiquidity(token) >= amount, "Liquidity is borrowed");

        uint256 shares = previewWithdrawShares(token, amount);
        require(shares > 0, "Shares are zero");
        require(liquidityShares[msg.sender][token] >= shares, "Not enough shares");

        liquidityShares[msg.sender][token] -= shares;
        totalLiquidityShares[token] -= shares;
        markets[token].totalLiquiditySupplied -= amount;
        markets[token].token.safeTransfer(msg.sender, amount);

        emit LiquidityWithdrawn(msg.sender, token, amount, shares);
    }

    function withdrawProtocolReserves(address token, address to, uint256 amount)
        external
        onlyOwner
        onlyActiveMarket(token)
    {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Amount is zero");
        require(protocolReserves[token] >= amount, "Not enough reserves");

        protocolReserves[token] -= amount;
        markets[token].token.safeTransfer(to, amount);

        emit ProtocolReserveWithdrawn(token, to, amount);
    }

    function depositCollateral(address token, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyActiveMarket(token)
    {
        require(amount > 0, "Amount is zero");

        markets[token].token.safeTransferFrom(msg.sender, address(this), amount);
        collateralDeposits[msg.sender][token] += amount;

        emit CollateralDeposited(msg.sender, token, amount);
    }

    function withdrawCollateral(address token, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyActiveMarket(token)
    {
        require(amount > 0, "Amount is zero");
        require(collateralDeposits[msg.sender][token] >= amount, "Not enough collateral");

        collateralDeposits[msg.sender][token] -= amount;
        require(isHealthy(msg.sender), "Position would be unsafe");

        markets[token].token.safeTransfer(msg.sender, amount);
        emit CollateralWithdrawn(msg.sender, token, amount);
    }

    function borrow(address token, uint256 amount) external nonReentrant whenNotPaused onlyActiveMarket(token) {
        require(amount > 0, "Amount is zero");
        require(availableLiquidity(token) >= amount, "Not enough liquidity");

        _accrueDebt(msg.sender, token);

        debts[msg.sender][token].principal += amount;
        markets[token].totalLiquidityBorrowed += amount;

        require(isHealthy(msg.sender), "Borrow exceeds collateral");

        markets[token].token.safeTransfer(msg.sender, amount);
        emit Borrowed(msg.sender, token, amount);
    }

    function repay(address token, uint256 amount) external nonReentrant whenNotPaused onlyActiveMarket(token) {
        require(amount > 0, "Amount is zero");

        _accrueDebt(msg.sender, token);

        DebtPosition storage debt = debts[msg.sender][token];
        require(debt.principal > 0, "No debt");

        uint256 payment = amount > debt.principal ? debt.principal : amount;
        debt.principal -= payment;
        markets[token].totalLiquidityBorrowed -= payment;
        markets[token].token.safeTransferFrom(msg.sender, address(this), payment);

        emit Repaid(msg.sender, token, payment);
    }

    function liquidate(address user, address debtToken, address collateralToken, uint256 repayAmount)
        external
        nonReentrant
        whenNotPaused
        onlyActiveMarket(debtToken)
        onlyActiveMarket(collateralToken)
    {
        require(repayAmount > 0, "Amount is zero");

        _accrueDebt(user, debtToken);
        require(getHealthFactor(user) < BASIS_POINTS, "Position is healthy");

        DebtPosition storage debt = debts[user][debtToken];
        uint256 actualRepay = repayAmount > debt.principal ? debt.principal : repayAmount;
        uint256 collateralToSeize = collateralAmountForDebt(debtToken, collateralToken, actualRepay);
        collateralToSeize =
            (collateralToSeize * (BASIS_POINTS + markets[collateralToken].liquidationPenalty)) / BASIS_POINTS;

        uint256 userCollateral = collateralDeposits[user][collateralToken];

        if (userCollateral < collateralToSeize) {
            _liquidateInsolvent(user, debtToken, collateralToken);
            return;
        }

        debt.principal -= actualRepay;
        markets[debtToken].totalLiquidityBorrowed -= actualRepay;
        collateralDeposits[user][collateralToken] -= collateralToSeize;

        markets[debtToken].token.safeTransferFrom(msg.sender, address(this), actualRepay);
        markets[collateralToken].token.safeTransfer(msg.sender, collateralToSeize);

        emit Liquidated(msg.sender, user, debtToken, collateralToken, actualRepay, collateralToSeize);
    }

    function _liquidateInsolvent(address user, address debtToken, address collateralToken) internal {
        DebtPosition storage debt = debts[user][debtToken];
        uint256 originalDebt = debt.principal;
        uint256 collateralToSeize = collateralDeposits[user][collateralToken];
        uint256 actualRepay = repayAmountForCollateral(debtToken, collateralToken, collateralToSeize);
        require(actualRepay > 0, "Collateral too small");

        if (actualRepay > originalDebt) {
            actualRepay = originalDebt;
        }

        uint256 unpaidDebt = originalDebt - actualRepay;

        debt.principal = 0;
        markets[debtToken].totalLiquidityBorrowed -= originalDebt;
        collateralDeposits[user][collateralToken] = 0;
        _recordBadDebt(debtToken, unpaidDebt);

        markets[debtToken].token.safeTransferFrom(msg.sender, address(this), actualRepay);
        markets[collateralToken].token.safeTransfer(msg.sender, collateralToSeize);

        emit BadDebtRecorded(user, debtToken, unpaidDebt);
        emit Liquidated(msg.sender, user, debtToken, collateralToken, actualRepay, collateralToSeize);
    }

    function _recordBadDebt(address token, uint256 amount) internal {
        uint256 reserveCoverage = amount > protocolReserves[token] ? protocolReserves[token] : amount;
        uint256 lenderLoss = amount - reserveCoverage;

        if (reserveCoverage > 0) {
            protocolReserves[token] -= reserveCoverage;
        }

        if (lenderLoss > 0) {
            badDebt[token] += lenderLoss;
            markets[token].totalLiquiditySupplied -= lenderLoss;
        }
    }

    function _accrueDebt(address user, address token) internal {
        DebtPosition storage debt = debts[user][token];

        if (debt.lastAccruedAt == 0) {
            debt.lastAccruedAt = block.timestamp;
            return;
        }

        if (debt.principal == 0) {
            debt.lastAccruedAt = block.timestamp;
            return;
        }

        uint256 elapsed = block.timestamp - debt.lastAccruedAt;
        uint256 interest = calculateInterest(token, debt.principal, elapsed);
        uint256 reserveAmount = (interest * markets[token].reserveFactor) / BASIS_POINTS;
        uint256 supplierInterest = interest - reserveAmount;

        debt.principal += interest;
        markets[token].totalLiquidityBorrowed += interest;
        markets[token].totalLiquiditySupplied += supplierInterest;
        protocolReserves[token] += reserveAmount;
        debt.lastAccruedAt = block.timestamp;

        if (reserveAmount > 0) {
            emit ProtocolReserveAccrued(token, reserveAmount);
        }
    }

    function calculateInterest(address token, uint256 principal, uint256 elapsedSeconds) public view returns (uint256) {
        return (principal * markets[token].borrowRate * elapsedSeconds) / (BASIS_POINTS * YEAR);
    }

    function availableLiquidity(address token) public view returns (uint256) {
        Market memory market = markets[token];
        return market.totalLiquiditySupplied - market.totalLiquidityBorrowed;
    }

    function previewSupplyShares(address token, uint256 amount) public view returns (uint256) {
        uint256 shares = totalLiquidityShares[token];
        uint256 assets = markets[token].totalLiquiditySupplied;

        if (shares == 0 || assets == 0) {
            return amount;
        }

        return (amount * shares) / assets;
    }

    function previewWithdrawShares(address token, uint256 amount) public view returns (uint256) {
        uint256 shares = totalLiquidityShares[token];
        uint256 assets = markets[token].totalLiquiditySupplied;
        require(shares > 0 && assets > 0, "Empty pool");

        return _ceilDiv(amount * shares, assets);
    }

    function getLiquidityValue(address user, address token) public view returns (uint256) {
        uint256 shares = liquidityShares[user][token];
        uint256 totalShares = totalLiquidityShares[token];

        if (shares == 0 || totalShares == 0) {
            return 0;
        }

        return (shares * markets[token].totalLiquiditySupplied) / totalShares;
    }

    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return a == 0 ? 0 : ((a - 1) / b) + 1;
    }

    function getTokenValueUsd(address token, uint256 amount) public view returns (uint256) {
        uint256 price = priceOracle.getPrice(token);
        require(price > 0, "Missing price");
        return (amount * price) / PRICE_DECIMALS;
    }

    function collateralAmountForDebt(address debtToken, address collateralToken, uint256 debtAmount)
        public
        view
        returns (uint256)
    {
        uint256 debtValueUsd = getTokenValueUsd(debtToken, debtAmount);
        uint256 collateralPrice = priceOracle.getPrice(collateralToken);
        require(collateralPrice > 0, "Missing collateral price");
        return (debtValueUsd * PRICE_DECIMALS) / collateralPrice;
    }

    function debtAmountForCollateral(address debtToken, address collateralToken, uint256 collateralAmount)
        public
        view
        returns (uint256)
    {
        uint256 collateralValueUsd = getTokenValueUsd(collateralToken, collateralAmount);
        uint256 debtPrice = priceOracle.getPrice(debtToken);
        require(debtPrice > 0, "Missing debt price");
        return (collateralValueUsd * PRICE_DECIMALS) / debtPrice;
    }

    function repayAmountForCollateral(address debtToken, address collateralToken, uint256 collateralAmount)
        public
        view
        returns (uint256)
    {
        uint256 debtValue = debtAmountForCollateral(debtToken, collateralToken, collateralAmount);
        return (debtValue * BASIS_POINTS) / (BASIS_POINTS + markets[collateralToken].liquidationPenalty);
    }

    function getBorrowLimitUsd(address user) public view returns (uint256) {
        uint256 limit = 0;

        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address token = supportedTokens[i];
            uint256 amount = collateralDeposits[user][token];

            if (amount > 0) {
                uint256 valueUsd = getTokenValueUsd(token, amount);
                limit += (valueUsd * markets[token].collateralFactor) / BASIS_POINTS;
            }
        }

        return limit;
    }

    function getMaxBorrowableTokenAmount(address user, address borrowToken) public view returns (uint256) {
        uint256 borrowLimitUsd = getBorrowLimitUsd(user);
        uint256 debtValueUsd = getDebtValueUsd(user);

        if (debtValueUsd >= borrowLimitUsd) {
            return 0;
        }

        uint256 remainingBorrowLimitUsd = borrowLimitUsd - debtValueUsd;
        uint256 borrowTokenPrice = priceOracle.getPrice(borrowToken);
        require(borrowTokenPrice > 0, "Missing borrow price");

        return (remainingBorrowLimitUsd * PRICE_DECIMALS) / borrowTokenPrice;
    }

    function getDebtValueUsd(address user) public view returns (uint256) {
        uint256 debtValue = 0;

        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address token = supportedTokens[i];
            DebtPosition memory debt = debts[user][token];

            if (debt.principal > 0) {
                uint256 principalWithPendingInterest = debt.principal;

                if (debt.lastAccruedAt > 0) {
                    uint256 elapsed = block.timestamp - debt.lastAccruedAt;
                    principalWithPendingInterest += calculateInterest(token, debt.principal, elapsed);
                }

                debtValue += getTokenValueUsd(token, principalWithPendingInterest);
            }
        }

        return debtValue;
    }

    function getHealthFactor(address user) public view returns (uint256) {
        uint256 debtValue = getDebtValueUsd(user);
        if (debtValue == 0) return type(uint256).max;

        uint256 liquidationValue = 0;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address token = supportedTokens[i];
            uint256 amount = collateralDeposits[user][token];

            if (amount > 0) {
                uint256 valueUsd = getTokenValueUsd(token, amount);
                liquidationValue += (valueUsd * markets[token].liquidationThreshold) / BASIS_POINTS;
            }
        }

        return (liquidationValue * BASIS_POINTS) / debtValue;
    }

    function isHealthy(address user) public view returns (bool) {
        return getDebtValueUsd(user) <= getBorrowLimitUsd(user);
    }

    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
