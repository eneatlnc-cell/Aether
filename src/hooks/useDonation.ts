"use client";

import { useCallback, useState } from "react";
import { useAccount, useSendTransaction } from "wagmi";
import { parseUnits, type Address } from "viem";
import { useToast } from "@/components/ui/Toast";
import { useTranslations } from "next-intl";
import {
  TREASURY_ADDRESSES,
  PREFERRED_ASSET,
  type AssetCode,
  type DonationPurpose,
} from "@/lib/fundFlowData";

export type DonationStep =
  | "idle"
  | "form"
  | "awaiting-signature"
  | "submitting"
  | "success"
  | "error";

export interface DonationResult {
  txHash: string;
  asset: AssetCode;
  amount: number;
  purpose: DonationPurpose;
  timestamp: number;
  donor: Address;
  treasury: Address;
}

interface SubmitArgs {
  asset: AssetCode;
  amount: number;
  purpose: DonationPurpose;
}

/**
 * 捐赠流程 Hook
 *
 * 当前为半占位实现：
 *  - ETH 走 wagmi useSendTransaction（真实链上交易，但需要用户已连接钱包）
 *  - USDC / USDT 需要真实合约地址后才能接入 ERC20 transfer
 *
 * 真实接入点：
 *  - ERC20: 通过 useReadContract 读取 decimals，再 useSimulateContract + useWriteContract
 *  - ETH:   直接 sendTransaction 到 TREASURY_ADDRESSES.arbitrum
 *
 * 在缺少合约地址时，Hook 会模拟一笔成功交易用于流程演示。
 */
export function useDonation() {
  const t = useTranslations("donation");
  const tToast = useTranslations("toast");
  const { push } = useToast();
  const { address, isConnected } = useAccount();
  const { sendTransactionAsync } = useSendTransaction();

  const [step, setStep] = useState<DonationStep>("idle");
  const [result, setResult] = useState<DonationResult | null>(null);

  const reset = useCallback(() => {
    setStep("idle");
    setResult(null);
  }, []);

  const submit = useCallback(
    async ({ asset, amount, purpose }: SubmitArgs) => {
      if (!isConnected || !address) {
        push(t("connectFirst"), "info");
        return;
      }

      if (amount <= 0) return;

      setStep("awaiting-signature");
      try {
        const treasury = TREASURY_ADDRESSES.arbitrum as Address;
        let txHash: string;

        if (asset === "ETH") {
          // 真实链上 ETH 转账
          const value = parseUnits(amount.toFixed(18), 18);
          const tx = await sendTransactionAsync({
            to: treasury,
            value,
            chainId: 42161,
          });
          txHash = tx;
        } else {
          // USDC / USDT 占位：缺少合约地址，模拟一笔成功交易
          // 真实接入后替换为 ERC20 transfer
          await new Promise((r) => setTimeout(r, 1200));
          txHash =
            "0x" +
            Array.from({ length: 64 }, () =>
              "0123456789abcdef"[Math.floor(Math.random() * 16)]
            ).join("");
        }

        setStep("submitting");
        // 等待确认（ETH 真实交易可监听 receipt，这里简化）
        await new Promise((r) => setTimeout(r, 800));

        const donationResult: DonationResult = {
          txHash,
          asset,
          amount,
          purpose,
          timestamp: Date.now(),
          donor: address,
          treasury,
        };
        setResult(donationResult);
        setStep("success");
        push(tToast("donationSuccess"), "success");
      } catch (err) {
        const name = (err as Error)?.name;
        if (name === "UserRejectedRequestError") {
          // 用户取消，静默回到表单
          setStep("form");
        } else {
          setStep("error");
          push(tToast("error"), "info");
        }
      }
    },
    [address, isConnected, sendTransactionAsync, push, t, tToast]
  );

  return {
    step,
    result,
    isConnected,
    preferredAsset: PREFERRED_ASSET,
    treasuryAddress: TREASURY_ADDRESSES.arbitrum,
    submit,
    reset,
  };
}
