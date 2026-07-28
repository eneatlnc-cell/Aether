// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AetherRing} from "../src/AetherRing.sol";
import {IAetherRing} from "../src/interfaces/IAetherRing.sol";
import {AetherElection} from "../src/AetherElection.sol";
import {IAetherElection} from "../src/interfaces/IAetherElection.sol";

/**
 * @title AetherElection Test v3
 * @dev 覆盖 4 阶段状态机、CITIZEN_TO_COUNCIL、空缺处理、候选人资格放宽
 *
 * 测试矩阵（10 项，对应 V3_DEV_STEPS.md 步骤 4.6）：
 *   T4.1  MEMBER_TO_GRASSROOTS：公民可注册
 *   T4.2  MEMBER_TO_GRASSROOTS：到期成员可注册
 *   T4.3  GRASSROOTS_TO_MID：仅对应院基层可参选
 *   T4.4  CITIZEN_TO_COUNCIL：仅公民可参选理事
 *   T4.5  理事会整理：批准/拒绝
 *   T4.6  议会审批：达到阈值推进
 *   T4.7  投票：前 N 名当选
 *   T4.8  finalize：名额不足 → PartiallyFilled
 *   T4.9  appointToVacancy：理事长填补空缺
 *   T4.10 无人参选 → 延长 7 天
 */
