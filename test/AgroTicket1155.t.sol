// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgroTicket1155} from "../src/AgroTicket1155.sol";
import {MockToken} from "../src/MockToken.sol";

contract AgroTicket1155Test is Test {
    uint256 private constant WAD = 1e18;

    address private molinosRioParana = address(this);
    address private camionerosEntreRios = address(0xCA11);
    address private outsider = address(0xBAD);

    AgroTicket1155 private tickets;
    MockToken private wTK;

    bytes32 private documentHash = keccak256("contrato-ticket-wtk-camioneros-v1");

    function setUp() public {
        tickets = new AgroTicket1155("ipfs://agro-ticket/{id}.json", molinosRioParana);
        wTK = new MockToken("Wheat Token", "wTK", 18, 0, address(this));
    }

    function testCreatesAndIssuesAuditableTicket() public {
        uint256 ticketId = _createDefaultTicket();

        tickets.issueTicket(ticketId, camionerosEntreRios);

        assertEq(tickets.balanceOf(camionerosEntreRios, ticketId), 1);
        assertEq(tickets.collateralValueUsd(ticketId), 1_300_000 * WAD);

        (
            address issuer,
            address borrower,
            address asset,
            uint256 assetAmount,
            uint256 notionalUsd,
            uint256 issuedAt,
            uint256 maturity,
            uint256 advanceRateBps,
            bytes32 storedDocumentHash,
            string memory documentURI,
            AgroTicket1155.TicketStatus status
        ) = tickets.tickets(ticketId);

        assertEq(issuer, molinosRioParana);
        assertEq(borrower, camionerosEntreRios);
        assertEq(asset, address(wTK));
        assertEq(assetAmount, 10_000 * WAD);
        assertEq(notionalUsd, 2_000_000 * WAD);
        assertEq(issuedAt, block.timestamp);
        assertEq(maturity, block.timestamp + 180 days);
        assertEq(advanceRateBps, 6_500);
        assertEq(storedDocumentHash, documentHash);
        assertEq(documentURI, "ipfs://ticket-camioneros-v1");
        assertEq(uint256(status), uint256(AgroTicket1155.TicketStatus.Issued));
    }

    function testRejectsAdvanceRateAboveSixtyFivePercent() public {
        vm.expectRevert(bytes("Ticket: advance too high"));
        tickets.createTicket(
            camionerosEntreRios,
            address(wTK),
            10_000 * WAD,
            2_000_000 * WAD,
            block.timestamp + 180 days,
            6_501,
            documentHash,
            "ipfs://ticket-camioneros-v1"
        );
    }

    function testMintPauseBlocksIssueButAllowsAdminCreate() public {
        tickets.setMintPaused(true);

        uint256 ticketId = _createDefaultTicket();

        vm.expectRevert(bytes("Ticket: mint paused"));
        tickets.issueTicket(ticketId, camionerosEntreRios);

        tickets.setMintPaused(false);
        tickets.issueTicket(ticketId, camionerosEntreRios);

        assertEq(tickets.balanceOf(camionerosEntreRios, ticketId), 1);
    }

    function testCanSettleEarlyBeforeMaturity() public {
        uint256 ticketId = _createIssuedTicket();

        tickets.settleEarly(ticketId);

        (,,,,,,,,,, AgroTicket1155.TicketStatus status) = tickets.tickets(ticketId);
        assertEq(uint256(status), uint256(AgroTicket1155.TicketStatus.Settled));
    }

    function testCannotDefaultBeforeMaturity() public {
        uint256 ticketId = _createIssuedTicket();

        vm.expectRevert(bytes("Ticket: not overdue"));
        tickets.markDefaulted(ticketId);
    }

    function testCanDefaultAfterMaturity() public {
        uint256 ticketId = _createIssuedTicket();

        vm.warp(block.timestamp + 181 days);
        tickets.markDefaulted(ticketId);

        (,,,,,,,,,, AgroTicket1155.TicketStatus status) = tickets.tickets(ticketId);
        assertEq(uint256(status), uint256(AgroTicket1155.TicketStatus.Defaulted));
    }

    function testBorrowerCanRequestAndAdminCanApproveExtension() public {
        uint256 ticketId = _createIssuedTicket();
        uint256 requestedMaturity = block.timestamp + 240 days;

        vm.prank(camionerosEntreRios);
        tickets.requestMaturityExtension(ticketId, requestedMaturity);

        assertEq(tickets.pendingMaturityExtension(ticketId), requestedMaturity);

        tickets.approveMaturityExtension(ticketId);

        (,,,,,, uint256 maturity,,,,) = tickets.tickets(ticketId);
        assertEq(maturity, requestedMaturity);
        assertEq(tickets.pendingMaturityExtension(ticketId), 0);
    }

    function testOutsiderCannotRequestExtension() public {
        uint256 ticketId = _createIssuedTicket();

        vm.prank(outsider);
        vm.expectRevert(bytes("Ticket: not authorized"));
        tickets.requestMaturityExtension(ticketId, block.timestamp + 240 days);
    }

    function testDocumentCanBeUpdatedBeforeFinalState() public {
        uint256 ticketId = _createIssuedTicket();
        bytes32 newHash = keccak256("contrato-ticket-wtk-camioneros-v2");

        tickets.updateDocument(ticketId, newHash, "ipfs://ticket-camioneros-v2");

        (,,,,,,,, bytes32 storedDocumentHash, string memory documentURI,) = tickets.tickets(ticketId);
        assertEq(storedDocumentHash, newHash);
        assertEq(documentURI, "ipfs://ticket-camioneros-v2");
    }

    function _createDefaultTicket() internal returns (uint256) {
        return tickets.createTicket(
            camionerosEntreRios,
            address(wTK),
            10_000 * WAD,
            2_000_000 * WAD,
            block.timestamp + 180 days,
            6_500,
            documentHash,
            "ipfs://ticket-camioneros-v1"
        );
    }

    function _createIssuedTicket() internal returns (uint256 ticketId) {
        ticketId = _createDefaultTicket();
        tickets.issueTicket(ticketId, camionerosEntreRios);
    }
}
