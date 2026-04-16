import { AIDecision, Policy } from "./types";
import { executeRepayment, getProtectionBudget, getUserDebt } from "./onchain";
import { logger } from "./logger";

/*
 * Execute the AI's repayment decision.
 * Performs final safety checks before calling the on-chain contract:
 * 1. Amount must be a valid positive number
 * 2. Must not exceed the user's per-tx limit
 * 3. Must not exceed the user's protection budget
 * 4. Must not exceed the user's actual debt
 */
export async function execute(
  user: string,
  decision: AIDecision,
  policy: Policy
): Promise<string | null> {
  const amount = Number(decision.amount);

  // --- Safety Checks ---

  if (isNaN(amount) || amount <= 0) {
    logger.warn("Invalid repay amount, skipping", { user, amount: decision.amount });
    return null;
  }

  if (amount > policy.maxRepayPerTx) {
    logger.warn("Amount exceeds maxRepayPerTx, capping", {
      user,
      requested: amount,
      max: policy.maxRepayPerTx,
    });
    // Don't skip — cap to the limit instead (AI sometimes returns slightly higher values)
  }

  const safeAmount = Math.min(amount, policy.maxRepayPerTx);

  // Re-read latest budget and debt (may have changed during AI decision)
  const [budget, debt] = await Promise.all([
    getProtectionBudget(user),
    getUserDebt(user),
  ]);

  if (budget <= 0) {
    logger.warn("No protection budget, skipping", { user, budget });
    return null;
  }

  if (debt <= 0) {
    logger.info("No debt to repay, skipping", { user, debt });
    return null;
  }

  const finalAmount = Math.min(safeAmount, budget, debt);

  if (finalAmount <= 0) {
    logger.warn("Final amount is 0 after checks, skipping", { user });
    return null;
  }

  // --- Execute Transaction ---

  logger.info("Executing repayment", {
    user,
    aiRequested: amount,
    finalAmount,
    reasoning: decision.reasoning,
  });

  try {
    const txHash = await executeRepayment(user, finalAmount, decision.reasoning);
    logger.info("Repayment successful", { user, finalAmount, txHash });
    return txHash;
  } catch (err) {
    logger.error("Repayment transaction failed", { user, error: String(err) });
    return null;
  }
}
