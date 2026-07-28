// SPDX-License-Identifier: Apache-2.0
// Aether DAO — 链上捐款 tx 验证
// 用 viem 直接读取 Arbitrum One 主网，验证用户提交的 txHash 真实性。防作弊核心。

import {
  createPublicClient,
  http,
  parseAbiItem,
  decodeEventLog,
  isAddressEqual,
  getEventSelector,
  type Hex,
} from "viem";
import { arbitrum } from "viem/chains";
import { getTreasuryAddress, getUsdcAddress } from "@/lib/contracts/config";

/** Arbitrum One chainId */
export const ARBITRUM_CHAIN_ID = 42161;

/** 金库 EOA（Arbitrum 主网，预启动阶段） */
export const TREASURY_EOA: Hex = "0x973B213023bdAfa8cD4a895e4dE748d2503E7137";

/** USDC（Arbitrum 主网，Circle 官方，6 decimals） */
export const USDC_ADDRESS: Hex = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831";

/** 最低捐款额（USDC） */
export const MIN_DONATION_USDC = 10;
const USDC_DECIMALS = 6;

/** ERC20 Transfer 事件 */
const TRANSFER_EVENT = parseAbiItem(
  "event Transfer(address indexed from, address indexed to, uint256 value)"
);
/** Transfer 事件 topic0 */
const TRANSFER_TOPIC = getEventSelector(TRANSFER_EVENT);

export interface VerifiedDonation {
  valid: boolean;
  reason?: string;
  donorAddress?: Hex;
  amountUsdc?: number;
  blockNumber?: bigint;
  /** 区块时间戳（unix 秒） */
  timestamp?: number;
}

/**
 * 验证一笔 tx 是否为有效的 USDC 捐款到金库 EOA。
 *
 * 检查项：
 *   1. tx 存在且成功（receipt.status === 'success'）
 *   2. 通过 arbitrum 客户端查询，隐式保证 chainId === 42161
 *   3. 包含 USDC Transfer 事件，且 to === TREASURY_EOA
 *   4. Transfer.from === 声称的 donor（忽略大小写）
 *   5. amount >= $10（USDC 6 decimals）
 *
 * RPC：优先 process.env.ARBITRUM_RPC_URL，否则使用公共 https://arb1.arbitrum.io/rpc
 *
 * 失败时返回 { valid: false, reason }，每种失败原因不同。
 */
export async function verifyDonationTx(
  txHash: string,
  claimedDonor: string
): Promise<VerifiedDonation> {
  const rpcUrl = process.env.ARBITRUM_RPC_URL ?? "https://arb1.arbitrum.io/rpc";
  const client = createPublicClient({
    chain: arbitrum,
    transport: http(rpcUrl),
  });

  const treasury = getTreasuryAddress(ARBITRUM_CHAIN_ID) ?? TREASURY_EOA;
  const usdc = getUsdcAddress(ARBITRUM_CHAIN_ID) ?? USDC_ADDRESS;
  const donor = claimedDonor.toLowerCase() as Hex;
  const hash = txHash.toLowerCase() as Hex;

  // 1. 拉取 receipt
  let receipt;
  try {
    receipt = await client.getTransactionReceipt({ hash });
  } catch {
    return { valid: false, reason: "Transaction not found on Arbitrum One" };
  }

  // 2. 校验成功
  if (receipt.status !== "success") {
    return { valid: false, reason: "Transaction reverted on-chain" };
  }

  // 3. 在 logs 中查找 USDC Transfer 到金库的事件
  let transferFrom: Hex | null = null;
  let transferValue = 0n;
  for (const log of receipt.logs) {
    if (log.topics[0] !== TRANSFER_TOPIC) continue;
    if (!isAddressEqual(log.address, usdc)) continue;

    let decoded;
    try {
      decoded = decodeEventLog({
        abi: [TRANSFER_EVENT],
        topics: log.topics,
        data: log.data,
      });
    } catch {
      continue;
    }
    if (decoded.eventName !== "Transfer") continue;

    const args = decoded.args as { from: Hex; to: Hex; value: bigint };
    if (!isAddressEqual(args.to, treasury)) continue; // 不是转给金库
    transferFrom = args.from;
    transferValue = args.value;
    break;
  }

  if (transferFrom === null) {
    return {
      valid: false,
      reason: "No USDC transfer to the treasury EOA found in this transaction",
    };
  }

  // 4. 校验 from === claimedDonor
  if (!isAddressEqual(transferFrom, donor)) {
    return {
      valid: false,
      reason: "Transaction sender does not match the claimed donor address",
    };
  }

  // 5. 校验金额 >= $10
  const amountUsdc = Number(transferValue) / 10 ** USDC_DECIMALS;
  if (amountUsdc < MIN_DONATION_USDC) {
    return {
      valid: false,
      reason: `Donation amount ${amountUsdc} USDC is below the $${MIN_DONATION_USDC} minimum`,
    };
  }

  // 6. 取区块时间戳
  let timestamp: number;
  try {
    const block = await client.getBlock({ blockNumber: receipt.blockNumber });
    timestamp = Number(block.timestamp);
  } catch {
    return { valid: false, reason: "Failed to fetch block timestamp" };
  }

  return {
    valid: true,
    donorAddress: transferFrom,
    amountUsdc,
    blockNumber: receipt.blockNumber,
    timestamp,
  };
}
