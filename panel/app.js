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

function activeModel() {
  return document.querySelector('input[name="modelType"]:checked').value;
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

function scenarioForPrice(model, price, data) {
  if (model === "productivo") {
    const collateralValue = data.wheatAmount * price;
    const debtValue = data.finalDebt;
    const hf = healthFactor(collateralValue, data.liquidationThreshold, debtValue);
    return { collateralValue, debtValue, hf };
  }

  const collateralValue = data.cashCollateral;
  const debtValue = data.finalDebtWTK * price;
  const hf = healthFactor(collateralValue, data.liquidationThreshold, debtValue);
  return { collateralValue, debtValue, hf };
}

function liquidationPrice(model, data) {
  if (model === "productivo") {
    return data.finalDebt / (data.wheatAmount * (data.liquidationThreshold / 100));
  }

  return (data.cashCollateral * (data.liquidationThreshold / 100)) / data.finalDebtWTK;
}

function applyModelDefaults(model) {
  if (model === "productivo") {
    $("lender").value = "Molinos Rio Parana";
    $("borrower").value = "Cooperativa AFRA - Asociacion Federada de Recolectores Argentinos";
    $("collateralToken").value = "wTK - trigo tokenizado";
    $("borrowToken").value = "aUSD - liquidez estable";
    $("wheatAmount").value = "10000";
    $("borrowAmount").value = "40000";
    $("wheatAmountLabel").textContent = "Trigo en garantia (bushels / wTK)";
    $("borrowAmountLabel").textContent = "Prestamo solicitado (aUSD)";
    return;
  }

  $("lender").value = "Molinos Rio Parana";
  $("borrower").value = "Asociacion Transportistas Camiones Ltd";
  $("collateralToken").value = "aUSD - garantia estable";
  $("borrowToken").value = "wTK - trigo tokenizado";
  $("wheatAmount").value = "100000";
  $("borrowAmount").value = "10000";
  $("wheatAmountLabel").textContent = "Garantia estable depositada (aUSD)";
  $("borrowAmountLabel").textContent = "Prestamo solicitado (wTK / bushels)";
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
  const liquidationBonus = val("liquidationBonus");

  const isProductive = model === "productivo";
  const collateralValue = isProductive ? wheatAmount * currentPrice : wheatAmount;
  const maxBorrowValue = collateralValue * (collateralFactor / 100);
  const interest = borrowAmount * (borrowRate / 100) * (termMonths / 12);
  const finalDebt = borrowAmount + interest;
  const finalDebtValue = isProductive ? finalDebt : finalDebt * currentPrice;
  const finalDebtWTK = isProductive ? 0 : finalDebt;
  const protocolReserve = interest * (reserveFactor / 100);
  const lenderYield = interest - protocolReserve;
  const data = {
    wheatAmount,
    cashCollateral: collateralValue,
    finalDebt,
    finalDebtWTK,
    liquidationThreshold,
  };
  const hfNow = healthFactor(collateralValue, liquidationThreshold, finalDebtValue);
  const liqPrice = liquidationPrice(model, data);

  $("collateralValue").textContent = money.format(collateralValue);
  $("maxBorrow").textContent = isProductive
    ? money.format(maxBorrowValue)
    : `${number.format(maxBorrowValue / currentPrice)} wTK`;
  $("finalDebt").textContent = isProductive
    ? money.format(finalDebt)
    : `${number.format(finalDebt)} wTK (${money.format(finalDebtValue)})`;
  $("healthFactor").textContent = Number.isFinite(hfNow) ? number.format(hfNow) : "Sin deuda";
  $("totalInterest").textContent = isProductive
    ? money.format(interest)
    : `${number.format(interest)} wTK`;
  $("lenderYield").textContent = isProductive
    ? money.format(lenderYield)
    : `${number.format(lenderYield)} wTK`;
  $("protocolReserve").textContent = isProductive
    ? money.format(protocolReserve)
    : `${number.format(protocolReserve)} wTK`;

  const status = labelForHealth(hfNow);
  $("estadoPrestamo").textContent = status;
  $("estadoDetalle").textContent =
    status === "Liquidable"
      ? `${borrower} quedo por debajo del umbral de liquidacion.`
      : `${borrower} puede operar con ${lender}, manteniendo el riesgo visible.`;

  const box = document.querySelector(".status-box");
  box.classList.toggle("danger", status === "Liquidable");
  box.classList.toggle("risk", status === "Riesgo alto" || status === "Riesgo medio");

  const scenarios = [
    ["Hoy", currentPrice],
    ["Diciembre", decemberPrice],
    ["Marzo", marchPrice],
    ["Liquidacion", liqPrice],
  ];

  $("scenarioRows").innerHTML = scenarios
    .map(([name, price]) => {
      const scenario = scenarioForPrice(model, price, data);
      const label = labelForHealth(scenario.hf);
      return `
        <tr>
          <td>${name}</td>
          <td>${money.format(price)}</td>
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
  const collateralWord = isProductive ? "tomar wTK" : "tomar garantia aUSD";
  $("liquidationText").textContent =
    `Si el trigo ${direction} ${money.format(liqPrice)} por bushel, ` +
    `un liquidador podria pagar parte de la deuda de ${borrower} y ${collateralWord} con un bonus del ${number.format(liquidationBonus)}%. ` +
    `El objetivo es proteger la liquidez aportada por ${lender}.`;
}

ids.forEach((id) => $(id).addEventListener("input", render));
document.querySelectorAll('input[name="modelType"]').forEach((input) => {
  input.addEventListener("change", () => {
    applyModelDefaults(activeModel());
    render();
  });
});
render();
