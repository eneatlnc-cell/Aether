type Status = "active" | "static" | "passed" | "rejected";

interface StatusDotProps {
  status: Status;
  label?: string;
}

const colorMap: Record<Status, string> = {
  active: "bg-accent status-pulse",
  static: "bg-ink/60",
  passed: "bg-ink",
  rejected: "bg-muted",
};

export function StatusDot({ status, label }: StatusDotProps) {
  return (
    <span className="inline-flex items-center gap-2">
      <span
        className={`w-2 h-2 rounded-full ${colorMap[status]}`}
        aria-hidden="true"
      />
      {label && (
        <span className="text-sm text-ink leading-none">{label}</span>
      )}
    </span>
  );
}
