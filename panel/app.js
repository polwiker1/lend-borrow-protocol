const ids = [
  "lender",
  "borrower",
  "collateralToken",
  "borrowToken",
  "wheatAmount",
  "currentPrice",
  "decemberPrice",
  "marchPrice",
  "borrowAmount",
  "termMonths",
  "collateralFactor",
  "liquidationThreshold",
  "borrowRate",
  "reserveFactor",
  "liquidationBonus",
  "commodityName",
  "ticketTokenSymbol",
  "tokenUnit",
  "referenceUnit",
  "unitsPerToken",
  "usdcPrice",
  "maxAgeMinutes",
  "lastPriceAgeMinutes",
  "operationType",
  "operationAmount",
  "ticketWallet",
  "ticketKind",
  "ticketAmount",
  "ticketTermMonths",
  "secondaryTicketFactor",
  "sltCurrentDebt",
  "sltRequestedAmount",
  "sltApprovedAmount",
  "sltFactorPercent",
  "sltTermMonths",
  "conversionAsset",
  "marketDiscount",
  "truckCost",
  "secondaryMarket",
];

const $ = (id) => document.getElementById(id);

const money = new Intl.NumberFormat("es-AR", {
  style: "currency",
  currency: "USD",
  maximumFractionDigits: 2,
});

const number = new Intl.NumberFormat("es-AR", {
  maximumFractionDigits: 2,
});

