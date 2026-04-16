// Sepolia deployed addresses (also used on Anvil fork)
export const ADDRESSES = {
  registry: "0x2a1eb5F43271d2d1aa0635bb56158D2280d6e7cC" as const,
  vault: "0xBB13da705D2Aa3DAA6ED8FfFcC83AD534281F27A" as const,
  aaveIntegration: "0x0cF45f3ECb4f67ea4688656c27a9c7bfe11E571E" as const,
  pool: "0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951" as const,
  usdc: "0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8" as const,
  weth: "0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c" as const,
} as const;

// Minimal ABIs — only the functions we need

export const REGISTRY_ABI = [
  {
    name: "getPolicy",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "healthFactorThreshold", type: "uint256" },
          { name: "maxRepayPerTx", type: "uint256" },
          { name: "cooldownPeriod", type: "uint256" },
          { name: "lastExecutionTime", type: "uint256" },
          { name: "active", type: "bool" },
        ],
      },
    ],
  },
  {
    name: "setPolicy",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "_healthFactorThreshold", type: "uint256" },
      { name: "_maxRepayPerTx", type: "uint256" },
      { name: "_cooldownPeriod", type: "uint256" },
    ],
    outputs: [],
  },
  {
    name: "deactivate",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [],
    outputs: [],
  },
  {
    name: "getRegisteredUsers",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address[]" }],
  },
] as const;

export const VAULT_ABI = [
  {
    name: "balanceOf",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "deposit",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "assets", type: "uint256" },
      { name: "receiver", type: "address" },
    ],
    outputs: [{ name: "shares", type: "uint256" }],
  },
  {
    name: "withdraw",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "assets", type: "uint256" },
      { name: "receiver", type: "address" },
      { name: "owner", type: "address" },
    ],
    outputs: [{ name: "shares", type: "uint256" }],
  },
  {
    name: "ProtectionExecuted",
    type: "event",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "repayAmount", type: "uint256", indexed: false },
      { name: "healthFactorBefore", type: "uint256", indexed: false },
      { name: "healthFactorAfter", type: "uint256", indexed: false },
      { name: "aiReasoning", type: "string", indexed: false },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
] as const;

export const POOL_ABI = [
  {
    name: "getUserAccountData",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [
      { name: "totalCollateralBase", type: "uint256" },
      { name: "totalDebtBase", type: "uint256" },
      { name: "availableBorrowsBase", type: "uint256" },
      { name: "currentLiquidationThreshold", type: "uint256" },
      { name: "ltv", type: "uint256" },
      { name: "healthFactor", type: "uint256" },
    ],
  },
] as const;

export const ERC20_ABI = [
  {
    name: "approve",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "balanceOf",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "allowance",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;
