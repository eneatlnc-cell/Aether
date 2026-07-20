"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import { CheckCircle2, Info, X } from "lucide-react";

type ToastVariant = "success" | "info";

interface ToastItem {
  id: number;
  message: string;
  variant: ToastVariant;
}

interface ToastContextValue {
  push: (message: string, variant?: ToastVariant) => void;
}

const ToastContext = createContext<ToastContextValue | null>(null);

export function useToast() {
  const ctx = useContext(ToastContext);
  if (!ctx) throw new Error("useToast must be used within ToastProvider");
  return ctx;
}

export function ToastProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<ToastItem[]>([]);

  const remove = useCallback((id: number) => {
    setItems((prev) => prev.filter((t) => t.id !== id));
  }, []);

  const push = useCallback(
    (message: string, variant: ToastVariant = "success") => {
      const id = Date.now() + Math.random();
      setItems((prev) => [...prev, { id, message, variant }]);
      setTimeout(() => remove(id), 4000);
    },
    [remove]
  );

  return (
    <ToastContext.Provider value={{ push }}>
      {children}
      <div className="fixed top-6 right-6 z-[100] flex flex-col gap-3 max-w-sm">
        {items.map((t) => (
          <ToastCard key={t.id} item={t} onClose={() => remove(t.id)} />
        ))}
      </div>
    </ToastContext.Provider>
  );
}

function ToastCard({ item, onClose }: { item: ToastItem; onClose: () => void }) {
  const [leaving, setLeaving] = useState(false);

  useEffect(() => {
    const timer = setTimeout(() => setLeaving(true), 3600);
    return () => clearTimeout(timer);
  }, []);

  const Icon = item.variant === "success" ? CheckCircle2 : Info;

  return (
    <div
      className={`${
        leaving ? "toast-leave" : "toast-enter"
      } flex items-start gap-3 bg-card border border-border rounded-[12px] shadow-[0_4px_12px_rgba(0,0,0,0.04)] px-4 py-3 min-w-[280px]`}
      role="status"
    >
      <Icon
        size={18}
        className={
          item.variant === "success"
            ? "text-accent mt-0.5 flex-shrink-0"
            : "text-muted mt-0.5 flex-shrink-0"
        }
      />
      <p className="text-sm text-ink leading-relaxed flex-1">{item.message}</p>
      <button
        onClick={onClose}
        aria-label="close"
        className="text-muted hover:text-ink transition-colors flex-shrink-0"
      >
        <X size={14} />
      </button>
    </div>
  );
}
