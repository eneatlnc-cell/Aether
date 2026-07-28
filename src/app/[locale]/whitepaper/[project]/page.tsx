// SPDX-License-Identifier: Apache-2.0
import { notFound } from "next/navigation";
import { projects, type ProjectId } from "@/lib/data";
import { WhitepaperView } from "@/components/whitepaper/WhitepaperView";

interface PageProps {
  params: Promise<{ project: string }>;
}

export async function generateStaticParams() {
  return projects.map((p) => ({ project: p.id }));
}

export default async function Page({ params }: PageProps) {
  const { project } = await params;
  if (!projects.find((p) => p.id === (project as ProjectId))) {
    notFound();
  }
  return <WhitepaperView projectId={project as ProjectId} />;
}
