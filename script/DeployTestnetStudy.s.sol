// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {AgroTicket1155} from "../src/AgroTicket1155.sol";
import {AgroTicketReceiptVault} from "../src/AgroTicketReceiptVault.sol";
import {LendingProtocol} from "../src/LendingProtocol.sol";
import {MockPriceOracle} from "../src/MockPriceOracle.sol";
import {MockToken} from "../src/MockToken.sol";
import {IAgroTicket1155, SLT} from "../src/SLT.sol";

contract DeployTestnetStudy is Script {
    uint256 private constant WAD = 1e18;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.envOr("ADMIN_ADDRESS", vm.addr(deployerPrivateKey));
        string memory ticketBaseUri = vm.envOr("TICKET_BASE_URI", string("ipfs://agro-ticket/{id}.json"));

        vm.startBroadcast(deployerPrivateKey);

        MockPriceOracle oracle = new MockPriceOracle();
        LendingProtocol lending = new LendingProtocol(address(oracle));
        AgroTicket1155 tickets = new AgroTicket1155(ticketBaseUri, admin);
        AgroTicketReceiptVault vault = new AgroTicketReceiptVault(tickets, admin);
        SLT slt = new SLT(IAgroTicket1155(address(tickets)), admin);
        MockToken agroUSD = new MockToken("Agro USD Testnet", "aUSD", 18, 0, admin);
        MockToken wTK = new MockToken("Wheat Token Testnet", "wTK", 18, 0, admin);
        MockToken sTK = new MockToken("Soy Token Testnet", "sTK", 18, 0, admin);
        MockToken gTK = new MockToken("Sunflower Token Testnet", "gTK", 18, 0, admin);

        oracle.setPrice(address(vault), 2_000_000e8);
        oracle.setPrice(address(agroUSD), 1e8);
        oracle.setPrice(address(wTK), 21_682_457_370);
        oracle.setPrice(address(sTK), 420e8);
        oracle.setPrice(address(gTK), 360e8);

        lending.addMarket(address(vault), 6_500, 8_000, 500, 500, 1_000);
        lending.addMarket(address(agroUSD), 8_000, 8_500, 500, 500, 1_000);
        lending.addMarket(address(wTK), 6_500, 8_000, 500, 500, 1_000);
        lending.addMarket(address(sTK), 6_500, 8_000, 500, 500, 1_000);
        lending.addMarket(address(gTK), 6_500, 8_000, 500, 500, 1_000);

        if (admin != vm.addr(deployerPrivateKey)) {
            oracle.transferOwnership(admin);
            lending.transferOwnership(admin);
        }

        vm.stopBroadcast();

        console2.log("ADMIN_ADDRESS", admin);
        console2.log("MockPriceOracle", address(oracle));
        console2.log("LendingProtocol", address(lending));
        console2.log("AgroTicket1155", address(tickets));
        console2.log("AgroTicketReceiptVault", address(vault));
        console2.log("SLT", address(slt));
        console2.log("AgroUSD", address(agroUSD));
        console2.log("wTK", address(wTK));
        console2.log("sTK", address(sTK));
        console2.log("gTK", address(gTK));
        console2.log("Seed liquidity suggestion: mint aUSD to lender and supplyLiquidity from that wallet.");
    }
}