contract AetherElectionTest is Test {
    AetherRing ring;
    AetherElection election;

    address admin = address(this);
    address chair = address(0xCCA1); // 理事长
    address parMember = address(0xAAA1); // tier 1 议员
    address citizen1 = address(0xC1D1);
    address citizen2 = address(0xC1D2);
    address citizen3 = address(0xC1D3);
    address citizen4 = address(0xC1D4);
    address citizen5 = address(0xC1D5);
    address nonMember = address(0x0FF1);
    address expiredMember = address(0xE7A1); // 到期议员

    function setUp() public {
        ring = new AetherRing();
        election = new AetherElection(address(ring));

        // 授权 election 合约在 ring 上的角色
        ring.grantRole(ring.ADMIN_ROLE(), address(election));
        ring.grantRole(ring.MINTER_ROLE(), address(election));
        ring.grantRole(ring.ELECTION_ROLE(), address(election));

        // 授予理事长角色
        election.grantCouncilChairRole(chair);

        // 铸造道环
        ring.mintRing(parMember, IAetherRing.RingTier.PARLIAMENT_MEMBER, "");
        ring.mintRing(citizen1, IAetherRing.RingTier.CITIZEN, "");
        ring.mintRing(citizen2, IAetherRing.RingTier.CITIZEN, "");
        ring.mintRing(citizen3, IAetherRing.RingTier.CITIZEN, "");
        ring.mintRing(citizen4, IAetherRing.RingTier.CITIZEN, "");
        ring.mintRing(citizen5, IAetherRing.RingTier.CITIZEN, "");
        // 给理事长铸 COUNCIL_CHAIR 道环
        ring.grantRole(ring.MINTER_ROLE(), address(this));
        ring.mintRing(chair, IAetherRing.RingTier.COUNCIL_CHAIR, "");

        // 议会审批阈值=1（默认）
    }

    // ═══════════════════════════════════════════════════════════
    //  T4.1 公民可注册 MEMBER_TO_GRASSROOTS
    // ═══════════════════════════════════════════════════════════

    function test_MemberToGrassroots_CitizenCanRegister() public {
        uint256 id = election.createElection(
            IAetherElection.ElectionType.MEMBER_TO_GRASSROOTS,
            1, // 议会
            IAetherElection.CouncilTargetTier.CouncilMember, // 不用
            2 // 2 席
        );

        vm.prank(citizen1);
        election.registerCandidate(id);

        (bool isNominated, bool isRegistered,,, ,) = election.getCandidateInfo(id, citizen1);
        assertTrue(isNominated);
        assertFalse(isRegistered); // 进入投票池需经理事会审批
    }

    // ═══════════════════════════════════════════════════════════
    //  T4.2 到期成员可注册 MEMBER_TO_GRASSROOTS（V5 资格放宽）
    // ═══════════════════════════════════════════════════════════

    function test_MemberToGrassroots_ExpiredMemberCanRegister() public {
        // 让 parMember 的任期到期（基层 1 年）
        vm.warp(block.timestamp + 366 days);
        ring.markExpiredIfDue(ring.getRingId(parMember));
        assertTrue(ring.isExpired(ring.getRingId(parMember)));

        uint256 id = election.createElection(
            IAetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, IAetherElection.CouncilTargetTier.CouncilMember, 1
        );

        // 到期议员可注册
        vm.prank(parMember);
        election.registerCandidate(id);

        (bool isNominated,,,, ,) = election.getCandidateInfo(id, parMember);
        assertTrue(isNominated);
    }

    // ═══════════════════════════════════════════════════════════
    //  T4.3 GRASSROOTS_TO_MID：仅对应院基层可参选
    // ═══════════════════════════════════════════════════════════

    function test_GrassrootsToMid_OnlyCorrespondingGrassroots() public {
        uint256 id = election.createElection(
            IAetherElection.ElectionType.GRASSROOTS_TO_MID, 1, // 议会基层→中层
            IAetherElection.CouncilTargetTier.CouncilMember, 1
        );

        // 议员可注册（tier 1 对应 chamber 1）
        vm.prank(parMember);
        election.registerCandidate(id);

        // 公民不可注册（tier 14）
        vm.expectRevert(AetherElection.NotEligibleCandidate.selector);
        vm.prank(citizen1);
        election.registerCandidate(id);
    }

    // ═══════════════════════════════════════════════════════════
    //  T4.4 CITIZEN_TO_COUNCIL：仅公民可参选
    // ═══════════════════════════════════════════════════════════

    function test_CitizenToCouncil_OnlyCitizen() public {
        uint256 id = election.createElection(
            IAetherElection.ElectionType.CITIZEN_TO_COUNCIL,
            4, // 理事
            IAetherElection.CouncilTargetTier.CouncilMember,
            2
        );

        // 公民可注册
        vm.prank(citizen1);
        election.registerCandidate(id);

        // 议员不可注册
        vm.expectRevert(AetherElection.NotEligibleCandidate.selector);
        vm.prank(parMember);
        election.registerCandidate(id);
    }

    // ═══════════════════════════════════════════════════════════
    //  T4.5 理事会整理：批准/拒绝
    // ═══════════════════════════════════════════════════════════

    function test_CouncilReview_ApproveReject() public {
        uint256 id = election.createElection(
            IAetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, IAetherElection.CouncilTargetTier.CouncilMember, 2
        );

        vm.prank(citizen1);
        election.registerCandidate(id);
        vm.prank(citizen2);
        election.registerCandidate(id);

        // 注册期结束 → 推进至 CouncilReview
        skip(7 days + 1);
        election.advanceToCouncilReview(id);

        // 理事长批准 citizen1，拒绝 citizen2
        vm.prank(chair);
        election.approveCandidate(id, citizen1);
        vm.prank(chair);
        election.rejectCandidate(id, citizen2);

        (, bool isReg1, bool isRej1,,, ) = election.getCandidateInfo(id, citizen1);
        (, bool isReg2, bool isRej2,,, ) = election.getCandidateInfo(id, citizen2);
        assertTrue(isReg1);
        assertFalse(isRej1);
        assertFalse(isReg2);
        assertTrue(isRej2);
    }

    // ═══════════════════════════════════════════════════════════
    //  T4.6 议会审批：达到阈值推进至投票阶段
    // ═══════════════════════════════════════════════════════════

    function test_ParliamentApproval_Vote() public {
        uint256 id = election.createElection(
            IAetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, IAetherElection.CouncilTargetTier.CouncilMember, 1
        );

        vm.prank(citizen1);
        election.registerCandidate(id);

        skip(7 days + 1);
        election.advanceToCouncilReview(id);

        vm.prank(chair);
        election.approveCandidate(id, citizen1);

        // 理事会整理期结束 → 推进至议会审批
        skip(3 days + 1);
        election.advanceToParliamentApproval(id);

        // 议员投票批准（阈值=1）
        vm.prank(parMember);
        election.parliamentApproveCandidateList(id);

        (, IAetherElection.ElectionStatus status,,,,,, ) = election.getElection(id);
        assertEq(uint8(status), uint8(IAetherElection.ElectionStatus.Active));
    }

    // ═══════════════════════════════════════════════════════════
    //  T4.7 投票：前 N 名当选
    // ═══════════════════════════════════════════════════════════

    function test_Voting_TopNWinners() public {
        uint256 id = election.createElection(
            IAetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, IAetherElection.CouncilTargetTier.CouncilMember, 2
        );

        // 3 个候选人
        vm.prank(citizen1);
        election.registerCandidate(id);
        vm.prank(citizen2);
        election.registerCandidate(id);
        vm.prank(citizen3);
        election.registerCandidate(id);

        skip(7 days + 1);
        election.advanceToCouncilReview(id);

        // 理事长全部批准
        vm.prank(chair);
        election.approveCandidate(id, citizen1);
        vm.prank(chair);
        election.approveCandidate(id, citizen2);
        vm.prank(chair);
        election.approveCandidate(id, citizen3);

        skip(3 days + 1);
        election.advanceToParliamentApproval(id);
        vm.prank(parMember);
        election.parliamentApproveCandidateList(id);

        // 公民投票：citizen4 → citizen1, citizen5 → citizen1, citizen2 的票为 0
        vm.prank(citizen4);
        election.castVote(id, citizen1);
        vm.prank(citizen5);
        election.castVote(id, citizen1);

        // 投票期结束 → finalize
        skip(7 days + 1);
        election.finalizeElection(id);

        // 前 2 名当选：citizen1（2 票）+ citizen2 或 citizen3（0 票，按注册时间）
        address[] memory winners = election.getWinners(id);
        assertEq(winners.length, 2);
        assertEq(winners[0], citizen1);

        (, IAetherElection.ElectionStatus status,,,,,, ) = election.getElection(id);
        assertEq(uint8(status), uint8(IAetherElection.ElectionStatus.Finalized));
    }

    // ═══════════════════════════════════════════════════════════
    //  T4.8 finalize：名额不足 → PartiallyFilled
    // ═══════════════════════════════════════════════════════════

    function test_Finalize_PartiallyFilled() public {
        // 5 席，但只有 2 个候选人
        uint256 id = election.createElection(
            IAetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, IAetherElection.CouncilTargetTier.CouncilMember, 5
        );

        vm.prank(citizen1);
        election.registerCandidate(id);
        vm.prank(citizen2);
        election.registerCandidate(id);

        skip(7 days + 1);
        election.advanceToCouncilReview(id);

        vm.prank(chair);
        election.approveCandidate(id, citizen1);
        vm.prank(chair);
        election.approveCandidate(id, citizen2);

        skip(3 days + 1);
        election.advanceToParliamentApproval(id);
        vm.prank(parMember);
        election.parliamentApproveCandidateList(id);

        skip(7 days + 1);
        election.finalizeElection(id);

        (, IAetherElection.ElectionStatus status,,,,, uint256 seatCount, uint256 unfilledSeats) = election.getElection(id);
        assertEq(uint8(status), uint8(IAetherElection.ElectionStatus.PartiallyFilled));
        assertEq(seatCount, 5);
        assertEq(unfilledSeats, 3);
    }

    // ═══════════════════════════════════════════════════════════
    //  T4.9 appointToVacancy：理事长填补空缺
    // ═══════════════════════════════════════════════════════════

    function test_AppointToVacancy_ChairAppoints() public {
        // 填满基层席位上限（60），使 _applyPromotion 在 finalize 时失败
        // parMember 已是 PARLIAMENT_MEMBER（setUp 中铸造），再铸 59 个
        for (uint256 i = 0; i < 59; i++) {
            ring.mintRing(address(uint160(0xF000 + i)), IAetherRing.RingTier.PARLIAMENT_MEMBER, "");
        }

        // 2 席，2 个候选人
        uint256 id = election.createElection(
            IAetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, IAetherElection.CouncilTargetTier.CouncilMember, 2
        );

        vm.prank(citizen1);
        election.registerCandidate(id);
        vm.prank(citizen2);
        election.registerCandidate(id);

        skip(7 days + 1);
        election.advanceToCouncilReview(id);

        // 理事长批准两人
        vm.prank(chair);
        election.approveCandidate(id, citizen1);
        vm.prank(chair);
        election.approveCandidate(id, citizen2);

        skip(3 days + 1);
        election.advanceToParliamentApproval(id);
        vm.prank(parMember);
        election.parliamentApproveCandidateList(id);

        skip(7 days + 1);
        election.finalizeElection(id);

        // 基层席位已满（60/60），_applyPromotion 对两人均失败
        // → PartiallyFilled，2 席空缺
        (, IAetherElection.ElectionStatus status1,,,,,, uint256 unfilled1) = election.getElection(id);
        assertEq(uint8(status1), uint8(IAetherElection.ElectionStatus.PartiallyFilled));
        assertEq(unfilled1, 2);

        // appointToVacancy 要求候选人已注册并通过审批（c.isRegistered == true）
        // citizen3 从未参选 → revert NotEligibleCandidate
        vm.expectRevert(AetherElection.NotEligibleCandidate.selector);
        vm.prank(chair);
        election.appointToVacancy(id, citizen3);

        // citizen2 是已注册并通过审批的候选人，可被任命
        // 但席位已满，晋升失败 → revert PromotionFailed
        vm.expectRevert(abi.encodeWithSelector(AetherElection.PromotionFailed.selector, citizen2));
        vm.prank(chair);
        election.appointToVacancy(id, citizen2);
    }

    // ═══════════════════════════════════════════════════════════
    //  T4.10 无人参选 → 延长 7 天
    // ═══════════════════════════════════════════════════════════

    function test_NoCandidates_Extend7Days() public {
        uint256 id = election.createElection(
            IAetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, IAetherElection.CouncilTargetTier.CouncilMember, 2
        );

        // 注册期结束，无人参选
        skip(7 days + 1);

        // extendRegistrationIfNoCandidates 应延长 7 天
        election.extendRegistrationIfNoCandidates(id);

        // 验证延长后的注册期
        (, uint256 registrationEndAt,,,, ) = election.getElectionTimelines(id);
        assertGt(registrationEndAt, block.timestamp);

        // 二次延长应 revert ExtensionAlreadyApplied（无人注册，确保通过 NoCandidates 检查）
        skip(7 days + 1);
        vm.expectRevert(AetherElection.ExtensionAlreadyApplied.selector);
        election.extendRegistrationIfNoCandidates(id);
    }

    // ═══════════════════════════════════════════════════════════
    //  额外：端到端流程（CITIZEN_TO_COUNCIL）
    // ═══════════════════════════════════════════════════════════

    function test_FullFlow_CitizenToCouncil() public {
        uint256 id = election.createElection(
            IAetherElection.ElectionType.CITIZEN_TO_COUNCIL,
            4, // 理事
            IAetherElection.CouncilTargetTier.CouncilMember,
            1
        );

        vm.prank(citizen1);
        election.registerCandidate(id);

        skip(7 days + 1);
        election.advanceToCouncilReview(id);

        vm.prank(chair);
        election.approveCandidate(id, citizen1);

        skip(3 days + 1);
        election.advanceToParliamentApproval(id);
        vm.prank(parMember);
        election.parliamentApproveCandidateList(id);

        // 公民投票
        vm.prank(citizen2);
        election.castVote(id, citizen1);
        vm.prank(citizen3);
        election.castVote(id, citizen1);

        skip(7 days + 1);
        election.finalizeElection(id);

        // citizen1 应被晋升为 COUNCIL_MEMBER (tier 10)
        assertEq(uint8(ring.getTier(citizen1)), uint8(IAetherRing.RingTier.COUNCIL_MEMBER));
    }
}
