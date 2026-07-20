// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AetherRing} from "../src/AetherRing.sol";
import {AetherGovernance} from "../src/AetherGovernance.sol";
import {IAetherRing} from "../src/interfaces/IAetherRing.sol";
import {ISafe} from "../src/interfaces/ISafe.sol";

/**
 * @title AetherGovernance Test v2
 * @dev 覆盖方案 B 计票规则 + IMPEACHMENT 弹劾流程 + PARAM 白名单
 *
 * 测试矩阵：
 *   场景1: 三院全赞成 + 会员多数赞成          → 通过
 *   场景2: 三院 2:1 + 会员多数赞成            → 通过
 *   场景3: 三院全赞成 + 会员参与率 < 30%       → 失败（参与率门槛）
 *   场景4: 三院全赞成 + 会员反对率 ≥ 60%       → 失败（绝对否决）
 *   场景5: 三院 1:1:1（无共识）                → 失败（院方共识门槛）
 *
 *   v2 新增：
 *   - onlyChamberMember：tier=10 普通会员不能提案
 *   - PARAM 白名单：非白名单 selector revert
 *   - IMPEACHMENT 弹劾全流程：100 联署 + 多签审查 + 会员 50%/70% 投票
 *   - IMPEACHMENT execute 撤销道环
 *   - Safe 多签 setSafeWallet
 */
