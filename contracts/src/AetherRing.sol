// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IAetherRing} from "./interfaces/IAetherRing.sol";
import {ISafe} from "./interfaces/ISafe.sol";

/**
 * @title AetherRing — 道环灵魂绑定代币（SBT）v3
 * @author Aether Foundation
 *
 * v3 升级要点（基于 37 项已确认决策）：
 *  ┌──────────────────────────────────────────────────────────────┐
 *  │ 1. 14 级权级（三院 1-9 + 理事会 10-12 + 元老 13 + 公民 14） │
 *  │ 2. 席位上限：基层 60 / 中层 12 / 高层 2（每院各自）           │
 *  │    理事会：理事 12 / 常务理事 4 / 理事长 2                     │
 *  │    任命元老上限 9（退休元老无上限）                            │
 *  │ 3. 任期：基层 1 年 / 中层 2 年 / 高层终生 / 理事长 4 年       │
 *  │    不可连任（MAX_CONSECUTIVE_TERMS = 0）                      │
 *  │ 4. 退休转元老：tier 3/6/9/12 → 13，isRetiredElder=true       │
 *  │    任命元老：appointElder()，上限 9，isAppointedElder=true   │
 *  │ 5. 公民休眠：2 年未活动 → isDormant，不计入 quorum 分母      │
 *  │ 6. 公民放弃：renounceCitizenship()，30 天冷却期               │
 *  │ 7. getActiveCitizens() 替代 getTotalMembers()                 │
 *  │ 8. markVoteActivity() 由治理/选举合约回调，更新活动时间        │
 *  └──────────────────────────────────────────────────────────────┘
 *
 * 权级体系（14 级）：
 *  ┌──────────────────────────────────────────────────────────┐
 *  │ 1  PARLIAMENT_MEMBER    议员    (议会基层，权重 1)        │
 *  │ 2  PARLIAMENT_SENIOR    参议员  (议会中层，权重 3)        │
 *  │ 3  PARLIAMENT_SPEAKER   议长    (议会高层，权重 10)       │
 *  │ 4  FEDERATION_MEMBER    委员    (联邦基层，权重 1)        │
 *  │ 5  FEDERATION_SENIOR    委员长  (联邦中层，权重 3)        │
 *  │ 6  FEDERATION_MINISTER  执政    (联邦高层，权重 10)       │
 *  │ 7  TRIBUNAL_JUDGE       法官    (法庭基层，权重 1)        │
 *  │ 8  TRIBUNAL_SENIOR      大法官  (法庭中层，权重 3)        │
 *  │ 9  TRIBUNAL_CHIEF       首席    (法庭高层，权重 10)       │
 *  │ 10 COUNCIL_MEMBER       理事    (理事会基层，权重 0)      │
 *  │ 11 COUNCIL_SENIOR       常务理事(理事会中层，权重 0)      │
 *  │ 12 COUNCIL_CHAIR        理事长  (理事会高层，权重 0)      │
 *  │ 13 ELDER                元老    (独立机构，权重 0)        │
 *  │ 14 CITIZEN              公民    (基金会，权重 1)          │
 *  └──────────────────────────────────────────────────────────┘
 *
 * 任期：
 *  - 基层（tier 1/4/7/10/11）: 365 days，不可连任
 *  - 中层（tier 2/5/8）: 730 days，不可连任
 *  - 高层（tier 3/6/9）: 终生，可荣誉退休转元老
 *  - 理事长（tier 12）: 4 年（COUNCIL_CHAIR_TERM），可连任
 *  - 元老（tier 13）: 终生
 *  - 公民（tier 14）: 无任期，2 年不活动休眠
 */
