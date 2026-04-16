// User's protection policy registered in the Registry
export interface Policy {
  healthFactorThreshold: number; // e.g. 1.3 (converted from 18-decimal precision)
  maxRepayPerTx: number; // e.g. 500 (USDC, converted from 6-decimal precision)
  cooldownPeriod: number; // seconds, e.g. 3600
  lastExecutionTime: number; // unix timestamp
  active: boolean;
}

// ETH market data
export interface MarketData {
  currentPrice: number; // e.g. 2200.50
  ethPriceChange1h: number; // percentage, e.g. -3.5
  ethPriceChange24h: number; // percentage, e.g. -8.2
}

// Full context passed to Claude for decision-making
export interface AgentContext {
  user: string; // user address
  hf: number; // current health factor, e.g. 1.15
  policy: Policy;
  budget: number; // USDC balance in Vault, e.g. 800
  totalDebt: number; // Aave USDC debt, e.g. 3000
  marketData: MarketData;
  urgency: "low" | "medium" | "high" | "critical";
  timeSinceLastExecution: number; // minutes
}

// Decision returned by Claude
export interface AIDecision {
  action: "repay" | "monitor" | "alert_only";
  amount: string; // USDC amount, e.g. "300"
  reasoning: string; // AI decision reasoning
}
