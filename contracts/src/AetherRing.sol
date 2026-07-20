// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IAetherRing} from "./interfaces/IAetherRing.sol";
import {ISafe} from "./interfaces/ISafe.sol";

/**
 * @title AetherRing — 道环灵魂绑定代币（SBT）v2
 * @author Aether Foundation
 *
 * v2 升级要点：
 *  ┌────────────────────────────────────────────────────────────┐
 *  │ 1. EMERITUS 荣誉退休状态：高层可自愿退休，保留名誉身份    │
 *  │    无投票权/提案权，可被多签 4/5 复出                       │
 *  │ 2. 席位上限：基层 20 / 中层 4 / 高层 2（每院各自）          │
 *  │ 3. 任期 & 连任：基层 1 年最多连任 1 次，中层 2 年最多连任 1 │
 *  │    次，高层终生。到期被动失效（EXPIRED）                    │
 *  │ 4. Safe v1.4 多签接入：退休/复出/任命由多签确认            │
 *  │ 5. tierCount[tier] 计数器：铸/撤/升降级实时维护             │
 *  └────────────────────────────────────────────────────────────┘
 *
 * 权级体系（10 级 + EMERITUS）：
 *  ┌─────────────────────────────────────────────┐
 *  │ 1  PARLIAMENT_MEMBER    议员   (基层，权重 2) │
 *  │ 2  PARLIAMENT_SENIOR    参议员 (中层，权重 5) │
 *  │ 3  PARLIAMENT_SPEAKER   议长   (高层，权重 20)│
 *  │ 4  FEDERATION_MEMBER    委员   (基层，权重 2) │
 *  │ 5  FEDERATION_SENIOR    委员长 (中层，权重 5) │
 *  │ 6  FEDERATION_MINISTER  部长   (高层，权重 20)│
 *  │ 7  SENATE_ADVISOR       顾问   (基层，权重 2) │
 *  │ 8  SENATE_FELLOW        研究员 (中层，权重 5) │
 *  │ 9  SENATE_ELDER         元老   (高层，权重 20)│
 *  │ 10 GENERAL_MEMBER       普通会员 (权重 1)     │
 *  └─────────────────────────────────────────────┘
 *  EMERITUS 不是 tier 枚举值，是独立的状态标记（isActive=false, isEmeritus=true）
 *
 * 任期（按层级）：
 *  - 基层（tier 1/4/7）:   termEndAt = mintedAt + 365 days，可连任 1 次
 *  - 中层（tier 2/5/8）:   termEndAt = mintedAt + 730 days，可连任 1 次
 *  - 高层（tier 3/6/9）:   termEndAt = type(uint64).max（终生）
 *  - 会员（tier 10）:       termEndAt = type(uint64).max（无任期）
 */
