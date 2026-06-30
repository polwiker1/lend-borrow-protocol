// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {LendingProtocol} from "../src/LendingProtocol.sol";
import {MockPriceOracle} from "../src/MockPriceOracle.sol";
import {MockToken} from "../src/MockToken.sol";

contract LendingProtocolTest is Test {
    uint256 private constant WAD = 1e18;

    address private lender = address(0xA11CE);
    address private borrower = address(0xB0B);
    address private liquidator = address(0xCAFE);
    address private molinosRioParana = address(0xBEEF);
    address private cooperativaAFRA = address(0xAFa);
    address private asociacionTransportistasCamionesLtd = address(0xCA11);

    MockToken private ethToken;
    MockToken private usdToken;
    MockPriceOracle private oracle;
    LendingProtocol private protocol;

    function setUp() public {
        ethToken = new MockToken("Mock ETH", "mETH", 18, 0, address(this));
        usdToken = new MockToken("Mock USD", "mUSD", 18, 0, address(this));
        oracle = new MockPriceOracle();
        protocol = new LendingProtocol(address(oracle));

        oracle.setPrice(address(ethToken), 2_000e8);
        oracle.setPrice(address(usdToken), 1e8);

        protocol.addMarket(address(ethToken), 7_500, 8_000, 500, 500, 1_000);
        protocol.addMarket(address(usdToken), 8_000, 8_500, 500, 500, 1_000);

        ethToken.mint(borrower, 1 * WAD);
        usdToken.mint(lender, 10_000 * WAD);
        usdToken.mint(liquidator, 10_000 * WAD);
    }

    function testBorrowAgainstCollateral() public {
        vm.startPrank(lender);
        usdToken.approve(address(protocol), 10_000 * WAD);
        protocol.supplyLiquidity(address(usdToken), 10_000 * WAD);
        vm.stopPrank();

        vm.startPrank(borrower);
        ethToken.approve(address(protocol), 1 * WAD);
        protocol.depositCollateral(address(ethToken), 1 * WAD);
        protocol.borrow(address(usdToken), 1_000 * WAD);
        vm.stopPrank();

        assertEq(usdToken.balanceOf(borrower), 1_000 * WAD);
        assertEq(protocol.getBorrowLimitUsd(borrower), 1_500 * WAD);
        assertTrue(protocol.isHealthy(borrower));
    }

    function testRejectsLiquidationPenaltyBelowFivePercent() public {
        MockToken token = new MockToken("Low Bonus", "LOW", 18, 0, address(this));
        oracle.setPrice(address(token), 1e8);

        vm.expectRevert(bytes("Bad liquidation penalty"));
        protocol.addMarket(address(token), 7_500, 8_000, 499, 500, 1_000);
    }

    function testRejectsLiquidationPenaltyAboveTenPercent() public {
        vm.expectRevert(bytes("Bad liquidation penalty"));
        protocol.updateMarket(address(ethToken), 7_500, 8_000, 1_001, 500, 1_000);
    }

    function testAllowsLiquidationPenaltyBetweenFiveAndTenPercent() public {
        protocol.updateMarket(address(ethToken), 7_500, 8_000, 750, 500, 1_000);

        (,,,, uint256 liquidationPenalty,,,,) = protocol.markets(address(ethToken));
        assertEq(liquidationPenalty, 750);
    }

    function testDebtAccruesSimpleInterest() public {
        vm.startPrank(lender);
        usdToken.approve(address(protocol), 10_000 * WAD);
        protocol.supplyLiquidity(address(usdToken), 10_000 * WAD);
        vm.stopPrank();

        vm.startPrank(borrower);
        ethToken.approve(address(protocol), 1 * WAD);
        protocol.depositCollateral(address(ethToken), 1 * WAD);
        protocol.borrow(address(usdToken), 1_000 * WAD);
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);

        assertEq(protocol.getDebtValueUsd(borrower), 1_050 * WAD);
    }

    function testRepayAccruedDebtThenBorrowAgainStartsFresh() public {
        vm.startPrank(lender);
        usdToken.approve(address(protocol), 10_000 * WAD);
        protocol.supplyLiquidity(address(usdToken), 10_000 * WAD);
        vm.stopPrank();

        vm.startPrank(borrower);
        ethToken.approve(address(protocol), 1 * WAD);
        protocol.depositCollateral(address(ethToken), 1 * WAD);
        protocol.borrow(address(usdToken), 1_000 * WAD);
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);

        // The borrower owes 1000 principal + 50 interest.
        assertEq(protocol.getDebtValueUsd(borrower), 1_050 * WAD);

        // Give the borrower the extra 50 needed to pay the interest.
        usdToken.mint(borrower, 50 * WAD);

        vm.startPrank(borrower);
        usdToken.approve(address(protocol), 1_050 * WAD);
        protocol.repay(address(usdToken), 1_050 * WAD);
        vm.stopPrank();

        assertEq(protocol.getDebtValueUsd(borrower), 0);
        assertEq(usdToken.balanceOf(borrower), 0);

        vm.warp(block.timestamp + 365 days);

        vm.prank(borrower);
        protocol.borrow(address(usdToken), 100 * WAD);

        assertEq(protocol.getDebtValueUsd(borrower), 100 * WAD);
        assertEq(usdToken.balanceOf(borrower), 100 * WAD);
    }

    function testLenderEarnsInterestThroughLiquidityShares() public {
        vm.startPrank(lender);
        usdToken.approve(address(protocol), 10_000 * WAD);
        protocol.supplyLiquidity(address(usdToken), 10_000 * WAD);
        vm.stopPrank();

        assertEq(protocol.liquidityShares(lender, address(usdToken)), 10_000 * WAD);
        assertEq(protocol.getLiquidityValue(lender, address(usdToken)), 10_000 * WAD);

        vm.startPrank(borrower);
        ethToken.approve(address(protocol), 1 * WAD);
        protocol.depositCollateral(address(ethToken), 1 * WAD);
        protocol.borrow(address(usdToken), 1_000 * WAD);
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);

        usdToken.mint(borrower, 50 * WAD);

        vm.startPrank(borrower);
        usdToken.approve(address(protocol), 1_050 * WAD);
        protocol.repay(address(usdToken), 1_050 * WAD);
        vm.stopPrank();

        assertEq(protocol.getLiquidityValue(lender, address(usdToken)), 10_045 * WAD);
        assertEq(protocol.protocolReserves(address(usdToken)), 5 * WAD);

        vm.prank(lender);
        protocol.withdrawLiquidity(address(usdToken), 10_045 * WAD);

        assertEq(usdToken.balanceOf(lender), 10_045 * WAD);
        assertEq(protocol.liquidityShares(lender, address(usdToken)), 0);
    }

    function testProtocolTreasuryEarnsReserveFactorFromInterest() public {
        vm.startPrank(lender);
        usdToken.approve(address(protocol), 10_000 * WAD);
        protocol.supplyLiquidity(address(usdToken), 10_000 * WAD);
        vm.stopPrank();

        vm.startPrank(borrower);
        ethToken.approve(address(protocol), 1 * WAD);
        protocol.depositCollateral(address(ethToken), 1 * WAD);
        protocol.borrow(address(usdToken), 1_000 * WAD);
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);
        usdToken.mint(borrower, 50 * WAD);

        vm.startPrank(borrower);
        usdToken.approve(address(protocol), 1_050 * WAD);
        protocol.repay(address(usdToken), 1_050 * WAD);
        vm.stopPrank();

        assertEq(protocol.getLiquidityValue(lender, address(usdToken)), 10_045 * WAD);
        assertEq(protocol.protocolReserves(address(usdToken)), 5 * WAD);

        protocol.withdrawProtocolReserves(address(usdToken), address(this), 5 * WAD);

        assertEq(usdToken.balanceOf(address(this)), 5 * WAD);
        assertEq(protocol.protocolReserves(address(usdToken)), 0);
    }

    function testTransportistasBorrowWTKAgainstAUSDCollateral() public {
        MockToken wTK = new MockToken("Wheat Token", "wTK", 18, 0, address(this));
        MockToken agroUSD = new MockToken("Agro USD", "aUSD", 18, 0, address(this));

        // Study price based on wheat CME quotation around 5.901 USD per bushel.
        oracle.setPrice(address(wTK), 590_100_000);
        oracle.setPrice(address(agroUSD), 1e8);

        protocol.addMarket(address(wTK), 7_500, 8_000, 500, 500, 1_000);
        protocol.addMarket(address(agroUSD), 7_500, 8_000, 500, 500, 1_000);

        wTK.mint(molinosRioParana, 20_000 * WAD);
        agroUSD.mint(asociacionTransportistasCamionesLtd, 100_000 * WAD);

        vm.startPrank(molinosRioParana);
        wTK.approve(address(protocol), 20_000 * WAD);
        protocol.supplyLiquidity(address(wTK), 20_000 * WAD);
        vm.stopPrank();

        vm.startPrank(asociacionTransportistasCamionesLtd);
        agroUSD.approve(address(protocol), 100_000 * WAD);
        protocol.depositCollateral(address(agroUSD), 100_000 * WAD);
        vm.stopPrank();

        uint256 expectedBorrowLimitUsd = 75_000 * WAD;
        uint256 expectedMaxWTK = (expectedBorrowLimitUsd * 1e8) / 590_100_000;

        assertEq(protocol.getBorrowLimitUsd(asociacionTransportistasCamionesLtd), expectedBorrowLimitUsd);
        assertEq(
            protocol.getMaxBorrowableTokenAmount(asociacionTransportistasCamionesLtd, address(wTK)), expectedMaxWTK
        );

        uint256 requestedWTK = 10_000 * WAD;

        vm.prank(asociacionTransportistasCamionesLtd);
        protocol.borrow(address(wTK), requestedWTK);

        assertEq(wTK.balanceOf(asociacionTransportistasCamionesLtd), requestedWTK);
        assertTrue(protocol.isHealthy(asociacionTransportistasCamionesLtd));
    }

    function testCooperativaAFRABorrowsAUSDAgainstWheatCollateral() public {
        MockToken wTK = new MockToken("Wheat Token", "wTK", 18, 0, address(this));
        MockToken agroUSD = new MockToken("Agro USD", "aUSD", 18, 0, address(this));

        // Productive financing model: AFRA owns wheat and borrows stable liquidity.
        oracle.setPrice(address(wTK), 590_100_000);
        oracle.setPrice(address(agroUSD), 1e8);

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

        uint256 wheatCollateralValueUsd = 59_010 * WAD;
        uint256 expectedBorrowLimitUsd = (wheatCollateralValueUsd * 7_500) / 10_000;
        uint256 requestedAUSD = 40_000 * WAD;

        assertEq(protocol.getBorrowLimitUsd(cooperativaAFRA), expectedBorrowLimitUsd);
        assertEq(protocol.getMaxBorrowableTokenAmount(cooperativaAFRA, address(agroUSD)), expectedBorrowLimitUsd);

        vm.prank(cooperativaAFRA);
        protocol.borrow(address(agroUSD), requestedAUSD);

        assertEq(agroUSD.balanceOf(cooperativaAFRA), requestedAUSD);
        assertTrue(protocol.isHealthy(cooperativaAFRA));
    }

    function testLiquidatorEarnsBonusWhenPositionIsUnsafe() public {
        vm.startPrank(lender);
        usdToken.approve(address(protocol), 10_000 * WAD);
        protocol.supplyLiquidity(address(usdToken), 10_000 * WAD);
        vm.stopPrank();

        vm.startPrank(borrower);
        ethToken.approve(address(protocol), 1 * WAD);
        protocol.depositCollateral(address(ethToken), 1 * WAD);
        protocol.borrow(address(usdToken), 1_000 * WAD);
        vm.stopPrank();

        oracle.setPrice(address(ethToken), 1_000e8);
        assertLt(protocol.getHealthFactor(borrower), 10_000);

        vm.startPrank(liquidator);
        usdToken.approve(address(protocol), 500 * WAD);
        protocol.liquidate(borrower, address(usdToken), address(ethToken), 500 * WAD);
        vm.stopPrank();

        // Liquidator paid 500 mUSD and received 525 USD worth of mETH.
        // That extra 25 USD is the 5% liquidation bonus.
        assertEq(ethToken.balanceOf(liquidator), 0.525 ether);
    }

    function testBadDebtMakesLenderLossVisibleAfterCrash() public {
        vm.startPrank(lender);
        usdToken.approve(address(protocol), 10_000 * WAD);
        protocol.supplyLiquidity(address(usdToken), 10_000 * WAD);
        vm.stopPrank();

        vm.startPrank(borrower);
        ethToken.approve(address(protocol), 1 * WAD);
        protocol.depositCollateral(address(ethToken), 1 * WAD);
        protocol.borrow(address(usdToken), 1_500 * WAD);
        vm.stopPrank();

        // mETH crashes from 2,000 USD to 300 USD.
        // The borrower owes 1,500 mUSD, but all collateral is now worth only 300 USD.
        oracle.setPrice(address(ethToken), 300e8);
        assertLt(protocol.getHealthFactor(borrower), 10_000);

        vm.startPrank(liquidator);
        usdToken.approve(address(protocol), 1_500 * WAD);
        protocol.liquidate(borrower, address(usdToken), address(ethToken), 1_500 * WAD);
        vm.stopPrank();

        uint256 expectedRepay = protocol.repayAmountForCollateral(address(usdToken), address(ethToken), 1 * WAD);
        uint256 expectedBadDebt = (1_500 * WAD) - expectedRepay;
        uint256 expectedLenderValue = (10_000 * WAD) - expectedBadDebt;

        assertEq(ethToken.balanceOf(liquidator), 1 * WAD);
        assertEq(protocol.badDebt(address(usdToken)), expectedBadDebt);
        assertEq(protocol.availableLiquidity(address(usdToken)), expectedLenderValue);
        assertEq(protocol.getLiquidityValue(lender, address(usdToken)), expectedLenderValue);

        vm.prank(lender);
        protocol.withdrawLiquidity(address(usdToken), expectedLenderValue);

        assertEq(usdToken.balanceOf(lender), expectedLenderValue);
    }

    /*
     * Crash risk lesson:
     * A fast collateral crash can make the protocol insolvent. The fix is not to
     * hide the loss; the protocol must record the unpaid amount as bad debt and
     * make that loss visible in the pool accounting.
     *
     * Next improvement:
     * Add a reserve fund or insurance module that absorbs part of badDebt before
     * the loss reaches lenders.
     */
}
