"use client";

import { fundFlow, type FundFlowSnapshot } from "@/lib/fundFlowData";

/**
 * 资金流向看板数据 Hook
 *
 * 当前为 Mock 占位 —— 待金库合约地址 + ABI 提供后，
 * 内部替换为 wagmi useReadContract 读取链上余额与已拨付金额。
 *
 * 接入点：
 *  - totalDonated: 监听 Donation 事件聚合
 *  - projectFunds: 读取 ProjectFund 合约的 allocated / spent 视图
 *  - treasuryBalanceUsd: 实时读取多签钱包的 ERC20 余额 + ETH 余额
 *  - monthlyFlow: 链下索引器或 The Graph 子图
 */
export function useFundFlow(): FundFlowSnapshot & { loading: boolean } {
  // 占位：直接返回 Mock。真实接入时使用 wagmi useReadContract + useQuery
  return {
    ...fundFlow,
    loading: false,
  };
}
