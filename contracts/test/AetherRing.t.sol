// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AetherRing} from "../src/AetherRing.sol";
import {IAetherRing} from "../src/interfaces/IAetherRing.sol";
import {ISafe} from "../src/interfaces/ISafe.sol";

/**
 * @title AetherRing Test v2
 * @dev 覆盖 SBT 不可转让、铸/撤/升降级、EMERITUS、席位上限、任期、Safe 多签
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
    }

    // ──────────── 铸造 ────────────

    function test_MintRing_Success() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_MEMBER, "ipfs://abc");

        assertEq(ring.getRingId(alice), 0);
        assertEq(ring.ownerOf(0), alice);
        assertTrue(ring.isBearer(alice));
        assertEq(ring.getTier(alice), 1);

        AetherRing.RingInfo memory info = ring.getRingInfo(0);
        assertEq(uint8(info.tier), 1);
        assertTrue(info.isActive);
        assertEq(info.covenantHash, "ipfs://abc");
        // 基层任期 365 天
        assertEq(info.termEndAt, info.mintedAt + 365 days);
        assertEq(info.consecutiveTerms, 0);
        assertFalse(info.isEmeritus);
        assertFalse(info.isExpired);
    }

    function test_MintRing_RevertWhen_NotMinter() public {
        vm.prank(bob);
        vm.expectRevert();
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_MEMBER, "");
    }

    function test_MintRing_RevertWhen_InvalidRecipient() public {
        vm.expectRevert(AetherRing.InvalidRecipient.selector);
        ring.mintRing(address(0), AetherRing.RingTier.PARLIAMENT_MEMBER, "");
    }

    function test_MintRing_RevertWhen_AlreadyHasRing() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_MEMBER, "");
        vm.expectRevert(abi.encodeWithSelector(AetherRing.AlreadyHasRing.selector, alice));
        ring.mintRing(alice, AetherRing.RingTier.SENATE_ELDER, "");
    }

    function test_MintRing_RevertWhen_InvalidTier() public {
        vm.expectRevert(AetherRing.InvalidTier.selector);
        ring.mintRing(alice, AetherRing.RingTier.NONE, "");
    }

    function test_MintRing_HighTier_TermIsMax() public {
        // 高层 = 终生任期
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_SPEAKER, "");
        AetherRing.RingInfo memory info = ring.getRingInfo(0);
        assertEq(info.termEndAt, type(uint64).max);
    }

    function test_MintRing_MidTier_TermIs730Days() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_SENIOR, "");
        AetherRing.RingInfo memory info = ring.getRingInfo(0);
        assertEq(info.termEndAt, info.mintedAt + 730 days);
    }

    // ──────────── SBT 不可转让 ────────────

    function test_TransferFrom_Reverts() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_MEMBER, "");
        vm.startPrank(alice);
        vm.expectRevert(AetherRing.SoulboundNoTransfer.selector);
        ring.transferFrom(alice, bob, 0);
        vm.stopPrank();
    }

    function test_SafeTransferFrom_Reverts() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_MEMBER, "");
        vm.startPrank(alice);
        vm.expectRevert(AetherRing.SoulboundNoTransfer.selector);
        ring.safeTransferFrom(alice, bob, 0);
        vm.stopPrank();
    }

    function test_Approve_Reverts() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_MEMBER, "");
        vm.startPrank(alice);
        vm.expectRevert(AetherRing.SoulboundNoApproval.selector);
        ring.approve(bob, 0);
        vm.stopPrank();
    }

    function test_SetApprovalForAll_Reverts() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_MEMBER, "");
        vm.startPrank(alice);
        vm.expectRevert(AetherRing.SoulboundNoApproval.selector);
        ring.setApprovalForAll(bob, true);
        vm.stopPrank();
    }

    // ──────────── 升降级（v2 新签名：resetTerm） ────────────

    function test_UpdateTier_Success_NoResetTerm() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_MEMBER, "");
        assertEq(ring.getTier(alice), 1);

        // 不重置任期：tier 变，任期不动
        uint64 oldTermEnd = ring.getRingInfo(0).termEndAt;
        ring.updateTier(0, AetherRing.RingTier.PARLIAMENT_SPEAKER, false);
        assertEq(ring.getTier(alice), 3);
        assertEq(ring.getRingInfo(0).termEndAt, oldTermEnd); // 任期不变

        // 降级
        ring.updateTier(0, AetherRing.RingTier.PARLIAMENT_MEMBER, false);
        assertEq(ring.getTier(alice), 1);
    }

    function test_UpdateTier_Success_ResetTerm() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_MEMBER, "");
        uint64 oldTermEnd = ring.getRingInfo(0).termEndAt;

        // 重置任期：mintedAt 和 termEndAt 都重置
        vm.warp(block.timestamp + 100 days);
        ring.updateTier(0, AetherRing.RingTier.PARLIAMENT_SENIOR, true);
        assertEq(ring.getTier(alice), 2);

        AetherRing.RingInfo memory info = ring.getRingInfo(0);
        // 新任期 = 当前时间 + 730 days（中层）
        assertEq(info.termEndAt, info.mintedAt + 730 days);
        assertEq(info.consecutiveTerms, 0);
        assertFalse(info.isExpired);
        assertGt(info.termEndAt, oldTermEnd);
    }

    function test_UpdateTier_AffectsGeneralMemberCount() public {
        ring.mintRing(alice, AetherRing.RingTier.GENERAL_MEMBER, "");
        assertEq(ring.getTotalMembers(), 1);

        ring.updateTier(0, AetherRing.RingTier.PARLIAMENT_MEMBER, false);
        assertEq(ring.getTotalMembers(), 0);

        ring.updateTier(0, AetherRing.RingTier.GENERAL_MEMBER, false);
        assertEq(ring.getTotalMembers(), 1);
    }

    function test_UpdateTier_RevertWhen_NotAdmin() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_MEMBER, "");
        vm.prank(bob);
        vm.expectRevert();
        ring.updateTier(0, AetherRing.RingTier.PARLIAMENT_SPEAKER, false);
    }

    function test_UpdateTier_RevertWhen_InvalidTier() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_MEMBER, "");
        vm.expectRevert(AetherRing.InvalidTier.selector);
        ring.updateTier(0, AetherRing.RingTier.NONE, false);
    }

    // ──────────── 席位上限 ────────────

    function test_SeatLimit_GrassrootsAt20() public {
        // 议员席位上限 20：铸 20 个成功，第 21 个 revert
        for (uint256 i = 0; i < 20; i++) {
            address m = address(uint160(0x1000 + i));
            ring.mintRing(m, AetherRing.RingTier.PARLIAMENT_MEMBER, "");
        }
        assertEq(ring.getTierCount(AetherRing.RingTier.PARLIAMENT_MEMBER), 20);

        vm.expectRevert(
            abi.encodeWithSelector(
                AetherRing.SeatLimitExceeded.selector,
                AetherRing.RingTier.PARLIAMENT_MEMBER,
                20,
                20
            )
        );
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_MEMBER, "");
    }

    function test_SeatLimit_HighAt2() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_SPEAKER, "");
        ring.mintRing(bob, AetherRing.RingTier.PARLIAMENT_SPEAKER, "");
        assertEq(ring.getTierCount(AetherRing.RingTier.PARLIAMENT_SPEAKER), 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                AetherRing.SeatLimitExceeded.selector,
                AetherRing.RingTier.PARLIAMENT_SPEAKER,
                2,
                2
            )
        );
        ring.mintRing(carol, AetherRing.RingTier.PARLIAMENT_SPEAKER, "");
    }

    function test_SeatLimit_GeneralMemberNoLimit() public {
        // 普通会员无上限
        for (uint256 i = 0; i < 100; i++) {
            address m = address(uint160(0x10000 + i));
            ring.mintRing(m, AetherRing.RingTier.GENERAL_MEMBER, "");
        }
        assertEq(ring.getTotalMembers(), 100);
    }

    function test_SeatLimit_UpdateTierRevertsWhenFull() public {
        ring.mintRing(alice, AetherRing.RingTier.GENERAL_MEMBER, "");
        ring.mintRing(bob, AetherRing.RingTier.GENERAL_MEMBER, "");

        // 议长席位已铸 2 个（max）
        ring.mintRing(address(0xA1), AetherRing.RingTier.PARLIAMENT_SPEAKER, "");
        ring.mintRing(address(0xA2), AetherRing.RingTier.PARLIAMENT_SPEAKER, "");

        // alice 想升到议长 → revert（席位满）
        vm.expectRevert(
            abi.encodeWithSelector(
                AetherRing.SeatLimitExceeded.selector,
                AetherRing.RingTier.PARLIAMENT_SPEAKER,
                2,
                2
            )
        );
        ring.updateTier(0, AetherRing.RingTier.PARLIAMENT_SPEAKER, false);
    }

    // ──────────── 任期 & 续任 ────────────

    function test_RenewTerm_Success() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_MEMBER, "");
        uint64 oldTermEnd = ring.getRingInfo(0).termEndAt;

        // 续任：再续 1 年
        vm.warp(block.timestamp + 30 days);
        uint64 newTermEnd = uint64(block.timestamp + 365 days);
        ring.renewTerm(0, newTermEnd);

        AetherRing.RingInfo memory info = ring.getRingInfo(0);
        assertEq(info.termEndAt, newTermEnd);
        assertEq(info.consecutiveTerms, 1);
        assertGt(info.termEndAt, oldTermEnd);
    }

    function test_RenewTerm_RevertWhen_TermLimitReached() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_MEMBER, "");
        ring.renewTerm(0, uint64(block.timestamp + 365 days));

        // 已经连任 1 次，无法再连任
        vm.expectRevert(abi.encodeWithSelector(AetherRing.TermLimitReached.selector, 1));
        ring.renewTerm(0, uint64(block.timestamp + 365 days));
    }

    function test_MarkExpiredIfDue_AfterTermEnds() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_MEMBER, "");
        assertTrue(ring.isBearer(alice));

        // 时间推进到任期结束之后
        vm.warp(block.timestamp + 366 days);

        // isBearer 应该返回 false（被动检查）
        assertFalse(ring.isBearer(alice));
        assertEq(ring.getTier(alice), 0);

        // 主动标记过期
        ring.markExpiredIfDue(0);
        AetherRing.RingInfo memory info = ring.getRingInfo(0);
        assertTrue(info.isExpired);
    }

    function test_MarkExpiredIfDue_NotYetExpired_NoOp() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_MEMBER, "");
        ring.markExpiredIfDue(0); // 未到期，no-op
        AetherRing.RingInfo memory info = ring.getRingInfo(0);
        assertFalse(info.isExpired);
    }

    function test_ExpiredBearer_CannotVote() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_MEMBER, "");
        vm.warp(block.timestamp + 400 days);
        // isBearer=false（因 termEndAt 已过），即使 isActive 仍为 true
        assertFalse(ring.isBearer(alice));
        assertEq(ring.getTier(alice), 0);
    }

    // ──────────── EMERITUS 退休 / 复出 ────────────

    function test_RetireToEmeritus_Success() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_SPEAKER, "");
        assertTrue(ring.isBearer(alice));

        // 只有 Safe 多签能调
        vm.prank(address(safe));
        ring.retireToEmeritus(0);

        // 退休后：isBearer=false（无投票权），但 isEmeritus=true
        assertFalse(ring.isBearer(alice));
        assertTrue(ring.isEmeritus(alice));
        assertEq(ring.getTier(alice), 0); // 退休后 getTier 返回 0

        AetherRing.RingInfo memory info = ring.getRingInfo(0);
        assertTrue(info.isEmeritus);
        assertFalse(info.isActive);
        // tier 编码仍保留（名誉身份）
        assertEq(uint8(info.tier), uint8(AetherRing.RingTier.PARLIAMENT_SPEAKER));
    }

    function test_RetireToEmeritus_RevertWhen_NotSafeWallet() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_SPEAKER, "");

        vm.prank(bob); // 非 Safe
        vm.expectRevert(abi.encodeWithSelector(AetherRing.NotSafeWallet.selector, bob));
        ring.retireToEmeritus(0);
    }

    function test_RetireToEmeritus_RevertWhen_NotHighTier() public {
        // 基层 / 中层不能退休（只有 tier 3/6/9）
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_MEMBER, "");
        vm.prank(address(safe));
        vm.expectRevert(AetherRing.InvalidTier.selector);
        ring.retireToEmeritus(0);
    }

    function test_RetireToEmeritus_RevertWhen_AlreadyEmeritus() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_SPEAKER, "");
        vm.prank(address(safe));
        ring.retireToEmeritus(0);

        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(AetherRing.AlreadyEmeritus.selector, 0));
        ring.retireToEmeritus(0);
    }

    function test_ResumeFromEmeritus_Success() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_SPEAKER, "");
        vm.prank(address(safe));
        ring.retireToEmeritus(0);
        assertFalse(ring.isBearer(alice));

        vm.prank(address(safe));
        ring.resumeFromEmeritus(0);

        // 复出后恢复投票权
        assertTrue(ring.isBearer(alice));
        assertFalse(ring.isEmeritus(alice));
        assertEq(ring.getTier(alice), 3);
    }

    function test_ResumeFromEmeritus_RevertWhen_NotEmeritus() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_SPEAKER, "");
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(AetherRing.NotEmeritus.selector, 0));
        ring.resumeFromEmeritus(0);
    }

    function test_RetireToEmeritus_RevertWhen_SafeWalletNotSet() public {
        AetherRing newRing = new AetherRing();
        newRing.mintRing(alice, AetherRing.RingTier.PARLIAMENT_SPEAKER, "");

        vm.prank(alice);
        vm.expectRevert(AetherRing.SafeWalletNotSet.selector);
        newRing.retireToEmeritus(0);
    }

    // ──────────── setSafeWallet ────────────

    function test_SetSafeWallet_Success() public {
        AetherRing newRing = new AetherRing();
        address oldSafe = address(0);
        MockSafe newSafe = new MockSafe();

        vm.expectEmit(true, true, false, false);
        emit AetherRing.SafeWalletUpdated(oldSafe, address(newSafe));
        newRing.setSafeWallet(address(newSafe));

        assertEq(address(newRing.safeWallet()), address(newSafe));
    }

    function test_SetSafeWallet_RevertWhen_NotAdmin() public {
        vm.prank(bob);
        vm.expectRevert();
        ring.setSafeWallet(address(0xBEEF));
    }

    function test_SetSafeWallet_RevertWhen_ZeroAddress() public {
        vm.expectRevert(AetherRing.InvalidRecipient.selector);
        ring.setSafeWallet(address(0));
    }

    // ──────────── 撤销 ────────────

    function test_RevokeRing_Success() public {
        ring.mintRing(alice, AetherRing.RingTier.GENERAL_MEMBER, "");
        assertEq(ring.getTotalMembers(), 1);

        ring.revokeRing(0);

        assertFalse(ring.isBearer(alice));
        assertEq(ring.getTier(alice), 0);
        assertEq(ring.getRingId(alice), 0);
        assertEq(ring.getTotalMembers(), 0);
    }

    function test_RevokeRing_RevertWhen_NotExists() public {
        vm.expectRevert(abi.encodeWithSelector(AetherRing.RingDoesNotExist.selector, 999));
        ring.revokeRing(999);
    }

    function test_RevokeRing_DecrementsTierCount() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_SPEAKER, "");
        assertEq(ring.getTierCount(AetherRing.RingTier.PARLIAMENT_SPEAKER), 1);

        ring.revokeRing(0);
        assertEq(ring.getTierCount(AetherRing.RingTier.PARLIAMENT_SPEAKER), 0);
    }

    // ──────────── getTotalMembers ────────────

    function test_GetTotalMembers_TracksMintRevoke() public {
        assertEq(ring.getTotalMembers(), 0);

        ring.mintRing(alice, AetherRing.RingTier.GENERAL_MEMBER, "");
        ring.mintRing(bob, AetherRing.RingTier.GENERAL_MEMBER, "");
        assertEq(ring.getTotalMembers(), 2);

        // 非会员不计入
        ring.mintRing(carol, AetherRing.RingTier.PARLIAMENT_MEMBER, "");
        assertEq(ring.getTotalMembers(), 2);

        // 撤销扣减
        ring.revokeRing(0);
        assertEq(ring.getTotalMembers(), 1);
    }

    // ──────────── setRingActive ────────────

    function test_SetRingActive_Toggles() public {
        ring.mintRing(alice, AetherRing.RingTier.PARLIAMENT_MEMBER, "");
        assertTrue(ring.isBearer(alice));

        ring.setRingActive(0, false);
        assertFalse(ring.isBearer(alice));
        assertEq(ring.getTier(alice), 0); // 被暂停后 getTier 也返回 0

        ring.setRingActive(0, true);
        assertTrue(ring.isBearer(alice));
        assertEq(ring.getTier(alice), 1);
    }

    // ──────────── supportsInterface ────────────

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
