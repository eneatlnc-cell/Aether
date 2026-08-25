"use client";
// SPDX-License-Identifier: Apache-2.0

import { treasuryTransactions, type TreasuryTransaction } from "@/lib/fundFlowData";

/**
 * 金库最近链上交易记录 Hook
 *
 * 当前为 Mock 占位 —— 待 BscScan API Key + 金库地址提供后，
 * 内部替换为对 BscScan API 的 fetch（或自建索引器）。
 *
 * 接入点：
 *  - GET https://api.bscscan.com/api?module=account&action=txlist
 *        &address={TREASURY_ADDRESSES.bsc}&sort=desc&apikey={KEY}
 *  - 取最近 5 笔，按 timestamp 倒序
 *  - 反向解析用途备注（可从 input data 解码或链下备注表关联）
 */
export function useTreasuryTransactions(
  limit = 5
): { data: TreasuryTransaction[]; loading: boolean } {
  // 占位：直接切片 Mock。真实接入时使用 SWR / react-query 缓存
  return {
    data: treasuryTransactions.slice(0, limit),
    loading: false,
  };
}
