// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {AetherRing} from "../src/AetherRing.sol";
import {IAetherRing} from "../src/interfaces/IAetherRing.sol";
import {AetherDonation} from "../src/AetherDonation.sol";

/**
 * @title DeployMinimal — Phase 1 最小化部署（捐款 + 创世高层）
 * @dev 只部署 AetherRing + AetherDonation，跳过 Governance / Election
 *
 * 功能：
 *   1. 部署 Ring + Donation，交叉授权
 *   2. 铸造创世高层道环（通过环境变量配置地址）
 *   3. deployer 持有 ADMIN_ROLE，donateAndMint 为 public 无需 MINTER_ROLE
 *
 * 必需环境变量：
 *   PRIVATE_KEY  部署私钥
 *   USDC         USDC 合约地址（donateAndMint 链上转账用）
 *
 * 可选环境变量：
 *   TREASURY         国库地址，默认 = deployer
 *   FOUNDER_1~5      创世高层地址（不设则跳过）
 *   FOUNDER_TIER_1~5 对应层级（1-9），默认 = 3（议长）
 *
 * 用法：
 *   PRIVATE_KEY=0x... \
 *   FOUNDER_1=0xAAA FOUNDER_TIER_1=6 \
 *   FOUNDER_2=0xBBB FOUNDER_TIER_2=9 \
 *   forge script script/DeployMinimal.s.sol:DeployMinimal \
 *     --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
 *     --broadcast -vvv
 *
 * 层级参考：
 *   1=议员  2=参议员  3=议长  4=委员  5=委员长  6=部长  7=顾问  8=研究员  9=元老
 */
contract DeployMinimal is Script {
    address public ringAddress;
    address public donationAddress;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // TREASURY 可选，默认用 deployer
        address treasury = vm.envOr("TREASURY", deployer);
        // USDC 必需：donateAndMint 链上转账用，构造函数校验非零
        address usdc = vm.envOr("USDC", address(0));
        require(usdc != address(0), "DeployMinimal: USDC env required");

        vm.startBroadcast(deployerPrivateKey);

        // ── 1. 部署 AetherRing ──
        AetherRing ring = new AetherRing();
        ringAddress = address(ring);

        // ── 2. 部署 AetherDonation ──
        AetherDonation donation = new AetherDonation(ringAddress, treasury, usdc, deployer);
        donationAddress = address(donation);

        // ── 3. 交叉授权 ──
        ring.grantRole(ring.MINTER_ROLE(), donationAddress);

        // ── 4. 铸造创世高层道环 ──
        _mintFounder(ring, deployer, "FOUNDER_1", "FOUNDER_TIER_1");
        _mintFounder(ring, deployer, "FOUNDER_2", "FOUNDER_TIER_2");
        _mintFounder(ring, deployer, "FOUNDER_3", "FOUNDER_TIER_3");
        _mintFounder(ring, deployer, "FOUNDER_4", "FOUNDER_TIER_4");
        _mintFounder(ring, deployer, "FOUNDER_5", "FOUNDER_TIER_5");

        vm.stopBroadcast();

        // ── 输出 ──
        console2.log("=== Aether Phase 1 - Donation + Founders ===");
        console2.log("Deployer:        ", deployer);
        console2.log("Treasury:        ", treasury);
        console2.log("AetherRing:      ", ringAddress);
        console2.log("AetherDonation:  ", donationAddress);
        console2.log("");
        console2.log("Roles:");
        console2.log("  ring.MINTER_ROLE    -> donation + deployer");
        console2.log("  donation.ADMIN_ROLE -> deployer (setTreasury / setUsdcToken)");
        console2.log("  (donateAndMint is public, no MINTER_ROLE needed)");
        console2.log("");
        console2.log("Next steps:");
        console2.log("  1. Users approve USDC + call donation.donateAndMint() to donate on-chain");
        console2.log("  2. Later: deploy Governance + Election for full governance");
    }

    /// @dev 读取 FOUNDER_N / FOUNDER_TIER_N 环境变量，铸造道环
    function _mintFounder(
        AetherRing ring,
        address deployer,
        string memory addrKey,
        string memory tierKey
    ) internal {
        address founder = vm.envOr(addrKey, address(0));
        if (founder == address(0)) {
            console2.log("  [skip]", addrKey, "not set");
            return;
        }
        if (founder == deployer) {
            console2.log("  [skip]", addrKey, "== deployer (disallowed)");
            return;
        }
        // tier 默认 3（议长），范围 1-9
        uint8 tier = uint8(vm.envOr(tierKey, uint256(3)));
        if (tier < 1 || tier > 9) {
            console2.log("  [skip]", addrKey, "invalid tier", tier);
            return;
        }
        ring.mintRing(founder, IAetherRing.RingTier(tier), "");
        console2.log("  [ok]  ", addrKey, "-> tier", uint256(tier));
        console2.log("         address:", founder);
    }
}
