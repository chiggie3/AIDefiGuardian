type Status = "safe" | "warning" | "danger" | "critical" | "inactive";

const STYLES: Record<Status, string> = {
  safe: "bg-safe/15 text-safe border-safe/30",
  warning: "bg-warn/15 text-warn border-warn/30",
  danger: "bg-danger/15 text-danger border-danger/30",
  critical: "bg-critical/15 text-critical border-critical/30 animate-pulse",
  inactive: "bg-slate-700/50 text-slate-400 border-slate-600/30",
};

const LABELS: Record<Status, string> = {
  safe: "Safe",
  warning: "Warning",
  danger: "Danger",
  critical: "Critical",
  inactive: "Inactive",
};

export function getHfStatus(hf: number, threshold?: number): Status {
  if (!threshold) {
    if (hf > 2) return "safe";
    if (hf > 1.5) return "warning";
    if (hf > 1.1) return "danger";
    return "critical";
  }
  const ratio = hf / threshold;
  if (ratio > 1.2) return "safe";
  if (ratio > 1.0) return "warning";
  if (ratio > 0.85) return "danger";
  return "critical";
}

export default function StatusBadge({
  status,
  label,
}: {
  status: Status;
  label?: string;
}) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium border ${STYLES[status]}`}
    >
      <span className="w-1.5 h-1.5 rounded-full bg-current" />
      {label || LABELS[status]}
    </span>
  );
}
