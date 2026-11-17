/* Migraine frontend configuration.
 *
 * Fill in `contractAddress` and `chainId` after deploying the contract. `rpcUrl` is
 * optional: when a browser wallet (MetaMask) is connected it is used for all
 * reads/writes; the RPC URL is only used as a read-only fallback.
 */
window.MIGRAINE_CONFIG = {
  // Address of the deployed Migraine contract.
  contractAddress: "0x0000000000000000000000000000000000000000",

  // Required: the chain id this deployment is on (for example 1 for Ethereum
  // mainnet). The page refuses to connect until it is set, and refuses a wallet on
  // any other network.
  chainId: null,

  // Optional: read-only RPC endpoint (not required when using a browser wallet).
  rpcUrl: null
};
