// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {LendingProtocol} from "../src/LendingProtocol.sol";
import {MockToken} from "../src/MockToken.sol";
import {IPyth, PythWheatOracle} from "../src/oracles/PythWheatOracle.sol";
import {MockPyth} from "./mocks/MockPyth.sol";

contract PythWheatOracleTest is Test {
    uint256 private constant WAD = 1e18;

    bytes32 private constant WHEAT_PRICE_ID = bytes32("WHEAT/USD");
    bytes32 private constant USDC_PRICE_ID = bytes32("USDC/USD");

    address private molinosRioParana = address(0xBEEF);
    address private cooperativaAFRA = address(0xAFa);

    address private wheatToken = address(0x1111);
    address private usdcToken = address(0x2222);
    address private unsupportedToken = address(0x3333);

    MockPyth private pyth;
    PythWheatOracle private oracle;

    function setUp() public {
        pyth = new MockPyth();
        oracle = new PythWheatOracle(address(pyth), WHEAT_PRICE_ID, USDC_PRICE_ID, wheatToken, usdcToken);

        pyth.setPrice(WHEAT_PRICE_ID, 590_100_000, -8); // 5.901 USD/bushel
        pyth.setPrice(USDC_PRICE_ID, 100_000_000, -8); // 1 USD
    }

    function testReturnsUsdcPriceWith8Decimals() public view {
        assertEq(oracle.getPrice(usdcToken), 1e8);
    }

    function testStartsWithOneHourMaxAge() public view {
        assertEq(oracle.maxAge(), 1 hours);
    }

    function testReturnsWheatBushelPriceWith8Decimals() public view {
        assertEq(oracle.getWheatBushelPriceUsd(), 590_100_000);
    }

    function testReturnsWheatTonPriceWith8Decimals() public view {
        assertEq(oracle.getWheatTonPriceUsd(), 21_682_457_370);
    }

    function testReturnsWheatTonPriceInUsdc() public view {
        assertEq(oracle.getPrice(wheatToken), 21_682_457_370);
    }

    function testReturnsWheatTonPriceAdjustedByUsdcDepeg() public {
        pyth.setPrice(USDC_PRICE_ID, 99_000_000, -8); // 0.99 USD

        assertEq(oracle.getPrice(wheatToken), 21_901_472_090);
    }

    function testRevertsForUnsupportedToken() public {
        vm.expectRevert(bytes("Oracle: unsupported token"));
        oracle.getPrice(unsupportedToken);
    }

    function testRevertsForStalePrice() public {
        vm.warp(block.timestamp + 1 hours + 1);

        vm.expectRevert(bytes("MockPyth: stale price"));
        oracle.getPrice(wheatToken);
    }

    function testOwnerCanTightenMaxAge() public {
        oracle.setMaxAge(15 minutes);
        assertEq(oracle.maxAge(), 15 minutes);

        vm.warp(block.timestamp + 15 minutes + 1);

        vm.expectRevert(bytes("MockPyth: stale price"));
        oracle.getPrice(wheatToken);
    }

    function testRejectsMaxAgeTooLow() public {
        vm.expectRevert(bytes("Oracle: max age too low"));
        oracle.setMaxAge(59 seconds);
    }

    function testRejectsMaxAgeTooHigh() public {
        vm.expectRevert(bytes("Oracle: max age too high"));
        oracle.setMaxAge(24 hours + 1);
    }

    function testLendingProtocolCanUsePythWheatOracleForAFRAModel() public {
        MockToken wTK = new MockToken("Wheat Token", "wTK", 18, 0, address(this));
        MockToken agroUSD = new MockToken("Agro USD", "aUSD", 18, 0, address(this));
        PythWheatOracle liveOracle =
            new PythWheatOracle(address(pyth), WHEAT_PRICE_ID, USDC_PRICE_ID, address(wTK), address(agroUSD));
        LendingProtocol protocol = new LendingProtocol(address(liveOracle));

        protocol.addMarket(address(wTK), 7_500, 8_000, 500, 500, 1_000);
        protocol.addMarket(address(agroUSD), 7_500, 8_000, 500, 500, 1_000);

        wTK.mint(cooperativaAFRA, 10_000 * WAD);
        agroUSD.mint(molinosRioParana, 100_000 * WAD);

        vm.startPrank(molinosRioParana);
        agroUSD.approve(address(protocol), 100_000 * WAD);
        protocol.supplyLiquidity(address(agroUSD), 100_000 * WAD);
        vm.stopPrank();

        vm.startPrank(cooperativaAFRA);
        wTK.approve(address(protocol), 10_000 * WAD);
        protocol.depositCollateral(address(wTK), 10_000 * WAD);
        vm.stopPrank();

        uint256 wheatCollateralValueUsd = (10_000 * WAD * liveOracle.getPrice(address(wTK))) / 1e8;
        uint256 expectedBorrowLimitUsd = (wheatCollateralValueUsd * 7_500) / 10_000;
        uint256 requestedAUSD = 40_000 * WAD;

        assertEq(protocol.getBorrowLimitUsd(cooperativaAFRA), expectedBorrowLimitUsd);
        assertEq(protocol.getMaxBorrowableTokenAmount(cooperativaAFRA, address(agroUSD)), expectedBorrowLimitUsd);

        vm.prank(cooperativaAFRA);
        protocol.borrow(address(agroUSD), requestedAUSD);

        assertEq(agroUSD.balanceOf(cooperativaAFRA), requestedAUSD);
        assertTrue(protocol.isHealthy(cooperativaAFRA));
    }

    function testNormalizesExpoMinus8() public view {
        IPyth.Price memory price = IPyth.Price({price: 590_100_000, conf: 0, expo: -8, publishTime: 1});

        assertEq(oracle.convertTo8DecimalsForTest(price), 590_100_000);
    }

    function testNormalizesExpoMinus6() public view {
        IPyth.Price memory price = IPyth.Price({price: 5_901_000, conf: 0, expo: -6, publishTime: 1});

        assertEq(oracle.convertTo8DecimalsForTest(price), 590_100_000);
    }

    function testNormalizesExpoMinus10() public view {
        IPyth.Price memory price = IPyth.Price({price: 59_010_000_000, conf: 0, expo: -10, publishTime: 1});

        assertEq(oracle.convertTo8DecimalsForTest(price), 590_100_000);
    }

    function testNormalizesExpoZero() public view {
        IPyth.Price memory price = IPyth.Price({price: 6, conf: 0, expo: 0, publishTime: 1});

        assertEq(oracle.convertTo8DecimalsForTest(price), 600_000_000);
    }

    function testRevertsForNegativePrice() public {
        IPyth.Price memory price = IPyth.Price({price: -1, conf: 0, expo: -8, publishTime: 1});

        vm.expectRevert(bytes("Oracle: price must be positive"));
        oracle.convertTo8DecimalsForTest(price);
    }
}
