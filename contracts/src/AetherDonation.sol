// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAetherRing} from "./interfaces/IAetherRing.sol";
import {IAetherDonation} from "./interfaces/IAetherDonation.sol";
import {AetherRing} from "./AetherRing.sol";

/**
 * @title AetherDonation — PayPal 捐款凭证 NFT + 公民身份发放
 * @author Aether Foundation
 *
 * ═══════════════════════════════════════════════════════════════
 *  设计依据
 * ═══════════════════════════════════════════════════════════════
 *
 *  - Q8  Donation NFT = ERC-721 SBT，不可转让，链下兑换 + 链上 settle
 *  - V7  首次捐款铸公民道环，二次捐款不重复铸（去重逻辑）
 *  - V8  防女巫：PayPal 账户去重（paypalAccountHash）+ 3 公民担保快速通道
 *  - V11 公民放弃冷却期 30 天（调 ring.canReacquireCitizenship 检查）
 *  - 补充 捐款门槛 ≥ $10（MIN_DONATION_USD = 10 * 10^6，USDC 6 decimals）
 *
 * ═══════════════════════════════════════════════════════════════
 *  角色权限
 * ═══════════════════════════════════════════════════════════════
 *
 *  - DEFAULT_ADMIN_ROLE  部署者（初始化后转交 Safe 多签）
 *  - ADMIN_ROLE          Safe 多签（settleDonation + 管理函数）
 *  - MINTER_ROLE         PayPal webhook 服务端（mintDonation）
 *
 *  部署后需在 AetherRing 上授权：
 *    ring.grantRole(ring.MINTER_ROLE(), address(donation))
 *  以便 donation 合约在首次捐款时铸公民道环 / 重新激活休眠公民
 *
 * ═══════════════════════════════════════════════════════════════
 *  mintDonation 四重校验
 * ═══════════════════════════════════════════════════════════════
 *
 *  1. amount >= MIN_DONATION_USD（$10）
 *  2. paypalTxId 防重放（usedPaypalTxIds）
 *  3. paypalAccountHash 防女巫：一个 PayPal 账户绑定一个钱包（同一钱包可多次捐款）
 *  4. canReacquireCitizenship 冷却期检查（30 天）
 *
 *  通过后：
 *  - 铸捐款凭证 NFT（每笔捐款都铸）
 *  - 首次捐款（ringId==0）：铸公民道环
 *  - 休眠公民（ringId!=0 但 dormant）：重新激活
 *  - 已活跃公民：仅铸捐款凭证
 */
