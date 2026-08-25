// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAetherRing} from "./interfaces/IAetherRing.sol";
import {IAetherDonation} from "./interfaces/IAetherDonation.sol";
import {AetherRing} from "./AetherRing.sol";

/**
 * @title AetherDonation — 纯链上 USDC 捐款凭证 NFT + 公民身份发放
 * @author Aether Foundation
 *
 * ═══════════════════════════════════════════════════════════════
 *  设计依据
 * ═══════════════════════════════════════════════════════════════
 *
 *  - Q8  Donation NFT = ERC-721 SBT，不可转让
 *  - V7  首次捐款铸公民道环，二次捐款不重复铸（去重逻辑）
 *  - V8  防女巫：3 公民担保快速通道（链上转账天然防女巫，无需账户去重）
 *  - V11 公民放弃冷却期 30 天（调 ring.canReacquireCitizenship 检查）
 *  - 补充 捐款门槛 ≥ $10（MIN_DONATION_USD，按稳定币 decimals 动态计算）
 *
 *  链无关精度（v3.5 修复，审计 P0-1）：
 *    MIN_DONATION_USD 不再硬编码 6 decimals，而是在构造时与 setUsdcToken
 *    切换代币时读取 IERC20.decimals() 动态计算（10 * 10^decimals）。
 *    这样同一份合约可部署在 6-decimals 与
 *    18-decimals（BNB Chain 的 Binance-Peg USDC/USDT）网络上，门槛语义一致。
 *
 *  纯链上流程（替代原 PayPal webhook 方案）：
 *    用户连钱包 → approve USDC → 调 donateAndMint()
 *    合约一笔交易内：转 USDC 到 treasury + 铸捐款凭证 NFT + 铸公民道环
 *
 * ═══════════════════════════════════════════════════════════════
 *  角色权限
 * ═══════════════════════════════════════════════════════════════
 *
 *  - DEFAULT_ADMIN_ROLE  部署者（初始化后转交 Safe 多签）
 *  - ADMIN_ROLE          Safe 多签（setTreasury / setRingContract / setUsdcToken）
 *
 *  donateAndMint 为 public，任何人都能调（无需 MINTER_ROLE）。
 *
 *  部署后需在 AetherRing 上授权：
 *    ring.grantRole(ring.MINTER_ROLE(), address(donation))
 *  以便 donation 合约在首次捐款时铸公民道环 / 重新激活休眠公民
 *
 * ═══════════════════════════════════════════════════════════════
 *  donateAndMint 流程
 * ═══════════════════════════════════════════════════════════════
 *
 *  1. 校验 amount >= MIN_DONATION_USD（$10）
 *  2. 校验 canReacquireCitizenship 冷却期（30 天）
 *  3. transferFrom USDC：从捐款人转到 treasury（检查返回值）
 *  4. 铸捐款凭证 NFT（每笔捐款都铸）
 *  5. 首次捐款（ringId==0）：铸公民道环
 *  6. 休眠公民（ringId!=0 但 dormant）：重新激活
 *  7. 已活跃公民：仅铸捐款凭证
 */

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

