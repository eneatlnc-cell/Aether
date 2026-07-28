// SPDX-License-Identifier: Apache-2.0
interface ProgressBarProps {
  /** 0 - 100 */
  value: number;
  variant?: "neutral" | "accent";
  height?: number;
  showLabel?: boolean;
  label?: string;
}

export function ProgressBar({
  value,
  variant = "neutral",
  height = 6,
  showLabel = false,
  label,
}: ProgressBarProps) {
  const clamped = Math.min(100, Math.max(0, value));
  const fillClass =
    variant === "accent"
      ? "bg-gradient-to-r from-border to-accent"
      : "bg-gradient-to-r from-border to-ink";

  return (
    <div className="w-full">
      <div
        className="w-full bg-border rounded-full overflow-hidden"
        style={{ height: `${height}px` }}
      >
        <div
          className={`h-full ${fillClass} transition-all duration-700`}
          style={{ width: `${clamped}%` }}
        />
      </div>
      {showLabel && (
        <div className="flex justify-between mt-2 text-xs text-muted">
          <span>{label}</span>
          <span>{clamped.toFixed(0)}%</span>
        </div>
      )}
    </div>
  );
}