contract AetherDonation is ERC721, AccessControl, IAetherDonation {
    // ──────────── 角色 ────────────
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // ──────────── 引用 ────────────
    IAetherRing public ringContract;
    address public treasury; // Safe 多签国库地址（USDC 接收方，仅记录用）

    // ──────────── 常量 ────────────
    uint256 public constant MIN_DONATION_USD = 10 * 10 ** 6; // $10（USDC 6 decimals）
    uint256 public constant SPONSORS_REQUIRED = 3; // V8: 3 公民担保激活快速通道
    uint256 public constant FAST_TRACK_DELAY = 24 hours; // 快速通道等待期
    uint256 public constant NORMAL_TRACK_DELAY = 7 days; // 普通通道等待期

    // ──────────── 存储 ────────────
    mapping(uint256 => Donation) private _donations;
    mapping(string => bool) public usedPaypalTxIds; // V7 防重放
    mapping(bytes32 => address) public paypalAccountToWallet; // V8 PayPal hash → 钱包（防女巫）
    mapping(address => uint256[]) private _donorTokenIds; // donor → tokenId 列表
    mapping(uint256 => mapping(address => bool)) public hasSponsored; // tokenId → sponsor → bool

    uint256 private _nextTokenId = 1; // 从 1 开始（0 表示"无"）

    // ──────────── 事件 ────────────
    event DonationMinted(uint256 indexed tokenId, address indexed donor, uint256 amount, string paypalTxId);
    event DonationSettled(uint256 indexed tokenId, uint256 usdcAmount);
    event SponsorAdded(uint256 indexed tokenId, address indexed sponsor, uint8 sponsorCount);
    event FastTrackActivated(uint256 indexed tokenId);
    event CitizenRingMinted(address indexed donor, uint256 ringTokenId);
    event DormantCitizenReactivated(address indexed donor);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event RingContractUpdated(address indexed oldRing, address indexed newRing);
    event PaypalAccountUnlinked(bytes32 indexed paypalAccountHash, address indexed oldWallet);

    // ──────────── 错误 ────────────
    error DonationTooSmall(uint256 amount, uint256 minRequired);
    error DuplicatePayPalTx(string paypalTxId);
    error DuplicatePayPalAccount(bytes32 paypalAccountHash);
    error RenounceCooldownActive(address donor);
    error DonationNotFound(uint256 tokenId);
    error AlreadySettled(uint256 tokenId);
    error AlreadyFastTrack(uint256 tokenId);
    error AlreadySponsored(uint256 tokenId, address sponsor);
    error NotCitizen(address sponsor);
    error CannotSelfSponsor(uint256 tokenId, address donor);
    error NonTransferable();
    error NonTransferableApproval();
    error InvalidTreasury();
    error InvalidRingContract();

    // ═══════════════════════════════════════════════════════════
    //                       构造函数
    // ═══════════════════════════════════════════════════════════

    /**
     * @param ring      AetherRing 合约地址
     * @param _treasury Safe 多签国库地址（USDC 接收方）
     * @param admin     初始管理员（部署者，后续转交 Safe）
     */
    constructor(address ring, address _treasury, address admin) ERC721("Aether Donation", "AETHD") {
        if (ring == address(0)) revert InvalidRingContract();
        if (_treasury == address(0)) revert InvalidTreasury();

        ringContract = IAetherRing(ring);
        treasury = _treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    // ═══════════════════════════════════════════════════════════
    //               mintDonation 核心（步骤 2.3）
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 铸造捐款凭证 NFT（仅 MINTER_ROLE，即 PayPal webhook 服务端）
     * @param donor             捐款人地址
     * @param amount            捐款金额（USD 6 decimals，≥ $10）
     * @param paypalTxId        PayPal 交易 ID（防重放）
     * @param paypalAccountHash PayPal 账户哈希 keccak256(payer_id)（防女巫去重）
     * @return tokenId 新铸的捐款凭证 ID
     *
     * 流程：
     *   1. 四重校验（金额 / TxId 防重放 / PayPal 账户防女巫 / 冷却期）
     *   2. 铸捐款凭证 NFT
     *   3. 首次捐款 → 铸公民道环；休眠公民 → 重新激活
     */
    function mintDonation(address donor, uint256 amount, string calldata paypalTxId, bytes32 paypalAccountHash)
        external
        onlyRole(MINTER_ROLE)
        returns (uint256)
    {
        // ── 1. 四重校验 ──
        if (amount < MIN_DONATION_USD) revert DonationTooSmall(amount, MIN_DONATION_USD);
        // Medium: PayPal TxId 非空检查（防止空字符串占用防重放映射）
        if (bytes(paypalTxId).length == 0) revert DuplicatePayPalTx(paypalTxId);
        if (usedPaypalTxIds[paypalTxId]) revert DuplicatePayPalTx(paypalTxId);
        // V8 防女巫：一个 PayPal 账户只能绑定一个钱包（同一钱包可多次捐款）
        address linkedWallet = paypalAccountToWallet[paypalAccountHash];
        if (linkedWallet != address(0) && linkedWallet != donor) {
            revert DuplicatePayPalAccount(paypalAccountHash);
        }
        if (!ringContract.canReacquireCitizenship(donor)) revert RenounceCooldownActive(donor);

        // ── 2. 标记已用（防重放 + PayPal 账户绑定钱包） ──
        usedPaypalTxIds[paypalTxId] = true;
        if (linkedWallet == address(0)) {
            paypalAccountToWallet[paypalAccountHash] = donor;
        }

        // ── 3. 铸捐款凭证 NFT（CEI：先写状态再铸） ──
        uint256 tokenId = _nextTokenId++;
        // M1: 状态写入前置，防止 _safeMint 回调重入造成状态不一致
        _donations[tokenId] = Donation({
            donor: donor,
            amount: amount,
            usdcAmount: 0,
            paypalTxId: paypalTxId,
            paypalAccountHash: paypalAccountHash,
            timestamp: block.timestamp,
            isSettled: false,
            sponsorCount: 0,
            fastTrackActivated: false
        });
        _donorTokenIds[donor].push(tokenId);
        _safeMint(donor, tokenId);

        // ── 4. 公民身份发放 / 重新激活 ──
        uint256 ringId = ringContract.getRingId(donor);
        if (ringId == 0) {
            // 首次捐款：铸公民道环
            ringContract.mintRing(donor, IAetherRing.RingTier.CITIZEN, "");
            emit CitizenRingMinted(donor, ringContract.getRingId(donor));
        } else {
            // Bug 30: 仅在确实休眠时才发重新激活事件，避免乐观误发
            bool wasDormant = ringContract.isDormant(donor);
            ringContract.reactivateDormantCitizen(donor);
            if (wasDormant) {
                emit DormantCitizenReactivated(donor);
            }
        }

        emit DonationMinted(tokenId, donor, amount, paypalTxId);
        return tokenId;
    }

    // ═══════════════════════════════════════════════════════════
    //               settleDonation 多签结算（步骤 2.4）
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice 多签结算（仅 ADMIN_ROLE），记录实际注入国库的 USDC 数量
     *         USDC 真实到账后由 Safe 多签调用
     * @param tokenId    捐款凭证 ID
     * @param usdcAmount 实际注入国库的 USDC 数量
     */
    function settleDonation(uint256 tokenId, uint256 usdcAmount) external onlyRole(ADMIN_ROLE) {
        Donation storage d = _donations[tokenId];
        if (d.donor == address(0)) revert DonationNotFound(tokenId);
        if (d.isSettled) revert AlreadySettled(tokenId);

        d.usdcAmount = usdcAmount;
        d.isSettled = true;

        emit DonationSettled(tokenId, usdcAmount);
    }

    // ═══════════════════════════════════════════════════════════
    //               3 公民担保快速通道（步骤 2.5，V8）
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
    //               查询函数（步骤 2.7）
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

    /**
     * @notice 查询未结算的捐款 tokenId 列表（审计用）
     * @dev 遍历所有捐款，O(n) 复杂度。仅用于链下审计调用
     */
    function getUnsettledDonations() external view returns (uint256[] memory) {
        uint256 total = _nextTokenId - 1;
        // 先计数
        uint256 unsettledCount = 0;
        for (uint256 i = 1; i <= total; i++) {
            if (!_donations[i].isSettled && _donations[i].donor != address(0)) {
                unsettledCount++;
            }
        }
        // 填充
        uint256[] memory result = new uint256[](unsettledCount);
        uint256 idx = 0;
        for (uint256 i = 1; i <= total; i++) {
            if (!_donations[i].isSettled && _donations[i].donor != address(0)) {
                result[idx++] = i;
            }
        }
        return result;
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

    function grantMinterRole(address account) external onlyRole(ADMIN_ROLE) {
        _grantRole(MINTER_ROLE, account);
    }

    function revokeMinterRole(address account) external onlyRole(ADMIN_ROLE) {
        _revokeRole(MINTER_ROLE, account);
    }

    /**
     * @notice Bug 29: 解绑 PayPal 账户与钱包的绑定（用户丢失私钥 / 迁移钱包时用）
     *         仅 ADMIN_ROLE（Safe 多签）可调用，防止误用绕过防女巫
     * @param paypalAccountHash 要解绑的 PayPal 账户哈希
     */
    function unlinkPaypalAccount(bytes32 paypalAccountHash) external onlyRole(ADMIN_ROLE) {
        address linked = paypalAccountToWallet[paypalAccountHash];
        if (linked == address(0)) revert DuplicatePayPalAccount(paypalAccountHash); // 复用错误码表示未找到
        delete paypalAccountToWallet[paypalAccountHash];
        emit PaypalAccountUnlinked(paypalAccountHash, linked);
    }

    // ═══════════════════════════════════════════════════════════
    //               SBT 不可转让（步骤 2.6）
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
