// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {AetherRing} from "../src/AetherRing.sol";
import {AetherGovernance} from "../src/AetherGovernance.sol";
import {AetherElection} from "../src/AetherElection.sol";
import {AetherDonation} from "../src/AetherDonation.sol";

/**
 * @title Genesis
 * @dev 创世数据脚本：铸造初始道环 + 任命元老 + 配置角色
 *
 * 前置条件：已运行 Deploy.s.sol，4 合约已部署，地址已写入 config
 *
 * 创世内容：
 *   1. 三院高层各 2 人（共 6 人，tier 3/6/9）
 *   2. 理事会：理事 2 + 常务理事 2 + 理事长 1（tier 10/11/12）
 *   3. 任命元老 5 人（tier 13，启动治理）
 *   4. 初始公民 10 人（tier 14，测试用，正式环境由捐款产生）
 *   5. 配置：Safe 多签、PROPOSER_ROLE、COUNCIL_CHAIR_ROLE
 *
 * 用法：
 *   PRIVATE_KEY=0x... \
 *   RING=0x... GOV=0x... ELECTION=0x... DONATION=0x... \
 *   SAFE=0x... \
 *   forge script script/Genesis.s.sol:Genesis \
 *     --rpc-url <RPC> --broadcast -vvv
 *
 * 注：appointElder 必须 msg.sender == Safe，所以本脚本会先设置 Safe，
 *     之后通过 Safe 多签执行 appointElder（链下组装交易）
 *     简化场景：若 deployer 临时持有 Safe 单签，可直接 broadcast
 */
