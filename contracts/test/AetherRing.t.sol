// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AetherRing} from "../src/AetherRing.sol";
import {IAetherRing} from "../src/interfaces/IAetherRing.sol";
import {ISafe} from "../src/interfaces/ISafe.sol";

/**
 * @title AetherRing Test v3
 * @dev 覆盖 14 级权级、席位上限、任期、退休转元老、任命元老、公民放弃、休眠机制
 *
 * 测试矩阵（25 项，对应 V3_DEV_STEPS.md 步骤 1.10）：
 *   T1.1  14 个 tier 各自任期正确
 *   T1.2  基层 60 席上限
 *   T1.3  中层 12 席上限
 *   T1.4  理事会 12/4/2 席位
 *   T1.5  任命元老 9 人上限
 *   T1.6  公民/退休元老无上限
 *   T1.7  tier 3/6/9 退休转 13
 *   T1.8  理事长 12 退休转 13
 *   T1.9  低 tier 退休 revert
 *   T1.10 退休后 isRetiredElder=true
 *   T1.11 公民放弃
 *   T1.12 非公民放弃 revert
 *   T1.13 30 天冷却期
 *   T1.14 2 年后休眠
 *   T1.15 2 年内不触发休眠
 *   T1.16 markVoteActivity 更新活动时间
 *   T1.17 getActiveCitizens 排除休眠
 *   T1.18 新人任命元老
 *   T1.19 已有公民任命升级
 *   T1.20 退休元老重新任命
 *   T1.21 第 10 个任命 revert
 *   T1.22 isElderActive 仅任命元老
 *   T1.23 多签权限校验
 *   T1.24 updateTier 重置任期
 *   T1.25 任期到期标记
 */
