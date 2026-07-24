// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AetherRing} from "./AetherRing.sol";
import {IAetherRing} from "./interfaces/IAetherRing.sol";
import {IAetherElection} from "./interfaces/IAetherElection.sol";

/**
 * @title AetherElection — Aether DAO 选举合约 v3
 * @author Aether Foundation
 *
 * ═══════════════════════════════════════════════════════════════
 *  v3 核心机制
 * ═══════════════════════════════════════════════════════════════
 *
 *  1. 三种选举类型：
 *     - MEMBER_TO_GRASSROOTS  公民 → 三院基层（普选）
 *     - GRASSROOTS_TO_MID     三院基层 → 中层（院选）
 *     - CITIZEN_TO_COUNCIL    公民 → 理事/常务理事（普选，v3 新增）
 *
 *  2. 4 阶段状态机：
 *     Pending（候选人注册）→ CouncilReview（理事会整理）→
 *     ParliamentApproval（议会审批）→ Active（投票）→ Finalized
 *     （失败路径 → Canceled / PartiallyFilled）
 *
 *  3. 候选人资格放宽（V5）：
 *     - MEMBER_TO_GRASSROOTS：公民 OR 三院成员到期（isExpired=true）
 *     - GRASSROOTS_TO_MID：对应院基层
 *     - CITIZEN_TO_COUNCIL：仅公民
 *
 *  4. 选举人资格：
 *     - MEMBER_TO_GRASSROOTS / CITIZEN_TO_COUNCIL：全体活跃公民
 *     - GRASSROOTS_TO_MID：对应院基层
 *
 *  5. 空缺处理（V12）：
 *     - 名额未满 → PartiallyFilled
 *     - 无人参选 → 注册期延长 7 天
 *     - 理事长可临时任命填补（appointToVacancy）
 *
 *  6. 当选规则：得票前 N 名（N=seatCount），平票按注册时间先后
 *
 *  7. 任期（v3 不可连任）：
 *     - 基层（1/4/7/10/11）：1 年
 *     - 中层（2/5/8）：2 年
 *     - 高层（3/6/9/12）：终身（由多签任命，不走选举）
 *
 *  注：高层由多签直接任命（AetherRing.retireToEmeritus / appointElder）
 */
