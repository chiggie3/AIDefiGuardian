import { useAccount } from "wagmi";
import { useAavePosition } from "../hooks/useAavePosition";
import { usePolicy, useBudget } from "../hooks/useGuardian";
import StatusBadge, { getHfStatus } from "../components/StatusBadge";
import HfGauge from "../components/HfGauge";

function formatUsd(value: number): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(value);
}

function StatCard({
  label,
  value,
  sub,
  accent,
}: {
  label: string;
  value: string;
  sub?: string;
  accent?: boolean;
}) {
  return (
    <div className="glass rounded-2xl p-5">
      <p className="text-xs text-slate-500 uppercase tracking-wide">{label}</p>
      <p
        className={`text-xl font-semibold mt-1 ${accent ? "gradient-text" : "text-white"}`}
      >
        {value}
      </p>
      {sub && <p className="text-xs text-slate-500 mt-1">{sub}</p>}
    </div>
  );
}

function BudgetBar({
  budget,
  maxRepay,
}: {
  budget: number;
  maxRepay: number;
}) {
  // How many full protections can the budget cover?
  const rounds = maxRepay > 0 ? Math.floor(budget / maxRepay) : 0;
  const barPercent = rounds >= 1 ? 100 : 0; // Any protections available = full bar

  return (
    <div className="glass rounded-2xl p-5">
      <div className="flex items-center justify-between mb-3">
        <p className="text-xs text-slate-500 uppercase tracking-wide">
          Budget Adequacy
        </p>
        <span
          className={`text-xs font-medium ${
            rounds >= 3
              ? "text-safe"
              : rounds >= 1
                ? "text-warn"
                : "text-danger"
          }`}
        >
          {rounds} protection{rounds !== 1 ? "s" : ""} available
        </span>
      </div>
      <div className="h-2 bg-slate-800 rounded-full overflow-hidden">
        <div
          className={`h-full rounded-full transition-all duration-700 ${
            rounds >= 3
              ? "bg-safe"
              : rounds >= 1
                ? "bg-warn"
                : "bg-danger"
          }`}
          style={{ width: `${barPercent}%` }}
        />
      </div>
      <p className="text-xs text-slate-600 mt-2">
        {budget.toFixed(0)} USDC / {maxRepay.toFixed(0)} per tx
      </p>
    </div>
  );
}

function PositionBreakdown({
  collateral,
  debt,
  ltv,
  liqThreshold,
  availableBorrow,
}: {
  collateral: number;
  debt: number;
  ltv: number;
  liqThreshold: number;
  availableBorrow: number;
}) {
  const currentLtv = collateral > 0 ? (debt / collateral) * 100 : 0;

  return (
    <div className="glass rounded-2xl p-5">
      <h3 className="text-sm font-medium text-white mb-4">Position Details</h3>
      <div className="space-y-3">
        <div className="flex justify-between text-sm">
          <span className="text-slate-400">Collateral</span>
          <span className="text-white font-mono">{formatUsd(collateral)}</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-slate-400">Total Debt</span>
          <span className="text-white font-mono">{formatUsd(debt)}</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-slate-400">Available to Borrow</span>
          <span className="text-white font-mono">
            {formatUsd(availableBorrow)}
          </span>
        </div>

        <div className="border-t border-slate-700/50 pt-3 mt-3" />

        {/* LTV bar */}
        <div>
          <div className="flex justify-between text-xs mb-1.5">
            <span className="text-slate-500">
              Current LTV: {currentLtv.toFixed(1)}%
            </span>
            <span className="text-slate-500">
              Max LTV: {(ltv / 100).toFixed(1)}%
            </span>
          </div>
          <div className="relative h-2 bg-slate-800 rounded-full overflow-hidden">
            {/* Liquidation threshold marker */}
            <div
              className="absolute top-0 h-full w-px bg-danger/60"
              style={{ left: `${liqThreshold / 100}%` }}
            />
            {/* Current LTV fill */}
            <div
              className={`h-full rounded-full transition-all duration-700 ${
                currentLtv < ltv / 100 - 10
                  ? "bg-safe"
                  : currentLtv < liqThreshold / 100
                    ? "bg-warn"
                    : "bg-danger"
              }`}
              style={{ width: `${Math.min(100, currentLtv)}%` }}
            />
          </div>
          <p className="text-xs text-slate-600 mt-1">
            Liquidation threshold: {(liqThreshold / 100).toFixed(1)}%
          </p>
        </div>
      </div>
    </div>
  );
}

