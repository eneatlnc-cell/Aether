"use client";

import { useState, useEffect } from "react";
import { useTranslations } from "next-intl";
import { Modal } from "@/components/ui/Modal";
import { AddressCopy } from "@/components/ui/AddressCopy";
import { Button } from "@/components/ui/Button";
import {
  useDonation,
  type DonationStep,
} from "@/hooks/useDonation";
import { CheckCircle2, Download, Loader2, Wallet } from "lucide-react";

interface DonationModalProps {
  open: boolean;
  onClose: () => void;
  /** M3-d 注入的 PDF 下载回调 */
  onDownloadReceipt?: (result: NonNullable<ReturnType<typeof useDonation>["result"]>) => void;
}

/** USDC 6 decimals：1 USDC = 1_000_000 最小单位 */
const USDC_DECIMALS = 6;

export function DonationModal({ open, onClose, onDownloadReceipt }: DonationModalProps) {
  const t = useTranslations("donation");
  const { step, result, isConnected, treasuryAddress, submit, reset } =
    useDonation();

  const [amount, setAmount] = useState<string>("");

  // 弹窗关闭时重置状态
  useEffect(() => {
    if (!open) {
      const id = setTimeout(() => reset(), 300);
      return () => clearTimeout(id);
    }
  }, [open, reset]);

  // 交易进行中不允许关闭
  const busy =
    step === "approving" ||
    step === "approve-pending" ||
    step === "donating" ||
    step === "donate-pending";

  const handleClose = () => {
    if (busy) return;
    onClose();
  };

  const handleSubmit = () => {
    const numericAmount = parseFloat(amount);
    if (Number.isNaN(numericAmount) || numericAmount <= 0) return;
    // 转 bigint（USDC 6 decimals）
    const amountBigInt = BigInt(Math.round(numericAmount * 10 ** USDC_DECIMALS));
    submit({ amount: amountBigInt, purpose: "unrestricted" });
  };

  return (
    <Modal open={open} onClose={handleClose} title={t("title")} maxWidth="max-w-md">
      <p className="text-sm text-muted leading-relaxed mb-6">{t("subtitle")}</p>

      {/* 金库地址 */}
      <div className="mb-6 p-3 bg-bg border border-border rounded-[8px]">
        <p className="text-xs text-muted mb-1.5">{t("treasuryAddress")}</p>
        {treasuryAddress ? (
          <AddressCopy address={treasuryAddress} label={t("copied")} />
        ) : (
          <p className="text-xs text-muted italic">{t("treasuryPending")}</p>
        )}
        <p className="text-xs text-muted mt-2">{t("preferredAsset")}</p>
      </div>

      {/* 步骤内容 */}
      {step === "success" && result ? (
        <SuccessView
          result={result}
          onDownload={() => onDownloadReceipt?.(result)}
          onClose={handleClose}
        />
      ) : (
        <FormView
          amount={amount}
          setAmount={setAmount}
          step={step}
          isConnected={isConnected}
          onSubmit={handleSubmit}
        />
      )}
    </Modal>
  );
}

/* ---------- 表单态 ---------- */
function FormView({
  amount,
  setAmount,
  step,
  isConnected,
  onSubmit,
}: {
  amount: string;
  setAmount: (v: string) => void;
  step: DonationStep;
  isConnected: boolean;
  onSubmit: () => void;
}) {
  const t = useTranslations("donation");

  const busy =
    step === "approving" ||
    step === "approve-pending" ||
    step === "donating" ||
    step === "donate-pending";

  // 根据 step 显示不同状态文案
  const statusText = (() => {
    if (step === "approving") return t("approving");
    if (step === "approve-pending") return t("approvePending");
    if (step === "donating") return t("signing");
    if (step === "donate-pending") return t("submitting");
    return null;
  })();

  return (
    <div className="space-y-5">
      {/* 资产固定为 USDC（预启动阶段只支持 USDC） */}
      <Field label={t("selectAsset")}>
        <div className="grid grid-cols-1 gap-2">
          <div className="px-3 py-2 rounded-[8px] text-sm font-medium border bg-accent text-white border-accent">
            USDC
          </div>
        </div>
      </Field>

      {/* 金额 */}
      <Field label={t("amount")}>
        <input
          type="number"
          inputMode="decimal"
          min="0"
          step="any"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          placeholder="0.00"
          disabled={busy}
          className="w-full px-3 py-2 bg-card border border-border rounded-[8px] text-sm text-ink focus:outline-none focus:border-accent disabled:opacity-60"
        />
      </Field>

      {/* 用途选择暂时隐藏 - 项目尚未确定 */}
      {/* TODO: 项目确定后恢复用途选择功能 */}

      {/* 未连接钱包提示 */}
      {!isConnected && (
        <p className="text-xs text-muted flex items-center gap-2">
          <Wallet size={12} />
          {t("connectFirst")}
        </p>
      )}

      {/* 提交按钮 */}
      <Button
        onClick={onSubmit}
        disabled={busy || !isConnected || !amount || parseFloat(amount) <= 0}
        variant="accent"
        className="w-full"
      >
        {busy ? (
          <>
            <Loader2 size={14} className="animate-spin" />
            {statusText}
          </>
        ) : (
          t("title")
        )}
      </Button>
    </div>
  );
}

/* ---------- 成功态 ---------- */
function SuccessView({
  result,
  onDownload,
  onClose,
}: {
  result: NonNullable<ReturnType<typeof useDonation>["result"]>;
  onDownload: () => void;
  onClose: () => void;
}) {
  const t = useTranslations("donation");

  return (
    <div className="text-center py-2">
      <div className="w-12 h-12 mx-auto rounded-full bg-accent/10 flex items-center justify-center mb-4">
        <CheckCircle2 size={24} className="text-accent" />
      </div>
      <p className="text-base font-semibold text-ink mb-1">{t("success")}</p>
      <p className="text-xs text-muted font-mono break-all px-4">
        {result.txHash.slice(0, 32)}…
      </p>

      <div className="mt-6 space-y-2">
        <Button onClick={onDownload} variant="accent" className="w-full">
          <Download size={14} />
          {t("downloadReceipt")}
        </Button>
        <Button onClick={onClose} variant="ghost" className="w-full">
          {t("closeWindow")}
        </Button>
      </div>
    </div>
  );
}

function Field({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <label className="block text-xs text-muted uppercase tracking-wide mb-2">
        {label}
      </label>
      {children}
    </div>
  );
}
