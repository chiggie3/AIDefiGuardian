import { useReadContract, useAccount } from "wagmi";
import { ADDRESSES, POOL_ABI } from "../config/contracts";

/** Read user's Aave position (collateral, debt, HF, etc.) */
export function useAavePosition() {
  const { address } = useAccount();

  const { data, isLoading, error, refetch } = useReadContract({
    address: ADDRESSES.pool,
    abi: POOL_ABI,
    functionName: "getUserAccountData",
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 10_000 },
  });

  if (!data) {
    return { position: null, isLoading, error, refetch };
  }

  const [
    totalCollateralBase,
    totalDebtBase,
    availableBorrowsBase,
    currentLiquidationThreshold,
    ltv,
    healthFactor,
  ] = data;

  return {
    position: {
      totalCollateralBase,
      totalDebtBase,
      availableBorrowsBase,
      currentLiquidationThreshold,
      ltv,
      healthFactor,
      // Formatted values (Aave base currency = USD with 8 decimals)
      collateralUsd: Number(totalCollateralBase) / 1e8,
      debtUsd: Number(totalDebtBase) / 1e8,
      availableBorrowUsd: Number(availableBorrowsBase) / 1e8,
      hf: Number(healthFactor) / 1e18,
    },
    isLoading,
    error,
    refetch,
  };
}