contract AetherRingTest is Test {
    AetherRing ring;
    address admin = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA401);

    // Safe 多签 mock
    MockSafe safe;

    function setUp() public {
        ring = new AetherRing();
        safe = new MockSafe();
        ring.setSafeWallet(address(safe));
        // 授予 Safe ADMIN_ROLE：appointElder 改回 onlyRole(ADMIN_ROLE)，
        // 测试中所有 vm.prank(address(safe)) 调用 appointElder 需此权限
        ring.grantRole(ring.ADMIN_ROLE(), address(safe));
        // 授予 GOVERNANCE_ROLE 用于 markVoteActivity 测试
        // 注：Solidity 0.8.26 不支持 ContractName.ConstantName 跨合约访问 public constant，
        //     必须通过实例 getter（ring.GOVERNANCE_ROLE()）获取
        ring.grantRole(ring.GOVERNANCE_ROLE(), address(this));
        ring.grantRole(ring.ELECTION_ROLE(), address(this));
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.1 铸造 — 14 个 tier 各自任期正确
    // ═══════════════════════════════════════════════════════════

    function test_MintRing_AllTiers_TermCorrect() public {
        // tier 1 议员（基层）：365 days
        ring.mintRing(alice, IAetherRing.RingTier.PARLIAMENT_MEMBER, "");
        AetherRing.RingInfo memory info = ring.getRingInfo(1);
        assertEq(uint8(info.tier), 1);
        assertEq(info.termEndAt, info.mintedAt + 365 days);
        assertTrue(info.isActive);
        assertFalse(info.isDormant);
        assertFalse(info.isRetiredElder);
        assertFalse(info.isAppointedElder);
        assertEq(info.lastActivityAt, info.mintedAt);

        // tier 2 参议员（中层）：730 days
        ring.mintRing(bob, IAetherRing.RingTier.PARLIAMENT_SENIOR, "");
        info = ring.getRingInfo(2);
        assertEq(uint8(info.tier), 2);
        assertEq(info.termEndAt, info.mintedAt + 730 days);

        // tier 3 议长（高层）：终生
        ring.mintRing(carol, IAetherRing.RingTier.PARLIAMENT_SPEAKER, "");
        info = ring.getRingInfo(3);
        assertEq(uint8(info.tier), 3);
        assertEq(info.termEndAt, type(uint64).max);

        // tier 4 委员（基层）：365 days
        address d4 = address(0xD4);
        ring.mintRing(d4, IAetherRing.RingTier.FEDERATION_MEMBER, "");
        info = ring.getRingInfo(4);
        assertEq(uint8(info.tier), 4);
        assertEq(info.termEndAt, info.mintedAt + 365 days);

        // tier 5 委员长（中层）：730 days
        address d5 = address(0xD5);
        ring.mintRing(d5, IAetherRing.RingTier.FEDERATION_SENIOR, "");
        info = ring.getRingInfo(5);
        assertEq(uint8(info.tier), 5);
        assertEq(info.termEndAt, info.mintedAt + 730 days);

        // tier 6 执政（高层）：终生
        address d6 = address(0xD6);
        ring.mintRing(d6, IAetherRing.RingTier.FEDERATION_MINISTER, "");
        info = ring.getRingInfo(6);
        assertEq(uint8(info.tier), 6);
        assertEq(info.termEndAt, type(uint64).max);

        // tier 7 法官（基层）：365 days
        address d7 = address(0xD7);
        ring.mintRing(d7, IAetherRing.RingTier.TRIBUNAL_JUDGE, "");
        info = ring.getRingInfo(7);
        assertEq(uint8(info.tier), 7);
        assertEq(info.termEndAt, info.mintedAt + 365 days);

        // tier 8 大法官（中层）：730 days
        address d8 = address(0xD8);
        ring.mintRing(d8, IAetherRing.RingTier.TRIBUNAL_SENIOR, "");
        info = ring.getRingInfo(8);
        assertEq(uint8(info.tier), 8);
        assertEq(info.termEndAt, info.mintedAt + 730 days);

        // tier 9 首席（高层）：终生
        address d9 = address(0xD9);
        ring.mintRing(d9, IAetherRing.RingTier.TRIBUNAL_CHIEF, "");
        info = ring.getRingInfo(9);
        assertEq(uint8(info.tier), 9);
        assertEq(info.termEndAt, type(uint64).max);

        // tier 10 理事（理事会基层）：365 days
        address d10 = address(0xD10);
        ring.mintRing(d10, IAetherRing.RingTier.COUNCIL_MEMBER, "");
        info = ring.getRingInfo(10);
        assertEq(uint8(info.tier), 10);
        assertEq(info.termEndAt, info.mintedAt + 365 days);

        // tier 11 常务理事（理事会中层）：365 days
        address d11 = address(0xD11);
        ring.mintRing(d11, IAetherRing.RingTier.COUNCIL_SENIOR, "");
        info = ring.getRingInfo(11);
        assertEq(uint8(info.tier), 11);
        assertEq(info.termEndAt, info.mintedAt + 365 days);

        // tier 12 理事长（理事会高层）：4 年
        address d12 = address(0xD12);
        ring.mintRing(d12, IAetherRing.RingTier.COUNCIL_CHAIR, "");
        info = ring.getRingInfo(12);
        assertEq(uint8(info.tier), 12);
        assertEq(info.termEndAt, info.mintedAt + 4 * 365 days);

        // tier 14 公民：无任期（type(uint64).max）
        address d14 = address(0xD14);
        ring.mintRing(d14, IAetherRing.RingTier.CITIZEN, "");
        info = ring.getRingInfo(13);
        assertEq(uint8(info.tier), 14);
        assertEq(info.termEndAt, type(uint64).max);

        // tier 13 ELDER 不能直接 mint，必须走 appointElder
        vm.expectRevert(AetherRing.InvalidTier.selector);
        ring.mintRing(address(0xDEAD), IAetherRing.RingTier.ELDER, "");
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.2 席位上限 — 基层 60
    // ═══════════════════════════════════════════════════════════

    function test_SeatLimit_GrassrootsAt60() public {
        // 铸 60 个议员成功
        for (uint256 i = 0; i < 60; i++) {
            address m = address(uint160(0x1000 + i));
            ring.mintRing(m, IAetherRing.RingTier.PARLIAMENT_MEMBER, "");
        }
        assertEq(ring.getTierCount(IAetherRing.RingTier.PARLIAMENT_MEMBER), 60);

        // 第 61 个 revert
        vm.expectRevert(
            abi.encodeWithSelector(
                AetherRing.SeatLimitExceeded.selector,
                IAetherRing.RingTier.PARLIAMENT_MEMBER,
                60,
                60
            )
        );
        ring.mintRing(alice, IAetherRing.RingTier.PARLIAMENT_MEMBER, "");
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.3 席位上限 — 中层 12
    // ═══════════════════════════════════════════════════════════

    function test_SeatLimit_MidAt12() public {
        for (uint256 i = 0; i < 12; i++) {
            address m = address(uint160(0x2000 + i));
            ring.mintRing(m, IAetherRing.RingTier.PARLIAMENT_SENIOR, "");
        }
        assertEq(ring.getTierCount(IAetherRing.RingTier.PARLIAMENT_SENIOR), 12);

        vm.expectRevert(
            abi.encodeWithSelector(
                AetherRing.SeatLimitExceeded.selector,
                IAetherRing.RingTier.PARLIAMENT_SENIOR,
                12,
                12
            )
        );
        ring.mintRing(alice, IAetherRing.RingTier.PARLIAMENT_SENIOR, "");
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.4 席位上限 — 理事会 12/4/2
    // ═══════════════════════════════════════════════════════════

    function test_SeatLimit_CouncilAt12_4_2() public {
        // 理事 12
        for (uint256 i = 0; i < 12; i++) {
            ring.mintRing(address(uint160(0x3000 + i)), IAetherRing.RingTier.COUNCIL_MEMBER, "");
        }
        vm.expectRevert(
            abi.encodeWithSelector(
                AetherRing.SeatLimitExceeded.selector, IAetherRing.RingTier.COUNCIL_MEMBER, 12, 12
            )
        );
        ring.mintRing(alice, IAetherRing.RingTier.COUNCIL_MEMBER, "");

        // 常务理事 4
        for (uint256 i = 0; i < 4; i++) {
            ring.mintRing(address(uint160(0x4000 + i)), IAetherRing.RingTier.COUNCIL_SENIOR, "");
        }
        vm.expectRevert(
            abi.encodeWithSelector(
                AetherRing.SeatLimitExceeded.selector, IAetherRing.RingTier.COUNCIL_SENIOR, 4, 4
            )
        );
        ring.mintRing(bob, IAetherRing.RingTier.COUNCIL_SENIOR, "");

        // 理事长 2
        ring.mintRing(carol, IAetherRing.RingTier.COUNCIL_CHAIR, "");
        ring.mintRing(address(0x5001), IAetherRing.RingTier.COUNCIL_CHAIR, "");
        vm.expectRevert(
            abi.encodeWithSelector(
                AetherRing.SeatLimitExceeded.selector, IAetherRing.RingTier.COUNCIL_CHAIR, 2, 2
            )
        );
        ring.mintRing(address(0x5002), IAetherRing.RingTier.COUNCIL_CHAIR, "");
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.5 席位上限 — 任命元老 9 人
    // ═══════════════════════════════════════════════════════════

    function test_SeatLimit_AppointedElderAt9() public {
        // 任命 9 个元老
        for (uint256 i = 0; i < 9; i++) {
            address candidate = address(uint160(0x6000 + i));
            vm.prank(address(safe));
            ring.appointElder(candidate, "");
        }
        assertEq(ring.getAppointedElderCount(), 9);

        // 第 10 个 revert
        vm.prank(address(safe));
        vm.expectRevert(
            abi.encodeWithSelector(AetherRing.AppointedElderLimitReached.selector, 9, 9)
        );
        ring.appointElder(address(0x6009), "");
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.6 公民/退休元老无上限
    // ═══════════════════════════════════════════════════════════

    function test_SeatLimit_CitizenAndElder_NoLimit() public {
        // 公民无上限（铸 200 个）
        for (uint256 i = 0; i < 200; i++) {
            ring.mintRing(address(uint160(0x7000 + i)), IAetherRing.RingTier.CITIZEN, "");
        }
        assertEq(ring.getTotalCitizens(), 200);

        // 退休元老无上限（通过 retireToEmeritus 转换）
        // 先铸 3 个高层，退休后全部变 ELDER（退休元老不计入 appointedElderCount）
        ring.mintRing(alice, IAetherRing.RingTier.PARLIAMENT_SPEAKER, "");
        ring.mintRing(bob, IAetherRing.RingTier.FEDERATION_MINISTER, "");
        ring.mintRing(carol, IAetherRing.RingTier.TRIBUNAL_CHIEF, "");

        vm.startPrank(address(safe));
        ring.retireToEmeritus(201);
        ring.retireToEmeritus(202);
        ring.retireToEmeritus(203);
        vm.stopPrank();

        // 3 个退休元老，appointedElderCount 仍为 0
        assertEq(ring.getAppointedElderCount(), 0);
        assertTrue(ring.isRetiredElder(alice));
        assertTrue(ring.isRetiredElder(bob));
        assertTrue(ring.isRetiredElder(carol));
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.7 退休转元老 — tier 3/6/9 退休转 13
    // ═══════════════════════════════════════════════════════════

    function test_RetireToEmeritus_HighTier_Success() public {
        // tier 3 议长退休
        ring.mintRing(alice, IAetherRing.RingTier.PARLIAMENT_SPEAKER, "");
        assertTrue(ring.isBearer(alice));

        vm.prank(address(safe));
        ring.retireToEmeritus(1);

        AetherRing.RingInfo memory info = ring.getRingInfo(1);
        assertEq(uint8(info.tier), uint8(IAetherRing.RingTier.ELDER)); // tier=13
        assertFalse(info.isActive); // 退休元老无投票权
        assertTrue(info.isEmeritus);
        assertTrue(info.isRetiredElder);
        assertFalse(info.isAppointedElder);
        assertEq(info.termEndAt, type(uint64).max); // 元老终生

        // getTier 返回 0（因 isActive=false / isEmeritus=true）
        assertEq(ring.getTier(alice), 0);
        assertFalse(ring.isBearer(alice));

        // tier 6 执政退休
        ring.mintRing(bob, IAetherRing.RingTier.FEDERATION_MINISTER, "");
        vm.prank(address(safe));
        ring.retireToEmeritus(2);
        assertEq(uint8(ring.getRingInfo(2).tier), uint8(IAetherRing.RingTier.ELDER));

        // tier 9 首席退休
        ring.mintRing(carol, IAetherRing.RingTier.TRIBUNAL_CHIEF, "");
        vm.prank(address(safe));
        ring.retireToEmeritus(3);
        assertEq(uint8(ring.getRingInfo(3).tier), uint8(IAetherRing.RingTier.ELDER));

        // 原 tier 席位计数减 1
        assertEq(ring.getTierCount(IAetherRing.RingTier.PARLIAMENT_SPEAKER), 0);
        assertEq(ring.getTierCount(IAetherRing.RingTier.FEDERATION_MINISTER), 0);
        assertEq(ring.getTierCount(IAetherRing.RingTier.TRIBUNAL_CHIEF), 0);
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.8 退休转元老 — 理事长 12 退休转 13
    // ═══════════════════════════════════════════════════════════

    function test_RetireToEmeritus_CouncilChair_Success() public {
        ring.mintRing(alice, IAetherRing.RingTier.COUNCIL_CHAIR, "");
        assertTrue(ring.isBearer(alice));

        vm.prank(address(safe));
        ring.retireToEmeritus(1);

        AetherRing.RingInfo memory info = ring.getRingInfo(1);
        assertEq(uint8(info.tier), uint8(IAetherRing.RingTier.ELDER));
        assertTrue(info.isRetiredElder);
        assertFalse(info.isAppointedElder);
        assertEq(ring.getTierCount(IAetherRing.RingTier.COUNCIL_CHAIR), 0);
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.9 退休转元老 — 低 tier 退休 revert
    // ═══════════════════════════════════════════════════════════

    function test_RetireToEmeritus_LowTier_Revert() public {
        // tier 1 议员（基层）不能退休
        ring.mintRing(alice, IAetherRing.RingTier.PARLIAMENT_MEMBER, "");
        vm.prank(address(safe));
        vm.expectRevert(AetherRing.InvalidTier.selector);
        ring.retireToEmeritus(1);

        // tier 2 参议员（中层）不能退休
        ring.mintRing(bob, IAetherRing.RingTier.PARLIAMENT_SENIOR, "");
        vm.prank(address(safe));
        vm.expectRevert(AetherRing.InvalidTier.selector);
        ring.retireToEmeritus(2);

        // tier 10 理事不能退休
        ring.mintRing(carol, IAetherRing.RingTier.COUNCIL_MEMBER, "");
        vm.prank(address(safe));
        vm.expectRevert(AetherRing.InvalidTier.selector);
        ring.retireToEmeritus(3);

        // tier 14 公民不能退休
        ring.mintRing(address(0xE14), IAetherRing.RingTier.CITIZEN, "");
        vm.prank(address(safe));
        vm.expectRevert(AetherRing.InvalidTier.selector);
        ring.retireToEmeritus(4);
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.10 退休后 isRetiredElder=true
    // ═══════════════════════════════════════════════════════════

    function test_RetireToEmeritus_SetsIsRetiredElder() public {
        ring.mintRing(alice, IAetherRing.RingTier.PARLIAMENT_SPEAKER, "");

        vm.prank(address(safe));
        ring.retireToEmeritus(1);

        // isElderActive 返回 false（退休元老无治理权）
        assertFalse(ring.isElderActive(alice));
        // isRetiredElder 返回 true
        assertTrue(ring.isRetiredElder(alice));
        // isEmeritus 返回 true
        assertTrue(ring.isEmeritus(alice));
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.11 公民放弃身份
    // ═══════════════════════════════════════════════════════════

    function test_RenounceCitizenship_Success() public {
        ring.mintRing(alice, IAetherRing.RingTier.CITIZEN, "");
        assertEq(ring.getTotalCitizens(), 1);
        assertTrue(ring.isBearer(alice));

        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit AetherRing.CitizenRenounced(1, alice);
        ring.renounceCitizenship();

        // 放弃后：道环已 burn，walletToRingId=0
        assertEq(ring.getRingId(alice), 0);
        assertFalse(ring.isBearer(alice));
        assertEq(ring.getTotalCitizens(), 0);
        // lastRenouncedAt 记录时间戳
        assertGt(ring.lastRenouncedAt(alice), 0);
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.12 非公民放弃 revert
    // ═══════════════════════════════════════════════════════════

    function test_RenounceCitizenship_NonCitizen_Revert() public {
        // tier 1 议员不能放弃公民身份
        ring.mintRing(alice, IAetherRing.RingTier.PARLIAMENT_MEMBER, "");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AetherRing.NotCitizen.selector, 1));
        ring.renounceCitizenship();

        // 无道环者调用 revert
        vm.prank(bob);
        vm.expectRevert(AetherRing.NotRingBearer.selector);
        ring.renounceCitizenship();
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.13 公民放弃 30 天冷却期
    // ═══════════════════════════════════════════════════════════

    function test_RenounceCitizenship_Cooldown30Days() public {
        ring.mintRing(alice, IAetherRing.RingTier.CITIZEN, "");

        // 放弃前 canReacquire=true
        assertTrue(ring.canReacquireCitizenship(alice));

        vm.prank(alice);
        ring.renounceCitizenship();

        // 放弃后立即检查：canReacquire=false（30 天冷却期内）
        assertFalse(ring.canReacquireCitizenship(alice));

        // 29 天后仍 false
        vm.warp(block.timestamp + 29 days);
        assertFalse(ring.canReacquireCitizenship(alice));

        // 30 天后 true
        vm.warp(block.timestamp + 1 days);
        assertTrue(ring.canReacquireCitizenship(alice));
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.14 2 年后休眠
    // ═══════════════════════════════════════════════════════════

    function test_MarkDormantIfDue_After2Years() public {
        ring.mintRing(alice, IAetherRing.RingTier.CITIZEN, "");
        assertFalse(ring.isDormant(alice));

        // 推进 2 年 + 1 秒
        vm.warp(block.timestamp + 2 * 365 days + 1);

        vm.expectEmit(true, true, false, false);
        emit AetherRing.CitizenDormant(1, alice);
        ring.markDormantIfDue(1);

        // 休眠后：isDormant=true，isBearer=false（投票权暂停）
        assertTrue(ring.isDormant(alice));
        assertFalse(ring.isBearer(alice));
        assertEq(ring.getTier(alice), 0);
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.15 2 年内不触发休眠
    // ═══════════════════════════════════════════════════════════

    function test_MarkDormantIfDue_Before2Years_Revert() public {
        ring.mintRing(alice, IAetherRing.RingTier.CITIZEN, "");

        // 1 年后：不足 2 年，revert
        vm.warp(block.timestamp + 365 days);
        vm.expectRevert(abi.encodeWithSelector(AetherRing.DormancyNotDue.selector, 1));
        ring.markDormantIfDue(1);

        // 仍然活跃
        assertFalse(ring.isDormant(alice));
        assertTrue(ring.isBearer(alice));
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.16 markVoteActivity 更新活动时间
    // ═══════════════════════════════════════════════════════════

    function test_MarkVoteActivity_UpdatesLastActivityAt() public {
        ring.mintRing(alice, IAetherRing.RingTier.CITIZEN, "");
        uint64 originalActivity = ring.getRingInfo(1).lastActivityAt;

        // 推进 100 天
        vm.warp(block.timestamp + 100 days);

        // markVoteActivity 更新活动时间（admin 有 GOVERNANCE_ROLE）
        ring.markVoteActivity(alice);

        AetherRing.RingInfo memory info = ring.getRingInfo(1);
        assertGt(info.lastActivityAt, originalActivity);
        assertEq(info.lastActivityAt, uint64(block.timestamp));

        // 非授权合约调用 revert
        vm.prank(bob);
        vm.expectRevert(AetherRing.Unauthorized.selector);
        ring.markVoteActivity(alice);
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.17 getActiveCitizens 排除休眠
    // ═══════════════════════════════════════════════════════════

    function test_GetActiveCitizens_ExcludesDormant() public {
        // 铸 5 个公民
        for (uint256 i = 0; i < 5; i++) {
            ring.mintRing(address(uint160(0x8000 + i)), IAetherRing.RingTier.CITIZEN, "");
        }
        assertEq(ring.getTotalCitizens(), 5);
        assertEq(ring.getActiveCitizens(), 5);

        // 推进 2 年+1 秒，标记 2 个休眠
        vm.warp(block.timestamp + 2 * 365 days + 1);
        ring.markDormantIfDue(1);
        ring.markDormantIfDue(2);

        // getActiveCitizens = 5 - 2 = 3
        assertEq(ring.getActiveCitizens(), 3);
        assertEq(ring.getTotalCitizens(), 5); // 含休眠

        // 已休眠的再次标记 revert
        vm.expectRevert(abi.encodeWithSelector(AetherRing.AlreadyDormant.selector, 1));
        ring.markDormantIfDue(1);
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.18 新人任命元老
    // ═══════════════════════════════════════════════════════════

    function test_AppointElder_NewCandidate() public {
        // alice 无道环，直接任命为元老
        assertEq(ring.getRingId(alice), 0);

        vm.prank(address(safe));
        vm.expectEmit(true, true, false, false);
        emit AetherRing.ElderAppointed(1, alice);
        ring.appointElder(alice, "ipfs://elder");

        AetherRing.RingInfo memory info = ring.getRingInfo(1);
        assertEq(uint8(info.tier), uint8(IAetherRing.RingTier.ELDER));
        assertTrue(info.isAppointedElder);
        assertFalse(info.isRetiredElder);
        assertTrue(info.isActive); // 任命元老有治理权
        assertEq(info.termEndAt, type(uint64).max);
        assertEq(ring.getAppointedElderCount(), 1);
        assertTrue(ring.isElderActive(alice));
        assertTrue(ring.isBearer(alice)); // 任命元老算有效持有人
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.19 已有公民任命升级
    // ═══════════════════════════════════════════════════════════

    function test_AppointElder_ExistingCitizen() public {
        // alice 已是公民（tier 14）
        ring.mintRing(alice, IAetherRing.RingTier.CITIZEN, "");
        assertEq(ring.getTotalCitizens(), 1);

        // 任命为元老
        vm.prank(address(safe));
        ring.appointElder(alice, "");

        AetherRing.RingInfo memory info = ring.getRingInfo(1);
        assertEq(uint8(info.tier), uint8(IAetherRing.RingTier.ELDER));
        assertTrue(info.isAppointedElder);
        assertTrue(info.isActive);
        // 公民计数 -1（原 tier 14 席位释放）
        assertEq(ring.getTotalCitizens(), 0);
        assertEq(ring.getAppointedElderCount(), 1);
        assertTrue(ring.isElderActive(alice));
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.20 退休元老重新任命
    // ═══════════════════════════════════════════════════════════

    function test_AppointElder_RetiredElder_Reactivate() public {
        // alice 是议长，退休为退休元老
        ring.mintRing(alice, IAetherRing.RingTier.PARLIAMENT_SPEAKER, "");
        vm.prank(address(safe));
        ring.retireToEmeritus(1);

        assertTrue(ring.isRetiredElder(alice));
        assertFalse(ring.isElderActive(alice));
        assertEq(ring.getAppointedElderCount(), 0);

        // 重新任命为任命元老
        vm.prank(address(safe));
        ring.appointElder(alice, "");

        AetherRing.RingInfo memory info = ring.getRingInfo(1);
        assertTrue(info.isAppointedElder);
        assertFalse(info.isRetiredElder); // 退休标记清除
        assertTrue(info.isActive); // 恢复治理权
        assertEq(ring.getAppointedElderCount(), 1);
        assertTrue(ring.isElderActive(alice));
        assertFalse(ring.isRetiredElder(alice));
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.21 第 10 个任命 revert
    // ═══════════════════════════════════════════════════════════

    function test_AppointElder_Limit9_Revert() public {
        // 任命 9 个
        for (uint256 i = 0; i < 9; i++) {
            vm.prank(address(safe));
            ring.appointElder(address(uint160(0x9000 + i)), "");
        }
        assertEq(ring.getAppointedElderCount(), 9);

        // 第 10 个 revert
        vm.prank(address(safe));
        vm.expectRevert(
            abi.encodeWithSelector(AetherRing.AppointedElderLimitReached.selector, 9, 9)
        );
        ring.appointElder(address(0x9009), "");
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.22 isElderActive 仅任命元老
    // ═══════════════════════════════════════════════════════════

    function test_IsElderActive_OnlyAppointed() public {
        // 任命元老：isElderActive=true
        vm.prank(address(safe));
        ring.appointElder(alice, "");
        assertTrue(ring.isElderActive(alice));

        // 退休元老：isElderActive=false
        ring.mintRing(bob, IAetherRing.RingTier.FEDERATION_MINISTER, "");
        vm.prank(address(safe));
        ring.retireToEmeritus(2);
        assertFalse(ring.isElderActive(bob));
        assertTrue(ring.isRetiredElder(bob));

        // 普通公民：isElderActive=false
        ring.mintRing(carol, IAetherRing.RingTier.CITIZEN, "");
        assertFalse(ring.isElderActive(carol));

        // 无道环者：isElderActive=false
        assertFalse(ring.isElderActive(address(0xDEAD)));
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.23 多签权限校验
    // ═══════════════════════════════════════════════════════════

    function test_SafeWallet_OnlyMultisig_RetireAppoint() public {
        ring.mintRing(alice, IAetherRing.RingTier.PARLIAMENT_SPEAKER, "");

        // 非 Safe 调 retireToEmeritus → revert
        vm.expectRevert(abi.encodeWithSelector(AetherRing.NotSafeWallet.selector, bob));
        vm.prank(bob);
        ring.retireToEmeritus(1);

        // 无 ADMIN_ROLE 调 appointElder → revert（AccessControlUnauthorizedAccount）
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                bob,
                ring.ADMIN_ROLE()
            )
        );
        vm.prank(bob);
        ring.appointElder(carol, "");

        // Safe 调 retireToEmeritus 成功（retireToEmeritus 仍要求 Safe）
        vm.prank(address(safe));
        ring.retireToEmeritus(1);

        // ADMIN_ROLE（此处为 Safe，已在 setUp 授予）调 appointElder 成功
        vm.prank(address(safe));
        ring.appointElder(carol, "");
        assertTrue(ring.isElderActive(carol));
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.24 updateTier 重置任期
    // ═══════════════════════════════════════════════════════════

    function test_UpdateTier_ResetTerm_NewTerm() public {
        ring.mintRing(alice, IAetherRing.RingTier.PARLIAMENT_MEMBER, "");
        uint64 oldTermEnd = ring.getRingInfo(1).termEndAt;

        // 推进 100 天后升级到参议员（中层），重置任期
        vm.warp(block.timestamp + 100 days);
        ring.updateTier(1, IAetherRing.RingTier.PARLIAMENT_SENIOR, true);

        AetherRing.RingInfo memory info = ring.getRingInfo(1);
        assertEq(uint8(info.tier), 2);
        // 新任期 = 当前时间 + 730 days（中层）
        assertEq(info.termEndAt, uint64(block.timestamp + 730 days));
        assertEq(info.mintedAt, uint64(block.timestamp));
        assertEq(info.consecutiveTerms, 0);
        assertFalse(info.isExpired);
        assertGt(info.termEndAt, oldTermEnd);

        // 不重置任期时，termEndAt 不变
        uint64 termBefore = info.termEndAt;
        ring.updateTier(1, IAetherRing.RingTier.PARLIAMENT_MEMBER, false);
        info = ring.getRingInfo(1);
        assertEq(uint8(info.tier), 1);
        assertEq(info.termEndAt, termBefore); // 任期不变
    }

    // ═══════════════════════════════════════════════════════════
    //  T1.25 任期到期标记
    // ═══════════════════════════════════════════════════════════

    function test_MarkExpiredIfDue_AfterTermEnds() public {
        ring.mintRing(alice, IAetherRing.RingTier.PARLIAMENT_MEMBER, "");
        assertTrue(ring.isBearer(alice));
        assertFalse(ring.isExpired(1));

        // 推进到任期结束之后
        vm.warp(block.timestamp + 366 days);

        // isBearer 被动检查返回 false
        assertFalse(ring.isBearer(alice));
        assertEq(ring.getTier(alice), 0);

        // 主动标记过期
        vm.expectEmit(true, false, false, true);
        emit AetherRing.RingExpired(1, ring.getRingInfo(1).termEndAt);
        ring.markExpiredIfDue(1);

        AetherRing.RingInfo memory info = ring.getRingInfo(1);
        assertTrue(info.isExpired);

        // 重复标记 no-op（不 revert）
        ring.markExpiredIfDue(1);

        // 高层（终生任期）不会过期
        ring.mintRing(bob, IAetherRing.RingTier.PARLIAMENT_SPEAKER, "");
        vm.warp(block.timestamp + 100 * 365 days);
        assertFalse(ring.isExpired(2));
        ring.markExpiredIfDue(2);
        assertFalse(ring.getRingInfo(2).isExpired);
    }

    // ═══════════════════════════════════════════════════════════
    //  SBT 不可转让（补充测试）
    // ═══════════════════════════════════════════════════════════

    function test_SBT_TransferReverts() public {
        ring.mintRing(alice, IAetherRing.RingTier.CITIZEN, "");
        vm.startPrank(alice);
        vm.expectRevert(AetherRing.SoulboundNoTransfer.selector);
        ring.transferFrom(alice, bob, 1);
        vm.stopPrank();
    }

    function test_SBT_ApproveReverts() public {
        ring.mintRing(alice, IAetherRing.RingTier.CITIZEN, "");
        vm.startPrank(alice);
        vm.expectRevert(AetherRing.SoulboundNoApproval.selector);
        ring.approve(bob, 1);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════
    //  supportsInterface（补充测试）
    // ═══════════════════════════════════════════════════════════

    function test_SupportsInterface_IAetherRing() public view {
        assertTrue(ring.supportsInterface(type(IAetherRing).interfaceId));
        assertTrue(ring.supportsInterface(0x80ac58cd)); // ERC721
        assertTrue(ring.supportsInterface(0x7965db0b)); // AccessControl
    }
}

/**
 * @title MockSafe — Safe 多签 mock
 * @dev 仅用于测试：实现 ISafe 接口，所有调用都由测试 prank address(safe) 模拟
 */
contract MockSafe is ISafe {
    address[] private _owners;
    uint256 private _threshold;

    constructor() {
        _owners.push(msg.sender);
        _threshold = 1;
    }

    function isOwner(address owner) external view returns (bool) {
        for (uint256 i = 0; i < _owners.length; i++) {
            if (_owners[i] == owner) return true;
        }
        return false;
    }

    function getThreshold() external view returns (uint256) {
        return _threshold;
    }

    function getOwners() external view returns (address[] memory) {
        return _owners;
    }
}
