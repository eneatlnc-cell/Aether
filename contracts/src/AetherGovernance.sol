// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AetherRing} from "./AetherRing.sol";
import {IAetherRing} from "./interfaces/IAetherRing.sol";

/**
 * @title AetherGovernance — Aether DAO 三院分权制衡治理主合约 v3
 * @author Aether Foundation
 *
 * ═══════════════════════════════════════════════════════════════
 *  v3 核心机制
 * ═══════════════════════════════════════════════════════════════
 *
 *  1. 七阶段提案流程（12 状态）：
 *     Drafting → PendingFirstVote → FirstVoteActive → PendingFormal
 *              → PendingCompliance → PublicVoteActive → PendingVeto
 *              → Queued → Executed
 *     （失败路径 → Defeated / Canceled / ReturnedToDraft）
 *
 *  2. 三院内部权重 1/3/10（基层/中层/高层），每院多数决出 FOR/AGAINST/NEUTRAL
 *
 *  3. 加权计票：三院各 1666（合计 4998≈50%）+ 公民 5000（50%），通过门槛 >50%
 *     公民 quorum：普通 20%，章程修订 50%
 *
 *  4. 元老否决：3 任命元老联署，72h 窗口（V5: 弹劾不可否决）
 *
 *  5. 弹劾：3 任命元老发起 → 公投 → 公民参与≥30% + 支持率≥70%
 *
 *  6. 理事长信任投票：8 理事联署触发 → 理事投票 → 不通过 30 天辞职
 *
 *  7. 紧急拨款：3 元老快速批准 + 12h Timelock（普通 48h）
 */
