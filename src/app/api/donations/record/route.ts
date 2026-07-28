// POST /api/donations/record
// 记录一笔链上已确认的 USDC 捐款，并（首次捐款时）生成模拟道环 ID。

import { NextRequest, NextResponse } from "next/server";
import {
  ensureSchema,
  getDonationByTxHash,
  recordDonation,
} from "@/lib/db";
import { verifyDonationTx } from "@/lib/verifyDonationTx";

const TX_HASH_RE = /^0x[a-fA-F0-9]{64}$/;
const ADDRESS_RE = /^0x[a-fA-F0-9]{40}$/;

/**
 * 记录捐款。
 *
 * 请求体：{ txHash: string, donorAddress: string, purpose?: string }
 *
 * 流程：
 *   1. 入参校验（txHash 0x+64 hex，donorAddress 0x+40 hex）
 *   2. 幂等检查：tx_hash 已记录 → 409 + 已有记录
 *   3. 链上 tx 验证（verifyDonationTx）
 *   4. 验证失败 → 400 + reason
 *   5. 入库（recordDonation，首次捐款生成 ring_id）
 *   6. 返回 200 + { ringId, donorAddress, amountUsdc, tier, isFirstDonation }
 *
 * 状态码：200 成功；400 参数/验证失败；409 已记录（返回已有数据）；500 数据库错误。
 */
export async function POST(req: NextRequest) {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json(
      { error: "Invalid JSON body" },
      { status: 400 }
    );
  }

  const { txHash, donorAddress, purpose } = (body ?? {}) as {
    txHash?: unknown;
    donorAddress?: unknown;
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
  const purposeStr =
    typeof purpose === "string" && purpose.length > 0 ? purpose : "unrestricted";

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
          ringId: existing.ring_id,
          purpose: existing.purpose,
        },
        { status: 409 }
      );
    }

    // 链上验证
    const verified = await verifyDonationTx(txHash, donorAddress);
    if (!verified.valid) {
      return NextResponse.json(
        { error: verified.reason ?? "Donation verification failed" },
        { status: 400 }
      );
    }

    // 入库
    const result = await recordDonation({
      txHash: txHash.toLowerCase(),
      donorAddress: donorAddress.toLowerCase(),
      amountUsdc: verified.amountUsdc!,
      blockNumber: verified.blockNumber!,
      txTimestamp: verified.timestamp!,
      purpose: purposeStr,
    });

    return NextResponse.json(
      {
        ringId: result.ringId,
        donorAddress: donorAddress.toLowerCase(),
        amountUsdc: verified.amountUsdc,
        tier: result.tier,
        isFirstDonation: result.isFirstDonation,
      },
      { status: 200 }
    );
  } catch (err) {
    return NextResponse.json(
      { error: "Internal server error", detail: String(err) },
      { status: 500 }
    );
  }
}
