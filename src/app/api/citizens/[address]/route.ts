// GET /api/citizens/[address]
// 查询某地址的公民身份与全部捐款记录。

import { NextRequest, NextResponse } from "next/server";
import {
  ensureSchema,
  getCitizenByAddress,
  getDonationsByDonor,
  ringTierLabel,
} from "@/lib/db";

const ADDRESS_RE = /^0x[a-fA-F0-9]{40}$/;

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
 *   donations: [ { txHash, amountUsdc, timestamp, purpose } ]
 * }
 *
 * 状态码：200 找到；400 参数错误；404 不是公民；500 数据库错误。
 */
export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ address: string }> }
) {
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
      })),
    });
  } catch (err) {
    return NextResponse.json(
      { error: "Internal server error", detail: String(err) },
      { status: 500 }
    );
  }
}