export default function Dashboard() {
  const { isConnected } = useAccount();
  const { position, isLoading: posLoading } = useAavePosition();
  const { data: policy, isLoading: polLoading } = usePolicy();
  const { data: budget, isLoading: budLoading } = useBudget();

  if (!isConnected) {
    return (
      <div className="flex flex-col items-center justify-center py-32">
        <div className="w-16 h-16 rounded-2xl bg-guardian/10 flex items-center justify-center mb-6">
          <svg
            viewBox="0 0 24 24"
            fill="none"
            className="w-8 h-8 text-guardian-light"
          >
            <path
              d="M12 2L3 7v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V7l-9-5z"
              fill="currentColor"
              opacity="0.2"
            />
            <path
              d="M12 2L3 7v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V7l-9-5z"
              stroke="currentColor"
              strokeWidth="1.5"
            />
          </svg>
        </div>
        <h1 className="text-2xl font-semibold text-white mb-2">
          AI DeFi Guardian
        </h1>
        <p className="text-slate-400 mb-2">
          AI-powered liquidation protection for Aave
        </p>
        <p className="text-sm text-slate-500">
          Connect your wallet to get started
        </p>
      </div>
    );
  }

  const loading = posLoading || polLoading || budLoading;
  const hf = position?.hf ?? 0;
  const threshold = policy
    ? Number(policy.healthFactorThreshold) / 1e18
    : undefined;
  const budgetUsdc = budget ? Number(budget) / 1e6 : 0;
  const maxRepay = policy ? Number(policy.maxRepayPerTx) / 1e6 : 0;
  const policyActive = policy?.active ?? false;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-white">Dashboard</h1>
          <p className="text-sm text-slate-400 mt-1">
            Real-time Aave position monitoring
          </p>
        </div>
        <div className="flex items-center gap-3">
          {!loading && policyActive && (
            <StatusBadge status="safe" label="Guardian Active" />
          )}
          {!loading && !policyActive && (
            <StatusBadge status="inactive" label="Guardian Inactive" />
          )}
          {!loading && position && (
            <StatusBadge status={getHfStatus(hf, threshold)} />
          )}
        </div>
      </div>

      {loading ? (
        <div className="glass rounded-2xl p-16 text-center">
          <div className="inline-block w-8 h-8 border-2 border-guardian/30 border-t-guardian rounded-full animate-spin" />
          <p className="text-slate-400 mt-4 text-sm">
            Loading position data...
          </p>
        </div>
      ) : (
        <>
          {/* Top row: HF gauge + stats */}
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            {/* HF Gauge — takes 1 col */}
            <div className="glass rounded-2xl p-6 glow flex flex-col items-center justify-center">
              {position && position.debtUsd > 0 ? (
                <HfGauge hf={hf} threshold={threshold} />
              ) : (
                <div className="text-center py-4">
                  <p className="text-3xl font-bold text-safe">No Debt</p>
                  <p className="text-xs text-slate-500 mt-2">
                    Health Factor: Infinite
                  </p>
                </div>
              )}
              {threshold && (
                <p className="text-xs text-slate-500 mt-1">
                  Protection triggers below {threshold.toFixed(2)}
                </p>
              )}
            </div>

            {/* Stats — takes 2 cols */}
            <div className="lg:col-span-2 grid grid-cols-2 gap-4">
              <StatCard
                label="Collateral"
                value={position ? formatUsd(position.collateralUsd) : "--"}
              />
              <StatCard
                label="Total Debt"
                value={position ? formatUsd(position.debtUsd) : "--"}
              />
              <StatCard
                label="Protection Budget"
                value={`${budgetUsdc.toFixed(2)} USDC`}
                accent
              />
              <StatCard
                label="Guardian"
                value={policyActive ? "Active" : "Inactive"}
                sub={
                  policyActive && threshold
                    ? `Threshold: ${threshold.toFixed(2)} | Max: ${maxRepay} USDC`
                    : "Set up protection in Setup page"
                }
              />
            </div>
          </div>

          {/* Bottom row: Position details + Budget adequacy */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {position && (
              <PositionBreakdown
                collateral={position.collateralUsd}
                debt={position.debtUsd}
                ltv={Number(position.ltv)}
                liqThreshold={Number(position.currentLiquidationThreshold)}
                availableBorrow={position.availableBorrowUsd}
              />
            )}

            {policyActive ? (
              <BudgetBar budget={budgetUsdc} maxRepay={maxRepay} />
            ) : (
              <div className="glass rounded-2xl p-5 flex items-center justify-center">
                <p className="text-slate-500 text-sm">
                  Activate Guardian in the Setup page to see budget adequacy
                </p>
              </div>
            )}
          </div>

          {/* Policy card */}
          {policyActive && policy && (
            <div className="glass rounded-2xl p-5">
              <h3 className="text-sm font-medium text-white mb-4">
                Active Policy
              </h3>
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                <div>
                  <p className="text-xs text-slate-500 uppercase tracking-wide">
                    HF Threshold
                  </p>
                  <p className="text-white font-mono text-lg mt-1">
                    {(Number(policy.healthFactorThreshold) / 1e18).toFixed(2)}
                  </p>
                </div>
                <div>
                  <p className="text-xs text-slate-500 uppercase tracking-wide">
                    Max Repay / TX
                  </p>
                  <p className="text-white font-mono text-lg mt-1">
                    {maxRepay} USDC
                  </p>
                </div>
                <div>
                  <p className="text-xs text-slate-500 uppercase tracking-wide">
                    Cooldown
                  </p>
                  <p className="text-white font-mono text-lg mt-1">
                    {Number(policy.cooldownPeriod) / 60} min
                  </p>
                </div>
                <div>
                  <p className="text-xs text-slate-500 uppercase tracking-wide">
                    Last Execution
                  </p>
                  <p className="text-white font-mono text-lg mt-1">
                    {Number(policy.lastExecutionTime) > 0
                      ? new Date(
                          Number(policy.lastExecutionTime) * 1000
                        ).toLocaleString()
                      : "Never"}
                  </p>
                </div>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}
