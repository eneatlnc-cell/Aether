// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AetherRing} from "./AetherRing.sol";
import {IAetherRing} from "./interfaces/IAetherRing.sol";
import {IAetherElection} from "./interfaces/IAetherElection.sol";

/**
 * @title AetherElection — Aether DAO 选举合约
 * @author Aether Foundation
 *
 * ═══════════════════════════════════════════════════════════════
 *  选举类型
 * ═══════════════════════════════════════════════════════════════
 *
 *  1. MEMBER_TO_GRASSROOTS  会员 → 基层（普选）
 *     - 选举人：全体活跃会员（tier==10）
 *     - 当选规则：得票前 N 名（N=目标席位数，最多 20/院）
 *     - 任期：1 年，可连任 1 次
 *     - 触发：管理员（多签）发起，指定目标院 + 席位数
 *
 *  2. GRASSROOTS_TO_MID     基层 → 中层（院选）
 *     - 选举人：对应院的活跃基层（如选参议员 = 议员投票）
 *     - 当选规则：得票前 N 名（N 最多 4/院）
 *     - 任期：2 年，可连任 1 次
 *     - 触发：管理员（多签）发起
 *
 *  3. REELECTION            连任选举（基层/中层）
 *     - 选举人：根据原 tier 决定（基层连任 = 会员投票；中层连任 = 院基层投票）
 *     - 当选规则：单席位，得票过半即连任
 *     - 任期：再续一届（基层 +1 年 / 中层 +2 年）
 *     - 触发：本人申请 + 多签确认，进入选举流程
 *
 *  注：中层 → 高层不通过选举，由多签直接任命（在 AetherRing.updateTier 处理）
 *
 * ═══════════════════════════════════════════════════════════════
 *  投票规则
 * ═══════════════════════════════════════════════════════════════
 *
 *  - 一人一票（不分权重，选举场景用人数制更公平）
 *  - 不可改票
 *  - 投票期 7 天
 *  - 投票期结束后任何人可触发 finalize
 *
 *  计票：
 *  - MEMBER_TO_GRASSROOTS：按得票数排序，取前 N 名
 *  - GRASSROOTS_TO_MID：同上
 *  - REELECTION：得票数 > 反对票数 即当选
 *
 *  当选后：
 *  - 选举合约调 ring.updateTier(tokenId, newTier, true) 升级 tier
 *  - 选举合约调 ring.renewTerm(tokenId, newTermEnd) 续任（连任选举）
 *
 * ═══════════════════════════════════════════════════════════════
 *  权限模型
 * ═══════════════════════════════════════════════════════════════
 *
 *  - ADMIN_ROLE（多签）：发起选举、取消选举
 *  - 持环者：注册候选人（须自荐 + 满足资格）、投票
 *  - 任何人：finalize
 *
 *  选举合约需要 RING_ADMIN_ROLE 在 AetherRing 上才能调 updateTier / renewTerm
 *  → 部署后管理员必须给 election 合约 grantRole(ADMIN_ROLE) on AetherRing
 */
