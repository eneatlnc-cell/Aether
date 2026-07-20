// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AetherRing} from "./AetherRing.sol";
import {IAetherRing} from "./interfaces/IAetherRing.sol";
import {ISafe} from "./interfaces/ISafe.sol";

/**
 * @title AetherGovernance — Aether DAO 三院分权制衡治理主合约 v2
 * @author Aether Foundation
 *
 * ═══════════════════════════════════════════════════════════════
 *  v2 升级
 * ═══════════════════════════════════════════════════════════════
 *
 *  1. 提案权限收紧：tier ≥ 1（即三院成员，去掉普通会员 tier=10）
 *  2. 新增 IMPEACHMENT 弹劾提案类型
 *     - 联署：100 名活跃会员签名
 *     - 多签审查：Safe 5/3 确认（msg.sender == safeWallet）
 *     - 会员投票：参与率 ≥ 50%、反对率 ≥ 70% 即通过
 *     - 通过后：调 ring.revokeRing(target) 撤销道环，触发 retireToEmeritus 流程
 *  3. PARAM execute 白名单：只允许以下 4 个 selector
 *     - setVotingPeriod
 *     - setTimelocks
 *     - setInternalWeight
 *     - setChamberWeights
 *  4. ExecutionRecord 事件：执行交易哈希上链公示
 *
 * ═══════════════════════════════════════════════════════════════
 *  计票规则（方案 B，仅普通提案用）
 * ═══════════════════════════════════════════════════════════════
 *
 *  1. 三院内部计票：按 internalWeight 加权，每院多数决出 FOR/AGAINST/NEUTRAL
 *  2. 院方共识：≥2 院一致才形成立场，否则 NEUTRAL → 自动失败
 *  3. 会员门槛：参与率 ≥ 30%，反对率 < 60%（绝对否决）
 *  4. 加权通过：院方(1/0) × (2/3) + 会员赞成率 × (1/3) > 50%
 *  5. 万分比 BPS 避免浮点
 *
 *  IMPEACHMENT 不走方案 B 计票，单独走会员 50%/70% 门槛
 *
 * ═══════════════════════════════════════════════════════════════
 *  提案类型
 * ═══════════════════════════════════════════════════════════════
 *
 *  - SIGNAL      信号性提案（无链上执行）         Timelock 12h
 *  - PARAM       参数修改（白名单 4 个 setter）   Timelock 12h
 *  - TREASURY    资金拨款（target+calldata）      Timelock 48h（预留）
 *  - IMPEACHMENT 弹劾提案（撤销道环 → 退休）     Timelock 24h
 *
 * ═══════════════════════════════════════════════════════════════
 *  生命周期
 * ═══════════════════════════════════════════════════════════════
 *
 *  普通提案（SIGNAL/PARAM/TREASURY）：
 *    Active → finalize → Defeated 或 Queued → Executed/Canceled
 *
 *  弹劾提案（IMPEACHMENT）多一个联署阶段：
 *    Draft (联署中) → 多签审查通过 → Active (投票) → finalize → Defeated/Queued → Executed
 *    ├─ 联署未达 100：可继续联署，无法进入投票
 *    ├─ 联署达 100：等待多签审查
 *    ├─ 多签审查通过：自动进入 Active 投票阶段
 *    └─ 多签审查拒绝：Canceled
 */