contract AetherDonation is ERC721, AccessControl, IAetherDonation {
    // ──────────── 角色 ────────────
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // ──────────── 引用 ────────────
    IAetherRing public ringContract;
    address public treasury; // Safe 多签国库地址（USDC 接收方）
    address public usdc; // USDC 合约地址（链上转账用）

    // ──────────── 常量 ────────────
    /** 最低捐款额（以美元计的整数部分）：$10 */
    uint256 public constant MIN_DONATION_WHOLE_USD = 10;
    /** 允许的代币最大精度（防止异常 decimals 导致乘法溢出/门槛失真） */
    uint8 public constant MAX_TOKEN_DECIMALS = 18;
    uint256 public constant SPONSORS_REQUIRED = 3; // V8: 3 公民担保激活快速通道
    uint256 public constant FAST_TRACK_DELAY = 24 hours; // 快速通道等待期
    uint256 public constant NORMAL_TRACK_DELAY = 7 days; // 普通通道等待期

    // ──────────── 存储 ────────────
    /**
     * 最低捐款额（代币最小单位）。
     * 构造时按所配稳定币 decimals 动态计算：10 * 10^decimals。
     * 例：6-decimals 稳定币 → 10_000_000；
     *     BNB Chain Binance-Peg USDC/USDT（18 decimals）→ 10_000_000_000_000_000_000。
     * setUsdcToken 切换代币时会同步重算。
     */
    uint256 public MIN_DONATION_USD;

    mapping(uint256 => Donation) private _donations;
    mapping(address => uint256[]) private _donorTokenIds; // donor → tokenId 列表
    mapping(uint256 => mapping(address => bool)) public hasSponsored; // tokenId → sponsor → bool

    uint256 private _nextTokenId = 1; // 从 1 开始（0 表示"无"）

    // ──────────── 事件 ────────────
    event DonationMinted(uint256 indexed tokenId, address indexed donor, uint256 amount);
    event SponsorAdded(uint256 indexed tokenId, address indexed sponsor, uint8 sponsorCount);
    event FastTrackActivated(uint256 indexed tokenId);
    event CitizenRingMinted(address indexed donor, uint256 ringTokenId);
    event DormantCitizenReactivated(address indexed donor);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event RingContractUpdated(address indexed oldRing, address indexed newRing);
    event UsdcTokenUpdated(address indexed oldUsdc, address indexed newUsdc);
    event MinDonationUpdated(uint256 oldMin, uint256 newMin);

    // ──────────── 错误 ────────────
    error DonationTooSmall(uint256 amount, uint256 minRequired);
    error RenounceCooldownActive(address donor);
    error DonationNotFound(uint256 tokenId);
    error AlreadyFastTrack(uint256 tokenId);
    error AlreadySponsored(uint256 tokenId, address sponsor);
    error NotCitizen(address sponsor);
    error CannotSelfSponsor(uint256 tokenId, address donor);
    error NonTransferable();
    error NonTransferableApproval();
    error InvalidTreasury();
    error InvalidRingContract();
    error InvalidUsdcToken();
    error InvalidTokenDecimals(uint8 decimals);
    error UsdcTransferFailed();

    // ═══════════════════════════════════════════════════════════
    //                       构造函数
    // ═══════════════════════════════════════════════════════════

    /**
     * @param ring      AetherRing 合约地址
     * @param _treasury Safe 多签国库地址（USDC 接收方）
     * @param _usdc     USDC 合约地址（链上转账用；需实现 decimals()）
     * @param admin     初始管理员（部署者，后续转交 Safe）
     */
    constructor(address ring, address _treasury, address _usdc, address admin)
        ERC721("Aether Donation", "AETHD")
    {
        if (ring == address(0)) revert InvalidRingContract();
        if (_treasury == address(0)) revert InvalidTreasury();
        if (_usdc == address(0)) revert InvalidUsdcToken();

        ringContract = IAetherRing(ring);
        treasury = _treasury;
        usdc = _usdc;

        // 按代币精度计算最低捐款额（链无关：6 或 18 decimals 语义一致）
        MIN_DONATION_USD = _computeMinDonation(_usdc);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    /**
     * @dev 按稳定币 decimals 计算 $10 对应的最小单位数量。
     *      decimals > 18 视为异常代币直接拒绝（防溢出与门槛失真）；
     *      decimals() 调用失败同样 revert（构造/切换即失败，fail-safe）。
     */
    function _computeMinDonation(address token) internal view returns (uint256) {
        uint8 d = IERC20(token).decimals();
        if (d > MAX_TOKEN_DECIMALS) revert InvalidTokenDecimals(d);
        return MIN_DONATION_WHOLE_USD * 10 ** d;
    }

    // ═══════════════════════════════════════════════════════════
    //               donateAndMint 核心（纯链上）
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 纯链上捐款：转账 USDC + 铸捐款凭证 NFT + 铸公民道环
     *         任何人可调（public），需先 approve USDC 给本合约
     * @param amount 捐款金额（代币最小单位，≥ $10，精度跟随所配稳定币）
     * @return tokenId 新铸的捐款凭证 ID
     *
     * 流程：
     *   1. 校验金额 + 冷却期
     *   2. transferFrom USDC：捐款人 → treasury（检查返回值）
     *   3. 铸捐款凭证 NFT（CEI：先写状态再铸）
     *   4. 首次捐款 → 铸公民道环；休眠公民 → 重新激活
     */
    function donateAndMint(uint256 amount) public returns (uint256) {
        // ── 1. 校验 ──
        if (amount < MIN_DONATION_USD) revert DonationTooSmall(amount, MIN_DONATION_USD);
        if (!ringContract.canReacquireCitizenship(msg.sender)) revert RenounceCooldownActive(msg.sender);

        // ── 2. 转账 USDC（捐款人 → 国库） ──
        // 某些 USDC 实现返回 false 而非 revert，需检查返回值
        bool ok = IERC20(usdc).transferFrom(msg.sender, treasury, amount);
        if (!ok) revert UsdcTransferFailed();

        // ── 3. 铸捐款凭证 NFT（CEI：先写状态再铸） ──
        uint256 tokenId = _nextTokenId++;
        // M1: 状态写入前置，防止 _safeMint 回调重入造成状态不一致
        _donations[tokenId] = Donation({
            donor: msg.sender,
            amount: amount,
            timestamp: block.timestamp,
            sponsorCount: 0,
            fastTrackActivated: false
        });
        _donorTokenIds[msg.sender].push(tokenId);
        _safeMint(msg.sender, tokenId);

        // ── 4. 公民身份发放 / 重新激活 ──
        uint256 ringId = ringContract.getRingId(msg.sender);
        if (ringId == 0) {
            // 首次捐款：铸公民道环
            ringContract.mintRing(msg.sender, IAetherRing.RingTier.CITIZEN, "");
            emit CitizenRingMinted(msg.sender, ringContract.getRingId(msg.sender));
        } else {
            // Bug 30: 仅在确实休眠时才发重新激活事件，避免乐观误发
            bool wasDormant = ringContract.isDormant(msg.sender);
            ringContract.reactivateDormantCitizen(msg.sender);
            if (wasDormant) {
                emit DormantCitizenReactivated(msg.sender);
            }
        }

        emit DonationMinted(tokenId, msg.sender, amount);
        return tokenId;
    }

    // ═══════════════════════════════════════════════════════════
    //               3 公民担保快速通道（V8）
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 担保捐款（3 个公民担保后激活快速通道）
     *         担保人必须是现有活跃公民（tier==14）
     * @param tokenId 被担保的捐款凭证 ID
     */
    function sponsorDonation(uint256 tokenId) external {
        Donation storage d = _donations[tokenId];
        if (d.donor == address(0)) revert DonationNotFound(tokenId);
        if (d.fastTrackActivated) revert AlreadyFastTrack(tokenId);
        if (hasSponsored[tokenId][msg.sender]) revert AlreadySponsored(tokenId, msg.sender);
        // 捐款人不能为自己的捐款担保
        if (msg.sender == d.donor) revert CannotSelfSponsor(tokenId, d.donor);

        // 担保人必须是现有活跃公民
        if (ringContract.getTier(msg.sender) != uint8(IAetherRing.RingTier.CITIZEN)) {
            revert NotCitizen(msg.sender);
        }

        hasSponsored[tokenId][msg.sender] = true;
        d.sponsorCount += 1;

        emit SponsorAdded(tokenId, msg.sender, d.sponsorCount);

        if (d.sponsorCount >= SPONSORS_REQUIRED) {
            d.fastTrackActivated = true;
            emit FastTrackActivated(tokenId);
        }
    }

    // ═══════════════════════════════════════════════════════════
    //               查询函数
    // ═══════════════════════════════════════════════════════════

    function getDonation(uint256 tokenId) external view returns (Donation memory) {
        if (_donations[tokenId].donor == address(0)) revert DonationNotFound(tokenId);
        return _donations[tokenId];
    }

    function getDonationsByDonor(address donor) external view returns (uint256[] memory) {
        return _donorTokenIds[donor];
    }

    function getTotalDonations() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    function isFastTrackActivated(uint256 tokenId) external view returns (bool) {
        return _donations[tokenId].fastTrackActivated;
    }

    function getSponsorCount(uint256 tokenId) external view returns (uint8) {
        return _donations[tokenId].sponsorCount;
    }

    function hasSponsoredDonation(uint256 tokenId, address sponsor) external view returns (bool) {
        return hasSponsored[tokenId][sponsor];
    }

    function nextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

    /**
     * @notice 代理查询：donor 是否可重新获取公民身份（30 天冷却期）
     */
    function canReacquireCitizenship(address user) external view returns (bool) {
        return ringContract.canReacquireCitizenship(user);
    }

    // ═══════════════════════════════════════════════════════════
    //               管理函数（ADMIN_ROLE）
    // ═══════════════════════════════════════════════════════════

    function setTreasury(address _treasury) external onlyRole(ADMIN_ROLE) {
        if (_treasury == address(0)) revert InvalidTreasury();
        address old = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(old, _treasury);
    }

    function setRingContract(address _ring) external onlyRole(ADMIN_ROLE) {
        if (_ring == address(0)) revert InvalidRingContract();
        address old = address(ringContract);
        ringContract = IAetherRing(_ring);
        emit RingContractUpdated(old, _ring);
    }

    /**
     * @notice 更新 USDC 合约地址（切换 USDC 实现时用）
     * @param _usdc 新的 USDC 合约地址（需实现 decimals()；门槛将按新代币精度重算）
     */
    function setUsdcToken(address _usdc) external onlyRole(ADMIN_ROLE) {
        if (_usdc == address(0)) revert InvalidUsdcToken();
        address old = usdc;
        usdc = _usdc;
        // 同步重算最低捐款额，避免换币后门槛失真（如 6→18 decimals 切换）
        uint256 newMin = _computeMinDonation(_usdc);
        uint256 oldMin = MIN_DONATION_USD;
        MIN_DONATION_USD = newMin;
        emit UsdcTokenUpdated(old, _usdc);
        if (newMin != oldMin) {
            emit MinDonationUpdated(oldMin, newMin);
        }
    }

    // ═══════════════════════════════════════════════════════════
    //               SBT 不可转让
    // ═══════════════════════════════════════════════════════════

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            revert NonTransferable();
        }
        return super._update(to, tokenId, auth);
    }

    function approve(address, uint256) public pure override {
        revert NonTransferableApproval();
    }

    function setApprovalForAll(address, bool) public pure override {
        revert NonTransferableApproval();
    }

    // ═══════════════════════════════════════════════════════════
    //               supportsInterface
    // ═══════════════════════════════════════════════════════════

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return interfaceId == type(IAetherDonation).interfaceId || super.supportsInterface(interfaceId);
    }
}
