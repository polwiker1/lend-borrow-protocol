// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgroTicket1155} from "../src/AgroTicket1155.sol";
import {AgroTicketReceiptVault} from "../src/AgroTicketReceiptVault.sol";
import {LendingProtocol} from "../src/LendingProtocol.sol";
import {MockPriceOracle} from "../src/MockPriceOracle.sol";
import {MockToken} from "../src/MockToken.sol";

contract AgroTicketLendingIntegrationTest is Test {
    uint256 private constant WAD = 1e18;

    address private molinosRioParana = address(this);
    address private camionerosEntreRios = address(0xCA11);
    address private lender = address(0xBEEF);

    AgroTicket1155 private tickets;
    AgroTicketReceiptVault private ticketVault;
    LendingProtocol private protocol;
    MockPriceOracle private oracle;
    MockToken private wTK;
    MockToken private agroUSD;

    bytes32 private documentHash = keccak256("contrato-ticket-wtk-camioneros-v1");

    function setUp() public {
        tickets = new AgroTicket1155("ipfs://agro-ticket/{id}.json", molinosRioParana);
        ticketVault = new AgroTicketReceiptVault(tickets, molinosRioParana);
        oracle = new MockPriceOracle();
        protocol = new LendingProtocol(address(oracle));

        wTK = new MockToken("Wheat Token", "wTK", 18, 0, address(this));
        agroUSD = new MockToken("Agro USD", "aUSD", 18, 0, address(this));

        oracle.setPrice(address(ticketVault), 2_000_000e8);
        oracle.setPrice(address(agroUSD), 1e8);

        protocol.addMarket(address(ticketVault), 6_500, 8_000, 500, 500, 1_000);
        protocol.addMarket(address(agroUSD), 8_000, 8_500, 500, 500, 1_000);

        agroUSD.mint(lender, 2_000_000 * WAD);

        vm.startPrank(lender);
        agroUSD.approve(address(protocol), 2_000_000 * WAD);
        protocol.supplyLiquidity(address(agroUSD), 2_000_000 * WAD);
        vm.stopPrank();
    }

    function testTicketReceiptCanBackBorrowUpToSixtyFivePercentOfNotional() public {
        uint256 ticketId = _issueAndLockTicket();

        vm.startPrank(camionerosEntreRios);
        ticketVault.approve(address(protocol), 1 * WAD);
        protocol.depositCollateral(address(ticketVault), 1 * WAD);
        vm.stopPrank();

        uint256 expectedBorrowLimit = tickets.collateralValueUsd(ticketId);

        assertEq(tickets.balanceOf(camionerosEntreRios, ticketId), 0);
        assertEq(tickets.balanceOf(address(ticketVault), ticketId), 1);
        assertEq(ticketVault.balanceOf(address(protocol)), 1 * WAD);
        assertEq(protocol.collateralDeposits(camionerosEntreRios, address(ticketVault)), 1 * WAD);
        assertEq(expectedBorrowLimit, 1_300_000 * WAD);
        assertEq(protocol.getBorrowLimitUsd(camionerosEntreRios), expectedBorrowLimit);
        assertEq(protocol.getMaxBorrowableTokenAmount(camionerosEntreRios, address(agroUSD)), expectedBorrowLimit);

        vm.prank(camionerosEntreRios);
        protocol.borrow(address(agroUSD), 1_000_000 * WAD);

        assertEq(agroUSD.balanceOf(camionerosEntreRios), 1_000_000 * WAD);
        assertTrue(protocol.isHealthy(camionerosEntreRios));
    }

    function testTicketReceiptRejectsBorrowAboveSixtyFivePercentOfNotional() public {
        _issueAndLockTicket();

        vm.startPrank(camionerosEntreRios);
        ticketVault.approve(address(protocol), 1 * WAD);
        protocol.depositCollateral(address(ticketVault), 1 * WAD);

        vm.expectRevert(bytes("Borrow exceeds collateral"));
        protocol.borrow(address(agroUSD), 1_300_000 * WAD + 1);
        vm.stopPrank();
    }

    function testSameTicketCannotMintReceiptTwice() public {
        uint256 ticketId = _issueAndLockTicket();

        assertTrue(ticketVault.ticketLocked(ticketId));
        assertEq(ticketVault.balanceOf(camionerosEntreRios), 1 * WAD);

        vm.prank(camionerosEntreRios);
        vm.expectRevert(bytes("Vault: ticket already locked"));
        ticketVault.lockTicket(ticketId);
    }

    function _issueAndLockTicket() internal returns (uint256 ticketId) {
        ticketId = tickets.createTicket(
            camionerosEntreRios,
            address(wTK),
            10_000 * WAD,
            2_000_000 * WAD,
            block.timestamp + 180 days,
            6_500,
            documentHash,
            "ipfs://ticket-camioneros-v1"
        );

        tickets.issueTicket(ticketId, camionerosEntreRios);

        vm.startPrank(camionerosEntreRios);
        tickets.setApprovalForAll(address(ticketVault), true);
        ticketVault.lockTicket(ticketId);
        vm.stopPrank();
    }
}
