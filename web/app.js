/* FixedRateRedeemer frontend logic (ethers v6). */
(() => {
  "use strict";

  const CONFIG = window.REDEEMER_CONFIG || {};
  const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

  const REDEEMER_ABI = [
    "function tokenA() view returns (address)",
    "function tokenB() view returns (address)",
    "function wallet() view returns (address)",
    "function rateNumerator() view returns (uint256)",
    "function rateDenominator() view returns (uint256)",
    "function previewRedeem(uint256 amountA) view returns (uint256 amountB)",
    "function redeem(uint256 amountA) returns (uint256 amountB)",
    "event Redeemed(address indexed redeemer, address indexed recipient, uint256 amountA, uint256 amountB)"
  ];

  const ERC20_ABI = [
    "function name() view returns (string)",
    "function symbol() view returns (string)",
    "function decimals() view returns (uint8)",
    "function balanceOf(address account) view returns (uint256)",
    "function allowance(address owner, address spender) view returns (uint256)",
    "function approve(address spender, uint256 amount) returns (bool)"
  ];

  const els = {
    connect: document.getElementById("connect"),
    account: document.getElementById("account"),
    tokenA: document.getElementById("tokenA"),
    tokenB: document.getElementById("tokenB"),
    wallet: document.getElementById("wallet"),
    rate: document.getElementById("rate"),
    balA: document.getElementById("balA"),
    balB: document.getElementById("balB"),
    allowA: document.getElementById("allowA"),
    amountA: document.getElementById("amountA"),
    max: document.getElementById("max"),
    preview: document.getElementById("preview"),
    approve: document.getElementById("approve"),
    redeem: document.getElementById("redeem"),
    status: document.getElementById("status")
  };

  const state = {
    provider: null,
    signer: null,
    account: null,
    redeemer: null,
    tokenA: null,
    tokenB: null,
    decA: 18,
    decB: 18,
    symA: "tokenA",
    symB: "tokenB",
    meta: {}
  };

  function setStatus(msg, kind) {
    els.status.textContent = msg || "";
    els.status.className = "status" + (kind ? " " + kind : "");
  }

  function short(addr) {
    return addr ? addr.slice(0, 6) + "\u2026" + addr.slice(-4) : "\u2014";
  }

  function fmt(value, decimals) {
    try {
      return Number(ethers.formatUnits(value, decimals)).toLocaleString(undefined, {
        maximumFractionDigits: 6
      });
    } catch (_) {
      return value.toString();
    }
  }

  function configured() {
    const a = CONFIG.contractAddress;
    return a && a.toLowerCase() !== ZERO_ADDRESS;
  }

  async function getReadProvider() {
    if (window.ethereum) return new ethers.BrowserProvider(window.ethereum);
    if (CONFIG.rpcUrl) return new ethers.JsonRpcProvider(CONFIG.rpcUrl);
    throw new Error("No wallet found and no rpcUrl configured.");
  }

  async function connect() {
    try {
      if (!configured()) {
        setStatus("Set contractAddress in config.js first.", "error");
        return;
      }
      if (!window.ethereum) {
        setStatus("No browser wallet found. Install MetaMask.", "error");
        return;
      }
      setStatus("Connecting\u2026");
      const provider = new ethers.BrowserProvider(window.ethereum);
      await provider.send("eth_requestAccounts", []);
      const signer = await provider.getSigner();
      const account = await signer.getAddress();

      const network = await provider.getNetwork();
      if (CONFIG.chainId != null && Number(network.chainId) !== Number(CONFIG.chainId)) {
        setStatus(
          "Wrong network: expected chain " + CONFIG.chainId + ", got " + network.chainId + ".",
          "error"
        );
        return;
      }

      state.provider = provider;
      state.signer = signer;
      state.account = account;
      state.redeemer = new ethers.Contract(CONFIG.contractAddress, REDEEMER_ABI, signer);

      els.connect.textContent = "Connected";
      els.connect.disabled = true;
      els.account.textContent = short(account);

      await loadInfo();
      setStatus("Connected.", "ok");
    } catch (err) {
      setStatus(err.shortMessage || err.message || String(err), "error");
    }
  }

  async function loadInfo() {
    const c = state.redeemer;
    const [tokenA, tokenB, wallet, num, den] = await Promise.all([
      c.tokenA(),
      c.tokenB(),
      c.wallet(),
      c.rateNumerator(),
      c.rateDenominator()
    ]);

    state.meta = { tokenA, tokenB, wallet, num, den };

    state.tokenA = new ethers.Contract(tokenA, ERC20_ABI, state.provider);
    state.tokenB = new ethers.Contract(tokenB, ERC20_ABI, state.provider);

    const [symA, decA, symB, decB] = await Promise.all([
      safeText(state.tokenA.symbol(), "A"),
      safeNum(state.tokenA.decimals(), 18),
      safeText(state.tokenB.symbol(), "B"),
      safeNum(state.tokenB.decimals(), 18)
    ]);
    state.symA = symA;
    state.decA = decA;
    state.symB = symB;
    state.decB = decB;

    els.tokenA.textContent = symA + " \u2014 " + short(tokenA);
    els.tokenB.textContent = symB + " \u2014 " + short(tokenB);
    els.wallet.textContent = short(wallet);

    const oneA = 10n ** BigInt(decA);
    const out = await c.previewRedeem(oneA);
    els.rate.textContent = "1 " + symA + " = " + fmt(out, decB) + " " + symB;

    await refreshBalances();
  }

  async function safeText(p, fallback) {
    try {
      return await p;
    } catch (_) {
      return fallback;
    }
  }

  async function safeNum(p, fallback) {
    try {
      return Number(await p);
    } catch (_) {
      return fallback;
    }
  }

  async function refreshBalances() {
    if (!state.account) return;
    const [bA, bB, allow] = await Promise.all([
      state.tokenA.balanceOf(state.account),
      state.tokenB.balanceOf(state.meta.wallet),
      state.tokenA.allowance(state.account, CONFIG.contractAddress)
    ]);
    els.balA.textContent = fmt(bA, state.decA) + " " + state.symA;
    els.balB.textContent = fmt(bB, state.decB) + " " + state.symB;
    els.allowA.textContent = fmt(allow, state.decA) + " " + state.symA;
    state.meta.userBalanceA = bA;
    state.meta.allowanceA = allow;
    updateButtons();
  }

  function parsedAmount() {
    const raw = (els.amountA.value || "").trim();
    if (!raw) return null;
    try {
      const v = ethers.parseUnits(raw, state.decA);
      return v > 0n ? v : null;
    } catch (_) {
      return null;
    }
  }

  async function updatePreview() {
    const amount = parsedAmount();
    if (!amount || !state.redeemer) {
      els.preview.textContent = "\u2014";
      updateButtons();
      return;
    }
    try {
      const out = await state.redeemer.previewRedeem(amount);
      els.preview.textContent = fmt(out, state.decB);
    } catch (_) {
      els.preview.textContent = "\u2014";
    }
    updateButtons();
  }

  function updateButtons() {
    const amount = parsedAmount();
    const connected = !!state.signer && !!state.account;
    const allowance = state.meta.allowanceA ?? 0n;
    const needsApproval = amount != null && allowance < amount;
    els.approve.disabled = !connected || amount == null || !needsApproval;
    els.redeem.disabled = !connected || amount == null || needsApproval;
  }

  async function approve() {
    const amount = parsedAmount();
    if (!amount) return;
    try {
      els.approve.disabled = true;
      setStatus("Approving " + state.symA + "\u2026");
      const tx = await state.tokenA.approve(CONFIG.contractAddress, amount);
      await tx.wait();
      setStatus("Approved.", "ok");
      await refreshBalances();
    } catch (err) {
      setStatus(err.shortMessage || err.message || String(err), "error");
      updateButtons();
    }
  }

  async function redeem() {
    const amount = parsedAmount();
    if (!amount) return;
    try {
      els.redeem.disabled = true;
      els.approve.disabled = true;
      setStatus("Redeeming\u2026");
      const tx = await state.redeemer.redeem(amount);
      const receipt = await tx.wait();
      let out = "?";
      for (const log of receipt.logs) {
        try {
          const parsed = state.redeemer.interface.parseLog(log);
          if (parsed && parsed.name === "Redeemed") {
            out = fmt(parsed.args.amountB, state.decB);
          }
        } catch (_) {
          /* ignore unrelated logs */
        }
      }
      setStatus("Redeemed for " + out + " " + state.symB + ".", "ok");
      els.amountA.value = "";
      els.preview.textContent = "\u2014";
      await refreshBalances();
    } catch (err) {
      setStatus(err.shortMessage || err.message || String(err), "error");
      updateButtons();
    }
  }

  function useMax() {
    if (state.meta.userBalanceA == null) return;
    els.amountA.value = ethers.formatUnits(state.meta.userBalanceA, state.decA);
    updatePreview();
  }

  // Wire up events.
  els.connect.addEventListener("click", connect);
  els.approve.addEventListener("click", approve);
  els.redeem.addEventListener("click", redeem);
  els.max.addEventListener("click", useMax);
  els.amountA.addEventListener("input", updatePreview);

  if (window.ethereum && window.ethereum.on) {
    window.ethereum.on("accountsChanged", () => window.location.reload());
    window.ethereum.on("chainChanged", () => window.location.reload());
  }

  if (!configured()) {
    setStatus("Configure contractAddress in config.js to begin.", "warn");
    els.connect.disabled = true;
  }
})();
