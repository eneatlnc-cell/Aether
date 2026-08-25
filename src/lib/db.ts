// SPDX-License-Identifier: Apache-2.0
// Aether DAO — 预启动阶段数据库层
// 使用 @vercel/postgres 的 `sql` 模板字符串；DATABASE_URL 由 Vercel 自动注入。
// 每次 API 调用应先 await ensureSchema()（幂等）。

import { sql } from "@vercel/postgres";
import { keccak256, toHex } from "viem";

/** 道环等级（预启动阶段只有公民身份一种） */
export const RING_TIER_CITIZEN = 1;

/**
 * 道环等级标签。
 */
export function ringTierLabel(tier: number): string {
  switch (tier) {
    case RING_TIER_CITIZEN:
      return "Citizen";
    default:
      return "Unknown";
  }
}

/** citizens 表行类型。NUMERIC / BIGINT 列默认以 string 返回。 */
export interface CitizenRow {
  address: string;
  ring_id: string;
  ring_tier: number;
  first_donation_at: Date;
  total_donated_usdc: string;
  donation_count: number;
  is_active: boolean;
  nickname: string | null;
  bio: string | null;
  updated_at: Date;
}

/** donations 表行类型。 */
export interface DonationRow {
  id: number;
  tx_hash: string;
  donor_address: string;
  amount_usdc: string;
  block_number: string;
  tx_timestamp: Date;
  purpose: string;
  ring_id: string | null;
  /** 交易所在链（v3.6 单链 BSC：56=主网，97=测试网） */
  chain_id: number;
  recorded_at: Date;
  migrated: boolean;
}

export interface RecordDonationInput {
  txHash: string;
  donorAddress: string;
  amountUsdc: number;
  /** 区块号 */
  blockNumber: bigint;
  /** 区块时间戳（unix 秒） */
  txTimestamp: number;
  purpose?: string;
  /** 交易所在链（56=BSC 主网，97=BSC 测试网） */
  chainId: number;
}

export interface RecordDonationResult {
  ringId: string;
  isFirstDonation: boolean;
  /** 命中已记录的 tx（并发或重复提交）时为 true */
  alreadyRecorded?: boolean;
  tier: number;
}

/**
 * 初始化数据库表（幂等）。
 * 在首次 API 调用时自动执行，或手动调用。
 */
export async function ensureSchema(): Promise<void> {
  await sql`
    CREATE TABLE IF NOT EXISTS citizens (
      address TEXT PRIMARY KEY,
      ring_id TEXT UNIQUE NOT NULL,
      ring_tier SMALLINT NOT NULL DEFAULT 1,
      first_donation_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      total_donated_usdc NUMERIC(20,6) NOT NULL DEFAULT 0,
      donation_count INTEGER NOT NULL DEFAULT 0,
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      nickname TEXT,
      bio TEXT,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `;
  await sql`
    CREATE TABLE IF NOT EXISTS donations (
      id SERIAL PRIMARY KEY,
      tx_hash TEXT UNIQUE NOT NULL,
      donor_address TEXT NOT NULL REFERENCES citizens(address),
      amount_usdc NUMERIC(20,6) NOT NULL,
      block_number BIGINT NOT NULL,
      tx_timestamp TIMESTAMPTZ NOT NULL,
      purpose TEXT NOT NULL DEFAULT 'unrestricted',
      ring_id TEXT,
      chain_id INTEGER NOT NULL DEFAULT 56,
      recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      migrated BOOLEAN NOT NULL DEFAULT FALSE
    )
  `;
  // v3.5 幂等迁移：为旧库补 chain_id 列
  // v3.6：默认值改为 56（BSC 主网）——Arbitrum 支持已移除，
  // 旧库中 42161 的历史行为预启动期测试数据，不影响 BSC 主网记账
  await sql`ALTER TABLE donations ADD COLUMN IF NOT EXISTS chain_id INTEGER NOT NULL DEFAULT 56`;
  await sql`CREATE INDEX IF NOT EXISTS idx_donations_donor ON donations(donor_address)`;
  await sql`CREATE INDEX IF NOT EXISTS idx_donations_tx ON donations(tx_hash)`;
  await sql`CREATE INDEX IF NOT EXISTS idx_donations_chain ON donations(chain_id)`;
}

/**
 * 生成道环 ID：keccak256(donorAddress + txHash + timestamp)。
 * 返回 0x 开头 64 位 hex。
 */
function generateRingId(
  donorAddress: string,
  txHash: string,
  timestamp: number
): string {
  return keccak256(toHex(`${donorAddress}${txHash}${timestamp}`));
}

/**
 * 查询单个公民。不存在返回 null。
 */
export async function getCitizenByAddress(
  address: string
): Promise<CitizenRow | null> {
  const { rows } = await sql<CitizenRow>`
    SELECT * FROM citizens WHERE address = ${address.toLowerCase()}
  `;
  return rows[0] ?? null;
}

