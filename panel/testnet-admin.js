const TICKET_ABI = [
  "function createTicket(address borrower,address asset,uint256 assetAmount,uint256 notionalUsd,uint256 maturity,uint256 advanceRateBps,bytes32 documentHash,string documentURI) returns (uint256)",
  "function issueTicket(uint256 ticketId,address to)",
  "function setApprovalForAll(address operator,bool approved)",
  "function safeTransferFrom(address from,address to,uint256 id,uint256 value,bytes data)",
  "function nextTicketId() view returns (uint256)",
];

const VAULT_ABI = [
  "function lockTicket(uint256 ticketId)",
  "function approve(address spender,uint256 amount) returns (bool)",
  "function RECEIPT_UNIT() view returns (uint256)",
];

const LENDING_ABI = [
  "function depositCollateral(address token,uint256 amount)",
  "function supplyLiquidity(address token,uint256 amount)",
  "function borrow(address token,uint256 amount)",
  "function borrowTo(address token,uint256 amount,address recipient)",
  "function pause()",
  "function unpause()",
  "function getMaxBorrowableTokenAmount(address user,address borrowToken) view returns (uint256)",
  "function availableLiquidity(address token) view returns (uint256)",
];

const SLT_ABI = [
  "function requestSLT(uint256 ltpTicketId,address recipient,uint256 requestedAmountUsd,uint256 currentDebtUsd,uint256 sltFactorBps,uint256 maturity,bytes32 documentHash,string documentURI) returns (uint256)",
  "function approveSLT(uint256 sltId,uint256 approvedAmountUsd)",
  "function markFunded(uint256 sltId)",
  "function nextSLTId() view returns (uint256)",
  "function getSLT(uint256 sltId) view returns (tuple(uint256 ltpTicketId,address primaryBorrower,address recipient,uint256 requestedAmountUsd,uint256 approvedAmountUsd,uint256 currentDebtUsdSnapshot,uint256 maxSLTAmountUsd,uint256 sltFactorBps,uint256 requestedAt,uint256 approvedAt,uint256 maturity,bytes32 documentHash,string documentURI,uint8 status))",
];

const ERC20_ABI = [
  "function mint(address to,uint256 amount)",
  "function approve(address spender,uint256 amount) returns (bool)",
  "function balanceOf(address account) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
];

let testnetProvider;
let testnetSigner;
let currentTicketId;
let currentSltId;
let currentChainId;

const testnetStatus = (message) => {
  const node = document.getElementById("testnetStatus");
  if (node) node.textContent = message;
};

const inputValue = (id) => document.getElementById(id).value.trim();
const numericValue = (id) => Number(document.getElementById(id).value || 0);

function explorerTxUrl(hash) {
  if (currentChainId === 421614n) return `https://sepolia.arbiscan.io/tx/${hash}`;
  return `https://sepolia.arbiscan.io/tx/${hash}`;
}

async function signerAddress() {
  if (!testnetSigner) return "wallet no conectada";
  return testnetSigner.getAddress();
}

