// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC1155Holder} from "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {AgroTicket1155} from "./AgroTicket1155.sol";

/**
 * @title AgroTicketReceiptVault
 * @notice Custodies AgroTicket1155 tickets and mints one ERC20 receipt per ticket.
 * @dev This prevents the same ticketId from backing more than one borrow flow.
 */
contract AgroTicketReceiptVault is ERC20, ERC1155Holder, Ownable, Pausable {
    uint256 public constant RECEIPT_UNIT = 1e18;

    AgroTicket1155 public immutable tickets;

    mapping(uint256 => bool) public ticketLocked;
    mapping(uint256 => address) public originalDepositor;

    event TicketLocked(uint256 indexed ticketId, address indexed depositor);

    constructor(AgroTicket1155 tickets_, address admin) ERC20("Agro Ticket Receipt", "agTICKET") Ownable(admin) {
        require(address(tickets_) != address(0), "Vault: invalid tickets");
        require(admin != address(0), "Vault: invalid admin");
        tickets = tickets_;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function lockTicket(uint256 ticketId) external whenNotPaused {
        require(!ticketLocked[ticketId], "Vault: ticket already locked");
        require(tickets.balanceOf(msg.sender, ticketId) == 1, "Vault: ticket balance must be one");

        ticketLocked[ticketId] = true;
        originalDepositor[ticketId] = msg.sender;

        tickets.safeTransferFrom(msg.sender, address(this), ticketId, 1, "");
        _mint(msg.sender, RECEIPT_UNIT);

        emit TicketLocked(ticketId, msg.sender);
    }
}