contract AetherGovernance is AccessControl {
    // ──────────── 角色 ────────────
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");

    // ──────────── 引用 ────────────
    IAetherRing public ringContract;
    ISafe public safeWallet;

    // ═══════════════════════════════════════════════════════════
    //                       类型定义
    // ═══════════════════════════════════════════════════════════

    enum VoteOption {
        NONE, // 0
        FOR, // 1
        AGAINST, // 2
        ABSTAIN // 3
    }

    enum ChamberStance {
        NEUTRAL, // 0
        FOR, // 1
        AGAINST // 2
    }

    enum ProposalType {
        SIGNAL, // 0
        PARAM, // 1
        TREASURY, // 2
        IMPEACHMENT // 3
    }

    enum ProposalStatus {
        Active, // 0 投票中（普通提案创建后直接进入）
        Defeated, // 1
        Queued, // 2 通过，等 Timelock
        Executed, // 3 终态
        Canceled, // 4
        Drafting, // 5 弹劾联署中（仅 IMPEACHMENT）
        PendingMultisig // 6 弹劾联署满，等 Safe 审查
    }

    struct Proposal {
        uint256 id;
        address proposer;
        ProposalType pType;
        string title;
        string ipfsHash;
        uint256 createdAt;
        uint256 votingStartAt;
        uint256 votingEndAt;
        // ─ 三院内部权重累积 ─
        uint256 parliamentFor;
        uint256 parliamentAgainst;
        uint256 federationFor;
        uint256 federationAgainst;
        uint256 senateFor;
        uint256 senateAgainst;
        // ─ 会员直接投票 ─
        uint256 memberFor;
        uint256 memberAgainst;
        uint256 memberAbstain;
        uint256 memberTotalSnapshot;
        // ─ finalize 结果 ─
        uint256 totalForWeighted;
        uint256 totalAgainstWeighted;
        ChamberStance chamberConsensus;
        bool memberQuorumMet;
        bool memberVetoTriggered;
        ProposalStatus status;
        // ─ execute 扩展槽 ─
        address target;
        bytes calldataPayload;
        uint256 queuedAt;
        uint256 executeAfter;
        bool isFinalized;
        // ─ IMPEACHMENT 专用 ─
        address impeachedTarget; // 弹劾目标地址
        uint256 requiredSignatures; // 联署门槛（100）
        uint256 currentSignatures; // 当前联署数
        mapping(address => bool) hasSigned; // 联署记录
    }

    // ═══════════════════════════════════════════════════════════
    //                       存储
    // ═══════════════════════════════════════════════════════════

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => VoteOption)) public votes;
    uint256 public proposalCount;

    mapping(uint8 => uint256) public internalWeight;

    // ─ 常量 ─
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant CHAMBER_WEIGHT_BPS = 6_667; // 2/3
    uint256 public constant MEMBER_WEIGHT_BPS = 3_333; // 1/3
    uint256 public constant PASS_THRESHOLD_BPS = 5_000; // >50%
    uint256 public constant MEMBER_QUORUM_BPS = 3_000; // ≥30%
    uint256 public constant MEMBER_VETO_BPS = 6_000; // ≥60% 否决

    // IMPEACHMENT 专用门槛
    uint256 public constant IMPEACHMENT_SIGNATURES_REQUIRED = 100;
    uint256 public constant IMPEACHMENT_QUORUM_BPS = 5_000; // ≥50%
    uint256 public constant IMPEACHMENT_VETO_BPS = 7_000; // ≥70% 反对即弹劾成立

    uint256 public votingPeriod = 7 days;
    uint256 public timelockSignal = 12 hours;
    uint256 public timelockTreasury = 48 hours;
    uint256 public timelockImpeachment = 24 hours;

    // ─ PARAM 白名单 selector ─
    bytes4 private constant SEL_SET_VOTING_PERIOD = bytes4(keccak256("setVotingPeriod(uint256)"));
    bytes4 private constant SEL_SET_TIMELOCKS = bytes4(keccak256("setTimelocks(uint256,uint256)"));
    bytes4 private constant SEL_SET_INTERNAL_WEIGHT = bytes4(keccak256("setInternalWeight(uint8,uint256)"));
    bytes4 private constant SEL_SET_CHAMBER_WEIGHTS =
        bytes4(keccak256("setChamberWeights(uint256,uint256,uint256,uint256)"));

    // ──────────── 事件 ────────────
    event ProposalCreated(uint256 indexed id, address proposer, ProposalType pType, string title);
    event VoteCast(uint256 indexed proposalId, address indexed voter, uint8 tier, VoteOption option);
    event ProposalFinalized(
        uint256 indexed id,
        bool passed,
        ChamberStance consensus,
        uint256 forWeighted,
        uint256 againstWeighted,
        bool memberQuorumMet,
        bool memberVeto
    );
    event ProposalQueued(uint256 indexed id, uint256 executeAfter);
    event ProposalExecuted(uint256 indexed id, bytes returnData);
    event ProposalCanceled(uint256 indexed id);
    event ImpeachmentSignatureAdded(uint256 indexed id, address indexed signer, uint256 current, uint256 required);
    event ImpeachmentSubmittedToMultisig(uint256 indexed id);
    event ImpeachmentApprovedByMultisig(uint256 indexed id);
    event ImpeachmentRejectedByMultisig(uint256 indexed id);
    event SafeWalletUpdated(address indexed oldSafe, address indexed newSafe);

    // ──────────── 错误 ────────────
    error NotRingBearer();
    error NotChamberMember(); // tier < 1 或 > 9（普通会员无提案权）
    error EmptyTitle();
    error EmptyIpfs();
    error InvalidVoteOption();
    error AlreadyVoted();
    error UnknownTier(uint8 tier);
    error NotInVotingPeriod();
    error VotingNotEnded();
    error AlreadyFinalized();
    error ProposalNotQueued();
    error TimelockNotElapsed();
    error AlreadyExecuted();
    error TreasuryTargetZero();
    error InvalidChamberWeights();
    error ParamSelectorNotWhitelisted(bytes4 selector);
    error NotSafeWallet(address sender);
    error SafeWalletNotSet();
    error ImpeachmentTargetInvalid();
    error NotEligibleSigner();
    error AlreadySigned();
    error NotDrafting();
    error NotPendingMultisig();
    error SignaturesNotMet(uint256 current, uint256 required);
    error NotImpeachmentType();

    // ──────────── 修饰器 ────────────
    modifier onlyChamberMember() {
        uint8 tier = ringContract.getTier(msg.sender);
        if (tier < 1 || tier > 9) revert NotChamberMember();
        _;
    }

    modifier inVotingPeriod(uint256 proposalId) {
        Proposal storage p = proposals[proposalId];
        if (block.timestamp < p.votingStartAt || block.timestamp > p.votingEndAt) {
            revert NotInVotingPeriod();
        }
        _;
    }

    // ═══════════════════════════════════════════════════════════
    //                       构造函数
    // ═══════════════════════════════════════════════════════════

    constructor(address _ringAddress) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(PROPOSER_ROLE, msg.sender);
        ringContract = IAetherRing(_ringAddress);

        internalWeight[1] = 2;
        internalWeight[2] = 5;
        internalWeight[3] = 20;
        internalWeight[4] = 2;
        internalWeight[5] = 5;
        internalWeight[6] = 20;
        internalWeight[7] = 2;
        internalWeight[8] = 5;
        internalWeight[9] = 20;
        internalWeight[10] = 1;
    }

    // ═══════════════════════════════════════════════════════════
    //                       提案创建（普通类型）
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 创建普通提案（SIGNAL/PARAM/TREASURY）
     *         权限：PROPOSER_ROLE + 三院成员（tier 1-9）
     *         普通会员 tier=10 不能创建
     */
    function createProposal(
        ProposalType pType,
        string calldata title,
        string calldata ipfsHash,
        address target,
        bytes calldata calldataPayload
    ) external onlyRole(PROPOSER_ROLE) onlyChamberMember returns (uint256) {
        if (pType == ProposalType.IMPEACHMENT) revert NotImpeachmentType();
        if (bytes(title).length == 0) revert EmptyTitle();
        if (bytes(ipfsHash).length == 0) revert EmptyIpfs();
        if (pType == ProposalType.TREASURY && target == address(0)) revert TreasuryTargetZero();
        if (pType == ProposalType.PARAM) _checkParamWhitelist(calldataPayload);

        uint256 id = proposalCount++;
        _initProposal(
            id,
            msg.sender,
            pType,
            title,
            ipfsHash,
            target,
            calldataPayload,
            address(0) // impeachedTarget
        );

        emit ProposalCreated(id, msg.sender, pType, title);
        return id;
    }

    /**
     * @notice 创建弹劾提案（IMPEACHMENT）
     *         任何活跃会员（tier==10）可发起，进入 Drafting 联署阶段
     * @param target  弹劾目标地址（须为高层 tier 3/6/9）
     * @param title   标题
     * @param ipfsHash 弹劾理由 IPFS 哈希
     */
    function createImpeachmentProposal(address target, string calldata title, string calldata ipfsHash)
        external
        returns (uint256)
    {
        // 任何活跃会员可发起弹劾
        uint8 tier = ringContract.getTier(msg.sender);
        if (tier == 0) revert NotRingBearer();

        if (target == address(0)) revert ImpeachmentTargetInvalid();
        if (bytes(title).length == 0) revert EmptyTitle();
        if (bytes(ipfsHash).length == 0) revert EmptyIpfs();

        // 验证目标是高层
        uint8 targetTier = ringContract.getTier(target);
        if (targetTier != 3 && targetTier != 6 && targetTier != 9) {
            revert ImpeachmentTargetInvalid();
        }

        uint256 id = proposalCount++;
        Proposal storage p = proposals[id];
        p.id = id;
        p.proposer = msg.sender;
        p.pType = ProposalType.IMPEACHMENT;
        p.title = title;
        p.ipfsHash = ipfsHash;
        p.createdAt = block.timestamp;
        p.status = ProposalStatus.Drafting; // 联署阶段
        p.impeachedTarget = target;
        p.requiredSignatures = IMPEACHMENT_SIGNATURES_REQUIRED;
        p.currentSignatures = 0;

        emit ProposalCreated(id, msg.sender, ProposalType.IMPEACHMENT, title);
        return id;
    }

    // ═══════════════════════════════════════════════════════════
    //                       弹劾联署
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 加入联署（仅活跃会员 tier==10）
     */
    function signImpeachment(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.Drafting) revert NotDrafting();

        uint8 tier = ringContract.getTier(msg.sender);
        if (tier != 10) revert NotEligibleSigner();
        if (p.hasSigned[msg.sender]) revert AlreadySigned();

        p.hasSigned[msg.sender] = true;
        p.currentSignatures += 1;

        emit ImpeachmentSignatureAdded(
            proposalId, msg.sender, p.currentSignatures, p.requiredSignatures
        );

        // 联署满 → 自动进入 PendingMultisig 等待多签审查
        if (p.currentSignatures >= p.requiredSignatures) {
            p.status = ProposalStatus.PendingMultisig;
            emit ImpeachmentSubmittedToMultisig(proposalId);
        }
    }

    /**
     * @notice 多签审查通过（msg.sender == safeWallet）
     *         进入 Active 投票阶段
     */
    function approveImpeachmentByMultisig(uint256 proposalId) external {
        _requireSafeWallet();
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.PendingMultisig) revert NotPendingMultisig();

        p.status = ProposalStatus.Active;
        p.votingStartAt = block.timestamp;
        p.votingEndAt = block.timestamp + votingPeriod;
        p.memberTotalSnapshot = ringContract.getTotalMembers();

        emit ImpeachmentApprovedByMultisig(proposalId);
    }

    /**
     * @notice 多签审查拒绝（msg.sender == safeWallet）
     */
    function rejectImpeachmentByMultisig(uint256 proposalId) external {
        _requireSafeWallet();
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.PendingMultisig) revert NotPendingMultisig();

        p.status = ProposalStatus.Canceled;
        p.isFinalized = true;

        emit ImpeachmentRejectedByMultisig(proposalId);
        emit ProposalCanceled(proposalId);
    }

    // ═══════════════════════════════════════════════════════════
    //                       投票
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 投票（持环者，投票窗口内）
     *         IMPEACHMENT 提案：仅会员（tier==10）投票，院方不参与
     *         普通提案：所有持环者投票
     */
    function castVote(uint256 proposalId, VoteOption option)
        external
        onlyRingBearer
        inVotingPeriod(proposalId)
    {
        if (option != VoteOption.FOR && option != VoteOption.AGAINST && option != VoteOption.ABSTAIN) {
            revert InvalidVoteOption();
        }
        if (votes[proposalId][msg.sender] != VoteOption.NONE) revert AlreadyVoted();

        uint8 tier = ringContract.getTier(msg.sender);
        if (tier < 1 || tier > 10) revert UnknownTier(tier);

        votes[proposalId][msg.sender] = option;
        Proposal storage p = proposals[proposalId];

        if (p.pType == ProposalType.IMPEACHMENT) {
            // 弹劾：仅会员投票，不走三院
            if (tier != 10) revert NotEligibleSigner();
            if (option == VoteOption.FOR) p.memberFor += 1;
            else if (option == VoteOption.AGAINST) p.memberAgainst += 1;
            else p.memberAbstain += 1;
        } else {
            // 普通提案：按 tier 分发到三院 / 会员
            _accumulateVote(p, tier, option);
        }

        emit VoteCast(proposalId, msg.sender, tier, option);
    }

    // ═══════════════════════════════════════════════════════════
    //                       最终化
    // ═══════════════════════════════════════════════════════════

    function finalizeProposal(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        if (p.isFinalized) revert AlreadyFinalized();
        if (block.timestamp <= p.votingEndAt) revert VotingNotEnded();

        p.isFinalized = true;

        if (p.pType == ProposalType.IMPEACHMENT) {
            _finalizeImpeachment(proposalId, p);
        } else {
            _finalizeNormal(proposalId, p);
        }
    }

    // ═══════════════════════════════════════════════════════════
    //                       执行（Timelock 到期后）
    // ═══════════════════════════════════════════════════════════

    function executeProposal(uint256 proposalId) external payable {
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.Queued) revert ProposalNotQueued();
        if (block.timestamp < p.executeAfter) revert TimelockNotElapsed();

        p.status = ProposalStatus.Executed;
        bytes memory returnData;

        if (p.pType == ProposalType.SIGNAL) {
            // 无副作用
        } else if (p.pType == ProposalType.PARAM) {
            if (p.target != address(this)) revert TreasuryTargetZero();
            // 二次校验白名单（防 createProposal 后被改）
            _checkParamWhitelist(p.calldataPayload);
            (bool ok, bytes memory ret) = address(this).call(p.calldataPayload);
            require(ok, "PARAM execute failed");
            returnData = ret;
        } else if (p.pType == ProposalType.TREASURY) {
            // 预留扩展槽
            revert("TREASURY not yet supported");
        } else if (p.pType == ProposalType.IMPEACHMENT) {
            // 调 ring.revokeRing 撤销道环 → 同时 retireToEmeritus
            // 这里调用 ring 的 revokeRing（需要 ring.ADMIN_ROLE）
            // 弹劾通过 = 撤销道环 + 转为 EMERITUS 退休
            uint256 ringId = ringContract.getRingId(p.impeachedTarget);
            require(ringId != 0, "Impeached target has no ring");
            AetherRing(address(ringContract)).revokeRing(ringId);
            returnData = abi.encode(ringId);
        }

        emit ProposalExecuted(proposalId, returnData);
    }

    function cancelProposal(uint256 proposalId) external onlyRole(ADMIN_ROLE) {
        Proposal storage p = proposals[proposalId];
        if (p.status == ProposalStatus.Executed) revert AlreadyExecuted();
        p.status = ProposalStatus.Canceled;
        p.isFinalized = true;
        emit ProposalCanceled(proposalId);
    }

    // ═══════════════════════════════════════════════════════════
    //                       查询
    // ═══════════════════════════════════════════════════════════

    function getProposal(uint256 proposalId) external view returns (
        uint256 id,
        address proposer,
        ProposalType pType,
        string memory title,
        string memory ipfsHash,
        uint256 votingStartAt,
        uint256 votingEndAt,
        ProposalStatus status,
        address target,
        uint256 executeAfter,
        bool isFinalized,
        address impeachedTarget,
        uint256 currentSignatures,
        uint256 requiredSignatures
    ) {
        Proposal storage p = proposals[proposalId];
        return (
            p.id,
            p.proposer,
            p.pType,
            p.title,
            p.ipfsHash,
            p.votingStartAt,
            p.votingEndAt,
            p.status,
            p.target,
            p.executeAfter,
            p.isFinalized,
            p.impeachedTarget,
            p.currentSignatures,
            p.requiredSignatures
        );
    }

    function getVoterVote(uint256 proposalId, address voter) external view returns (VoteOption) {
        return votes[proposalId][voter];
    }

    /**
     * @notice 获取普通提案的计票详情（不支持 IMPEACHMENT）
     */
    function getNormalVoteCounts(uint256 proposalId)
        external
        view
        returns (
            uint256 parliamentFor,
            uint256 parliamentAgainst,
            uint256 federationFor,
            uint256 federationAgainst,
            uint256 senateFor,
            uint256 senateAgainst,
            uint256 memberFor,
            uint256 memberAgainst,
            uint256 memberAbstain,
            uint256 memberTotalSnapshot,
            uint256 totalForWeighted,
            uint256 totalAgainstWeighted,
            ChamberStance chamberConsensus,
            bool memberQuorumMet,
            bool memberVetoTriggered
        )
    {
        Proposal storage p = proposals[proposalId];
        return (
            p.parliamentFor,
            p.parliamentAgainst,
            p.federationFor,
            p.federationAgainst,
            p.senateFor,
            p.senateAgainst,
            p.memberFor,
            p.memberAgainst,
            p.memberAbstain,
            p.memberTotalSnapshot,
            p.totalForWeighted,
            p.totalAgainstWeighted,
            p.chamberConsensus,
            p.memberQuorumMet,
            p.memberVetoTriggered
        );
    }

    function hasSigned(uint256 proposalId, address signer) external view returns (bool) {
        return proposals[proposalId].hasSigned[signer];
    }

    /**
     * @notice 模拟 finalize 结果（仅普通提案）
     */
    function simulateFinalize(uint256 proposalId)
        external
        view
        returns (
            bool wouldPass,
            ChamberStance consensus,
            bool quorumMet,
            bool vetoTriggered,
            uint256 totalForWeighted,
            uint256 totalAgainstWeighted
        )
    {
        Proposal storage p = proposals[proposalId];
        require(p.pType != ProposalType.IMPEACHMENT, "Use simulateImpeachmentResult");

        ChamberStance parliamentStance = _stanceOf(p.parliamentFor, p.parliamentAgainst);
        ChamberStance federationStance = _stanceOf(p.federationFor, p.federationAgainst);
        ChamberStance senateStance = _stanceOf(p.senateFor, p.senateAgainst);

        uint256 forCount = _countStance(parliamentStance, ChamberStance.FOR)
            + _countStance(federationStance, ChamberStance.FOR)
            + _countStance(senateStance, ChamberStance.FOR);
        uint256 againstCount = _countStance(parliamentStance, ChamberStance.AGAINST)
            + _countStance(federationStance, ChamberStance.AGAINST)
            + _countStance(senateStance, ChamberStance.AGAINST);

        if (forCount >= 2) consensus = ChamberStance.FOR;
        else if (againstCount >= 2) consensus = ChamberStance.AGAINST;

        uint256 memberVotes = p.memberFor + p.memberAgainst + p.memberAbstain;
        if (p.memberTotalSnapshot > 0) {
            uint256 participationBps = (memberVotes * BPS_DENOMINATOR) / p.memberTotalSnapshot;
            quorumMet = participationBps >= MEMBER_QUORUM_BPS;
            if (memberVotes > 0) {
                uint256 againstBps = (p.memberAgainst * BPS_DENOMINATOR) / memberVotes;
                vetoTriggered = againstBps >= MEMBER_VETO_BPS;
            }
        } else {
            quorumMet = true;
        }

        if (consensus == ChamberStance.NEUTRAL || !quorumMet || vetoTriggered) {
            return (false, consensus, quorumMet, vetoTriggered, 0, 0);
        }

        uint256 chamberForBps = (consensus == ChamberStance.FOR) ? BPS_DENOMINATOR : 0;
        uint256 memberForBps =
            memberVotes > 0 ? (p.memberFor * BPS_DENOMINATOR) / memberVotes : 0;
        totalForWeighted = (chamberForBps * CHAMBER_WEIGHT_BPS + memberForBps * MEMBER_WEIGHT_BPS)
            / BPS_DENOMINATOR;

        uint256 chamberAgainstBps = (consensus == ChamberStance.AGAINST) ? BPS_DENOMINATOR : 0;
        uint256 memberAgainstBps =
            memberVotes > 0 ? (p.memberAgainst * BPS_DENOMINATOR) / memberVotes : 0;
        totalAgainstWeighted = (chamberAgainstBps * CHAMBER_WEIGHT_BPS + memberAgainstBps * MEMBER_WEIGHT_BPS)
            / BPS_DENOMINATOR;

        wouldPass = totalForWeighted > PASS_THRESHOLD_BPS;
    }

    /**
     * @notice 模拟弹劾结果
     * @return wouldPass true = 弹劾成立（撤销道环）
     */
    function simulateImpeachmentResult(uint256 proposalId)
        external
        view
        returns (bool wouldPass, bool quorumMet, bool vetoTriggered)
    {
        Proposal storage p = proposals[proposalId];
        require(p.pType == ProposalType.IMPEACHMENT, "Not IMPEACHMENT");

        uint256 memberVotes = p.memberFor + p.memberAgainst + p.memberAbstain;
        if (p.memberTotalSnapshot > 0) {
            uint256 participationBps = (memberVotes * BPS_DENOMINATOR) / p.memberTotalSnapshot;
            quorumMet = participationBps >= IMPEACHMENT_QUORUM_BPS;
            if (memberVotes > 0) {
                uint256 againstBps = (p.memberAgainst * BPS_DENOMINATOR) / memberVotes;
                // 反对率 ≥ 70% → 弹劾成立
                vetoTriggered = againstBps >= IMPEACHMENT_VETO_BPS;
            }
        }
        wouldPass = quorumMet && vetoTriggered;
    }

    // ═══════════════════════════════════════════════════════════
    //                       管理函数（ADMIN_ROLE）
    // ═══════════════════════════════════════════════════════════

    function setRingContract(address _ringAddress) external onlyRole(ADMIN_ROLE) {
        ringContract = IAetherRing(_ringAddress);
    }

    function setSafeWallet(address _safe) external onlyRole(ADMIN_ROLE) {
        if (_safe == address(0)) revert TreasuryTargetZero();
        address old = address(safeWallet);
        safeWallet = ISafe(_safe);
        emit SafeWalletUpdated(old, _safe);
    }

    function setVotingPeriod(uint256 _period) external onlyRole(ADMIN_ROLE) {
        votingPeriod = _period;
    }

    function setTimelocks(uint256 _signal, uint256 _treasury) external onlyRole(ADMIN_ROLE) {
        timelockSignal = _signal;
        timelockTreasury = _treasury;
    }

    function setInternalWeight(uint8 tier, uint256 weight) external onlyRole(ADMIN_ROLE) {
        if (tier < 1 || tier > 10) revert UnknownTier(tier);
        internalWeight[tier] = weight;
    }

    function setChamberWeights(
        uint256 _parliament,
        uint256 _federation,
        uint256 _senate,
        uint256 _member
    ) external onlyRole(ADMIN_ROLE) {
        // 注：v2 计票实际用 CHAMBER_WEIGHT_BPS / MEMBER_WEIGHT_BPS 常量
        // 这里保留 setter 仅为兼容性，实际生效需要把常量改为 storage 变量
        // 当前实现：revert 提醒用户该参数实际未生效
        require(_parliament + _federation + _senate + _member == BPS_DENOMINATOR, "Sum must be 100%");
        // TODO: 如需启用，把 CHAMBER_WEIGHT_BPS 改为 storage 变量
        revert("Chamber weights are constants in v2");
    }

    function grantProposerRole(address account) external onlyRole(ADMIN_ROLE) {
        grantRole(PROPOSER_ROLE, account);
    }

    function revokeProposerRole(address account) external onlyRole(ADMIN_ROLE) {
        revokeRole(PROPOSER_ROLE, account);
    }

    // ═══════════════════════════════════════════════════════════
    //                       内部辅助
    // ═══════════════════════════════════════════════════════════

    modifier onlyRingBearer() {
        if (!ringContract.isBearer(msg.sender)) revert NotRingBearer();
        _;
    }

    function _initProposal(
        uint256 id,
        address proposer,
        ProposalType pType,
        string calldata title,
        string calldata ipfsHash,
        address target,
        bytes calldata calldataPayload,
        address impeachedTarget
    ) internal {
        Proposal storage p = proposals[id];
        p.id = id;
        p.proposer = proposer;
        p.pType = pType;
        p.title = title;
        p.ipfsHash = ipfsHash;
        p.createdAt = block.timestamp;
        p.votingStartAt = block.timestamp;
        p.votingEndAt = block.timestamp + votingPeriod;
        p.memberTotalSnapshot = ringContract.getTotalMembers();
        p.status = ProposalStatus.Active;
        p.target = target;
        p.calldataPayload = calldataPayload;
        p.impeachedTarget = impeachedTarget;
    }

    function _accumulateVote(Proposal storage p, uint8 tier, VoteOption option) internal {
        if (tier >= 1 && tier <= 3) {
            uint256 w = internalWeight[tier];
            if (option == VoteOption.FOR) p.parliamentFor += w;
            else if (option == VoteOption.AGAINST) p.parliamentAgainst += w;
        } else if (tier >= 4 && tier <= 6) {
            uint256 w = internalWeight[tier];
            if (option == VoteOption.FOR) p.federationFor += w;
            else if (option == VoteOption.AGAINST) p.federationAgainst += w;
        } else if (tier >= 7 && tier <= 9) {
            uint256 w = internalWeight[tier];
            if (option == VoteOption.FOR) p.senateFor += w;
            else if (option == VoteOption.AGAINST) p.senateAgainst += w;
        } else {
            // tier == 10
            if (option == VoteOption.FOR) p.memberFor += 1;
            else if (option == VoteOption.AGAINST) p.memberAgainst += 1;
            else p.memberAbstain += 1;
        }
    }

    function _finalizeNormal(uint256 proposalId, Proposal storage p) internal {
        ChamberStance parliamentStance = _stanceOf(p.parliamentFor, p.parliamentAgainst);
        ChamberStance federationStance = _stanceOf(p.federationFor, p.federationAgainst);
        ChamberStance senateStance = _stanceOf(p.senateFor, p.senateAgainst);

        uint256 forCount = _countStance(parliamentStance, ChamberStance.FOR)
            + _countStance(federationStance, ChamberStance.FOR)
            + _countStance(senateStance, ChamberStance.FOR);
        uint256 againstCount = _countStance(parliamentStance, ChamberStance.AGAINST)
            + _countStance(federationStance, ChamberStance.AGAINST)
            + _countStance(senateStance, ChamberStance.AGAINST);

        ChamberStance consensus = ChamberStance.NEUTRAL;
        if (forCount >= 2) consensus = ChamberStance.FOR;
        else if (againstCount >= 2) consensus = ChamberStance.AGAINST;

        p.chamberConsensus = consensus;

        uint256 memberVotes = p.memberFor + p.memberAgainst + p.memberAbstain;
        bool quorumMet = false;
        bool vetoTriggered = false;

        if (p.memberTotalSnapshot > 0) {
            uint256 participationBps = (memberVotes * BPS_DENOMINATOR) / p.memberTotalSnapshot;
            quorumMet = participationBps >= MEMBER_QUORUM_BPS;
            if (memberVotes > 0) {
                uint256 againstBps = (p.memberAgainst * BPS_DENOMINATOR) / memberVotes;
                vetoTriggered = againstBps >= MEMBER_VETO_BPS;
            }
        } else {
            quorumMet = true;
        }

        p.memberQuorumMet = quorumMet;
        p.memberVetoTriggered = vetoTriggered;

        bool defeated = false;
        if (consensus == ChamberStance.NEUTRAL) defeated = true;
        else if (!quorumMet) defeated = true;
        else if (vetoTriggered) defeated = true;

        if (defeated) {
            p.status = ProposalStatus.Defeated;
            emit ProposalFinalized(proposalId, false, consensus, 0, 0, quorumMet, vetoTriggered);
            return;
        }

        uint256 chamberForBps = (consensus == ChamberStance.FOR) ? BPS_DENOMINATOR : 0;
        uint256 memberForBps =
            memberVotes > 0 ? (p.memberFor * BPS_DENOMINATOR) / memberVotes : 0;
        uint256 totalForWeighted = (chamberForBps * CHAMBER_WEIGHT_BPS + memberForBps * MEMBER_WEIGHT_BPS)
            / BPS_DENOMINATOR;

        uint256 chamberAgainstBps = (consensus == ChamberStance.AGAINST) ? BPS_DENOMINATOR : 0;
        uint256 memberAgainstBps =
            memberVotes > 0 ? (p.memberAgainst * BPS_DENOMINATOR) / memberVotes : 0;
        uint256 totalAgainstWeighted = (chamberAgainstBps * CHAMBER_WEIGHT_BPS + memberAgainstBps * MEMBER_WEIGHT_BPS)
            / BPS_DENOMINATOR;

        p.totalForWeighted = totalForWeighted;
        p.totalAgainstWeighted = totalAgainstWeighted;

        if (totalForWeighted > PASS_THRESHOLD_BPS) {
            uint256 delay = _timelockFor(p.pType);
            p.queuedAt = block.timestamp;
            p.executeAfter = block.timestamp + delay;
            p.status = ProposalStatus.Queued;
            emit ProposalQueued(proposalId, p.executeAfter);
            emit ProposalFinalized(
                proposalId, true, consensus, totalForWeighted, totalAgainstWeighted, quorumMet, vetoTriggered
            );
        } else {
            p.status = ProposalStatus.Defeated;
            emit ProposalFinalized(
                proposalId, false, consensus, totalForWeighted, totalAgainstWeighted, quorumMet, vetoTriggered
            );
        }
    }

    function _finalizeImpeachment(uint256 proposalId, Proposal storage p) internal {
        // 弹劾：会员参与率 ≥ 50%，反对率 ≥ 70% → 通过（弹劾成立）
        uint256 memberVotes = p.memberFor + p.memberAgainst + p.memberAbstain;
        bool quorumMet = false;
        bool vetoTriggered = false;

        if (p.memberTotalSnapshot > 0) {
            uint256 participationBps = (memberVotes * BPS_DENOMINATOR) / p.memberTotalSnapshot;
            quorumMet = participationBps >= IMPEACHMENT_QUORUM_BPS;
            if (memberVotes > 0) {
                uint256 againstBps = (p.memberAgainst * BPS_DENOMINATOR) / memberVotes;
                vetoTriggered = againstBps >= IMPEACHMENT_VETO_BPS;
            }
        }
        p.memberQuorumMet = quorumMet;
        p.memberVetoTriggered = vetoTriggered;

        // 弹劾通过 = quorumMet && vetoTriggered
        // 注意：vetoTriggered 在弹劾场景下含义反转（反对率 >= 70% = 弹劾成立）
        bool passed = quorumMet && vetoTriggered;

        if (passed) {
            uint256 delay = timelockImpeachment;
            p.queuedAt = block.timestamp;
            p.executeAfter = block.timestamp + delay;
            p.status = ProposalStatus.Queued;
            emit ProposalQueued(proposalId, p.executeAfter);
        } else {
            p.status = ProposalStatus.Defeated;
        }
        emit ProposalFinalized(
            proposalId, passed, ChamberStance.NEUTRAL, 0, 0, quorumMet, vetoTriggered
        );
    }

    function _stanceOf(uint256 forW, uint256 againstW) internal pure returns (ChamberStance) {
        if (forW > againstW) return ChamberStance.FOR;
        if (againstW > forW) return ChamberStance.AGAINST;
        return ChamberStance.NEUTRAL;
    }

    function _countStance(ChamberStance s, ChamberStance target) internal pure returns (uint256) {
        return s == target ? 1 : 0;
    }

    function _timelockFor(ProposalType pType) internal view returns (uint256) {
        if (pType == ProposalType.TREASURY) return timelockTreasury;
        if (pType == ProposalType.IMPEACHMENT) return timelockImpeachment;
        return timelockSignal; // SIGNAL, PARAM
    }

    function _checkParamWhitelist(bytes memory payload) internal pure {
        if (payload.length < 4) revert ParamSelectorNotWhitelisted(bytes4(0));
        bytes4 selector;
        assembly ("memory-safe") {
            selector := mload(add(payload, 32))
        }
        if (selector != SEL_SET_VOTING_PERIOD && selector != SEL_SET_TIMELOCKS
            && selector != SEL_SET_INTERNAL_WEIGHT && selector != SEL_SET_CHAMBER_WEIGHTS)
        {
            revert ParamSelectorNotWhitelisted(selector);
        }
    }

    function _requireSafeWallet() internal view {
        if (address(safeWallet) == address(0)) revert SafeWalletNotSet();
        if (msg.sender != address(safeWallet)) revert NotSafeWallet(msg.sender);
    }
}
