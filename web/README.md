# Migraine web frontend

A tiny, dependency-free (ethers-v6-from-CDN) static UI for the
`Migraine` contract.

## Run it

```bash
cd web
python3 -m http.server 8080
# open http://localhost:8080
```

Any static file server works. There is no build step.

## Configure

Edit `config.js`:

```js
window.MIGRAINE_CONFIG = {
  contractAddress: "0xYourDeployedRedeemer",
  chainId: null,          // e.g. 1, 11155111, 31337; null disables the check
  rpcUrl: null            // optional read-only RPC fallback
};
```

## What it does

1. **Connect wallet** — uses `window.ethereum` (MetaMask).
2. Reads `tokenA`, `tokenB`, `wallet`, the fixed rate and the vault's `tokenB`
   balance directly from the contract.
3. Shows your `tokenA` balance and your current `tokenA` allowance to the
   redeemer.
4. **Approve token A** — only enabled when your allowance is below the amount
   you typed.
5. **Redeem** — calls `redeem(amountA)`, waits for the receipt and reads the
   `Redeemed` event to report the exact `tokenB` received.

The UI never asks for token `B` approvals: the *vault wallet* is responsible
for approving the redeemer to spend `tokenB` (a Safe transaction). See the
project `README.md` for the operational checklist.

## Security notes

- The page is static and has no backend. It only talks to your wallet and the
  chain.
- Pin or self-host the ethers bundle if you do not want to load it from a CDN.
