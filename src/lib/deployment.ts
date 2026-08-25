// SPDX-License-Identifier: Apache-2.0
/**
 * 部署状态开关 —— 治理/金库数据的"真实 or 演示"单一事实来源
 *
 * 现状：Aether DAO 合约尚未部署到 BNB Smart Chain（含测试网）。
 * 上线之前，前端所有提案、票数、资金流数据均为界面演示（mock），
 * 必须向用户明示"演示数据"，不得伪装成链上真实记录。
 *
 * 合约部署后切换步骤：
 *  1. 将 GOVERNANCE_DEPLOYED / TREASURY_DEPLOYED 置为 true
 *     （或改为读取 isDeployed(chainId) 的运行时判断）
 *  2. useProposals() 切换为 wagmi useReadContract(AetherGovernance)
 *  3. useTreasuryTransactions() 切换为 BscScan API / 自建索引器
 *  4. 移除 src/lib/data.ts 与 fundFlowData.ts 中的 mock 数据
 */
export const GOVERNANCE_DEPLOYED = false;
export const TREASURY_DEPLOYED = false;
