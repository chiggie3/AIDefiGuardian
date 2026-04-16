import { useState } from "react";
import { useAccount } from "wagmi";
import {
  usePolicy,
  useBudget,
  useUsdcBalance,
  useVaultAllowance,
  useSetPolicy,
  useDeactivate,
  useApproveUsdc,
  useDeposit,
  useWithdraw,
} from "../hooks/useGuardian";

type TxStatus = "idle" | "pending" | "success" | "error";

function TxFeedback({
  status,
  error,
}: {
  status: TxStatus;
  error?: Error | null;
}) {
  if (status === "idle") return null;
  if (status === "pending")
    return (
      <div className="flex items-center gap-2 text-sm text-guardian-light">
        <div className="w-4 h-4 border-2 border-guardian/30 border-t-guardian rounded-full animate-spin" />
        Confirm in MetaMask...
      </div>
    );
  if (status === "success")
    return <p className="text-sm text-safe">Transaction confirmed!</p>;
  if (status === "error")
    return (
      <p className="text-sm text-danger">
        {error?.message?.slice(0, 120) || "Transaction failed"}
      </p>
    );
  return null;
}

// --- Policy Form ---

function PolicyForm() {
  const { data: policy } = usePolicy();
  const { setPolicy, isPending } = useSetPolicy();
  const { deactivate, isPending: deactivating } = useDeactivate();
  const [txStatus, setTxStatus] = useState<TxStatus>("idle");
  const [txError, setTxError] = useState<Error | null>(null);

  const currentThreshold = policy
    ? (Number(policy.healthFactorThreshold) / 1e18).toFixed(2)
    : "";
  const currentMaxRepay = policy
    ? (Number(policy.maxRepayPerTx) / 1e6).toString()
    : "";
  const currentCooldown = policy
    ? (Number(policy.cooldownPeriod) / 60).toString()
    : "";

  const [threshold, setThreshold] = useState("");
  const [maxRepay, setMaxRepay] = useState("");
  const [cooldown, setCooldown] = useState("");

  const handleSetPolicy = async () => {
    const t = parseFloat(threshold || currentThreshold || "1.3");
    const m = parseFloat(maxRepay || currentMaxRepay || "500");
    const c = parseFloat(cooldown || currentCooldown || "60");

    if (t < 1.05 || t > 1.8) {
      setTxError(new Error("Threshold must be between 1.05 and 1.80"));
      setTxStatus("error");
      return;
    }
    if (m <= 0) {
      setTxError(new Error("Max repay must be > 0"));
      setTxStatus("error");
      return;
    }
    if (c < 60) {
      setTxError(new Error("Cooldown must be >= 60 minutes"));
      setTxStatus("error");
      return;
    }

    try {
      setTxStatus("pending");
      setTxError(null);
      // Convert: threshold to 18 decimals, maxRepay to 6 decimals (USDC), cooldown to seconds
      const thresholdWei = BigInt(Math.round(t * 1e18));
      const maxRepayWei = BigInt(Math.round(m * 1e6));
      const cooldownSec = BigInt(Math.round(c * 60));
      await setPolicy(thresholdWei, maxRepayWei, cooldownSec);
      setTxStatus("success");
      setThreshold("");
      setMaxRepay("");
      setCooldown("");
    } catch (err) {
      setTxError(err as Error);
      setTxStatus("error");
    }
  };

  const handleDeactivate = async () => {
    try {
      setTxStatus("pending");
      setTxError(null);
      await deactivate();
      setTxStatus("success");
    } catch (err) {
      setTxError(err as Error);
      setTxStatus("error");
    }
  };

  return (
    <div className="glass rounded-2xl p-6 space-y-5">
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-medium text-white">Protection Policy</h2>
        {policy?.active && (
          <span className="text-xs text-safe bg-safe/10 px-2 py-0.5 rounded-full">
            Active
          </span>
        )}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div>
          <label className="block text-xs text-slate-400 mb-1.5">
            HF Threshold (1.05 - 1.80)
          </label>
          <input
            type="number"
            step="0.01"
            min="1.05"
            max="1.80"
            placeholder={currentThreshold || "1.30"}
            value={threshold}
            onChange={(e) => setThreshold(e.target.value)}
          />
        </div>
        <div>
          <label className="block text-xs text-slate-400 mb-1.5">
            Max Repay per TX (USDC)
          </label>
          <input
            type="number"
            step="1"
            min="1"
            placeholder={currentMaxRepay || "500"}
            value={maxRepay}
            onChange={(e) => setMaxRepay(e.target.value)}
          />
        </div>
        <div>
          <label className="block text-xs text-slate-400 mb-1.5">
            Cooldown (minutes, min 60)
          </label>
          <input
            type="number"
            step="1"
            min="60"
            placeholder={currentCooldown || "60"}
            value={cooldown}
            onChange={(e) => setCooldown(e.target.value)}
          />
        </div>
      </div>

      <div className="flex gap-3 items-center">
        <button
          onClick={handleSetPolicy}
          disabled={isPending}
          className="px-5 py-2.5 rounded-xl bg-guardian text-white font-medium hover:bg-guardian-dark transition-colors disabled:opacity-50 cursor-pointer"
        >
          {isPending ? "Confirming..." : policy?.active ? "Update Policy" : "Activate Protection"}
        </button>
        {policy?.active && (
          <button
            onClick={handleDeactivate}
            disabled={deactivating}
            className="px-5 py-2.5 rounded-xl border border-slate-600 text-slate-300 font-medium hover:bg-slate-800 transition-colors disabled:opacity-50 cursor-pointer"
          >
            {deactivating ? "Confirming..." : "Deactivate"}
          </button>
        )}
        <TxFeedback status={txStatus} error={txError} />
      </div>
    </div>
  );
}

