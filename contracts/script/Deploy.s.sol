// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {AetherRing} from "../src/AetherRing.sol";
import {AetherGovernance} from "../src/AetherGovernance.sol";
import {AetherElection} from "../src/AetherElection.sol";
import {AetherDonation} from "../src/AetherDonation.sol";

/**
 * @title Deploy
 * @dev 部署 AetherRing → AetherGovernance → AetherElection → AetherDonation，并完成交叉授权
 *
 * 部署顺序：
 *   1. AetherRing        — SBT 身份凭证（自带 admin/minter 角色）
 *   2. AetherGovernance  — 引用 ring 地址
 *   3. AetherElection    — 引用 ring 地址
 *   4. AetherDonation    — 引用 ring 地址 + treasury + USDC
 *   5. 交叉授权：
 *      - ring.ADMIN_ROLE      → governance（IMPEACHMENT execute 调 revokeRing）
 *      - ring.ADMIN_ROLE      → election（选举成功调 updateTier）
 *      - ring.MINTER_ROLE     → election（铸造新道环）
 *      - ring.MINTER_ROLE     → donation（铸公民道环 + 重新激活休眠公民）
 *      - ring.GOVERNANCE_ROLE → governance（调 markVoteActivity）
 *      - ring.ELECTION_ROLE   → election（调 markVoteActivity）
 *   6. 配置 Safe 多签（ring.setSafeWallet + DEFAULT_ADMIN_ROLE 转交 4 合约）
 *
 * v3.3 改造（纯链上 USDC 捐款，移除 PayPal webhook）：
 *   - H5  TREASURY 环境变量强制要求（不再用 deployer 兜底，避免国库指向部署者）
 *   - H8  4 合约 DEFAULT_ADMIN_ROLE 授予 Safe 多签（deployer 仍保留用于 Genesis，Genesis 后应手动 renounce）
 *   - M9  donation.ADMIN_ROLE 授予 Safe 多签（setTreasury / setRingContract / setUsdcToken 由 Safe 控制）
 *   - M12 必需环境变量校验（缺失则 revert，避免脚本部分成功导致状态不一致）
 *   - 新增 USDC 环境变量（必需）：捐款合约构造函数参数，纯链上转账用
 *   - 删除 PAYPAL_SERVER 环境变量与 donation.MINTER_ROLE 授权（donateAndMint 为 public，无需外部 minter）
 *
 * USDC 地址参考：
 *   - Arbitrum One 主网原生 USDC：0xaf88d065e77c8cC2239327C5EDb3A432268e5831
 *   - Arbitrum Sepolia 测试网 USDC 地址需部署时确认（通过环境变量传入）
 *   - 部署占位：0x0000000000000000000000000000000000000000（仅用于本地 anvil 测试，
 *     真实部署必须传入有效 USDC 合约地址）
 *
 * 注：Solidity 0.8.26 不支持 ContractName.ConstantName 跨合约访问 public constant，
 *     所有角色常量通过实例 getter 获取（如 ring.ADMIN_ROLE()）
 *
 * 必需环境变量：
 *   PRIVATE_KEY      部署私钥
 *   TREASURY         Safe 多签国库地址（USDC 接收方，H5：不再兜底）
 *   SAFE             Safe 多签钱包地址（接收 DEFAULT_ADMIN_ROLE + donation.ADMIN_ROLE + ring.setSafeWallet）
 *   USDC             USDC 合约地址（donateAndMint 链上转账用）
 *
 * 用法：
 *   anvil &
 *   PRIVATE_KEY=0x... TREASURY=0x... SAFE=0x... USDC=0x... \
 *   forge script script/Deploy.s.sol:Deploy \
 *     --rpc-url http://127.0.0.1:8545 \
 *     --broadcast \
 *     -vvv
 *
 * 部署到 Arbitrum Sepolia：
 *   PRIVATE_KEY=0x... TREASURY=0x... SAFE=0x... USDC=0x... \
 *   forge script script/Deploy.s.sol:Deploy \
 *     --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
 *     --broadcast \
 *     --verify
 */
