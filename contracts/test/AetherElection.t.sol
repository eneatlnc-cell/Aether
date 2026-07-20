// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AetherRing} from "../src/AetherRing.sol";
import {AetherElection} from "../src/AetherElection.sol";
import {IAetherElection} from "../src/interfaces/IAetherElection.sol";

/**
 * @title AetherElection Test
 * @dev 覆盖三种选举类型 + 资格校验 + 投票 + 计票 + 自动晋升/续任
 *
 * 选举类型：
 *   1. MEMBER_TO_GRASSROOTS  会员 → 基层（普选，全体会员投票）
 *   2. GRASSROOTS_TO_MID     基层 → 中层（院选，对应院基层投票）
 *   3. REELECTION            连任选举（FOR vs AGAINST）
 */
contract AetherElectionTest is Test {
    AetherRing ring;
    AetherElection election;

    address admin = address(this);

    // 5 个候选会员（用于 MEMBER_TO_GRASSROOTS）
    address[5] candidates;
    // 20 个投票会员
    address[20] voters;
    // 3 个议员（基层，用于 GRASSROOTS_TO_MID 候选人）
    address[3] grassroots;
    // 6 个议员（基层，用于 GRASSROOTS_TO_MID 投票人）
    address[6] grassrootsVoters;

    uint256 constant VOTING_PERIOD = 7 days;

    function setUp() public {
        ring = new AetherRing();
        election = new AetherElection(address(ring));

        // 选举合约必须有 ADMIN_ROLE on Ring 才能调 updateTier / renewTerm
        ring.grantRole(AetherRing.ADMIN_ROLE, address(election));

        // 铸 5 个候选会员 + 20 个投票会员（共 25 个 GENERAL_MEMBER）
        for (uint256 i = 0; i < 5; i++) {
            candidates[i] = makeAddr(string(abi.encodePacked("cand", i)));
            ring.mintRing(candidates[i], AetherRing.RingTier.GENERAL_MEMBER, "");
        }
        for (uint256 i = 0; i < 20; i++) {
            voters[i] = makeAddr(string(abi.encodePacked("voter", i)));
            ring.mintRing(voters[i], AetherRing.RingTier.GENERAL_MEMBER, "");
        }

        // 铸 3 个议员（基层，tier=1）作为 GRASSROOTS_TO_MID 候选人
        for (uint256 i = 0; i < 3; i++) {
            grassroots[i] = makeAddr(string(abi.encodePacked("grass", i)));
            ring.mintRing(grassroots[i], AetherRing.RingTier.PARLIAMENT_MEMBER, "");
        }

        // 铸 6 个议员作为 GRASSROOTS_TO_MID 投票人（基层席位上限 20）
        for (uint256 i = 0; i < 6; i++) {
            grassrootsVoters[i] = makeAddr(string(abi.encodePacked("gv", i)));
            ring.mintRing(grassrootsVoters[i], AetherRing.RingTier.PARLIAMENT_MEMBER, "");
        }
    }

    // ═══════════════════════════════════════════════════════════
    //             MEMBER_TO_GRASSROOTS（普选）
    // ═══════════════════════════════════════════════════════════

    function test_MemberToGrassroots_Create_Success() public {
        address[] memory cands = new address[](3);
        cands[0] = candidates[0];
        cands[1] = candidates[1];
        cands[2] = candidates[2];

        uint256 id = election.createElection(
            AetherElection.ElectionType.MEMBER_TO_GRASSROOTS,
            1, // 议会
            2, // 2 席位
            cands,
            address(0)
        );

        assertEq(id, 0);
        (IAetherElection.ElectionType eType, IAetherElection.ElectionStatus status,,,,,) =
            election.getElection(id);
        assertEq(uint8(eType), uint8(AetherElection.ElectionType.MEMBER_TO_GRASSROOTS));
        assertEq(uint8(status), uint8(IAetherElection.ElectionStatus.Active));
    }

    function test_MemberToGrassroots_Create_RevertWhen_NotAdmin() public {
        address[] memory cands = new address[](2);
        cands[0] = candidates[0];
        cands[1] = candidates[1];

        vm.prank(voters[0]);
        vm.expectRevert();
        election.createElection(
            AetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, 2, cands, address(0)
        );
    }

    function test_MemberToGrassroots_Create_RevertWhen_CandidateNotMember() public {
        // grassroots[0] 是 tier=1，不能作为 MEMBER_TO_GRASSROOTS 候选人
        address[] memory cands = new address[](1);
        cands[0] = grassroots[0];

        vm.expectRevert(AetherElection.NotEligibleCandidate.selector);
        election.createElection(
            AetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, 1, cands, address(0)
        );
    }

    function test_MemberToGrassroots_Create_RevertWhen_InvalidChamber() public {
        address[] memory cands = new address[](1);
        cands[0] = candidates[0];

        vm.expectRevert(AetherElection.InvalidChamber.selector);
        election.createElection(
            AetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 4, 1, cands, address(0)
        );
    }

    function test_MemberToGrassroots_Create_RevertWhen_SeatCountExceeds() public {
        address[] memory cands = new address[](21);
        for (uint256 i = 0; i < 21; i++) {
            // 铸新会员作为候选
            address m = makeAddr(string(abi.encodePacked("nc", i)));
            ring.mintRing(m, AetherRing.RingTier.GENERAL_MEMBER, "");
            cands[i] = m;
        }

        vm.expectRevert(AetherElection.InvalidSeatCount.selector);
        election.createElection(
            AetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, 21, cands, address(0)
        );
    }

    function test_MemberToGrassroots_Vote_RevertWhen_NotEligibleVoter() public {
        // 只有 tier==10 会员能投
        address[] memory cands = new address[](2);
        cands[0] = candidates[0];
        cands[1] = candidates[1];

        uint256 id = election.createElection(
            AetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, 2, cands, address(0)
        );

        // grassroots[0] tier=1 不能投
        vm.prank(grassroots[0]);
        vm.expectRevert(AetherElection.NotEligibleVoter.selector);
        election.castVote(id, candidates[0]);
    }

    function test_MemberToGrassroots_Vote_RevertWhen_AlreadyVoted() public {
        address[] memory cands = new address[](2);
        cands[0] = candidates[0];
        cands[1] = candidates[1];

        uint256 id = election.createElection(
            AetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, 2, cands, address(0)
        );

        vm.prank(voters[0]);
        election.castVote(id, candidates[0]);

        vm.prank(voters[0]);
        vm.expectRevert(AetherElection.AlreadyVoted.selector);
        election.castVote(id, candidates[1]);
    }

    function test_MemberToGrassroots_Vote_RevertWhen_CandidateNotRegistered() public {
        address[] memory cands = new address[](1);
        cands[0] = candidates[0];

        uint256 id = election.createElection(
            AetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, 1, cands, address(0)
        );

        // 投给未注册的候选人（candidates[1] 未注册）
        vm.prank(voters[0]);
        vm.expectRevert(AetherElection.CandidateNotRegistered.selector);
        election.castVote(id, candidates[1]);
    }

    function test_MemberToGrassroots_Finalize_TopNPromoted() public {
        address[] memory cands = new address[](3);
        cands[0] = candidates[0];
        cands[1] = candidates[1];
        cands[2] = candidates[2];

        uint256 id = election.createElection(
            AetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, 2, cands, address(0)
        );

        // 投票：
        // candidates[0] → 8 票
        // candidates[1] → 6 票
        // candidates[2] → 4 票
        for (uint256 i = 0; i < 8; i++) {
            vm.prank(voters[i]);
            election.castVote(id, candidates[0]);
        }
        for (uint256 i = 8; i < 14; i++) {
            vm.prank(voters[i]);
            election.castVote(id, candidates[1]);
        }
        for (uint256 i = 14; i < 18; i++) {
            vm.prank(voters[i]);
            election.castVote(id, candidates[2]);
        }

        // 时间推进过投票期
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        election.finalizeElection(id);

        // 前 2 名当选：candidates[0] 和 candidates[1]
        address[] memory winners = election.getWinners(id);
        assertEq(winners.length, 2);
        assertEq(winners[0], candidates[0]);
        assertEq(winners[1], candidates[1]);

        // 当选者升到 tier=1（PARLIAMENT_MEMBER）
        assertEq(ring.getTier(candidates[0]), 1);
        assertEq(ring.getTier(candidates[1]), 1);
        // 未当选者仍是 tier=10
        assertEq(ring.getTier(candidates[2]), 10);
    }

    function test_MemberToGrassroots_Finalize_RevertWhen_NotEnded() public {
        address[] memory cands = new address[](1);
        cands[0] = candidates[0];

        uint256 id = election.createElection(
            AetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, 1, cands, address(0)
        );

        vm.expectRevert(AetherElection.ElectionNotEnded.selector);
        election.finalizeElection(id);
    }

    function test_MemberToGrassroots_Finalize_RevertWhen_AlreadyFinalized() public {
        address[] memory cands = new address[](1);
        cands[0] = candidates[0];

        uint256 id = election.createElection(
            AetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, 1, cands, address(0)
        );

        vm.prank(voters[0]);
        election.castVote(id, candidates[0]);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        election.finalizeElection(id);

        vm.expectRevert(AetherElection.AlreadyFinalized.selector);
        election.finalizeElection(id);
    }

    // ═══════════════════════════════════════════════════════════
    //             GRASSROOTS_TO_MID（院选）
    // ═══════════════════════════════════════════════════════════

    function test_GrassrootsToMid_Create_Success() public {
        // 3 个议员竞选参议员（中层，2 席位）
        address[] memory cands = new address[](3);
        cands[0] = grassroots[0];
        cands[1] = grassroots[1];
        cands[2] = grassroots[2];

        uint256 id = election.createElection(
            AetherElection.ElectionType.GRASSROOTS_TO_MID, 1, 2, cands, address(0)
        );
        assertEq(id, 0);
    }

    function test_GrassrootsToMid_Create_RevertWhen_CandidateNotGrassroots() public {
        // candidates[0] 是 tier=10，不能作为 GRASSROOTS_TO_MID 候选
        address[] memory cands = new address[](1);
        cands[0] = candidates[0];

        vm.expectRevert(AetherElection.NotEligibleCandidate.selector);
        election.createElection(
            AetherElection.ElectionType.GRASSROOTS_TO_MID, 1, 1, cands, address(0)
        );
    }

    function test_GrassrootsToMid_Vote_RevertWhen_NotChamberGrassroots() public {
        // 只有 tier==1 议员能投
        address[] memory cands = new address[](1);
        cands[0] = grassroots[0];

        uint256 id = election.createElection(
            AetherElection.ElectionType.GRASSROOTS_TO_MID, 1, 1, cands, address(0)
        );

        // voters[0] tier=10 不能投
        vm.prank(voters[0]);
        vm.expectRevert(AetherElection.NotEligibleVoter.selector);
        election.castVote(id, grassroots[0]);
    }

    function test_GrassrootsToMid_Finalize_PromotedToMid() public {
        // 3 个议员竞选 2 个参议员席位
        address[] memory cands = new address[](3);
        cands[0] = grassroots[0];
        cands[1] = grassroots[1];
        cands[2] = grassroots[2];

        uint256 id = election.createElection(
            AetherElection.ElectionType.GRASSROOTS_TO_MID, 1, 2, cands, address(0)
        );

        // 6 个议员投票
        // grassroots[0] → 4 票
        // grassroots[1] → 2 票
        // grassroots[2] → 0 票
        for (uint256 i = 0; i < 4; i++) {
            vm.prank(grassrootsVoters[i]);
            election.castVote(id, grassroots[0]);
        }
        for (uint256 i = 4; i < 6; i++) {
            vm.prank(grassrootsVoters[i]);
            election.castVote(id, grassroots[1]);
        }

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        election.finalizeElection(id);

        // 前 2 名：grassroots[0] 和 grassroots[1]
        address[] memory winners = election.getWinners(id);
        assertEq(winners.length, 2);
        assertEq(winners[0], grassroots[0]);
        assertEq(winners[1], grassroots[1]);

        // 升级到 tier=2（PARLIAMENT_SENIOR）
        assertEq(ring.getTier(grassroots[0]), 2);
        assertEq(ring.getTier(grassroots[1]), 2);
        // grassroots[2] 仍是 tier=1
        assertEq(ring.getTier(grassroots[2]), 1);
    }

    // ═══════════════════════════════════════════════════════════
    //             REELECTION（连任选举）
    // ═══════════════════════════════════════════════════════════

    function test_Reelection_Create_Success() public {
        // grassroots[0] 是 tier=1 议员，竞选连任
        uint256 id = election.createElection(
            AetherElection.ElectionType.REELECTION, 0, 0, new address[](0), grassroots[0]
        );
        assertEq(id, 0);
    }

    function test_Reelection_Create_RevertWhen_TargetZero() public {
        vm.expectRevert(AetherElection.TargetNotRegistered.selector);
        election.createElection(
            AetherElection.ElectionType.REELECTION, 0, 0, new address[](0), address(0)
        );
    }

    function test_Reelection_VoteFor_Success() public {
        uint256 id = election.createElection(
            AetherElection.ElectionType.REELECTION, 0, 0, new address[](0), grassroots[0]
        );

        // 基层连任 = 会员（tier=10）投票
        vm.prank(voters[0]);
        election.castVote(id, grassroots[0]);

        assertEq(election.getCandidateVoteCount(id, grassroots[0]), 1);
    }

    function test_Reelection_VoteAgainst_Success() public {
        uint256 id = election.createElection(
            AetherElection.ElectionType.REELECTION, 0, 0, new address[](0), grassroots[0]
        );

        vm.prank(voters[0]);
        election.castReelectionAgainst(id);

        (uint256 forVotes, uint256 againstVotes, bool passed) = election.getReelectionResult(id);
        assertEq(forVotes, 0);
        assertEq(againstVotes, 1);
        assertFalse(passed); // 还未 finalize
    }

    function test_Reelection_Against_RevertWhen_NotReelectionType() public {
        // 用 MEMBER_TO_GRASSROOTS 创建，然后尝试 castReelectionAgainst
        address[] memory cands = new address[](1);
        cands[0] = candidates[0];
        uint256 id = election.createElection(
            AetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, 1, cands, address(0)
        );

        vm.prank(voters[0]);
        vm.expectRevert(AetherElection.NotReelectionType.selector);
        election.castReelectionAgainst(id);
    }

    function test_Reelection_Finalize_Passes_WhenForMoreThanAgainst() public {
        uint256 id = election.createElection(
            AetherElection.ElectionType.REELECTION, 0, 0, new address[](0), grassroots[0]
        );

        // 12 赞成 / 5 反对
        for (uint256 i = 0; i < 12; i++) {
            vm.prank(voters[i]);
            election.castVote(id, grassroots[0]);
        }
        for (uint256 i = 12; i < 17; i++) {
            vm.prank(voters[i]);
            election.castReelectionAgainst(id);
        }

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        election.finalizeElection(id);

        (uint256 forVotes, uint256 againstVotes, bool passed) = election.getReelectionResult(id);
        assertEq(forVotes, 12);
        assertEq(againstVotes, 5);
        assertTrue(passed);

        // 验证续任：consecutiveTerms=1, termEndAt 推后 1 年
        uint256 ringId = ring.getRingId(grassroots[0]);
        AetherRing.RingInfo memory info = ring.getRingInfo(ringId);
        assertEq(info.consecutiveTerms, 1);
    }

    function test_Reelection_Finalize_Fails_WhenAgainstMoreThanFor() public {
        uint256 id = election.createElection(
            AetherElection.ElectionType.REELECTION, 0, 0, new address[](0), grassroots[0]
        );

        // 5 赞成 / 12 反对
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(voters[i]);
            election.castVote(id, grassroots[0]);
        }
        for (uint256 i = 5; i < 17; i++) {
            vm.prank(voters[i]);
            election.castReelectionAgainst(id);
        }

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        election.finalizeElection(id);

        (, , bool passed) = election.getReelectionResult(id);
        assertFalse(passed);

        // 续任失败，consecutiveTerms 不变
        uint256 ringId = ring.getRingId(grassroots[0]);
        AetherRing.RingInfo memory info = ring.getRingInfo(ringId);
        assertEq(info.consecutiveTerms, 0);
    }

    function test_Reelection_Finalize_Tie_Fails() public {
        // 票数相等 → forVotes > againstVotes 不成立 → 失败
        uint256 id = election.createElection(
            AetherElection.ElectionType.REELECTION, 0, 0, new address[](0), grassroots[0]
        );

        for (uint256 i = 0; i < 10; i++) {
            vm.prank(voters[i]);
            election.castVote(id, grassroots[0]);
        }
        for (uint256 i = 10; i < 20; i++) {
            vm.prank(voters[i]);
            election.castReelectionAgainst(id);
        }

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        election.finalizeElection(id);

        (, , bool passed) = election.getReelectionResult(id);
        assertFalse(passed);
    }

    // ═══════════════════════════════════════════════════════════
    //                  cancel & 通用
    // ═══════════════════════════════════════════════════════════

    function test_CancelElection_Success() public {
        address[] memory cands = new address[](1);
        cands[0] = candidates[0];

        uint256 id = election.createElection(
            AetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, 1, cands, address(0)
        );

        election.cancelElection(id);

        (, IAetherElection.ElectionStatus status,,,,,) = election.getElection(id);
        assertEq(uint8(status), uint8(IAetherElection.ElectionStatus.Canceled));
    }

    function test_CancelElection_RevertWhen_NotAdmin() public {
        address[] memory cands = new address[](1);
        cands[0] = candidates[0];

        uint256 id = election.createElection(
            AetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, 1, cands, address(0)
        );

        vm.prank(voters[0]);
        vm.expectRevert();
        election.cancelElection(id);
    }

    function test_Vote_RevertWhen_ElectionNotActive() public {
        address[] memory cands = new address[](1);
        cands[0] = candidates[0];

        uint256 id = election.createElection(
            AetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, 1, cands, address(0)
        );

        election.cancelElection(id);

        vm.prank(voters[0]);
        vm.expectRevert(AetherElection.ElectionNotActive.selector);
        election.castVote(id, candidates[0]);
    }

    function test_Vote_RevertWhen_VotingEnded() public {
        address[] memory cands = new address[](1);
        cands[0] = candidates[0];

        uint256 id = election.createElection(
            AetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, 1, cands, address(0)
        );

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        vm.prank(voters[0]);
        vm.expectRevert(AetherElection.ElectionNotActive.selector);
        election.castVote(id, candidates[0]);
    }

    function test_HasVoted_TracksCorrectly() public {
        address[] memory cands = new address[](2);
        cands[0] = candidates[0];
        cands[1] = candidates[1];

        uint256 id = election.createElection(
            AetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, 2, cands, address(0)
        );

        assertFalse(election.hasVoted(id, voters[0]));

        vm.prank(voters[0]);
        election.castVote(id, candidates[0]);

        assertTrue(election.hasVoted(id, voters[0]));
        assertFalse(election.hasVoted(id, voters[1]));
    }

    function test_GetCandidateVoteCount() public {
        address[] memory cands = new address[](2);
        cands[0] = candidates[0];
        cands[1] = candidates[1];

        uint256 id = election.createElection(
            AetherElection.ElectionType.MEMBER_TO_GRASSROOTS, 1, 2, cands, address(0)
        );

        vm.prank(voters[0]);
        election.castVote(id, candidates[0]);
        vm.prank(voters[1]);
        election.castVote(id, candidates[0]);
        vm.prank(voters[2]);
        election.castVote(id, candidates[1]);

        assertEq(election.getCandidateVoteCount(id, candidates[0]), 2);
        assertEq(election.getCandidateVoteCount(id, candidates[1]), 1);
    }

    // ═══════════════════════════════════════════════════════════
    //   setRingContract（管理员迁移 ring 引用）
    // ═══════════════════════════════════════════════════════════

    function test_SetRingContract_RevertWhen_NotAdmin() public {
        vm.prank(voters[0]);
        vm.expectRevert();
        election.setRingContract(address(0xBEEF));
    }
}
