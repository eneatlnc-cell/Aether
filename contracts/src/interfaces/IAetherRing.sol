// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IAetherRing v3
 * @dev AetherGovernance / AetherElection / AetherDonation 依赖的最小接口
 *      v3 变化：getTotalMembers → getActiveCitizens（排除休眠公民）
 *      新增：markVoteActivity / isElderActive / isExpired / canReacquireCitizenship
 */
interface IAetherRing {
    /// @notice 检查地址是否持有有效道环（活跃 + 未到期 + 非退休 + 非休眠）
    function isBearer(address holder) external view returns (bool);

    /// @notice 获取地址的权级编码（0=无，1-14 对应 RingTier）
    function getTier(address holder) external view returns (uint8);

    /// @notice 获取地址持有的道环 tokenId（0 表示无）
    function getRingId(address holder) external view returns (uint256);

    /// @notice 获取活跃公民总数（用于治理 quorum 分母，排除休眠公民）
    /// @dev v3 替代 v2 的 getTotalMembers()
    function getActiveCitizens() external view returns (uint256);

    /// @notice 获取公民总数（含休眠，审计用）
    function getTotalCitizens() external view returns (uint256);

    /// @notice 检查 tokenId 是否已到期（被动失效）
    function isExpired(uint256 tokenId) external view returns (bool);

    /// @notice 检查地址是否为任命元老（有治理权：否决/弹劾）
    ///         退休元老返回 false
    function isElderActive(address holder) external view returns (bool);

    /// @notice 检查地址是否为退休元老（仅名誉，无治理权）
    function isRetiredElder(address holder) external view returns (bool);

    /// @notice 检查公民是否休眠
    function isDormant(address holder) external view returns (bool);

    /// @notice 治理活动回调（由 Governance/Election 合约调用，更新公民最后活动时间）
    function markVoteActivity(address voter) external;

    /// @notice 检查地址是否可重新获取公民身份（30 天冷却期）
    function canReacquireCitizenship(address user) external view returns (bool);
}
