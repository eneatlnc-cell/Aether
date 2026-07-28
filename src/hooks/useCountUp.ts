"use client";
// SPDX-License-Identifier: Apache-2.0

import { useEffect, useRef, useState } from "react";

interface UseCountUpOptions {
  duration?: number;
  start?: boolean;
}

/**
 * 数字滚动递增动画 Hook
 * 用于仪表盘 KPI 数据加载时的渐进展示
 */
export function useCountUp(
  target: number,
  { duration = 1200, start = true }: UseCountUpOptions = {}
) {
  const [value, setValue] = useState(0);
  const fromRef = useRef(0);
  const rafRef = useRef<number | null>(null);

  useEffect(() => {
    if (!start) return;
    const from = fromRef.current;
    const startTime = performance.now();

    const tick = (now: number) => {
      const elapsed = now - startTime;
      const progress = Math.min(1, elapsed / duration);
      // easeOutCubic
      const eased = 1 - Math.pow(1 - progress, 3);
      const next = from + (target - from) * eased;
      setValue(next);
      if (progress < 1) {
        rafRef.current = requestAnimationFrame(tick);
      } else {
        fromRef.current = target;
      }
    };

    rafRef.current = requestAnimationFrame(tick);
    return () => {
      if (rafRef.current) cancelAnimationFrame(rafRef.current);
    };
  }, [target, duration, start]);

  return value;
}
