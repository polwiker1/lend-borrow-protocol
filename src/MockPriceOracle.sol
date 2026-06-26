// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title MockPriceOracle
 * @notice Simple oracle for study and tests. Prices use 8 decimals, like many Chainlink feeds.
 * @dev Example: a token priced at 1 USD is stored as 1e8. A token priced at 2,000 USD is 2000e8.
 */
contract MockPriceOracle is Ownable {
    mapping(address => uint256) private prices;

    event PriceUpdated(address indexed token, uint256 price);

    constructor() Ownable(msg.sender) {}

    function setPrice(address token, uint256 price) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(price > 0, "Invalid price");

        prices[token] = price;
        emit PriceUpdated(token, price);
    }

    function getPrice(address token) external view returns (uint256) {
        return prices[token];
    }
}