function val(id) {
  const parsed = Number($(id).value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function activeModel() {
  return document.querySelector('input[name="modelType"]:checked').value;
}

function tokenPriceUsd(referencePrice, unitsPerToken) {
  return referencePrice * unitsPerToken;
}

function tokenPriceUsdc(referencePrice, unitsPerToken, usdcPrice) {
  if (usdcPrice <= 0) return 0;
  return tokenPriceUsd(referencePrice, unitsPerToken) / usdcPrice;
}

function referencePriceForTokenUsdc(tokenPrice, unitsPerToken, usdcPrice) {
  if (unitsPerToken <= 0) return 0;
  return (tokenPrice * usdcPrice) / unitsPerToken;
}

function healthFactor(collateralValue, liquidationThreshold, debtValue) {
  if (debtValue <= 0) return Infinity;
  return (collateralValue * (liquidationThreshold / 100)) / debtValue;
}

function labelForHealth(hf) {
  if (hf < 1) return "Liquidable";
  if (hf < 1.12) return "Riesgo alto";
  if (hf < 1.3) return "Riesgo medio";
  return "Saludable";
}

function scenarioForPrice(model, referencePrice, data) {
  const unitPrice = tokenPriceUsdc(referencePrice, data.unitsPerToken, data.usdcPrice);

  if (model === "productivo") {
    const collateralValue = data.wheatAmount * unitPrice;
    const debtValue = data.finalDebt;
    const hf = healthFactor(collateralValue, data.liquidationThreshold, debtValue);
    return { unitPrice, collateralValue, debtValue, hf };
  }

  const collateralValue = data.cashCollateral;
  const debtValue = data.finalDebtWTK * unitPrice;
  const hf = healthFactor(collateralValue, data.liquidationThreshold, debtValue);
  return { unitPrice, collateralValue, debtValue, hf };
}

function liquidationTokenPrice(model, data) {
  if (model === "productivo") {
    return data.finalDebt / (data.wheatAmount * (data.liquidationThreshold / 100));
  }

  return (data.cashCollateral * (data.liquidationThreshold / 100)) / data.finalDebtWTK;
}

function applyModelDefaults(model) {
  $("currentPrice").value = "216.82";
  $("decemberPrice").value = "224.87";
  $("marchPrice").value = "232.25";
  $("referenceUnit").value = "tonelada";
  $("unitsPerToken").value = "1";

  if (model === "productivo") {
    $("lender").value = "Molinos Rio Parana";
    $("borrower").value = "Cooperativa AFRA - Asociacion Federada de Recolectores Argentinos";
    $("collateralToken").value = "wTK - trigo tokenizado";
    $("borrowToken").value = "aUSD - liquidez estable";
    $("wheatAmount").value = "10000";
    $("borrowAmount").value = "40000";
    $("operationAmount").value = "40000";
    $("operationType").value = "borrow";
    $("ticketAmount").value = "10000";
    $("ticketKind").value = "primary";
    $("ticketTermMonths").value = "6";
    $("commodityName").value = "Trigo";
    $("ticketTokenSymbol").value = "wTK";
    $("tokenUnit").value = "tonelada";
    $("borrowAmountLabel").textContent = "Prestamo solicitado (aUSD)";
    return;
  }

  if (model === "ticket") {
    $("lender").value = "Molinos Rio Parana";
    $("borrower").value = "Operador Logistico Portuario del Parana";
    $("collateralToken").value = "Garantia documental / flujo logistico portuario";
    $("borrowToken").value = "aUSD o wTK - segun necesidad operativa";
    $("wheatAmount").value = "3000000";
    $("borrowAmount").value = "10000";
    $("operationAmount").value = "6500";
    $("operationType").value = "borrow";
    $("ticketWallet").value = "0xLogisticaPortuaria00000000000000000001";
    $("ticketAmount").value = "10000";
    $("ticketKind").value = "primary";
    $("ticketTermMonths").value = "6";
    $("conversionAsset").value = "USDT";
    $("marketDiscount").value = "2";
    $("truckCost").value = "85000";
    $("secondaryMarket").value = "Mesa tokenizada / pool estable auditado";
    $("commodityName").value = "Trigo";
    $("ticketTokenSymbol").value = "wTK";
    $("tokenUnit").value = "tonelada";
    $("borrowAmountLabel").textContent = "Prestamo solicitado";
    return;
  }

  $("lender").value = "Molinos Rio Parana";
  $("borrower").value = "Asociacion Transportistas Camiones Ltd";
  $("collateralToken").value = "aUSD - garantia estable";
  $("borrowToken").value = "wTK - trigo tokenizado";
  $("wheatAmount").value = "100000";
  $("borrowAmount").value = "100";
  $("operationAmount").value = "100";
  $("operationType").value = "borrow";
  $("ticketAmount").value = "100";
  $("ticketKind").value = "primary";
  $("ticketTermMonths").value = "6";
  $("commodityName").value = "Trigo";
  $("ticketTokenSymbol").value = "wTK";
  $("tokenUnit").value = "tonelada";
  $("borrowAmountLabel").textContent = "Prestamo solicitado";
}

function operationPreview(model, data) {
  const amount = model === "productivo" && data.operationType === "borrow" ? data.borrowAmount : data.operationAmount;
  const isProductive = model === "productivo";
  const isSecondaryBorrow = model === "ticket" && data.operationType === "borrow";

  if (data.oracleIsStale) {
    return {
      status: "Bloqueada",
      text: `La operacion queda bloqueada porque el precio tiene ${number.format(data.lastPriceAgeMinutes)} minutos y el max age permite ${number.format(data.maxAgeMinutes)} minutos.`,
    };
  }

  if (data.operationType === "supply") {
    const unit = isProductive ? "aUSD" : data.tokenSymbol;
    return {
      status: "Lista",
      text: `${data.lender} aportaria ${number.format(amount)} ${unit}. Esa liquidez queda disponible para borrowers y gana interes cuando haya deuda activa.`,
    };
  }

  if (data.operationType === "deposit") {
    const unit = isProductive ? data.tokenSymbol : "aUSD";
    return {
      status: "Lista",
      text: `${data.borrower} depositaria ${number.format(amount)} ${unit} como garantia. El protocolo recalcula el limite segun factor colateral y precio oracle.`,
    };
  }

  if (data.operationType === "borrow") {
    if (isSecondaryBorrow) {
      const secondaryFactor = clamp(data.secondaryTicketFactor, 0, 65);
      const secondaryLimitTokens = data.ticketAmount * (secondaryFactor / 100);
      const secondaryLimitValue = secondaryLimitTokens * data.currentTokenPrice;
      const requestedValue = amount * data.currentTokenPrice;
      const fits = amount <= secondaryLimitTokens;

      return {
        status: fits ? "Lista" : "Sobre limite",
        text: fits
          ? `${data.borrower} podria solicitar un SLT por ${number.format(amount)} ${data.tokenSymbol}. La base WRA secundaria declarada es ${number.format(data.ticketAmount)} ${data.tokenSymbol} y el limite aplicado es ${number.format(secondaryLimitTokens)} ${data.tokenSymbol} (${money.format(secondaryLimitValue)}).`
          : `El SLT supera el limite secundario: pide ${number.format(amount)} ${data.tokenSymbol} (${money.format(requestedValue)}) contra ${number.format(secondaryLimitTokens)} ${data.tokenSymbol} (${money.format(secondaryLimitValue)}) habilitados. La base WRA ya arrastra riesgo financiero y no deberia aceptarse al 100%.`,
      };
    }

    const requestedValue = isProductive ? amount : amount * data.currentTokenPrice;
    const fits = requestedValue <= data.maxBorrowValue;
    return {
      status: fits ? "Lista" : "Sobre limite",
      text: fits
        ? `${data.borrower} puede pedir ${isProductive ? money.format(amount) : `${number.format(amount)} ${data.tokenSymbol}`} porque el valor solicitado es ${money.format(requestedValue)} y el maximo prestable es ${money.format(data.maxBorrowValue)}.`
        : `La operacion supera el maximo prestable: pide ${money.format(requestedValue)} contra ${money.format(data.maxBorrowValue)} habilitados. Puede seguir saludable porque la liquidacion usa otro umbral mas alto.`,
    };
  }

  if (data.operationType === "repay") {
    return {
      status: "Lista",
      text: `${data.borrower} pagaria ${isProductive ? money.format(amount) : `${number.format(amount)} ${data.tokenSymbol}`}. Primero baja la deuda; si paga todo, el health factor vuelve a quedar sin deuda activa.`,
    };
  }

  const canLiquidate = data.hfNow < 1;
  return {
    status: canLiquidate ? "Ejecutable" : "No ejecutable",
    text: canLiquidate
      ? `El liquidador puede pagar deuda y tomar colateral con bonus de ${number.format(data.liquidationBonus)}%.`
      : `Todavia no se puede liquidar: el health factor es ${number.format(data.hfNow)} y debe caer por debajo de 1.`,
  };
}

function render() {
  const model = activeModel();
  const lender = $("lender").value.trim() || "Lender";
  const borrower = $("borrower").value.trim() || "Borrower";
  const wheatAmount = val("wheatAmount");
  const currentPrice = val("currentPrice");
  const decemberPrice = val("decemberPrice");
  const marchPrice = val("marchPrice");
  const borrowAmount = val("borrowAmount");
  const termMonths = val("termMonths");
  const collateralFactor = val("collateralFactor");
  const liquidationThreshold = val("liquidationThreshold");
  const borrowRate = val("borrowRate");
  const reserveFactor = val("reserveFactor");
  const liquidationBonus = clamp(val("liquidationBonus"), 5, 10);
  const commodityName = $("commodityName").value.trim() || "Commodity";
  const tokenSymbol = $("ticketTokenSymbol").value.trim() || "cTK";
  const tokenUnit = $("tokenUnit").value.trim() || "unidad";
  const referenceUnit = $("referenceUnit").value.trim() || "unidad mercado";
  const unitsPerToken = val("unitsPerToken");
  const usdcPrice = val("usdcPrice");
  const maxAgeMinutes = clamp(val("maxAgeMinutes"), 1, 1440);
  const lastPriceAgeMinutes = val("lastPriceAgeMinutes");
  const operationType = $("operationType").value;
  const operationAmount = val("operationAmount");
  const ticketWallet = $("ticketWallet").value.trim() || "0xTicketReceiver";
  const ticketKind = $("ticketKind").value;
  const ticketAmount = val("ticketAmount");
  const ticketTermMonths = val("ticketTermMonths");
  const secondaryTicketFactor = clamp(val("secondaryTicketFactor"), 0, 65);
  const conversionAsset = $("conversionAsset").value.trim() || "USDT";
  const marketDiscount = val("marketDiscount");
  const truckCost = val("truckCost");
  const secondaryMarket = $("secondaryMarket").value.trim() || "Mercado secundario tokenizado";
  const sltApprovedAmount = val("sltApprovedAmount");

  if (String(liquidationBonus) !== $("liquidationBonus").value && document.activeElement !== $("liquidationBonus")) {
    $("liquidationBonus").value = liquidationBonus;
  }

  const isProductive = model === "productivo";
  const currentTokenPrice = tokenPriceUsdc(currentPrice, unitsPerToken, usdcPrice);
  const collateralValue = isProductive ? wheatAmount * currentTokenPrice : wheatAmount;
  const maxBorrowValue = collateralValue * (collateralFactor / 100);
  const interest = borrowAmount * (borrowRate / 100) * (termMonths / 12);
  const finalDebt = borrowAmount + interest;
  const finalDebtValue = isProductive ? finalDebt : finalDebt * currentTokenPrice;
  const sltDebtValue = isProductive ? sltApprovedAmount : sltApprovedAmount;
  const totalDebtWithSltValue = finalDebtValue + sltDebtValue;
  const hfWithSlt = healthFactor(collateralValue, liquidationThreshold, totalDebtWithSltValue);
  const finalDebtWTK = isProductive ? 0 : finalDebt;
  const protocolReserve = interest * (reserveFactor / 100);
  const lenderYield = interest - protocolReserve;
  const data = {
    model,
    lender,
    borrower,
    wheatAmount,
    borrowAmount,
    cashCollateral: collateralValue,
    finalDebt,
    finalDebtWTK,
    liquidationThreshold,
    liquidationBonus,
    commodityName,
    tokenSymbol,
    tokenUnit,
    referenceUnit,
    unitsPerToken,
    usdcPrice,
    currentTokenPrice,
    maxBorrowValue,
    currentDebtValue: finalDebtValue,
    operationType,
    operationAmount,
    maxAgeMinutes,
    lastPriceAgeMinutes,
    oracleIsStale: lastPriceAgeMinutes > maxAgeMinutes,
    ticketWallet,
    ticketKind,
    ticketAmount,
    ticketTermMonths,
    secondaryTicketFactor,
    sltApprovedAmount,
    sltDebtValue,
    totalDebtWithSltValue,
    hfWithSlt,
    conversionAsset,
    marketDiscount,
    truckCost,
    secondaryMarket,
  };
  const hfNow = healthFactor(collateralValue, liquidationThreshold, finalDebtValue);
  data.hfNow = hfNow;
  const liqTokenPrice = liquidationTokenPrice(model, data);
  const liqReferencePrice = referencePriceForTokenUsdc(liqTokenPrice, unitsPerToken, usdcPrice);

  $("collateralValueLabel").textContent =
    model === "ticket"
      ? "Garantia documentada"
      : isProductive
        ? `Valor de ${commodityName.toLowerCase()} en garantia`
        : "Garantia estable";
  $("finalDebtLabel").textContent = isProductive
    ? "Deuda estimada al vencimiento"
    : `${tokenSymbol} adeudados al vencimiento`;
  $("collateralValue").textContent = money.format(collateralValue);
  $("maxBorrow").textContent = isProductive
    ? money.format(maxBorrowValue)
    : `${number.format(maxBorrowValue / currentTokenPrice)} ${tokenSymbol}`;
  $("finalDebt").textContent = isProductive
    ? money.format(finalDebt)
    : `${number.format(finalDebt)} ${tokenSymbol} (${money.format(finalDebtValue)})`;
  $("healthFactor").textContent = Number.isFinite(hfNow) ? number.format(hfNow) : "Sin deuda";
  $("primaryDebtView").textContent = money.format(finalDebtValue);
  $("sltDebtView").textContent = money.format(sltDebtValue);
  $("totalDebtWithSltView").textContent = money.format(totalDebtWithSltValue);
  $("totalDebtWithSltDetail").textContent =
    `HF post-SLT: ${Number.isFinite(hfWithSlt) ? number.format(hfWithSlt) : "Sin deuda"}. Esta lectura suma LTP primario + SLT.`;
  $("totalInterest").textContent = isProductive ? money.format(interest) : `${number.format(interest)} ${tokenSymbol}`;
  $("lenderYield").textContent = isProductive ? money.format(lenderYield) : `${number.format(lenderYield)} ${tokenSymbol}`;
  $("protocolReserve").textContent = isProductive
    ? money.format(protocolReserve)
    : `${number.format(protocolReserve)} ${tokenSymbol}`;
  $("currentPriceLabel").textContent = `Precio ${commodityName.toLowerCase()} actual (USD/${referenceUnit})`;
  $("decemberPriceLabel").textContent = `Precio ${commodityName.toLowerCase()} esperado a diciembre`;
  $("marchPriceLabel").textContent = `Precio ${commodityName.toLowerCase()} esperado a marzo`;
  $("wheatAmountLabel").textContent =
    model === "ticket"
      ? "Garantia documentada estimada (USD)"
      : isProductive
        ? `${commodityName} en garantia (${tokenUnit} / ${tokenSymbol})`
        : "Garantia estable depositada (aUSD)";
  $("borrowAmountLabel").textContent = isProductive
    ? "Prestamo solicitado (aUSD)"
    : `Prestamo solicitado (${tokenSymbol} / ${tokenUnit})`;
  $("ticketAmountLabel").textContent =
    ticketKind === "secondary"
      ? `${tokenSymbol} WRA base en mercado secundario`
      : `Cantidad documentada del activo (${tokenSymbol})`;
  $("tokenPriceLabel").textContent = `Precio 1 ${tokenSymbol}`;
  $("wTKPrice").textContent = `${money.format(currentTokenPrice)} / ${tokenUnit}`;
  $("tokenPriceDetail").textContent =
    `1 ${tokenSymbol} = 1 ${tokenUnit}; precio manual ${money.format(currentPrice)} / ${referenceUnit}; factor de conversion ${number.format(unitsPerToken)} ${referenceUnit} por token.`;
  $("priceHeader").textContent = `Precio ${commodityName.toLowerCase()}`;
  $("ticketTokenLabel").textContent = `Activo documentado (${tokenSymbol})`;

  const status = labelForHealth(hfNow);
  $("estadoPrestamo").textContent = status;
  $("estadoDetalle").textContent =
    status === "Liquidable"
      ? `${borrower} quedo por debajo del umbral de liquidacion.`
      : `${borrower} puede operar con ${lender}, manteniendo el riesgo visible.`;

  const box = document.querySelector(".status-box");
  box.classList.toggle("danger", status === "Liquidable");
  box.classList.toggle("risk", status === "Riesgo alto" || status === "Riesgo medio");

  const oracleIsStale = lastPriceAgeMinutes > maxAgeMinutes;
  $("oracleStatus").textContent = oracleIsStale ? "Precio viejo" : "Vigente";
  $("oracleDetail").textContent = oracleIsStale
    ? `El contrato revertiria: ${number.format(lastPriceAgeMinutes)} min supera maxAge ${number.format(maxAgeMinutes)} min.`
    : `Dato valido: ${number.format(lastPriceAgeMinutes)} min dentro de maxAge ${number.format(maxAgeMinutes)} min.`;

  const scenarios = [
    ["Hoy", currentPrice],
    ["Diciembre", decemberPrice],
    ["Marzo", marchPrice],
    ["Crash -10%", currentPrice * 0.9],
    ["Liquidacion", liqReferencePrice],
  ];

  $("scenarioRows").innerHTML = scenarios
    .map(([name, price]) => {
      const scenario = scenarioForPrice(model, price, data);
      const label = labelForHealth(scenario.hf);
      return `
        <tr>
          <td>${name}</td>
          <td>${money.format(price)} / ${referenceUnit}<br><small>${money.format(scenario.unitPrice)} / ${tokenUnit} ${tokenSymbol}</small></td>
          <td>${money.format(scenario.collateralValue)}</td>
          <td>${Number.isFinite(scenario.hf) ? number.format(scenario.hf) : "Sin deuda"}</td>
          <td>${label}</td>
        </tr>
      `;
    })
    .join("");

  const risk = $("riskCallout");
  risk.classList.toggle("danger", hfNow < 1);
  risk.classList.toggle("warning", hfNow >= 1 && hfNow < 1.3);

  const direction = isProductive ? "cae cerca de" : "sube cerca de";
  const collateralWord = isProductive ? `tomar ${tokenSymbol}` : "tomar garantia aUSD";
  $("liquidationText").textContent =
    `Si ${commodityName.toLowerCase()} ${direction} ${money.format(liqReferencePrice)} por ${referenceUnit} (${money.format(liqTokenPrice)} por ${tokenUnit}), ` +
    `un liquidador podria pagar parte de la deuda de ${borrower} y ${collateralWord} con un bonus del ${number.format(liquidationBonus)}%. ` +
    `El objetivo es proteger la liquidez aportada por ${lender}.`;

  const operation = operationPreview(model, data);
  $("operationStatus").textContent = operation.status;
  $("operationDetail").textContent = operationLabelsForDetail(operation.status);
  $("operationText").textContent = operation.text;
  renderDebtRiskLesson(model, data);
  renderTicket(data);
}

function operationLabelsForDetail(status) {
  if (status === "Bloqueada") return "El oracle impide ejecutar.";
  if (status === "Sobre limite") return "No se aprobaria nueva deuda, aunque aun no sea liquidable.";
  if (status === "Ejecutable") return "La posicion ya es liquidable.";
  if (status === "No ejecutable") return "La posicion sigue saludable.";
  return "La operacion no rompe el limite actual.";
}

function renderDebtRiskLesson(model, data) {
  if (model === "productivo") {
    $("debtRiskText").textContent =
      `${data.borrower} deja ${data.commodityName.toLowerCase()} como garantia y toma deuda estable. Si ${data.commodityName.toLowerCase()} baja, cae el valor del colateral y se acerca la liquidacion. ` +
      `Si ${data.commodityName.toLowerCase()} sube, mejora su margen porque la garantia vale mas contra una deuda que no cambia tanto en dolares.`;
    return;
  }

  const debtNow = data.finalDebtWTK * data.currentTokenPrice;
  const debtUp = debtNow * 1.1;
  const debtDown = debtNow * 0.9;

  $("debtRiskText").textContent =
    `${data.borrower} recibe ${number.format(data.borrowAmount)} ${data.tokenSymbol} y al vencimiento debe devolver ${number.format(data.finalDebtWTK)} ${data.tokenSymbol} con interes. ` +
    `Si ${data.commodityName.toLowerCase()} sube 10%, la deuda medida en estable sube de ${money.format(debtNow)} a ${money.format(debtUp)}. ` +
    `Si ${data.commodityName.toLowerCase()} baja 10%, la deuda medida en estable baja a ${money.format(debtDown)}. ` +
    `Liquidacion y nueva toma son controles distintos: puede no ser liquidable, pero igual quedar bloqueado para emitir mas deuda.`;
}

function shortWallet(wallet) {
  if (wallet.length <= 14) return wallet;
  return `${wallet.slice(0, 8)}...${wallet.slice(-6)}`;
}

function ticketIdFor(data) {
  const prefix = data.ticketKind === "secondary" ? "SLT" : "LTP";
  const emittedAmount = ticketDocumentedAmount(data);
  const base = `${prefix}-${data.borrower}-${emittedAmount}-${data.ticketTermMonths}-${data.ticketWallet}`;
  let hash = 0;

  for (let i = 0; i < base.length; i++) {
    hash = (hash * 31 + base.charCodeAt(i)) % 100000;
  }

  return `${prefix}-${String(hash).padStart(5, "0")}`;
}

function ticketDocumentedAmount(data) {
  if (data.ticketKind === "secondary") return data.operationAmount;
  if (data.model === "productivo") return data.wheatAmount;
  return data.ticketAmount;
}

function renderTicket(data) {
  const discount = clamp(data.marketDiscount, 0, 30);
  const emittedAmount = ticketDocumentedAmount(data);
  const ticketNotional = emittedAmount * data.currentTokenPrice;
  const stableValue = ticketNotional * (1 - discount / 100);
  const truckUnits = data.truckCost > 0 ? stableValue / data.truckCost : 0;
  const ticketId = ticketIdFor(data);
  const ticketKindLabel = data.ticketKind === "secondary" ? "ticket secundario SLT" : "ticket primario LTP";
  const truckText =
    data.truckCost > 0
      ? ` A modo de ejemplo, eso equivale a ${number.format(truckUnits)} unidad(es) logisticas de ${money.format(data.truckCost)} cada una.`
      : "";

  $("ticketId").textContent = ticketId;
  $("ticketTerm").textContent = `Plazo ${number.format(data.ticketTermMonths)} meses`;
  $("ticketReceiver").textContent = data.borrower;
  $("ticketWtk").textContent = `${number.format(emittedAmount)} ${data.tokenSymbol}`;
  $("ticketNotional").textContent = money.format(ticketNotional);
  $("ticketStable").textContent = `${money.format(stableValue)} en ${data.conversionAsset}`;
  $("ticketText").textContent =
    `${data.lender} emite para ${data.borrower} un ${ticketKindLabel} que documenta ${number.format(emittedAmount)} ${data.tokenSymbol} ` +
    `en la cartera ${shortWallet(data.ticketWallet)}. Con el precio oracle actual, el valor nocional es ${money.format(ticketNotional)}. ` +
    `Si ese ticket se negocia en ${data.secondaryMarket} con un descuento del ${number.format(discount)}%, ` +
    `la salida estimada seria ${money.format(stableValue)} en ${data.conversionAsset}.` +
    truckText +
    (data.ticketKind === "secondary"
      ? ` Este SLT pertenece al mercado secundario WRA: no reutiliza el agTICKET bloqueado del LTP, sino que aplica haircut sobre tokens ${data.tokenSymbol} que ya arrastran riesgo financiero.`
      : "");
}

ids.forEach((id) => {
  $(id).addEventListener("input", render);
  $(id).addEventListener("change", render);
});
document.querySelectorAll('input[name="modelType"]').forEach((input) => {
  input.addEventListener("change", () => {
    applyModelDefaults(activeModel());
    render();
  });
});
render();