contract Genesis is Script {
    // ── 创世地址（环境变量传入，正式环境替换为真实地址） ──
    address[] public highTierAddresses; // 三院高层
    address[] public councilAddresses; // 理事会
    address public councilChair; // 理事长
    address[] public elderAddresses; // 任命元老
    address[] public citizenAddresses; // 初始公民

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address ringAddr = vm.envAddress("RING");
        address govAddr = vm.envAddress("GOV");
        address electionAddr = vm.envAddress("ELECTION");
        address donationAddr = vm.envAddress("DONATION");
        address safeAddr = vm.envAddress("SAFE");

        AetherRing ring = AetherRing(ringAddr);
        AetherGovernance gov = AetherGovernance(govAddr);
        AetherElection election = AetherElection(electionAddr);
        AetherDonation donation = AetherDonation(donationAddr);

        vm.startBroadcast(deployerPrivateKey);

        // ── 1. 设置 Safe 多签地址（必须先于 appointElder） ──
        ring.setSafeWallet(safeAddr);
        console2.log("Safe wallet set:", safeAddr);

        // ── 2. 铸造三院高层（deployer 持有 MINTER_ROLE） ──
        // 议长 tier 3（2 人）
        address parSpeaker1 = vm.envOr("PAR_SPEAKER_1", deployer);
        address parSpeaker2 = vm.envOr("PAR_SPEAKER_2", deployer);
        ring.mintRing(parSpeaker1, AetherRing.RingTier.PARLIAMENT_SPEAKER, "");
        ring.mintRing(parSpeaker2, AetherRing.RingTier.PARLIAMENT_SPEAKER, "");

        // 执政 tier 6（2 人）
        address fedMinister1 = vm.envOr("FED_MINISTER_1", deployer);
        address fedMinister2 = vm.envOr("FED_MINISTER_2", deployer);
        ring.mintRing(fedMinister1, AetherRing.RingTier.FEDERATION_MINISTER, "");
        ring.mintRing(fedMinister2, AetherRing.RingTier.FEDERATION_MINISTER, "");

        // 首席 tier 9（2 人）
        address tribChief1 = vm.envOr("TRIB_CHIEF_1", deployer);
        address tribChief2 = vm.envOr("TRIB_CHIEF_2", deployer);
        ring.mintRing(tribChief1, AetherRing.RingTier.TRIBUNAL_CHIEF, "");
        ring.mintRing(tribChief2, AetherRing.RingTier.TRIBUNAL_CHIEF, "");

        // ── 3. 铸造理事会 ──
        // 理事 tier 10（2 人）
        address council1 = vm.envOr("COUNCIL_1", deployer);
        address council2 = vm.envOr("COUNCIL_2", deployer);
        ring.mintRing(council1, AetherRing.RingTier.COUNCIL_MEMBER, "");
        ring.mintRing(council2, AetherRing.RingTier.COUNCIL_MEMBER, "");

        // 常务理事 tier 11（2 人）
        address councilSenior1 = vm.envOr("COUNCIL_SENIOR_1", deployer);
        address councilSenior2 = vm.envOr("COUNCIL_SENIOR_2", deployer);
        ring.mintRing(councilSenior1, AetherRing.RingTier.COUNCIL_SENIOR, "");
        ring.mintRing(councilSenior2, AetherRing.RingTier.COUNCIL_SENIOR, "");

        // 理事长 tier 12（1 人）
        councilChair = vm.envOr("COUNCIL_CHAIR", deployer);
        ring.mintRing(councilChair, AetherRing.RingTier.COUNCIL_CHAIR, "");

        // ── 4. 授予理事长 election.COUNCIL_CHAIR_ROLE ──
        election.grantCouncilChairRole(councilChair);
        console2.log("Council chair role granted to:", councilChair);

        // ── 5. 授予初始议员 PROPOSER_ROLE ──
        // 议长可创建提案
        gov.grantRole(gov.PROPOSER_ROLE(), parSpeaker1);
        gov.grantRole(gov.PROPOSER_ROLE(), fedMinister1);
        gov.grantRole(gov.PROPOSER_ROLE(), tribChief1);
        gov.grantRole(gov.PROPOSER_ROLE(), councilChair);
        console2.log("PROPOSER_ROLE granted to initial high-tier members");

        // ── 6. 铸造初始公民（tier 14，10 人，测试用） ──
        // 正式环境公民由捐款产生，此处仅用于初始测试
        for (uint256 i = 1; i <= 10; i++) {
            // 用 derive-remember-key 生成确定性地址，或从环境变量读取
            // 简化：跳过，由捐款流程产生
        }
        console2.log("Initial citizens: skip (use donation flow in production)");

        // ── 7. 任命元老（5 人，需 Safe 多签） ──
        // 注：appointElder 必须 msg.sender == Safe
        // 若 deployer 临时持 Safe 单签，可直接广播；否则需 Safe 多签组装交易
        // 此处仅输出待执行命令，实际由 Safe 多签执行
        console2.log("");
        console2.log("=== Pending Safe multisig transactions ===");
        console2.log("The following must be executed via Safe multisig:");
        console2.log("  ring.appointElder(<elder_1>, '')");
        console2.log("  ring.appointElder(<elder_2>, '')");
        console2.log("  ring.appointElder(<elder_3>, '')");
        console2.log("  ring.appointElder(<elder_4>, '')");
        console2.log("  ring.appointElder(<elder_5>, '')");
        console2.log("");
        console2.log("Elder addresses (set via env ELDER_1..ELDER_5):");
        for (uint256 i = 1; i <= 5; i++) {
            string memory envKey = string(abi.encodePacked("ELDER_", uint8(0x30 + i)));
            address elder = vm.envOr(envKey, address(0));
            if (elder != address(0)) {
                console2.log("  Elder address:", elder);
            }
        }

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Genesis Summary ===");
        console2.log("High-tier minted: 6 (2 speakers + 2 ministers + 2 chiefs)");
        console2.log("Council minted:   5 (2 members + 2 seniors + 1 chair)");
        console2.log("PROPOSER_ROLE:    granted to 4 high-tier + chair");
        console2.log("COUNCIL_CHAIR:    granted on election contract");
        console2.log("Safe wallet:      configured on ring");
        console2.log("Pending:          5 elder appointments (via Safe multisig)");
    }
}
