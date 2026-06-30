# Testnet Runbook

This repo can be deployed to a testnet as a study environment for Lending Tango Parana.

## 1. Configure environment

Copy `.env.example` to `.env` and fill:

```bash
PRIVATE_KEY=
RPC_URL=
ADMIN_ADDRESS=
TICKET_BASE_URI=ipfs://agro-ticket/{id}.json
```

`ADMIN_ADDRESS` should ideally be a multisig or an admin wallet used only for this testnet study.

## 2. Dry run

```bash
set -a
source .env
set +a
forge script script/DeployTestnetStudy.s.sol:DeployTestnetStudy --rpc-url "$RPC_URL"
```

## 3. Broadcast

```bash
set -a
source .env
set +a
forge script script/DeployTestnetStudy.s.sol:DeployTestnetStudy --rpc-url "$RPC_URL" --broadcast
```

The script prints:

- `MockPriceOracle`
- `LendingProtocol`
- `AgroTicket1155`
- `AgroTicketReceiptVault`
- `AgroUSD`
- `wTK`
- `sTK`
- `gTK`

## 4. Admin flow

The intended human flow is:

1. Admin creates the ERC1155 ticket in `AgroTicket1155`.
2. Admin issues the ticket to the borrower.
3. Borrower locks the ERC1155 ticket in `AgroTicketReceiptVault`.
4. Vault mints one `agTICKET` receipt.
5. Borrower deposits `agTICKET` into `LendingProtocol`.
6. Borrower can borrow up to the configured collateral factor, capped by the ticket advance model.

The key invariant:

```text
One ticketId can mint one receipt only once.
```

That prevents double financing against the same off-chain document.

## 5. Manual price model

The current study deploy uses `MockPriceOracle`. Prices are admin-set and use 8 decimals.

This is intentional for testnet:

- the UI can test wheat, soy, sunflower or other tokenized commodities;
- the math is visible;
- the real oracle can be integrated later without changing the study flow.
