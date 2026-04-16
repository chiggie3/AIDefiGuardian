import { useState } from "react";
import { useActionLog, type ProtectionEvent } from "../hooks/useActionLog";

function formatHf(hfRaw: bigint): string {
  const hf = Number(hfRaw) / 1e18;
  if (hf > 100) return ">100";
  return hf.toFixed(4);
}

function formatUsdc(raw: bigint): string {
  return (Number(raw) / 1e6).toFixed(2);
}

function formatTime(ts: bigint): string {
  return new Date(Number(ts) * 1000).toLocaleString();
}

function shortenAddress(addr: string): string {
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

function HfChange({
  before,
  after,
}: {
  before: bigint;
  after: bigint;
}) {
  const hfBefore = Number(before) / 1e18;
  const hfAfter = Number(after) / 1e18;
  const improved = hfAfter > hfBefore;

  return (
    <div className="flex items-center gap-2 font-mono text-sm">
      <span className="text-danger">{hfBefore.toFixed(3)}</span>
      <svg viewBox="0 0 20 20" fill="none" className="w-4 h-4 text-slate-500">
        <path
          d="M4 10h12m0 0l-3-3m3 3l-3 3"
          stroke="currentColor"
          strokeWidth="1.5"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
      <span className={improved ? "text-safe" : "text-warn"}>
        {hfAfter.toFixed(3)}
      </span>
    </div>
  );
}

function EventRow({
  event,
  isExpanded,
  onToggle,
}: {
  event: ProtectionEvent;
  isExpanded: boolean;
  onToggle: () => void;
}) {
  return (
    <div className="glass rounded-xl overflow-hidden">
      {/* Main row */}
      <button
        onClick={onToggle}
        className="w-full px-5 py-4 flex items-center justify-between hover:bg-slate-800/30 transition-colors cursor-pointer text-left"
      >
        <div className="flex items-center gap-6">
          {/* Status icon */}
          <div className="w-9 h-9 rounded-lg bg-safe/10 flex items-center justify-center shrink-0">
            <svg
              viewBox="0 0 20 20"
              fill="none"
              className="w-5 h-5 text-safe"
            >
              <path
                d="M10 2L3 6v4c0 4.4 3 8.5 7 9.5 4-1 7-5.1 7-9.5V6l-7-4z"
                fill="currentColor"
                opacity="0.2"
              />
              <path
                d="M7 10l2 2 4-4"
                stroke="currentColor"
                strokeWidth="1.5"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
          </div>

          <div>
            <div className="flex items-center gap-3 mb-1">
              <span className="text-sm font-medium text-white">
                Repaid {formatUsdc(event.repayAmount)} USDC
              </span>
              <span className="text-xs text-slate-500">
                for {shortenAddress(event.user)}
              </span>
            </div>
            <HfChange
              before={event.healthFactorBefore}
              after={event.healthFactorAfter}
            />
          </div>
        </div>

        <div className="flex items-center gap-4">
          <span className="text-xs text-slate-500">
            {formatTime(event.timestamp)}
          </span>
          <svg
            viewBox="0 0 20 20"
            fill="none"
            className={`w-4 h-4 text-slate-500 transition-transform ${isExpanded ? "rotate-180" : ""}`}
          >
            <path
              d="M5 8l5 5 5-5"
              stroke="currentColor"
              strokeWidth="1.5"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        </div>
      </button>

      {/* Expanded details */}
      {isExpanded && (
        <div className="px-5 pb-4 border-t border-slate-700/50">
          <div className="pt-4 space-y-3">
            {/* AI Reasoning */}
            <div>
              <p className="text-xs text-slate-500 uppercase tracking-wide mb-1">
                AI Reasoning
              </p>
              <p className="text-sm text-slate-300 bg-slate-800/50 rounded-lg p-3 leading-relaxed">
                {event.aiReasoning}
              </p>
            </div>

            {/* Details grid */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
              <div>
                <p className="text-xs text-slate-500">User</p>
                <p className="text-xs text-white font-mono mt-0.5">
                  {shortenAddress(event.user)}
                </p>
              </div>
              <div>
                <p className="text-xs text-slate-500">Amount</p>
                <p className="text-xs text-white font-mono mt-0.5">
                  {formatUsdc(event.repayAmount)} USDC
                </p>
              </div>
              <div>
                <p className="text-xs text-slate-500">Block</p>
                <p className="text-xs text-white font-mono mt-0.5">
                  #{event.blockNumber.toString()}
                </p>
              </div>
              <div>
                <p className="text-xs text-slate-500">TX Hash</p>
                <p className="text-xs text-guardian-light font-mono mt-0.5 truncate">
                  {event.txHash.slice(0, 16)}...
                </p>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default function ActionLog() {
  const { events, isLoading, error } = useActionLog();
  const [expandedIdx, setExpandedIdx] = useState<number | null>(null);

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-white">Action Log</h1>
          <p className="text-sm text-slate-400 mt-1">
            AI protection execution history — on-chain events
          </p>
        </div>
        <div className="flex items-center gap-2">
          <span className="w-2 h-2 rounded-full bg-safe animate-pulse" />
          <span className="text-xs text-slate-500">Live</span>
        </div>
      </div>

      {/* Content */}
      {isLoading ? (
        <div className="glass rounded-2xl p-16 text-center">
          <div className="inline-block w-8 h-8 border-2 border-guardian/30 border-t-guardian rounded-full animate-spin" />
          <p className="text-slate-400 mt-4 text-sm">Loading events...</p>
        </div>
      ) : error ? (
        <div className="glass rounded-2xl p-8 text-center">
          <p className="text-danger text-sm">Error loading events</p>
          <p className="text-xs text-slate-500 mt-1">{error.slice(0, 200)}</p>
        </div>
      ) : events.length === 0 ? (
        <div className="glass rounded-2xl p-16 text-center">
          <div className="w-12 h-12 rounded-xl bg-slate-800/50 flex items-center justify-center mx-auto mb-4">
            <svg
              viewBox="0 0 24 24"
              fill="none"
              className="w-6 h-6 text-slate-500"
            >
              <path
                d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                stroke="currentColor"
                strokeWidth="1.5"
                strokeLinecap="round"
              />
            </svg>
          </div>
          <p className="text-slate-400 text-sm">No protection events yet</p>
          <p className="text-xs text-slate-600 mt-1">
            Events will appear here when the AI Agent executes a repayment
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {/* Summary */}
          <div className="flex gap-4 mb-2">
            <div className="glass rounded-xl px-4 py-2">
              <span className="text-xs text-slate-500">Total Events</span>
              <span className="text-sm text-white font-medium ml-2">
                {events.length}
              </span>
            </div>
            <div className="glass rounded-xl px-4 py-2">
              <span className="text-xs text-slate-500">Total Repaid</span>
              <span className="text-sm text-white font-medium ml-2">
                {(
                  events.reduce(
                    (sum, e) => sum + Number(e.repayAmount),
                    0
                  ) / 1e6
                ).toFixed(2)}{" "}
                USDC
              </span>
            </div>
          </div>

          {/* Event list */}
          {events.map((event, idx) => (
            <EventRow
              key={event.txHash}
              event={event}
              isExpanded={expandedIdx === idx}
              onToggle={() =>
                setExpandedIdx(expandedIdx === idx ? null : idx)
              }
            />
          ))}
        </div>
      )}
    </div>
  );
}
