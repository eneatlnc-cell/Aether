// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IAetherElection v3
 * @dev 选举合约的最小接口，便于 Governance 引用而不引入循环依赖
 *
 *  v3 变更：
 *   - 删除 REELECTION（v3 不可连任）
 *   - 新增 CITIZEN_TO_COUNCIL（公民 → 理事/常务理事）
 *   - 新增 4 阶段状态机（CandidateRegistration → CouncilReview → ParliamentApproval → Voting → Finalized）
 *   - 新增 PartiallyFilled 状态 + 空缺处理
 */
interface IAetherElection {
    // ──────────── 选举类型 ────────────
    enum ElectionType {
        MEMBER_TO_GRASSROOTS, // 0 公民 → 三院基层（普选）
        GRASSROOTS_TO_MID, // 1 三院基层 → 中层（院选）
        CITIZEN_TO_COUNCIL // 2 公民 → 理事/常务理事（普选，v3 新增）
    }

    // ──────────── 选举状态 ────────────
    enum ElectionStatus {
        Pending, // 0 等待开始（候选人注册阶段）
        CouncilReview, // 1 理事会整理阶段
        ParliamentApproval, // 2 议会审批阶段
        Active, // 3 投票中
        Finalized, // 4 已计票（席位已满）
        PartiallyFilled, // 5 已计票但有空缺
        Canceled // 6 取消
    }

    // ──────────── 理事目标层级（仅 CITIZEN_TO_COUNCIL 用） ────────────
    enum CouncilTargetTier {
        CouncilMember, // 0 → tier 10 理事
        CouncilSenior // 1 → tier 11 常务理事
    }

    /**
     * @notice 获取选举基本信息（用于前端展示）
     */
    function getElection(uint256 electionId)
        external
        view
        returns (
            ElectionType eType,
            ElectionStatus status,
            uint256 candidateCount,
            uint256 totalVotes,
            uint256 votingStartAt,
            uint256 votingEndAt,
            uint256 seatCount, // 当选席位数
            uint256 unfilledSeats // 空缺席位数（v3 新增）
        );
}
