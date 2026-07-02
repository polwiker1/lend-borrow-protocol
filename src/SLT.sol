// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";

interface IAgroTicket1155 {
    enum TicketStatus {
        Created,
        Issued,
        Funded,
        Settled,
        Defaulted,
        Cancelled
    }

    function tickets(uint256 ticketId)
        external
        view
        returns (
            address issuer,
            address borrower,
            address asset,
            uint256 assetAmount,
            uint256 notionalUsd,
            uint256 issuedAt,
            uint256 maturity,
            uint256 advanceRateBps,
            bytes32 documentHash,
            string memory documentURI,
            TicketStatus status
        );

    function collateralValueUsd(uint256 ticketId) external view returns (uint256);
}

/**
 * @title SLT
 * @notice Non-transferable registry for a secondary liquidity ticket.
 * @dev SLT is not a token. It records a one-time delegation of free credit
 * margin from a primary LTP borrower to a third-party wallet.
 */
contract SLT is Ownable, Pausable {
    uint256 public constant BASIS_POINTS = 10_000;

    enum SLTStatus {
        None,
        Requested,
        Approved,
        Funded,
        Repaid,
        Defaulted,
        Cancelled
    }

    struct SLTPosition {
        uint256 ltpTicketId;
        address primaryBorrower;
        address recipient;
        uint256 requestedAmountUsd;
        uint256 approvedAmountUsd;
        uint256 currentDebtUsdSnapshot;
        uint256 maxSLTAmountUsd;
        uint256 sltFactorBps;
        uint256 requestedAt;
        uint256 approvedAt;
        uint256 maturity;
        bytes32 documentHash;
        string documentURI;
        SLTStatus status;
    }

    IAgroTicket1155 public immutable tickets;
    uint256 public nextSLTId = 1;

    mapping(uint256 => SLTPosition) public positions;
    mapping(uint256 => uint256) public sltByLTP;

    event SLTRequested(
        uint256 indexed sltId,
        uint256 indexed ltpTicketId,
        address indexed primaryBorrower,
        address recipient,
        uint256 requestedAmountUsd,
        uint256 maxSLTAmountUsd,
        uint256 maturity,
        bytes32 documentHash,
        string documentURI
    );
    event SLTApproved(uint256 indexed sltId, uint256 approvedAmountUsd);
    event SLTFunded(uint256 indexed sltId);
    event SLTRepaid(uint256 indexed sltId);
    event SLTDefaulted(uint256 indexed sltId);
    event SLTCancelled(uint256 indexed sltId);

    constructor(IAgroTicket1155 tickets_, address admin) Ownable(admin) {
        require(address(tickets_) != address(0), "SLT: invalid tickets");
        require(admin != address(0), "SLT: invalid admin");
        tickets = tickets_;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function requestSLT(
        uint256 ltpTicketId,
        address recipient,
        uint256 requestedAmountUsd,
        uint256 currentDebtUsd,
        uint256 sltFactorBps,
        uint256 maturity,
        bytes32 documentHash,
        string calldata documentURI
    ) external whenNotPaused returns (uint256 sltId) {
        require(sltByLTP[ltpTicketId] == 0, "SLT: LTP already used");
        require(recipient != address(0), "SLT: invalid recipient");
        require(requestedAmountUsd > 0, "SLT: zero amount");
        require(sltFactorBps <= BASIS_POINTS, "SLT: bad factor");
        require(documentHash != bytes32(0), "SLT: missing document");

        (, address primaryBorrower,,,,, uint256 ltpMaturity,,,, IAgroTicket1155.TicketStatus status) =
            tickets.tickets(ltpTicketId);
        require(primaryBorrower != address(0), "SLT: LTP not found");
        require(msg.sender == primaryBorrower, "SLT: only primary borrower");
        require(recipient != primaryBorrower, "SLT: recipient is borrower");
        require(
            status == IAgroTicket1155.TicketStatus.Issued || status == IAgroTicket1155.TicketStatus.Funded,
            "SLT: bad LTP status"
        );
        require(maturity > block.timestamp, "SLT: bad maturity");
        require(maturity <= ltpMaturity, "SLT: maturity exceeds LTP");

        uint256 maxAmount = maxSLTAmount(ltpTicketId, currentDebtUsd, sltFactorBps);
        require(requestedAmountUsd <= maxAmount, "SLT: amount exceeds margin");

        sltId = nextSLTId;
        nextSLTId++;
        sltByLTP[ltpTicketId] = sltId;

        positions[sltId] = SLTPosition({
            ltpTicketId: ltpTicketId,
            primaryBorrower: primaryBorrower,
            recipient: recipient,
            requestedAmountUsd: requestedAmountUsd,
            approvedAmountUsd: 0,
            currentDebtUsdSnapshot: currentDebtUsd,
            maxSLTAmountUsd: maxAmount,
            sltFactorBps: sltFactorBps,
            requestedAt: block.timestamp,
            approvedAt: 0,
            maturity: maturity,
            documentHash: documentHash,
            documentURI: documentURI,
            status: SLTStatus.Requested
        });

        emit SLTRequested(
            sltId,
            ltpTicketId,
            primaryBorrower,
            recipient,
            requestedAmountUsd,
            maxAmount,
            maturity,
            documentHash,
            documentURI
        );
    }

    function approveSLT(uint256 sltId, uint256 approvedAmountUsd) external onlyOwner whenNotPaused {
        SLTPosition storage position = positions[sltId];
        require(position.status == SLTStatus.Requested, "SLT: not requested");
        require(approvedAmountUsd > 0, "SLT: zero approval");
        require(approvedAmountUsd <= position.requestedAmountUsd, "SLT: approval too high");
        require(approvedAmountUsd <= position.maxSLTAmountUsd, "SLT: exceeds max");

        position.approvedAmountUsd = approvedAmountUsd;
        position.approvedAt = block.timestamp;
        position.status = SLTStatus.Approved;

        emit SLTApproved(sltId, approvedAmountUsd);
    }

    function markFunded(uint256 sltId) external whenNotPaused {
        SLTPosition storage position = positions[sltId];
        require(position.status == SLTStatus.Approved, "SLT: not approved");
        require(msg.sender == position.primaryBorrower, "SLT: only primary borrower");

        position.status = SLTStatus.Funded;
        emit SLTFunded(sltId);
    }

    function markRepaid(uint256 sltId) external onlyOwner whenNotPaused {
        SLTPosition storage position = positions[sltId];
        require(position.status == SLTStatus.Funded, "SLT: not funded");

        position.status = SLTStatus.Repaid;
        emit SLTRepaid(sltId);
    }

    function markDefaulted(uint256 sltId) external onlyOwner whenNotPaused {
        SLTPosition storage position = positions[sltId];
        require(position.status == SLTStatus.Funded, "SLT: not funded");
        require(block.timestamp > position.maturity, "SLT: not overdue");

        position.status = SLTStatus.Defaulted;
        emit SLTDefaulted(sltId);
    }

    function cancelSLT(uint256 sltId) external onlyOwner whenNotPaused {
        SLTPosition storage position = positions[sltId];
        require(position.status == SLTStatus.Requested || position.status == SLTStatus.Approved, "SLT: cannot cancel");

        position.status = SLTStatus.Cancelled;
        emit SLTCancelled(sltId);
    }

    function maxSLTAmount(uint256 ltpTicketId, uint256 currentDebtUsd, uint256 sltFactorBps)
        public
        view
        returns (uint256)
    {
        require(sltFactorBps <= BASIS_POINTS, "SLT: bad factor");
        uint256 collateralLimitUsd = tickets.collateralValueUsd(ltpTicketId);
        if (currentDebtUsd >= collateralLimitUsd) return 0;

        uint256 freeMargin = collateralLimitUsd - currentDebtUsd;
        return (freeMargin * sltFactorBps) / BASIS_POINTS;
    }

    function getSLT(uint256 sltId) external view returns (SLTPosition memory) {
        return positions[sltId];
    }
}
