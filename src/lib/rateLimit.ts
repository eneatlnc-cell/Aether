// SPDX-License-Identifier: Apache-2.0
// Aether DAO — 轻量内存限流（固定窗口计数）
//
// 适用范围与局限（务必阅读）：
//   - Vercel serverless 为多实例部署，本实现按"实例内"计数：
//     能挡住单实例上的高频刷请求（脚本轰炸、重试风暴），属最佳努力兜底。
//   - 跨实例精确限流需要共享存储（Upstash Redis）或平台层（Vercel WAF），
//     预启动阶段流量极低，暂不引入。
//
// 用法：
//   const rl = rateLimit(`record:${ip}`, 10, 60_000);
//   if (!rl.allowed) return 429 + Retry-After;

export interface RateLimitResult {
  allowed: boolean;
  /** 窗口内允许的最大请求数 */
  limit: number;
  /** 本窗口剩余额度 */
  remaining: number;
  /** 窗口重置时间（epoch ms） */
  resetAt: number;
}

/** 实例内计数桶：key → {count, resetAt} */
const buckets = new Map<string, { count: number; resetAt: number }>();

/** 防内存膨胀：超过该键数强制清扫过期桶 */
const MAX_KEYS = 10_000;

let lastSweep = 0;

/**
 * 固定窗口限流。窗口内第 limit+1 次请求开始拒绝。
 *
 * @param key      限流键（建议 `"<路由>:<ip>"`）
 * @param limit    窗口内允许的最大请求数
 * @param windowMs 窗口长度（毫秒）
 */
export function rateLimit(
  key: string,
  limit: number,
  windowMs: number
): RateLimitResult {
  const now = Date.now();

  // 周期性（或键数超限时）清扫过期桶，避免 Map 无界增长
  if (now - lastSweep > windowMs || buckets.size > MAX_KEYS) {
    sweep(now);
  }

  let bucket = buckets.get(key);
  if (!bucket || bucket.resetAt <= now) {
    bucket = { count: 0, resetAt: now + windowMs };
    buckets.set(key, bucket);
  }
  bucket.count += 1;

  return {
    allowed: bucket.count <= limit,
    limit,
    remaining: Math.max(0, limit - bucket.count),
    resetAt: bucket.resetAt,
  };
}

function sweep(now: number): void {
  lastSweep = now;
  for (const [key, bucket] of buckets) {
    if (bucket.resetAt <= now) buckets.delete(key);
  }
}

/**
 * 从请求头解析客户端 IP（Vercel 会注入 x-forwarded-for）。
 * 解析失败返回 "unknown"（所有未知来源共享一个桶，仍可兜底防刷）。
 */
export function clientIpFromHeaders(headers: Headers): string {
  const forwarded = headers.get("x-forwarded-for");
  if (forwarded) {
    const first = forwarded.split(",")[0]?.trim();
    if (first) return first;
  }
  return headers.get("x-real-ip")?.trim() || "unknown";
}

/**
 * 构造 429 响应（含 Retry-After 秒数，取 ≥1 避免 0）。
 */
export function tooManyRequests(resetAt: number): ResponseInit {
  const retryAfter = Math.max(1, Math.ceil((resetAt - Date.now()) / 1000));
  return {
    status: 429,
    headers: { "Retry-After": String(retryAfter) },
  };
}
