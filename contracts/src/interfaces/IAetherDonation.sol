// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

/**
 * @title IAetherDonation
 * @dev AetherDonation 合约对外暴露的最小接口
 *      供前端 / 治理合约 / 审计脚本引用，避免循环依赖
 *
 * 设计依据：
 *  - 纯链上 USDC 捐款：用户 approve USDC → 调 donateAndMint，一笔交易完成转账 + 铸 NFT + 铸公民道环
 *  - V7  捐款凭证 NFT 去重逻辑（首次捐款铸公民道环，二次不重复）
 *  - V8  防女巫：3 公民担保快速通道（链上转账天然防女巫，无需账户去重）
 *  - V11 公民放弃冷却期（30 天，调 ring.canReacquireCitizenship 检查）
 *  - Q8  Donation NFT = ERC-721 SBT，不可转让
 */
interface IAetherDonation {
    /// @notice 捐款凭证数据结构（与 AetherDonation.Donation 一致）
    struct Donation {
        address donor;
        uint256 amount; // USDC 数量（6 decimals）
        uint256 timestamp;
        // V8 担保快速通道
        uint8 sponsorCount;
        bool fastTrackActivated;
    }

    /// @notice 纯链上捐款：转账 USDC + 铸捐款凭证 NFT + 铸公民道环
    ///         任何人可调（public），需先 approve USDC 给本合约
    ///         - 金额 < $10 revert
    ///         - 公民放弃冷却期内 revert
    ///         - USDC transferFrom 失败 revert
    ///         - 首次捐款：同时铸公民道环
    ///         - 休眠公民：重新激活
    /// @return tokenId 新铸的捐款凭证 ID
    function donateAndMint(uint256 amount) external returns (uint256 tokenId);

    /// @notice 查询捐款凭证
    function getDonation(uint256 tokenId) external view returns (Donation memory);

    /// @notice 查询某 donor 的所有捐款凭证 tokenId
    function getDonationsByDonor(address donor) external view returns (uint256[] memory);

    /// @notice 查询捐款凭证总数
    function getTotalDonations() external view returns (uint256);

    /// @notice 担保捐款（3 个公民担保后激活快速通道）
    function sponsorDonation(uint256 tokenId) external;

    /// @notice 查询某捐款是否已激活快速通道
    function isFastTrackActivated(uint256 tokenId) external view returns (bool);

    /// @notice 查询某 donor 是否可重新获取公民身份（代理到 ring.canReacquireCitizenship）
    function canReacquireCitizenship(address user) external view returns (bool);
}
