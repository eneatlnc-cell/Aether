"use client";
// SPDX-License-Identifier: Apache-2.0

import { useState } from "react";
import { Check, Copy } from "lucide-react";
import { useToast } from "./Toast";

interface AddressCopyProps {
  address: string;
  className?: string;
  label?: string;
}

export function AddressCopy({ address, className = "", label }: AddressCopyProps) {
  const [copied, setCopied] = useState(false);
  const { push } = useToast();

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(address);
      setCopied(true);
      push(label ?? "Copied", "success");
      setTimeout(() => setCopied(false), 2000);
    } catch {
      push("Copy failed", "info");
    }
  };

  const short = `${address.slice(0, 6)}…${address.slice(-4)}`;

  return (
    <button
      onClick={handleCopy}
      className={`inline-flex items-center gap-2 font-mono text-sm text-ink hover:text-accent transition-colors ${className}`}
      title={address}
    >
      <span>{short}</span>
      {copied ? <Check size={14} /> : <Copy size={14} />}
    </button>
  );
}