contract AetherGovernanceTest is Test {
    AetherRing ring;
    AetherGovernance gov;
    MockSafe safe;

    address admin = address(this);

    // 持环者地址
    address parliamentSpeaker; // 议长 tier=3 权重 20
    address parliamentSenior1; // 参议员 tier=2 权重 5
    address parliamentSenior2;
    address parliamentMember1; // 议员 tier=1 权重 2

    address federationMinister; // 部长 tier=6 权重 20
    address federationSenior; // 委员长 tier=5 权重 5

    address senateElder; // 元老 tier=9 权重 20
    address senateFellow; // 研究员 tier=8 权重 5

    // 10 个普通会员（用于常规场景）
    address[10] members;

    // 100 个普通会员（用于 IMPEACHMENT 联署）
    address[100] signers;

    uint256 constant VOTING_PERIOD = 7 days;

    function setUp() public {
        ring = new AetherRing();
        gov = new AetherGovernance(address(ring));
        safe = new MockSafe();

        // 接入 Safe mock
        ring.setSafeWallet(address(safe));
        gov.setSafeWallet(address(safe));

        // 授权 governance 在 IMPEACHMENT execute 时能调 ring.revokeRing
        ring.grantRole(AetherRing.ADMIN_ROLE, address(gov));

        // ─── 铸道环 ───
        parliamentSpeaker = makeAddr("parliamentSpeaker");
        parliamentSenior1 = makeAddr("parliamentSenior1");
        parliamentSenior2 = makeAddr("parliamentSenior2");
        parliamentMember1 = makeAddr("parliamentMember1");

        federationMinister = makeAddr("federationMinister");
        federationSenior = makeAddr("federationSenior");

        senateElder = makeAddr("senateElder");
        senateFellow = makeAddr("senateFellow");

        ring.mintRing(parliamentSpeaker, AetherRing.RingTier.PARLIAMENT_SPEAKER, "");
        ring.mintRing(parliamentSenior1, AetherRing.RingTier.PARLIAMENT_SENIOR, "");
        ring.mintRing(parliamentSenior2, AetherRing.RingTier.PARLIAMENT_SENIOR, "");
        ring.mintRing(parliamentMember1, AetherRing.RingTier.PARLIAMENT_MEMBER, "");

        ring.mintRing(federationMinister, AetherRing.RingTier.FEDERATION_MINISTER, "");
        ring.mintRing(federationSenior, AetherRing.RingTier.FEDERATION_SENIOR, "");

        ring.mintRing(senateElder, AetherRing.RingTier.SENATE_ELDER, "");
        ring.mintRing(senateFellow, AetherRing.RingTier.SENATE_FELLOW, "");

        // 10 个会员，构成 30% 参与率需要 ≥3 人投票
        for (uint256 i = 0; i < 10; i++) {
            members[i] = makeAddr(string(abi.encodePacked("member", i)));
            ring.mintRing(members[i], AetherRing.RingTier.GENERAL_MEMBER, "");
        }

        // 100 个会员用于 IMPEACHMENT 联署
        for (uint256 i = 0; i < 100; i++) {
            signers[i] = makeAddr(string(abi.encodePacked("signer", i)));
            ring.mintRing(signers[i], AetherRing.RingTier.GENERAL_MEMBER, "");
        }

        assertEq(ring.getTotalMembers(), 110);

        // 给三院成员授予 PROPOSER_ROLE
        address[8] memory proposers = [
            parliamentSpeaker,
            parliamentSenior1,
            parliamentSenior2,
            parliamentMember1,
            federationMinister,
            federationSenior,
            senateElder,
            senateFellow
        ];
        for (uint256 i = 0; i < proposers.length; i++) {
            gov.grantProposerRole(proposers[i]);
        }
    }

    // ═══════════════════════════════════════════════════════════
    //                    辅助函数
    // ═══════════════════════════════════════════════════════════

    function _createProposal() internal returns (uint256) {
        vm.prank(parliamentSpeaker);
        return gov.createProposal(
            AetherGovernance.ProposalType.SIGNAL,
            "Test Proposal",
            "ipfs://test",
            address(0),
            ""
        );
    }

    function _vote(address voter, AetherGovernance.VoteOption opt) internal {
        vm.prank(voter);
        gov.castVote(0, opt);
    }

    function _votePid(uint256 pid, address voter, AetherGovernance.VoteOption opt) internal {
        vm.prank(voter);
        gov.castVote(pid, opt);
    }

    function _warpPastVoting() internal {
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
    }

    // ═══════════════════════════════════════════════════════════
    //                  场景 1：三院全赞成 + 会员多数赞成 → 通过
    // ═══════════════════════════════════════════════════════════

    function test_Scenario1_AllChambersFor_MembersFor_Passes() public {
        uint256 pid = _createProposal();

        _vote(parliamentSpeaker, AetherGovernance.VoteOption.FOR);
        _vote(federationMinister, AetherGovernance.VoteOption.FOR);
        _vote(senateElder, AetherGovernance.VoteOption.FOR);

        for (uint256 i = 0; i < 8; i++) {
            _vote(members[i], AetherGovernance.VoteOption.FOR);
        }
        _vote(members[8], AetherGovernance.VoteOption.AGAINST);
        _vote(members[9], AetherGovernance.VoteOption.ABSTAIN);

        _warpPastVoting();
        gov.finalizeProposal(pid);

        AetherGovernance.Proposal memory p = gov.getProposal(pid);
        assertEq(uint8(p.status), uint8(AetherGovernance.ProposalStatus.Queued));
    }

    // ═══════════════════════════════════════════════════════════
    //       场景 2：三院 2:1 赞成 + 会员多数赞成 → 通过
    // ═══════════════════════════════════════════════════════════

    function test_Scenario2_TwoChambersFor_Passes() public {
        uint256 pid = _createProposal();

        _vote(parliamentSpeaker, AetherGovernance.VoteOption.FOR);
        _vote(federationMinister, AetherGovernance.VoteOption.FOR);
        _vote(senateElder, AetherGovernance.VoteOption.AGAINST);

        for (uint256 i = 0; i < 7; i++) {
            _vote(members[i], AetherGovernance.VoteOption.FOR);
        }
        _vote(members[7], AetherGovernance.VoteOption.AGAINST);
        _vote(members[8], AetherGovernance.VoteOption.AGAINST);
        _vote(members[9], AetherGovernance.VoteOption.ABSTAIN);

        _warpPastVoting();
        gov.finalizeProposal(pid);

        AetherGovernance.Proposal memory p = gov.getProposal(pid);
        assertEq(uint8(p.status), uint8(AetherGovernance.ProposalStatus.Queued));
    }

    // ═══════════════════════════════════════════════════════════
    //    场景 3：三院全赞成 + 会员参与率 < 30% → 失败
    // ═══════════════════════════════════════════════════════════

    function test_Scenario3_AllChambersFor_LowMemberQuorum_Fails() public {
        uint256 pid = _createProposal();

        _vote(parliamentSpeaker, AetherGovernance.VoteOption.FOR);
        _vote(federationMinister, AetherGovernance.VoteOption.FOR);
        _vote(senateElder, AetherGovernance.VoteOption.FOR);

        // memberTotalSnapshot = 110，30% = 33。这里只 2 人投票 → 远低于 30%
        _vote(members[0], AetherGovernance.VoteOption.FOR);
        _vote(members[1], AetherGovernance.VoteOption.FOR);

        _warpPastVoting();
        gov.finalizeProposal(pid);

        AetherGovernance.Proposal memory p = gov.getProposal(pid);
        assertEq(uint8(p.status), uint8(AetherGovernance.ProposalStatus.Defeated));
        assertFalse(p.memberQuorumMet);
    }

    // ═══════════════════════════════════════════════════════════
    //   场景 4：三院全赞成 + 会员反对率 ≥ 60% → 绝对否决
    // ═══════════════════════════════════════════════════════════

    function test_Scenario4_AllChambersFor_MemberVeto_Fails() public {
        uint256 pid = _createProposal();

        _vote(parliamentSpeaker, AetherGovernance.VoteOption.FOR);
        _vote(federationMinister, AetherGovernance.VoteOption.FOR);
        _vote(senateElder, AetherGovernance.VoteOption.FOR);

        // 110 会员中至少需要 33 人投票才能满足 30% 参与率
        // 这里 40 人投票：25 反对 / 14 赞成 / 1 弃权 → 反对率 62.5% ≥ 60% → 否决
        for (uint256 i = 0; i < 25; i++) {
            _vote(signers[i], AetherGovernance.VoteOption.AGAINST);
        }
        for (uint256 i = 25; i < 39; i++) {
            _vote(signers[i], AetherGovernance.VoteOption.FOR);
        }
        _vote(signers[39], AetherGovernance.VoteOption.ABSTAIN);

        _warpPastVoting();
        gov.finalizeProposal(pid);

        AetherGovernance.Proposal memory p = gov.getProposal(pid);
        assertEq(uint8(p.status), uint8(AetherGovernance.ProposalStatus.Defeated));
        assertTrue(p.memberQuorumMet);
        assertTrue(p.memberVetoTriggered);
    }

    // ═══════════════════════════════════════════════════════════
    //       场景 5：三院 1:1:1 无共识 → 自动失败
    // ═══════════════════════════════════════════════════════════

    function test_Scenario5_NoChamberConsensus_Fails() public {
        uint256 pid = _createProposal();

        _vote(parliamentSpeaker, AetherGovernance.VoteOption.FOR);
        _vote(federationMinister, AetherGovernance.VoteOption.AGAINST);
        // 元老院弃权 → NEUTRAL

        // 会员全赞成（40 人，参与率 > 30%）
        for (uint256 i = 0; i < 40; i++) {
            _vote(signers[i], AetherGovernance.VoteOption.FOR);
        }

        _warpPastVoting();
        gov.finalizeProposal(pid);

        AetherGovernance.Proposal memory p = gov.getProposal(pid);
        assertEq(uint8(p.status), uint8(AetherGovernance.ProposalStatus.Defeated));
        assertEq(uint8(p.chamberConsensus), uint8(AetherGovernance.ChamberStance.NEUTRAL));
    }

    // ═══════════════════════════════════════════════════════════
    //                    边界 & 异常
    // ═══════════════════════════════════════════════════════════

    function test_RevertWhen_VoteWithoutRing() public {
        _createProposal();
        address noRing = makeAddr("noRing");
        vm.prank(noRing);
        vm.expectRevert(AetherGovernance.NotRingBearer.selector);
        gov.castVote(0, AetherGovernance.VoteOption.FOR);
    }

    function test_RevertWhen_DoubleVote() public {
        _createProposal();
        _vote(parliamentSpeaker, AetherGovernance.VoteOption.FOR);
        vm.prank(parliamentSpeaker);
        vm.expectRevert(AetherGovernance.AlreadyVoted.selector);
        gov.castVote(0, AetherGovernance.VoteOption.AGAINST);
    }

    function test_RevertWhen_InvalidVoteOption() public {
        _createProposal();
        vm.prank(parliamentSpeaker);
        vm.expectRevert(AetherGovernance.InvalidVoteOption.selector);
        gov.castVote(0, AetherGovernance.VoteOption.NONE);
    }

    function test_RevertWhen_VoteOutsideVotingPeriod() public {
        _createProposal();
        _warpPastVoting();
        vm.prank(parliamentSpeaker);
        vm.expectRevert(AetherGovernance.NotInVotingPeriod.selector);
        gov.castVote(0, AetherGovernance.VoteOption.FOR);
    }

    function test_RevertWhen_FinalizeBeforeVotingEnds() public {
        _createProposal();
        vm.expectRevert(AetherGovernance.VotingNotEnded.selector);
        gov.finalizeProposal(0);
    }

    function test_RevertWhen_FinalizeTwice() public {
        uint256 pid = _createProposal();
        _vote(parliamentSpeaker, AetherGovernance.VoteOption.FOR);
        _vote(federationMinister, AetherGovernance.VoteOption.FOR);
        _vote(senateElder, AetherGovernance.VoteOption.FOR);
        for (uint256 i = 0; i < 40; i++) {
            _vote(signers[i], AetherGovernance.VoteOption.FOR);
        }
        _warpPastVoting();
        gov.finalizeProposal(pid);
        vm.expectRevert(AetherGovernance.AlreadyFinalized.selector);
        gov.finalizeProposal(pid);
    }

    function test_RevertWhen_CreateProposalWithoutRing() public {
        address noRing = makeAddr("noRing");
        gov.grantProposerRole(noRing);
        vm.prank(noRing);
        // v2: onlyChamberMember 在 onlyRole 之后；getTier(noRing)=0 < 1 → NotChamberMember
        vm.expectRevert(AetherGovernance.NotChamberMember.selector);
        gov.createProposal(
            AetherGovernance.ProposalType.SIGNAL, "x", "ipfs://x", address(0), ""
        );
    }

    function test_RevertWhen_EmptyTitle() public {
        vm.prank(parliamentSpeaker);
        vm.expectRevert(AetherGovernance.EmptyTitle.selector);
        gov.createProposal(AetherGovernance.ProposalType.SIGNAL, "", "ipfs://x", address(0), "");
    }

    function test_RevertWhen_TreasuryWithZeroTarget() public {
        vm.prank(parliamentSpeaker);
        vm.expectRevert(AetherGovernance.TreasuryTargetZero.selector);
        gov.createProposal(
            AetherGovernance.ProposalType.TREASURY, "x", "ipfs://x", address(0), ""
        );
    }

    // ═══════════════════════════════════════════════════════════
    //   v2 新增：onlyChamberMember 修饰器（tier=10 不能提案）
    // ═══════════════════════════════════════════════════════════

    function test_RevertWhen_Tier10MemberCannotPropose() public {
        // members[0] 是 tier=10，即便有 PROPOSER_ROLE 也不能提案
        gov.grantProposerRole(members[0]);
        vm.prank(members[0]);
        vm.expectRevert(AetherGovernance.NotChamberMember.selector);
        gov.createProposal(
            AetherGovernance.ProposalType.SIGNAL, "tier10 propose", "ipfs://x", address(0), ""
        );
    }

    function test_Tier1Member_CanPropose() public {
        // 议员 tier=1 可提案
        vm.prank(parliamentMember1);
        uint256 pid = gov.createProposal(
            AetherGovernance.ProposalType.SIGNAL, "tier1 propose", "ipfs://x", address(0), ""
        );
        assertEq(pid, 0);
    }

    // ═══════════════════════════════════════════════════════════
    //   v2 新增：PARAM 白名单
    // ═══════════════════════════════════════════════════════════

    function test_RevertWhen_PARAM_NonWhitelistedSelector() public {
        // setRingContract 不在白名单内
        vm.prank(parliamentSpeaker);
        vm.expectRevert(
            abi.encodeWithSelector(
                AetherGovernance.ParamSelectorNotWhitelisted.selector,
                bytes4(keccak256("setRingContract(address)"))
            )
        );
        gov.createProposal(
            AetherGovernance.ProposalType.PARAM,
            "change ring contract",
            "ipfs://x",
            address(gov),
            abi.encodeWithSelector(gov.setRingContract.selector, address(0xBEEF))
        );
    }

    function test_RevertWhen_PARAM_SetSafeWallet_NotWhitelisted() public {
        // setSafeAddress 不在白名单内
        vm.prank(parliamentSpeaker);
        vm.expectRevert(AetherGovernance.ParamSelectorNotWhitelisted.selector);
        gov.createProposal(
            AetherGovernance.ProposalType.PARAM,
            "change safe wallet",
            "ipfs://x",
            address(gov),
            abi.encodeWithSelector(gov.setSafeWallet.selector, address(0xBEEF))
        );
    }

    function test_PARAM_Whitelisted_setInternalWeight() public {
        vm.prank(parliamentSpeaker);
        uint256 pid = gov.createProposal(
            AetherGovernance.ProposalType.PARAM,
            "adjust internal weight",
            "ipfs://x",
            address(gov),
            abi.encodeWithSelector(gov.setInternalWeight.selector, uint8(1), 3)
        );

        // 投票通过
        _vote(parliamentSpeaker, AetherGovernance.VoteOption.FOR);
        _vote(federationMinister, AetherGovernance.VoteOption.FOR);
        _vote(senateElder, AetherGovernance.VoteOption.FOR);
        for (uint256 i = 0; i < 40; i++) {
            _vote(signers[i], AetherGovernance.VoteOption.FOR);
        }
        _warpPastVoting();
        gov.finalizeProposal(pid);

        // Timelock 后执行
        vm.warp(block.timestamp + 12 hours + 1);
        gov.executeProposal(pid);

        assertEq(gov.internalWeight(1), 3);
    }

    // ═══════════════════════════════════════════════════════════
    //                    Timelock & execute
    // ═══════════════════════════════════════════════════════════

    function test_QueuedProposal_RequiresTimelockBeforeExecute() public {
        uint256 pid = _createProposal();
        _vote(parliamentSpeaker, AetherGovernance.VoteOption.FOR);
        _vote(federationMinister, AetherGovernance.VoteOption.FOR);
        _vote(senateElder, AetherGovernance.VoteOption.FOR);
        for (uint256 i = 0; i < 40; i++) {
            _vote(signers[i], AetherGovernance.VoteOption.FOR);
        }
        _warpPastVoting();
        gov.finalizeProposal(pid);

        vm.expectRevert(AetherGovernance.TimelockNotElapsed.selector);
        gov.executeProposal(pid);

        vm.warp(block.timestamp + 12 hours + 1);
        gov.executeProposal(pid);

        AetherGovernance.Proposal memory p = gov.getProposal(pid);
        assertEq(uint8(p.status), uint8(AetherGovernance.ProposalStatus.Executed));
    }

    function test_SignalExecute_HasNoSideEffects() public {
        uint256 pid = _createProposal();
        _vote(parliamentSpeaker, AetherGovernance.VoteOption.FOR);
        _vote(federationMinister, AetherGovernance.VoteOption.FOR);
        _vote(senateElder, AetherGovernance.VoteOption.FOR);
        for (uint256 i = 0; i < 40; i++) {
            _vote(signers[i], AetherGovernance.VoteOption.FOR);
        }
        _warpPastVoting();
        gov.finalizeProposal(pid);

        assertEq(gov.votingPeriod(), 7 days);

        vm.warp(block.timestamp + 12 hours + 1);
        gov.executeProposal(pid);

        assertEq(gov.votingPeriod(), 7 days);
    }

    function test_PARAM_Execute_ModifiesParam() public {
        vm.prank(parliamentSpeaker);
        uint256 pid = gov.createProposal(
            AetherGovernance.ProposalType.PARAM,
            "Extend voting period to 3 days",
            "ipfs://param",
            address(gov),
            abi.encodeWithSelector(gov.setVotingPeriod.selector, 3 days)
        );

        _vote(parliamentSpeaker, AetherGovernance.VoteOption.FOR);
        _vote(federationMinister, AetherGovernance.VoteOption.FOR);
        _vote(senateElder, AetherGovernance.VoteOption.FOR);
        for (uint256 i = 0; i < 40; i++) {
            _vote(signers[i], AetherGovernance.VoteOption.FOR);
        }
        _warpPastVoting();
        gov.finalizeProposal(pid);

        assertEq(gov.votingPeriod(), 7 days);

        vm.warp(block.timestamp + 12 hours + 1);
        gov.executeProposal(pid);

        assertEq(gov.votingPeriod(), 3 days);
    }

    // ═══════════════════════════════════════════════════════════
    //                    simulateFinalize
    // ═══════════════════════════════════════════════════════════

    function test_SimulateFinalize_MatchesActual() public {
        uint256 pid = _createProposal();
        _vote(parliamentSpeaker, AetherGovernance.VoteOption.FOR);
        _vote(federationMinister, AetherGovernance.VoteOption.FOR);
        _vote(senateElder, AetherGovernance.VoteOption.FOR);
        for (uint256 i = 0; i < 35; i++) {
            _vote(signers[i], AetherGovernance.VoteOption.FOR);
        }
        _vote(signers[35], AetherGovernance.VoteOption.AGAINST);
        _vote(signers[36], AetherGovernance.VoteOption.ABSTAIN);
        _vote(signers[37], AetherGovernance.VoteOption.ABSTAIN);

        (
            bool wouldPass,
            AetherGovernance.ChamberStance consensus,
            bool quorumMet,
            bool veto,
            uint256 forW,
            uint256 againstW
        ) = gov.simulateFinalize(pid);

        assertTrue(wouldPass);
        assertEq(uint8(consensus), uint8(AetherGovernance.ChamberStance.FOR));
        assertTrue(quorumMet);
        assertFalse(veto);
        assertGt(forW, againstW);

        _warpPastVoting();
        gov.finalizeProposal(pid);

        AetherGovernance.Proposal memory p = gov.getProposal(pid);
        assertEq(p.totalForWeighted, forW);
        assertEq(p.totalAgainstWeighted, againstW);
    }

    // ═══════════════════════════════════════════════════════════
    //                    权重验证
    // ═══════════════════════════════════════════════════════════

    function test_InternalWeight_SpeakerDominatesParliament() public {
        uint256 pid = _createProposal();

        _vote(parliamentSpeaker, AetherGovernance.VoteOption.FOR); // 权重 20

        // 铸 9 个新议员（议院席位上限 20，可容纳）
        for (uint256 i = 0; i < 9; i++) {
            address m = makeAddr(string(abi.encodePacked("mp", i)));
            ring.mintRing(m, AetherRing.RingTier.PARLIAMENT_MEMBER, "");
            gov.grantProposerRole(m);
            vm.prank(m);
            gov.castVote(pid, AetherGovernance.VoteOption.AGAINST); // 各权重 2，总 18
        }

        _vote(federationMinister, AetherGovernance.VoteOption.FOR);
        _vote(senateElder, AetherGovernance.VoteOption.FOR);

        for (uint256 i = 0; i < 40; i++) {
            _vote(signers[i], AetherGovernance.VoteOption.FOR);
        }

        _warpPastVoting();
        gov.finalizeProposal(pid);

        AetherGovernance.Proposal memory p = gov.getProposal(pid);
        // 议会立场：FOR（20 vs 18）
        assertEq(uint8(p.chamberConsensus), uint8(AetherGovernance.ChamberStance.FOR));
        assertEq(uint8(p.status), uint8(AetherGovernance.ProposalStatus.Queued));
    }

    // ═══════════════════════════════════════════════════════════
    //                    cancel
    // ═══════════════════════════════════════════════════════════

    function test_CancelProposal_AdminOnly() public {
        uint256 pid = _createProposal();

        vm.prank(parliamentSpeaker);
        vm.expectRevert();
        gov.cancelProposal(pid);

        gov.cancelProposal(pid);
        AetherGovernance.Proposal memory p = gov.getProposal(pid);
        assertEq(uint8(p.status), uint8(AetherGovernance.ProposalStatus.Canceled));
        assertTrue(p.isFinalized);
    }

    // ═══════════════════════════════════════════════════════════
    // ═══════════════════════════════════════════════════════════
    //                  v2 新增：IMPEACHMENT 弹劾全流程
    // ═══════════════════════════════════════════════════════════
    // ═══════════════════════════════════════════════════════════

    function test_Impeachment_Create_Success() public {
        vm.prank(members[0]); // 任何会员可发起
        uint256 pid = gov.createImpeachmentProposal(
            parliamentSpeaker, "Impeach Speaker", "ipfs://impeach"
        );

        assertEq(pid, 0);
        (, , , , , , , AetherGovernance.ProposalStatus status, , , , address target, uint256 curSig, uint256 reqSig) =
            gov.getProposal(pid);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.Drafting));
        assertEq(target, parliamentSpeaker);
        assertEq(curSig, 0);
        assertEq(reqSig, 100);
    }

    function test_Impeachment_Create_RevertWhen_TargetNotHighTier() public {
        // 弹劾目标必须是 tier 3/6/9，弹劾议员（tier 1）应 revert
        vm.prank(members[0]);
        vm.expectRevert(AetherGovernance.ImpeachmentTargetInvalid.selector);
        gov.createImpeachmentProposal(parliamentMember1, "x", "ipfs://x");
    }

    function test_Impeachment_Create_RevertWhen_TargetZeroAddress() public {
        vm.prank(members[0]);
        vm.expectRevert(AetherGovernance.ImpeachmentTargetInvalid.selector);
        gov.createImpeachmentProposal(address(0), "x", "ipfs://x");
    }

    function test_Impeachment_Sign_Success() public {
        vm.prank(members[0]);
        uint256 pid = gov.createImpeachmentProposal(parliamentSpeaker, "x", "ipfs://x");

        vm.prank(signers[0]);
        gov.signImpeachment(pid);

        assertTrue(gov.hasSigned(pid, signers[0]));
        (, , , , , , , , , , , , uint256 curSig,) = gov.getProposal(pid);
        assertEq(curSig, 1);
    }

    function test_Impeachment_Sign_RevertWhen_AlreadySigned() public {
        vm.prank(members[0]);
        uint256 pid = gov.createImpeachmentProposal(parliamentSpeaker, "x", "ipfs://x");

        vm.prank(signers[0]);
        gov.signImpeachment(pid);

        vm.prank(signers[0]);
        vm.expectRevert(AetherGovernance.AlreadySigned.selector);
        gov.signImpeachment(pid);
    }

    function test_Impeachment_Sign_RevertWhen_NotMember() public {
        // tier 1-9 不能联署
        vm.prank(members[0]);
        uint256 pid = gov.createImpeachmentProposal(parliamentSpeaker, "x", "ipfs://x");

        vm.prank(parliamentMember1); // tier=1
        vm.expectRevert(AetherGovernance.NotEligibleSigner.selector);
        gov.signImpeachment(pid);
    }

    function test_Impeachment_Sign_AutoTransitionTo_Multisig() public {
        vm.prank(members[0]);
        uint256 pid = gov.createImpeachmentProposal(parliamentSpeaker, "x", "ipfs://x");

        // 100 个会员联署
        for (uint256 i = 0; i < 100; i++) {
            vm.prank(signers[i]);
            gov.signImpeachment(pid);
        }

        // 联署满 100 → 自动进入 PendingMultisig
        (, , , , , , , AetherGovernance.ProposalStatus status,,,,) = gov.getProposal(pid);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.PendingMultisig));
    }

    function test_Impeachment_Sign_RevertWhen_NotDrafting() public {
        vm.prank(members[0]);
        uint256 pid = gov.createImpeachmentProposal(parliamentSpeaker, "x", "ipfs://x");

        // 联署满 100 → PendingMultisig
        for (uint256 i = 0; i < 100; i++) {
            vm.prank(signers[i]);
            gov.signImpeachment(pid);
        }

        // 第 101 个签（不存在，但状态已是 PendingMultisig → NotDrafting）
        vm.prank(members[0]);
        vm.expectRevert(AetherGovernance.NotDrafting.selector);
        gov.signImpeachment(pid);
    }

    function test_Impeachment_MultisigApprove_Success() public {
        vm.prank(members[0]);
        uint256 pid = gov.createImpeachmentProposal(parliamentSpeaker, "x", "ipfs://x");
        for (uint256 i = 0; i < 100; i++) {
            vm.prank(signers[i]);
            gov.signImpeachment(pid);
        }

        // 多签审查通过 → Active
        vm.prank(address(safe));
        gov.approveImpeachmentByMultisig(pid);

        (, , , , , , , AetherGovernance.ProposalStatus status,,,,) = gov.getProposal(pid);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.Active));
    }

    function test_Impeachment_MultisigApprove_RevertWhen_NotSafeWallet() public {
        vm.prank(members[0]);
        uint256 pid = gov.createImpeachmentProposal(parliamentSpeaker, "x", "ipfs://x");
        for (uint256 i = 0; i < 100; i++) {
            vm.prank(signers[i]);
            gov.signImpeachment(pid);
        }

        // 非 Safe 调 → revert
        vm.prank(members[0]);
        vm.expectRevert(abi.encodeWithSelector(AetherGovernance.NotSafeWallet.selector, members[0]));
        gov.approveImpeachmentByMultisig(pid);
    }

    function test_Impeachment_MultisigReject_CancelsProposal() public {
        vm.prank(members[0]);
        uint256 pid = gov.createImpeachmentProposal(parliamentSpeaker, "x", "ipfs://x");
        for (uint256 i = 0; i < 100; i++) {
            vm.prank(signers[i]);
            gov.signImpeachment(pid);
        }

        vm.prank(address(safe));
        gov.rejectImpeachmentByMultisig(pid);

        (, , , , , , , AetherGovernance.ProposalStatus status,,,,) = gov.getProposal(pid);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.Canceled));
    }

    function test_Impeachment_Vote_RevertWhen_BeforeMultisigApproved() public {
        vm.prank(members[0]);
        uint256 pid = gov.createImpeachmentProposal(parliamentSpeaker, "x", "ipfs://x");
        // 联署未满 / 未多签审查 → Drafting 或 PendingMultisig 状态，投票应 revert
        vm.prank(signers[0]);
        vm.expectRevert(AetherGovernance.NotInVotingPeriod.selector);
        gov.castVote(pid, AetherGovernance.VoteOption.AGAINST);
    }

    function test_Impeachment_Vote_RevertWhen_NotMember() public {
        _setupApprovedImpeachment(parliamentSpeaker);
        uint256 pid = 0;

        // tier 1-9 不能投弹劾票
        vm.prank(parliamentMember1);
        vm.expectRevert(AetherGovernance.NotEligibleSigner.selector);
        gov.castVote(pid, AetherGovernance.VoteOption.AGAINST);
    }

    function test_Impeachment_FullFlow_Passes() public {
        // 完整流程：联署 100 → 多签批准 → 会员投票（≥50% 参与率 + ≥70% 反对率）→ 通过
        _setupApprovedImpeachment(parliamentSpeaker);
        uint256 pid = 0;

        // memberTotalSnapshot = 110（含 10 members + 100 signers）
        // 50% quorum = 55；70% against = 77
        // 投票：80 反对 / 10 赞成 / 5 弃权 = 95 人参与（86% > 50%）
        // 反对率 = 80/95 = 84% > 70% → 弹劾成立
        for (uint256 i = 0; i < 80; i++) {
            vm.prank(signers[i]);
            gov.castVote(pid, AetherGovernance.VoteOption.AGAINST);
        }
        for (uint256 i = 80; i < 90; i++) {
            vm.prank(signers[i]);
            gov.castVote(pid, AetherGovernance.VoteOption.FOR);
        }
        for (uint256 i = 90; i < 95; i++) {
            vm.prank(signers[i]);
            gov.castVote(pid, AetherGovernance.VoteOption.ABSTAIN);
        }

        _warpPastVoting();
        gov.finalizeProposal(pid);

        AetherGovernance.Proposal memory p = gov.getProposal(pid);
        assertEq(uint8(p.status), uint8(AetherGovernance.ProposalStatus.Queued));
        assertTrue(p.memberQuorumMet);
        assertTrue(p.memberVetoTriggered); // 反对率 ≥ 70%

        // execute 撤销道环
        vm.warp(block.timestamp + 24 hours + 1);
        uint256 ringIdBefore = ring.getRingId(parliamentSpeaker);
        assertGt(ringIdBefore, 0);

        gov.executeProposal(pid);

        // 道环被撤销
        assertEq(ring.getRingId(parliamentSpeaker), 0);
        assertFalse(ring.isBearer(parliamentSpeaker));
    }

    function test_Impeachment_Fails_LowParticipation() public {
        _setupApprovedImpeachment(parliamentSpeaker);
        uint256 pid = 0;

        // 只 30 人投票（30/110 = 27% < 50%）→ 不达参与率
        for (uint256 i = 0; i < 30; i++) {
            vm.prank(signers[i]);
            gov.castVote(pid, AetherGovernance.VoteOption.AGAINST);
        }

        _warpPastVoting();
        gov.finalizeProposal(pid);

        AetherGovernance.Proposal memory p = gov.getProposal(pid);
        assertEq(uint8(p.status), uint8(AetherGovernance.ProposalStatus.Defeated));
        assertFalse(p.memberQuorumMet);
    }

    function test_Impeachment_Fails_LowAgainstRate() public {
        _setupApprovedImpeachment(parliamentSpeaker);
        uint256 pid = 0;

        // 60 投票：40 反对 / 15 赞成 / 5 弃权 → 反对率 40/60 = 66.7% < 70% → 失败
        for (uint256 i = 0; i < 40; i++) {
            vm.prank(signers[i]);
            gov.castVote(pid, AetherGovernance.VoteOption.AGAINST);
        }
        for (uint256 i = 40; i < 55; i++) {
            vm.prank(signers[i]);
            gov.castVote(pid, AetherGovernance.VoteOption.FOR);
        }
        for (uint256 i = 55; i < 60; i++) {
            vm.prank(signers[i]);
            gov.castVote(pid, AetherGovernance.VoteOption.ABSTAIN);
        }

        _warpPastVoting();
        gov.finalizeProposal(pid);

        AetherGovernance.Proposal memory p = gov.getProposal(pid);
        assertEq(uint8(p.status), uint8(AetherGovernance.ProposalStatus.Defeated));
        assertTrue(p.memberQuorumMet); // 60/110 = 54% > 50%
        assertFalse(p.memberVetoTriggered); // 66.7% < 70%
    }

    function test_Impeachment_SimulateResult() public {
        _setupApprovedImpeachment(parliamentSpeaker);
        uint256 pid = 0;

        for (uint256 i = 0; i < 80; i++) {
            vm.prank(signers[i]);
            gov.castVote(pid, AetherGovernance.VoteOption.AGAINST);
        }
        for (uint256 i = 80; i < 90; i++) {
            vm.prank(signers[i]);
            gov.castVote(pid, AetherGovernance.VoteOption.FOR);
        }

        (bool wouldPass, bool quorumMet, bool vetoTriggered) = gov.simulateImpeachmentResult(pid);
        assertTrue(wouldPass);
        assertTrue(quorumMet);
        assertTrue(vetoTriggered);
    }

    // ═══════════════════════════════════════════════════════════
    //                       setSafeWallet
    // ═══════════════════════════════════════════════════════════

    function test_SetSafeWallet_Success() public {
        MockSafe newSafe = new MockSafe();
        vm.expectEmit(true, true, false, false);
        emit AetherGovernance.SafeWalletUpdated(address(safe), address(newSafe));
        gov.setSafeWallet(address(newSafe));
        assertEq(address(gov.safeWallet()), address(newSafe));
    }

    function test_SetSafeWallet_RevertWhen_NotAdmin() public {
        vm.prank(members[0]);
        vm.expectRevert();
        gov.setSafeWallet(address(0xBEEF));
    }

    // ═══════════════════════════════════════════════════════════
    //                       辅助：创建已批准的弹劾提案
    // ═══════════════════════════════════════════════════════════

    function _setupApprovedImpeachment(address target) internal {
        vm.prank(members[0]);
        uint256 pid = gov.createImpeachmentProposal(target, "Impeach", "ipfs://x");
        assertEq(pid, 0);

        // 100 联署
        for (uint256 i = 0; i < 100; i++) {
            vm.prank(signers[i]);
            gov.signImpeachment(pid);
        }

        // 多签批准
        vm.prank(address(safe));
        gov.approveImpeachmentByMultisig(pid);
    }
}

/**
 * @title MockSafe — Safe 多签 mock
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
