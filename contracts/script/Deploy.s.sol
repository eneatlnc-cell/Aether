// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {AetherRing} from "../src/AetherRing.sol";
import {AetherGovernance} from "../src/AetherGovernance.sol";
import {AetherElection} from "../src/AetherElection.sol";

/**
 * @title Deploy
 * @dev 部署 AetherRing → AetherGovernance → AetherElection，并完成交叉授权
 *
 * 部署顺序：
 *   1. AetherRing        — SBT 身份凭证（自带 admin/minter 角色）
 *   2. AetherGovernance  — 引用 ring 地址
 *   3. AetherElection    — 引用 ring 地址
 *   4. 授权：
 *      - ring.ADMIN_ROLE → governance（IMPEACHMENT execute 调 revokeRing）
 *      - ring.ADMIN_ROLE → election（选举成功调 updateTier / renewTerm）
 *      - ring.MINTER_ROLE → governance / election（铸造新道环，如选举新进会员）
 *   5. 可选：gov.grantProposerRole 给初始议员
 *
 * 用法：
 *   anvil &
 *   forge script script/Deploy.s.sol:Deploy \
 *     --rpc-url http://127.0.0.1:8545 \
 *     --broadcast \
 *     -vvv
 *
 * 部署到 Arbitrum Sepolia：
 *   forge script script/Deploy.s.sol:Deploy \
 *     --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify
 */
contract Deploy is Script {
    // ── 部署的合约地址（广播后填回） ──
    address public ringAddress;
    address public governanceAddress;
    address public electionAddress;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

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

        // 4. 交叉授权
        // 4.1 governance 需要 ring.ADMIN_ROLE 才能在 IMPEACHMENT execute 时调 revokeRing
        ring.grantRole(AetherRing.ADMIN_ROLE, governanceAddress);
        // 4.2 election 需要 ring.ADMIN_ROLE 才能在 finalize 时调 updateTier / renewTerm
        ring.grantRole(AetherRing.ADMIN_ROLE, electionAddress);
        // 4.3 election 需要 ring.MINTER_ROLE（可选，用于选举新会员铸造道环的场景）
        ring.grantRole(AetherRing.MINTER_ROLE, electionAddress);

        vm.stopBroadcast();

        // ── 控制台输出 ──
        console2.log("=== Aether DAO Deployment ===");
        console2.log("Deployer:        ", deployer);
        console2.log("AetherRing:      ", ringAddress);
        console2.log("AetherGovernance:", governanceAddress);
        console2.log("AetherElection:  ", electionAddress);
        console2.log("");
        console2.log("Roles granted:");
        console2.log("  ring.ADMIN_ROLE  -> governance (for IMPEACHMENT revokeRing)");
        console2.log("  ring.ADMIN_ROLE  -> election   (for updateTier / renewTerm)");
        console2.log("  ring.MINTER_ROLE -> election   (for minting new rings)");
        console2.log("");
        console2.log("Next steps:");
        console2.log("  1. Mint initial rings for council members via ring.mintRing()");
        console2.log("  2. Set Safe multisig wallet: ring.setSafeWallet(<SAFE>) + gov.setSafeWallet(<SAFE>)");
        console2.log("  3. Grant PROPOSER_ROLE to addresses allowed to create proposals:");
        console2.log("     gov.grantProposerRole(<addr>)");
        console2.log("  4. Update frontend src/lib/contracts/config.ts with the above addresses");
    }
}
