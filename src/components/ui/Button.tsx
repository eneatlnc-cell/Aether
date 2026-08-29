"use client";
// SPDX-License-Identifier: Apache-2.0

import { type ButtonHTMLAttributes, type ReactNode } from "react";

type Variant = "accent" | "outline" | "ghost";

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  children: ReactNode;
}

const variantClass: Record<Variant, string> = {
  accent:
    "bg-accent text-white hover:bg-accent/90 disabled:opacity-60 disabled:hover:bg-accent",
  outline:
    "border border-accent text-accent hover:bg-accent/5 disabled:opacity-60",
  ghost: "text-ink hover:bg-bg disabled:opacity-60",
};

export function Button({
  variant = "accent",
  className = "",
  children,
  ...rest
}: ButtonProps) {
  return (
    <button
      className={`inline-flex items-center justify-center gap-2 px-4 py-2 rounded-[8px] text-sm font-medium transition-colors disabled:cursor-not-allowed ${variantClass[variant]} ${className}`}
      {...rest}
    >
      {children}
    </button>
  );
}