contract Deploy is Script {
    // ── 部署的合约地址（广播后填回） ──
    address public ringAddress;
    address public governanceAddress;
    address public electionAddress;
    address public donationAddress;

    // ── 必需环境变量校验错误 ──
    error MissingEnv(string name);

    /// @dev M12：必需环境变量校验，缺失即 revert，避免后续步骤状态不一致
    function _requireEnv(string memory name) internal returns (address value) {
        value = vm.envOr(name, address(0));
        if (value == address(0)) revert MissingEnv(name);
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // M12 + H5：TREASURY / SAFE / USDC 必需，缺失即终止
        // 注意：donation 构造函数要求 treasury != address(0) 且 usdc != address(0)
        address treasury = _requireEnv("TREASURY");
        address safeAddr = _requireEnv("SAFE");
        address usdc = _requireEnv("USDC");

        vm.startBroadcast(deployerPrivateKey);

        // 1. 部署 AetherRing
        AetherRing ring = new AetherRing();
        ringAddress = address(ring);

        // 2. 部署 AetherGovernance，引用 ring 地址
        AetherGovernance gov = new AetherGovernance(ringAddress);
        governanceAddress = address(gov);

        // 3. 部署 AetherElection，引用 ring 地址
        AetherElection election = new AetherElection(ringAddress);
        electionAddress = address(election);

        // 4. 部署 AetherDonation，引用 ring 地址 + treasury + USDC + deployer(admin)
        //    H5：treasury 现为强制环境变量，不再用 deployer 兜底
        AetherDonation donation = new AetherDonation(ringAddress, treasury, usdc, deployer);
        donationAddress = address(donation);

        // 5. 交叉授权（合约间互调所需角色）
        // 5.1 governance 需要 ring.ADMIN_ROLE 才能在 IMPEACHMENT execute 时调 revokeRing
        ring.grantRole(ring.ADMIN_ROLE(), governanceAddress);
        // 5.2 election 需要 ring.ADMIN_ROLE 才能在 finalize 时调 updateTier
        ring.grantRole(ring.ADMIN_ROLE(), electionAddress);
        // 5.3 election 需要 ring.MINTER_ROLE（铸造新道环）
        ring.grantRole(ring.MINTER_ROLE(), electionAddress);
        // 5.4 donation 需要 ring.MINTER_ROLE（铸公民道环 + reactivateDormantCitizen）
        ring.grantRole(ring.MINTER_ROLE(), donationAddress);
        // 5.5 governance 需要 ring.GOVERNANCE_ROLE 调 markVoteActivity（v3 公民休眠机制）
        ring.grantRole(ring.GOVERNANCE_ROLE(), governanceAddress);
        // 5.6 election 需要 ring.ELECTION_ROLE 调 markVoteActivity
        ring.grantRole(ring.ELECTION_ROLE(), electionAddress);

        // 6. 配置 Safe 多签（ring.setSafeWallet 必须先于 appointElder）
        ring.setSafeWallet(safeAddr);

        // 7. H8：4 合约 DEFAULT_ADMIN_ROLE 授予 Safe
        //    deployer 仍保留 DEFAULT_ADMIN_ROLE 用于后续 Genesis 脚本；
        //    Genesis 完成后应由 deployer 手动 renounceRole(DEFAULT_ADMIN_ROLE, deployer)
        ring.grantRole(ring.DEFAULT_ADMIN_ROLE(), safeAddr);
        gov.grantRole(gov.DEFAULT_ADMIN_ROLE(), safeAddr);
        election.grantRole(election.DEFAULT_ADMIN_ROLE(), safeAddr);
        donation.grantRole(donation.DEFAULT_ADMIN_ROLE(), safeAddr);

        // 8. M9：donation.ADMIN_ROLE 授予 Safe（setTreasury / setRingContract / setUsdcToken 由 Safe 控制）
        donation.grantRole(donation.ADMIN_ROLE(), safeAddr);

        vm.stopBroadcast();

        // ── 控制台输出 ──
        console2.log("=== Aether DAO Deployment ===");
        console2.log("Deployer:        ", deployer);
        console2.log("Treasury:        ", treasury);
        console2.log("Safe multisig:   ", safeAddr);
        console2.log("USDC token:      ", usdc);
        console2.log("AetherRing:      ", ringAddress);
        console2.log("AetherGovernance:", governanceAddress);
        console2.log("AetherElection:  ", electionAddress);
        console2.log("AetherDonation:  ", donationAddress);
        console2.log("");
        console2.log("Roles granted on AetherRing:");
        console2.log("  ADMIN_ROLE       -> governance (IMPEACHMENT revokeRing)");
        console2.log("  ADMIN_ROLE       -> election   (updateTier)");
        console2.log("  MINTER_ROLE      -> election   (minting new rings)");
        console2.log("  MINTER_ROLE      -> donation   (mintRing CITIZEN + reactivateDormant)");
        console2.log("  GOVERNANCE_ROLE  -> governance (markVoteActivity)");
        console2.log("  ELECTION_ROLE    -> election   (markVoteActivity)");
        console2.log("  DEFAULT_ADMIN_ROLE -> Safe (H8)");
        console2.log("  safeWallet       -> Safe (ring.setSafeWallet)");
        console2.log("");
        console2.log("Roles granted on AetherDonation:");
        console2.log("  ADMIN_ROLE         -> Safe (M9)");
        console2.log("  DEFAULT_ADMIN_ROLE -> Safe (H8)");
        console2.log("  (donateAndMint is public, no MINTER_ROLE needed)");
        console2.log("");
        console2.log("Roles granted on AetherGovernance / AetherElection:");
        console2.log("  DEFAULT_ADMIN_ROLE -> Safe (H8)");
        console2.log("");
        console2.log("Next steps:");
        console2.log("  1. Run Genesis.s.sol to mint initial rings + appoint elders + 10 citizens");
        console2.log("  2. After Genesis: deployer renounces DEFAULT_ADMIN_ROLE on all 4 contracts");
        console2.log("     (call renounceRole(DEFAULT_ADMIN_ROLE, deployer) via each contract)");
        console2.log("  3. Grant PROPOSER_ROLE to initial chamber members via gov.grantProposerRole()");
        console2.log("  4. Update frontend src/lib/contracts/config.ts with the above addresses");
    }
}
