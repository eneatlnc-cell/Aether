// SPDX-License-Identifier: Apache-2.0
// GET /api/citizens/[address]
// 查询某地址的公民身份与全部捐款记录。
//
// v3.6 安全加固（P4）：
//   - 限流：每 IP 60 次/分钟（读路径，阈值放宽）
//   - 500 响应不再回传 detail（错误细节只进服务端日志）

import { NextRequest, NextResponse } from "next/server";
import {
  ensureSchema,
  getCitizenByAddress,
  getDonationsByDonor,
  ringTierLabel,
} from "@/lib/db";
import { rateLimit, clientIpFromHeaders, tooManyRequests } from "@/lib/rateLimit";

const ADDRESS_RE = /^0x[a-fA-F0-9]{40}$/;

/** 每 IP 每分钟最大查询请求数 */
const RATE_LIMIT = 60;
const RATE_WINDOW_MS = 60_000;

/**
 * 查询公民身份。
 *
 * 路径参数：address（0x + 40 hex）
 *
 * 响应：
 * {
 *   citizen: {
 *     address, ringId, ringTier, ringTierLabel, isActive,
 *     firstDonationAt, totalDonatedUsdc, donationCount, nickname, bio
 *   },
 *   donations: [ { txHash, amountUsdc, timestamp, purpose, chainId } ]
 * }
 *
 * 状态码：200 找到；400 参数错误；404 不是公民；500 数据库错误。
 */
export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ address: string }> }
) {
  // 限流（读路径，阈值放宽）
  const ip = clientIpFromHeaders(req.headers);
  const rl = rateLimit(`citizens:${ip}`, RATE_LIMIT, RATE_WINDOW_MS);
  if (!rl.allowed) {
    return NextResponse.json(
      { error: "Too many requests; please retry after a minute" },
      tooManyRequests(rl.resetAt)
    );
  }

  const { address } = await params;

  if (!ADDRESS_RE.test(address)) {
    return NextResponse.json(
      { error: "Invalid address; expected 0x-prefixed 40 hex chars" },
      { status: 400 }
    );
  }

  try {
    await ensureSchema();
    const citizen = await getCitizenByAddress(address.toLowerCase());
    if (!citizen) {
      return NextResponse.json(
        { error: "No citizen found for this address" },
        { status: 404 }
      );
    }
    const donations = await getDonationsByDonor(address.toLowerCase());

    return NextResponse.json({
      citizen: {
        address: citizen.address,
        ringId: citizen.ring_id,
        ringTier: citizen.ring_tier,
        ringTierLabel: ringTierLabel(citizen.ring_tier),
        isActive: citizen.is_active,
        firstDonationAt: citizen.first_donation_at,
        totalDonatedUsdc: Number(citizen.total_donated_usdc),
        donationCount: citizen.donation_count,
        nickname: citizen.nickname,
        bio: citizen.bio,
      },
      donations: donations.map((d) => ({
        txHash: d.tx_hash,
        amountUsdc: Number(d.amount_usdc),
        timestamp: d.tx_timestamp,
        purpose: d.purpose,
        // v3.6：透传链 ID，前端据此切换 bscscan 主网/测试网域名
        chainId: d.chain_id,
      })),
    });
  } catch (err) {
    // 细节只进服务端日志，不回传给客户端（防 SQL/连接串等信息泄露）
    console.error("[api/citizens] internal error:", err);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