contract AetherGovernance is AccessControl {
    // ──────────── 角色 ────────────
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");

    // ──────────── 引用 ────────────
    IAetherRing public ringContract;

    // ═══════════════════════════════════════════════════════════
    //                       类型定义
    // ═══════════════════════════════════════════════════════════

    enum VoteOption { NONE, FOR, AGAINST, ABSTAIN }

    enum ChamberStance { NEUTRAL, FOR, AGAINST }

    enum ProposalType { SIGNAL, PARAM, TREASURY, IMPEACHMENT }

    enum ProposalStatus {
        Drafting,           // 0  草案（理事会推进/退回）
        PendingFirstVote,   // 1  待开始一审
        FirstVoteActive,    // 2  议会一审中
        PendingFormal,      // 3  一审通过，待正式提交
        PendingCompliance,  // 4  法庭合规审查中
        PublicVoteActive,   // 5  公投中
        PendingVeto,        // 6  待元老否决
        Queued,             // 7  Timelock 排队
        Executed,           // 8  已执行
        Defeated,           // 9  未通过
        Canceled,           // 10 被否决/取消
        ReturnedToDraft     // 11 退回草案
    }

    enum TreasuryUrgency { Normal, Emergency }

    struct Proposal {
        uint256 id;
        address proposer;
        ProposalType pType;
        string title;
        string ipfsHash;
        uint256 createdAt;
        // ── 时间窗口 ──
        uint256 firstVoteStartAt;
        uint256 firstVoteEndAt;
        uint256 complianceVoteEndAt;
        uint256 publicVoteStartAt;
        uint256 publicVoteEndAt;
        uint256 vetoWindowEndAt;
        // ── 三院内部权重累积 ──
        uint256 parliamentFor;
        uint256 parliamentAgainst;
        uint256 federationFor;
        uint256 federationAgainst;
        uint256 tribunalFor;
        uint256 tribunalAgainst;
        // ── 公民投票 ──
        uint256 citizenFor;
        uint256 citizenAgainst;
        uint256 citizenAbstain;
        uint256 citizenTotalSnapshot;
        // ── 法庭合规审查 ──
        uint256 complianceFor;
        uint256 complianceAgainst;
        // ── finalize 结果 ──
        ChamberStance parliamentStance;
        ChamberStance federationStance;
        ChamberStance tribunalStance;
        bool citizenQuorumMet;
        bool passed;
        ProposalStatus status;
        // ── execute 扩展 ──
        address target;
        bytes calldataPayload;
        uint256 queuedAt;
        uint256 executeAfter;
        bool isExecuted;
        bool isConstitutional;
        TreasuryUrgency urgency;
        // ── IMPEACHMENT 专用 ──
        address impeachedTarget;
        uint256 requiredImpeachSignatures;
        uint256 currentImpeachSignatures;
        // ── 元老否决 ──
        uint256 requiredVetoSignatures;
        uint256 currentVetoSignatures;
        // ── 理事会退回联署 ──
        uint256 requiredReturnSignatures;
        uint256 currentReturnSignatures;
        // ── 紧急拨款批准 ──
        uint256 emergencyApprovals;
        // ── mappings（必须在末尾） ──
        mapping(address => bool) hasFirstVoted;
        mapping(address => bool) hasPublicVoted;
        mapping(address => bool) hasComplianceVoted;
        mapping(address => bool) hasImpeachSigned;
        mapping(address => bool) hasVetoed;
        mapping(address => bool) hasSignedReturn;
        mapping(address => bool) hasEmergencyApproved;
    }

    struct ConfidenceVote {
        address chair;
        uint256 startedAt;
        uint256 forVotes;
        uint256 againstVotes;
        bool resolved;
        mapping(address => bool) hasVoted;
    }

    // ═══════════════════════════════════════════════════════════
    //                       存储
    // ═══════════════════════════════════════════════════════════

    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;

    mapping(uint8 => uint256) public internalWeight;

    mapping(uint256 => ConfidenceVote) public confidenceVotes;
    uint256 public confidenceVoteCount;
    mapping(address => uint256) public councilTriggerSignatures;
    mapping(address => mapping(address => bool)) public hasSignedConfidenceTrigger;
    mapping(address => uint256) public chairPendingResign;

    // ── 常量 ──
    uint256 public constant BPS_DENOMINATOR = 10_000;
    // 权重归一到 100%：三院合计 4998 + 公民 5000 = 9998 ≈ 10000
    // 设计：三院全 FOR（4998）+ 公民 0% = 4998 < 5000，三院无法独断
    //       公民 100%（5000）+ 0 院 = 5000，不 > 5000，公民也无法独断
    // → 提案通过必须跨院 + 公民合作，体现 50/50 制衡
    uint256 public constant CHAMBER_WEIGHT_BPS = 1_666;        // 每院 ≈16.6%，三院合计 4998
    uint256 public constant CITIZEN_WEIGHT_BPS = 5_000;        // 公民 50%
    uint256 public constant PASS_THRESHOLD_BPS = 5_000;        // >50%
    uint256 public constant CITIZEN_QUORUM_BPS = 2_000;        // ≥20%
    uint256 public constant CONSTITUTIONAL_QUORUM_BPS = 5_000; // 章程修订 50%

    uint256 public constant FIRST_VOTE_PERIOD = 5 days;
    uint256 public constant PUBLIC_VOTE_PERIOD = 7 days;
    uint256 public constant COMPLIANCE_VOTE_PERIOD = 3 days;
    uint256 public constant VETO_WINDOW = 72 hours;
    uint256 public constant TIMELOCK_NORMAL = 48 hours;
    uint256 public constant TIMELOCK_EMERGENCY = 12 hours;

    uint256 public constant IMPEACHMENT_SIGNATURES = 3;
    uint256 public constant IMPEACHMENT_QUORUM_BPS = 3_000;    // 公民参与 ≥30%
    uint256 public constant IMPEACHMENT_PASS_BPS = 7_000;      // 支持率 ≥70%
    uint256 public constant VETO_SIGNATURES = 3;
    uint256 public constant RETURN_SIGNATURES = 2;
    uint256 public constant EMERGENCY_ELDER_APPROVALS = 3;
    uint256 public constant CONFIDENCE_TRIGGER_SIGNATURES = 8;
    uint256 public constant CONFIDENCE_VOTE_PERIOD = 7 days;
    uint256 public constant CONFIDENCE_RESIGN_WINDOW = 30 days;

    // ── PARAM 白名单 selector ──
    bytes4 private constant SEL_SET_VOTING_PERIODS = bytes4(keccak256("setVotingPeriods(uint256,uint256,uint256)"));
    bytes4 private constant SEL_SET_TIMELOCKS = bytes4(keccak256("setTimelocks(uint256,uint256)"));
    bytes4 private constant SEL_SET_INTERNAL_WEIGHT = bytes4(keccak256("setInternalWeight(uint8,uint256)"));

    // ── 可调参数（PARAM 可修改） ──
    uint256 public firstVotePeriod = FIRST_VOTE_PERIOD;
    uint256 public publicVotePeriod = PUBLIC_VOTE_PERIOD;
    uint256 public complianceVotePeriod = COMPLIANCE_VOTE_PERIOD;
    uint256 public timelockNormal = TIMELOCK_NORMAL;
    uint256 public timelockEmergency = TIMELOCK_EMERGENCY;

    // ──────────── 事件 ────────────
    event ProposalCreated(uint256 indexed id, address proposer, ProposalType pType, string title);
    event ProposalAdvanced(uint256 indexed id);
    event ProposalReturned(uint256 indexed id);
    event ProposalResubmitted(uint256 indexed id);
    event FirstVoteStarted(uint256 indexed id);
    event FirstVoteCast(uint256 indexed id, address voter, VoteOption option);
    event FirstVoteFinalized(uint256 indexed id, bool passed);
    event FormalProposalSubmitted(uint256 indexed id);
    event ComplianceVoteCast(uint256 indexed id, address voter, VoteOption option);
    event ComplianceFinalized(uint256 indexed id, bool compliant);
    event PublicVoteCast(uint256 indexed id, address voter, VoteOption option);
    event ProposalFinalized(uint256 indexed id, bool passed);
    event ProposalVetoed(uint256 indexed id);
    event ProposalQueued(uint256 indexed id, uint256 executeAfter);
    event ProposalExecuted(uint256 indexed id);
    event ProposalCanceled(uint256 indexed id);
    event ImpeachmentSigned(uint256 indexed id, address signer, uint256 current, uint256 required);
    event ImpeachmentToPublicVote(uint256 indexed id);
    event ImpeachmentFinalized(uint256 indexed id, bool passed);
    event EmergencyApproved(uint256 indexed id, address elder);
    event ConfidenceTriggerSigned(address indexed chair, address signer, uint256 current);
    event ConfidenceVoteTriggered(uint256 indexed id, address chair);
    event ConfidenceVoteCast(uint256 indexed id, address voter, bool support);
    event ConfidenceVoteFinalized(uint256 indexed id, bool passed);
    event ChairConfidenceFailed(uint256 indexed id, address chair);
    event RingContractUpdated(address oldRing, address newRing);

    // ──────────── 错误 ────────────
    error NotChamberMember();
    error EmptyTitle();
    error EmptyIpfs();
    error TreasuryTargetZero();
    error ConstitutionalOnlyForParam();
    error UseCreateImpeachmentProposal();
    error NotDrafting();
    error NotCouncilChair();
    error NotCouncilMember();
    error AlreadySigned();
    error NotReturnedToDraft();
    error NotProposer();
    error NotPendingFirstVote();
    error NotFirstVoteActive();
    error FirstVoteNotEnded();
    error NotParliamentMember();
    error NotPendingFormal();
    error NotAuthorized();
    error NotPendingCompliance();
    error ComplianceNotEnded();
    error NotTribunalMember();
    error NotPublicVoteActive();
    error PublicVoteNotEnded();
    error NotEligibleVoter();
    error NotPendingVeto();
    error CannotVetoImpeachment();
    error NotAppointedElder();
    error AlreadyVetoed();
    error VetoWindowNotEnded();
    error VetoWindowEnded();
    error NotQueued();
    error TimelockNotElapsed();
    error NotEmergency();
    error EmergencyApprovalNotMet();
    error AlreadyApproved();
    error ImpeachmentTargetInvalid();
    error ExecutionFailed(bytes ret);
    error ParamSelectorNotWhitelisted(bytes4 selector);
    error NotRingBearer();
    error UnknownTier(uint8 tier);
    error AlreadyVoted();
    error AlreadyResolved();
    error ConfidenceVoteNotEnded();
    error NotEnoughSignatures(uint256 current, uint256 required);
    error ParamOutOfRange();
    error ZeroRingAddress();
    error AlreadyInTerminalState();

    // ──────────── 修饰器 ────────────
    modifier onlyChamberMember() {
        uint8 tier = ringContract.getTier(msg.sender);
        if (tier < 1 || tier > 9) revert NotChamberMember();
        _;
    }

    // ═══════════════════════════════════════════════════════════
    //                       构造函数
    // ═══════════════════════════════════════════════════════════

    constructor(address _ringAddress) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(PROPOSER_ROLE, msg.sender);
        // PARAM 提案通过 address(this).call 执行 setVotingPeriods 等 onlyRole(ADMIN_ROLE) 函数
        // 因此治理合约自身需要 ADMIN_ROLE
        _grantRole(ADMIN_ROLE, address(this));
        ringContract = IAetherRing(_ringAddress);

        // 三院内部权重：1/3/10（基层/中层/高层）
        internalWeight[1] = 1;  // 议员
        internalWeight[2] = 3;  // 参议员
        internalWeight[3] = 10; // 议长
        internalWeight[4] = 1;  // 委员
        internalWeight[5] = 3;  // 委员长
        internalWeight[6] = 10; // 执政
        internalWeight[7] = 1;  // 法官
        internalWeight[8] = 3;  // 大法官
        internalWeight[9] = 10; // 首席
        internalWeight[14] = 1; // 公民（公投一人一票，权重不用于累积）
    }

    // ═══════════════════════════════════════════════════════════
    //               普通提案创建（步骤 3.4）
    // ═══════════════════════════════════════════════════════════

    function createProposal(
        ProposalType pType,
        string calldata title,
        string calldata ipfsHash,
        address target,
        bytes calldata calldataPayload,
        bool isConstitutional,
        TreasuryUrgency urgency
    ) external onlyRole(PROPOSER_ROLE) onlyChamberMember returns (uint256) {
        if (pType == ProposalType.IMPEACHMENT) revert UseCreateImpeachmentProposal();
        if (bytes(title).length == 0) revert EmptyTitle();
        if (bytes(ipfsHash).length == 0) revert EmptyIpfs();
        if (pType == ProposalType.TREASURY && target == address(0)) revert TreasuryTargetZero();
        if (pType == ProposalType.PARAM) _checkParamWhitelist(calldataPayload);
        if (isConstitutional && pType != ProposalType.PARAM) revert ConstitutionalOnlyForParam();

        uint256 id = proposalCount++;
        Proposal storage p = proposals[id];
        p.id = id;
        p.proposer = msg.sender;
        p.pType = pType;
        p.title = title;
        p.ipfsHash = ipfsHash;
        p.createdAt = block.timestamp;
        p.status = ProposalStatus.Drafting;
        p.target = target;
        p.calldataPayload = calldataPayload;
        p.isConstitutional = isConstitutional;
        p.urgency = urgency;
        p.requiredReturnSignatures = RETURN_SIGNATURES;
        p.requiredVetoSignatures = VETO_SIGNATURES;
        p.requiredImpeachSignatures = IMPEACHMENT_SIGNATURES;

        emit ProposalCreated(id, msg.sender, pType, title);
        return id;
    }

    // ═══════════════════════════════════════════════════════════
    //               理事会推进/退回（步骤 3.5）
    // ═══════════════════════════════════════════════════════════

    function advanceProposal(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.Drafting) revert NotDrafting();
        // IMPEACHMENT 走专用流程（createImpeachmentProposal → signImpeachment），不能走普通七阶段
        if (p.pType == ProposalType.IMPEACHMENT) revert UseCreateImpeachmentProposal();
        if (ringContract.getTier(msg.sender) != uint8(IAetherRing.RingTier.COUNCIL_CHAIR)) revert NotCouncilChair();

        p.status = ProposalStatus.PendingFirstVote;
        emit ProposalAdvanced(proposalId);
    }

    function returnProposal(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.Drafting) revert NotDrafting();
        // IMPEACHMENT 提案不可被理事会退回
        if (p.pType == ProposalType.IMPEACHMENT) revert UseCreateImpeachmentProposal();
        uint8 tier = ringContract.getTier(msg.sender);
        if (tier < uint8(IAetherRing.RingTier.COUNCIL_MEMBER) || tier > uint8(IAetherRing.RingTier.COUNCIL_CHAIR)) {
            revert NotCouncilMember();
        }
        if (p.hasSignedReturn[msg.sender]) revert AlreadySigned();

        p.hasSignedReturn[msg.sender] = true;
        p.currentReturnSignatures += 1;

        if (p.currentReturnSignatures >= p.requiredReturnSignatures) {
            p.status = ProposalStatus.ReturnedToDraft;
            emit ProposalReturned(proposalId);
        }
    }

    function resubmitFromReturn(uint256 proposalId, string calldata newTitle, string calldata newIpfs) external {
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.ReturnedToDraft) revert NotReturnedToDraft();
        if (msg.sender != p.proposer) revert NotProposer();

        p.title = newTitle;
        p.ipfsHash = newIpfs;
        p.currentReturnSignatures = 0;
        p.status = ProposalStatus.Drafting;
        emit ProposalResubmitted(proposalId);
    }

    // ═══════════════════════════════════════════════════════════
    //               议会一审（步骤 3.6）
    // ═══════════════════════════════════════════════════════════

    function startFirstVote(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.PendingFirstVote) revert NotPendingFirstVote();
        // H-6: 限制为提案者或理事会主席，防止恶意提前启动投票窗口
        if (msg.sender != p.proposer
            && ringContract.getTier(msg.sender) != uint8(IAetherRing.RingTier.COUNCIL_CHAIR)) {
            revert NotProposer();
        }

        p.status = ProposalStatus.FirstVoteActive;
        p.firstVoteStartAt = block.timestamp;
        p.firstVoteEndAt = block.timestamp + firstVotePeriod;
        emit FirstVoteStarted(proposalId);
    }

    function castFirstVote(uint256 proposalId, VoteOption option) external {
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.FirstVoteActive) revert NotFirstVoteActive();
        if (block.timestamp > p.firstVoteEndAt) revert NotFirstVoteActive();
        if (option != VoteOption.FOR && option != VoteOption.AGAINST) revert NotEligibleVoter();
        if (p.hasFirstVoted[msg.sender]) revert AlreadyVoted();

        uint8 tier = ringContract.getTier(msg.sender);
        if (!_isParliamentMember(tier)) revert NotParliamentMember();

        p.hasFirstVoted[msg.sender] = true;
        uint256 weight = internalWeight[tier];
        if (option == VoteOption.FOR) p.parliamentFor += weight;
        else p.parliamentAgainst += weight;

        ringContract.markVoteActivity(msg.sender);
        emit FirstVoteCast(proposalId, msg.sender, option);
    }

    function finalizeFirstVote(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.FirstVoteActive) revert NotFirstVoteActive();
        if (block.timestamp < p.firstVoteEndAt) revert FirstVoteNotEnded();

        bool passed = p.parliamentFor > p.parliamentAgainst;
        p.status = passed ? ProposalStatus.PendingFormal : ProposalStatus.Defeated;
        emit FirstVoteFinalized(proposalId, passed);
    }

    // ═══════════════════════════════════════════════════════════
    //               正式提交 + 法庭合规审查（步骤 3.7）
    // ═══════════════════════════════════════════════════════════

    function submitFormalProposal(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.PendingFormal) revert NotPendingFormal();
        if (msg.sender != p.proposer && ringContract.getTier(msg.sender) != uint8(IAetherRing.RingTier.COUNCIL_CHAIR)) {
            revert NotAuthorized();
        }

        p.status = ProposalStatus.PendingCompliance;
        p.complianceVoteEndAt = block.timestamp + complianceVotePeriod;
        emit FormalProposalSubmitted(proposalId);
    }

    function castComplianceVote(uint256 proposalId, VoteOption option) external {
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.PendingCompliance) revert NotPendingCompliance();
        if (block.timestamp > p.complianceVoteEndAt) revert NotPendingCompliance();
        if (option != VoteOption.FOR && option != VoteOption.AGAINST) revert NotEligibleVoter();
        if (p.hasComplianceVoted[msg.sender]) revert AlreadyVoted();

        uint8 tier = ringContract.getTier(msg.sender);
        if (!_isTribunalMember(tier)) revert NotTribunalMember();

        p.hasComplianceVoted[msg.sender] = true;
        uint256 weight = internalWeight[tier];
        if (option == VoteOption.FOR) p.complianceFor += weight;
        else p.complianceAgainst += weight;

        emit ComplianceVoteCast(proposalId, msg.sender, option);
    }

    function finalizeCompliance(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.PendingCompliance) revert NotPendingCompliance();
        if (block.timestamp < p.complianceVoteEndAt) revert ComplianceNotEnded();

        bool compliant = p.complianceFor > p.complianceAgainst;
        if (compliant) {
            // 合规通过 → 进入公投，重置三院计数（公投是独立阶段）
            p.parliamentFor = 0;
            p.parliamentAgainst = 0;
            p.federationFor = 0;
            p.federationAgainst = 0;
            p.tribunalFor = 0;
            p.tribunalAgainst = 0;
            p.status = ProposalStatus.PublicVoteActive;
            p.publicVoteStartAt = block.timestamp;
            p.publicVoteEndAt = block.timestamp + publicVotePeriod;
            p.citizenTotalSnapshot = ringContract.getActiveCitizens();
        } else {
            p.status = ProposalStatus.ReturnedToDraft;
        }
        emit ComplianceFinalized(proposalId, compliant);
    }

    // ═══════════════════════════════════════════════════════════
    //               公投投票（步骤 3.8）
    // ═══════════════════════════════════════════════════════════

    function castPublicVote(uint256 proposalId, VoteOption option) external {
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.PublicVoteActive) revert NotPublicVoteActive();
        if (block.timestamp > p.publicVoteEndAt) revert NotPublicVoteActive();
        if (option != VoteOption.FOR && option != VoteOption.AGAINST && option != VoteOption.ABSTAIN) {
            revert NotEligibleVoter();
        }
        if (p.hasPublicVoted[msg.sender]) revert AlreadyVoted();

        uint8 tier = ringContract.getTier(msg.sender);
        if (tier == 0) revert NotRingBearer();

        uint256 weight = internalWeight[tier];

        if (_isParliamentMember(tier)) {
            if (option == VoteOption.FOR) p.parliamentFor += weight;
            else if (option == VoteOption.AGAINST) p.parliamentAgainst += weight;
        } else if (_isFederationMember(tier)) {
            if (option == VoteOption.FOR) p.federationFor += weight;
            else if (option == VoteOption.AGAINST) p.federationAgainst += weight;
        } else if (_isTribunalMember(tier)) {
            if (option == VoteOption.FOR) p.tribunalFor += weight;
            else if (option == VoteOption.AGAINST) p.tribunalAgainst += weight;
        } else if (tier == uint8(IAetherRing.RingTier.CITIZEN)) {
            if (option == VoteOption.FOR) p.citizenFor += 1;
            else if (option == VoteOption.AGAINST) p.citizenAgainst += 1;
            else p.citizenAbstain += 1;
        } else {
            revert NotEligibleVoter();
        }

        p.hasPublicVoted[msg.sender] = true;
        ringContract.markVoteActivity(msg.sender);
        emit PublicVoteCast(proposalId, msg.sender, option);
    }

    // ═══════════════════════════════════════════════════════════
    //               finalizeProposal 新计票（步骤 3.9）
    // ═══════════════════════════════════════════════════════════

    function finalizeProposal(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        if (p.pType == ProposalType.IMPEACHMENT) revert NotPublicVoteActive();
        if (p.status != ProposalStatus.PublicVoteActive) revert NotPublicVoteActive();
        if (block.timestamp < p.publicVoteEndAt) revert PublicVoteNotEnded();

        // 1. 每院内部多数决
        p.parliamentStance = _stanceOf(p.parliamentFor, p.parliamentAgainst);
        p.federationStance = _stanceOf(p.federationFor, p.federationAgainst);
        p.tribunalStance = _stanceOf(p.tribunalFor, p.tribunalAgainst);

        // 2. 公民参与率检查
        uint256 citizenVotes = p.citizenFor + p.citizenAgainst + p.citizenAbstain;
        uint256 requiredQuorum = p.isConstitutional ? CONSTITUTIONAL_QUORUM_BPS : CITIZEN_QUORUM_BPS;
        p.citizenQuorumMet = p.citizenTotalSnapshot > 0
            && (citizenVotes * BPS_DENOMINATOR) / p.citizenTotalSnapshot >= requiredQuorum;

        // 3. 加权计算：三院 FOR 数 × 1666 BPS + 公民赞成率 × 5000 BPS（合计 ≈10000）
        uint256 chamberForCount = _countStance(p.parliamentStance, ChamberStance.FOR)
            + _countStance(p.federationStance, ChamberStance.FOR)
            + _countStance(p.tribunalStance, ChamberStance.FOR);
        uint256 chamberForBps = chamberForCount * CHAMBER_WEIGHT_BPS;

        uint256 citizenForBps = citizenVotes > 0
            ? (p.citizenFor * BPS_DENOMINATOR) / citizenVotes : 0;

        uint256 totalForBps = chamberForBps + (citizenForBps * CITIZEN_WEIGHT_BPS) / BPS_DENOMINATOR;

        p.passed = p.citizenQuorumMet && totalForBps > PASS_THRESHOLD_BPS;

        if (p.passed) {
            p.status = ProposalStatus.PendingVeto;
            p.vetoWindowEndAt = block.timestamp + VETO_WINDOW;
        } else {
            p.status = ProposalStatus.Defeated;
        }

        emit ProposalFinalized(proposalId, p.passed);
    }

    // ═══════════════════════════════════════════════════════════
    //               元老否决（步骤 3.10）
    // ═══════════════════════════════════════════════════════════

    function vetoProposal(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.PendingVeto) revert NotPendingVeto();
        if (block.timestamp > p.vetoWindowEndAt) revert VetoWindowEnded();
        if (p.pType == ProposalType.IMPEACHMENT) revert CannotVetoImpeachment();
        if (!ringContract.isElderActive(msg.sender)) revert NotAppointedElder();
        if (p.hasVetoed[msg.sender]) revert AlreadyVetoed();

        p.hasVetoed[msg.sender] = true;
        p.currentVetoSignatures += 1;

        if (p.currentVetoSignatures >= p.requiredVetoSignatures) {
            p.status = ProposalStatus.Canceled;
            emit ProposalVetoed(proposalId);
        }
    }

    function finalizeVetoWindow(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.PendingVeto) revert NotPendingVeto();
        if (block.timestamp < p.vetoWindowEndAt) revert VetoWindowNotEnded();

        p.status = ProposalStatus.Queued;
        p.queuedAt = block.timestamp;
        p.executeAfter = block.timestamp + (
            p.urgency == TreasuryUrgency.Emergency ? timelockEmergency : timelockNormal
        );
        emit ProposalQueued(proposalId, p.executeAfter);
    }

    // ═══════════════════════════════════════════════════════════
    //               executeProposal（步骤 3.11）
    // ═══════════════════════════════════════════════════════════

    function executeProposal(uint256 proposalId) external payable {
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.Queued) revert NotQueued();
        if (block.timestamp < p.executeAfter) revert TimelockNotElapsed();

        // CEI：先更新状态，防止重入
        p.status = ProposalStatus.Executed;
        p.isExecuted = true;

        if (p.pType == ProposalType.SIGNAL) {
            // 信号性提案，无链上执行
        } else if (p.pType == ProposalType.PARAM) {
            _checkParamWhitelist(p.calldataPayload);
            (bool ok, bytes memory ret) = address(this).call(p.calldataPayload);
            if (!ok) revert ExecutionFailed(ret);
        } else if (p.pType == ProposalType.TREASURY) {
            if (p.urgency == TreasuryUrgency.Emergency && p.emergencyApprovals < EMERGENCY_ELDER_APPROVALS) {
                revert EmergencyApprovalNotMet();
            }
            (bool ok, bytes memory ret) = p.target.call{value: msg.value}(p.calldataPayload);
            if (!ok) revert ExecutionFailed(ret);
        }

        emit ProposalExecuted(proposalId);
    }

    function approveEmergencyTreasury(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        // H-7: 必须在 Queued（Timelock 排队）状态才能紧急审批
        // 防止对未通过投票或已执行的提案滥用紧急审批
        if (p.status != ProposalStatus.Queued) revert NotQueued();
        if (p.urgency != TreasuryUrgency.Emergency) revert NotEmergency();
        if (!ringContract.isElderActive(msg.sender)) revert NotAppointedElder();
        if (p.hasEmergencyApproved[msg.sender]) revert AlreadyApproved();

        p.hasEmergencyApproved[msg.sender] = true;
        p.emergencyApprovals += 1;
        emit EmergencyApproved(proposalId, msg.sender);
    }

    // ═══════════════════════════════════════════════════════════
    //               弹劾重写（步骤 3.12）
    // ═══════════════════════════════════════════════════════════

    function createImpeachmentProposal(
        address target,
        string calldata title,
        string calldata ipfsHash
    ) external returns (uint256) {
        if (!ringContract.isElderActive(msg.sender)) revert NotAppointedElder();
        if (target == address(0)) revert ImpeachmentTargetInvalid();
        if (bytes(title).length == 0) revert EmptyTitle();
        if (bytes(ipfsHash).length == 0) revert EmptyIpfs();

        uint8 targetTier = ringContract.getTier(target);
        // V4：可弹劾 tier 1-13，不可弹劾公民 14
        if (targetTier == 0 || targetTier == uint8(IAetherRing.RingTier.CITIZEN)) revert ImpeachmentTargetInvalid();

        uint256 id = proposalCount++;
        Proposal storage p = proposals[id];
        p.id = id;
        p.proposer = msg.sender;
        p.pType = ProposalType.IMPEACHMENT;
        p.title = title;
        p.ipfsHash = ipfsHash;
        p.createdAt = block.timestamp;
        p.status = ProposalStatus.Drafting;
        p.impeachedTarget = target;
        p.requiredImpeachSignatures = IMPEACHMENT_SIGNATURES;
        p.currentImpeachSignatures = 1;
        p.hasImpeachSigned[msg.sender] = true;

        emit ProposalCreated(id, msg.sender, ProposalType.IMPEACHMENT, title);
        return id;
    }

    function signImpeachment(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.Drafting) revert NotDrafting();
        if (!ringContract.isElderActive(msg.sender)) revert NotAppointedElder();
        if (p.hasImpeachSigned[msg.sender]) revert AlreadySigned();

        p.hasImpeachSigned[msg.sender] = true;
        p.currentImpeachSignatures += 1;

        emit ImpeachmentSigned(proposalId, msg.sender, p.currentImpeachSignatures, p.requiredImpeachSignatures);

        if (p.currentImpeachSignatures >= p.requiredImpeachSignatures) {
            // 联署满 → 直接进入公投（无法庭审查，无元老否决）
            p.status = ProposalStatus.PublicVoteActive;
            p.publicVoteStartAt = block.timestamp;
            p.publicVoteEndAt = block.timestamp + publicVotePeriod;
            p.citizenTotalSnapshot = ringContract.getActiveCitizens();
            emit ImpeachmentToPublicVote(proposalId);
        }
    }

    function finalizeImpeachment(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        if (p.pType != ProposalType.IMPEACHMENT) revert NotPublicVoteActive();
        if (p.status != ProposalStatus.PublicVoteActive) revert NotPublicVoteActive();
        if (block.timestamp < p.publicVoteEndAt) revert PublicVoteNotEnded();

        // 弹劾计票：公民参与率 ≥30% + 支持率 ≥70%
        // 注意：弹劾的 FOR = 支持弹劾，AGAINST = 反对弹劾
        // 弹劾通过 = 支持率 ≥70%（citizenFor / citizenVotes）
        uint256 citizenVotes = p.citizenFor + p.citizenAgainst + p.citizenAbstain;
        bool quorumMet = p.citizenTotalSnapshot > 0
            && (citizenVotes * BPS_DENOMINATOR) / p.citizenTotalSnapshot >= IMPEACHMENT_QUORUM_BPS;
        bool passRateMet = citizenVotes > 0
            && ((p.citizenFor * BPS_DENOMINATOR) / citizenVotes >= IMPEACHMENT_PASS_BPS);

        bool passed = quorumMet && passRateMet;

        if (passed) {
            // 直接撤销道环（弹劾跳过 Timelock 和否决）
            uint256 ringId = ringContract.getRingId(p.impeachedTarget);
            if (ringId != 0) {
                ringContract.revokeRing(ringId);
            }
            // H-9: 清除被弹劾者在治理合约中的其他权限
            // revokeRing 只撤销道环，不影响已授予的 PROPOSER_ROLE 等
            if (hasRole(PROPOSER_ROLE, p.impeachedTarget)) {
                _revokeRole(PROPOSER_ROLE, p.impeachedTarget);
            }
            p.status = ProposalStatus.Executed;
            p.isExecuted = true;
        } else {
            p.status = ProposalStatus.Defeated;
        }

        emit ImpeachmentFinalized(proposalId, passed);
    }

    // ═══════════════════════════════════════════════════════════
    //               理事长信任投票（步骤 3.13）
    // ═══════════════════════════════════════════════════════════

    function signConfidenceTrigger(address chair) external {
        uint8 tier = ringContract.getTier(msg.sender);
        if (tier != uint8(IAetherRing.RingTier.COUNCIL_MEMBER) && tier != uint8(IAetherRing.RingTier.COUNCIL_SENIOR)) {
            revert NotCouncilMember();
        }
        if (hasSignedConfidenceTrigger[chair][msg.sender]) revert AlreadySigned();

        hasSignedConfidenceTrigger[chair][msg.sender] = true;
        councilTriggerSignatures[chair] += 1;

        emit ConfidenceTriggerSigned(chair, msg.sender, councilTriggerSignatures[chair]);
    }

    function triggerConfidenceVote(address chair, string calldata /* reasonIpfs */) external {
        if (councilTriggerSignatures[chair] < CONFIDENCE_TRIGGER_SIGNATURES) {
            revert NotEnoughSignatures(councilTriggerSignatures[chair], CONFIDENCE_TRIGGER_SIGNATURES);
        }

        uint256 id = confidenceVoteCount++;
        ConfidenceVote storage cv = confidenceVotes[id];
        cv.chair = chair;
        cv.startedAt = block.timestamp;

        emit ConfidenceVoteTriggered(id, chair);
    }

    function voteConfidence(uint256 voteId, bool support) external {
        ConfidenceVote storage cv = confidenceVotes[voteId];
        if (cv.resolved) revert AlreadyResolved();
        if (cv.hasVoted[msg.sender]) revert AlreadyVoted();

        uint8 tier = ringContract.getTier(msg.sender);
        if (tier != uint8(IAetherRing.RingTier.COUNCIL_MEMBER) && tier != uint8(IAetherRing.RingTier.COUNCIL_SENIOR)) {
            revert NotCouncilMember();
        }

        cv.hasVoted[msg.sender] = true;
        if (support) cv.forVotes += 1;
        else cv.againstVotes += 1;

        emit ConfidenceVoteCast(voteId, msg.sender, support);
    }

    function finalizeConfidence(uint256 voteId) external {
        ConfidenceVote storage cv = confidenceVotes[voteId];
        if (cv.resolved) revert AlreadyResolved();
        if (block.timestamp < cv.startedAt + CONFIDENCE_VOTE_PERIOD) revert ConfidenceVoteNotEnded();

        cv.resolved = true;
        bool passed = cv.forVotes > cv.againstVotes;

        if (!passed) {
            // 理事长 30 天内需辞职
            chairPendingResign[cv.chair] = block.timestamp + CONFIDENCE_RESIGN_WINDOW;
            emit ChairConfidenceFailed(voteId, cv.chair);
        }

        emit ConfidenceVoteFinalized(voteId, passed);
    }

    // ═══════════════════════════════════════════════════════════
    //               查询
    // ═══════════════════════════════════════════════════════════

    function getProposal(uint256 proposalId)
        external
        view
        returns (
            uint256 id,
            address proposer,
            ProposalType pType,
            string memory title,
            string memory ipfsHash,
            ProposalStatus status,
            address target,
            uint256 executeAfter,
            bool isExecuted,
            bool isConstitutional,
            TreasuryUrgency urgency,
            address impeachedTarget,
            uint256 currentImpeachSignatures,
            uint256 requiredImpeachSignatures,
            uint256 currentVetoSignatures,
            uint256 requiredVetoSignatures,
            uint256 currentReturnSignatures,
            uint256 requiredReturnSignatures,
            uint256 emergencyApprovals
        )
    {
        Proposal storage p = proposals[proposalId];
        return (
            p.id, p.proposer, p.pType, p.title, p.ipfsHash, p.status, p.target,
            p.executeAfter, p.isExecuted, p.isConstitutional, p.urgency,
            p.impeachedTarget, p.currentImpeachSignatures, p.requiredImpeachSignatures,
            p.currentVetoSignatures, p.requiredVetoSignatures,
            p.currentReturnSignatures, p.requiredReturnSignatures,
            p.emergencyApprovals
        );
    }

    function getVoteCounts(uint256 proposalId)
        external
        view
        returns (
            uint256 parliamentFor, uint256 parliamentAgainst,
            uint256 federationFor, uint256 federationAgainst,
            uint256 tribunalFor, uint256 tribunalAgainst,
            uint256 citizenFor, uint256 citizenAgainst, uint256 citizenAbstain,
            uint256 citizenTotalSnapshot,
            uint256 complianceFor, uint256 complianceAgainst,
            ChamberStance parliamentStance, ChamberStance federationStance, ChamberStance tribunalStance,
            bool citizenQuorumMet, bool passed
        )
    {
        Proposal storage p = proposals[proposalId];
        return (
            p.parliamentFor, p.parliamentAgainst,
            p.federationFor, p.federationAgainst,
            p.tribunalFor, p.tribunalAgainst,
            p.citizenFor, p.citizenAgainst, p.citizenAbstain,
            p.citizenTotalSnapshot,
            p.complianceFor, p.complianceAgainst,
            p.parliamentStance, p.federationStance, p.tribunalStance,
            p.citizenQuorumMet, p.passed
        );
    }

    function getProposalTimelines(uint256 proposalId)
        external
        view
        returns (
            uint256 createdAt,
            uint256 firstVoteStartAt, uint256 firstVoteEndAt,
            uint256 complianceVoteEndAt,
            uint256 publicVoteStartAt, uint256 publicVoteEndAt,
            uint256 vetoWindowEndAt,
            uint256 queuedAt, uint256 executeAfter
        )
    {
        Proposal storage p = proposals[proposalId];
        return (
            p.createdAt,
            p.firstVoteStartAt, p.firstVoteEndAt,
            p.complianceVoteEndAt,
            p.publicVoteStartAt, p.publicVoteEndAt,
            p.vetoWindowEndAt,
            p.queuedAt, p.executeAfter
        );
    }

    function hasFirstVoted(uint256 proposalId, address voter) external view returns (bool) {
        return proposals[proposalId].hasFirstVoted[voter];
    }
    function hasPublicVoted(uint256 proposalId, address voter) external view returns (bool) {
        return proposals[proposalId].hasPublicVoted[voter];
    }
    function hasComplianceVoted(uint256 proposalId, address voter) external view returns (bool) {
        return proposals[proposalId].hasComplianceVoted[voter];
    }
    function hasImpeachSigned(uint256 proposalId, address signer) external view returns (bool) {
        return proposals[proposalId].hasImpeachSigned[signer];
    }
    function hasVetoed(uint256 proposalId, address elder) external view returns (bool) {
        return proposals[proposalId].hasVetoed[elder];
    }
    function hasSignedReturn(uint256 proposalId, address council) external view returns (bool) {
        return proposals[proposalId].hasSignedReturn[council];
    }
    function hasEmergencyApproved(uint256 proposalId, address elder) external view returns (bool) {
        return proposals[proposalId].hasEmergencyApproved[elder];
    }

    function getConfidenceVote(uint256 voteId)
        external
        view
        returns (address chair, uint256 startedAt, uint256 forVotes, uint256 againstVotes, bool resolved)
    {
        ConfidenceVote storage cv = confidenceVotes[voteId];
        return (cv.chair, cv.startedAt, cv.forVotes, cv.againstVotes, cv.resolved);
    }

    // ═══════════════════════════════════════════════════════════
    //               管理函数（ADMIN_ROLE）
    // ═══════════════════════════════════════════════════════════

    function setRingContract(address _ring) external onlyRole(ADMIN_ROLE) {
        // M5: 零地址检查，防止误设导致合约卡死
        if (_ring == address(0)) revert ZeroRingAddress();
        address old = address(ringContract);
        ringContract = IAetherRing(_ring);
        emit RingContractUpdated(old, _ring);
    }

    function grantProposerRole(address account) external onlyRole(ADMIN_ROLE) {
        grantRole(PROPOSER_ROLE, account);
    }

    function revokeProposerRole(address account) external onlyRole(ADMIN_ROLE) {
        revokeRole(PROPOSER_ROLE, account);
    }

    // ── PARAM 可修改的参数（由 PARAM 提案通过 execute 调用） ──

    function setVotingPeriods(uint256 _firstVote, uint256 _publicVote, uint256 _compliance) external onlyRole(ADMIN_ROLE) {
        // M4: 下界校验，防止设为 0 导致同块即可 finalize
        if (_firstVote < 1 hours || _publicVote < 1 hours || _compliance < 1 hours) revert ParamOutOfRange();
        firstVotePeriod = _firstVote;
        publicVotePeriod = _publicVote;
        complianceVotePeriod = _compliance;
    }

    function setTimelocks(uint256 _normal, uint256 _emergency) external onlyRole(ADMIN_ROLE) {
        // M4: 下界校验，防止 timelock=0 导致排队后立即可执行
        if (_normal < 1 hours || _emergency < 1 hours) revert ParamOutOfRange();
        timelockNormal = _normal;
        timelockEmergency = _emergency;
    }

    function setInternalWeight(uint8 tier, uint256 weight) external onlyRole(ADMIN_ROLE) {
        if (tier < 1 || tier > 14) revert UnknownTier(tier);
        // M4: 权重上界校验，防止极端值导致计票失真
        if (weight > 100) revert ParamOutOfRange();
        internalWeight[tier] = weight;
    }

    function cancelProposal(uint256 proposalId) external onlyRole(ADMIN_ROLE) {
        Proposal storage p = proposals[proposalId];
        // M3 + H-8: 终态保护 + 公投阶段保护
        // 禁止对已 Executed/Defeated/Canceled 的提案重复取消
        if (p.status == ProposalStatus.Executed || p.status == ProposalStatus.Defeated
            || p.status == ProposalStatus.Canceled) {
            revert AlreadyInTerminalState();
        }
        // H-8: 公投进行中和元老否决窗口期间禁止取消（防中心化滥用）
        if (p.status == ProposalStatus.PublicVoteActive || p.status == ProposalStatus.PendingVeto
            || p.status == ProposalStatus.Queued) {
            revert AlreadyInTerminalState();
        }
        p.status = ProposalStatus.Canceled;
        emit ProposalCanceled(proposalId);
    }

    // ═══════════════════════════════════════════════════════════
    //               内部辅助
    // ═══════════════════════════════════════════════════════════

    function _isParliamentMember(uint8 tier) internal pure returns (bool) {
        return tier >= 1 && tier <= 3;
    }

    function _isFederationMember(uint8 tier) internal pure returns (bool) {
        return tier >= 4 && tier <= 6;
    }

    function _isTribunalMember(uint8 tier) internal pure returns (bool) {
        return tier >= 7 && tier <= 9;
    }

    function _stanceOf(uint256 forW, uint256 againstW) internal pure returns (ChamberStance) {
        if (forW > againstW) return ChamberStance.FOR;
        if (againstW > forW) return ChamberStance.AGAINST;
        return ChamberStance.NEUTRAL;
    }

    function _countStance(ChamberStance s, ChamberStance target) internal pure returns (uint256) {
        return s == target ? 1 : 0;
    }

    function _checkParamWhitelist(bytes memory payload) internal pure {
        if (payload.length < 4) revert ParamSelectorNotWhitelisted(bytes4(0));
        bytes4 selector;
        assembly ("memory-safe") {
            selector := mload(add(payload, 32))
        }
        if (selector != SEL_SET_VOTING_PERIODS && selector != SEL_SET_TIMELOCKS
            && selector != SEL_SET_INTERNAL_WEIGHT)
        {
            revert ParamSelectorNotWhitelisted(selector);
        }
    }
}
