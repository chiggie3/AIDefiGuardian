/**
 * HF semicircle gauge
 * Draws an SVG half-circle arc that changes color based on HF value.
 * HF range mapping: 0.8 ~ 3.0 -> 0% ~ 100%
 */

const MIN_HF = 0.8;
const MAX_HF = 3.0;

function hfToPercent(hf: number): number {
  const clamped = Math.max(MIN_HF, Math.min(MAX_HF, hf));
  return ((clamped - MIN_HF) / (MAX_HF - MIN_HF)) * 100;
}

function hfToColor(hf: number): string {
  if (hf > 2.0) return "#22c55e"; // green
  if (hf > 1.5) return "#f59e0b"; // amber
  if (hf > 1.1) return "#ef4444"; // red
  return "#dc2626"; // deep red
}

export default function HfGauge({
  hf,
  threshold,
}: {
  hf: number;
  threshold?: number;
}) {
  const percent = hfToPercent(hf);
  const color = hfToColor(hf);

  // SVG arc math — semicircle from 180° to 0° (left to right)
  const radius = 80;
  const cx = 100;
  const cy = 95;
  const circumference = Math.PI * radius; // semicircle circumference
  const dashOffset = circumference * (1 - percent / 100);

  // Threshold marker position
  const thresholdPercent = threshold ? hfToPercent(threshold) : null;
  const thresholdAngle = thresholdPercent
    ? Math.PI * (1 - thresholdPercent / 100)
    : null;
  const thresholdX = thresholdAngle
    ? cx + radius * Math.cos(thresholdAngle)
    : 0;
  const thresholdY = thresholdAngle
    ? cy - radius * Math.sin(thresholdAngle)
    : 0;

  return (
    <div className="flex flex-col items-center">
      <svg viewBox="0 0 200 120" className="w-64 h-auto">
        {/* Background arc */}
        <path
          d={`M ${cx - radius} ${cy} A ${radius} ${radius} 0 0 1 ${cx + radius} ${cy}`}
          fill="none"
          stroke="rgba(100, 116, 139, 0.2)"
          strokeWidth="12"
          strokeLinecap="round"
        />

        {/* Value arc */}
        <path
          d={`M ${cx - radius} ${cy} A ${radius} ${radius} 0 0 1 ${cx + radius} ${cy}`}
          fill="none"
          stroke={color}
          strokeWidth="12"
          strokeLinecap="round"
          strokeDasharray={circumference}
          strokeDashoffset={dashOffset}
          style={{
            transition: "stroke-dashoffset 0.8s ease, stroke 0.5s ease",
            filter: `drop-shadow(0 0 6px ${color}40)`,
          }}
        />

        {/* Threshold marker */}
        {thresholdAngle && (
          <>
            <circle
              cx={thresholdX}
              cy={thresholdY}
              r="3"
              fill="#818cf8"
              stroke="#0a0f1a"
              strokeWidth="1.5"
            />
            <text
              x={thresholdX}
              y={thresholdY - 10}
              textAnchor="middle"
              className="text-[8px] fill-slate-400"
            >
              {threshold?.toFixed(1)}
            </text>
          </>
        )}

        {/* HF value */}
        <text
          x={cx}
          y={cy - 18}
          textAnchor="middle"
          className="text-3xl font-bold"
          fill={color}
        >
          {hf > 100 ? ">100" : hf.toFixed(3)}
        </text>
        <text
          x={cx}
          y={cy}
          textAnchor="middle"
          className="text-[10px]"
          fill="#94a3b8"
        >
          Health Factor
        </text>

        {/* Scale labels */}
        <text
          x={cx - radius - 2}
          y={cy + 14}
          textAnchor="middle"
          className="text-[8px]"
          fill="#475569"
        >
          0.8
        </text>
        <text
          x={cx + radius + 2}
          y={cy + 14}
          textAnchor="middle"
          className="text-[8px]"
          fill="#475569"
        >
          3.0
        </text>
      </svg>
    </div>
  );
}
