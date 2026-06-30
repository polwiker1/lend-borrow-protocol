const TICKET_ABI = [
  "function createTicket(address borrower,address asset,uint256 assetAmount,uint256 notionalUsd,uint256 maturity,uint256 advanceRateBps,bytes32 documentHash,string documentURI) returns (uint256)",
  "function issueTicket(uint256 ticketId,address to)",
  "function setApprovalForAll(address operator,bool approved)",
  "function nextTicketId() view returns (uint256)",
];

const VAULT_ABI = [
  "function lockTicket(uint256 ticketId)",
  "function approve(address spender,uint256 amount) returns (bool)",
  "function RECEIPT_UNIT() view returns (uint256)",
];

const LENDING_ABI = ["function depositCollateral(address token,uint256 amount)"];

let testnetProvider;
let testnetSigner;
let currentTicketId;

const testnetStatus = (message) => {
  const node = document.getElementById("testnetStatus");
  if (node) node.textContent = message;
};

const inputValue = (id) => document.getElementById(id).value.trim();
const numericValue = (id) => Number(document.getElementById(id).value || 0);

function requireEthers() {
  if (!window.ethers) throw new Error("ethers no esta cargado. Revisa conexion a internet.");
  if (!window.ethereum) throw new Error("No se encontro wallet EIP-1193. Instala MetaMask o compatible.");
}

function parseUnits18(value) {
  return window.ethers.parseUnits(String(value), 18);
}

async function sha256Bytes32(text) {
  const data = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return `0x${Array.from(new Uint8Array(hash)).map((byte) => byte.toString(16).padStart(2, "0")).join("")}`;
}

async function connectWallet() {
  requireEthers();
  testnetProvider = new window.ethers.BrowserProvider(window.ethereum);
  await testnetProvider.send("eth_requestAccounts", []);
  testnetSigner = await testnetProvider.getSigner();
  const network = await testnetProvider.getNetwork();
  testnetStatus(`Wallet conectada: ${await testnetSigner.getAddress()} | chainId ${network.chainId}`);
}

function contractAt(address, abi) {
  if (!testnetSigner) throw new Error("Conecta la wallet primero.");
  if (!window.ethers.isAddress(address)) throw new Error(`Direccion invalida: ${address}`);
  return new window.ethers.Contract(address, abi, testnetSigner);
}

async function createTicketOnchain() {
  const ticket = contractAt(inputValue("ticketContractAddress"), TICKET_ABI);
  const borrower = inputValue("ticketWallet");
  const asset = inputValue("assetContractAddress");
  const ticketAmount = numericValue("ticketAmount");
  const currentPrice = numericValue("currentPrice");
  const unitsPerToken = numericValue("unitsPerToken");
  const usdcPrice = numericValue("usdcPrice") || 1;
  const notional = ticketAmount * currentPrice * unitsPerToken / usdcPrice;
  const maturity = Math.floor(Date.now() / 1000) + Math.floor(numericValue("ticketTermMonths") * 30 * daysInSeconds());
  const documentText = inputValue("documentReference") || "ticket-document";
  const documentHash = await sha256Bytes32(documentText);
  const documentURI = `manual://${encodeURIComponent(documentText)}`;

  const nextTicketId = await ticket.nextTicketId();
  testnetStatus(`Creando ticket ${nextTicketId.toString()}...`);
  const tx = await ticket.createTicket(
    borrower,
    asset,
    parseUnits18(ticketAmount),
    parseUnits18(notional.toFixed(6)),
    maturity,
    6500,
    documentHash,
    documentURI,
  );
  await tx.wait();
  currentTicketId = nextTicketId;
  document.getElementById("manualTicketId").value = currentTicketId.toString();
  testnetStatus(`Ticket creado: ${currentTicketId.toString()}. Tx ${tx.hash}`);
}

async function issueTicketOnchain() {
  const ticket = contractAt(inputValue("ticketContractAddress"), TICKET_ABI);
  const ticketId = currentTicketId || BigInt(inputValue("manualTicketId") || 0);
  if (!ticketId) throw new Error("Primero crea un ticket.");

  testnetStatus(`Emitiendo ticket ${ticketId.toString()}...`);
  const tx = await ticket.issueTicket(ticketId, inputValue("ticketWallet"));
  await tx.wait();
  testnetStatus(`Ticket emitido. Tx ${tx.hash}`);
}

async function lockTicketOnchain() {
  const ticket = contractAt(inputValue("ticketContractAddress"), TICKET_ABI);
  const vault = contractAt(inputValue("vaultContractAddress"), VAULT_ABI);
  const ticketId = currentTicketId || BigInt(inputValue("manualTicketId") || 0);
  if (!ticketId) throw new Error("Primero crea o carga un ticket.");

  testnetStatus("Aprobando vault para custodiar ERC1155...");
  const approveTx = await ticket.setApprovalForAll(inputValue("vaultContractAddress"), true);
  await approveTx.wait();

  testnetStatus(`Bloqueando ticket ${ticketId.toString()} en vault...`);
  const lockTx = await vault.lockTicket(ticketId);
  await lockTx.wait();
  testnetStatus(`Ticket bloqueado y receipt emitido. Tx ${lockTx.hash}`);
}

async function depositReceiptOnchain() {
  const vault = contractAt(inputValue("vaultContractAddress"), VAULT_ABI);
  const lending = contractAt(inputValue("lendingContractAddress"), LENDING_ABI);
  const receiptUnit = await vault.RECEIPT_UNIT();

  testnetStatus("Aprobando receipt para lending...");
  const approveTx = await vault.approve(inputValue("lendingContractAddress"), receiptUnit);
  await approveTx.wait();

  testnetStatus("Depositando agTICKET como colateral...");
  const depositTx = await lending.depositCollateral(inputValue("vaultContractAddress"), receiptUnit);
  await depositTx.wait();
  testnetStatus(`Receipt depositado en lending. Tx ${depositTx.hash}`);
}

function daysInSeconds() {
  return 24 * 60 * 60;
}

function bindTestnetButton(id, handler) {
  const button = document.getElementById(id);
  if (!button) return;
  button.addEventListener("click", async () => {
    try {
      button.disabled = true;
      await handler();
    } catch (error) {
      testnetStatus(error.message || String(error));
    } finally {
      button.disabled = false;
    }
  });
}

bindTestnetButton("connectWallet", connectWallet);
bindTestnetButton("createTicketOnchain", createTicketOnchain);
bindTestnetButton("issueTicketOnchain", issueTicketOnchain);
bindTestnetButton("lockTicketOnchain", lockTicketOnchain);
bindTestnetButton("depositReceiptOnchain", depositReceiptOnchain);