function shortAddress(address) {
  if (!address || address.length < 12) return address;
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

function markLifecycle(step, details) {
  const node = document.querySelector(`[data-step="${step}"]`);
  if (!node) return;

  node.classList.add("done");
  const small = node.querySelector("small");
  if (!small) return;

  const txPart = details.txHash
    ? ` <a href="${explorerTxUrl(details.txHash)}" target="_blank" rel="noreferrer">${details.txHash.slice(0, 10)}...</a>`
    : "";
  small.innerHTML = `${details.text}${txPart}`;
}

function isLifecycleDone(step) {
  const node = document.querySelector(`[data-step="${step}"]`);
  return Boolean(node && node.classList.contains("done"));
}

function requireEthers() {
  if (!window.ethers) throw new Error("ethers no esta cargado. Revisa conexion a internet.");
  if (!window.ethereum) throw new Error("No se encontro wallet EIP-1193. Instala MetaMask o compatible.");
}

function parseUnits18(value) {
  return window.ethers.parseUnits(String(value), 18);
}

function formatUnits18(value) {
  return window.ethers.formatUnits(value, 18);
}

function percentToBps(value) {
  return Math.round(Number(value || 0) * 100);
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
  currentChainId = network.chainId;
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
  const ticketKind = inputValue("ticketKind");
  const modelInput = document.querySelector('input[name="modelType"]:checked');
  const model = modelInput ? modelInput.value : "productivo";
  const ticketAmount =
    ticketKind === "secondary"
      ? numericValue("operationAmount")
      : model === "productivo"
        ? numericValue("wheatAmount")
        : numericValue("ticketAmount");
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
  markLifecycle("create", {
    text: `Ticket ID ${currentTicketId.toString()} creado por ${shortAddress(await signerAddress())}.`,
    txHash: tx.hash,
  });
}

async function issueTicketOnchain() {
  const ticket = contractAt(inputValue("ticketContractAddress"), TICKET_ABI);
  const ticketId = currentTicketId || BigInt(inputValue("manualTicketId") || 0);
  if (!ticketId) throw new Error("Primero crea un ticket.");

  testnetStatus(`Emitiendo ticket ${ticketId.toString()}...`);
  const tx = await ticket.issueTicket(ticketId, inputValue("ticketWallet"));
  await tx.wait();
  testnetStatus(`Ticket emitido. Tx ${tx.hash}`);
  markLifecycle("issue", {
    text: `Ticket ID ${ticketId.toString()} emitido a ${shortAddress(inputValue("ticketWallet"))}.`,
    txHash: tx.hash,
  });
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
  markLifecycle("lock", {
    text: `Ticket ID ${ticketId.toString()} bloqueado por ${shortAddress(await signerAddress())}; vault emitio 1 agTICKET.`,
    txHash: lockTx.hash,
  });
}

async function transferTicketOnchain() {
  const ticket = contractAt(inputValue("ticketContractAddress"), TICKET_ABI);
  const ticketId = currentTicketId || BigInt(inputValue("manualTicketId") || 0);
  const to = inputValue("ticketTransferTo");
  const from = await signerAddress();

  if (!ticketId) throw new Error("Carga el Ticket ID antes de transferir.");
  if (!window.ethers.isAddress(to)) throw new Error("Wallet destino invalida.");

  testnetStatus(`Transfiriendo LTP ${ticketId.toString()} a ${to}...`);
  const tx = await ticket.safeTransferFrom(from, to, ticketId, 1, "0x");
  await tx.wait();
  testnetStatus(`LTP transferido. Tx ${tx.hash}`);
  markLifecycle("lock", {
    text: `Ticket ID ${ticketId.toString()} transferido de ${shortAddress(from)} a ${shortAddress(to)}.`,
    txHash: tx.hash,
  });
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
  markLifecycle("deposit", {
    text: `${shortAddress(await signerAddress())} deposito 1 agTICKET como colateral en LendingProtocol.`,
    txHash: depositTx.hash,
  });
}

async function fundAUsdLiquidityOnchain() {
  const lending = contractAt(inputValue("lendingContractAddress"), LENDING_ABI);
  const borrowToken = contractAt(inputValue("borrowTokenAddress"), ERC20_ABI);
  const signer = await testnetSigner.getAddress();
  const amount = parseUnits18(numericValue("liquidityAmount"));
  const symbol = await borrowToken.symbol();

  testnetStatus(`Minteando token prestado de prueba para ${signer}...`);
  const mintTx = await borrowToken.mint(signer, amount);
  await mintTx.wait();

  testnetStatus(`Aprobando ${symbol} para LendingProtocol...`);
  const approveTx = await borrowToken.approve(inputValue("lendingContractAddress"), amount);
  await approveTx.wait();

  testnetStatus("Fondeando liquidez del token prestado en LendingProtocol...");
  const supplyTx = await lending.supplyLiquidity(inputValue("borrowTokenAddress"), amount);
  await supplyTx.wait();
  testnetStatus(`Liquidez del token prestado fondeada. Tx ${supplyTx.hash}`);
  markLifecycle("fund", {
    text: `${shortAddress(await signerAddress())} fondeo ${numericValue("liquidityAmount")} ${symbol} como liquidez.`,
    txHash: supplyTx.hash,
  });
}

async function borrowAUsdOnchain() {
  const lending = contractAt(inputValue("lendingContractAddress"), LENDING_ABI);
  const borrowToken = contractAt(inputValue("borrowTokenAddress"), ERC20_ABI);
  const borrower = await testnetSigner.getAddress();
  const borrowTokenAddress = inputValue("borrowTokenAddress");
  const amount = parseUnits18(numericValue("borrowAUsdAmount"));
  const symbol = await borrowToken.symbol();
  const maxBorrow = await lending.getMaxBorrowableTokenAmount(borrower, borrowTokenAddress);
  const available = await lending.availableLiquidity(borrowTokenAddress);

  if (amount > maxBorrow) {
    throw new Error(`Monto sobre limite. Maximo para esta wallet: ${formatUnits18(maxBorrow)} ${symbol}.`);
  }

  if (amount > available) {
    throw new Error(`No hay liquidez suficiente. Disponible: ${formatUnits18(available)} ${symbol}.`);
  }

  if (!isLifecycleDone("fund")) {
    markLifecycle("fund", {
      text: `Liquidez ${symbol} ya disponible antes del prestamo: ${formatUnits18(available)} ${symbol}.`,
    });
  }

  testnetStatus(`Pidiendo ${numericValue("borrowAUsdAmount")} ${symbol} contra agTICKET depositado...`);
  const borrowTx = await lending.borrow(borrowTokenAddress, amount);
  await borrowTx.wait();
  testnetStatus(`Prestamo ${symbol} recibido. Tx ${borrowTx.hash}`);
  markLifecycle("borrow", {
    text: `${shortAddress(await signerAddress())} recibio ${numericValue("borrowAUsdAmount")} ${symbol}.`,
    txHash: borrowTx.hash,
  });
}

async function requestSltOnchain() {
  const slt = contractAt(inputValue("sltContractAddress"), SLT_ABI);
  const ltpTicketId = BigInt(inputValue("sltLtpTicketId") || inputValue("manualTicketId") || 0);
  const recipient = inputValue("sltRecipientWallet");
  const requestedAmount = parseUnits18(numericValue("sltRequestedAmount"));
  const currentDebt = parseUnits18(numericValue("sltCurrentDebt"));
  const sltFactorBps = percentToBps(inputValue("sltFactorPercent"));
  const maturity = Math.floor(Date.now() / 1000) + Math.floor(numericValue("sltTermMonths") * 30 * daysInSeconds());
  const documentText = inputValue("sltDocumentReference") || inputValue("documentReference") || "slt-document";
  const documentHash = await sha256Bytes32(documentText);
  const documentURI = `manual://${encodeURIComponent(documentText)}`;

  if (!ltpTicketId) throw new Error("Carga el LTP base para solicitar SLT.");
  if (!window.ethers.isAddress(recipient)) throw new Error("Wallet 3 invalida.");
  if (requestedAmount <= 0n) throw new Error("Monto SLT invalido.");
  if (sltFactorBps <= 0 || sltFactorBps > 10_000) throw new Error("Factor SLT invalido.");

  const nextSltId = await slt.nextSLTId();
  testnetStatus(`Solicitando SLT ${nextSltId.toString()} sobre LTP ${ltpTicketId.toString()}...`);
  const tx = await slt.requestSLT(
    ltpTicketId,
    recipient,
    requestedAmount,
    currentDebt,
    sltFactorBps,
    maturity,
    documentHash,
    documentURI,
  );
  await tx.wait();

  currentSltId = nextSltId;
  document.getElementById("manualSltId").value = currentSltId.toString();
  testnetStatus(`SLT solicitado: ${currentSltId.toString()}. Tx ${tx.hash}`);
  markLifecycle("sltRequest", {
    text: `Borrower solicito SLT ${currentSltId.toString()} por ${numericValue("sltRequestedAmount")} aUSD para ${shortAddress(recipient)}.`,
    txHash: tx.hash,
  });
}

async function approveSltOnchain() {
  const slt = contractAt(inputValue("sltContractAddress"), SLT_ABI);
  const sltId = currentSltId || BigInt(inputValue("manualSltId") || 0);
  const approvedAmount = parseUnits18(numericValue("sltApprovedAmount") || numericValue("sltRequestedAmount"));

  if (!sltId) throw new Error("Carga el SLT ID para aprobar.");
  if (approvedAmount <= 0n) throw new Error("Monto aprobado invalido.");

  testnetStatus(`Aprobando SLT ${sltId.toString()}...`);
  const tx = await slt.approveSLT(sltId, approvedAmount);
  await tx.wait();
  testnetStatus(`SLT aprobado. Tx ${tx.hash}`);
  markLifecycle("sltApprove", {
    text: `Admin aprobo SLT ${sltId.toString()} por ${numericValue("sltApprovedAmount") || numericValue("sltRequestedAmount")} aUSD.`,
    txHash: tx.hash,
  });
}

async function executeSltOnchain() {
  const lending = contractAt(inputValue("lendingContractAddress"), LENDING_ABI);
  const slt = contractAt(inputValue("sltContractAddress"), SLT_ABI);
  const borrowToken = contractAt(inputValue("borrowTokenAddress"), ERC20_ABI);
  const sltId = currentSltId || BigInt(inputValue("manualSltId") || 0);
  const recipient = inputValue("sltRecipientWallet");
  const borrowTokenAddress = inputValue("borrowTokenAddress");
  const amount = parseUnits18(numericValue("sltApprovedAmount") || numericValue("sltRequestedAmount"));
  const borrower = await signerAddress();
  const symbol = await borrowToken.symbol();
  const maxBorrow = await lending.getMaxBorrowableTokenAmount(borrower, borrowTokenAddress);
  const available = await lending.availableLiquidity(borrowTokenAddress);

  if (!sltId) throw new Error("Carga el SLT ID para ejecutar.");
  if (!window.ethers.isAddress(recipient)) throw new Error("Wallet 3 invalida.");
  if (amount > maxBorrow) {
    throw new Error(`Monto sobre limite del borrower. Maximo visible: ${formatUnits18(maxBorrow)} ${symbol}.`);
  }
  if (amount > available) {
    throw new Error(`No hay liquidez suficiente. Disponible: ${formatUnits18(available)} ${symbol}.`);
  }

  testnetStatus(`Enviando ${formatUnits18(amount)} ${symbol} a wallet 3...`);
  const borrowTx = await lending.borrowTo(borrowTokenAddress, amount, recipient);
  await borrowTx.wait();

  testnetStatus(`Marcando SLT ${sltId.toString()} como fondeado...`);
  const fundedTx = await slt.markFunded(sltId);
  await fundedTx.wait();

  testnetStatus(`SLT ejecutado. borrowTo ${borrowTx.hash} | markFunded ${fundedTx.hash}`);
  markLifecycle("sltExecute", {
    text: `Borrower ejecuto SLT ${sltId.toString()}; wallet 3 recibio ${formatUnits18(amount)} ${symbol}.`,
    txHash: borrowTx.hash,
  });
}

async function pauseProtocolOnchain() {
  const lending = contractAt(inputValue("lendingContractAddress"), LENDING_ABI);
  testnetStatus("Pausando LendingProtocol como fusible operativo...");
  const tx = await lending.pause();
  await tx.wait();
  testnetStatus(`Lending pausado. Tx ${tx.hash}`);
}

async function unpauseProtocolOnchain() {
  const lending = contractAt(inputValue("lendingContractAddress"), LENDING_ABI);
  testnetStatus("Reactivando LendingProtocol...");
  const tx = await lending.unpause();
  await tx.wait();
  testnetStatus(`Lending reactivado. Tx ${tx.hash}`);
}

function bindRoleTabs() {
  document.querySelectorAll("[data-role-tab]").forEach((tab) => {
    tab.addEventListener("click", () => {
      const role = tab.dataset.roleTab;
      document.querySelectorAll("[data-role-tab]").forEach((item) => {
        item.classList.toggle("active", item.dataset.roleTab === role);
      });
      document.querySelectorAll("[data-role-panel]").forEach((panel) => {
        panel.classList.toggle("active", panel.dataset.rolePanel === role);
      });
    });
  });
}

function bindGuide() {
  const modal = document.getElementById("guideModal");
  const open = document.getElementById("openGuide");
  if (!modal || !open) return;

  const setOpen = (isOpen) => {
    modal.classList.toggle("open", isOpen);
    modal.setAttribute("aria-hidden", String(!isOpen));
    document.body.classList.toggle("modal-open", isOpen);
  };

  open.addEventListener("click", () => setOpen(true));
  modal.querySelectorAll("[data-guide-close]").forEach((item) => {
    item.addEventListener("click", () => setOpen(false));
  });

  modal.querySelectorAll("[data-guide-tab]").forEach((tab) => {
    tab.addEventListener("click", () => {
      const key = tab.dataset.guideTab;
      modal.querySelectorAll("[data-guide-tab]").forEach((item) => {
        item.classList.toggle("active", item.dataset.guideTab === key);
      });
      modal.querySelectorAll("[data-guide-panel]").forEach((panel) => {
        panel.classList.toggle("active", panel.dataset.guidePanel === key);
      });
    });
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") setOpen(false);
  });
}

async function copyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    await navigator.clipboard.writeText(text);
    return;
  }

  const area = document.createElement("textarea");
  area.value = text;
  area.setAttribute("readonly", "");
  area.style.position = "fixed";
  area.style.opacity = "0";
  document.body.appendChild(area);
  area.select();
  document.execCommand("copy");
  document.body.removeChild(area);
}