// --- Budget Form ---

function BudgetForm() {
  const { data: budget } = useBudget();
  const { data: usdcBalance } = useUsdcBalance();
  const { data: allowance } = useVaultAllowance();
  const { approve, isPending: approving } = useApproveUsdc();
  const { deposit, isPending: depositing } = useDeposit();
  const { withdraw, isPending: withdrawing } = useWithdraw();

  const [amount, setAmount] = useState("");
  const [txStatus, setTxStatus] = useState<TxStatus>("idle");
  const [txError, setTxError] = useState<Error | null>(null);

  const budgetUsdc = budget ? Number(budget) / 1e6 : 0;
  const walletUsdc = usdcBalance ? Number(usdcBalance) / 1e6 : 0;
  const currentAllowance = allowance ? Number(allowance) / 1e6 : 0;

  const handleDeposit = async () => {
    const amt = parseFloat(amount);
    if (!amt || amt <= 0) return;

    const amtWei = BigInt(Math.round(amt * 1e6));

    try {
      setTxStatus("pending");
      setTxError(null);

      // Approve if needed
      if (currentAllowance < amt) {
        await approve(amtWei);
      }
      await deposit(amtWei);
      setTxStatus("success");
      setAmount("");
    } catch (err) {
      setTxError(err as Error);
      setTxStatus("error");
    }
  };

  const handleWithdraw = async () => {
    const amt = parseFloat(amount);
    if (!amt || amt <= 0) return;

    try {
      setTxStatus("pending");
      setTxError(null);
      const amtWei = BigInt(Math.round(amt * 1e6));
      await withdraw(amtWei);
      setTxStatus("success");
      setAmount("");
    } catch (err) {
      setTxError(err as Error);
      setTxStatus("error");
    }
  };

  return (
    <div className="glass rounded-2xl p-6 space-y-5">
      <h2 className="text-lg font-medium text-white">Protection Budget</h2>

      <div className="grid grid-cols-2 gap-4">
        <div className="bg-slate-800/50 rounded-xl p-4">
          <p className="text-xs text-slate-500 uppercase tracking-wide">
            Vault Balance
          </p>
          <p className="text-xl font-semibold text-white mt-1">
            {budgetUsdc.toFixed(2)}{" "}
            <span className="text-sm text-slate-400">USDC</span>
          </p>
        </div>
        <div className="bg-slate-800/50 rounded-xl p-4">
          <p className="text-xs text-slate-500 uppercase tracking-wide">
            Wallet Balance
          </p>
          <p className="text-xl font-semibold text-white mt-1">
            {walletUsdc.toFixed(2)}{" "}
            <span className="text-sm text-slate-400">USDC</span>
          </p>
        </div>
      </div>

      <div>
        <label className="block text-xs text-slate-400 mb-1.5">
          Amount (USDC)
        </label>
        <input
          type="number"
          step="1"
          min="0"
          placeholder="500"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
        />
      </div>

      <div className="flex gap-3 items-center">
        <button
          onClick={handleDeposit}
          disabled={depositing || approving}
          className="px-5 py-2.5 rounded-xl bg-guardian text-white font-medium hover:bg-guardian-dark transition-colors disabled:opacity-50 cursor-pointer"
        >
          {approving ? "Approving..." : depositing ? "Depositing..." : "Deposit"}
        </button>
        <button
          onClick={handleWithdraw}
          disabled={withdrawing}
          className="px-5 py-2.5 rounded-xl border border-slate-600 text-slate-300 font-medium hover:bg-slate-800 transition-colors disabled:opacity-50 cursor-pointer"
        >
          {withdrawing ? "Withdrawing..." : "Withdraw"}
        </button>
        <TxFeedback status={txStatus} error={txError} />
      </div>
    </div>
  );
}

// --- Setup Page ---

export default function Setup() {
  const { isConnected } = useAccount();

  if (!isConnected) {
    return (
      <div className="text-center py-20">
        <p className="text-slate-400 text-lg">
          Connect your wallet to set up Guardian protection
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold text-white">Setup</h1>
        <p className="text-sm text-slate-400 mt-1">
          Configure your protection policy and deposit budget
        </p>
      </div>
      <PolicyForm />
      <BudgetForm />
    </div>
  );
}
