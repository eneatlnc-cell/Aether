// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AetherRing} from "../src/AetherRing.sol";
import {IAetherRing} from "../src/interfaces/IAetherRing.sol";
import {AetherDonation} from "../src/AetherDonation.sol";
import {IAetherDonation} from "../src/interfaces/IAetherDonation.sol";

/**
 * @title AetherDonation Test
 * @dev 覆盖 13 个测试用例（对应 V3_DEV_STEPS.md 步骤 2.9）
 *
 *   T2.1  首次捐款铸公民道环
 *   T2.2  二次捐款不重复铸公民道环
 *   T2.3  金额 < $10 revert
 *   T2.4  paypalTxId 防重放
 *   T2.5  paypalAccountHash 去重
 *   T2.6  放弃冷却期内 revert
 *   T2.7  settleDonation 非 admin revert
 *   T2.8  settleDonation 重复 settle revert
 *   T2.9  3 公民担保激活快速通道
 *   T2.10 非公民担保 revert
 *   T2.11 SBT 不可转让
 *   T2.12 多笔捐款查询
 *   T2.13 未 settle 列表
 */
contract AetherDonationTest is Test {
    AetherRing ring;
    AetherDonation donation;

    address admin = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA401);
    address dave = address(0xDA4E);
    address treasury = address(0x7EAF); // Safe 多签国库（mock 地址即可）

    // ── 常量 ──
    uint256 constant MIN_DONATION = 10 * 10 ** 6; // $10
    bytes32 constant PAYPAL_HASH_BASE = keccak256("paypal_account_base");

    function setUp() public {
        ring = new AetherRing();
        donation = new AetherDonation(address(ring), treasury, admin);

        // AetherDonation 需要 AetherRing.MINTER_ROLE 才能铸公民道环 / 重新激活休眠公民
        // 注：Solidity 0.8.26 不支持 ContractName.ConstantName 跨合约访问，用实例 getter
        ring.grantRole(ring.MINTER_ROLE(), address(donation));
    }

    // ── 辅助：生成唯一 PayPal 凭证 ──
    function _paypalTxId(uint256 seq) internal pure returns (string memory) {
        return string(abi.encodePacked("PAYPAL-TX-", _uintToStr(seq)));
    }

    function _paypalHash(address donor) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(donor));
    }

    function _uintToStr(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.1  首次捐款铸公民道环
    // ═══════════════════════════════════════════════════════════
    function test_MintDonation_FirstTime_MintsCitizenRing() public {
        uint256 tokenId = donation.mintDonation(alice, MIN_DONATION, _paypalTxId(1), _paypalHash(alice));

        // 捐款凭证已铸
        assertEq(tokenId, 1);
        assertEq(donation.ownerOf(tokenId), alice);

        // 公民道环已铸
        assertTrue(ring.isBearer(alice));
        assertEq(ring.getTier(alice), uint8(IAetherRing.RingTier.CITIZEN));
        assertEq(ring.getRingId(alice), 1); // ring tokenId 从 1 开始

        // Donation 数据正确
        IAetherDonation.Donation memory d = donation.getDonation(tokenId);
        assertEq(d.donor, alice);
        assertEq(d.amount, MIN_DONATION);
        assertEq(d.usdcAmount, 0);
        assertFalse(d.isSettled);
        assertFalse(d.fastTrackActivated);
        assertEq(d.sponsorCount, 0);
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.2  二次捐款不重复铸公民道环
    // ═══════════════════════════════════════════════════════════
    function test_MintDonation_SecondTime_NoCitizenRing() public {
        // 第一次捐款
        donation.mintDonation(alice, MIN_DONATION, _paypalTxId(1), _paypalHash(alice));
        uint256 ringIdAfterFirst = ring.getRingId(alice);
        assertTrue(ringIdAfterFirst != 0);

        // 第二次捐款（不同 PayPal 账户 + TxId）
        // 注：同一 donor 用不同 PayPal 账户是不允许的（paypalAccountHash 去重），
        //     但同一 PayPal 账户可以多笔捐款 → 用同一 hash + 不同 txId
        //     实际场景：服务端确保一个钱包对应一个 PayPal 账户
        uint256 tokenId2 = donation.mintDonation(alice, MIN_DONATION * 2, _paypalTxId(2), _paypalHash(alice));

        // 第二笔捐款凭证已铸
        assertEq(tokenId2, 2);
        assertEq(donation.ownerOf(tokenId2), alice);

        // 公民道环未重复铸造（ringId 不变）
        assertEq(ring.getRingId(alice), ringIdAfterFirst);
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.3  金额 < $10 revert
    // ═══════════════════════════════════════════════════════════
    function test_MintDonation_AmountLessThan10_Revert() public {
        vm.expectRevert(
            abi.encodeWithSelector(AetherDonation.DonationTooSmall.selector, 5 * 10 ** 6, MIN_DONATION)
        );
        donation.mintDonation(alice, 5 * 10 ** 6, _paypalTxId(1), _paypalHash(alice));
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.4  paypalTxId 防重放
    // ═══════════════════════════════════════════════════════════
    function test_MintDonation_DuplicatePayPalTx_Revert() public {
        string memory txId = _paypalTxId(1);
        donation.mintDonation(alice, MIN_DONATION, txId, _paypalHash(alice));

        // 同一 txId 给不同 donor → revert
        vm.expectRevert(abi.encodeWithSelector(AetherDonation.DuplicatePayPalTx.selector, txId));
        donation.mintDonation(bob, MIN_DONATION, txId, _paypalHash(bob));
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.5  paypalAccountHash 去重
    // ═══════════════════════════════════════════════════════════
    function test_MintDonation_DuplicatePayPalAccount_Revert() public {
        bytes32 acctHash = _paypalHash(alice);
        donation.mintDonation(alice, MIN_DONATION, _paypalTxId(1), acctHash);

        // 同一 PayPal 账户给不同 donor → revert
        vm.expectRevert(abi.encodeWithSelector(AetherDonation.DuplicatePayPalAccount.selector, acctHash));
        donation.mintDonation(bob, MIN_DONATION, _paypalTxId(2), acctHash);
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.6  放弃冷却期内 revert
    // ═══════════════════════════════════════════════════════════
    function test_MintDonation_InCooldown_Revert() public {
        // 1. 首次捐款 → alice 成为公民
        donation.mintDonation(alice, MIN_DONATION, _paypalTxId(1), _paypalHash(alice));
        assertTrue(ring.isBearer(alice));

        // 2. alice 放弃公民身份（触发 30 天冷却）
        vm.prank(alice);
        ring.renounceCitizenship();
        assertFalse(ring.isBearer(alice));

        // 3. 冷却期内再次捐款 → revert
        vm.expectRevert(abi.encodeWithSelector(AetherDonation.RenounceCooldownActive.selector, alice));
        donation.mintDonation(alice, MIN_DONATION, _paypalTxId(2), _paypalHash(alice));

        // 4. 30 天后可以重新捐款
        vm.warp(block.timestamp + 30 days + 1);
        uint256 tokenId = donation.mintDonation(alice, MIN_DONATION, _paypalTxId(2), _paypalHash(alice));
        assertEq(tokenId, 2);
        assertTrue(ring.isBearer(alice));
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.7  settleDonation 非 admin revert
    // ═══════════════════════════════════════════════════════════
    function test_SettleDonation_OnlyAdmin() public {
        uint256 tokenId = donation.mintDonation(alice, MIN_DONATION, _paypalTxId(1), _paypalHash(alice));

        // 非 admin 调用 → revert（AccessControl.AccessControlUnauthorizedAccount）
        vm.prank(bob);
        vm.expectRevert();
        donation.settleDonation(tokenId, MIN_DONATION);
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.8  settleDonation 重复 settle revert
    // ═══════════════════════════════════════════════════════════
    function test_SettleDonation_AlreadySettled_Revert() public {
        uint256 tokenId = donation.mintDonation(alice, MIN_DONATION, _paypalTxId(1), _paypalHash(alice));

        // 第一次 settle
        donation.settleDonation(tokenId, MIN_DONATION);
        assertTrue(donation.getDonation(tokenId).isSettled);

        // 重复 settle → revert
        vm.expectRevert(abi.encodeWithSelector(AetherDonation.AlreadySettled.selector, tokenId));
        donation.settleDonation(tokenId, MIN_DONATION);
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.9  3 公民担保激活快速通道
    // ═══════════════════════════════════════════════════════════
    function test_SponsorDonation_3Sponsors_ActivatesFastTrack() public {
        // alice, bob, carol 捐款成为公民
        donation.mintDonation(alice, MIN_DONATION, _paypalTxId(1), _paypalHash(alice));
        donation.mintDonation(bob, MIN_DONATION, _paypalTxId(2), _paypalHash(bob));
        donation.mintDonation(carol, MIN_DONATION, _paypalTxId(3), _paypalHash(carol));

        // dave 捐款（成为公民 + 获得捐款凭证）
        uint256 daveTokenId = donation.mintDonation(dave, MIN_DONATION, _paypalTxId(4), _paypalHash(dave));
        assertFalse(donation.isFastTrackActivated(daveTokenId));

        // alice 担保
        vm.prank(alice);
        donation.sponsorDonation(daveTokenId);
        assertEq(donation.getSponsorCount(daveTokenId), 1);
        assertFalse(donation.isFastTrackActivated(daveTokenId));

        // bob 担保
        vm.prank(bob);
        donation.sponsorDonation(daveTokenId);
        assertEq(donation.getSponsorCount(daveTokenId), 2);
        assertFalse(donation.isFastTrackActivated(daveTokenId));

        // carol 担保 → 激活快速通道
        vm.prank(carol);
        vm.expectEmit(true, false, false, false);
        emit AetherDonation.FastTrackActivated(daveTokenId);
        donation.sponsorDonation(daveTokenId);
        assertEq(donation.getSponsorCount(daveTokenId), 3);
        assertTrue(donation.isFastTrackActivated(daveTokenId));
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.10 非公民担保 revert
    // ═══════════════════════════════════════════════════════════
    function test_SponsorDonation_NonCitizen_Revert() public {
        // alice 捐款
        uint256 tokenId = donation.mintDonation(alice, MIN_DONATION, _paypalTxId(1), _paypalHash(alice));

        // bob 无道环 → 担保 revert
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(AetherDonation.NotCitizen.selector, bob));
        donation.sponsorDonation(tokenId);
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.11 SBT 不可转让
    // ═══════════════════════════════════════════════════════════
    function test_Transfer_Revert() public {
        uint256 tokenId = donation.mintDonation(alice, MIN_DONATION, _paypalTxId(1), _paypalHash(alice));

        // transferFrom revert
        vm.prank(alice);
        vm.expectRevert(AetherDonation.NonTransferable.selector);
        donation.transferFrom(alice, bob, tokenId);

        // safeTransferFrom (with data) revert
        vm.prank(alice);
        vm.expectRevert(AetherDonation.NonTransferable.selector);
        donation.safeTransferFrom(alice, bob, tokenId, "");

        // approve revert
        vm.prank(alice);
        vm.expectRevert(AetherDonation.NonTransferableApproval.selector);
        donation.approve(bob, tokenId);

        // setApprovalForAll revert
        vm.prank(alice);
        vm.expectRevert(AetherDonation.NonTransferableApproval.selector);
        donation.setApprovalForAll(bob, true);
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.12 多笔捐款查询
    // ═══════════════════════════════════════════════════════════
    function test_GetDonationsByDonor_ReturnsAllTokens() public {
        // alice 捐款 3 次
        donation.mintDonation(alice, MIN_DONATION, _paypalTxId(1), _paypalHash(alice));
        donation.mintDonation(alice, MIN_DONATION * 2, _paypalTxId(2), _paypalHash(alice));
        donation.mintDonation(alice, MIN_DONATION * 3, _paypalTxId(3), _paypalHash(alice));

        // bob 捐款 1 次
        donation.mintDonation(bob, MIN_DONATION, _paypalTxId(4), _paypalHash(bob));

        // 查询 alice 的捐款凭证
        uint256[] memory aliceTokens = donation.getDonationsByDonor(alice);
        assertEq(aliceTokens.length, 3);
        assertEq(aliceTokens[0], 1);
        assertEq(aliceTokens[1], 2);
        assertEq(aliceTokens[2], 3);

        // 查询 bob 的捐款凭证
        uint256[] memory bobTokens = donation.getDonationsByDonor(bob);
        assertEq(bobTokens.length, 1);
        assertEq(bobTokens[0], 4);

        // 总数
        assertEq(donation.getTotalDonations(), 4);
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.13 未 settle 列表（审计用）
    // ═══════════════════════════════════════════════════════════
    function test_GetUnsettledDonations_AuditList() public {
        // 铸 4 笔捐款
        donation.mintDonation(alice, MIN_DONATION, _paypalTxId(1), _paypalHash(alice));
        donation.mintDonation(bob, MIN_DONATION, _paypalTxId(2), _paypalHash(bob));
        donation.mintDonation(carol, MIN_DONATION, _paypalTxId(3), _paypalHash(carol));
        donation.mintDonation(dave, MIN_DONATION, _paypalTxId(4), _paypalHash(dave));

        // settle 第 1 和第 3 笔
        donation.settleDonation(1, MIN_DONATION);
        donation.settleDonation(3, MIN_DONATION);

        // 未 settle 列表 = [2, 4]
        uint256[] memory unsettled = donation.getUnsettledDonations();
        assertEq(unsettled.length, 2);
        assertEq(unsettled[0], 2);
        assertEq(unsettled[1], 4);
    }

    // ═══════════════════════════════════════════════════════════
    //  补充：构造函数零地址校验
    // ═══════════════════════════════════════════════════════════
    function test_Constructor_ZeroAddress_Revert() public {
        vm.expectRevert(AetherDonation.InvalidRingContract.selector);
        new AetherDonation(address(0), treasury, admin);

        vm.expectRevert(AetherDonation.InvalidTreasury.selector);
        new AetherDonation(address(ring), address(0), admin);
    }

    // ═══════════════════════════════════════════════════════════
    //  补充：重复担保 revert
    // ═══════════════════════════════════════════════════════════
    function test_SponsorDonation_Duplicate_Revert() public {
        donation.mintDonation(alice, MIN_DONATION, _paypalTxId(1), _paypalHash(alice));
        donation.mintDonation(bob, MIN_DONATION, _paypalTxId(2), _paypalHash(bob));

        // alice 担保 bob
        vm.prank(alice);
        donation.sponsorDonation(2);

        // alice 重复担保 → revert
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AetherDonation.AlreadySponsored.selector, 2, alice));
        donation.sponsorDonation(2);
    }
}