function bindCopyButtons() {
  const status = document.getElementById("copyStatus");
  document.querySelectorAll("[data-copy-address]").forEach((button) => {
    button.addEventListener("click", async () => {
      const address = button.dataset.copyAddress;
      try {
        await copyText(address);
        if (status) status.textContent = `Copiado: ${address}`;
      } catch (error) {
        if (status) status.textContent = `No se pudo copiar. Direccion: ${address}`;
      }
    });
  });
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

bindRoleTabs();
bindGuide();
bindCopyButtons();
bindTestnetButton("connectWalletAdmin", connectWallet);
bindTestnetButton("connectWalletBorrower", connectWallet);
bindTestnetButton("connectWalletAuditor", connectWallet);
bindTestnetButton("createTicketOnchain", createTicketOnchain);
bindTestnetButton("issueTicketOnchain", issueTicketOnchain);
bindTestnetButton("transferTicketOnchain", transferTicketOnchain);
bindTestnetButton("lockTicketOnchain", lockTicketOnchain);
bindTestnetButton("depositReceiptOnchain", depositReceiptOnchain);
bindTestnetButton("fundAUsdLiquidityOnchain", fundAUsdLiquidityOnchain);
bindTestnetButton("borrowAUsdOnchain", borrowAUsdOnchain);
bindTestnetButton("requestSltOnchain", requestSltOnchain);
bindTestnetButton("approveSltOnchain", approveSltOnchain);
bindTestnetButton("executeSltOnchain", executeSltOnchain);
bindTestnetButton("pauseProtocolOnchain", pauseProtocolOnchain);
bindTestnetButton("unpauseProtocolOnchain", unpauseProtocolOnchain);
