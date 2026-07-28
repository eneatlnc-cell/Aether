// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AetherRing} from "../src/AetherRing.sol";
import {IAetherRing} from "../src/interfaces/IAetherRing.sol";
import {AetherDonation} from "../src/AetherDonation.sol";
import {IAetherDonation} from "../src/interfaces/IAetherDonation.sol";

/**
 * @title AetherDonation Test
 * @dev 纯链上 USDC 捐款测试（覆盖 donateAndMint 全部分支）
 *
 *   T2.1  首次捐款：approve + donateAndMint → 铸公民道环 + USDC 转账 + 凭证 NFT
 *   T2.2  二次捐款：不重复铸公民道环，但铸新凭证 NFT
 *   T2.3  金额 < $10 revert DonationTooSmall
 *   T2.4  放弃冷却期内 revert RenounceCooldownActive
 *   T2.5  休眠公民重新激活（emit DormantCitizenReactivated）
 *   T2.6  USDC transferFrom 返回 false → revert UsdcTransferFailed
 *   T2.7  3 公民担保激活快速通道
 *   T2.8  非公民担保 revert
 *   T2.9  SBT 不可转让
 *   T2.10 多笔捐款查询
 *   T2.11 构造函数零地址校验（ring / treasury / usdc）
 *   T2.12 重复担保 revert
 *   T2.13 setUsdcToken 管理函数
 */
