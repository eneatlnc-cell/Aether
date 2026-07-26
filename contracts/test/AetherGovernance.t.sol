// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AetherRing} from "../src/AetherRing.sol";
import {IAetherRing} from "../src/interfaces/IAetherRing.sol";
import {AetherGovernance} from "../src/AetherGovernance.sol";

/**
 * @title AetherGovernance v3 Test
 * @dev 覆盖 30 个测试用例（对应 V3_DEV_STEPS.md 步骤 3.15）
 *
 * 测试矩阵：
 *   T3.1-T3.2   提案创建权限
 *   T3.3-T3.5   理事会推进/退回
 *   T3.6-T3.7   议会一审
 *   T3.8-T3.9   法庭合规审查
 *   T3.10-T3.11 公投投票权限
 *   T3.12-T3.14 finalize 计票
 *   T3.15-T3.18 元老否决
 *   T3.19-T3.20 执行
 *   T3.21-T3.24 弹劾
 *   T3.25-T3.27 信任投票
 *   T3.28-T3.29 状态转换
 *   T3.30       端到端流程
 */
contract AetherGovernanceTest is Test {
    AetherRing ring;
    AetherGovernance gov;

    // ── 测试地址 ──
    address admin = address(this);
    address fedMember = address(0xFED1); // tier 4 委员（联邦基层）
    address parMember = address(0xAAA1); // tier 1 议员（议会基层）
    address parSpeaker = address(0xAAA3); // tier 3 议长
    address tribJudge = address(0xBB17); // tier 7 法官
    address tribChief = address(0xBB19); // tier 9 首席
    address councilMember1 = address(0xC101);
    address councilMember2 = address(0xC102);
    address councilChair = address(0xC120); // tier 12 理事长
    address elder1 = address(0xE101);
    address elder2 = address(0xE102);
    address elder3 = address(0xE103);
    address citizen1 = address(0xC1D1);
    address citizen2 = address(0xC1D2);
    address citizen3 = address(0xC1D3);
    address citizen4 = address(0xC1D4);
    address citizen5 = address(0xC1D5);
    address nonMember = address(0x0FF1);

    function setUp() public {
        ring = new AetherRing();
        gov = new AetherGovernance(address(ring));

        // 授权 gov 调 ring 的 markVoteActivity + revokeRing
        ring.grantRole(ring.GOVERNANCE_ROLE(), address(gov));
        ring.grantRole(ring.ADMIN_ROLE(), address(gov));

        // 铸道环
        ring.mintRing(fedMember, IAetherRing.RingTier.FEDERATION_MEMBER, "");
        ring.mintRing(parMember, IAetherRing.RingTier.PARLIAMENT_MEMBER, "");
        ring.mintRing(parSpeaker, IAetherRing.RingTier.PARLIAMENT_SPEAKER, "");
        ring.mintRing(tribJudge, IAetherRing.RingTier.TRIBUNAL_JUDGE, "");
        ring.mintRing(tribChief, IAetherRing.RingTier.TRIBUNAL_CHIEF, "");
        ring.mintRing(councilMember1, IAetherRing.RingTier.COUNCIL_MEMBER, "");
        ring.mintRing(councilMember2, IAetherRing.RingTier.COUNCIL_MEMBER, "");
        ring.mintRing(councilChair, IAetherRing.RingTier.COUNCIL_CHAIR, "");

        // 任命元老（通过 setSafeWallet + appointElder）
        // appointElder 用 onlyRole(ADMIN_ROLE)，测试合约 address(this) 持有 ADMIN_ROLE（构造时授予），
        // 这里直接由 address(this) 调用；retireToEmeritus 仍要求 Safe
        // 使用已部署的 gov 合约地址作为 safeWallet（setSafeWallet 要求地址有代码）
        ring.setSafeWallet(address(gov));
        ring.appointElder(elder1, "");
        ring.appointElder(elder2, "");
        ring.appointElder(elder3, "");

        // 铸公民道环
        ring.mintRing(citizen1, IAetherRing.RingTier.CITIZEN, "");
        ring.mintRing(citizen2, IAetherRing.RingTier.CITIZEN, "");
        ring.mintRing(citizen3, IAetherRing.RingTier.CITIZEN, "");
        ring.mintRing(citizen4, IAetherRing.RingTier.CITIZEN, "");
        ring.mintRing(citizen5, IAetherRing.RingTier.CITIZEN, "");

        // 给 fedMember 授 PROPOSER_ROLE
        gov.grantProposerRole(fedMember);
        gov.grantProposerRole(parMember);
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.1  tier 4（联邦基层）创建成功
    // ═══════════════════════════════════════════════════════════
    function test_CreateProposal_FederationMember_Success() public {
        vm.prank(fedMember);
        uint256 id = gov.createProposal(
            AetherGovernance.ProposalType.SIGNAL, "Test", "ipfs", address(0), "", false, AetherGovernance.TreasuryUrgency.Normal
        );
        assertEq(id, 0);

        (, , , , , AetherGovernance.ProposalStatus status, , , , , , , , , , , , , ) = gov.getProposal(id);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.Drafting));
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.2  tier 14（公民）创建 revert
    // ═══════════════════════════════════════════════════════════
    function test_CreateProposal_Citizen_Revert() public {
        gov.grantProposerRole(citizen1);
        vm.prank(citizen1);
        vm.expectRevert(AetherGovernance.NotChamberMember.selector);
        gov.createProposal(
            AetherGovernance.ProposalType.SIGNAL, "Test", "ipfs", address(0), "", false, AetherGovernance.TreasuryUrgency.Normal
        );
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.3  理事长推进
    // ═══════════════════════════════════════════════════════════
    function test_AdvanceProposal_OnlyChair_Success() public {
        vm.prank(fedMember);
        uint256 id = gov.createProposal(
            AetherGovernance.ProposalType.SIGNAL, "Test", "ipfs", address(0), "", false, AetherGovernance.TreasuryUrgency.Normal
        );

        vm.prank(councilChair);
        gov.advanceProposal(id);

        (, , , , , AetherGovernance.ProposalStatus status, , , , , , , , , , , , , ) = gov.getProposal(id);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.PendingFirstVote));
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.4  非理事长推进 revert
    // ═══════════════════════════════════════════════════════════
    function test_AdvanceProposal_NonChair_Revert() public {
        vm.prank(fedMember);
        uint256 id = gov.createProposal(
            AetherGovernance.ProposalType.SIGNAL, "Test", "ipfs", address(0), "", false, AetherGovernance.TreasuryUrgency.Normal
        );

        vm.prank(councilMember1);
        vm.expectRevert(AetherGovernance.NotCouncilChair.selector);
        gov.advanceProposal(id);
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.5  2 理事联署退回
    // ═══════════════════════════════════════════════════════════
    function test_ReturnProposal_2Signatures_TriggersReturn() public {
        vm.prank(fedMember);
        uint256 id = gov.createProposal(
            AetherGovernance.ProposalType.SIGNAL, "Test", "ipfs", address(0), "", false, AetherGovernance.TreasuryUrgency.Normal
        );

        vm.prank(councilMember1);
        gov.returnProposal(id);

        // 1 个签名还不够
        (, , , , , AetherGovernance.ProposalStatus status, , , , , , , , , , , , , ) = gov.getProposal(id);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.Drafting));

        vm.prank(councilMember2);
        gov.returnProposal(id);

        (, , , , , status, , , , , , , , , , , , , ) = gov.getProposal(id);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.ReturnedToDraft));
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.6  仅议会一审
    // ═══════════════════════════════════════════════════════════
    function test_FirstVote_ParliamentOnly() public {
        _advanceToFirstVote(0);

        // 联邦成员投票 → revert
        vm.prank(fedMember);
        vm.expectRevert(AetherGovernance.NotParliamentMember.selector);
        gov.castFirstVote(0, AetherGovernance.VoteOption.FOR);

        // 议会成员投票 → 成功
        vm.prank(parMember);
        gov.castFirstVote(0, AetherGovernance.VoteOption.FOR);
        assertTrue(gov.hasFirstVoted(0, parMember));
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.7  一审通过进 PendingFormal
    // ═══════════════════════════════════════════════════════════
    function test_FirstVote_Passes_ForGtAgainst() public {
        _advanceToFirstVote(0);

        vm.prank(parMember);
        gov.castFirstVote(0, AetherGovernance.VoteOption.FOR);

        vm.warp(block.timestamp + 5 days + 1);
        gov.finalizeFirstVote(0);

        (, , , , , AetherGovernance.ProposalStatus status, , , , , , , , , , , , , ) = gov.getProposal(0);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.PendingFormal));
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.8  仅法庭合规投票
    // ═══════════════════════════════════════════════════════════
    function test_ComplianceVote_TribunalOnly() public {
        _advanceToCompliance(0);

        // 议会成员投票 → revert
        vm.prank(parMember);
        vm.expectRevert(AetherGovernance.NotTribunalMember.selector);
        gov.castComplianceVote(0, AetherGovernance.VoteOption.FOR);

        // 法庭成员投票 → 成功
        vm.prank(tribJudge);
        gov.castComplianceVote(0, AetherGovernance.VoteOption.FOR);
        assertTrue(gov.hasComplianceVoted(0, tribJudge));
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.9  不合规退回 Draft
    // ═══════════════════════════════════════════════════════════
    function test_Compliance_Reject_ReturnsToDraft() public {
        _advanceToCompliance(0);

        // 法庭投反对
        vm.prank(tribJudge);
        gov.castComplianceVote(0, AetherGovernance.VoteOption.AGAINST);

        vm.warp(block.timestamp + 3 days + 1);
        gov.finalizeCompliance(0);

        (, , , , , AetherGovernance.ProposalStatus status, , , , , , , , , , , , , ) = gov.getProposal(0);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.ReturnedToDraft));
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.10 三院+公民投票
    // ═══════════════════════════════════════════════════════════
    function test_PublicVote_AllChambersAndCitizens() public {
        _advanceToPublicVote(0);

        vm.prank(parMember);
        gov.castPublicVote(0, AetherGovernance.VoteOption.FOR);
        vm.prank(fedMember);
        gov.castPublicVote(0, AetherGovernance.VoteOption.FOR);
        vm.prank(tribJudge);
        gov.castPublicVote(0, AetherGovernance.VoteOption.FOR);
        vm.prank(citizen1);
        gov.castPublicVote(0, AetherGovernance.VoteOption.FOR);

        assertTrue(gov.hasPublicVoted(0, parMember));
        assertTrue(gov.hasPublicVoted(0, citizen1));
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.11 理事会/元老公投 revert
    // ═══════════════════════════════════════════════════════════
    function test_PublicVote_CouncilAndElder_Revert() public {
        _advanceToPublicVote(0);

        vm.prank(councilMember1);
        vm.expectRevert(AetherGovernance.NotEligibleVoter.selector);
        gov.castPublicVote(0, AetherGovernance.VoteOption.FOR);

        vm.prank(elder1);
        vm.expectRevert(AetherGovernance.NotEligibleVoter.selector);
        gov.castPublicVote(0, AetherGovernance.VoteOption.FOR);
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.12 三院全 FOR + 公民 0% 参与 → quorum 未达失败
    // ═══════════════════════════════════════════════════════════
    function test_Finalize_AllChambersFOR_Citizen0Pct_Fails() public {
        _advanceToPublicVote(0);

        vm.prank(parMember);
        gov.castPublicVote(0, AetherGovernance.VoteOption.FOR);
        vm.prank(fedMember);
        gov.castPublicVote(0, AetherGovernance.VoteOption.FOR);
        vm.prank(tribJudge);
        gov.castPublicVote(0, AetherGovernance.VoteOption.FOR);

        vm.warp(block.timestamp + 7 days + 1);
        gov.finalizeProposal(0);

        (, , , , , AetherGovernance.ProposalStatus status, , , , , , , , , , , , , ) = gov.getProposal(0);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.Defeated));
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.13 三院全 FOR + 公民参与 + 通过
    // ═══════════════════════════════════════════════════════════
    function test_Finalize_AllFOR_Citizen30Pct_Passes() public {
        _advanceToPublicVote(0);

        // 5 个公民中 2 个投票（40% 参与，>20% quorum），全部 FOR
        vm.prank(parMember);
        gov.castPublicVote(0, AetherGovernance.VoteOption.FOR);
        vm.prank(fedMember);
        gov.castPublicVote(0, AetherGovernance.VoteOption.FOR);
        vm.prank(tribJudge);
        gov.castPublicVote(0, AetherGovernance.VoteOption.FOR);
        vm.prank(citizen1);
        gov.castPublicVote(0, AetherGovernance.VoteOption.FOR);
        vm.prank(citizen2);
        gov.castPublicVote(0, AetherGovernance.VoteOption.FOR);

        vm.warp(block.timestamp + 7 days + 1);
        gov.finalizeProposal(0);

        (, , , , , AetherGovernance.ProposalStatus status, , , , , , , , , , , , , ) = gov.getProposal(0);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.PendingVeto));
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.14 章程修订 quorum 50%
    // ═══════════════════════════════════════════════════════════
    function test_Finalize_Constitutional_Quorum50Pct() public {
        // 创建章程修订提案（isConstitutional=true, pType=PARAM）
        bytes memory payload = abi.encodeWithSelector(gov.setVotingPeriods.selector, 5 days, 7 days, 3 days);
        vm.prank(fedMember);
        uint256 id = gov.createProposal(
            AetherGovernance.ProposalType.PARAM, "Constitutional", "ipfs", address(0), payload, true, AetherGovernance.TreasuryUrgency.Normal
        );

        _advanceToPublicVote(id);

        // 5 个公民中 2 个投票（40% < 50% 章程 quorum）→ 失败
        vm.prank(parMember);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR);
        vm.prank(fedMember);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR);
        vm.prank(tribJudge);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR);
        vm.prank(citizen1);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR);
        vm.prank(citizen2);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR);

        vm.warp(block.timestamp + 7 days + 1);
        gov.finalizeProposal(id);

        (, , , , , AetherGovernance.ProposalStatus status, , , , , , , , , , , , , ) = gov.getProposal(id);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.Defeated));
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.15 3 任命元老否决
    // ═══════════════════════════════════════════════════════════
    function test_Veto_3AppointedElders_Cancels() public {
        _advanceToPendingVeto(0);

        vm.prank(elder1);
        gov.vetoProposal(0);
        vm.prank(elder2);
        gov.vetoProposal(0);
        vm.prank(elder3);
        gov.vetoProposal(0);

        (, , , , , AetherGovernance.ProposalStatus status, , , , , , , , , , , , , ) = gov.getProposal(0);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.Canceled));
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.16 退休元老否决 revert
    // ═══════════════════════════════════════════════════════════
    function test_Veto_RetiredElder_Revert() public {
        _advanceToPendingVeto(0);

        // 退休元老（先铸一个可退休的 tier 3 道环，再通过 safe 退休转元老）
        address retiredElder = address(0xEE04);
        ring.mintRing(retiredElder, IAetherRing.RingTier.PARLIAMENT_SPEAKER, "");
        vm.startPrank(address(gov));
        ring.retireToEmeritus(ring.getRingId(retiredElder));
        vm.stopPrank();

        vm.prank(retiredElder);
        vm.expectRevert(AetherGovernance.NotAppointedElder.selector);
        gov.vetoProposal(0);
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.17 弹劾不可否决
    // ═══════════════════════════════════════════════════════════
    function test_Veto_Impeachment_Revert() public {
        // 创建弹劾提案 → 联署 → 公投 → finalize → 会直接 Executed/Defeated
        // 弹劾不会进入 PendingVeto 状态，所以 vetoProposal 会因 status 检查 revert
        vm.prank(elder1);
        uint256 id = gov.createImpeachmentProposal(parMember, "Impeach", "ipfs");

        vm.prank(elder2);
        gov.signImpeachment(id);
        vm.prank(elder3);
        gov.signImpeachment(id);

        // 弹劾已进入 PublicVoteActive，不是 PendingVeto
        vm.prank(elder1);
        vm.expectRevert(AetherGovernance.NotPendingVeto.selector);
        gov.vetoProposal(id);
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.18 72h 超时进 Timelock
    // ═══════════════════════════════════════════════════════════
    function test_VetoWindow_72hTimeout_Queued() public {
        _advanceToPendingVeto(0);

        vm.warp(block.timestamp + 72 hours + 1);
        gov.finalizeVetoWindow(0);

        (, , , , , AetherGovernance.ProposalStatus status, , , , , , , , , , , , , ) = gov.getProposal(0);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.Queued));
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.19 Timelock 未到 revert
    // ═══════════════════════════════════════════════════════════
    function test_Execute_TimelockNotElapsed_Revert() public {
        _advanceToQueued(0);

        vm.expectRevert(AetherGovernance.TimelockNotElapsed.selector);
        gov.executeProposal(0);
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.20 紧急拨款 3 元老批准
    // ═══════════════════════════════════════════════════════════
    function test_Execute_EmergencyTreasury_3ElderApprovals() public {
        // 创建紧急拨款提案
        address target = address(0x7AB7);
        bytes memory payload = abi.encodeWithSignature("transfer(address,uint256)", address(1), 100);
        vm.prank(fedMember);
        uint256 id = gov.createProposal(
            AetherGovernance.ProposalType.TREASURY, "Emergency", "ipfs", target, payload, false, AetherGovernance.TreasuryUrgency.Emergency
        );

        _advanceToQueued(id);

        // 先跳过紧急 Timelock 12h，才能测到 EmergencyApprovalNotMet
        // （executeProposal 先检查 timelock 再检查 emergency approvals）
        skip(12 hours + 1);

        // 未获 3 元老批准 → revert
        vm.expectRevert(AetherGovernance.EmergencyApprovalNotMet.selector);
        gov.executeProposal(id);

        // 3 元老批准
        vm.prank(elder1);
        gov.approveEmergencyTreasury(id);
        vm.prank(elder2);
        gov.approveEmergencyTreasury(id);
        vm.prank(elder3);
        gov.approveEmergencyTreasury(id);

        // 执行（target 无代码但 call 仍返回 ok，提案状态变为 Executed）
        gov.executeProposal(id);
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.21 仅任命元老发起弹劾
    // ═══════════════════════════════════════════════════════════
    function test_Impeachment_Create_AppointedElderOnly() public {
        // 非元老发起 → revert
        vm.prank(fedMember);
        vm.expectRevert(AetherGovernance.NotAppointedElder.selector);
        gov.createImpeachmentProposal(parMember, "Impeach", "ipfs");

        // 任命元老发起 → 成功
        vm.prank(elder1);
        uint256 id = gov.createImpeachmentProposal(parMember, "Impeach", "ipfs");
        assertEq(id, 0);
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.22 3 联署进公投
    // ═══════════════════════════════════════════════════════════
    function test_Impeachment_3Signatures_ToPublicVote() public {
        vm.prank(elder1);
        uint256 id = gov.createImpeachmentProposal(parMember, "Impeach", "ipfs");

        vm.prank(elder2);
        gov.signImpeachment(id);

        // 2 签名还不够
        (, , , , , AetherGovernance.ProposalStatus status, , , , , , , , , , , , , ) = gov.getProposal(id);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.Drafting));

        vm.prank(elder3);
        gov.signImpeachment(id);

        (, , , , , status, , , , , , , , , , , , , ) = gov.getProposal(id);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.PublicVoteActive));
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.23 弹劾 30% quorum + 70% 支持率（FOR）→ 通过
    //  v3.1 修正：citizenFor（支持弹劾）≥ 70%，citizenAgainst 不再使用
    // ═══════════════════════════════════════════════════════════
    function test_Impeachment_30PctQuorum_70PctFor_Passes() public {
        vm.prank(elder1);
        uint256 id = gov.createImpeachmentProposal(parMember, "Impeach", "ipfs");
        vm.prank(elder2);
        gov.signImpeachment(id);
        vm.prank(elder3);
        gov.signImpeachment(id);

        // 5 公民中 3 个投票（60% 参与 > 30% quorum），其中 3 个 FOR（100% 支持率 ≥ 70%）
        vm.prank(citizen1);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR);
        vm.prank(citizen2);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR);
        vm.prank(citizen3);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR);

        vm.warp(block.timestamp + 7 days + 1);
        gov.finalizeImpeachment(id);

        (, , , , , AetherGovernance.ProposalStatus status, , , , , , , , , , , , , ) = gov.getProposal(id);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.Executed));
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.23b 弹劾：支持率不足 70% → 不通过（Defeated）
    // ═══════════════════════════════════════════════════════════
    function test_Impeachment_Below70PctFor_Defeated() public {
        vm.prank(elder1);
        uint256 id = gov.createImpeachmentProposal(parMember, "Impeach", "ipfs");
        vm.prank(elder2);
        gov.signImpeachment(id);
        vm.prank(elder3);
        gov.signImpeachment(id);

        // 4 公民投票（80% 参与 > 30%），2 FOR + 2 AGAINST（50% < 70%）
        vm.prank(citizen1);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR);
        vm.prank(citizen2);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR);
        vm.prank(citizen3);
        gov.castPublicVote(id, AetherGovernance.VoteOption.AGAINST);
        vm.prank(citizen4);
        gov.castPublicVote(id, AetherGovernance.VoteOption.AGAINST);

        vm.warp(block.timestamp + 7 days + 1);
        gov.finalizeImpeachment(id);

        (, , , , , AetherGovernance.ProposalStatus status, , , , , , , , , , , , , ) = gov.getProposal(id);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.Defeated));
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.23c 弹劾：参与率不足 30% → 不通过（Defeated）
    // ═══════════════════════════════════════════════════════════
    function test_Impeachment_Below30PctQuorum_Defeated() public {
        vm.prank(elder1);
        uint256 id = gov.createImpeachmentProposal(parMember, "Impeach", "ipfs");
        vm.prank(elder2);
        gov.signImpeachment(id);
        vm.prank(elder3);
        gov.signImpeachment(id);

        // 5 公民中仅 1 个投票（20% 参与 < 30% quorum）
        vm.prank(citizen1);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR);

        vm.warp(block.timestamp + 7 days + 1);
        gov.finalizeImpeachment(id);

        (, , , , , AetherGovernance.ProposalStatus status, , , , , , , , , , , , , ) = gov.getProposal(id);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.Defeated));
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.24 弹劾公民 revert
    // ═══════════════════════════════════════════════════════════
    function test_Impeachment_TargetCitizen_Revert() public {
        vm.prank(elder1);
        vm.expectRevert(AetherGovernance.ImpeachmentTargetInvalid.selector);
        gov.createImpeachmentProposal(citizen1, "Impeach", "ipfs");
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.25 8 理事联署触发信任投票
    // ═══════════════════════════════════════════════════════════
    function test_ConfidenceVote_8Signatures_Trigger() public {
        // 需要至少 8 个理事。当前只有 2 个 COUNCIL_MEMBER + 1 个 COUNCIL_CHAIR
        // COUNCIL_CHAIR(tier 12) 不参与信任投票签名（只有 tier 10/11 可签）
        // 需要铸更多理事
        address[] memory members = new address[](8);
        for (uint256 i = 0; i < 8; i++) {
            members[i] = address(uint160(0xC200 + i));
            ring.mintRing(members[i], IAetherRing.RingTier.COUNCIL_MEMBER, "");
        }

        // 8 理事签名
        for (uint256 i = 0; i < 8; i++) {
            vm.prank(members[i]);
            gov.signConfidenceTrigger(councilChair);
        }

        assertEq(gov.councilTriggerSignatures(councilChair), 8);

        // 触发信任投票
        gov.triggerConfidenceVote(councilChair, "reason");
        assertEq(gov.confidenceVoteCount(), 1);
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.26 仅理事投票
    // ═══════════════════════════════════════════════════════════
    function test_ConfidenceVote_CouncilOnly() public {
        // 先触发信任投票（简化：直接铸 8 理事签名）
        address[] memory members = new address[](8);
        for (uint256 i = 0; i < 8; i++) {
            members[i] = address(uint160(0xC300 + i));
            ring.mintRing(members[i], IAetherRing.RingTier.COUNCIL_MEMBER, "");
        }
        for (uint256 i = 0; i < 8; i++) {
            vm.prank(members[i]);
            gov.signConfidenceTrigger(councilChair);
        }
        gov.triggerConfidenceVote(councilChair, "reason");

        // 非理事投票 → revert
        vm.prank(citizen1);
        vm.expectRevert(AetherGovernance.NotCouncilMember.selector);
        gov.voteConfidence(0, true);

        // 理事投票 → 成功
        vm.prank(councilMember1);
        gov.voteConfidence(0, true);
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.27 不通过 30 天辞职
    // ═══════════════════════════════════════════════════════════
    function test_ConfidenceVote_NotPassed_30DayResign() public {
        address[] memory members = new address[](8);
        for (uint256 i = 0; i < 8; i++) {
            members[i] = address(uint160(0xC400 + i));
            ring.mintRing(members[i], IAetherRing.RingTier.COUNCIL_MEMBER, "");
        }
        for (uint256 i = 0; i < 8; i++) {
            vm.prank(members[i]);
            gov.signConfidenceTrigger(councilChair);
        }
        gov.triggerConfidenceVote(councilChair, "reason");

        // 只有 1 票支持，0 票反对 → 实际是通过（forVotes > againstVotes）
        // 要测试不通过，需要 against > for
        vm.prank(councilMember1);
        gov.voteConfidence(0, false); // 反对理事长
        vm.prank(councilMember2);
        gov.voteConfidence(0, false); // 反对理事长

        vm.warp(block.timestamp + 7 days + 1);
        gov.finalizeConfidence(0);

        // 检查 chairPendingResign 被设置
        assertGt(gov.chairPendingResign(councilChair), 0);
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.28 状态转换 Drafting → PendingFirstVote
    // ═══════════════════════════════════════════════════════════
    function test_StateTransition_DraftingToPendingFirst() public {
        vm.prank(fedMember);
        uint256 id = gov.createProposal(
            AetherGovernance.ProposalType.SIGNAL, "Test", "ipfs", address(0), "", false, AetherGovernance.TreasuryUrgency.Normal
        );

        (, , , , , AetherGovernance.ProposalStatus status, , , , , , , , , , , , , ) = gov.getProposal(id);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.Drafting));

        vm.prank(councilChair);
        gov.advanceProposal(id);

        (, , , , , status, , , , , , , , , , , , , ) = gov.getProposal(id);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.PendingFirstVote));
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.29 非法状态转换全 revert
    // ═══════════════════════════════════════════════════════════
    function test_StateTransition_Illegal_AllRevert() public {
        vm.prank(fedMember);
        uint256 id = gov.createProposal(
            AetherGovernance.ProposalType.SIGNAL, "Test", "ipfs", address(0), "", false, AetherGovernance.TreasuryUrgency.Normal
        );

        // 在 Drafting 状态调 startFirstVote → revert（需先 advance）
        vm.expectRevert(AetherGovernance.NotPendingFirstVote.selector);
        gov.startFirstVote(id);

        // 在 Drafting 状态调 castFirstVote → revert
        vm.prank(parMember);
        vm.expectRevert(AetherGovernance.NotFirstVoteActive.selector);
        gov.castFirstVote(id, AetherGovernance.VoteOption.FOR);

        // 在 Drafting 状态调 castPublicVote → revert
        vm.prank(parMember);
        vm.expectRevert(AetherGovernance.NotPublicVoteActive.selector);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR);

        // 在 Drafting 状态调 finalizeProposal → revert
        vm.expectRevert(AetherGovernance.NotPublicVoteActive.selector);
        gov.finalizeProposal(id);

        // 在 Drafting 状态调 vetoProposal → revert
        vm.prank(elder1);
        vm.expectRevert(AetherGovernance.NotPendingVeto.selector);
        gov.vetoProposal(id);
    }

    // ═══════════════════════════════════════════════════════════
    //  T3.30 端到端流程：提案 → 执行
    // ═══════════════════════════════════════════════════════════
    function test_FullFlow_ProposalToExecution() public {
        // 1. 创建 SIGNAL 提案
        vm.prank(fedMember);
        uint256 id = gov.createProposal(
            AetherGovernance.ProposalType.SIGNAL, "Full Flow", "ipfs", address(0), "", false, AetherGovernance.TreasuryUrgency.Normal
        );

        // 2. 理事长推进
        vm.prank(councilChair);
        gov.advanceProposal(id);

        // 3. 开始一审
        vm.prank(councilChair);
        gov.startFirstVote(id);

        // 4. 议会投票
        vm.prank(parMember);
        gov.castFirstVote(id, AetherGovernance.VoteOption.FOR);

        // 5. 一审结束
        vm.warp(block.timestamp + 5 days + 1);
        gov.finalizeFirstVote(id);

        // 6. 正式提交
        vm.prank(fedMember);
        gov.submitFormalProposal(id);

        // 7. 法庭合规投票
        vm.prank(tribJudge);
        gov.castComplianceVote(id, AetherGovernance.VoteOption.FOR);

        // 8. 合规结束 → 进入公投
        vm.warp(block.timestamp + 3 days + 1);
        gov.finalizeCompliance(id);

        // 9. 公投投票
        vm.prank(parMember);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR);
        vm.prank(fedMember);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR);
        vm.prank(tribJudge);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR);
        vm.prank(citizen1);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR);
        vm.prank(citizen2);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR);

        // 10. finalize → PendingVeto
        skip(7 days + 1);
        gov.finalizeProposal(id);

        (, , , , , AetherGovernance.ProposalStatus status, , , , , , , , , , , , , ) = gov.getProposal(id);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.PendingVeto));

        // 11. 72h 超时 → Queued
        skip(72 hours + 1);
        gov.finalizeVetoWindow(id);

        (, , , , , status, , , , , , , , , , , , , ) = gov.getProposal(id);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.Queued));

        // 12. Timelock 到期 → 执行
        skip(48 hours + 1);
        gov.executeProposal(id);

        (, , , , , status, , , , , , , , , , , , , ) = gov.getProposal(id);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.Executed));
    }

    // ═══════════════════════════════════════════════════════════
    //  辅助函数：推进到各阶段
    // ═══════════════════════════════════════════════════════════

    function _advanceToFirstVote(uint256 id) internal {
        vm.prank(fedMember);
        gov.createProposal(
            AetherGovernance.ProposalType.SIGNAL, "Test", "ipfs", address(0), "", false, AetherGovernance.TreasuryUrgency.Normal
        );
        vm.prank(councilChair);
        gov.advanceProposal(id);
        vm.prank(councilChair);
        gov.startFirstVote(id);
    }

    function _advanceToCompliance(uint256 id) internal {
        _advanceToFirstVote(id);
        vm.prank(parMember);
        gov.castFirstVote(id, AetherGovernance.VoteOption.FOR);
        vm.warp(block.timestamp + 5 days + 1);
        gov.finalizeFirstVote(id);
        vm.prank(fedMember);
        gov.submitFormalProposal(id);
    }

    function _advanceToPublicVote(uint256 id) internal {
        _advanceToCompliance(id);
        vm.prank(tribJudge);
        gov.castComplianceVote(id, AetherGovernance.VoteOption.FOR);
        vm.warp(block.timestamp + 3 days + 1);
        gov.finalizeCompliance(id);
    }

    function _advanceToPendingVeto(uint256 id) internal {
        _advanceToPublicVote(id);
        vm.prank(parMember);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR);
        vm.prank(fedMember);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR);
        vm.prank(tribJudge);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR);
        vm.prank(citizen1);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR);
        vm.prank(citizen2);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR);
        vm.warp(block.timestamp + 7 days + 1);
        gov.finalizeProposal(id);
    }

    function _advanceToQueued(uint256 id) internal {
        _advanceToPendingVeto(id);
        vm.warp(block.timestamp + 72 hours + 1);
        gov.finalizeVetoWindow(id);
    }
}
