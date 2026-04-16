import { useReadContract, useWriteContract, useAccount } from "wagmi";
import {
  ADDRESSES,
  REGISTRY_ABI,
  VAULT_ABI,
  ERC20_ABI,
} from "../config/contracts";

/** Read user's Guardian policy from Registry */
export function usePolicy() {
  const { address } = useAccount();
  return useReadContract({
    address: ADDRESSES.registry,
    abi: REGISTRY_ABI,
    functionName: "getPolicy",
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 10_000 },
  });
}

/** Read user's gUSDC balance in Vault (protection budget) */
export function useBudget() {
  const { address } = useAccount();
  return useReadContract({
    address: ADDRESSES.vault,
    abi: VAULT_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 10_000 },
  });
}

/** Read user's USDC balance */
export function useUsdcBalance() {
  const { address } = useAccount();
  return useReadContract({
    address: ADDRESSES.usdc,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 10_000 },
  });
}

/** Read USDC allowance for Vault */
export function useVaultAllowance() {
  const { address } = useAccount();
  return useReadContract({
    address: ADDRESSES.usdc,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: address ? [address, ADDRESSES.vault] : undefined,
    query: { enabled: !!address, refetchInterval: 5_000 },
  });
}

/** Write: setPolicy on Registry */
export function useSetPolicy() {
  const { writeContractAsync, isPending, isSuccess, error } =
    useWriteContract();

  const setPolicy = async (
    threshold: bigint,
    maxRepay: bigint,
    cooldown: bigint
  ) => {
    return writeContractAsync({
      address: ADDRESSES.registry,
      abi: REGISTRY_ABI,
      functionName: "setPolicy",
      args: [threshold, maxRepay, cooldown],
    });
  };

  return { setPolicy, isPending, isSuccess, error };
}

/** Write: deactivate policy */
export function useDeactivate() {
  const { writeContractAsync, isPending, isSuccess, error } =
    useWriteContract();

  const deactivate = async () => {
    return writeContractAsync({
      address: ADDRESSES.registry,
      abi: REGISTRY_ABI,
      functionName: "deactivate",
    });
  };

  return { deactivate, isPending, isSuccess, error };
}

/** Write: approve USDC for Vault */
export function useApproveUsdc() {
  const { writeContractAsync, isPending, isSuccess, error } =
    useWriteContract();

  const approve = async (amount: bigint) => {
    return writeContractAsync({
      address: ADDRESSES.usdc,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [ADDRESSES.vault, amount],
    });
  };

  return { approve, isPending, isSuccess, error };
}

/** Write: deposit USDC into Vault */
export function useDeposit() {
  const { writeContractAsync, isPending, isSuccess, error } =
    useWriteContract();
  const { address } = useAccount();

  const deposit = async (amount: bigint) => {
    if (!address) throw new Error("Wallet not connected");
    return writeContractAsync({
      address: ADDRESSES.vault,
      abi: VAULT_ABI,
      functionName: "deposit",
      args: [amount, address],
    });
  };

  return { deposit, isPending, isSuccess, error };
}

/** Write: withdraw USDC from Vault */
export function useWithdraw() {
  const { writeContractAsync, isPending, isSuccess, error } =
    useWriteContract();
  const { address } = useAccount();

  const withdraw = async (amount: bigint) => {
    if (!address) throw new Error("Wallet not connected");
    return writeContractAsync({
      address: ADDRESSES.vault,
      abi: VAULT_ABI,
      functionName: "withdraw",
      args: [amount, address, address],
    });
  };

  return { withdraw, isPending, isSuccess, error };
}