contract AetherRing is ERC721, AccessControl, IAetherRing {
    // ──────────── 角色 ────────────
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant ELECTION_ROLE = keccak256("ELECTION_ROLE");

    // ──────────── 层级 ────────────
    enum TierLevel {
        NONE, // 0
        GRASSROOTS, // 1 基层
        MID, // 2 中层
        HIGH, // 3 高层
        COUNCIL, // 4 理事会
        ELDER_LEVEL, // 5 元老院
        CITIZEN_LEVEL // 6 公民
    }

    // ──────────── 存储 ────────────
    mapping(uint256 => RingInfo) public ringInfo;
    mapping(address => uint256) public walletToRingId;
    uint256 private _nextTokenId = 1; // 从 1 开始（0 表示"无道环"哨兵）

    // 按权级计数（用于席位上限检查）
    mapping(uint8 => uint256) private _tierCount;

    // 任命元老计数
    uint256 private _appointedElderCount;

    // 休眠公民计数
    uint256 private _dormantCitizenCount;

    // 公民放弃冷却记录
    mapping(address => uint256) public lastRenouncedAt;

    // 多签钱包
    ISafe public safeWallet;

    // ──────────── 席位上限常量 ────────────
    uint256 public constant GRASSROOTS_LIMIT = 60; // 基层每院 60
    uint256 public constant MID_LIMIT = 12; // 中层每院 12
    uint256 public constant HIGH_LIMIT = 2; // 高层每院 2
    uint256 public constant COUNCIL_MEMBER_LIMIT = 12; // 理事 12
    uint256 public constant COUNCIL_SENIOR_LIMIT = 4; // 常务理事 4
    uint256 public constant COUNCIL_CHAIR_LIMIT = 2; // 理事长 2
    uint256 public constant APPOINTED_ELDER_LIMIT = 9; // 任命元老上限 9

    // ──────────── 任期长度常量 ────────────
    uint64 public constant GRASSROOTS_TERM = 365 days; // 基层 1 年
    uint64 public constant MID_TERM = 730 days; // 中层 2 年
    uint64 public constant HIGH_TERM = type(uint64).max; // 高层终生
    uint64 public constant COUNCIL_CHAIR_TERM = 4 * 365 days; // 理事长 4 年
    uint64 public constant ELDER_TERM = type(uint64).max; // 元老终生
    uint64 public constant CITIZEN_TERM = type(uint64).max; // 公民无任期

    // ──────────── 公民休眠常量（V1） ────────────
    uint64 public constant DORMANCY_PERIOD = 2 * 365 days; // 2 年未活动 → 休眠
    uint256 public constant RENOUNCE_COOLDOWN = 30 days; // 公民放弃后 30 天冷却

    // 连任上限（v3：不可连任）
    uint8 public constant MAX_CONSECUTIVE_TERMS = 0;

    // ──────────── 事件 ────────────
    event RingMinted(address indexed holder, uint256 indexed tokenId, RingTier tier, string covenantHash);
    event RingRevoked(uint256 indexed tokenId, address indexed holder);
    event TierUpdated(uint256 indexed tokenId, RingTier oldTier, RingTier newTier);
    event RingActivated(uint256 indexed tokenId);
    event RingDeactivated(uint256 indexed tokenId);
    event RingExpired(uint256 indexed tokenId, uint64 termEndAt);
    event RingRetired(uint256 indexed tokenId, address indexed holder, RingTier oldTier); // 退休转元老
    event RingResumed(uint256 indexed tokenId, address indexed holder); // 退休复出
    event SafeWalletUpdated(address indexed oldSafe, address indexed newSafe);
    event CitizenDormant(uint256 indexed tokenId, address indexed holder); // 公民休眠
    event CitizenReactivated(uint256 indexed tokenId, address indexed holder); // 公民重新激活
    event CitizenRenounced(uint256 indexed tokenId, address indexed holder); // 公民放弃
    event ElderAppointed(uint256 indexed tokenId, address indexed holder); // 任命元老
    event VoteActivityMarked(address indexed voter, uint256 lastActivityAt);

    // ──────────── 自定义错误 ────────────
    error InvalidRecipient();
    error AlreadyHasRing(address holder);
    error InvalidTier();
    error RingDoesNotExist(uint256 tokenId);
    error SoulboundNoTransfer();
    error SoulboundNoApproval();
    error InactiveRing(uint256 tokenId);
    error SeatLimitExceeded(RingTier tier, uint256 current, uint256 limit);
    error NotSafeOwner(address sender);
    error NotSafeWallet(address sender);
    error AlreadyEmeritus(uint256 tokenId);
    error NotEmeritus(uint256 tokenId);
    error RingExpiredCannotVote(uint256 tokenId, uint64 termEndAt);
    error SafeWalletNotSet();
    error SafeThresholdNotMet(uint256 required, uint256 actual);
    error NotCitizen(uint256 tokenId);
    error AlreadyDormant(uint256 tokenId);
    error NotDormant(uint256 tokenId);
    error DormancyNotDue(uint256 tokenId);
    error Unauthorized();
    error NotAppointedElder(address sender);
    error AppointedElderLimitReached(uint256 current, uint256 limit);
    error RenounceCooldownActive(uint256 remainingSeconds);
    error NotRingBearer();
    error AlreadyAppointedElder(uint256 tokenId);

    // ──────────── 构造函数 ────────────
    constructor() ERC721("Aether Ring", "AETHR") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    // ═══════════════════════════════════════════════════════════
    //                       铸造
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 铸造道环
     * @param recipient  接收地址
     * @param tier       权级（1-14）
     * @param covenantHash  契约内容 IPFS 哈希
     * @return tokenId 新铸的道环 ID
     */
    function mintRing(address recipient, RingTier tier, string calldata covenantHash)
        external
        onlyRole(MINTER_ROLE)
        returns (uint256)
    {
        if (recipient == address(0)) revert InvalidRecipient();
        if (walletToRingId[recipient] != 0) revert AlreadyHasRing(recipient);
        if (tier == RingTier.NONE) revert InvalidTier();
        // 任命元老不能通过 mintRing 直接铸，必须走 appointElder
        if (tier == RingTier.ELDER) revert InvalidTier();
        // 公民冷却期检查（防止放弃后立即重新获取）
        if (tier == RingTier.CITIZEN && !canReacquireCitizenship(recipient)) {
            revert RenounceCooldownActive(uint256(RENOUNCE_COOLDOWN - (block.timestamp - lastRenouncedAt[recipient])));
        }

        _checkSeatLimit(tier);

        uint256 tokenId = _nextTokenId++;
        _safeMint(recipient, tokenId);

        walletToRingId[recipient] = tokenId;

        uint64 mintedAt = uint64(block.timestamp);
        uint64 termEndAt = _termEndFor(tier, mintedAt);

        ringInfo[tokenId] = RingInfo({
            tier: tier,
            mintedAt: mintedAt,
            termEndAt: termEndAt,
            consecutiveTerms: 0,
            isActive: true,
            isEmeritus: false,
            isExpired: false,
            covenantHash: covenantHash,
            lastActivityAt: mintedAt,
            isDormant: false,
            isRetiredElder: false,
            isAppointedElder: false
        });

        _tierCount[uint8(tier)] += 1;

        emit RingMinted(recipient, tokenId, tier, covenantHash);
        return tokenId;
    }

    // ═══════════════════════════════════════════════════════════
    //                       升降级
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 升降级（管理员 / 选举合约）
     *         注意：中层→高层任命必须走多签；此处仅做技术性 tier 变更
     * @param tokenId   道环 ID
     * @param newTier   新权级
     * @param resetTerm 是否重置任期（选举当选后调 true）
     */
    function updateTier(uint256 tokenId, RingTier newTier, bool resetTerm) external onlyRole(ADMIN_ROLE) {
        if (!_exists(tokenId)) revert RingDoesNotExist(tokenId);
        if (newTier == RingTier.NONE) revert InvalidTier();
        if (newTier == RingTier.ELDER) revert InvalidTier(); // ELDER 只能通过 appointElder / retireToEmeritus

        RingInfo storage info = ringInfo[tokenId];
        RingTier oldTier = info.tier;
        if (oldTier == newTier) return;

        // 席位上限检查（新 tier 不能超限）
        _checkSeatLimit(newTier);

        // 调整计数（ELDER 不维护 _tierCount，跳过递减防下溢）
        if (oldTier != RingTier.ELDER) {
            _tierCount[uint8(oldTier)] -= 1;
        }
        if (newTier != RingTier.ELDER) {
            _tierCount[uint8(newTier)] += 1;
        }

        info.tier = newTier;

        // 升降级时重置任期（晋升到新层级 = 新任期）
        if (resetTerm) {
            uint64 newTermEnd = _termEndFor(newTier, uint64(block.timestamp));
            info.mintedAt = uint64(block.timestamp);
            info.termEndAt = newTermEnd;
            info.consecutiveTerms = 0;
            info.isExpired = false;
        }

        emit TierUpdated(tokenId, oldTier, newTier);
    }

    // ═══════════════════════════════════════════════════════════
    //                       任期到期被动失效
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 标记道环已到期（被动失效模式：投票/提案时被自动拒绝）
     *         任何人可调用，合约只做时间检查
     */
    function markExpiredIfDue(uint256 tokenId) external {
        if (!_exists(tokenId)) revert RingDoesNotExist(tokenId);
        RingInfo storage info = ringInfo[tokenId];
        if (info.isExpired) return;
        if (block.timestamp >= info.termEndAt) {
            info.isExpired = true;
            emit RingExpired(tokenId, info.termEndAt);
        }
    }

    // ═══════════════════════════════════════════════════════════
    //                       撤销（管理员 / 弹劾结果）
    // ═══════════════════════════════════════════════════════════

    function revokeRing(uint256 tokenId) external {
        if (!hasRole(ADMIN_ROLE, msg.sender) && !hasRole(GOVERNANCE_ROLE, msg.sender)) {
            revert Unauthorized();
        }
        if (!_exists(tokenId)) revert RingDoesNotExist(tokenId);
        address holder = ownerOf(tokenId);

        RingInfo storage info = ringInfo[tokenId];
        // ELDER tier 不维护 _tierCount（appointElder/retireToEmeritus 不增加），跳过递减防下溢
        if (info.tier != RingTier.ELDER) {
            _tierCount[uint8(info.tier)] -= 1;
        }
        if (info.isAppointedElder) {
            _appointedElderCount -= 1;
        }
        if (info.tier == RingTier.CITIZEN && info.isDormant) {
            _dormantCitizenCount -= 1;
        }
        info.isActive = false;
        walletToRingId[holder] = 0;

        _burn(tokenId);
        delete ringInfo[tokenId];
        emit RingRevoked(tokenId, holder);
    }

    function setRingActive(uint256 tokenId, bool active) external onlyRole(ADMIN_ROLE) {
        if (!_exists(tokenId)) revert RingDoesNotExist(tokenId);
        // M7: 不允许激活已到期的道环（绕过任期限制）
        if (active && (ringInfo[tokenId].isExpired || block.timestamp >= ringInfo[tokenId].termEndAt)) {
            revert RingExpiredCannotVote(tokenId, ringInfo[tokenId].termEndAt);
        }
        ringInfo[tokenId].isActive = active;
        if (active) emit RingActivated(tokenId);
        else emit RingDeactivated(tokenId);
    }

    // ═══════════════════════════════════════════════════════════
    //               退休转元老（V7 + V10）
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 高层/理事长自愿退休 → 转为退休元老（tier=13, isRetiredElder=true）
     *         调用方必须是 Safe 多签钱包
     *         退休资格：tier 3（议长）/6（执政）/9（首席）/12（理事长）
     * @param tokenId  要退休的道环 ID
     */
    function retireToEmeritus(uint256 tokenId) external {
        _requireSafeWallet();
        if (!_exists(tokenId)) revert RingDoesNotExist(tokenId);

        RingInfo storage info = ringInfo[tokenId];
        if (info.isEmeritus) revert AlreadyEmeritus(tokenId);

        RingTier oldTier = info.tier;
        if (!_isRetirable(oldTier)) revert InvalidTier();

        address holder = ownerOf(tokenId);

        // 原 tier 席位计数减 1
        _tierCount[uint8(oldTier)] -= 1;

        // 转为元老：tier=13，保留 covenantHash 和 mintedAt
        info.tier = RingTier.ELDER;
        info.isActive = false; // 退休元老无投票权
        info.isEmeritus = true;
        info.isRetiredElder = true; // 退休元老（无治理权）
        info.isAppointedElder = false;
        info.termEndAt = ELDER_TERM;
        // ELDER 无上限，不做席位检查

        emit RingRetired(tokenId, holder, oldTier);
    }

    /**
     * @notice 退休元老复出（须多签确认）
     *         注意：复出后 tier 保持 ELDER，但 isRetiredElder=false, isActive=true
     *         此函数仅用于错误退休的恢复，正常情况下退休不可逆
     * @param tokenId  要复出的道环 ID
     */
    function resumeFromEmeritus(uint256 tokenId) external {
        _requireSafeWallet();
        if (!_exists(tokenId)) revert RingDoesNotExist(tokenId);

        RingInfo storage info = ringInfo[tokenId];
        if (!info.isEmeritus) revert NotEmeritus(tokenId);

        address holder = ownerOf(tokenId);

        info.isActive = true;
        info.isEmeritus = false;
        info.isRetiredElder = false;
        // 退休复出后保持 ELDER 身份但不再标记退休

        emit RingResumed(tokenId, holder);
    }

    // ═══════════════════════════════════════════════════════════
    //               任命元老（V10）
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 任命元老（须多签确认）
     *         - 候选人已有道环：升级为 ELDER + isAppointedElder=true
     *         - 候选人无道环：铸新 ELDER 道环
     *         上限：9 人
     * @param candidate 候选人地址
     * @param covenantHash 契约哈希（新铸时用）
     */
    function appointElder(address candidate, string calldata covenantHash) external onlyRole(ADMIN_ROLE) {
        if (candidate == address(0)) revert InvalidRecipient();

        if (_appointedElderCount >= APPOINTED_ELDER_LIMIT) {
            revert AppointedElderLimitReached(_appointedElderCount, APPOINTED_ELDER_LIMIT);
        }

        uint256 ringId = walletToRingId[candidate];
        if (ringId == 0) {
            // 新铸道环
            ringId = _nextTokenId++;
            _safeMint(candidate, ringId);
            walletToRingId[candidate] = ringId;

            uint64 mintedAt = uint64(block.timestamp);
            ringInfo[ringId] = RingInfo({
                tier: RingTier.ELDER,
                mintedAt: mintedAt,
                termEndAt: ELDER_TERM,
                consecutiveTerms: 0,
                isActive: true,
                isEmeritus: false,
                isExpired: false,
                covenantHash: covenantHash,
                lastActivityAt: mintedAt,
                isDormant: false,
                isRetiredElder: false,
                isAppointedElder: true
            });
            // ELDER 不计入 _tierCount（无上限）
        } else {
            // 已有道环，升级为任命元老
            RingInfo storage info = ringInfo[ringId];
            if (info.isAppointedElder) revert AlreadyAppointedElder(ringId);

            RingTier oldTier = info.tier;
            if (oldTier != RingTier.ELDER) {
                _tierCount[uint8(oldTier)] -= 1;
                info.tier = RingTier.ELDER;
            }
            if (info.isRetiredElder) {
                info.isRetiredElder = false; // 退休元老重新任命，转为任命元老
            }
            if (info.isEmeritus) {
                info.isEmeritus = false;
            }
            info.isAppointedElder = true;
            info.isActive = true; // 任命元老有治理权
            info.termEndAt = ELDER_TERM;
        }

        _appointedElderCount += 1;
        emit ElderAppointed(ringId, candidate);
    }

    // ═══════════════════════════════════════════════════════════
    //               公民放弃身份（V11）
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 公民自愿放弃身份（_burn 道环）
     *         放弃后 30 天内不能重新获取公民身份
     */
    function renounceCitizenship() external {
        uint256 ringId = walletToRingId[msg.sender];
        if (ringId == 0) revert NotRingBearer();

        RingInfo storage info = ringInfo[ringId];
        if (info.tier != RingTier.CITIZEN) revert NotCitizen(ringId);

        address holder = msg.sender;

        _tierCount[uint8(RingTier.CITIZEN)] -= 1;
        if (info.isDormant) {
            _dormantCitizenCount -= 1;
        }
        walletToRingId[holder] = 0;
        lastRenouncedAt[holder] = block.timestamp;

        _burn(ringId);
        emit CitizenRenounced(ringId, holder);
    }

    /**
     * @notice 检查地址是否可重新获取公民身份（30 天冷却期）
     */
    function canReacquireCitizenship(address user) public view returns (bool) {
        uint256 lastRenounced = lastRenouncedAt[user];
        if (lastRenounced == 0) return true;
        return block.timestamp >= lastRenounced + RENOUNCE_COOLDOWN;
    }

    // ═══════════════════════════════════════════════════════════
    //               公民休眠机制（V1）
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 标记公民为休眠状态（2 年未活动）
     *         任何人可调用，合约只做时间检查
     * @param tokenId 公民道环 ID
     */
    function markDormantIfDue(uint256 tokenId) external {
        if (!_exists(tokenId)) revert RingDoesNotExist(tokenId);
        RingInfo storage info = ringInfo[tokenId];
        if (info.tier != RingTier.CITIZEN) revert NotCitizen(tokenId);
        if (info.isDormant) revert AlreadyDormant(tokenId);

        if (block.timestamp - info.lastActivityAt > DORMANCY_PERIOD) {
            info.isDormant = true;
            _dormantCitizenCount += 1;
            emit CitizenDormant(tokenId, ownerOf(tokenId));
        } else {
            revert DormancyNotDue(tokenId);
        }
    }

    /**
     * @notice 治理活动回调（由治理/选举合约调用，更新公民最后活动时间）
     *         如果公民已休眠，捐款激活时由 Donation 合约调用此函数重新激活
     * @param voter 投票人地址
     */
    function markVoteActivity(address voter) external {
        if (!hasRole(GOVERNANCE_ROLE, msg.sender) && !hasRole(ELECTION_ROLE, msg.sender)) {
            revert Unauthorized();
        }
        uint256 ringId = walletToRingId[voter];
        if (ringId == 0) return;
        RingInfo storage info = ringInfo[ringId];
        info.lastActivityAt = uint64(block.timestamp);
        // 注意：此函数不重新激活休眠公民（重新激活需通过捐款）
        emit VoteActivityMarked(voter, info.lastActivityAt);
    }

    /**
     * @notice 重新激活休眠公民（由 Donation 合约在捐款时调用）
     * @param voter 公民地址
     */
    function reactivateDormantCitizen(address voter) external onlyRole(MINTER_ROLE) {
        uint256 ringId = walletToRingId[voter];
        if (ringId == 0) return;
        RingInfo storage info = ringInfo[ringId];
        if (info.tier != RingTier.CITIZEN) return;
        if (!info.isDormant) return;

        info.isDormant = false;
        info.lastActivityAt = uint64(block.timestamp);
        if (_dormantCitizenCount > 0) {
            _dormantCitizenCount -= 1;
        }
        emit CitizenReactivated(ringId, voter);
    }

    // ═══════════════════════════════════════════════════════════
    //                       查询接口
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 检查地址是否持有有效道环（活跃 + 未到期 + 非退休）
     * @dev 这是治理合约调用的核心接口，必须严格
     */
    function isBearer(address holder) external view returns (bool) {
        uint256 ringId = walletToRingId[holder];
        if (ringId == 0) return false;
        RingInfo storage info = ringInfo[ringId];
        if (!info.isActive) return false;
        if (info.isEmeritus) return false;
        if (info.isExpired) return false;
        if (block.timestamp >= info.termEndAt) return false;
        // 休眠公民不算有效持有人（投票权暂停）
        if (info.tier == RingTier.CITIZEN && info.isDormant) return false;
        return true;
    }

    function getTier(address holder) external view returns (uint8) {
        uint256 ringId = walletToRingId[holder];
        if (ringId == 0) return 0;
        RingInfo storage info = ringInfo[ringId];
        if (!info.isActive || info.isEmeritus || info.isExpired) return 0;
        if (block.timestamp >= info.termEndAt) return 0;
        if (info.tier == RingTier.CITIZEN && info.isDormant) return 0;
        return uint8(info.tier);
    }

    function getRingId(address holder) external view returns (uint256) {
        return walletToRingId[holder];
    }

    /**
     * @notice 获取活跃公民总数（用于治理 quorum 分母，排除休眠公民）
     */
    function getActiveCitizens() external view returns (uint256) {
        uint256 total = _tierCount[uint8(RingTier.CITIZEN)];
        // L2: 下溢保护（防止 _dormantCitizenCount 异常超过总数时 revert 阻塞治理）
        return total > _dormantCitizenCount ? total - _dormantCitizenCount : 0;
    }

    /**
     * @notice 获取公民总数（含休眠，审计用）
     */
    function getTotalCitizens() external view returns (uint256) {
        return _tierCount[uint8(RingTier.CITIZEN)];
    }

    /**
     * @notice 获取任命元老计数
     */
    function getAppointedElderCount() external view returns (uint256) {
        return _appointedElderCount;
    }

    function getRingInfo(uint256 tokenId) external view returns (RingInfo memory) {
        if (!_exists(tokenId)) revert RingDoesNotExist(tokenId);
        return ringInfo[tokenId];
    }

    function getTierCount(RingTier tier) external view returns (uint256) {
        return _tierCount[uint8(tier)];
    }

    function nextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

    function isEmeritus(address holder) external view returns (bool) {
        uint256 ringId = walletToRingId[holder];
        if (ringId == 0) return false;
        return ringInfo[ringId].isEmeritus;
    }

    function isExpired(uint256 tokenId) external view returns (bool) {
        if (!_exists(tokenId)) return false;
        RingInfo storage info = ringInfo[tokenId];
        return info.isExpired || block.timestamp >= info.termEndAt;
    }

    /**
     * @notice 检查地址是否为任命元老（有治理权：否决/弹劾）
     *         退休元老返回 false
     */
    function isElderActive(address holder) external view returns (bool) {
        uint256 ringId = walletToRingId[holder];
        if (ringId == 0) return false;
        RingInfo storage info = ringInfo[ringId];
        return info.isAppointedElder && !info.isEmeritus && info.isActive;
    }

    /**
     * @notice 检查地址是否为退休元老（仅名誉，无治理权）
     */
    function isRetiredElder(address holder) external view returns (bool) {
        uint256 ringId = walletToRingId[holder];
        if (ringId == 0) return false;
        return ringInfo[ringId].isRetiredElder;
    }

    /**
     * @notice 检查公民是否休眠
     */
    function isDormant(address holder) external view returns (bool) {
        uint256 ringId = walletToRingId[holder];
        if (ringId == 0) return false;
        RingInfo storage info = ringInfo[ringId];
        return info.tier == RingTier.CITIZEN && info.isDormant;
    }

    // ═══════════════════════════════════════════════════════════
    //                       Safe 多签管理
    // ═══════════════════════════════════════════════════════════

    function setSafeWallet(address _safe) external onlyRole(ADMIN_ROLE) {
        if (_safe == address(0)) revert InvalidRecipient();
        address old = address(safeWallet);
        safeWallet = ISafe(_safe);
        emit SafeWalletUpdated(old, _safe);
    }

    // ═══════════════════════════════════════════════════════════
    //                       SBT 核心：override _update
    // ═══════════════════════════════════════════════════════════

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            revert SoulboundNoTransfer();
        }
        return super._update(to, tokenId, auth);
    }

    function approve(address, uint256) public pure override {
        revert SoulboundNoApproval();
    }

    function setApprovalForAll(address, bool) public pure override {
        revert SoulboundNoApproval();
    }

    // ═══════════════════════════════════════════════════════════
    //                       内部辅助
    // ═══════════════════════════════════════════════════════════

    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    function _checkSeatLimit(RingTier tier) internal view {
        uint256 current = _tierCount[uint8(tier)];
        uint256 limit = _seatLimitOf(tier);
        if (current >= limit) revert SeatLimitExceeded(tier, current, limit);
    }

    function _termEndFor(RingTier tier, uint64 startAt) internal pure returns (uint64) {
        TierLevel level = _levelOf(tier);
        if (level == TierLevel.GRASSROOTS) return startAt + GRASSROOTS_TERM;
        if (level == TierLevel.MID) return startAt + MID_TERM;
        if (level == TierLevel.HIGH) return HIGH_TERM;
        if (level == TierLevel.COUNCIL) {
            if (tier == RingTier.COUNCIL_CHAIR) return startAt + COUNCIL_CHAIR_TERM;
            return startAt + GRASSROOTS_TERM; // 理事/常务理事 1 年任期
        }
        if (level == TierLevel.ELDER_LEVEL) return ELDER_TERM;
        if (level == TierLevel.CITIZEN_LEVEL) return CITIZEN_TERM;
        return HIGH_TERM;
    }

    function _levelOf(RingTier tier) internal pure returns (TierLevel) {
        // 三院基层
        if (tier == RingTier.PARLIAMENT_MEMBER || tier == RingTier.FEDERATION_MEMBER || tier == RingTier.TRIBUNAL_JUDGE)
        {
            return TierLevel.GRASSROOTS;
        }
        // 三院中层
        if (
            tier == RingTier.PARLIAMENT_SENIOR || tier == RingTier.FEDERATION_SENIOR
                || tier == RingTier.TRIBUNAL_SENIOR
        ) {
            return TierLevel.MID;
        }
        // 三院高层
        if (
            tier == RingTier.PARLIAMENT_SPEAKER || tier == RingTier.FEDERATION_MINISTER
                || tier == RingTier.TRIBUNAL_CHIEF
        ) {
            return TierLevel.HIGH;
        }
        // 理事会
        if (tier == RingTier.COUNCIL_MEMBER || tier == RingTier.COUNCIL_SENIOR || tier == RingTier.COUNCIL_CHAIR) {
            return TierLevel.COUNCIL;
        }
        if (tier == RingTier.ELDER) return TierLevel.ELDER_LEVEL;
        if (tier == RingTier.CITIZEN) return TierLevel.CITIZEN_LEVEL;
        return TierLevel.NONE;
    }

    function _seatLimitOf(RingTier tier) internal pure returns (uint256) {
        TierLevel level = _levelOf(tier);
        if (level == TierLevel.GRASSROOTS) return GRASSROOTS_LIMIT;
        if (level == TierLevel.MID) return MID_LIMIT;
        if (level == TierLevel.HIGH) return HIGH_LIMIT;
        if (tier == RingTier.COUNCIL_MEMBER) return COUNCIL_MEMBER_LIMIT;
        if (tier == RingTier.COUNCIL_SENIOR) return COUNCIL_SENIOR_LIMIT;
        if (tier == RingTier.COUNCIL_CHAIR) return COUNCIL_CHAIR_LIMIT;
        // ELDER 和 CITIZEN 无上限
        return type(uint256).max;
    }

    function _isRetirable(RingTier tier) internal pure returns (bool) {
        return tier == RingTier.PARLIAMENT_SPEAKER // 3
            || tier == RingTier.FEDERATION_MINISTER // 6
            || tier == RingTier.TRIBUNAL_CHIEF // 9
            || tier == RingTier.COUNCIL_CHAIR; // 12
    }

    function _requireSafeWallet() internal view {
        if (address(safeWallet) == address(0)) revert SafeWalletNotSet();
        if (msg.sender != address(safeWallet)) revert NotSafeWallet(msg.sender);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return interfaceId == type(IAetherRing).interfaceId || super.supportsInterface(interfaceId);
    }
}