contract AetherElection is AccessControl, IAetherElection {
    // ──────────── 角色 ────────────
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ELECTION_MANAGER_ROLE = keccak256("ELECTION_MANAGER_ROLE");
    bytes32 public constant COUNCIL_CHAIR_ROLE = keccak256("COUNCIL_CHAIR_ROLE");

    // ──────────── 引用 ────────────
    IAetherRing public ringContract;

    // ──────────── 常量 ────────────
    uint256 public constant REGISTRATION_PERIOD = 7 days;
    uint256 public constant COUNCIL_REVIEW_PERIOD = 3 days;
    uint256 public constant PARLIAMENT_APPROVAL_PERIOD = 3 days;
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant NO_CANDIDATE_EXTENSION = 7 days;
    uint256 public constant MAX_SEATS_GRASSROOTS = 60;
    uint256 public constant MAX_SEATS_MID = 12;
    uint256 public constant MAX_SEATS_COUNCIL = 12;

    // ──────────── 数据结构 ────────────
    struct Candidate {
        address candidate;
        bool isRegistered; // 已通过理事会整理 + 议会审批（即进入投票池）
        bool isNominated; // 已注册但未审批
        bool isRejected; // 被理事会或议会拒绝
        uint256 voteCount;
        bool won; // finalize 后标记
        uint256 registeredAt; // 注册时间戳（平票时排序用）
    }

    struct Election {
        uint256 id;
        ElectionType eType;
        ElectionStatus status;
        uint8 chamber; // 1=议会 2=联邦 3=法庭 4=理事 5=常务理事
        CouncilTargetTier councilTarget; // 仅 CITIZEN_TO_COUNCIL 用
        uint256 seatCount;
        // 时间窗口
        uint256 registrationStartAt;
        uint256 registrationEndAt;
        uint256 councilReviewEndAt;
        uint256 parliamentApprovalEndAt;
        uint256 votingStartAt;
        uint256 votingEndAt;
        // 候选人
        address[] candidates; // 所有注册过的候选人（含被拒）
        mapping(address => Candidate) candidateInfo;
        // 议会审批：议会成员对候选人列表的整体批准
        mapping(address => bool) hasParliamentApproved;
        uint256 parliamentApprovalCount;
        uint256 requiredParliamentApprovals; // 简化：议会成员半数以上（设为 1，由 Admin 配置）
        // 投票
        mapping(address => bool) hasVoted;
        mapping(address => address) voteChoice;
        uint256 totalVotes;
        // 结果
        address[] winners;
        uint256 unfilledSeats;
        bool noCandidateExtended; // 是否已因无人参选延长过
    }

    mapping(uint256 => Election) private elections;
    uint256 public electionCount;

    // 议会成员名单（用于 requiredParliamentApprovals 计算；简化为手动设置阈值）
    uint256 public parliamentApprovalThreshold = 1;

    // ──────────── 事件 ────────────
    event ElectionCreated(
        uint256 indexed id,
        ElectionType eType,
        uint8 chamber,
        CouncilTargetTier councilTarget,
        uint256 seatCount,
        uint256 registrationEndAt
    );
    event CandidateRegistered(uint256 indexed electionId, address candidate);
    event CandidateApproved(uint256 indexed electionId, address candidate);
    event CandidateRejected(uint256 indexed electionId, address candidate);
    event CouncilReviewFinalized(uint256 indexed electionId);
    event ParliamentApprovalCast(uint256 indexed electionId, address approver, uint256 count);
    event ParliamentApprovalPassed(uint256 indexed electionId);
    event VotingStarted(uint256 indexed electionId, uint256 votingEndAt);
    event VoteCast(uint256 indexed electionId, address indexed voter, address candidate);
    event ElectionFinalized(uint256 indexed id, address[] winners, uint256 unfilledSeats);
    event SeatsUnfilled(uint256 indexed id, uint256 unfilledSeats);
    event VacancyFilled(uint256 indexed id, address candidate);
    event ElectionCanceled(uint256 indexed id);
    event RegistrationExtended(uint256 indexed electionId, uint256 newRegistrationEndAt);
    event RingContractUpdated(address oldRing, address newRing);
    event ParliamentThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    // ──────────── 错误 ────────────
    error NotRingBearer();
    error NotEligibleVoter();
    error NotEligibleCandidate();
    error ElectionNotPending();
    error ElectionNotCouncilReview();
    error ElectionNotParliamentApproval();
    error ElectionNotActive();
    error ElectionNotEnded();
    error ElectionNotPartiallyFilled();
    error AlreadyVoted();
    error AlreadyRegistered();
    error AlreadyApproved();
    error AlreadyFinalized();
    error CandidateNotRegistered();
    error CandidateAlreadyApproved();
    error CandidateAlreadyRejected();
    error InvalidElectionType();
    error InvalidElectionId(uint256 electionId);
    error InvalidChamber();
    error InvalidSeatCount();
    error NoCandidates();
    error NoVacancy();
    error PromotionFailed(address candidate);
    error NotCouncilChair();
    error RegistrationNotEnded();
    error CouncilReviewNotEnded();
    error ParliamentApprovalNotMet();
    error ExtensionAlreadyApplied();
    error ZeroAddress();

    // ═══════════════════════════════════════════════════════════
    //                       构造函数
    // ═══════════════════════════════════════════════════════════

    constructor(address _ringAddress) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(ELECTION_MANAGER_ROLE, msg.sender);
        ringContract = IAetherRing(_ringAddress);
    }

    /// @dev 校验 electionId 有效性（防止对不存在的选举操作）
    modifier validElection(uint256 electionId) {
        if (electionId >= electionCount) revert InvalidElectionId(electionId);
        _;
    }

    // ═══════════════════════════════════════════════════════════
    //               阶段 1：创建选举 + 候选人注册（步骤 4.2/4.3/4.4）
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 创建选举（仅 ADMIN_ROLE）
     * @param eType          选举类型
     * @param chamber        目标院 (1=议会 2=联邦 3=法庭 4=理事 5=常务理事)
     * @param councilTarget  仅 CITIZEN_TO_COUNCIL 用：0=理事 1=常务理事
     * @param seatCount      席位数
     */
    function createElection(
        ElectionType eType,
        uint8 chamber,
        CouncilTargetTier councilTarget,
        uint256 seatCount
    ) external onlyRole(ADMIN_ROLE) returns (uint256) {
        // 校验 chamber 与 eType 一致
        if (eType == ElectionType.CITIZEN_TO_COUNCIL) {
            if (councilTarget == CouncilTargetTier.CouncilMember) {
                if (chamber != 4) revert InvalidChamber();
            } else {
                if (chamber != 5) revert InvalidChamber();
            }
        } else {
            if (chamber < 1 || chamber > 3) revert InvalidChamber();
        }

        // 校验席位数
        uint256 maxSeats;
        if (eType == ElectionType.MEMBER_TO_GRASSROOTS) maxSeats = MAX_SEATS_GRASSROOTS;
        else if (eType == ElectionType.GRASSROOTS_TO_MID) maxSeats = MAX_SEATS_MID;
        else maxSeats = MAX_SEATS_COUNCIL;
        if (seatCount == 0 || seatCount > maxSeats) revert InvalidSeatCount();

        uint256 id = electionCount++;
        Election storage e = elections[id];
        e.id = id;
        e.eType = eType;
        e.status = ElectionStatus.Pending;
        e.chamber = chamber;
        e.councilTarget = councilTarget;
        e.seatCount = seatCount;
        e.registrationStartAt = block.timestamp;
        e.registrationEndAt = block.timestamp + REGISTRATION_PERIOD;
        e.requiredParliamentApprovals = parliamentApprovalThreshold;

        emit ElectionCreated(id, eType, chamber, councilTarget, seatCount, e.registrationEndAt);
        return id;
    }

    /**
     * @notice 候选人注册（自荐）
     *         - MEMBER_TO_GRASSROOTS：公民或到期三院成员
     *         - GRASSROOTS_TO_MID：对应院基层
     *         - CITIZEN_TO_COUNCIL：仅公民
     */
    function registerCandidate(uint256 electionId) external validElection(electionId) {
        Election storage e = elections[electionId];
        if (e.status != ElectionStatus.Pending) revert ElectionNotPending();
        if (block.timestamp > e.registrationEndAt) revert RegistrationNotEnded();
        if (e.candidateInfo[msg.sender].isNominated) revert AlreadyRegistered();

        if (!_isEligibleCandidate(e.eType, e.chamber, msg.sender)) revert NotEligibleCandidate();

        e.candidates.push(msg.sender);
        e.candidateInfo[msg.sender] = Candidate({
            candidate: msg.sender,
            isRegistered: false,
            isNominated: true,
            isRejected: false,
            voteCount: 0,
            won: false,
            registeredAt: block.timestamp
        });

        emit CandidateRegistered(electionId, msg.sender);
    }

    /**
     * @notice 注册期结束后，若无人参选，延长 7 天
     */
    function extendRegistrationIfNoCandidates(uint256 electionId) external validElection(electionId) {
        Election storage e = elections[electionId];
        if (e.status != ElectionStatus.Pending) revert ElectionNotPending();
        if (block.timestamp < e.registrationEndAt) revert RegistrationNotEnded();
        if (e.candidates.length > 0) revert NoCandidates();
        if (e.noCandidateExtended) revert ExtensionAlreadyApplied();

        e.noCandidateExtended = true;
        e.registrationEndAt = block.timestamp + NO_CANDIDATE_EXTENSION;

        emit RegistrationExtended(electionId, e.registrationEndAt);
    }

    /**
     * @notice 推进至理事会整理阶段
     *         - 必须注册期结束
     *         - 必须至少有 1 个候选人
     */
    function advanceToCouncilReview(uint256 electionId) external validElection(electionId) {
        Election storage e = elections[electionId];
        if (e.status != ElectionStatus.Pending) revert ElectionNotPending();
        if (block.timestamp < e.registrationEndAt) revert RegistrationNotEnded();
        if (e.candidates.length == 0) revert NoCandidates();

        e.status = ElectionStatus.CouncilReview;
        e.councilReviewEndAt = block.timestamp + COUNCIL_REVIEW_PERIOD;

        emit CouncilReviewFinalized(electionId);
    }

    // ═══════════════════════════════════════════════════════════
    //               阶段 2：理事会整理（步骤 4.3）
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 理事会批准候选人（仅 COUNCIL_CHAIR_ROLE）
     *         理事长对每个候选人单独审批
     */
    function approveCandidate(uint256 electionId, address candidate) external validElection(electionId) onlyRole(COUNCIL_CHAIR_ROLE) {
        Election storage e = elections[electionId];
        if (e.status != ElectionStatus.CouncilReview) revert ElectionNotCouncilReview();

        Candidate storage c = e.candidateInfo[candidate];
        if (!c.isNominated) revert CandidateNotRegistered();
        if (c.isRegistered) revert CandidateAlreadyApproved();
        if (c.isRejected) revert CandidateAlreadyRejected();

        c.isRegistered = true; // 通过审批，进入投票池

        emit CandidateApproved(electionId, candidate);
    }

    /**
     * @notice 理事会拒绝候选人（仅 COUNCIL_CHAIR_ROLE）
     */
    function rejectCandidate(uint256 electionId, address candidate) external validElection(electionId) onlyRole(COUNCIL_CHAIR_ROLE) {
        Election storage e = elections[electionId];
        if (e.status != ElectionStatus.CouncilReview) revert ElectionNotCouncilReview();

        Candidate storage c = e.candidateInfo[candidate];
        if (!c.isNominated) revert CandidateNotRegistered();
        if (c.isRejected) revert CandidateAlreadyRejected();
        if (c.isRegistered) revert CandidateAlreadyApproved();

        c.isRejected = true;

        emit CandidateRejected(electionId, candidate);
    }

    /**
     * @notice 推进至议会审批阶段
     */
    function advanceToParliamentApproval(uint256 electionId) external validElection(electionId) {
        Election storage e = elections[electionId];
        if (e.status != ElectionStatus.CouncilReview) revert ElectionNotCouncilReview();
        if (block.timestamp < e.councilReviewEndAt) revert CouncilReviewNotEnded();

        // 校验至少 1 个候选人通过审批
        bool hasApproved = false;
        for (uint256 i = 0; i < e.candidates.length; i++) {
            if (e.candidateInfo[e.candidates[i]].isRegistered) {
                hasApproved = true;
                break;
            }
        }
        if (!hasApproved) revert NoCandidates();

        e.status = ElectionStatus.ParliamentApproval;
        e.parliamentApprovalEndAt = block.timestamp + PARLIAMENT_APPROVAL_PERIOD;

        emit CouncilReviewFinalized(electionId);
    }

    // ═══════════════════════════════════════════════════════════
    //               阶段 3：议会审批（步骤 4.3）
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 议会成员对整个候选人列表投批准票
     *         简化：达到 requiredParliamentApprovals 即通过
     */
    function parliamentApproveCandidateList(uint256 electionId) external validElection(electionId) {
        Election storage e = elections[electionId];
        if (e.status != ElectionStatus.ParliamentApproval) revert ElectionNotParliamentApproval();
        if (e.hasParliamentApproved[msg.sender]) revert AlreadyApproved();

        // 仅议会成员（tier 1/2/3）可投批准票
        uint8 tier = ringContract.getTier(msg.sender);
        if (tier < 1 || tier > 3) revert NotEligibleVoter();

        e.hasParliamentApproved[msg.sender] = true;
        e.parliamentApprovalCount += 1;

        emit ParliamentApprovalCast(electionId, msg.sender, e.parliamentApprovalCount);

        if (e.parliamentApprovalCount >= e.requiredParliamentApprovals) {
            e.status = ElectionStatus.Active;
            e.votingStartAt = block.timestamp;
            e.votingEndAt = block.timestamp + VOTING_PERIOD;
            emit ParliamentApprovalPassed(electionId);
            emit VotingStarted(electionId, e.votingEndAt);
        }
    }

    /**
     * @notice 议会审批期结束后自动推进（即使未达阈值，也进入投票阶段）
     *         防止议会拖延导致选举卡死
     */
    function forceAdvanceToVoting(uint256 electionId) external validElection(electionId) {
        Election storage e = elections[electionId];
        if (e.status != ElectionStatus.ParliamentApproval) revert ElectionNotParliamentApproval();
        if (block.timestamp < e.parliamentApprovalEndAt) revert ParliamentApprovalNotMet();
        // M8: 议会审批期结束后强制推进，但至少需 1 票批准（防止完全被否决的名单进入投票）
        if (e.parliamentApprovalCount == 0) revert ParliamentApprovalNotMet();

        e.status = ElectionStatus.Active;
        e.votingStartAt = block.timestamp;
        e.votingEndAt = block.timestamp + VOTING_PERIOD;
        emit ParliamentApprovalPassed(electionId);
        emit VotingStarted(electionId, e.votingEndAt);
    }

    // ═══════════════════════════════════════════════════════════
    //               阶段 4：投票（步骤 4.3）
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 投票
     * @param electionId  选举 ID
     * @param candidate   投给的候选人（必须通过理事会审批）
     */
    function castVote(uint256 electionId, address candidate) external validElection(electionId) {
        Election storage e = elections[electionId];
        if (e.status != ElectionStatus.Active) revert ElectionNotActive();
        if (block.timestamp > e.votingEndAt) revert ElectionNotActive();
        if (e.hasVoted[msg.sender]) revert AlreadyVoted();
        if (!_isEligibleVoter(e.eType, e.chamber, msg.sender)) revert NotEligibleVoter();

        Candidate storage c = e.candidateInfo[candidate];
        if (!c.isRegistered) revert CandidateNotRegistered();

        e.hasVoted[msg.sender] = true;
        e.voteChoice[msg.sender] = candidate;
        c.voteCount += 1;
        e.totalVotes += 1;

        // 更新公民投票活动时间（休眠机制）
        ringContract.markVoteActivity(msg.sender);

        emit VoteCast(electionId, msg.sender, candidate);
    }

    // ═══════════════════════════════════════════════════════════
    //               阶段 5：计票 + 空缺处理（步骤 4.5）
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 最终化（任何人可触发）
     *         - 取得票前 N 名（N=seatCount），平票按注册时间先后
     *         - 名额未满 → PartiallyFilled，记录 unfilledSeats
     */
    function finalizeElection(uint256 electionId) external validElection(electionId) {
        Election storage e = elections[electionId];
        if (e.status != ElectionStatus.Active) revert AlreadyFinalized();
        if (block.timestamp <= e.votingEndAt) revert ElectionNotEnded();

        // 收集已通过审批的候选人
        address[] memory approvedCandidates = _getApprovedCandidates(e);
        if (approvedCandidates.length == 0) {
            // 没有候选人进入投票池 → 全部空缺
            e.unfilledSeats = e.seatCount;
            e.status = ElectionStatus.PartiallyFilled;
            emit SeatsUnfilled(electionId, e.unfilledSeats);
            emit ElectionFinalized(electionId, e.winners, e.unfilledSeats);
            return;
        }

        // 按票数 + 注册时间排序
        address[] memory sorted = _sortCandidatesByVotes(approvedCandidates, e);
        uint256 winCount = e.seatCount < sorted.length ? e.seatCount : sorted.length;

        // Bug 18: 逐个晋升，失败的跳过并计入未填补名额
        for (uint256 i = 0; i < winCount; i++) {
            address winner = sorted[i];
            bool ok = _applyPromotion(e.eType, e.chamber, e.councilTarget, winner);
            if (ok) {
                e.winners.push(winner);
                e.candidateInfo[winner].won = true;
            }
            // 失败的候选人不加入 winners，自然计入 unfilledSeats
        }

        if (e.winners.length < e.seatCount) {
            e.unfilledSeats = e.seatCount - e.winners.length;
            e.status = ElectionStatus.PartiallyFilled;
            emit SeatsUnfilled(electionId, e.unfilledSeats);
        } else {
            e.status = ElectionStatus.Finalized;
        }

        emit ElectionFinalized(electionId, e.winners, e.unfilledSeats);
    }

    /**
     * @notice 理事长填补空缺（仅 PartiallyFilled 状态）
     *         临时任命的候选人无需经过投票，直接晋升
     * @param electionId  选举 ID
     * @param candidate   被任命的候选人地址（必须符合资格）
     */
    function appointToVacancy(uint256 electionId, address candidate) external validElection(electionId) onlyRole(COUNCIL_CHAIR_ROLE) {
        if (candidate == address(0)) revert ZeroAddress();
        Election storage e = elections[electionId];
        if (e.status != ElectionStatus.PartiallyFilled) revert ElectionNotPartiallyFilled();
        if (e.unfilledSeats == 0) revert NoVacancy();

        // M6: 必须是已通过理事会审批进入投票池的候选人（防止绕过选举结果任意任命）
        Candidate storage c = e.candidateInfo[candidate];
        if (!c.isRegistered) revert NotEligibleCandidate();
        if (c.isRejected) revert NotEligibleCandidate();

        // 校验资格
        if (!_isEligibleCandidate(e.eType, e.chamber, candidate)) revert NotEligibleCandidate();

        // 校验未重复任命
        if (c.won) revert AlreadyApproved();

        // Bug 18: 晋升失败时 revert，由理事长选择其他候选人
        bool ok = _applyPromotion(e.eType, e.chamber, e.councilTarget, candidate);
        if (!ok) revert PromotionFailed(candidate);

        e.winners.push(candidate);
        c.won = true;
        e.unfilledSeats -= 1;

        if (e.unfilledSeats == 0) {
            e.status = ElectionStatus.Finalized;
        }

        emit VacancyFilled(electionId, candidate);
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
            uint256 seatCount,
            uint256 unfilledSeats
        )
    {
        Election storage e = elections[electionId];
        return (
            e.eType,
            e.status,
            e.candidates.length,
            e.totalVotes,
            e.votingStartAt,
            e.votingEndAt,
            e.seatCount,
            e.unfilledSeats
        );
    }

    function getElectionTimelines(uint256 electionId)
        external
        view
        returns (
            uint256 registrationStartAt,
            uint256 registrationEndAt,
            uint256 councilReviewEndAt,
            uint256 parliamentApprovalEndAt,
            uint256 votingStartAt,
            uint256 votingEndAt
        )
    {
        Election storage e = elections[electionId];
        return (
            e.registrationStartAt,
            e.registrationEndAt,
            e.councilReviewEndAt,
            e.parliamentApprovalEndAt,
            e.votingStartAt,
            e.votingEndAt
        );
    }

    function getCandidateInfo(uint256 electionId, address candidate)
        external
        view
        returns (bool isNominated, bool isRegistered, bool isRejected, uint256 voteCount, bool won, uint256 registeredAt)
    {
        Candidate storage c = elections[electionId].candidateInfo[candidate];
        return (c.isNominated, c.isRegistered, c.isRejected, c.voteCount, c.won, c.registeredAt);
    }

    function getCandidateVoteCount(uint256 electionId, address candidate) external view returns (uint256) {
        return elections[electionId].candidateInfo[candidate].voteCount;
    }

    function getWinners(uint256 electionId) external view returns (address[] memory) {
        return elections[electionId].winners;
    }

    function getCandidates(uint256 electionId) external view returns (address[] memory) {
        return elections[electionId].candidates;
    }

    function hasVoted(uint256 electionId, address voter) external view returns (bool) {
        return elections[electionId].hasVoted[voter];
    }

    function hasParliamentApproved(uint256 electionId, address approver) external view returns (bool) {
        return elections[electionId].hasParliamentApproved[approver];
    }

    // ═══════════════════════════════════════════════════════════
    //                       管理
    // ═══════════════════════════════════════════════════════════

    function cancelElection(uint256 electionId) external validElection(electionId) onlyRole(ADMIN_ROLE) {
        Election storage e = elections[electionId];
        if (e.status == ElectionStatus.Finalized || e.status == ElectionStatus.PartiallyFilled) {
            revert AlreadyFinalized();
        }
        e.status = ElectionStatus.Canceled;
        emit ElectionCanceled(electionId);
    }

    function setRingContract(address _ring) external onlyRole(ADMIN_ROLE) {
        address old = address(ringContract);
        ringContract = IAetherRing(_ring);
        emit RingContractUpdated(old, _ring);
    }

    function setParliamentApprovalThreshold(uint256 _threshold) external onlyRole(ADMIN_ROLE) {
        if (_threshold == 0) revert InvalidSeatCount();
        uint256 old = parliamentApprovalThreshold;
        parliamentApprovalThreshold = _threshold;
        emit ParliamentThresholdUpdated(old, _threshold);
    }

    function grantCouncilChairRole(address chair) external onlyRole(ADMIN_ROLE) {
        if (chair == address(0)) revert ZeroAddress();
        _grantRole(COUNCIL_CHAIR_ROLE, chair);
    }

    // ═══════════════════════════════════════════════════════════
    //                       内部辅助
    // ═══════════════════════════════════════════════════════════

    /**
     * @dev 判断地址是否有资格作为候选人（V5 放宽）
     *  - MEMBER_TO_GRASSROOTS: 公民 OR 三院成员到期（isExpired=true）
     *  - GRASSROOTS_TO_MID: 对应院基层 (tier 1/4/7)
     *  - CITIZEN_TO_COUNCIL: 仅公民 (tier==14)
     */
    function _isEligibleCandidate(ElectionType eType, uint8 chamber, address candidate)
        internal
        view
        returns (bool)
    {
        uint256 ringId = ringContract.getRingId(candidate);
        if (ringId == 0) return false;

        // 用 getRingInfo 读取原始 tier（不受 isActive/isExpired/isDormant 影响）
        IAetherRing.RingInfo memory info = ringContract.getRingInfo(ringId);
        uint8 tier = uint8(info.tier);

        if (eType == ElectionType.MEMBER_TO_GRASSROOTS) {
            // 公民可直接参选
            if (tier == 14) return true;
            // 三院成员到期（基层/中层/高层任一层级到期均可参选）
            if (tier >= 1 && tier <= 9 && info.isExpired) return true;
            return false;
        }

        if (eType == ElectionType.CITIZEN_TO_COUNCIL) {
            return tier == 14;
        }

        if (eType == ElectionType.GRASSROOTS_TO_MID) {
            if (chamber == 1) return tier == 1; // 议员 → 参议员
            if (chamber == 2) return tier == 4; // 委员 → 委员长
            if (chamber == 3) return tier == 7; // 法官 → 大法官
        }

        return false;
    }

    /**
     * @dev 判断地址是否有资格投票
     *  - MEMBER_TO_GRASSROOTS / CITIZEN_TO_COUNCIL: 全体活跃公民 (tier==14)
     *  - GRASSROOTS_TO_MID: 对应院基层 (tier 1/4/7)
     */
    function _isEligibleVoter(ElectionType eType, uint8 chamber, address voter) internal view returns (bool) {
        uint8 tier = ringContract.getTier(voter);
        if (tier == 0) return false;

        if (eType == ElectionType.MEMBER_TO_GRASSROOTS || eType == ElectionType.CITIZEN_TO_COUNCIL) {
            return tier == 14;
        }

        if (eType == ElectionType.GRASSROOTS_TO_MID) {
            if (chamber == 1) return tier == 1;
            if (chamber == 2) return tier == 4;
            if (chamber == 3) return tier == 7;
        }

        return false;
    }

    /**
     * @dev 升级当选者 tier
     *      选举合约必须有 ring.ADMIN_ROLE（updateTier）和 ring.MINTER_ROLE（首次铸道环）
     */
    function _applyPromotion(
        ElectionType eType,
        uint8 chamber,
        CouncilTargetTier councilTarget,
        address winner
    ) internal returns (bool success) {
        IAetherRing.RingTier newTier;

        if (eType == ElectionType.MEMBER_TO_GRASSROOTS) {
            if (chamber == 1) newTier = IAetherRing.RingTier.PARLIAMENT_MEMBER;
            else if (chamber == 2) newTier = IAetherRing.RingTier.FEDERATION_MEMBER;
            else newTier = IAetherRing.RingTier.TRIBUNAL_JUDGE;
        } else if (eType == ElectionType.GRASSROOTS_TO_MID) {
            if (chamber == 1) newTier = IAetherRing.RingTier.PARLIAMENT_SENIOR;
            else if (chamber == 2) newTier = IAetherRing.RingTier.FEDERATION_SENIOR;
            else newTier = IAetherRing.RingTier.TRIBUNAL_SENIOR;
        } else if (eType == ElectionType.CITIZEN_TO_COUNCIL) {
            if (councilTarget == CouncilTargetTier.CouncilMember) {
                newTier = IAetherRing.RingTier.COUNCIL_MEMBER;
            } else {
                newTier = IAetherRing.RingTier.COUNCIL_SENIOR;
            }
        }

        uint256 ringId = ringContract.getRingId(winner);

        // Bug 18: try/catch 防止单个候选人晋升失败阻塞整个选举
        if (ringId == 0) {
            // 公民当选基层/理事但未持有道环：先铸道环
            try ringContract.mintRing(winner, newTier, "") {
                success = true;
            } catch {
                success = false;
            }
        } else {
            // 已有道环（如到期成员重新当选）：updateTier
            try ringContract.updateTier(ringId, newTier, true) {
                success = true;
            } catch {
                success = false;
            }
        }
    }

    /**
     * @dev 收集所有通过理事会审批的候选人（isRegistered=true）
     */
    function _getApprovedCandidates(Election storage e) internal view returns (address[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < e.candidates.length; i++) {
            if (e.candidateInfo[e.candidates[i]].isRegistered) {
                count++;
            }
        }
        address[] memory approved = new address[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < e.candidates.length; i++) {
            if (e.candidateInfo[e.candidates[i]].isRegistered) {
                approved[idx] = e.candidates[i];
                idx++;
            }
        }
        return approved;
    }

    /**
     * @dev 简单冒泡排序，按票数从高到低；平票按注册时间先后（早者排前）
     *      候选人数量 <=60，gas 可控
     */
    function _sortCandidatesByVotes(address[] memory candidates, Election storage e)
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
                uint256 votesI = e.candidateInfo[sorted[i]].voteCount;
                uint256 votesJ = e.candidateInfo[sorted[j]].voteCount;
                // 票数高的排前；票数相同则注册早的排前
                if (votesJ > votesI) {
                    (sorted[i], sorted[j]) = (sorted[j], sorted[i]);
                } else if (votesJ == votesI) {
                    if (e.candidateInfo[sorted[j]].registeredAt < e.candidateInfo[sorted[i]].registeredAt) {
                        (sorted[i], sorted[j]) = (sorted[j], sorted[i]);
                    }
                }
            }
        }
        return sorted;
    }
}
