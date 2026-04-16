import { http, createConfig } from "wagmi";
import { sepolia } from "wagmi/chains";
import { injected } from "wagmi/connectors";

const rpcUrl = import.meta.env.VITE_RPC_URL || "http://127.0.0.1:8545";

// Anvil fork of Sepolia — same chainId as Sepolia (11155111)
// When running locally with anvil --fork-url, use localhost:8545
// MetaMask will connect as if it's Sepolia
const anvilFork = {
  ...sepolia,
  rpcUrls: {
    default: {
      http: [rpcUrl],
    },
  },
} as const;

export const config = createConfig({
  chains: [anvilFork],
  connectors: [injected()],
  transports: {
    [sepolia.id]: http(rpcUrl),
  },
});

declare module "wagmi" {
  interface Register {
    config: typeof config;
  }
}