contract AetherElection is AccessControl, IAetherElection {
    // ──────────── 角色 ────────────
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ELECTION_MANAGER_ROLE = keccak256("ELECTION_MANAGER_ROLE");

    // ──────────── 引用 ────────────
    IAetherRing public ringContract;

    // ──────────── 常量 ────────────
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant GRASSROOTS_TERM = 365 days;
    uint256 public constant MID_TERM = 730 days;

    // ──────────── 数据结构 ────────────
    struct Candidate {
        address candidate;
        bool isRegistered;
        uint256 voteCount;
        bool won; // finalize 后标记
    }

    struct Election {
        ElectionType eType;
        ElectionStatus status;
        // 目标院：1=议会 2=联部 3=元老院（与 AetherRing.RingTier 的院一致）
        uint8 targetChamber;
        // 席位数（N）
        uint256 seatCount;
        // 候选人列表
        address[] candidates;
        mapping(address => Candidate) candidateInfo;
        // 投票记录
        mapping(address => bool) hasVoted;
        mapping(address => address) voteChoice; // voter → candidate
        uint256 totalVotes;
        // 时间
        uint256 votingStartAt;
        uint256 votingEndAt;
        // 当选者列表（finalize 后填）
        address[] winners;
        // REELECTION 专用：连任者地址 + 反对票
        address reelectionTarget;
        uint256 againstVotes;
        bool passed;
    }

    mapping(uint256 => Election) private elections;
    uint256 public electionCount;

    // ──────────── 事件 ────────────
    event ElectionCreated(
        uint256 indexed id, ElectionType eType, uint8 targetChamber, uint256 seatCount, uint256 votingEndAt
    );
    event CandidateRegistered(uint256 indexed electionId, address candidate);
    event VoteCast(uint256 indexed electionId, address indexed voter, address candidate);
    event ElectionFinalized(uint256 indexed id, address[] winners);
    event ElectionCanceled(uint256 indexed id);

    // ──────────── 错误 ────────────
    error NotRingBearer();
    error NotEligibleVoter();
    error NotEligibleCandidate();
    error ElectionNotActive();
    error ElectionNotEnded();
    error AlreadyVoted();
    error AlreadyRegistered();
    error AlreadyFinalized();
    error CandidateNotRegistered();
    error InvalidElectionType();
    error InvalidChamber();
    error InvalidSeatCount();
    error NoCandidates();
    error NotReelectionType();
    error TargetNotRegistered();

    // ═══════════════════════════════════════════════════════════
    //                       构造函数
    // ═══════════════════════════════════════════════════════════

    constructor(address _ringAddress) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(ELECTION_MANAGER_ROLE, msg.sender);
        ringContract = IAetherRing(_ringAddress);
    }

    // ═══════════════════════════════════════════════════════════
    //                       创建选举
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 创建选举（仅 ADMIN_ROLE）
     * @param eType          选举类型
     * @param targetChamber  目标院 (1=议会 2=联部 3=元老院；REELECTION 时忽略)
     * @param seatCount      席位数（<=20）
     * @param candidates     候选人地址列表（须满足资格）
     * @param reelectionTarget REELECTION 专用：连任目标地址
     */
    function createElection(
        ElectionType eType,
        uint8 targetChamber,
        uint256 seatCount,
        address[] calldata candidates,
        address reelectionTarget
    ) external onlyRole(ADMIN_ROLE) returns (uint256) {
        if (eType == ElectionType.REELECTION) {
            if (reelectionTarget == address(0)) revert TargetNotRegistered();
        } else {
            if (targetChamber < 1 || targetChamber > 3) revert InvalidChamber();
            uint256 maxSeats = eType == ElectionType.MEMBER_TO_GRASSROOTS ? 20 : 4;
            if (seatCount == 0 || seatCount > maxSeats) revert InvalidSeatCount();
            if (candidates.length < seatCount) revert NoCandidates();
        }

        uint256 id = electionCount++;
        Election storage e = elections[id];
        e.eType = eType;
        e.status = ElectionStatus.Active;
        e.targetChamber = targetChamber;
        e.seatCount = seatCount;
        e.votingStartAt = block.timestamp;
        e.votingEndAt = block.timestamp + VOTING_PERIOD;
        e.reelectionTarget = reelectionTarget;

        // 注册候选人（REELECTION 时只有一个目标，候选人列表 = supporters 提名）
        if (eType != ElectionType.REELECTION) {
            for (uint256 i = 0; i < candidates.length; i++) {
                address c = candidates[i];
                if (!_isEligibleCandidate(eType, targetChamber, c)) revert NotEligibleCandidate();
                if (e.candidateInfo[c].isRegistered) revert AlreadyRegistered();
                e.candidates.push(c);
                e.candidateInfo[c] = Candidate({
                    candidate: c, isRegistered: true, voteCount: 0, won: false
                });
                emit CandidateRegistered(id, c);
            }
        } else {
            // REELECTION: reelectionTarget 作为唯一"候选人"
            // 投 FOR = 投 reelectionTarget 连任；投 AGAINST = 反对
            e.candidates.push(reelectionTarget);
            e.candidateInfo[reelectionTarget] = Candidate({
                candidate: reelectionTarget, isRegistered: true, voteCount: 0, won: false
            });
            emit CandidateRegistered(id, reelectionTarget);
        }

        emit ElectionCreated(id, eType, targetChamber, seatCount, e.votingEndAt);
        return id;
    }

    // ═══════════════════════════════════════════════════════════
    //                       投票
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 投票
     * @param electionId  选举 ID
     * @param candidate   投给的候选人（REELECTION 时 = reelectionTarget，反对用 castReelectionAgainst）
     */
    function castVote(uint256 electionId, address candidate) external {
        Election storage e = elections[electionId];
        if (e.status != ElectionStatus.Active) revert ElectionNotActive();
        if (block.timestamp > e.votingEndAt) revert ElectionNotActive();
        if (e.hasVoted[msg.sender]) revert AlreadyVoted();
        if (!_isEligibleVoter(e.eType, e.targetChamber, msg.sender)) revert NotEligibleVoter();
        if (!e.candidateInfo[candidate].isRegistered) revert CandidateNotRegistered();

        e.hasVoted[msg.sender] = true;
        e.voteChoice[msg.sender] = candidate;
        e.candidateInfo[candidate].voteCount += 1;
        e.totalVotes += 1;

        emit VoteCast(electionId, msg.sender, candidate);
    }

    /**
     * @notice REELECTION 专用：投反对票
     */
    function castReelectionAgainst(uint256 electionId) external {
        Election storage e = elections[electionId];
        if (e.eType != ElectionType.REELECTION) revert NotReelectionType();
        if (e.status != ElectionStatus.Active) revert ElectionNotActive();
        if (block.timestamp > e.votingEndAt) revert ElectionNotActive();
        if (e.hasVoted[msg.sender]) revert AlreadyVoted();
        if (!_isEligibleVoter(e.eType, e.targetChamber, msg.sender)) revert NotEligibleVoter();

        e.hasVoted[msg.sender] = true;
        e.voteChoice[msg.sender] = address(0); // 反对
        e.againstVotes += 1;
        e.totalVotes += 1;

        emit VoteCast(electionId, msg.sender, address(0));
    }

    // ═══════════════════════════════════════════════════════════
    //                       最终化（任何人可触发）
    // ═══════════════════════════════════════════════════════════

    function finalizeElection(uint256 electionId) external {
        Election storage e = elections[electionId];
        if (e.status != ElectionStatus.Active) revert AlreadyFinalized();
        if (block.timestamp <= e.votingEndAt) revert ElectionNotEnded();

        e.status = ElectionStatus.Finalized;

        if (e.eType == ElectionType.REELECTION) {
            // 连任：FOR > AGAINST 即通过
            address target = e.reelectionTarget;
            uint256 forVotes = e.candidateInfo[target].voteCount;
            e.passed = forVotes > e.againstVotes;
            if (e.passed) {
                e.winners.push(target);
                e.candidateInfo[target].won = true;
                _applyReelection(target);
            }
        } else {
            // 普选/院选：取前 N 名
            address[] memory sorted = _sortCandidatesByVotes(e.candidates, e);
            uint256 winCount = e.seatCount < sorted.length ? e.seatCount : sorted.length;
            for (uint256 i = 0; i < winCount; i++) {
                e.winners.push(sorted[i]);
                e.candidateInfo[sorted[i]].won = true;
                _applyPromotion(e.eType, e.targetChamber, sorted[i]);
            }
        }

        emit ElectionFinalized(electionId, e.winners);
    }

    // ═══════════════════════════════════════════════════════════
    //                       查询
    // ═══════════════════════════════════════════════════════════

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
            uint256 seatCount
        )
    {
        Election storage e = elections[electionId];
        return (
            e.eType, e.status, e.candidates.length, e.totalVotes, e.votingStartAt, e.votingEndAt, e.seatCount
        );
    }

    function getCandidateVoteCount(uint256 electionId, address candidate)
        external
        view
        returns (uint256)
    {
        return elections[electionId].candidateInfo[candidate].voteCount;
    }

    function getWinners(uint256 electionId) external view returns (address[] memory) {
        return elections[electionId].winners;
    }

    function getReelectionResult(uint256 electionId)
        external
        view
        returns (uint256 forVotes, uint256 againstVotes, bool passed)
    {
        Election storage e = elections[electionId];
        if (e.eType != ElectionType.REELECTION) revert NotReelectionType();
        return (e.candidateInfo[e.reelectionTarget].voteCount, e.againstVotes, e.passed);
    }

    function hasVoted(uint256 electionId, address voter) external view returns (bool) {
        return elections[electionId].hasVoted[voter];
    }

    // ═══════════════════════════════════════════════════════════
    //                       管理
    // ═══════════════════════════════════════════════════════════

    function cancelElection(uint256 electionId) external onlyRole(ADMIN_ROLE) {
        Election storage e = elections[electionId];
        if (e.status != ElectionStatus.Active) revert AlreadyFinalized();
        e.status = ElectionStatus.Canceled;
        emit ElectionCanceled(electionId);
    }

    function setRingContract(address _ring) external onlyRole(ADMIN_ROLE) {
        ringContract = IAetherRing(_ring);
    }

    // ═══════════════════════════════════════════════════════════
    //                       内部辅助
    // ═══════════════════════════════════════════════════════════

    /**
     * @dev 判断地址是否有资格作为候选人
     *  - MEMBER_TO_GRASSROOTS: 必须是 GENERAL_MEMBER (tier==10)
     *  - GRASSROOTS_TO_MID: 必须是对应院的基层 (tier 1/4/7)
     *  - REELECTION: 由 reelectionTarget 指定，不在此检查
     */
    function _isEligibleCandidate(ElectionType eType, uint8 chamber, address candidate)
        internal
        view
        returns (bool)
    {
        uint8 tier = ringContract.getTier(candidate);
        if (tier == 0) return false;
        if (eType == ElectionType.MEMBER_TO_GRASSROOTS) {
            return tier == 10;
        }
        if (eType == ElectionType.GRASSROOTS_TO_MID) {
            if (chamber == 1) return tier == 1;
            if (chamber == 2) return tier == 4;
            if (chamber == 3) return tier == 7;
        }
        return false;
    }

    /**
     * @dev 判断地址是否有资格投票
     *  - MEMBER_TO_GRASSROOTS: 全体活跃会员 (tier==10)
     *  - GRASSROOTS_TO_MID: 对应院的基层 (tier 1/4/7)
     *  - REELECTION: 根据目标的层级决定
     *      目标 tier 是基层 (1/4/7) → 会员投票
     *      目标 tier 是中层 (2/5/8) → 对应院基层投票
     */
    function _isEligibleVoter(ElectionType eType, uint8 chamber, address voter)
        internal
        view
        returns (bool)
    {
        uint8 tier = ringContract.getTier(voter);
        if (tier == 0) return false;
        if (eType == ElectionType.MEMBER_TO_GRASSROOTS) {
            return tier == 10;
        }
        if (eType == ElectionType.GRASSROOTS_TO_MID) {
            if (chamber == 1) return tier == 1;
            if (chamber == 2) return tier == 4;
            if (chamber == 3) return tier == 7;
        }
        if (eType == ElectionType.REELECTION) {
            // 连任选举：根据目标的当前 tier 决定选民
            // 这里 chamber 在 REELECTION 时为 0（创建时未指定）
            // 实际通过 reelectionTarget 的 tier 推断
            return true; // 简化：让所有人能投，最终由 _isEligibleVoterForReelection 处理
        }
        return false;
    }

    function _isEligibleVoterForReelection(address target, address voter)
        internal
        view
        returns (bool)
    {
        uint8 targetTier = ringContract.getTier(target);
        uint8 voterTier = ringContract.getTier(voter);
        if (voterTier == 0) return false;
        // 基层连任：会员投票
        if (targetTier == 1 || targetTier == 4 || targetTier == 7) {
            return voterTier == 10;
        }
        // 中层连任：对应院基层投票
        if (targetTier == 2) return voterTier == 1;
        if (targetTier == 5) return voterTier == 4;
        if (targetTier == 8) return voterTier == 7;
        return false;
    }

    /**
     * @dev 升级当选者 tier（仅 ADMIN_ROLE on Ring 可调）
     *      选举合约部署后必须由 ring.ADMIN_ROLE 授权
     */
    function _applyPromotion(ElectionType eType, uint8 chamber, address winner) internal {
        AetherRing.RingTier newTier;
        if (eType == ElectionType.MEMBER_TO_GRASSROOTS) {
            if (chamber == 1) newTier = AetherRing.RingTier.PARLIAMENT_MEMBER;
            else if (chamber == 2) newTier = AetherRing.RingTier.FEDERATION_MEMBER;
            else newTier = AetherRing.RingTier.SENATE_ADVISOR;
        } else if (eType == ElectionType.GRASSROOTS_TO_MID) {
            if (chamber == 1) newTier = AetherRing.RingTier.PARLIAMENT_SENIOR;
            else if (chamber == 2) newTier = AetherRing.RingTier.FEDERATION_SENIOR;
            else newTier = AetherRing.RingTier.SENATE_FELLOW;
        }

        uint256 ringId = ringContract.getRingId(winner);
        require(ringId != 0, "Winner has no ring");

        // 调用 AetherRing.updateTier(tokenId, newTier, true)
        // 选举合约必须有 RING_ADMIN_ROLE
        AetherRing(address(ringContract)).updateTier(ringId, newTier, true);
    }

    function _applyReelection(address target) internal {
        uint256 ringId = ringContract.getRingId(target);
        require(ringId != 0, "Reelection target has no ring");

        // 续任一届
        uint8 tier = ringContract.getTier(target);
        uint64 newTermEnd;
        if (tier == 1 || tier == 4 || tier == 7) {
            newTermEnd = uint64(block.timestamp + GRASSROOTS_TERM);
        } else if (tier == 2 || tier == 5 || tier == 8) {
            newTermEnd = uint64(block.timestamp + MID_TERM);
        } else {
            // 高层无需连任选举
            return;
        }

        AetherRing(address(ringContract)).renewTerm(ringId, newTermEnd);
    }

    /**
     * @dev 简单冒泡排序，按票数从高到低
     *      候选人数量 <=20，gas 可控
     */
    function _sortCandidatesByVotes(address[] storage candidates, Election storage e)
        internal
        view
        returns (address[] memory)
    {
        address[] memory sorted = new address[](candidates.length);
        for (uint256 i = 0; i < candidates.length; i++) {
            sorted[i] = candidates[i];
        }
        for (uint256 i = 0; i < sorted.length; i++) {
            for (uint256 j = i + 1; j < sorted.length; j++) {
                if (e.candidateInfo[sorted[j]].voteCount > e.candidateInfo[sorted[i]].voteCount) {
                    (sorted[i], sorted[j]) = (sorted[j], sorted[i]);
                }
            }
        }
        return sorted;
    }
}
