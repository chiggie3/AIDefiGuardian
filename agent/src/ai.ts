import Anthropic from "@anthropic-ai/sdk";
import dotenv from "dotenv";
import path from "path";
import { AgentContext, AIDecision } from "./types";
import { logger } from "./logger";

dotenv.config({ path: path.join(__dirname, "..", ".env") });

// --- Claude API Client ---

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

// --- System Prompt: defines Claude's role and output format ---

const SYSTEM_PROMPT = `You are a DeFi risk management AI protecting users' Aave positions from liquidation.

You receive pre-computed flags and position data. Use the flags directly — do not re-evaluate them.

DECISION LOGIC (follow strictly):
1. If "Budget sufficient" is NO → action: "alert_only"
2. If "HF below threshold" is YES AND "ETH declining" is YES → action: "repay"
3. If "HF below threshold" is YES AND "ETH declining" is NO → action: "repay" if urgency is "high" or "critical", otherwise "monitor"
4. If "HF below threshold" is NO → action: "monitor"

REPAYMENT AMOUNT (when action is "repay"):
- Use maxRepayPerTx as the amount
- But cap at: min(maxRepayPerTx, budget, totalDebt)
- At high/critical urgency, always use the full maximum allowed

IMPORTANT: A single repayment of maxRepayPerTx does NOT need to cover the full debt. Even a partial repayment significantly improves the health factor. Your job is to protect, not to fully repay.

Return ONLY valid JSON:
{
  "action": "repay" | "monitor" | "alert_only",
  "amount": "500",
  "reasoning": "Brief explanation under 100 words"
}

amount: in USDC. Set to "0" when action is not "repay".`;

// --- Build User Prompt ---
function buildPrompt(ctx: AgentContext): string {
  const belowThreshold = ctx.hf < ctx.policy.healthFactorThreshold;
  const ethDeclining = ctx.marketData.ethPriceChange1h < 0 || ctx.marketData.ethPriceChange24h < 0;
  const budgetSufficient = ctx.budget >= ctx.policy.maxRepayPerTx;
  const maxAllowed = Math.min(ctx.policy.maxRepayPerTx, ctx.budget, ctx.totalDebt);

  return `=== Pre-computed Flags ===
HF below threshold: ${belowThreshold ? "YES" : "NO"}
ETH declining: ${ethDeclining ? "YES" : "NO"}
Budget sufficient: ${budgetSufficient ? "YES" : "NO"}
Urgency: ${ctx.urgency}

=== Position Data ===
Health factor: ${ctx.hf} (threshold: ${ctx.policy.healthFactorThreshold})
ETH price: $${ctx.marketData.currentPrice} | 1h: ${ctx.marketData.ethPriceChange1h.toFixed(2)}% | 24h: ${ctx.marketData.ethPriceChange24h.toFixed(2)}%
Protection budget: ${ctx.budget} USDC
Total debt: ${ctx.totalDebt} USDC
Max repay per tx: ${ctx.policy.maxRepayPerTx} USDC
Max allowed repay amount: ${maxAllowed} USDC
Time since last protection: ${ctx.timeSinceLastExecution} minutes

Provide your decision.`;
}

// --- Parse Claude's JSON response ---

function parseDecision(text: string): AIDecision {
  // Try to extract JSON from text (Claude sometimes wraps in markdown code blocks)
  const jsonMatch = text.match(/\{[\s\S]*\}/);
  if (!jsonMatch) {
    throw new Error("No JSON found in response");
  }

  const parsed = JSON.parse(jsonMatch[0]);

  // Validate fields
  if (!["repay", "monitor", "alert_only"].includes(parsed.action)) {
    throw new Error(`Invalid action: ${parsed.action}`);
  }
  if (typeof parsed.amount !== "string") {
    throw new Error("amount must be a string");
  }
  if (typeof parsed.reasoning !== "string") {
    throw new Error("reasoning must be a string");
  }

  return {
    action: parsed.action,
    amount: parsed.amount,
    reasoning: parsed.reasoning,
  };
}

// --- Core decision function ---
export async function decide(context: AgentContext): Promise<AIDecision> {
  const prompt = buildPrompt(context);

  try {
    logger.info("Calling Claude API for decision", { user: context.user, hf: context.hf });

    const response = await client.messages.create({
      model: "claude-haiku-4-5",
      max_tokens: 256,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: prompt }],
    });

    const text =
      response.content.length > 0 && response.content[0].type === "text"
        ? response.content[0].text
        : "";

    logger.info("Claude raw response", { text });

    const decision = parseDecision(text);
    logger.info("AI decision parsed", { decision });
    return decision;
  } catch (err) {
    // Fail-safe: any error defaults to monitor, never execute on failure
    logger.error("AI decision failed, defaulting to monitor", { error: String(err) });
    return {
      action: "monitor",
      amount: "0",
      reasoning: "AI decision failed, defaulting to monitor",
    };
  }
}

// --- Test entry point ---

if (require.main === module) {
  (async () => {
    try {
      console.log("=== Testing Claude API Decision ===\n");

      // Simulate a dangerous position scenario
      const testContext: AgentContext = {
        user: "0x1234567890abcdef1234567890abcdef12345678",
        hf: 1.15,
        policy: {
          healthFactorThreshold: 1.3,
          maxRepayPerTx: 500,
          cooldownPeriod: 3600,
          lastExecutionTime: 0,
          active: true,
        },
        budget: 800,
        totalDebt: 3000,
        marketData: {
          currentPrice: 2200,
          ethPriceChange1h: -3.5,
          ethPriceChange24h: -8.2,
        },
        urgency: "high",
        timeSinceLastExecution: 120,
      };

      console.log("Input: HF=1.15 (threshold 1.3), ETH 1h drop 3.5%, urgency=high\n");

      const decision = await decide(testContext);
      console.log("\nAI decision:", decision);
    } catch (err) {
      console.error("Error:", err);
    }
  })();
}
