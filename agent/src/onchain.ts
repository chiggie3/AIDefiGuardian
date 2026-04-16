import { ethers } from "ethers";
import dotenv from "dotenv";
import path from "path";
import { Policy } from "./types";
import { logger } from "./logger";

dotenv.config({ path: path.join(__dirname, "..", ".env") });

// --- Provider & Wallet ---

const provider = new ethers.JsonRpcProvider(process.env.SEPOLIA_RPC_URL);
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY!, provider);

// --- Contract Addresses (Sepolia deployment) ---

const REGISTRY_ADDRESS = "0x2a1eb5F43271d2d1aa0635bb56158D2280d6e7cC";
const AAVE_INTEGRATION_ADDRESS = "0x0cF45f3ECb4f67ea4688656c27a9c7bfe11E571E";
const VAULT_ADDRESS = "0xBB13da705D2Aa3DAA6ED8FfFcC83AD534281F27A";

// --- Minimal ABI (only functions the Agent needs) ---

const registryAbi = [
  "function getRegisteredUsers() view returns (address[])",
  "function getPolicy(address user) view returns (tuple(uint256 healthFactorThreshold, uint256 maxRepayPerTx, uint256 cooldownPeriod, uint256 lastExecutionTime, bool active))",
];

const aaveIntegrationAbi = [
  "function getHealthFactor(address user) view returns (uint256)",
  "function getUserDebt(address user) view returns (uint256)",
];

const vaultAbi = [
  "function balanceOf(address account) view returns (uint256)",
  "function convertToAssets(uint256 shares) view returns (uint256)",
  "function executeRepayment(address user, uint256 repayAmount, string aiReasoning)",
];

// --- Contract Instances ---

const registry = new ethers.Contract(REGISTRY_ADDRESS, registryAbi, provider);
const aaveIntegration = new ethers.Contract(AAVE_INTEGRATION_ADDRESS, aaveIntegrationAbi, provider);
const vault = new ethers.Contract(VAULT_ADDRESS, vaultAbi, provider);
const vaultWithSigner = new ethers.Contract(VAULT_ADDRESS, vaultAbi, wallet);

// --- Read Functions ---

export async function getRegisteredUsers(): Promise<string[]> {
  const users: string[] = await registry.getRegisteredUsers();
  return users;
}

export async function getPolicy(user: string): Promise<Policy> {
  const raw = await registry.getPolicy(user);
  return {
    healthFactorThreshold: Number(ethers.formatUnits(raw.healthFactorThreshold, 18)),
    maxRepayPerTx: Number(ethers.formatUnits(raw.maxRepayPerTx, 6)),
    cooldownPeriod: Number(raw.cooldownPeriod),
    lastExecutionTime: Number(raw.lastExecutionTime),
    active: raw.active,
  };
}

export async function getHealthFactor(user: string): Promise<number> {
  const hf: bigint = await aaveIntegration.getHealthFactor(user);
  return Number(ethers.formatUnits(hf, 18));
}

export async function getUserDebt(user: string): Promise<number> {
  const debt: bigint = await aaveIntegration.getUserDebt(user);
  return Number(ethers.formatUnits(debt, 6));
}

export async function getProtectionBudget(user: string): Promise<number> {
  const shares: bigint = await vault.balanceOf(user);
  if (shares === 0n) return 0;
  const assets: bigint = await vault.convertToAssets(shares);
  return Number(ethers.formatUnits(assets, 6));
}

// --- Write Functions ---

export async function executeRepayment(
  user: string,
  amountUsdc: number,
  aiReasoning: string
): Promise<string> {
  const amount = ethers.parseUnits(amountUsdc.toString(), 6);
  logger.info("Sending executeRepayment tx", { user, amountUsdc, aiReasoning });
  const tx = await vaultWithSigner.executeRepayment(user, amount, aiReasoning);
  const receipt = await tx.wait();
  if (!receipt) throw new Error("Transaction was not mined");
  logger.info("TX confirmed", { hash: receipt.hash, blockNumber: receipt.blockNumber });
  return receipt.hash;
}

// --- Test entry point: run this file directly to read on-chain data ---

if (require.main === module) {
  (async () => {
    try {
      console.log("=== Reading on-chain data ===\n");

      const users = await getRegisteredUsers();
      console.log("Registered users:", users);

      for (const user of users) {
        console.log(`\n--- ${user} ---`);
        const policy = await getPolicy(user);
        console.log("Policy:", policy);

        if (policy.active) {
          const hf = await getHealthFactor(user);
          console.log("Health factor:", hf);

          const debt = await getUserDebt(user);
          console.log("USDC debt:", debt);

          const budget = await getProtectionBudget(user);
          console.log("Protection budget:", budget, "USDC");
        } else {
          console.log("Policy inactive, skipping");
        }
      }
    } catch (err) {
      console.error("Error:", err);
    }
  })();
}
