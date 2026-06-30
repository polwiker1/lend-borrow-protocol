// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

interface IPyth {
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint256 publishTime;
    }

    function getPriceNoOlderThan(bytes32 id, uint256 age) external view returns (Price memory price);
}

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
}

/**
 * @title PythWheatOracle
 * @notice Study oracle for a LATAM wheat lending model.
 * @dev LendingProtocol expects all prices with 8 decimals.
 *
 * Unit model:
 * - Pyth/CME reference: USD per bushel.
 * - Local agro model: 1 wTK = 1 metric ton of wheat.
 * - Conversion: 1 metric ton of wheat ~= 36.7437 bushels.
 */
contract PythWheatOracle is IPriceOracle, Ownable {
    uint256 public constant PRICE_DECIMALS = 1e8;
    uint256 public constant BUSHELS_PER_TON_1E8 = 3_674_370_000; // 36.7437 * 1e8
    uint256 public constant DEFAULT_MAX_AGE = 1 hours;
    uint256 public constant MIN_MAX_AGE = 1 minutes;
    uint256 public constant MAX_MAX_AGE = 24 hours;

    IPyth public immutable pyth;
    address public immutable wheatToken;
    address public immutable usdcToken;

    bytes32 public wheatPriceId;
    bytes32 public usdcPriceId;
    uint256 public maxAge;

    event MaxAgeUpdated(uint256 maxAge);

    constructor(
        address pythContract,
        bytes32 wheatPriceId_,
        bytes32 usdcPriceId_,
        address wheatToken_,
        address usdcToken_
    ) Ownable(msg.sender) {
        require(pythContract != address(0), "Oracle: invalid pyth");
        require(wheatToken_ != address(0), "Oracle: invalid wheat token");
        require(usdcToken_ != address(0), "Oracle: invalid usdc token");

        pyth = IPyth(pythContract);
        wheatPriceId = wheatPriceId_;
        usdcPriceId = usdcPriceId_;
        wheatToken = wheatToken_;
        usdcToken = usdcToken_;
        maxAge = DEFAULT_MAX_AGE;
    }

    function getPrice(address token) external view override returns (uint256) {
        if (token == wheatToken) {
            return getWheatTonPriceInUsdc();
        }

        if (token == usdcToken) {
            return _convertTo8Decimals(pyth.getPriceNoOlderThan(usdcPriceId, maxAge));
        }

        revert("Oracle: unsupported token");
    }

    function getWheatBushelPriceUsd() public view returns (uint256) {
        return _convertTo8Decimals(pyth.getPriceNoOlderThan(wheatPriceId, maxAge));
    }

    function getWheatTonPriceUsd() public view returns (uint256) {
        return (getWheatBushelPriceUsd() * BUSHELS_PER_TON_1E8) / PRICE_DECIMALS;
    }

    function getWheatTonPriceInUsdc() public view returns (uint256) {
        uint256 wheatTonUsd = getWheatTonPriceUsd();
        uint256 usdcUsd = _convertTo8Decimals(pyth.getPriceNoOlderThan(usdcPriceId, maxAge));

        return (wheatTonUsd * PRICE_DECIMALS) / usdcUsd;
    }

    function convertTo8DecimalsForTest(IPyth.Price memory priceObj) external pure returns (uint256) {
        return _convertTo8Decimals(priceObj);
    }

    function _convertTo8Decimals(IPyth.Price memory priceObj) internal pure returns (uint256) {
        require(priceObj.price > 0, "Oracle: price must be positive");

        uint256 rawPrice = uint256(uint64(priceObj.price));

        if (priceObj.expo == -8) {
            return rawPrice;
        }

        if (priceObj.expo < 0) {
            uint32 decimals = uint32(-priceObj.expo);

            if (decimals > 8) {
                return rawPrice / (10 ** (decimals - 8));
            }

            return rawPrice * (10 ** (8 - decimals));
        }

        return rawPrice * (10 ** (uint32(priceObj.expo) + 8));
    }

    function setPriceIds(bytes32 wheatPriceId_, bytes32 usdcPriceId_) external onlyOwner {
        wheatPriceId = wheatPriceId_;
        usdcPriceId = usdcPriceId_;
    }

    function setMaxAge(uint256 maxAge_) external onlyOwner {
        require(maxAge_ >= MIN_MAX_AGE, "Oracle: max age too low");
        require(maxAge_ <= MAX_MAX_AGE, "Oracle: max age too high");

        maxAge = maxAge_;
        emit MaxAgeUpdated(maxAge_);
    }
}
