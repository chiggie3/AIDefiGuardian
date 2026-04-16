import Anthropic from "@anthropic-ai/sdk";
import dotenv from "dotenv";
import path from "path";
import { AgentContext, AIDecision } from "./types";
import { logger } from "./logger";

dotenv.config({ path: path.join(__dirname, "..", ".env") });

// --- Claude API Client ---

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

// --- System Prompt: defines Claude's role and output format ---

const SYSTEM_PROMPT = `You are a DeFi risk management AI responsible for protecting users' Aave lending positions from liquidation.

You will receive real-time data about a user's position and must decide whether to execute a repayment.

Decision criteria:
1. Health factor below threshold AND ETH still declining → recommend repay
2. Health factor below threshold BUT ETH has rebounded or stabilized → recommend monitor
3. Protection budget insufficient to meaningfully improve health factor → recommend alert_only
4. When uncertain → conservatively choose monitor

Repayment amount principles:
- Must not exceed the user's configured max repay per transaction (maxRepayPerTx)
- Must not exceed the user's available protection budget
- Must not exceed the user's total debt
- Higher urgency should use amounts closer to the maximum
- At critical urgency, use the full maximum

You must return only valid JSON in this format:
{
  "action": "repay" or "monitor" or "alert_only",
  "amount": "300",
  "reasoning": "Brief explanation in under 100 words"
}

amount field: in USDC, only relevant when action is repay, otherwise "0".
Do not return anything other than JSON.`;

// --- Build User Prompt ---
function buildPrompt(ctx: AgentContext): string {
  return `Current position data:
- User address: ${ctx.user}
- Health factor: ${ctx.hf} (protection threshold: ${ctx.policy.healthFactorThreshold})
- Urgency level: ${ctx.urgency}
- ETH current price: $${ctx.marketData.currentPrice}
- ETH 1h price change: ${ctx.marketData.ethPriceChange1h.toFixed(2)}%
- ETH 24h price change: ${ctx.marketData.ethPriceChange24h.toFixed(2)}%
- Available protection budget: ${ctx.budget} USDC
- User total debt: ${ctx.totalDebt} USDC
- Max repay per transaction: ${ctx.policy.maxRepayPerTx} USDC
- Time since last protection: ${ctx.timeSinceLastExecution} minutes

Please provide your decision.`;
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
