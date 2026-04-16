import { useEffect, useState } from "react";
import { usePublicClient } from "wagmi";
import { parseAbiItem } from "viem";
import { ADDRESSES } from "../config/contracts";

export interface ProtectionEvent {
  user: string;
  repayAmount: bigint;
  healthFactorBefore: bigint;
  healthFactorAfter: bigint;
  aiReasoning: string;
  timestamp: bigint;
  txHash: string;
  blockNumber: bigint;
}

const EVENT_ABI = parseAbiItem(
  "event ProtectionExecuted(address indexed user, uint256 repayAmount, uint256 healthFactorBefore, uint256 healthFactorAfter, string aiReasoning, uint256 timestamp)"
);

/**
 * Fetch ProtectionExecuted events from the GuardianVault contract.
 * Looks back N blocks from the latest, polls every 15 seconds for new events.
 */
export function useActionLog(lookbackBlocks = 5000n) {
  const client = usePublicClient();
  const [events, setEvents] = useState<ProtectionEvent[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!client) return;

    let cancelled = false;

    async function fetchEvents() {
      try {
        const blockNumber = await client!.getBlockNumber();
        const fromBlock =
          blockNumber > lookbackBlocks ? blockNumber - lookbackBlocks : 0n;

        const logs = await client!.getLogs({
          address: ADDRESSES.vault,
          event: EVENT_ABI,
          fromBlock,
          toBlock: "latest",
        });

        if (cancelled) return;

        const parsed: ProtectionEvent[] = logs.map((log) => ({
          user: log.args.user!,
          repayAmount: log.args.repayAmount!,
          healthFactorBefore: log.args.healthFactorBefore!,
          healthFactorAfter: log.args.healthFactorAfter!,
          aiReasoning: log.args.aiReasoning!,
          timestamp: log.args.timestamp!,
          txHash: log.transactionHash,
          blockNumber: log.blockNumber,
        }));

        // Sort by timestamp descending (newest first)
        parsed.sort((a, b) => Number(b.timestamp - a.timestamp));
        setEvents(parsed);
        setError(null);
      } catch (err) {
        if (!cancelled) {
          setError(String(err));
        }
      } finally {
        if (!cancelled) {
          setIsLoading(false);
        }
      }
    }

    fetchEvents();

    // Poll every 15 seconds
    const interval = setInterval(fetchEvents, 15_000);

    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, [client, lookbackBlocks]);

  return { events, isLoading, error };
}
