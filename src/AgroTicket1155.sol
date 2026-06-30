// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC1155} from "openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";

/**
 * @title AgroTicket1155
 * @notice Educational ERC1155 module for audited agro-finance tickets.
 * @dev Each ticket id represents one audited credit operation. The ERC1155
 * balance tracks who holds the ticket; TicketData tracks the financial facts.
 */
contract AgroTicket1155 is ERC1155, Ownable, Pausable {
    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant MAX_ADVANCE_RATE_BPS = 6_500;

    enum TicketStatus {
        Created,
        Issued,
        Funded,
        Settled,
        Defaulted,
        Cancelled
    }

    struct TicketData {
        address issuer;
        address borrower;
        address asset;
        uint256 assetAmount;
        uint256 notionalUsd;
        uint256 issuedAt;
        uint256 maturity;
        uint256 advanceRateBps;
        bytes32 documentHash;
        string documentURI;
        TicketStatus status;
    }

    uint256 public nextTicketId = 1;
    bool public mintPaused;

    mapping(uint256 => TicketData) public tickets;
    mapping(uint256 => uint256) public pendingMaturityExtension;

    event MintPauseUpdated(bool paused);
    event TicketCreated(
        uint256 indexed ticketId,
        address indexed issuer,
        address indexed borrower,
        address asset,
        uint256 assetAmount,
        uint256 notionalUsd,
        uint256 maturity,
        uint256 advanceRateBps,
        bytes32 documentHash,
        string documentURI
    );
    event TicketIssued(uint256 indexed ticketId, address indexed to);
    event TicketFunded(uint256 indexed ticketId);
    event TicketSettled(uint256 indexed ticketId, uint256 settledAt);
    event TicketDefaulted(uint256 indexed ticketId, uint256 defaultedAt);
    event TicketCancelled(uint256 indexed ticketId);
    event TicketDocumentUpdated(uint256 indexed ticketId, bytes32 documentHash, string documentURI);
    event ExtensionRequested(uint256 indexed ticketId, uint256 requestedMaturity);
    event ExtensionApproved(uint256 indexed ticketId, uint256 oldMaturity, uint256 newMaturity);
    event ExtensionCancelled(uint256 indexed ticketId);

    modifier mintOpen() {
        require(!mintPaused, "Ticket: mint paused");
        _;
    }

    modifier ticketExists(uint256 ticketId) {
        require(tickets[ticketId].issuer != address(0), "Ticket: not found");
        _;
    }

    constructor(string memory uri_, address admin) ERC1155(uri_) Ownable(admin) {
        require(admin != address(0), "Ticket: invalid admin");
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setMintPaused(bool paused) external onlyOwner {
        mintPaused = paused;
        emit MintPauseUpdated(paused);
    }

    function createTicket(
        address borrower,
        address asset,
        uint256 assetAmount,
        uint256 notionalUsd,
        uint256 maturity,
        uint256 advanceRateBps,
        bytes32 documentHash,
        string calldata documentURI
    ) external onlyOwner whenNotPaused returns (uint256 ticketId) {
        require(borrower != address(0), "Ticket: invalid borrower");
        require(asset != address(0), "Ticket: invalid asset");
        require(assetAmount > 0, "Ticket: zero asset amount");
        require(notionalUsd > 0, "Ticket: zero notional");
        require(maturity > block.timestamp, "Ticket: bad maturity");
        require(advanceRateBps <= MAX_ADVANCE_RATE_BPS, "Ticket: advance too high");
        require(documentHash != bytes32(0), "Ticket: missing document");

        ticketId = nextTicketId;
        nextTicketId++;

        tickets[ticketId] = TicketData({
            issuer: msg.sender,
            borrower: borrower,
            asset: asset,
            assetAmount: assetAmount,
            notionalUsd: notionalUsd,
            issuedAt: 0,
            maturity: maturity,
            advanceRateBps: advanceRateBps,
            documentHash: documentHash,
            documentURI: documentURI,
            status: TicketStatus.Created
        });

        emit TicketCreated(
            ticketId,
            msg.sender,
            borrower,
            asset,
            assetAmount,
            notionalUsd,
            maturity,
            advanceRateBps,
            documentHash,
            documentURI
        );
    }

    function issueTicket(uint256 ticketId, address to)
        external
        onlyOwner
        whenNotPaused
        mintOpen
        ticketExists(ticketId)
    {
        TicketData storage ticket = tickets[ticketId];
        require(to != address(0), "Ticket: invalid receiver");
        require(ticket.status == TicketStatus.Created, "Ticket: not created");

        ticket.issuedAt = block.timestamp;
        ticket.status = TicketStatus.Issued;
        _mint(to, ticketId, 1, "");

        emit TicketIssued(ticketId, to);
    }

    function markFunded(uint256 ticketId) external onlyOwner whenNotPaused ticketExists(ticketId) {
        TicketData storage ticket = tickets[ticketId];
        require(ticket.status == TicketStatus.Issued, "Ticket: not issued");

        ticket.status = TicketStatus.Funded;
        emit TicketFunded(ticketId);
    }

    function settleEarly(uint256 ticketId) external onlyOwner whenNotPaused ticketExists(ticketId) {
        _settle(ticketId);
    }

    function settleAtMaturity(uint256 ticketId) external onlyOwner whenNotPaused ticketExists(ticketId) {
        require(block.timestamp >= tickets[ticketId].maturity, "Ticket: not matured");
        _settle(ticketId);
    }

    function markDefaulted(uint256 ticketId) external onlyOwner whenNotPaused ticketExists(ticketId) {
        TicketData storage ticket = tickets[ticketId];
        require(block.timestamp > ticket.maturity, "Ticket: not overdue");
        require(ticket.status == TicketStatus.Issued || ticket.status == TicketStatus.Funded, "Ticket: bad status");

        ticket.status = TicketStatus.Defaulted;
        emit TicketDefaulted(ticketId, block.timestamp);
    }

    function cancelTicket(uint256 ticketId) external onlyOwner whenNotPaused ticketExists(ticketId) {
        TicketData storage ticket = tickets[ticketId];
        require(ticket.status == TicketStatus.Created, "Ticket: already issued");

        ticket.status = TicketStatus.Cancelled;
        emit TicketCancelled(ticketId);
    }

    function updateDocument(uint256 ticketId, bytes32 documentHash, string calldata documentURI)
        external
        onlyOwner
        whenNotPaused
        ticketExists(ticketId)
    {
        require(documentHash != bytes32(0), "Ticket: missing document");

        TicketData storage ticket = tickets[ticketId];
        require(ticket.status != TicketStatus.Settled, "Ticket: settled");
        require(ticket.status != TicketStatus.Defaulted, "Ticket: defaulted");
        require(ticket.status != TicketStatus.Cancelled, "Ticket: cancelled");

        ticket.documentHash = documentHash;
        ticket.documentURI = documentURI;
        emit TicketDocumentUpdated(ticketId, documentHash, documentURI);
    }

    function requestMaturityExtension(uint256 ticketId, uint256 requestedMaturity)
        external
        whenNotPaused
        ticketExists(ticketId)
    {
        TicketData memory ticket = tickets[ticketId];
        require(msg.sender == ticket.borrower || balanceOf(msg.sender, ticketId) > 0, "Ticket: not authorized");
        require(ticket.status == TicketStatus.Issued || ticket.status == TicketStatus.Funded, "Ticket: bad status");
        require(requestedMaturity > ticket.maturity, "Ticket: not an extension");

        pendingMaturityExtension[ticketId] = requestedMaturity;
        emit ExtensionRequested(ticketId, requestedMaturity);
    }

    function approveMaturityExtension(uint256 ticketId) external onlyOwner whenNotPaused ticketExists(ticketId) {
        uint256 requestedMaturity = pendingMaturityExtension[ticketId];
        require(requestedMaturity != 0, "Ticket: no extension");

        TicketData storage ticket = tickets[ticketId];
        require(ticket.status == TicketStatus.Issued || ticket.status == TicketStatus.Funded, "Ticket: bad status");

        uint256 oldMaturity = ticket.maturity;
        ticket.maturity = requestedMaturity;
        pendingMaturityExtension[ticketId] = 0;

        emit ExtensionApproved(ticketId, oldMaturity, requestedMaturity);
    }

    function cancelMaturityExtension(uint256 ticketId) external onlyOwner ticketExists(ticketId) {
        require(pendingMaturityExtension[ticketId] != 0, "Ticket: no extension");

        pendingMaturityExtension[ticketId] = 0;
        emit ExtensionCancelled(ticketId);
    }

    function collateralValueUsd(uint256 ticketId) external view ticketExists(ticketId) returns (uint256) {
        TicketData memory ticket = tickets[ticketId];
        return (ticket.notionalUsd * ticket.advanceRateBps) / BASIS_POINTS;
    }

    function _settle(uint256 ticketId) internal {
        TicketData storage ticket = tickets[ticketId];
        require(ticket.status == TicketStatus.Issued || ticket.status == TicketStatus.Funded, "Ticket: bad status");

        ticket.status = TicketStatus.Settled;
        emit TicketSettled(ticketId, block.timestamp);
    }
}
