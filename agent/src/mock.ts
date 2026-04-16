import { Policy, MarketData } from "./types";
import { logger } from "./logger";

/**
 * MOCK_MODE module: simulates on-chain state with fake data, no real transactions.
 *
 * Simulated scenario: a user's HF gradually drops from 1.5 to the danger zone,
 * allowing us to observe the AI's full decision process from "monitor" to "repay".
 */

// Simulated state: HF decreases on each read
let mockHF = 1.5;
const HF_DROP_PER_CYCLE = 0.05; // drops 0.05 per cycle

const MOCK_USER = "0x000000000000000000000000000000000000dEaD";

const MOCK_POLICY: Policy = {
  healthFactorThreshold: 1.3,
  maxRepayPerTx: 500,
  cooldownPeriod: 3600,
  lastExecutionTime: 0,
  active: true,
};

// --- Mock versions of onchain functions ---

export function getRegisteredUsers(): string[] {
  return [MOCK_USER];
}

export function getPolicy(_user: string): Policy {
  return { ...MOCK_POLICY };
}

export function getHealthFactor(_user: string): number {
  const hf = mockHF;
  // Decrease after each read, simulating ETH price drop causing HF decline
  mockHF = Math.max(mockHF - HF_DROP_PER_CYCLE, 1.0);
  logger.info("[MOCK] Health factor", { hf, nextHF: mockHF });
  return hf;
}

export function getUserDebt(_user: string): number {
  return 3000; // Fixed 3000 USDC debt
}

export function getProtectionBudget(_user: string): number {
  return 800; // Fixed 800 USDC budget
}

// --- Mock versions of market functions ---

let mockEthPrice = 2400;
const PRICE_DROP_PER_CYCLE = 50; // drops $50 per cycle

export function getMarketData(): MarketData {
  const currentPrice = mockEthPrice;
  mockEthPrice = Math.max(mockEthPrice - PRICE_DROP_PER_CYCLE, 1500);
  return {
    currentPrice,
    ethPriceChange1h: -2.5, // Simulate continued decline
    ethPriceChange24h: -7.0,
  };
}

// --- Mock version of executor ---

export function executeRepayment(
  user: string,
  amount: number,
  reasoning: string
): string {
  const fakeTxHash = "0x" + "mock".repeat(16);
  logger.info("[MOCK] Repayment executed (no real tx)", {
    user,
    amount,
    reasoning,
    fakeTxHash,
  });
  // HF should recover after repayment
  mockHF += 0.3;
  logger.info("[MOCK] HF restored after repayment", { newHF: mockHF });
  return fakeTxHash;
}

// --- Reset state (for testing) ---

export function resetMockState(): void {
  mockHF = 1.5;
  mockEthPrice = 2400;
}
