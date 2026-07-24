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
 *   4. AetherDonation    — 引用 ring 地址 + treasury
 *   5. 交叉授权：
 *      - ring.ADMIN_ROLE      → governance（IMPEACHMENT execute 调 revokeRing）
 *      - ring.ADMIN_ROLE      → election（选举成功调 updateTier）
 *      - ring.MINTER_ROLE     → election（铸造新道环）
 *      - ring.MINTER_ROLE     → donation（铸公民道环 + 重新激活休眠公民）
 *      - ring.GOVERNANCE_ROLE → governance（调 markVoteActivity）
 *      - ring.ELECTION_ROLE   → election（调 markVoteActivity）
 *   6. 可选：gov.grantProposerRole 给初始议员
 *
 * 注：Solidity 0.8.26 不支持 ContractName.ConstantName 跨合约访问 public constant，
 *     所有角色常量通过实例 getter 获取（如 ring.ADMIN_ROLE()）
 *
 * 用法：
 *   anvil &
 *   PRIVATE_KEY=0x... TREASURY=0x... forge script script/Deploy.s.sol:Deploy \
 *     --rpc-url http://127.0.0.1:8545 \
 *     --broadcast \
 *     -vvv
 *
 * 部署到 Arbitrum Sepolia：
 *   PRIVATE_KEY=0x... TREASURY=0x... forge script script/Deploy.s.sol:Deploy \
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

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        // Treasury = Safe 多签国库地址（USDC 接收方）
        // 未设置时用 deployer 占位，部署后需 donation.setTreasury(<SAFE>) 更新
        address treasury = vm.envOr("TREASURY", deployer);

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

        // 4. 部署 AetherDonation，引用 ring 地址 + treasury + deployer(admin)
        AetherDonation donation = new AetherDonation(ringAddress, treasury, deployer);
        donationAddress = address(donation);

        // 5. 交叉授权
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

        vm.stopBroadcast();

        // ── 控制台输出 ──
        console2.log("=== Aether DAO Deployment ===");
        console2.log("Deployer:        ", deployer);
        console2.log("Treasury:        ", treasury);
        console2.log("AetherRing:      ", ringAddress);
        console2.log("AetherGovernance:", governanceAddress);
        console2.log("AetherElection:  ", electionAddress);
        console2.log("AetherDonation:  ", donationAddress);
        console2.log("");
        console2.log("Roles granted on AetherRing:");
        console2.log("  ADMIN_ROLE      -> governance (IMPEACHMENT revokeRing)");
        console2.log("  ADMIN_ROLE      -> election   (updateTier)");
        console2.log("  MINTER_ROLE     -> election   (minting new rings)");
        console2.log("  MINTER_ROLE     -> donation   (mintRing CITIZEN + reactivateDormant)");
        console2.log("  GOVERNANCE_ROLE -> governance (markVoteActivity)");
        console2.log("  ELECTION_ROLE   -> election   (markVoteActivity)");
        console2.log("");
        console2.log("Next steps:");
        console2.log("  1. Mint initial rings for council members via ring.mintRing()");
        console2.log("  2. Set Safe multisig wallet: ring.setSafeWallet(<SAFE>)");
        console2.log("  3. Transfer donation ADMIN_ROLE to Safe: donation.grantRole(donation.ADMIN_ROLE(), <SAFE>)");
        console2.log("  4. Set PayPal webhook minter: donation.grantMinterRole(<PAYPAL_SERVER>)");
        console2.log("  5. Update treasury: donation.setTreasury(<SAFE>)");
        console2.log("  6. Grant PROPOSER_ROLE: gov.grantProposerRole(<addr>)");
        console2.log("  7. Grant election COUNCIL_CHAIR_ROLE: election.grantCouncilChairRole(<addr>)");
        console2.log("     (v3: chair handles approveCandidate/rejectCandidate/appointToVacancy)");
        console2.log("  8. Update frontend src/lib/contracts/config.ts with the above addresses");
    }
}
