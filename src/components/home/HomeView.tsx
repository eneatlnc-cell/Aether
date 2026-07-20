import { Navbar } from "@/components/home/Navbar";
import { Footer } from "@/components/home/Footer";
import { Hero } from "@/components/home/Hero";
import { FlagshipProjects } from "@/components/home/FlagshipProjects";
import { FundFlowDashboard } from "@/components/home/fundflow/FundFlowDashboard";
import { ProposalFeed } from "@/components/home/ProposalFeed";
import { CouncilPreview } from "@/components/home/CouncilPreview";

export function HomeView() {
  return (
    <>
      <Navbar />
      <main className="flex-1">
        <Hero />
        <FlagshipProjects />
        <FundFlowDashboard />

        {/* 提案 + 理事会 */}
        <section className="py-16 sm:py-20 px-6 lg:px-8">
          <div className="max-w-[1280px] mx-auto grid grid-cols-1 md:grid-cols-3 gap-8 lg:gap-12">
            <ProposalFeed />
            <CouncilPreview />
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}