contract AetherRing is ERC721, AccessControl, IAetherRing {
    // ──────────── 角色 ────────────
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // ──────────── 10 级权级枚举 ────────────
    enum RingTier {
        NONE, // 0
        PARLIAMENT_MEMBER, // 1  议员（基层）
        PARLIAMENT_SENIOR, // 2  参议员（中层）
        PARLIAMENT_SPEAKER, // 3  议长（高层）
        FEDERATION_MEMBER, // 4  委员（基层）
        FEDERATION_SENIOR, // 5  委员长（中层）
        FEDERATION_MINISTER, // 6  部长（高层）
        SENATE_ADVISOR, // 7  顾问（基层）
        SENATE_FELLOW, // 8  研究员（中层）
        SENATE_ELDER, // 9  元老（高层）
        GENERAL_MEMBER // 10 普通会员
    }

    // ──────────── 层级 ────────────
    enum TierLevel {
        NONE, // 0
        GRASSROOTS, // 1 基层
        MID, // 2 中层
        HIGH, // 3 高层
        GENERAL // 4 会员
    }

    // ──────────── 数据结构 ────────────
    struct RingInfo {
        RingTier tier;
        uint64 mintedAt;
        uint64 termEndAt; // 任期结束时间；高层/会员为 type(uint64).max
        uint8 consecutiveTerms; // 已连任次数（0 = 首任，1 = 连任 1 次）
        bool isActive; // 投票/提案权限
        bool isEmeritus; // 荣誉退休标记（独立于 isActive）
        bool isExpired; // 任期到期标记
        string covenantHash;
    }

    // ──────────── 存储 ────────────
    mapping(uint256 => RingInfo) public ringInfo;
    mapping(address => uint256) public walletToRingId;
    uint256 private _nextTokenId;

    // 按权级计数（用于席位上限检查）
    mapping(uint8 => uint256) private _tierCount;

    // 多签钱包
    ISafe public safeWallet;

    // 席位上限（每院每层级）
    uint256 public constant GRASSROOTS_LIMIT = 20; // 基层每院 20
    uint256 public constant MID_LIMIT = 4; // 中层每院 4
    uint256 public constant HIGH_LIMIT = 2; // 高层每院 2

    // 任期长度
    uint64 public constant GRASSROOTS_TERM = 365 days;
    uint64 public constant MID_TERM = 730 days;
    uint64 public constant HIGH_TERM = type(uint64).max; // 终生
    uint64 public constant GENERAL_TERM = type(uint64).max; // 会员无任期

    // 连任上限
    uint8 public constant MAX_CONSECUTIVE_TERMS = 1; // 最多连任 1 次

    // ──────────── 事件 ────────────
    event RingMinted(address indexed holder, uint256 indexed tokenId, RingTier tier, string covenantHash);
    event RingRevoked(uint256 indexed tokenId, address indexed holder);
    event TierUpdated(uint256 indexed tokenId, RingTier oldTier, RingTier newTier);
    event RingActivated(uint256 indexed tokenId);
    event RingDeactivated(uint256 indexed tokenId);
    event RingExpired(uint256 indexed tokenId, uint64 termEndAt);
    event RingRetired(uint256 indexed tokenId, address indexed holder); // 转为 EMERITUS
    event RingResumed(uint256 indexed tokenId, address indexed holder); // 退休复出
    event SafeWalletUpdated(address indexed oldSafe, address indexed newSafe);
    event TermRenewed(uint256 indexed tokenId, uint64 newTermEndAt, uint8 newConsecutiveTerms);

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
    error TermLimitReached(uint8 consecutiveTerms);
    error SafeWalletNotSet();
    error SafeThresholdNotMet(uint256 required, uint256 actual);

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
     * @param tier       权级（1-10）
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

        // 席位上限检查（tier 10 无上限）
        if (tier != RingTier.GENERAL_MEMBER) {
            uint256 current = _tierCount[uint8(tier)];
            uint256 limit = _seatLimitOf(tier);
            if (current >= limit) revert SeatLimitExceeded(tier, current, limit);
        }

        uint256 tokenId = _nextTokenId++;
        _safeMint(recipient, tokenId);

        walletToRingId[recipient] = tokenId;

        uint64 mintedAt = uint64(block.timestamp);
        uint64 termEndAt = _termEndFor(tier, mintedAt, 0);

        ringInfo[tokenId] = RingInfo({
            tier: tier,
            mintedAt: mintedAt,
            termEndAt: termEndAt,
            consecutiveTerms: 0,
            isActive: true,
            isEmeritus: false,
            isExpired: false,
            covenantHash: covenantHash
        });

        _tierCount[uint8(tier)] += 1;

        emit RingMinted(recipient, tokenId, tier, covenantHash);
        return tokenId;
    }

    // ═══════════════════════════════════════════════════════════
    //                       升降级
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 升降级（管理员）
     *         注意：中层→高层任命必须走多签；此处仅做技术性 tier 变更
     * @param tokenId  道环 ID
     * @param newTier  新权级
     * @param resetTerm 是否重置任期（连任选举成功后调 true）
     */
    function updateTier(uint256 tokenId, RingTier newTier, bool resetTerm) external onlyRole(ADMIN_ROLE) {
        if (!_exists(tokenId)) revert RingDoesNotExist(tokenId);
        if (newTier == RingTier.NONE) revert InvalidTier();

        RingInfo storage info = ringInfo[tokenId];
        RingTier oldTier = info.tier;
        if (oldTier == newTier) return;

        // 席位上限检查（新 tier 不能超限）
        if (newTier != RingTier.GENERAL_MEMBER) {
            uint256 current = _tierCount[uint8(newTier)];
            uint256 limit = _seatLimitOf(newTier);
            // 升级时旧 tier 会被减 1，所以新 tier 的可用席位 +1
            if (current >= limit) revert SeatLimitExceeded(newTier, current, limit);
        }

        // 调整计数
        _tierCount[uint8(oldTier)] -= 1;
        _tierCount[uint8(newTier)] += 1;

        info.tier = newTier;

        // 升降级时重置任期（晋升到新层级 = 新任期）
        if (resetTerm) {
            uint64 newTermEnd = _termEndFor(newTier, uint64(block.timestamp), 0);
            info.mintedAt = uint64(block.timestamp);
            info.termEndAt = newTermEnd;
            info.consecutiveTerms = 0;
            info.isExpired = false;
        }

        emit TierUpdated(tokenId, oldTier, newTier);
    }

    // ═══════════════════════════════════════════════════════════
    //                       任期续任
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 续任（连任选举成功后调用）
     * @dev 只能 ADMIN_ROLE（选举合约通过多签/选举流程获得授权后调）
     * @param tokenId  道环 ID
     * @param newTermEnd  新任期结束时间
     */
    function renewTerm(uint256 tokenId, uint64 newTermEnd) external onlyRole(ADMIN_ROLE) {
        if (!_exists(tokenId)) revert RingDoesNotExist(tokenId);
        RingInfo storage info = ringInfo[tokenId];
        if (info.consecutiveTerms >= MAX_CONSECUTIVE_TERMS) {
            revert TermLimitReached(info.consecutiveTerms);
        }
        info.termEndAt = newTermEnd;
        info.consecutiveTerms += 1;
        info.isExpired = false;
        emit TermRenewed(tokenId, newTermEnd, info.consecutiveTerms);
    }

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

    function revokeRing(uint256 tokenId) external onlyRole(ADMIN_ROLE) {
        if (!_exists(tokenId)) revert RingDoesNotExist(tokenId);
        address holder = ownerOf(tokenId);

        RingInfo storage info = ringInfo[tokenId];
        _tierCount[uint8(info.tier)] -= 1;
        info.isActive = false;
        walletToRingId[holder] = 0;

        _burn(tokenId);
        emit RingRevoked(tokenId, holder);
    }

    function setRingActive(uint256 tokenId, bool active) external onlyRole(ADMIN_ROLE) {
        if (!_exists(tokenId)) revert RingDoesNotExist(tokenId);
        ringInfo[tokenId].isActive = active;
        if (active) emit RingActivated(tokenId);
        else emit RingDeactivated(tokenId);
    }

    // ═══════════════════════════════════════════════════════════
    //                       荣誉退休 EMERITUS
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 高层自愿退休（须多签 3/5 确认）
     *         调用方必须是 Safe 多签钱包（msg.sender == address(safeWallet)）
     *         前端流程：高层签名 → 多签聚合 → Safe.execTransaction → 调本函数
     * @param tokenId  要退休的道环 ID
     */
    function retireToEmeritus(uint256 tokenId) external {
        _requireSafeWallet();
        if (!_exists(tokenId)) revert RingDoesNotExist(tokenId);

        RingInfo storage info = ringInfo[tokenId];
        if (info.isEmeritus) revert AlreadyEmeritus(tokenId);

        // 只有高层（tier 3/6/9）能退休
        RingTier t = info.tier;
        if (t != RingTier.PARLIAMENT_SPEAKER && t != RingTier.FEDERATION_MINISTER && t != RingTier.SENATE_ELDER) {
            revert InvalidTier();
        }

        address holder = ownerOf(tokenId);

        // 退休：保留 tier（名誉身份），但 isActive=false（无投票/提案权）
        info.isActive = false;
        info.isEmeritus = true;
        // 不调整 _tierCount：名誉席位不占活跃席位，但保留 tier 编码
        // 注意：这里的策略是 tier 编码不动，外部通过 isEmeritus 判断
        // 这样 getTier 仍然返回原 tier（便于历史展示），
        // 但 isBearer 返回 false（治理合约不接受其投票）

        emit RingRetired(tokenId, holder);
    }

    /**
     * @notice 退休复出（须多签 4/5 签名）
     *         调用方必须是 Safe 多签钱包
     *         注意：Safe 阈值由 Safe 自身管理，本合约只验证 msg.sender == safeWallet
     *         实际签名数检查在 Safe.execTransaction 内部完成
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

        emit RingResumed(tokenId, holder);
    }

    // ═══════════════════════════════════════════════════════════
    //                       查询接口
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 检查地址是否持有有效道环（活跃 + 未到期 + 非 EMERITUS）
     * @dev 这是治理合约调用的核心接口，必须严格
     */
    function isBearer(address holder) external view returns (bool) {
        uint256 ringId = walletToRingId[holder];
        if (ringId == 0) return false;
        RingInfo storage info = ringInfo[ringId];
        if (!info.isActive) return false;
        if (info.isEmeritus) return false;
        if (info.isExpired) return false;
        // 时间检查（即使 isExpired 未被标记，时间过了也拒绝）
        if (block.timestamp >= info.termEndAt) return false;
        return true;
    }

    function getTier(address holder) external view returns (uint8) {
        uint256 ringId = walletToRingId[holder];
        if (ringId == 0) return 0;
        RingInfo storage info = ringInfo[ringId];
        if (!info.isActive || info.isEmeritus || info.isExpired) return 0;
        if (block.timestamp >= info.termEndAt) return 0;
        return uint8(info.tier);
    }

    function getRingId(address holder) external view returns (uint256) {
        return walletToRingId[holder];
    }

    function getTotalMembers() external view returns (uint256) {
        return _tierCount[uint8(RingTier.GENERAL_MEMBER)];
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
        return tokenId < _nextTokenId;
    }

    function _termEndFor(RingTier tier, uint64 startAt, uint8 /*consecutiveTerms*/)
        internal
        pure
        returns (uint64)
    {
        TierLevel level = _levelOf(tier);
        if (level == TierLevel.GRASSROOTS) return startAt + GRASSROOTS_TERM;
        if (level == TierLevel.MID) return startAt + MID_TERM;
        // HIGH 和 GENERAL 都是终生
        return HIGH_TERM;
    }

    function _levelOf(RingTier tier) internal pure returns (TierLevel) {
        if (tier == RingTier.PARLIAMENT_MEMBER || tier == RingTier.FEDERATION_MEMBER || tier == RingTier.SENATE_ADVISOR)
        {
            return TierLevel.GRASSROOTS;
        }
        if (
            tier == RingTier.PARLIAMENT_SENIOR || tier == RingTier.FEDERATION_SENIOR
                || tier == RingTier.SENATE_FELLOW
        ) {
            return TierLevel.MID;
        }
        if (
            tier == RingTier.PARLIAMENT_SPEAKER || tier == RingTier.FEDERATION_MINISTER
                || tier == RingTier.SENATE_ELDER
        ) {
            return TierLevel.HIGH;
        }
        if (tier == RingTier.GENERAL_MEMBER) return TierLevel.GENERAL;
        return TierLevel.NONE;
    }

    function _seatLimitOf(RingTier tier) internal pure returns (uint256) {
        TierLevel level = _levelOf(tier);
        if (level == TierLevel.GRASSROOTS) return GRASSROOTS_LIMIT;
        if (level == TierLevel.MID) return MID_LIMIT;
        if (level == TierLevel.HIGH) return HIGH_LIMIT;
        return type(uint256).max; // GENERAL_MEMBER 无上限
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
