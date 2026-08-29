// SPDX-License-Identifier: Apache-2.0
// POST /api/donations/record
// 记录一笔链上已确认的 USDC 捐款，并（首次捐款时）生成模拟道环 ID。
//
// v3.6 安全加固（P4）：
//   - 限流：每 IP 10 次/分钟（实例内固定窗口，详见 lib/rateLimit.ts）
//   - purpose 白名单 + 长度上限（防任意字符串写入数据库/回显）
//   - 时间窗口校验：拒绝未来区块（容忍 5 分钟时钟偏差）与超 30 天的旧交易
//   - 500 响应不再回传 detail（错误细节只进服务端日志，防内部信息泄露）

import { NextRequest, NextResponse } from "next/server";
import {
  ensureSchema,
  getDonationByTxHash,
  recordDonation,
} from "@/lib/db";
import { verifyDonationTx, isSupportedChain, SUPPORTED_CHAIN_IDS } from "@/lib/verifyDonationTx";
import { rateLimit, clientIpFromHeaders, tooManyRequests } from "@/lib/rateLimit";

const TX_HASH_RE = /^0x[a-fA-F0-9]{64}$/;
const ADDRESS_RE = /^0x[a-fA-F0-9]{40}$/;

/**
 * 捐款用途白名单。与前端资金流向/影响力页的项目 ID 一一对应
 * （src/lib/data.ts 的 ProjectId 联合类型）。
 * 未传或空串 → 默认 unrestricted；白名单外的值一律 400。
 */
const ALLOWED_PURPOSES: ReadonlySet<string> = new Set([
  "unrestricted",
  "ai-framework",
  "self-organizing-net",
]);

/** purpose 长度上限（白名单已限定取值，此处为纵深防御） */
const MAX_PURPOSE_LENGTH = 64;

/** 允许的区块时间偏差（秒）：拒绝"来自未来"的交易，容忍 RPC/本地时钟漂移 */
const FUTURE_TOLERANCE_SECONDS = 5 * 60;

/** 交易最大年龄（秒）：拒绝过老的交易回灌历史数据 */
const MAX_TX_AGE_SECONDS = 30 * 24 * 60 * 60;

/** 每 IP 每分钟最大记录请求数 */
const RATE_LIMIT = 10;
const RATE_WINDOW_MS = 60_000;

/**
 * 记录捐款。
 *
 * 请求体：{ txHash: string, donorAddress: string, chainId: number, purpose?: string }
 *
 * 流程：
 *   0. 限流（每 IP 10 次/分钟）
 *   1. 入参校验（txHash 0x+64 hex，donorAddress 0x+40 hex，chainId 白名单，purpose 白名单）
 *   2. 幂等检查：tx_hash 已记录 → 409 + 已有记录
 *   3. 链上 tx 验证（verifyDonationTx，按 chainId 选网；金库/稳定币/精度按链解析）
 *   4. 时间窗口校验（未来区块 / 超 30 天旧交易 → 400）
 *   5. 验证失败 → 400 + reason
 *   6. 入库（recordDonation，含 chain_id；首次捐款生成 ring_id）
 *   7. 返回 200 + { ringId, donorAddress, amountUsdc, chainId, tier, isFirstDonation }
 *
 * 状态码：200 成功；400 参数/验证失败；409 已记录（返回已有数据）；
 *         429 限流；500 数据库错误（不回传细节）。
 */
export async function POST(req: NextRequest) {
  // 0. 限流（写路径，阈值收紧）
  const ip = clientIpFromHeaders(req.headers);
  const rl = rateLimit(`donations:record:${ip}`, RATE_LIMIT, RATE_WINDOW_MS);
  if (!rl.allowed) {
    return NextResponse.json(
      { error: "Too many requests; please retry after a minute" },
      tooManyRequests(rl.resetAt)
    );
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json(
      { error: "Invalid JSON body" },
      { status: 400 }
    );
  }

  const { txHash, donorAddress, chainId, purpose } = (body ?? {}) as {
    txHash?: unknown;
    donorAddress?: unknown;
    chainId?: unknown;
    purpose?: unknown;
  };

  if (typeof txHash !== "string" || !TX_HASH_RE.test(txHash)) {
    return NextResponse.json(
      { error: "Invalid txHash; expected 0x-prefixed 64 hex chars" },
      { status: 400 }
    );
  }
  if (typeof donorAddress !== "string" || !ADDRESS_RE.test(donorAddress)) {
    return NextResponse.json(
      { error: "Invalid donorAddress; expected 0x-prefixed 40 hex chars" },
      { status: 400 }
    );
  }
  if (!isSupportedChain(chainId)) {
    return NextResponse.json(
      {
        error: `Invalid or missing chainId; expected one of [${SUPPORTED_CHAIN_IDS.join(
          ", "
        )}] (target mainnet: 56 BNB Smart Chain)`,
      },
      { status: 400 }
    );
  }

  // purpose：未传/空 → 默认 unrestricted；白名单外或超长 → 400
  const purposeStr =
    typeof purpose === "string" && purpose.length > 0 ? purpose : "unrestricted";
  if (purposeStr.length > MAX_PURPOSE_LENGTH || !ALLOWED_PURPOSES.has(purposeStr)) {
    return NextResponse.json(
      {
        error: `Invalid purpose; allowed values: ${Array.from(ALLOWED_PURPOSES).join(
          ", "
        )}`,
      },
      { status: 400 }
    );
  }

  try {
    await ensureSchema();

    // 幂等：tx_hash 已记录则直接返回已有数据
    const existing = await getDonationByTxHash(txHash.toLowerCase());
    if (existing) {
      return NextResponse.json(
        {
          alreadyRecorded: true,
          txHash: existing.tx_hash,
          donorAddress: existing.donor_address,
          amountUsdc: Number(existing.amount_usdc),
          chainId: existing.chain_id,
          ringId: existing.ring_id,
          purpose: existing.purpose,
        },
        { status: 409 }
      );
    }

    // 链上验证（按声明的 chainId 选网）
    const verified = await verifyDonationTx(txHash, donorAddress, chainId);
    if (!verified.valid) {
      return NextResponse.json(
        { error: verified.reason ?? "Donation verification failed" },
        { status: 400 }
      );
    }

    // 时间窗口：区块时间不得来自未来（容忍时钟偏差）或早于 30 天前
    const txTimestamp = verified.timestamp!;
    const now = Math.floor(Date.now() / 1000);
    if (txTimestamp > now + FUTURE_TOLERANCE_SECONDS) {
      return NextResponse.json(
        { error: "Transaction timestamp is in the future; please retry shortly" },
        { status: 400 }
      );
    }
    if (now - txTimestamp > MAX_TX_AGE_SECONDS) {
      return NextResponse.json(
        { error: "Transaction is older than 30 days and can no longer be recorded" },
        { status: 400 }
      );
    }

    // 入库
    const result = await recordDonation({
      txHash: txHash.toLowerCase(),
      donorAddress: donorAddress.toLowerCase(),
      amountUsdc: verified.amountUsdc!,
      blockNumber: verified.blockNumber!,
      txTimestamp,
      purpose: purposeStr,
      chainId,
    });

    return NextResponse.json(
      {
        ringId: result.ringId,
        donorAddress: donorAddress.toLowerCase(),
        amountUsdc: verified.amountUsdc,
        chainId,
        tier: result.tier,
        isFirstDonation: result.isFirstDonation,
      },
      { status: 200 }
    );
  } catch (err) {
    // 细节只进服务端日志，不回传给客户端（防 SQL/连接串等信息泄露）
    console.error("[api/donations/record] internal error:", err);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
