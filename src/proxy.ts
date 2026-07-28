// SPDX-License-Identifier: Apache-2.0
import createMiddleware from "next-intl/middleware";
import type { NextRequest } from "next/server";
import { routing } from "./i18n/routing";

// Next.js 16: middleware 改名为 proxy
const handleI18n = createMiddleware(routing);

export function proxy(request: NextRequest) {
  return handleI18n(request);
}

export const config = {
  matcher: ["/((?!api|_next|_vercel|.*\\..*).*)"],
};
