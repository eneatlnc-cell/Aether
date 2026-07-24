// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IAetherDonation
 * @dev AetherDonation 合约对外暴露的最小接口
 *      供前端 / 治理合约 / 审计脚本引用，避免循环依赖
 *
 * 设计依据：
 *  - V7  捐款凭证 NFT 去重逻辑（首次捐款铸公民道环，二次不重复）
 *  - V8  防女巫机制（PayPal 账户去重 + 3 公民担保快速通道）
 *  - V11 公民放弃冷却期（30 天，调 ring.canReacquireCitizenship 检查）
 *  - Q8  Donation NFT = ERC-721 SBT，链下兑换 + 链上 settle
 */
interface IAetherDonation {
    /// @notice 捐款凭证数据结构（与 AetherDonation.Donation 一致）
    struct Donation {
        address donor;
        uint256 amount; // USD 最小单位（6 decimals）
        uint256 usdcAmount; // 实际注入国库的 USDC（settle 时填）
        string paypalTxId;
        bytes32 paypalAccountHash; // V8 防女巫：keccak256(payer_id)
        uint256 timestamp;
        bool isSettled;
        // V8 担保快速通道
        uint8 sponsorCount;
        bool fastTrackActivated;
    }

    /// @notice 铸造捐款凭证 NFT（仅 MINTER_ROLE，即 PayPal webhook 服务端）
    ///         - 金额 < $10 revert
    ///         - 重复 paypalTxId revert
    ///         - paypalAccountHash 防女巫：一个 PayPal 账户只能绑定一个钱包（同一钱包可多次捐款）
    ///         - 公民放弃冷却期内 revert
    ///         - 首次捐款：同时铸公民道环
    function mintDonation(address donor, uint256 amount, string calldata paypalTxId, bytes32 paypalAccountHash)
        external
        returns (uint256 tokenId);

    /// @notice 多签结算（仅 ADMIN_ROLE），记录实际注入国库的 USDC 数量
    function settleDonation(uint256 tokenId, uint256 usdcAmount) external;

    /// @notice 查询捐款凭证
    function getDonation(uint256 tokenId) external view returns (Donation memory);

    /// @notice 查询某 donor 的所有捐款凭证 tokenId
    function getDonationsByDonor(address donor) external view returns (uint256[] memory);

    /// @notice 查询捐款凭证总数
    function getTotalDonations() external view returns (uint256);

    /// @notice 查询未结算的捐款 tokenId 列表（审计用）
    function getUnsettledDonations() external view returns (uint256[] memory);

    /// @notice 担保捐款（3 个公民担保后激活快速通道）
    function sponsorDonation(uint256 tokenId) external;

    /// @notice 查询某捐款是否已激活快速通道
    function isFastTrackActivated(uint256 tokenId) external view returns (bool);

    /// @notice 查询某 donor 是否可重新获取公民身份（代理到 ring.canReacquireCitizenship）
    function canReacquireCitizenship(address user) external view returns (bool);
}
