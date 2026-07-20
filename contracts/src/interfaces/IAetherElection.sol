// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IAetherElection
 * @dev 选举合约的最小接口，便于 Governance 引用而不引入循环依赖
 */
interface IAetherElection {
    enum ElectionType {
        MEMBER_TO_GRASSROOTS, // 0 会员 → 基层（普选）
        GRASSROOTS_TO_MID, // 1 基层 → 中层（院选）
        REELECTION // 2 连任选举
    }

    enum ElectionStatus {
        Pending, // 0 等待开始
        Active, // 1 投票中
        Finalized, // 2 已计票
        Canceled // 3 取消
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
            uint256 seatCount // 当选席位数
        );
}
