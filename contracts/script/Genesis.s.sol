// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {AetherRing} from "../src/AetherRing.sol";
import {IAetherRing} from "../src/interfaces/IAetherRing.sol";
import {AetherGovernance} from "../src/AetherGovernance.sol";
import {AetherElection} from "../src/AetherElection.sol";

/**
 * @title Genesis
 * @dev 创世数据脚本：铸造初始道环 + 任命元老 + 配置角色
 *
 * 前置条件：已运行 Deploy.s.sol，4 合约已部署，地址已写入 config
 *
 * 创世内容：
 *   1. 三院高层各 2 人（共 6 人，tier 3/6/9）
 *   2. 理事会：理事 2 + 常务理事 2 + 理事长 1（tier 10/11/12）
 *   3. 任命元老 5 人（tier 13，启动治理）— v3.2 实际调用 appointElder（C3 修复）
 *   4. 初始公民 10 人（tier 14，测试用）— v3.2 实际铸造（H6 修复）
 *   5. 配置：PROPOSER_ROLE（仅授予 tier 1-9 三院成员，H7 修复）、COUNCIL_CHAIR_ROLE
 *
 * v3.2 修复（C3/H6/H7/M12）：
 *   - C3  任命元老实际调用 ring.appointElder(elder, "")（不再仅 console.log）
 *   - H6  初始 10 公民实际铸造（不再循环体为空），从 CITIZEN_1..CITIZEN_10 环境变量读取
 *   - H7  PROPOSER_ROLE 仅授予三院成员（tier 1-9），理事长（tier 12）不授予
 *        （createProposal 受 onlyChamberMember 修饰器限制，tier 12 即使有角色也会 revert）
 *   - M12 创世地址必须 ≠ deployer，否则同一地址重复 mint 触发 AlreadyHasRing revert
 *
 * 必需环境变量：
 *   PRIVATE_KEY      部署私钥（持有 DEFAULT_ADMIN_ROLE + ADMIN_ROLE）
 *   RING             AetherRing 合约地址
 *   GOV              AetherGovernance 合约地址
 *   ELECTION         AetherElection 合约地址
 *   DONATION         AetherDonation 合约地址
 *   SAFE             Safe 多签钱包地址（已在 Deploy.s.sol 中配置为 ring.safeWallet）
 *
 * 创世地址环境变量（缺失时回退到 address(0)，校验后跳过该地址的 mint）：
 *   PAR_SPEAKER_1 / PAR_SPEAKER_2          议长 tier 3
 *   FED_MINISTER_1 / FED_MINISTER_2        执政 tier 6
 *   TRIB_CHIEF_1 / TRIB_CHIEF_2            首席 tier 9
 *   COUNCIL_1 / COUNCIL_2                  理事 tier 10
 *   COUNCIL_SENIOR_1 / COUNCIL_SENIOR_2    常务理事 tier 11
 *   COUNCIL_CHAIR                          理事长 tier 12
 *   ELDER_1..ELDER_5                       任命元老 tier 13
 *   CITIZEN_1..CITIZEN_10                  初始公民 tier 14（测试用，正式环境由捐款产生）
 *
 * 用法：
 *   PRIVATE_KEY=0x... \
 *   RING=0x... GOV=0x... ELECTION=0x... DONATION=0x... SAFE=0x... \
 *   PAR_SPEAKER_1=0x... ... CITIZEN_10=0x... \
 *   forge script script/Genesis.s.sol:Genesis \
 *     --rpc-url <RPC> --broadcast -vvv
 *
 * 注：appointElder 仅需 ADMIN_ROLE（deployer 持有），可由 deployer 直接广播。
 *     retireToEmeritus / resumeFromEmeritus 才需要 msg.sender == Safe。
 */
