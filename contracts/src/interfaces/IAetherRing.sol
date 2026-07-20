// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IAetherRing
 * @dev AetherGovernance 依赖的最小接口，避免直接 import 实现合约
 */
interface IAetherRing {
    /// @notice 检查地址是否持有有效道环
    function isBearer(address holder) external view returns (bool);

    /// @notice 获取地址的权级编码（0=无，1-10 对应 RingTier）
    function getTier(address holder) external view returns (uint8);

    /// @notice 获取地址持有的道环 tokenId（0 表示无）
    function getRingId(address holder) external view returns (uint256);

    /// @notice 获取当前 GENERAL_MEMBER (tier==10) 总数
    /// @dev 用于治理合约计算会员参与率分母
    function getTotalMembers() external view returns (uint256);
}
