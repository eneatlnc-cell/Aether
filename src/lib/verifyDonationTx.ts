// SPDX-License-Identifier: Apache-2.0
// Aether DAO — 链上捐款 tx 验证
// 用 viem 按请求声明的 chainId 读取对应网络，验证用户提交的 txHash 真实性。防作弊核心。
//
// v3.6（单链 BSC）：目标主网为 BNB Smart Chain（56）。
//   - verifyDonationTx(txHash, claimedDonor, chainId) 必须显式传 chainId
//   - 金库 / 稳定币地址与 decimals 均从 config 按链解析
//     （BSC Binance-Peg USDC/USDT 为 18 decimals）
//   - Arbitrum 支持已移除（早期仅作测试链使用，从未部署主网）

import {
  createPublicClient,
  http,
  parseAbiItem,
  decodeEventLog,
  isAddressEqual,
  getEventSelector,
  formatUnits,
  type Hex,
  type Chain,
} from "viem";
import { bsc, bscTestnet } from "viem/chains";
import {
  getStablecoin,
  getTreasuryAddress,
  getNetworkLabel,
  CHAIN_IDS,
} from "@/lib/contracts/config";

/** 支持捐款验证的链（服务端白名单） */
export const SUPPORTED_CHAIN_IDS = [
  CHAIN_IDS.bsc, // 56  BNB Smart Chain（唯一目标主网）
  CHAIN_IDS.bscTestnet, // 97  BSC 测试网
] as const;

export type SupportedChainId = (typeof SUPPORTED_CHAIN_IDS)[number];

/** 目标主网：BNB Smart Chain chainId */
export const BSC_CHAIN_ID = CHAIN_IDS.bsc;

/** 最低捐款额（整数美元部分，与合约 MIN_DONATION_WHOLE_USD 一致） */
export const MIN_DONATION_USDC = 10;

/** 各链的 viem Chain 定义、默认公共 RPC 与 RPC 环境变量名 */
const CHAIN_CONFIG: Record<number, { chain: Chain; defaultRpc: string; rpcEnv: string }> = {
  [CHAIN_IDS.bsc]: {
    chain: bsc,
    defaultRpc: "https://bsc-dataseed.binance.org",
    rpcEnv: "BSC_RPC_URL",
  },
  [CHAIN_IDS.bscTestnet]: {
    chain: bscTestnet,
    defaultRpc: "https://data-seed-prebsc-1-s1.binance.org:8545",
    rpcEnv: "BSC_TESTNET_RPC_URL",
  },
};

/** ERC20 Transfer 事件 */
const TRANSFER_EVENT = parseAbiItem(
  "event Transfer(address indexed from, address indexed to, uint256 value)"
);
/** Transfer 事件 topic0 */
const TRANSFER_TOPIC = getEventSelector(TRANSFER_EVENT);

export interface VerifiedDonation {
  valid: boolean;
  reason?: string;
  /** 验证所针对的 chainId（回显，入库用） */
  chainId?: number;
  donorAddress?: Hex;
  amountUsdc?: number;
  blockNumber?: bigint;
  /** 区块时间戳（unix 秒） */
  timestamp?: number;
}

/** 校验 chainId 是否在支持白名单内 */
export function isSupportedChain(chainId: unknown): chainId is SupportedChainId {
  return (
    typeof chainId === "number" &&
    Number.isInteger(chainId) &&
    (SUPPORTED_CHAIN_IDS as readonly number[]).includes(chainId)
  );
}

/**
 * 验证一笔 tx 是否为有效的稳定币捐款到金库地址。
 *
 * @param txHash        链上交易哈希
 * @param claimedDonor  声称的捐款人地址
 * @param chainId       交易所在链（必须在 SUPPORTED_CHAIN_IDS 内）
 *
 * 检查项：
 *   1. chainId 在服务端白名单内
 *   2. tx 存在且成功（receipt.status === 'success'）
 *   3. 包含稳定币 Transfer 事件，且 to === 金库地址（treasury）
 *   4. Transfer.from === 声称的 donor（忽略大小写）
 *   5. amount >= $10（按该链稳定币 decimals 换算）
 *
 * RPC：优先 process.env.<RPC_ENV>（如 BSC_RPC_URL），
 *      否则使用各链公共 RPC。
 *
 * 失败时返回 { valid: false, reason }，每种失败原因不同。
 */
export async function verifyDonationTx(
  txHash: string,
  claimedDonor: string,
  chainId: number
): Promise<VerifiedDonation> {
  const cfg = CHAIN_CONFIG[chainId];
  if (!cfg) {
    return {
      valid: false,
      reason: `Unsupported chainId ${chainId}; supported: ${SUPPORTED_CHAIN_IDS.join(", ")}`,
    };
  }
  const networkName = getNetworkLabel(chainId);

  // 金库与稳定币配置必须齐备（无硬编码默认金库，未配置即拒绝）
  const treasury = getTreasuryAddress(chainId);
  const stablecoin = getStablecoin(chainId);
  if (!treasury || !stablecoin) {
    return {
      valid: false,
      chainId,
      reason: `Treasury or stablecoin not configured for ${networkName} (chainId ${chainId})`,
    };
  }

  const rpcUrl = process.env[cfg.rpcEnv] ?? cfg.defaultRpc;
  const client = createPublicClient({
    chain: cfg.chain,
    transport: http(rpcUrl),
  });

  const donor = claimedDonor.toLowerCase() as Hex;
  const hash = txHash.toLowerCase() as Hex;

  // 1. 拉取 receipt
  let receipt;
  try {
    receipt = await client.getTransactionReceipt({ hash });
  } catch {
    return { valid: false, chainId, reason: `Transaction not found on ${networkName}` };
  }

  // 2. 校验成功
  if (receipt.status !== "success") {
    return { valid: false, chainId, reason: "Transaction reverted on-chain" };
  }

  // 3. 在 logs 中查找稳定币 Transfer 到金库的事件
  let transferFrom: Hex | null = null;
  let transferValue = 0n;
  for (const log of receipt.logs) {
    if (log.topics[0] !== TRANSFER_TOPIC) continue;
    if (!isAddressEqual(log.address, stablecoin.address)) continue;

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
      chainId,
      reason: `No ${stablecoin.symbol} transfer to the treasury found in this transaction on ${networkName}`,
    };
  }

  // 4. 校验 from === claimedDonor
  if (!isAddressEqual(transferFrom, donor)) {
    return {
      valid: false,
      chainId,
      reason: "Transaction sender does not match the claimed donor address",
    };
  }

  // 5. 校验金额 >= $10（按该链稳定币精度换算）
  //    viem formatUnits：字符串精确换算，避免 18 decimals 大数先过 Number 丢精度
  const amountUsdc = Number(formatUnits(transferValue, stablecoin.decimals));
  if (amountUsdc < MIN_DONATION_USDC) {
    return {
      valid: false,
      chainId,
      reason: `Donation amount ${amountUsdc} ${stablecoin.symbol} is below the $${MIN_DONATION_USDC} minimum`,
    };
  }

  // 6. 取区块时间戳
  let timestamp: number;
  try {
    const block = await client.getBlock({ blockNumber: receipt.blockNumber });
    timestamp = Number(block.timestamp);
  } catch {
    return { valid: false, chainId, reason: "Failed to fetch block timestamp" };
  }

  return {
    valid: true,
    chainId,
    donorAddress: transferFrom,
    amountUsdc,
    blockNumber: receipt.blockNumber,
    timestamp,
  };
}
