import dotenv from "dotenv";
import path from "path";

dotenv.config({ path: path.join(__dirname, "..", ".env") });

import { logger } from "./logger";
import { AgentContext } from "./types";
import { decide } from "./ai";
import * as mock from "./mock";
import * as onchain from "./onchain";
import * as market from "./market";
import * as executor from "./executePayment";

// --- Configuration ---

const MOCK_MODE = process.env.MOCK_MODE === "true";
const POLL_INTERVAL_MS = MOCK_MODE
  ? 10 * 1000   // mock mode: 10s per cycle for easy observation
  : 5 * 60 * 1000; // production mode: 5 minutes per cycle
const MAX_CYCLES = MOCK_MODE
  ? 5                                          // mock mode: stop after 5 cycles
  : Number(process.env.MAX_CYCLES) || Infinity; // production: infinite by default, configurable via env

// --- Urgency Calculation ---

function calculateUrgency(
  hf: number,
  threshold: number
): "low" | "medium" | "high" | "critical" {
  const ratio = hf / threshold;
  if (ratio <= 0.8) return "critical";  // HF far below threshold
  if (ratio <= 0.9) return "high";
  if (ratio <= 1.0) return "medium";    // HF around threshold
  return "low";                          // HF still above threshold
}

// --- Process Single User ---

async function processUser(user: string): Promise<void> {
  // 1. Read user policy
  const policy = MOCK_MODE
    ? mock.getPolicy(user)
    : await onchain.getPolicy(user);

  if (!policy.active) {
    logger.info("Policy inactive, skipping", { user });
    return;
  }

  // 2. Read HF, budget, debt, market data in parallel
  const [hf, budget, totalDebt, marketData] = MOCK_MODE
    ? [
        mock.getHealthFactor(user),
        mock.getProtectionBudget(user),
        mock.getUserDebt(user),
        mock.getMarketData(),
      ]
    : await Promise.all([
        onchain.getHealthFactor(user),
        onchain.getProtectionBudget(user),
        onchain.getUserDebt(user),
        market.updateAndGetMarketData(),
      ]);

  logger.info("User data collected", { user, hf, budget, totalDebt, marketData });

  // 3. Safety check: HF well above threshold -> skip
  if (hf > policy.healthFactorThreshold * 1.2) {
    logger.info("HF safe, skipping", {
      user,
      hf,
      threshold: policy.healthFactorThreshold,
    });
    return;
  }

  // 4. Build AI context
  const urgency = calculateUrgency(hf, policy.healthFactorThreshold);
  const timeSinceLastExecution =
    policy.lastExecutionTime > 0
      ? (Date.now() / 1000 - policy.lastExecutionTime) / 60
      : Infinity;

  const context: AgentContext = {
    user,
    hf,
    policy,
    budget,
    totalDebt,
    marketData,
    urgency,
    timeSinceLastExecution,
  };

  // 5. Call Claude for decision
  const decision = await decide(context);
  logger.info("AI decision", { user, decision });

  // 6. Execute decision
  if (decision.action === "repay") {
    if (MOCK_MODE) {
      mock.executeRepayment(user, Number(decision.amount), decision.reasoning);
    } else {
      await executor.execute(user, decision, policy);
    }
  } else if (decision.action === "alert_only") {
    logger.warn("ALERT: Budget insufficient for effective protection", {
      user,
      hf,
      budget,
      reasoning: decision.reasoning,
    });
  }
  // action === "monitor" -> do nothing, wait for next cycle
}

// --- Main Loop ---

async function monitorLoop(cycle: number): Promise<void> {
  logger.info(`=== Monitor cycle ${cycle} start ===`, { mockMode: MOCK_MODE });

  try {
    // Get user list
    const users = MOCK_MODE
      ? mock.getRegisteredUsers()
      : await onchain.getRegisteredUsers();

    // Deduplicate (known issue: registeredUsers may contain duplicate addresses)
    const uniqueUsers = [...new Set(users)];
    logger.info("Registered users", { count: uniqueUsers.length, users: uniqueUsers });

    // Process each user
    for (const user of uniqueUsers) {
      try {
        await processUser(user);
      } catch (err) {
        // Single user failure should not affect other users
        logger.error("Error processing user", { user, error: String(err) });
      }
    }
  } catch (err) {
    logger.error("Monitor loop error", { error: String(err) });
  }

  logger.info(`=== Monitor cycle ${cycle} end ===`);
}

// --- Startup ---

async function main(): Promise<void> {
  logger.info("AI Guardian Agent starting", {
    mockMode: MOCK_MODE,
    pollInterval: POLL_INTERVAL_MS / 1000 + "s",
    maxCycles: MAX_CYCLES,
  });

  for (let cycle = 1; cycle <= MAX_CYCLES; cycle++) {
    await monitorLoop(cycle);

    if (cycle < MAX_CYCLES) {
      logger.info(`Waiting ${POLL_INTERVAL_MS / 1000}s for next cycle...`);
      await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
    }
  }

  logger.info("Agent stopped");
}

main().catch((err) => {
  logger.error("Fatal error", { error: String(err) });
  process.exit(1);
});
