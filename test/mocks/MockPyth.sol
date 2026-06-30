// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IPyth} from "../../src/oracles/PythWheatOracle.sol";

contract MockPyth is IPyth {
    mapping(bytes32 => Price) private prices;

    function setPrice(bytes32 id, int64 price, int32 expo) external {
        prices[id] = Price({price: price, conf: 0, expo: expo, publishTime: block.timestamp});
    }

    function getPriceNoOlderThan(bytes32 id, uint256 age) external view returns (Price memory price) {
        price = prices[id];
        require(price.publishTime != 0, "MockPyth: missing price");
        require(block.timestamp - price.publishTime <= age, "MockPyth: stale price");
    }
}