/**
 * 查询或创建公民。
 *
 * 注意：ring_id 列为 NOT NULL，且本函数不自动生成 ring_id（由 recordDonation 生成），
 * 因此创建新公民时必须由调用方传入 ringId。若公民已存在，传入的 ringId 会被忽略，
 * 返回既有公民（含其原始 ring_id）。
 */
export async function getOrCreateCitizen(
  address: string,
  ringId: string
): Promise<CitizenRow> {
  const addr = address.toLowerCase();
  await sql`
    INSERT INTO citizens (address, ring_id, ring_tier, total_donated_usdc, donation_count, first_donation_at, updated_at)
    VALUES (${addr}, ${ringId}, ${RING_TIER_CITIZEN}, 0, 0, NOW(), NOW())
    ON CONFLICT (address) DO NOTHING
  `;
  const citizen = await getCitizenByAddress(addr);
  if (!citizen) {
    throw new Error(`Failed to get or create citizen for ${addr}`);
  }
  return citizen;
}

/**
 * 查询某地址的所有捐款记录（按链上时间正序）。
 */
export async function getDonationsByDonor(
  address: string
): Promise<DonationRow[]> {
  const { rows } = await sql<DonationRow>`
    SELECT * FROM donations WHERE donor_address = ${address.toLowerCase()}
    ORDER BY tx_timestamp ASC
  `;
  return rows;
}

/**
 * 按 tx_hash 查询单笔捐款（防重复提交）。不存在返回 null。
 */
export async function getDonationByTxHash(
  txHash: string
): Promise<DonationRow | null> {
  const { rows } = await sql<DonationRow>`
    SELECT * FROM donations WHERE tx_hash = ${txHash.toLowerCase()}
  `;
  return rows[0] ?? null;
}

/**
 * 核心函数：记录一笔捐款 + 更新公民统计 + 首次捐款时确定 ring_id。
 *
 * 流程：
 *   1. 由 (donorAddress, txHash, txTimestamp) 生成 ring_id
 *   2. 幂等创建公民（写入 ring_id；已存在则保留原 ring_id）
 *   3. 幂等写入捐款（tx_hash 唯一）；若该 tx 已存在则返回 alreadyRecorded
 *   4. 累加公民统计（总额、次数）；isFirstDonation = 累加后次数 === 1
 *
 * @returns ringId（公民当前道环 ID）、isFirstDonation、tier
 */
export async function recordDonation(
  input: RecordDonationInput
): Promise<RecordDonationResult> {
  const addr = input.donorAddress.toLowerCase();
  const txHash = input.txHash.toLowerCase();
  const purpose = input.purpose ?? "unrestricted";
  const blockNum = Number(input.blockNumber); // BIGINT 列；BSC 区块号在安全范围内
  const txIso = new Date(input.txTimestamp * 1000).toISOString();

  const ringId = generateRingId(addr, txHash, input.txTimestamp);

  // 1. 确保公民存在（首次创建时写入 ring_id；已存在则忽略）
  await getOrCreateCitizen(addr, ringId);
  const citizen = await getCitizenByAddress(addr);
  const canonicalRingId = citizen!.ring_id;

  // 2. 幂等写入捐款（donations.donor_address 有 FK → 必须先有公民；chain_id 记录所在链）
  const { rows } = await sql<{ id: number }>`
    INSERT INTO donations (tx_hash, donor_address, amount_usdc, block_number, tx_timestamp, purpose, ring_id, chain_id)
    VALUES (${txHash}, ${addr}, ${input.amountUsdc}, ${blockNum}, ${txIso}, ${purpose}, ${canonicalRingId}, ${input.chainId})
    ON CONFLICT (tx_hash) DO NOTHING
    RETURNING id
  `;
  if (rows.length === 0) {
    // 该 tx 已被记录（并发或重复请求），不重复累加
    return {
      ringId: canonicalRingId,
      isFirstDonation: false,
      alreadyRecorded: true,
      tier: RING_TIER_CITIZEN,
    };
  }

  // 3. 累加公民统计
  const { rows: updRows } = await sql<{ donation_count: number }>`
    UPDATE citizens
    SET total_donated_usdc = total_donated_usdc + ${input.amountUsdc},
        donation_count = donation_count + 1,
        updated_at = NOW()
    WHERE address = ${addr}
    RETURNING donation_count
  `;
  const isFirstDonation = (updRows[0]?.donation_count ?? 0) === 1;

  return {
    ringId: canonicalRingId,
    isFirstDonation,
    tier: RING_TIER_CITIZEN,
  };
}

/**
 * 统计当前活跃公民总数。
 */
export async function getTotalCitizens(): Promise<number> {
  const { rows } = await sql<{ count: number }>`
    SELECT COUNT(*)::int AS count FROM citizens WHERE is_active = TRUE
  `;
  return rows[0]?.count ?? 0;
}

/**
 * 统计所有活跃公民累计捐款总额（USD）。
 */
export async function getTotalDonationsUsd(): Promise<number> {
  const { rows } = await sql<{ total: string }>`
    SELECT COALESCE(SUM(total_donated_usdc), 0) AS total
    FROM citizens WHERE is_active = TRUE
  `;
  return Number(rows[0]?.total ?? 0);
}
