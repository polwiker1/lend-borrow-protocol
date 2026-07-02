// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgroTicket1155} from "../src/AgroTicket1155.sol";
import {MockToken} from "../src/MockToken.sol";
import {IAgroTicket1155, SLT} from "../src/SLT.sol";

contract SLTTest is Test {
    uint256 private constant WAD = 1e18;

    address private admin = address(this);
    address private primaryBorrower = address(0xA11CE);
    address private secondaryWallet = address(0xB0B);
    address private outsider = address(0xBAD);

    AgroTicket1155 private tickets;
    MockToken private gTK;
    SLT private slt;

    bytes32 private ltpHash = keccak256("ltp-girasol-cal-v1");
    bytes32 private sltHash = keccak256("slt-subcredito-cal-v1");

    function setUp() public {
        tickets = new AgroTicket1155("ipfs://agro-ticket/{id}.json", admin);
        gTK = new MockToken("Sunflower Token", "gTK", 18, 0, admin);
        slt = new SLT(IAgroTicket1155(address(tickets)), admin);
    }

    function testPrimaryBorrowerCanRequestAndAdminCanApproveSLT() public {
        uint256 ticketId = _createIssuedTicket();

        vm.prank(primaryBorrower);
        uint256 sltId = slt.requestSLT(
            ticketId,
            secondaryWallet,
            20_000 * WAD,
            25_000 * WAD,
            10_000,
            block.timestamp + 90 days,
            sltHash,
            "ipfs://slt-cal-v1"
        );

        slt.approveSLT(sltId, 20_000 * WAD);

        SLT.SLTPosition memory position = slt.getSLT(sltId);
        assertEq(position.ltpTicketId, ticketId);
        assertEq(position.primaryBorrower, primaryBorrower);
        assertEq(position.recipient, secondaryWallet);
        assertEq(position.maxSLTAmountUsd, 40_000 * WAD);
        assertEq(position.approvedAmountUsd, 20_000 * WAD);
        assertEq(uint256(position.status), uint256(SLT.SLTStatus.Approved));
    }

    function testRejectsDuplicateSLTForSameLTP() public {
        uint256 ticketId = _createIssuedTicket();
        _requestDefaultSLT(ticketId);

        vm.prank(primaryBorrower);
        vm.expectRevert(bytes("SLT: LTP already used"));
        slt.requestSLT(
            ticketId,
            secondaryWallet,
            10_000 * WAD,
            25_000 * WAD,
            10_000,
            block.timestamp + 90 days,
            sltHash,
            "ipfs://slt-cal-v2"
        );
    }

    function testRejectsAmountAboveFreeMargin() public {
        uint256 ticketId = _createIssuedTicket();

        vm.prank(primaryBorrower);
        vm.expectRevert(bytes("SLT: amount exceeds margin"));
        slt.requestSLT(
            ticketId,
            secondaryWallet,
            40_001 * WAD,
            25_000 * WAD,
            10_000,
            block.timestamp + 90 days,
            sltHash,
            "ipfs://slt-cal-v1"
        );
    }

    function testRejectsNonPrimaryBorrower() public {
        uint256 ticketId = _createIssuedTicket();

        vm.prank(outsider);
        vm.expectRevert(bytes("SLT: only primary borrower"));
        slt.requestSLT(
            ticketId,
            secondaryWallet,
            20_000 * WAD,
            25_000 * WAD,
            10_000,
            block.timestamp + 90 days,
            sltHash,
            "ipfs://slt-cal-v1"
        );
    }

    function testRejectsMaturityAfterLTP() public {
        uint256 ticketId = _createIssuedTicket();

        vm.prank(primaryBorrower);
        vm.expectRevert(bytes("SLT: maturity exceeds LTP"));
        slt.requestSLT(
            ticketId,
            secondaryWallet,
            20_000 * WAD,
            25_000 * WAD,
            10_000,
            block.timestamp + 181 days,
            sltHash,
            "ipfs://slt-cal-v1"
        );
    }

    function testCanFundRepayAndDefaultLifecycle() public {
        uint256 ticketId = _createIssuedTicket();
        uint256 sltId = _requestDefaultSLT(ticketId);

        slt.approveSLT(sltId, 20_000 * WAD);
        vm.prank(primaryBorrower);
        slt.markFunded(sltId);
        slt.markRepaid(sltId);

        SLT.SLTPosition memory repaid = slt.getSLT(sltId);
        assertEq(uint256(repaid.status), uint256(SLT.SLTStatus.Repaid));

        uint256 secondTicket = _createIssuedTicket();
        uint256 defaultSlt = _requestDefaultSLT(secondTicket);
        slt.approveSLT(defaultSlt, 20_000 * WAD);
        vm.prank(primaryBorrower);
        slt.markFunded(defaultSlt);

        vm.warp(block.timestamp + 91 days);
        slt.markDefaulted(defaultSlt);

        SLT.SLTPosition memory defaulted = slt.getSLT(defaultSlt);
        assertEq(uint256(defaulted.status), uint256(SLT.SLTStatus.Defaulted));
    }

    function testOnlyPrimaryBorrowerCanMarkSLTFunded() public {
        uint256 ticketId = _createIssuedTicket();
        uint256 sltId = _requestDefaultSLT(ticketId);

        slt.approveSLT(sltId, 20_000 * WAD);

        vm.prank(outsider);
        vm.expectRevert(bytes("SLT: only primary borrower"));
        slt.markFunded(sltId);

        vm.prank(primaryBorrower);
        slt.markFunded(sltId);

        SLT.SLTPosition memory position = slt.getSLT(sltId);
        assertEq(uint256(position.status), uint256(SLT.SLTStatus.Funded));
    }

    function _requestDefaultSLT(uint256 ticketId) internal returns (uint256) {
        vm.prank(primaryBorrower);
        return slt.requestSLT(
            ticketId,
            secondaryWallet,
            20_000 * WAD,
            25_000 * WAD,
            10_000,
            block.timestamp + 90 days,
            sltHash,
            "ipfs://slt-cal-v1"
        );
    }

    function _createIssuedTicket() internal returns (uint256 ticketId) {
        ticketId = tickets.createTicket(
            primaryBorrower,
            address(gTK),
            500 * WAD,
            100_000 * WAD,
            block.timestamp + 180 days,
            6_500,
            ltpHash,
            "ipfs://ltp-cal-v1"
        );

        tickets.issueTicket(ticketId, primaryBorrower);
    }
}
