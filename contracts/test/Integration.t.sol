// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AetherRing} from "../src/AetherRing.sol";
import {IAetherRing} from "../src/interfaces/IAetherRing.sol";
import {AetherGovernance} from "../src/AetherGovernance.sol";
import {AetherElection, IAetherElection} from "../src/AetherElection.sol";
import {AetherDonation} from "../src/AetherDonation.sol";
import {ISafe} from "../src/interfaces/ISafe.sol";

/**
 * @title Integration Test — 跨合约端到端流程
 * @dev Phase 5 集成测试：验证 4 合约协同工作
 *
 * 测试矩阵（5 项，对应 V3_DEV_STEPS.md 步骤 5.2）：
 *   T5.1  完整提案流程：草案→一审→合规→公投→否决窗口→执行
 *   T5.2  完整弹劾流程：元老发起→3联署→公投→撤销道环
 *   T5.3  完整选举流程：创建→注册→理事会→议会审批→投票→finalize→晋升
 *   T5.4  完整捐款流程：mintDonation→铸公民道环→settle→3担保激活快速通道
 *   T5.5  跨合约角色权限校验
 */
contract IntegrationTest is Test {
    AetherRing ring;
    AetherGovernance gov;
    AetherElection election;
    AetherDonation donation;
    MockSafe safe;

    // ── 身份地址 ──
    address admin = address(this);
    address chair = address(0xCCA1); // 理事长 tier 12
    address parMember = address(0xAAA1); // 议员 tier 1
    address parSpeaker = address(0xAAA3); // 议长 tier 3
    address fedMember = address(0xBBB4); // 委员 tier 4
    address fedMinister = address(0xBBB6); // 执政 tier 6
    address tribJudge = address(0xCC17); // 法官 tier 7
    address tribChief = address(0xCC19); // 首席 tier 9
    address elder1 = address(0xE1D1); // 任命元老 1
    address elder2 = address(0xE1D2);
    address elder3 = address(0xE1D3);
    address citizen1 = address(0xC1D1);
    address citizen2 = address(0xC1D2);
    address citizen3 = address(0xC1D3);
    address citizen4 = address(0xC1D4);
    address citizen5 = address(0xC1D5);
    address newDonor = address(0xD0A1); // 新捐款人
    address paypalServer = address(0xBAD1); // PayPal webhook 服务端

    // ── 常量 ──
    uint256 constant DONATION_AMOUNT = 10 * 10 ** 6; // $10 USDC (6 decimals)

    function setUp() public {
        // ── 1. 部署 4 合约（按 Deploy.s.sol 顺序） ──
        ring = new AetherRing();
        safe = new MockSafe();
        ring.setSafeWallet(address(safe));

        gov = new AetherGovernance(address(ring));
        election = new AetherElection(address(ring));
        donation = new AetherDonation(address(ring), admin, admin); // treasury=admin 占位

        // ── 2. 交叉授权（与 Deploy.s.sol 一致） ──
        ring.grantRole(ring.ADMIN_ROLE(), address(gov));
        ring.grantRole(ring.ADMIN_ROLE(), address(election));
        ring.grantRole(ring.MINTER_ROLE(), address(election));
        ring.grantRole(ring.MINTER_ROLE(), address(donation));
        ring.grantRole(ring.GOVERNANCE_ROLE(), address(gov));
        ring.grantRole(ring.ELECTION_ROLE(), address(election));

        // ── 3. 铸造初始道环 ──
        ring.grantRole(ring.MINTER_ROLE(), address(this));
        ring.mintRing(chair, AetherRing.RingTier.COUNCIL_CHAIR, "");
        ring.mintRing(parMember, AetherRing.RingTier.PARLIAMENT_MEMBER, "");
        ring.mintRing(parSpeaker, AetherRing.RingTier.PARLIAMENT_SPEAKER, "");
        ring.mintRing(fedMember, AetherRing.RingTier.FEDERATION_MEMBER, "");
        ring.mintRing(fedMinister, AetherRing.RingTier.FEDERATION_MINISTER, "");
        ring.mintRing(tribJudge, AetherRing.RingTier.TRIBUNAL_JUDGE, "");
        ring.mintRing(tribChief, AetherRing.RingTier.TRIBUNAL_CHIEF, "");
        ring.mintRing(citizen1, AetherRing.RingTier.CITIZEN, "");
        ring.mintRing(citizen2, AetherRing.RingTier.CITIZEN, "");
        ring.mintRing(citizen3, AetherRing.RingTier.CITIZEN, "");
        ring.mintRing(citizen4, AetherRing.RingTier.CITIZEN, "");
        ring.mintRing(citizen5, AetherRing.RingTier.CITIZEN, "");

        // ── 4. 任命 3 位元老（通过 Safe 多签 mock） ──
        vm.prank(address(safe));
        ring.appointElder(elder1, "");
        vm.prank(address(safe));
        ring.appointElder(elder2, "");
        vm.prank(address(safe));
        ring.appointElder(elder3, "");

        // ── 5. governance/election 角色配置 ──
        gov.grantRole(gov.PROPOSER_ROLE(), fedMember);
        election.grantCouncilChairRole(chair);

        // ── 6. donation 授权 PayPal webhook 服务端 ──
        donation.grantRole(donation.MINTER_ROLE(), paypalServer);
    }

    // ═══════════════════════════════════════════════════════════
    //  T5.1 完整提案流程：草案→一审→合规→公投→否决窗口→执行
    // ═══════════════════════════════════════════════════════════

    function test_FullProposalFlow_DraftToExecute() public {
        // 1. 联邦委员创建 SIGNAL 提案
        vm.prank(fedMember);
        uint256 id = gov.createProposal(
            AetherGovernance.ProposalType.SIGNAL,
            "Integration Test Proposal",
            "ipfs://QmTest",
            address(0),
            "",
            false, // 非章程修订
            AetherGovernance.TreasuryUrgency.Normal
        );

        // 2. 理事长推进至一审
        vm.prank(chair);
        gov.advanceProposal(id);

        // 3. 议会一审
        gov.startFirstVote(id);
        vm.prank(parMember);
        gov.castFirstVote(id, AetherGovernance.VoteOption.FOR);

        // 4. 一审结束（5 天）
        vm.warp(block.timestamp + 5 days + 1);
        gov.finalizeFirstVote(id);

        // 5. 正式提交 + 法庭合规
        vm.prank(fedMember);
        gov.submitFormalProposal(id);
        vm.prank(tribJudge);
        gov.castComplianceVote(id, AetherGovernance.VoteOption.FOR);

        // 6. 合规结束（3 天）→ 进入公投
        vm.warp(block.timestamp + 3 days + 1);
        gov.finalizeCompliance(id);

        // 7. 公投（三院 + 公民全部 FOR）
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

        // 8. 公投结束（7 天）→ PendingVeto
        vm.warp(block.timestamp + 7 days + 1);
        gov.finalizeProposal(id);

        // 9. 元老否决窗口超时（72h）→ Queued
        vm.warp(block.timestamp + 72 hours + 1);
        gov.finalizeVetoWindow(id);

        // 10. Timelock 到期（48h）→ 执行
        vm.warp(block.timestamp + 48 hours + 1);
        gov.executeProposal(id);

        (,,,,, AetherGovernance.ProposalStatus status,,,,,,,,,,,,,) = gov.getProposal(id);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.Executed));
    }

    // ═══════════════════════════════════════════════════════════
    //  T5.2 完整弹劾流程：元老发起→3联署→公投→撤销道环
    // ═══════════════════════════════════════════════════════════

    function test_FullImpeachmentFlow() public {
        // 目标：弹劾 fedMember（tier 4）
        uint256 targetRingId = ring.getRingId(fedMember);
        assertEq(uint8(ring.getTier(fedMember)), 4);

        // 1. 元老 1 发起弹劾
        vm.prank(elder1);
        uint256 id = gov.createImpeachmentProposal(fedMember, "Impeach fedMember", "ipfs://impeach");

        // 2. 元老 2、3 联署
        vm.prank(elder2);
        gov.signImpeachment(id);
        vm.prank(elder3);
        gov.signImpeachment(id);

        // 联署满 3 → 进入公投
        (,,,,, AetherGovernance.ProposalStatus status,,,,,,,,,,,,,) = gov.getProposal(id);
        assertEq(uint8(status), uint8(AetherGovernance.ProposalStatus.PublicVoteActive));

        // 3. 公民投票（弹劾：FOR=支持弹劾，AGAINST=反对弹劾）
        // 弹劾通过需：参与率 ≥40% + 反对率 ≥60%
        // citizenTotalSnapshot = 5（5 个公民），需 ≥2 人参与
        vm.prank(citizen1);
        gov.castPublicVote(id, AetherGovernance.VoteOption.AGAINST); // 反对弹劾
        vm.prank(citizen2);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR); // 支持弹劾
        vm.prank(citizen3);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR); // 支持弹劾
        vm.prank(citizen4);
        gov.castPublicVote(id, AetherGovernance.VoteOption.FOR); // 支持弹劾

        // 4. 公投结束（7 天）→ finalizeImpeachment
        vm.warp(block.timestamp + 7 days + 1);
        gov.finalizeImpeachment(id);

        // 5. 验证：fedMember 的道环已被撤销
        assertEq(uint8(ring.getTier(fedMember)), 0);
        assertEq(ring.getRingId(fedMember), 0);

        (,,,,, AetherGovernance.ProposalStatus status2,,,,,,,,,,,,,) = gov.getProposal(id);
        assertEq(uint8(status2), uint8(AetherGovernance.ProposalStatus.Executed));
    }

    // ═══════════════════════════════════════════════════════════
    //  T5.3 完整选举流程：创建→注册→理事会→议会审批→投票→finalize→晋升
    // ═══════════════════════════════════════════════════════════

    function test_FullElectionFlow() public {
        // 1. 创建 MEMBER_TO_GRASSROOTS 选举（议会基层，2 席）
        uint256 id = election.createElection(
            IAetherElection.ElectionType.MEMBER_TO_GRASSROOTS,
            1, // 议会
            IAetherElection.CouncilTargetTier.CouncilMember,
            2
        );

        // 2. 公民注册为候选人
        vm.prank(citizen1);
        election.registerCandidate(id);
        vm.prank(citizen2);
        election.registerCandidate(id);
        vm.prank(citizen3);
        election.registerCandidate(id);

        // 3. 注册期结束（7 天）→ 理事会整理
        vm.warp(block.timestamp + 7 days + 1);
        election.advanceToCouncilReview(id);

        // 4. 理事长批准全部 3 个候选人
        vm.prank(chair);
        election.approveCandidate(id, citizen1);
        vm.prank(chair);
        election.approveCandidate(id, citizen2);
        vm.prank(chair);
        election.approveCandidate(id, citizen3);

        // 5. 理事会期结束（3 天）→ 议会审批
        vm.warp(block.timestamp + 3 days + 1);
        election.advanceToParliamentApproval(id);

        // 6. 议员批准（阈值=1）
        vm.prank(parMember);
        election.parliamentApproveCandidateList(id);

        // 7. 公民投票：citizen4 → citizen1, citizen5 → citizen1
        vm.prank(citizen4);
        election.castVote(id, citizen1);
        vm.prank(citizen5);
        election.castVote(id, citizen1);

        // 8. 投票期结束（7 天）→ finalize
        vm.warp(block.timestamp + 7 days + 1);
        election.finalizeElection(id);

        // 9. 验证：citizen1 当选并晋升为 PARLIAMENT_MEMBER (tier 1)
        assertEq(uint8(ring.getTier(citizen1)), uint8(AetherRing.RingTier.PARLIAMENT_MEMBER));

        address[] memory winners = election.getWinners(id);
        assertEq(winners.length, 2);
        assertEq(winners[0], citizen1);

        (, IAetherElection.ElectionStatus status,,,,,, ) = election.getElection(id);
        assertEq(uint8(status), uint8(IAetherElection.ElectionStatus.Finalized));
    }

    // ═══════════════════════════════════════════════════════════
    //  T5.4 完整捐款流程：mintDonation→铸公民道环→settle→3担保激活快速通道
    // ═══════════════════════════════════════════════════════════

    function test_DonationFlow_FirstDonation() public {
        // 验证初始状态：newDonor 无道环
        assertEq(ring.getRingId(newDonor), 0);

        // 1. PayPal 服务端铸造捐款凭证（newDonor 首次捐款）
        bytes32 paypalHash = keccak256("paypal-payer-id-001");
        vm.prank(paypalServer);
        uint256 tokenId = donation.mintDonation(newDonor, DONATION_AMOUNT, "PP-TX-001", paypalHash);

        // 2. 验证：newDonor 自动获得公民道环
        assertEq(uint8(ring.getTier(newDonor)), uint8(AetherRing.RingTier.CITIZEN));
        assertTrue(ring.getRingId(newDonor) != 0);

        // 3. 多签结算（admin 占位）
        donation.settleDonation(tokenId, DONATION_AMOUNT);

        // 4. 3 个公民担保激活快速通道（此处验证担保流程，fastTrack 主要用于审计）
        vm.prank(citizen1);
        donation.sponsorDonation(tokenId);
        vm.prank(citizen2);
        donation.sponsorDonation(tokenId);
        vm.prank(citizen3);
        donation.sponsorDonation(tokenId);

        // 5. 验证：快速通道已激活
        AetherDonation.Donation memory d = donation.getDonation(tokenId);
        assertTrue(d.fastTrackActivated);
        assertEq(d.sponsorCount, 3);
        assertTrue(d.isSettled);
    }

    // ═══════════════════════════════════════════════════════════
    //  T5.5 跨合约角色权限校验
    // ═══════════════════════════════════════════════════════════

    function test_CrossContract_RoleEnforcement() public {
        // 1. governance 无 ring.ADMIN_ROLE 时不能 revokeRing
        //    （此处已授权，验证授权生效）
        assertTrue(ring.hasRole(ring.ADMIN_ROLE(), address(gov)));

        // 2. election 无 ring.MINTER_ROLE 时不能 mintRing
        assertTrue(ring.hasRole(ring.MINTER_ROLE(), address(election)));

        // 3. donation 无 ring.MINTER_ROLE 时不能 mintRing
        assertTrue(ring.hasRole(ring.MINTER_ROLE(), address(donation)));

        // 4. 非任命元老不能发起弹劾
        vm.expectRevert(AetherGovernance.NotAppointedElder.selector);
        vm.prank(citizen1);
        gov.createImpeachmentProposal(fedMember, "Should fail", "ipfs");

        // 5. 退休元老不能发起弹劾（先制造一个退休元老）
        vm.prank(address(safe));
        ring.retireToEmeritus(ring.getRingId(fedMinister)); // 执政退休转元老
        assertTrue(ring.isRetiredElder(fedMinister));
        assertFalse(ring.isElderActive(fedMinister));

        vm.expectRevert(AetherGovernance.NotAppointedElder.selector);
        vm.prank(fedMinister);
        gov.createImpeachmentProposal(fedMember, "Should fail", "ipfs");

        // 6. 非理事会长不能 approveCandidate
        uint256 id = election.createElection(
            IAetherElection.ElectionType.MEMBER_TO_GRASSROOTS,
            1,
            IAetherElection.CouncilTargetTier.CouncilMember,
            1
        );
        vm.prank(citizen1);
        election.registerCandidate(id);
        vm.warp(block.timestamp + 7 days + 1);
        election.advanceToCouncilReview(id);

        vm.expectRevert();
        vm.prank(citizen2);
        election.approveCandidate(id, citizen1);
    }
}

/**
 * @title MockSafe — Safe 多签 mock（与 AetherRing.t.sol 中一致）
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
