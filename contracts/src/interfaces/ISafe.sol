// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title ISafe
 * @dev Safe v1.4 最小接口，只暴露治理需要的两个函数
 *
 * 完整 Safe 合约：https://github.com/safe-global/safe-contracts/blob/v1.4.0/contracts/Safe.sol
 *
 * 验证逻辑：
 *   - isOwner(addr):  addr 是否为多签持有人
 *   - getThreshold(): 当前多签阈值（多少个签名才能执行交易）
 *
 * 调用方式（在 AetherRing / Governance 里）：
 *   require(safe.isOwner(msg.sender), "Not multisig owner");
 *   // 或者由 Safe 发起 execTransaction 来调本合约的 admin 函数
 *   // 这种情况下 msg.sender == safeAddress，直接验证地址即可
 */
interface ISafe {
    function isOwner(address owner) external view returns (bool);
    function getThreshold() external view returns (uint256);
    function getOwners() external view returns (address[] memory);
}