contract Genesis is Script {
    // ── 必需环境变量校验错误 ──
    error MissingEnv(string name);

    /// @dev M12：必需环境变量校验，缺失即 revert
    function _requireEnv(string memory name) internal returns (address value) {
        value = vm.envOr(name, address(0));
        if (value == address(0)) revert MissingEnv(name);
    }

    /// @dev M12：可选创世地址校验 — 必须非零且 ≠ deployer，否则跳过 mint
    ///      （deployer 已在构造时获得 ADMIN/MINTER，重复 mint 会触发 AlreadyHasRing）
    function _optionalAddr(string memory name, address deployer) internal returns (address value, bool ok) {
        value = vm.envOr(name, address(0));
        if (value == address(0)) {
            console2.log("  [skip] ", name, " not set");
            return (address(0), false);
        }
        if (value == deployer) {
            // M12：deployer 不能作为创世地址（否则同一地址已持 ADMIN_ROLE 但无道环，再 mint 也会触发 AlreadyHasRing 之外的混乱）
            console2.log("  [skip] ", name, " == deployer (M12: disallowed)");
            return (address(0), false);
        }
        return (value, true);
    }

    /// @dev 读取并校验创世地址后铸道环；失败（未设/为 deployer）则跳过
    function _mintInitial(
        AetherRing ring,
        string memory envKey,
        IAetherRing.RingTier tier,
        address deployer
    ) internal {
        (address addr, bool ok) = _optionalAddr(envKey, deployer);
        if (!ok) return;
        // 检查地址是否已持道环（防止重复 mint 阻塞整个脚本）
        if (ring.getRingId(addr) != 0) {
            console2.log("  [skip] ", envKey, " already has ring");
            return;
        }
        ring.mintRing(addr, tier, "");
        console2.log("  [ok]   ", envKey, " minted tier", uint256(uint8(tier)));
    }

    /// @dev 读取并校验元老地址后实际调用 appointElder（C3 修复）
    function _appointElder(AetherRing ring, string memory envKey, address deployer) internal {
        (address addr, bool ok) = _optionalAddr(envKey, deployer);
        if (!ok) return;
        if (ring.isElderActive(addr)) {
            console2.log("  [skip] ", envKey, " already appointed elder");
            return;
        }
        // C3：实际调用 appointElder（不再仅 console.log）
        ring.appointElder(addr, "");
        console2.log("  [ok]   ", envKey, " appointed as elder");
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // M12：必需环境变量校验
        address ringAddr = _requireEnv("RING");
        address govAddr = _requireEnv("GOV");
        address electionAddr = _requireEnv("ELECTION");
        address donationAddr = _requireEnv("DONATION");
        address safeAddr = _requireEnv("SAFE");

        AetherRing ring = AetherRing(ringAddr);
        AetherGovernance gov = AetherGovernance(govAddr);
        AetherElection election = AetherElection(electionAddr);
        // donation 已在 Deploy.s.sol 中完成配置，Genesis 不再操作
        donationAddr;

        vm.startBroadcast(deployerPrivateKey);

        // ── 1. 铸造三院高层（deployer 持有 MINTER_ROLE） ──
        console2.log("=== Minting high-tier rings ===");
        // 议长 tier 3（2 人）
        _mintInitial(ring, "PAR_SPEAKER_1", IAetherRing.RingTier.PARLIAMENT_SPEAKER, deployer);
        _mintInitial(ring, "PAR_SPEAKER_2", IAetherRing.RingTier.PARLIAMENT_SPEAKER, deployer);

        // 执政 tier 6（2 人）
        _mintInitial(ring, "FED_MINISTER_1", IAetherRing.RingTier.FEDERATION_MINISTER, deployer);
        _mintInitial(ring, "FED_MINISTER_2", IAetherRing.RingTier.FEDERATION_MINISTER, deployer);

        // 首席 tier 9（2 人）
        _mintInitial(ring, "TRIB_CHIEF_1", IAetherRing.RingTier.TRIBUNAL_CHIEF, deployer);
        _mintInitial(ring, "TRIB_CHIEF_2", IAetherRing.RingTier.TRIBUNAL_CHIEF, deployer);

        // ── 2. 铸造理事会 ──
        console2.log("=== Minting council rings ===");
        // 理事 tier 10（2 人）
        _mintInitial(ring, "COUNCIL_1", IAetherRing.RingTier.COUNCIL_MEMBER, deployer);
        _mintInitial(ring, "COUNCIL_2", IAetherRing.RingTier.COUNCIL_MEMBER, deployer);

        // 常务理事 tier 11（2 人）
        _mintInitial(ring, "COUNCIL_SENIOR_1", IAetherRing.RingTier.COUNCIL_SENIOR, deployer);
        _mintInitial(ring, "COUNCIL_SENIOR_2", IAetherRing.RingTier.COUNCIL_SENIOR, deployer);

        // 理事长 tier 12（1 人）
        _mintInitial(ring, "COUNCIL_CHAIR", IAetherRing.RingTier.COUNCIL_CHAIR, deployer);

        // ── 3. H6：铸造初始公民（tier 14，10 人） ──
        // 正式环境公民由捐款产生，此处仅用于初始测试网（quorum 分母需要 ≥1）
        console2.log("=== Minting 10 initial citizens (H6) ===");
        for (uint256 i = 1; i <= 10; i++) {
            string memory envKey = _citizenEnvKey(i);
            _mintInitial(ring, envKey, IAetherRing.RingTier.CITIZEN, deployer);
        }

        // ── 4. C3：实际任命 5 位元老 ──
        // 注：appointElder 仅需 ADMIN_ROLE（deployer 持有），可由 deployer 直接广播
        //     retireToEmeritus / resumeFromEmeritus 才需要 msg.sender == Safe
        console2.log("=== Appointing 5 elders (C3) ===");
        _appointElder(ring, "ELDER_1", deployer);
        _appointElder(ring, "ELDER_2", deployer);
        _appointElder(ring, "ELDER_3", deployer);
        _appointElder(ring, "ELDER_4", deployer);
        _appointElder(ring, "ELDER_5", deployer);

        // ── 5. 授予理事长 election.COUNCIL_CHAIR_ROLE ──
        // 该角色用于 approveCandidate / rejectCandidate / appointToVacancy
        (address councilChair, bool chairOk) = _optionalAddr("COUNCIL_CHAIR", deployer);
        if (chairOk) {
            election.grantCouncilChairRole(councilChair);
            console2.log("Council chair role granted to:", councilChair);
        }

        // ── 6. H7：PROPOSER_ROLE 仅授予三院成员（tier 1-9） ──
        // 注意：createProposal 受 onlyChamberMember 修饰器限制（tier 1-9），
        //       理事长（tier 12）即使有角色也会 revert，故不再授予
        console2.log("=== Granting PROPOSER_ROLE to chamber members (H7) ===");
        _grantProposerIfSet(gov, "PAR_SPEAKER_1", deployer);
        _grantProposerIfSet(gov, "PAR_SPEAKER_2", deployer);
        _grantProposerIfSet(gov, "FED_MINISTER_1", deployer);
        _grantProposerIfSet(gov, "FED_MINISTER_2", deployer);
        _grantProposerIfSet(gov, "TRIB_CHIEF_1", deployer);
        _grantProposerIfSet(gov, "TRIB_CHIEF_2", deployer);
        // H7：不再授予理事长 PROPOSER_ROLE（原代码最后一行已删除）

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Genesis Summary ===");
        console2.log("High-tier minted: 6 (2 speakers + 2 ministers + 2 chiefs)");
        console2.log("Council minted:   5 (2 members + 2 seniors + 1 chair)");
        console2.log("Citizens minted:  up to 10 (H6: read from CITIZEN_1..CITIZEN_10)");
        console2.log("Elders appointed: up to 5 (C3: actual appointElder calls)");
        console2.log("PROPOSER_ROLE:    granted to chamber members only (H7)");
        console2.log("COUNCIL_CHAIR:    granted on election contract");
        console2.log("");
        console2.log("=== Post-Genesis manual steps ===");
        console2.log("1. deployer renounces DEFAULT_ADMIN_ROLE on all 4 contracts:");
        console2.log("   ring.renounceRole(ring.DEFAULT_ADMIN_ROLE(), <deployer>)");
        console2.log("   gov.renounceRole(gov.DEFAULT_ADMIN_ROLE(), <deployer>)");
        console2.log("   election.renounceRole(election.DEFAULT_ADMIN_ROLE(), <deployer>)");
        console2.log("   donation.renounceRole(donation.DEFAULT_ADMIN_ROLE(), <deployer>)");
        console2.log("2. Verify Safe multisig now holds DEFAULT_ADMIN_ROLE on all 4 contracts");
        console2.log("3. Update frontend src/lib/contracts/config.ts with deployed addresses");
    }

    /// @dev 生成 CITIZEN_<i> 环境变量名（H-10: 修复 i=10 时生成 "CITIZEN_:" 的 bug）
    function _citizenEnvKey(uint256 i) internal pure returns (string memory) {
        // i ∈ [1, 10]，支持多位数
        if (i < 10) {
            bytes1 digit = bytes1(uint8(0x30 + i));
            return string(abi.encodePacked("CITIZEN_", digit));
        }
        // i >= 10: 拆分十位和个位
        bytes1 tens = bytes1(uint8(0x30 + i / 10));
        bytes1 ones = bytes1(uint8(0x30 + i % 10));
        return string(abi.encodePacked("CITIZEN_", tens, ones));
    }

    /// @dev 读取地址并授予 PROPOSER_ROLE（仅当环境变量已设置且 ≠ deployer）
    function _grantProposerIfSet(AetherGovernance gov, string memory envKey, address deployer) internal {
        (address addr, bool ok) = _optionalAddr(envKey, deployer);
        if (!ok) return;
        if (gov.hasRole(gov.PROPOSER_ROLE(), addr)) {
            console2.log("  [skip] ", envKey, " already PROPOSER");
            return;
        }
        gov.grantRole(gov.PROPOSER_ROLE(), addr);
        console2.log("  [ok]   ", envKey, " granted PROPOSER_ROLE");
    }
}
