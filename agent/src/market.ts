import { ethers } from "ethers";
import dotenv from "dotenv";
import path from "path";
import { MarketData } from "./types";
import { logger } from "./logger";

dotenv.config({ path: path.join(__dirname, "..", ".env") });

// --- Chainlink ETH/USD Price Feed (Sepolia) ---

const CHAINLINK_ETH_USD = "0x694AA1769357215DE4FAC081bf1f309aDC325306";

const chainlinkAbi = [
  "function latestRoundData() view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)",
];

const provider = new ethers.JsonRpcProvider(process.env.SEPOLIA_RPC_URL);
const priceFeed = new ethers.Contract(CHAINLINK_ETH_USD, chainlinkAbi, provider);

// --- Price history cache (in-memory, cleared on restart) ---

interface PricePoint {
  timestamp: number; // ms
  price: number;
}

const priceHistory: PricePoint[] = [];
const MAX_HISTORY = 288; // 24h / 5min = 288 data points

// --- Core Functions ---

/**
 * Read current ETH price from Chainlink, store in history cache, calculate price changes.
 * Called once per monitorLoop cycle.
 */
export async function updateAndGetMarketData(): Promise<MarketData> {
  const [, answer] = await priceFeed.latestRoundData();
  if (answer <= 0) throw new Error(`Invalid Chainlink price: ${answer}`);
  const currentPrice = Number(answer) / 1e8; // Chainlink uses 8 decimals

  // Store in history
  const now = Date.now();
  priceHistory.push({ timestamp: now, price: currentPrice });

  // Keep only the most recent 288 data points
  while (priceHistory.length > MAX_HISTORY) {
    priceHistory.shift();
  }

  // Calculate price changes
  const change1h = calcChange(currentPrice, now - 60 * 60 * 1000);
  const change24h = calcChange(currentPrice, now - 24 * 60 * 60 * 1000);

  logger.info("Market data updated", {
    currentPrice,
    ethPriceChange1h: change1h,
    ethPriceChange24h: change24h,
    historySize: priceHistory.length,
  });

  return {
    currentPrice,
    ethPriceChange1h: change1h,
    ethPriceChange24h: change24h,
  };
}

/**
 * Calculate percentage change from the price at sinceMs to current price.
 * Finds the closest historical point to sinceMs.
 * Returns 0 when insufficient data (AI treats 0% as conservative signal).
 */
function calcChange(currentPrice: number, sinceMs: number): number {
  // Find the first point >= sinceMs (closest to target time)
  const pastPoint = priceHistory.find((p) => p.timestamp >= sinceMs);
  if (!pastPoint || pastPoint.price === 0) return 0;
  return ((currentPrice - pastPoint.price) / pastPoint.price) * 100;
}

// --- Test entry point ---

if (require.main === module) {
  (async () => {
    try {
      console.log("=== Reading Chainlink ETH/USD Price ===\n");
      const data = await updateAndGetMarketData();
      console.log("Market data:", data);
      console.log("\nNote: 1h/24h changes are 0 on first run (insufficient history)");
    } catch (err) {
      console.error("Error:", err);
    }
  })();
}
