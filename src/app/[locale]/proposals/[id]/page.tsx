// SPDX-License-Identifier: Apache-2.0
import { notFound } from "next/navigation";
import { proposals } from "@/lib/data";

interface PageProps {
  params: Promise<{ id: string }>;
}

export async function generateStaticParams() {
  return proposals.map((p) => ({ id: p.id }));
}

export default async function Page({ params }: PageProps) {
  const { id } = await params;
  const proposal = proposals.find((p) => p.id === id);
  if (!proposal) notFound();

  const { ProposalDetailView } = await import(
    "@/components/proposals/ProposalDetailView"
  );
  return <ProposalDetailView proposalId={id} />;
}