contract AetherDonationTest is Test {
    AetherRing ring;
    AetherDonation donation;
    MockUSDC usdc;
    BadUSDC badUsdc;

    address admin = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA401);
    address dave = address(0xDA4E);
    address treasury = address(0x7EAF); // Safe 多签国库（mock 地址即可）

    // ── 常量 ──
    uint256 constant MIN_DONATION = 10 * 10 ** 6; // $10
    // AetherRing 公民休眠期（2 年），测试中用于构造休眠状态
    uint256 constant DORMANCY_PERIOD = 2 * 365 days;

    function setUp() public {
        ring = new AetherRing();
        usdc = new MockUSDC();
        donation = new AetherDonation(address(ring), treasury, address(usdc), admin);

        // AetherDonation 需要 AetherRing.MINTER_ROLE 才能铸公民道环 / 重新激活休眠公民
        // 注：Solidity 0.8.26 不支持 ContractName.ConstantName 跨合约访问，用实例 getter
        ring.grantRole(ring.MINTER_ROLE(), address(donation));
    }

    // ── 辅助：以 donor 身份完成 approve + donateAndMint ──
    function _donate(address donor, uint256 amount) internal returns (uint256 tokenId) {
        usdc.mint(donor, amount);
        vm.startPrank(donor);
        usdc.approve(address(donation), amount);
        tokenId = donation.donateAndMint(amount);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.1  首次捐款：approve + donateAndMint → 铸公民道环 + USDC 转账 + 凭证 NFT
    // ═══════════════════════════════════════════════════════════
    function test_DonateAndMint_FirstTime_MintsCitizenRing() public {
        uint256 treasuryBefore = usdc.balanceOf(treasury);

        uint256 tokenId = _donate(alice, MIN_DONATION);

        // 捐款凭证已铸
        assertEq(tokenId, 1);
        assertEq(donation.ownerOf(tokenId), alice);

        // 公民道环已铸
        assertTrue(ring.isBearer(alice));
        assertEq(ring.getTier(alice), uint8(IAetherRing.RingTier.CITIZEN));
        assertEq(ring.getRingId(alice), 1); // ring tokenId 从 1 开始

        // USDC 已从 alice 转到 treasury
        assertEq(usdc.balanceOf(alice), 0);
        assertEq(usdc.balanceOf(treasury), treasuryBefore + MIN_DONATION);

        // Donation 数据正确
        IAetherDonation.Donation memory d = donation.getDonation(tokenId);
        assertEq(d.donor, alice);
        assertEq(d.amount, MIN_DONATION);
        assertEq(d.timestamp, block.timestamp);
        assertFalse(d.fastTrackActivated);
        assertEq(d.sponsorCount, 0);
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.2  二次捐款：不重复铸公民道环，但铸新凭证 NFT
    // ═══════════════════════════════════════════════════════════
    function test_DonateAndMint_SecondTime_NoDuplicateCitizenRing() public {
        // 第一次捐款
        _donate(alice, MIN_DONATION);
        uint256 ringIdAfterFirst = ring.getRingId(alice);
        assertTrue(ringIdAfterFirst != 0);

        // 第二次捐款（更大金额）
        uint256 tokenId2 = _donate(alice, MIN_DONATION * 2);

        // 第二笔捐款凭证已铸
        assertEq(tokenId2, 2);
        assertEq(donation.ownerOf(tokenId2), alice);

        // 公民道环未重复铸造（ringId 不变）
        assertEq(ring.getRingId(alice), ringIdAfterFirst);

        // 第二笔 Donation 金额正确
        IAetherDonation.Donation memory d = donation.getDonation(tokenId2);
        assertEq(d.amount, MIN_DONATION * 2);
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.3  金额 < $10 revert DonationTooSmall
    // ═══════════════════════════════════════════════════════════
    function test_DonateAndMint_AmountLessThan10_Revert() public {
        uint256 small = 5 * 10 ** 6;
        usdc.mint(alice, small);
        vm.startPrank(alice);
        usdc.approve(address(donation), small);

        vm.expectRevert(
            abi.encodeWithSelector(AetherDonation.DonationTooSmall.selector, small, MIN_DONATION)
        );
        donation.donateAndMint(small);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.4  放弃冷却期内 revert RenounceCooldownActive
    // ═══════════════════════════════════════════════════════════
    function test_DonateAndMint_InCooldown_Revert() public {
        // 1. 首次捐款 → alice 成为公民
        _donate(alice, MIN_DONATION);
        assertTrue(ring.isBearer(alice));

        // 2. alice 放弃公民身份（触发 30 天冷却）
        vm.prank(alice);
        ring.renounceCitizenship();
        assertFalse(ring.isBearer(alice));

        // 3. 冷却期内再次捐款 → revert
        usdc.mint(alice, MIN_DONATION);
        vm.startPrank(alice);
        usdc.approve(address(donation), MIN_DONATION);
        vm.expectRevert(abi.encodeWithSelector(AetherDonation.RenounceCooldownActive.selector, alice));
        donation.donateAndMint(MIN_DONATION);
        vm.stopPrank();

        // 4. 30 天后可以重新捐款
        vm.warp(block.timestamp + 30 days + 1);
        uint256 tokenId = _donate(alice, MIN_DONATION);
        assertEq(tokenId, 2);
        assertTrue(ring.isBearer(alice));
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.5  休眠公民重新激活
    // ═══════════════════════════════════════════════════════════
    function test_DonateAndMint_DormantCitizen_Reactivated() public {
        // 1. alice 首次捐款成为公民
        _donate(alice, MIN_DONATION);
        uint256 ringId = ring.getRingId(alice);
        assertTrue(ringId != 0);
        assertFalse(ring.isDormant(alice));

        // 2. 推进时间超过休眠期（2 年），标记休眠
        vm.warp(block.timestamp + DORMANCY_PERIOD + 1);
        ring.markDormantIfDue(ringId);
        assertTrue(ring.isDormant(alice));

        // 3. alice 再次捐款 → 应触发重新激活
        uint256 treasuryBefore = usdc.balanceOf(treasury);
        usdc.mint(alice, MIN_DONATION * 3);
        vm.startPrank(alice);
        usdc.approve(address(donation), MIN_DONATION * 3);

        vm.expectEmit(true, false, false, false);
        emit AetherDonation.DormantCitizenReactivated(alice);

        uint256 tokenId2 = donation.donateAndMint(MIN_DONATION * 3);
        vm.stopPrank();

        // 4. 验证：新捐款凭证已铸，公民已重新激活，USDC 已转账
        assertEq(tokenId2, 2);
        assertFalse(ring.isDormant(alice));
        assertTrue(ring.isBearer(alice));
        assertEq(usdc.balanceOf(treasury), treasuryBefore + MIN_DONATION * 3);
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.6  USDC transferFrom 返回 false → revert UsdcTransferFailed
    // ═══════════════════════════════════════════════════════════
    function test_DonateAndMint_UsdcTransferFails_Revert() public {
        // 切换 USDC 为返回 false 的 BadUSDC
        badUsdc = new BadUSDC();
        donation.setUsdcToken(address(badUsdc));

        // BadUSDC.transferFrom 恒返回 false
        badUsdc.mint(alice, MIN_DONATION);
        vm.startPrank(alice);
        badUsdc.approve(address(donation), MIN_DONATION);

        vm.expectRevert(AetherDonation.UsdcTransferFailed.selector);
        donation.donateAndMint(MIN_DONATION);
        vm.stopPrank();

        // 验证：未铸任何凭证 NFT，alice 仍是 0 道环
        assertEq(donation.getTotalDonations(), 0);
        assertEq(ring.getRingId(alice), 0);
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.7  3 公民担保激活快速通道
    // ═══════════════════════════════════════════════════════════
    function test_SponsorDonation_3Sponsors_ActivatesFastTrack() public {
        // alice, bob, carol 捐款成为公民
        _donate(alice, MIN_DONATION);
        _donate(bob, MIN_DONATION);
        _donate(carol, MIN_DONATION);

        // dave 捐款（成为公民 + 获得捐款凭证）
        uint256 daveTokenId = _donate(dave, MIN_DONATION);
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
    //  T2.8  非公民担保 revert
    // ═══════════════════════════════════════════════════════════
    function test_SponsorDonation_NonCitizen_Revert() public {
        // alice 捐款
        uint256 tokenId = _donate(alice, MIN_DONATION);

        // bob 无道环 → 担保 revert
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(AetherDonation.NotCitizen.selector, bob));
        donation.sponsorDonation(tokenId);
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.9  SBT 不可转让
    // ═══════════════════════════════════════════════════════════
    function test_Transfer_Revert() public {
        uint256 tokenId = _donate(alice, MIN_DONATION);

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
    //  T2.10 多笔捐款查询
    // ═══════════════════════════════════════════════════════════
    function test_GetDonationsByDonor_ReturnsAllTokens() public {
        // alice 捐款 3 次
        _donate(alice, MIN_DONATION);
        _donate(alice, MIN_DONATION * 2);
        _donate(alice, MIN_DONATION * 3);

        // bob 捐款 1 次
        _donate(bob, MIN_DONATION);

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
    //  T2.11 构造函数零地址校验（ring / treasury / usdc）
    // ═══════════════════════════════════════════════════════════
    function test_Constructor_ZeroAddress_Revert() public {
        vm.expectRevert(AetherDonation.InvalidRingContract.selector);
        new AetherDonation(address(0), treasury, address(usdc), admin);

        vm.expectRevert(AetherDonation.InvalidTreasury.selector);
        new AetherDonation(address(ring), address(0), address(usdc), admin);

        vm.expectRevert(AetherDonation.InvalidUsdcToken.selector);
        new AetherDonation(address(ring), treasury, address(0), admin);
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.12 重复担保 revert
    // ═══════════════════════════════════════════════════════════
    function test_SponsorDonation_Duplicate_Revert() public {
        _donate(alice, MIN_DONATION);
        _donate(bob, MIN_DONATION);

        // alice 担保 bob 的捐款凭证（tokenId=2）
        vm.prank(alice);
        donation.sponsorDonation(2);

        // alice 重复担保 → revert
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AetherDonation.AlreadySponsored.selector, 2, alice));
        donation.sponsorDonation(2);
    }

    // ═══════════════════════════════════════════════════════════
    //  T2.13 setUsdcToken 管理函数
    // ═══════════════════════════════════════════════════════════
    function test_SetUsdcToken_AdminOnly() public {
        MockUSDC newUsdc = new MockUSDC();

        // 非 admin revert
        vm.prank(bob);
        vm.expectRevert();
        donation.setUsdcToken(address(newUsdc));

        // 零地址 revert
        vm.expectRevert(AetherDonation.InvalidUsdcToken.selector);
        donation.setUsdcToken(address(0));

        // admin 切换成功 + 事件
        vm.expectEmit(true, true, false, false);
        emit AetherDonation.UsdcTokenUpdated(address(usdc), address(newUsdc));
        donation.setUsdcToken(address(newUsdc));
        assertEq(donation.usdc(), address(newUsdc));
    }
}

/**
 * @title MockUSDC — 标准 ERC20 mock（6 decimals，支持 approve/transferFrom）
 * @dev 仅用于测试：public mint 任意地址可调，transferFrom 返回 true
 */
contract MockUSDC {
    string public name = "USD Coin";
    string public symbol = "USDC";
    uint8 public decimals = 6;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "USDC: insufficient allowance");
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "USDC: insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}

/**
 * @title BadUSDC — transferFrom 恒返回 false 的 mock
 * @dev 用于测试 AetherDonation.donateAndMint 的返回值检查（UsdcTransferFailed）
 */
contract BadUSDC {
    string public name = "Bad USD Coin";
    string public symbol = "BUSDC";
    uint8 public decimals = 6;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return false;
    }

    // 关键：transferFrom 恒返回 false（不 revert），模拟某些 USDC 实现的失败行为
    function transferFrom(address, address, uint256) external returns (bool) {
        return false;
    }
}
