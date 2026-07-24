# Aether DAO v3.0 全面安全审计报告

> **审计日期**：2026-07-24
> **审计范围**：4 个智能合约 + 5 个前端 hooks + 部署脚本 + 配置 + 集成测试
> **审计方法**：静态分析 + 状态机建模 + CEI 检查 + 权限矩阵 + ABI 一致性比对
> **结论**：发现 **3 个 Critical、11 个 High（含 v3.1 新增 H11）、12 个 Medium、9 个 Low/Info** 问题。Hooks 与 ABI 一致性良好；合约层与部署脚本存在阻断性缺陷，**主网部署前必须修复 Critical/High 项**。

---

## 一、严重程度分布

| 严重程度 | 数量 | 说明 |
|---|---|---|
| 🔴 Critical | 3（C2 已于 v3.1 修复）| 阻断核心功能，可导致资金损失或治理瘫痪 |
| 🟠 High | 10 + 1（H11 已于 v3.1 修复）| 严重安全漏洞或功能失效，主网前必须修复 |
| 🟡 Medium | 12 | 设计偏离或潜在风险，建议修复 |
| 🟢 Low / Info | 9 | 代码质量/文档/最佳实践问题 |

> **v3.1 修复批次**：
> - **C2** 弹劾计票语义反转（`citizenAgainst`→`citizenFor`）+ 阈值 40/60→30/70 ✅
> - **H11**（新增）加权计票权重总和 120% > 100% → 归一为 4998+5000=9998≈100%（50/50 制衡）✅

---

## 二、🔴 Critical 问题（3 项）

### C1. AetherRing `_nextTokenId` 初始值为 0，破坏哨兵约定

- **文件**：[contracts/src/AetherRing.sol](file:///workspace/contracts/src/AetherRing.sol#L113) (line 113, 221, 228, 231)
- **现象**：`uint256 private _nextTokenId;` 默认为 0。第一次 `mintRing` 返回 tokenId=0，但代码在多处用 `walletToRingId[addr] == 0` 作为"无道环"哨兵。
- **影响**：
  - 首个铸道环地址可**重复 mint**（AlreadyHasRing 检查 `walletToRingId[recipient] != 0` 对 0 失效）
  - tokenId=0 持有者 `isBearer`/`getTier`/`isEmeritus`/`isDormant` 全部返回 false（被视为无道环）
  - 无法 `renounceCitizenship`、`markVoteActivity` 不更新、`reactivateDormantCitizen` 失败
  - **跨合约传染**：AetherDonation.mintDonation 首次捐款 donor 拿到 tokenId=0，二次捐款时 `getRingId==0` 触发再次 mintRing；AetherElection._applyPromotion 同样重复铸道环
- **对比**：AetherDonation.sol:73 已正确写 `uint256 private _nextTokenId = 1;`，开发者知晓约定但未在 Ring 应用
- **修复**：
  ```solidity
  uint256 private _nextTokenId = 1; // 从 1 开始（0 表示"无"）
  ```

### C2. AetherGovernance 弹劾计票逻辑语义反转 ✅ 已修复 (v3.1)

- **文件**：[contracts/src/AetherGovernance.sol](file:///workspace/contracts/src/AetherGovernance.sol#L714-L715) (line 704-713)
- **现象（修复前）**：
  ```solidity
  // 注释：FOR=支持弹劾，AGAINST=反对弹劾
  bool passRateMet = citizenVotes > 0
      && ((p.citizenAgainst * BPS_DENOMINATOR) / citizenVotes >= IMPEACHMENT_PASS_BPS);
  ```
  注释自相矛盾（line 705 说 FOR=支持，line 707 说"通过=反对率≥60%"）。实际使用 `citizenAgainst` 判断通过，导致**当 60% 公民投票反对弹劾时弹劾反而通过**。
- **影响**：弹劾机制完全反转 — 无辜者易被弹劾、恶人无法被弹劾。
- **测试污染**：Integration.t.sol T5.2 (line 197-203) 依赖同一 bug，3 人支持 + 1 人反对时仍期望通过，需同步修正。
- **修复（v3.1 已实施）**：
  ```solidity
  // 弹劾计票：公民参与率 ≥30% + 支持率 ≥70%
  bool passRateMet = citizenVotes > 0
      && ((p.citizenFor * BPS_DENOMINATOR) / citizenVotes >= IMPEACHMENT_PASS_BPS);
  ```
  - `p.citizenAgainst` → `p.citizenFor`（修复语义反转）
  - `IMPEACHMENT_QUORUM_BPS`：4000 → **3000**（参与率门槛 40% → 30%）
  - `IMPEACHMENT_PASS_BPS`：6000 → **7000**（通过率门槛 60% → 70%，使用 citizenFor）
  - 测试 AetherGovernance.t.sol T3.23 重写为 `test_Impeachment_30PctQuorum_70PctFor_Passes`，
    新增 T3.23b（支持率不足 70% → Defeated）和 T3.23c（参与率不足 30% → Defeated）覆盖负面路径

### C3. Genesis.s.sol 任命元老完全未执行

- **文件**：[contracts/script/Genesis.s.sol](file:///workspace/contracts/script/Genesis.s.sol#L119-L140) (line 119-140)
- **现象**：脚本注释声称"任命元老 5 人"，但 line 123-139 仅 `console2.log` 文本输出，**没有调用 `ring.appointElder(...)`**。
- **影响**：部署后链上 `_appointedElderCount = 0`，所有依赖 `isElderActive` 的功能瘫痪：
  - 弹劾 `createImpeachmentProposal` / `signImpeachment`
  - 否决 `vetoProposal`
  - 紧急拨款 `approveEmergencyTreasury`
  - 信任投票 `signConfidenceTrigger`
- **修复**：在 `setSafeWallet` 之后实际调用 `ring.appointElder(elder_i, "")`；若 deployer 不持 Safe 单签，应 revert 并输出待签名 calldata 供 Safe 多签执行。

---

## 三、🟠 High 问题（11 项，含 v3.1 新增 H11）

### H1. executeProposal TREASURY 分支重入（CEI 违规）

- **文件**：[contracts/src/AetherGovernance.sol](file:///workspace/contracts/src/AetherGovernance.sol#L606-L628) (line 621, 625)
- **现象**：外部调用 `p.target.call{value: msg.value}(p.calldataPayload)` 在 `p.status = Executed` 之前。恶意 target 可在回调中重入，此时 status 仍为 Queued，状态检查通过，导致**双重转账**。
- **修复**：CEI 模式 — 外部调用前置 `p.status = Executed; p.isExecuted = true; emit ProposalExecuted(...)`；或引入 OpenZeppelin ReentrancyGuard。

### H2. PARAM 提案执行必然失败

- **文件**：[contracts/src/AetherGovernance.sol](file:///workspace/contracts/src/AetherGovernance.sol#L613-L616) + [line 281-285](file:///workspace/contracts/src/AetherGovernance.sol#L281-L285) + [line 935-949](file:///workspace/contracts/src/AetherGovernance.sol#L935-L949)
- **现象**：`executeProposal` 通过 `address(this).call(p.calldataPayload)` 调用 `setVotingPeriods` / `setTimelocks` / `setInternalWeight`，这些函数有 `onlyRole(ADMIN_ROLE)`，但构造函数未向 `address(this)` 授予 ADMIN_ROLE。
- **影响**：所有 PARAM 提案（含章程修订）永远 revert，治理参数无法通过提案修改。
- **修复**：构造函数末尾增加 `_grantRole(ADMIN_ROLE, address(this));`。

### H3. advanceProposal 缺 pType 校验，理事长可绕过 3 元老联署

- **文件**：[contracts/src/AetherGovernance.sol](file:///workspace/contracts/src/AetherGovernance.sol#L345-L352)
- **现象**：`advanceProposal` 仅校验 `status == Drafting`，不校验 `pType`。理事长可对 IMPEACHMENT 提案调用，推入 PendingFirstVote → ... → PublicVoteActive，最终 `finalizeImpeachment` 完成弹劾。
- **影响**：绕过 `IMPEACHMENT_SIGNATURES = 3` 设计，仅需 1 元老创建 + 1 理事长推进即可启动弹劾公投，破坏分权制衡。
- **修复**：`advanceProposal` 开头增加 `if (p.pType == ProposalType.IMPEACHMENT) revert UseCreateImpeachmentProposal();`，并在 startFirstVote / finalizeFirstVote / submitFormalProposal / finalizeCompliance 增加深度防御。

### H4. revokeRing 对 ELDER 道环下溢

- **文件**：[contracts/src/AetherRing.sol](file:///workspace/contracts/src/AetherRing.sol#L320-L337) (line 325)
- **现象**：ELDER (tier 13) 的 `_tierCount[13]` 从未被自增（mintRing 禁止铸 ELDER；appointElder/retireToEmeritus 显式跳过；updateTier 禁止升到 ELDER）。`revokeRing` 的 `_tierCount[uint8(info.tier)] -= 1` 在 Solidity 0.8+ 下对 ELDER revert。
- **影响**：`finalizeImpeachment` 弹劾元老时调 `revokeRing` 会 revert，**弹劾元老功能完全失效**。
- **修复**：`if (info.tier != RingTier.ELDER) { _tierCount[uint8(info.tier)] -= 1; }`

### H5. Treasury 占位风险

- **文件**：[contracts/script/Deploy.s.sol](file:///workspace/contracts/script/Deploy.s.sol#L56)
- **现象**：`address treasury = vm.envOr("TREASURY", deployer);` 未设置时用 deployer 占位，donation 合约记录的 treasury 实际指向 deployer。
- **影响**：部署者忘配环境变量时部署"成功"但资金记录错误，需事后 `setTreasury` 修正。
- **修复**：改为 `vm.envAddress("TREASURY")`（缺失即 revert），或显式警告。

### H6. 初始 10 公民未铸造

- **文件**：[contracts/script/Genesis.s.sol](file:///workspace/contracts/script/Genesis.s.sol#L113-L117)
- **现象**：循环体为空（全注释），直接 log "skip"。
- **影响**：测试网若依赖 Genesis 初始化公民，`getActiveCitizens()=0` 导致所有公投 `citizenTotalSnapshot=0`，`finalizeProposal` 中 `citizenQuorumMet` 永远 false，普通提案无法通过。
- **修复**：从环境变量读取地址并 `ring.mintRing(citizen, CITIZEN, "")`，或彻底删除并明确"公民身份仅通过捐款产生"。

### H7. PROPOSER_ROLE 授予理事长无效

- **文件**：[contracts/script/Genesis.s.sol](file:///workspace/contracts/script/Genesis.s.sol#L108)
- **现象**：`gov.grantRole(gov.PROPOSER_ROLE(), councilChair)` 授予理事长（tier 12）PROPOSER_ROLE，但 `createProposal` 修饰器 `onlyRole(PROPOSER_ROLE) onlyChamberMember`，`onlyChamberMember` 要求 `tier >= 1 && tier <= 9`，理事长 tier=12 不满足。
- **影响**：理事长持 PROPOSER_ROLE 但无法用，易误导运维。
- **修复**：删除该授予；理事长权限通过 `advanceProposal` / `returnProposal` 体现。

### H8. 4 合约 DEFAULT_ADMIN_ROLE 转移缺失

- **文件**：[contracts/script/Genesis.s.sol](file:///workspace/contracts/script/Genesis.s.sol)
- **现象**：脚本仅调 `ring.setSafeWallet(safeAddr)`，未执行任何 4 合约的 `DEFAULT_ADMIN_ROLE` 转移给 Safe。
- **影响**：deployer 永久持有所有合约最高权限，Safe 多签无法真正接管，中心化风险。
- **修复**：脚本末尾增加 4 个合约的 `grantRole(DEFAULT_ADMIN_ROLE, safeAddr)` + `grantRole(ADMIN_ROLE, safeAddr)`，并提示 deployer 后续 `renounceRole`。

### H9. DEPLOY.md 文档严重过时（v2 残留）

- **文件**：[DEPLOY.md](file:///workspace/DEPLOY.md#L182-L347) (line 94-117, 166-169, 182-193, 215-216, 324-347)
- **现象**：
  - 第 3 节"3 个合约"遗漏 Donation（实际 4 个）
  - tier 表残留 `SENATE_ADVISOR/FELLOW/ELDER` 与 `GENERAL_MEMBER`（v3 已改名）
  - 弹劾流程"100 名活跃会员联署"（v3 为 3 任命元老）
  - 提到已删除的 `approveImpeachmentByMultisig` / `REELECTION`
  - 指示对 Governance 调 `setSafeWallet`（合约无此函数，会 revert）
  - `getTotalMembers()` 已改名 `getTotalCitizens()`
  - `.env.local` 缺少 `NEXT_PUBLIC_AETHER_DONATION_ADDRESS`
- **影响**：部署者按文档操作频繁 revert，严重影响部署流程。
- **修复**：全面重写 DEPLOY.md 对齐 v3。

### H10. 捐款→投票→选举完整链路未串联测试

- **文件**：[contracts/test/Integration.t.sol](file:///workspace/contracts/test/Integration.t.sol)
- **现象**：T5.4 验证 newDonor 通过 mintDonation 获得公民道环，但未继续验证 newDonor 能参与治理投票或选举。T5.1/T5.2/T5.3 使用预铸的 citizen1-5。
- **影响**：跨合约端到端身份流转未验证，donation 铸的公民道环与 governance/election 资格检查不一致无法被测试捕获。
- **修复**：新增 `test_DonationToVoteToElection_ChainFlow` 覆盖完整链路。

### H11. 加权计票权重总和 120% > 100%（白皮书自相矛盾）✅ 已修复 (v3.1)

- **文件**：[contracts/src/AetherGovernance.sol](file:///workspace/contracts/src/AetherGovernance.sol#L166-L167) (line 162-164, 546-557)
- **现象（修复前）**：
  ```solidity
  uint256 public constant CHAMBER_WEIGHT_BPS = 2_000;  // 每院 20%
  uint256 public constant CITIZEN_WEIGHT_BPS = 6_000;  // 公民 60%
  // 三院全 FOR: 3 × 2000 = 6000 BPS
  // 公民 100%:  1.0 × 6000 = 6000 BPS
  // 最大总和:   6000 + 6000 = 12000 BPS = 120% > 100%
  ```
  白皮书与代码均声称"三院各 20%（共 60%）+ 公民 60%"，但 60% + 60% = 120%，权重未归一到 100%。
- **关键影响**：三院一致 FOR 即可达 6000 > 5000 通过门槛，**完全绕过公民**（仅需形式满足 quorum 即可），违背"公民 60% 主导"的设计初衷。
- **修复（v3.1 已实施）**：
  ```solidity
  uint256 public constant CHAMBER_WEIGHT_BPS = 1_666;  // 每院 ≈16.6%，三院合计 4998
  uint256 public constant CITIZEN_WEIGHT_BPS = 5_000;  // 公民 50%
  // 合计 4998 + 5000 = 9998 ≈ 10000（100%）
  // 三院全 FOR(4998) + 公民 0% = 4998 < 5000 → 三院无法独断
  // 公民 100%(5000) + 0 院 = 5000，不 > 5000 → 公民也无法独断
  // → 提案通过必须跨院 + 公民合作，体现 50/50 制衡
  ```

---

## 四、🟡 Medium 问题（12 项）

### M1. AetherDonation mintDonation 违反 CEI

- **文件**：[contracts/src/AetherDonation.sol](file:///workspace/contracts/src/AetherDonation.sol#L138-L191) (line 161-174)
- **现象**：`_safeMint` 后才写入 `_donations[tokenId]` 和 `_donorTokenIds[donor]`。donor 为合约时 onERC721Received 回调中可重入 sponsorDonation（会因 donor==address(0) revert，实际可利用性有限）。
- **修复**：将状态写入移到 `_safeMint` 之前，或改用 `_mint`。

### M2. paypalAccountHash 离链计算，单点信任

- **文件**：[contracts/src/AetherDonation.sol](file:///workspace/contracts/src/AetherDonation.sol#L138)
- **现象**：`paypalAccountHash` 由 MINTER_ROLE 传入，合约内不计算 `keccak256(payer_id)`。MINTER_ROLE 密钥泄露时可为同一 PayPal 账户传不同 hash 绕过防女巫。
- **修复**：合约接收 `payer_id` 并内部计算 hash；或文档明确 MINTER_ROLE 需多签保护。

### M3. PayPal TxId 跨链重放风险

- **文件**：[contracts/src/AetherDonation.sol](file:///workspace/contracts/src/AetherDonation.sol#L68)
- **现象**：`usedPaypalTxIds` 是链上 storage，多链部署时同一 TxId 可在每条链各 mint 一次。
- **修复**：TxId 编码 chainId，或跨链消息验证。

### M4. cancelProposal 无终态保护

- **文件**：[contracts/src/AetherGovernance.sol](file:///workspace/contracts/src/AetherGovernance.sol#L951-L955)
- **现象**：可对已 Executed/Defeated/Canceled 的提案再次 cancel，污染状态机。
- **修复**：`if (p.status == Executed || p.status == Canceled) revert AlreadyFinalized();`

### M5. setRingContract 无零地址检查（Governance / Election）

- **文件**：[contracts/src/AetherGovernance.sol](file:///workspace/contracts/src/AetherGovernance.sol#L919-L923) + [contracts/src/AetherElection.sol](file:///workspace/contracts/src/AetherElection.sol#L609-L613)
- **现象**：ADMIN_ROLE 可设 `ringContract = address(0)`，此后所有 ring 调用 revert，合约永久卡死。对比 AetherDonation.sol:321 已正确校验。
- **修复**：`if (_ring == address(0)) revert ZeroAddress();`

### M6. appointToVacancy 可任命被拒/未注册候选人

- **文件**：[contracts/src/AetherElection.sol](file:///workspace/contracts/src/AetherElection.sol#L487-L511)
- **现象**：仅检查 `c.won`，未检查 `c.isRejected` 和 `c.isNominated`。理事长可任命被理事会明确拒绝的人或从未注册的陌生人。
- **修复**：增加 `if (!c.isNominated) revert CandidateNotRegistered();` + `if (c.isRejected) revert CandidateAlreadyRejected();`

### M7. setRingActive 可激活到期道环

- **文件**：[contracts/src/AetherRing.sol](file:///workspace/contracts/src/AetherRing.sol#L339-L344)
- **现象**：ADMIN_ROLE 可将 `isExpired=true` 或 `block.timestamp >= termEndAt` 的道环设为 `isActive=true`。虽然 isBearer/getTier 综合检查会兜底，但破坏状态一致性。
- **修复**：`if (active && (info.isExpired || block.timestamp >= info.termEndAt)) revert ...;`

### M8. forceAdvanceToVoting 使议会审批形同虚设

- **文件**：[contracts/src/AetherElection.sol](file:///workspace/contracts/src/AetherElection.sol#L392-L402)
- **现象**：审批期结束后任何人可强制进入投票，即使 `parliamentApprovalCount == 0`。议会审批成为纯延迟机制，无法真正否决。
- **修复**：若设计为"未达阈值即取消"，应改逻辑；若为"防止拖延"，应在文档明确。

### M9. donation ADMIN_ROLE 未转交 Safe

- **文件**：[contracts/script/Deploy.s.sol](file:///workspace/contracts/script/Deploy.s.sol#L113)
- **现象**：donation 的 ADMIN_ROLE 与 DEFAULT_ADMIN_ROLE 仍持有 deployer，仅注释提示转移。
- **修复**：脚本末尾 `donation.grantRole(donation.DEFAULT_ADMIN_ROLE(), treasury)` + `grantRole(ADMIN_ROLE, treasury)`。

### M10. PayPal MINTER_ROLE 未配置

- **文件**：[contracts/script/Deploy.s.sol](file:///workspace/contracts/script/Deploy.s.sol#L113)
- **现象**：donation 的 `mintDonation` 要求 MINTER_ROLE，部署后 deployer 持有但 PayPal webhook 服务端地址未配置。
- **影响**：部署后无法接收任何捐款。
- **修复**：脚本通过 `PAYPAL_SERVER` 环境变量读取并 `grantMinterRole`。

### M11. IAetherRing 写入方法未纳入接口

- **文件**：[contracts/src/interfaces/IAetherRing.sol](file:///workspace/contracts/src/interfaces/IAetherRing.sol#L10-L44)
- **现象**：`revokeRing` / `mintRing` / `updateTier` / `reactivateDormantCitizen` 被 governance/election/donation 通过 `AetherRing(address(ringContract))` 强转调用，未声明在接口中。
- **影响**：接口契约不完整；强转破坏抽象，未来代理升级会 revert；mock 测试困难。
- **修复**：将 4 个写入方法声明加入 IAetherRing，调用方改为通过接口调用。

### M12. 环境变量默认 deployer 导致 AlreadyHasRing revert

- **文件**：[contracts/script/Genesis.s.sol](file:///workspace/contracts/script/Genesis.s.sol#L65-L97)
- **现象**：大量 `vm.envOr("PAR_SPEAKER_1", deployer)`，漏配时所有高层地址回退 deployer，第二次 mintRing revert `AlreadyHasRing`，部分广播已成功导致状态不一致。
- **修复**：开头校验所有必需地址非 deployer，或每次 mintRing 前检查 `walletToRingId[addr] == 0`。

---

## 五、🟢 Low / Info 问题（9 项）

| # | 文件 | 行号 | 问题 |
|---|---|---|---|
| L1 | AetherDonation.sol | 182-187 | DormantCitizenReactivated 事件误报（非休眠也 emit） |
| L2 | AetherRing.sol | 609-611 | getActiveCitizens 潜在下溢（_dormantCitizenCount > _tierCount[CITIZEN] 时 revert） |
| L3 | AetherRing.sol | 228-251 | mintRing/appointElder _safeMint 违反 CEI（可触发虚假 RingExpired 事件） |
| L4 | AetherElection.sol | 291, 354 | advanceToCouncilReview / advanceToParliamentApproval 复用 CouncilReviewFinalized 事件 |
| L5 | AetherElection.sol | 446 | finalizeElection 时间边界 `<=` 与 castVote `>` 不一致（1 秒死区） |
| L6 | AetherElection.sol | 756-780 | _sortCandidatesByVotes O(n²) 冒泡排序，n≤60 接近 gas 边界 |
| L7 | AetherGovernance.sol | 312, 332, 596 | urgency=Emergency 未限制为 TREASURY 类型（SIGNAL/PARAM 也可获 12h timelock） |
| L8 | AetherGovernance.sol | 596-599 | Timelock 可被矿工缩短约 15 秒（0.03%，可忽略） |
| I1 | 多文件 | — | grantMinterRole/setVotingPeriods/setInternalWeight/grantCouncilChairRole 等管理函数缺自定义事件（仅基类 RoleGranted/RoleRevoked） |

---

## 六、Hooks 与 ABI 一致性审计（✅ 无问题）

5 个 hooks（useRingInfo / useGovernance / useImpeachment / useElection / useDonation）与 4 个 ABI 文件在以下 4 个维度**完全一致**：

| 维度 | 结论 |
|---|---|
| 函数名拼写 | ✅ 所有 functionName 在 ABI 中存在 |
| 参数顺序/数量/类型 | ✅ 所有 args 数组与 ABI inputs 匹配（createProposal 7 参、createElection 4 参、mintDonation 4 参、settleDonation 2 参等） |
| 返回值解析 | ✅ 字段索引与 ABI outputs 对齐（getRingInfo 12 字段、getProposal 19 字段、getElection 8 字段、getElectionTimelines 6 字段、getCandidateInfo 6 字段、getDonation 9 字段） |
| Enum 定义 | ✅ 全部从 index.ts 导入，源头单一 |

**说明**：用户在 Phase 6 任务列表中提到的部分函数名（advanceToFirstVote / senateVeto / returnToDraft / castConfidenceVote / castImpeachmentVote 等）实际为预期名，hook 使用了正确的 ABI 名（advanceProposal / vetoProposal / returnProposal / voteConfidence / castPublicVote），**非 bug**。

**wagmi 类型处理**：getRingInfo / getDonation 等 struct 返回值的 `as unknown as readonly unknown[]` 二次转换已正确处理 wagmi 类型推断问题，tsc --noEmit 0 错误。

---

## 七、跨合约角色授权审计

### 7.1 Deploy.s.sol 已正确授权 ✅

| 授权 | 行号 | 用途 |
|---|---|---|
| `ring.MINTER_ROLE() → donation` | Deploy.s.sol:84 | donation 铸公民道环 + reactivateDormantCitizen |
| `ring.MINTER_ROLE() → election` | Deploy.s.sol:82 | election._applyPromotion 中 mintRing |
| `ring.ADMIN_ROLE() → governance` | Deploy.s.sol:78 | governance.finalizeImpeachment 中 revokeRing |
| `ring.ADMIN_ROLE() → election` | Deploy.s.sol:80 | election._applyPromotion 中 updateTier |
| `ring.GOVERNANCE_ROLE() → governance` | Deploy.s.sol:86 | governance.markVoteActivity |
| `ring.ELECTION_ROLE() → election` | Deploy.s.sol:88 | election.markVoteActivity |

### 7.2 合约间接口调用

governance/election/donation 调用的 ring 方法**全部存在**于 AetherRing 实现，但 4 个写入方法（revokeRing/mintRing/updateTier/reactivateDormantCitizen）未声明在 IAetherRing 中，通过强转调用（见 M11）。

### 7.3 config.ts 地址读取 ✅

- 支持 Arbitrum One (42161) / Sepolia (421614) / Anvil (31337)
- 链专属 + 通用环境变量两级回退
- 正则校验 0x + 40 hex
- 未部署时 `index.ts` 的 4 个地址函数返回 null（含零地址二次检查），hooks 的 `enabled: !!addr` 防止误调用

---

## 八、集成测试覆盖审计

### 8.1 已覆盖 ✅

| 测试 | 覆盖范围 |
|---|---|
| T5.1 完整提案流程 | 草案→一审→合规→公投→否决窗口→执行 |
| T5.2 完整弹劾流程 | 元老发起→3联署→公投→撤销道环（已重写为 30%/70% + citizenFor 路径） |
| T5.3 完整选举流程 | 创建→注册→理事会→议会审批→投票→finalize→晋升 |
| T5.4 完整捐款流程 | mintDonation→铸公民道环→settle→3担保激活快速通道 |
| T5.5 角色权限校验 | 非任命元老不能弹劾、退休元老不能弹劾、非理事会长不能 approveCandidate |

### 8.2 未覆盖（缺失测试）

- 🔴 捐款→投票→选举完整链路串联（见 H10）
- 🟠 appointToVacancy 空缺处理（PartiallyFilled 状态、unfilledSeats 计算、填满转 Finalized）
- 🟡 角色不匹配负面测试不充分（donation 无 MINTER_ROLE / election 无 ADMIN_ROLE / 非 Safe 调 appointElder / 非 PROPOSER_ROLE 创建提案 / 非三院成员 createProposal）
- 🟡 弹劾负面路径（参与率<30% / 支持率<70% / 弹劾公民 revert / 弹劾 ELDER 允许）

---

## 九、修复优先级建议

### 🔴 立即修复（阻断部署/治理）

1. **C1** AetherRing.sol:113 → `uint256 private _nextTokenId = 1;`
2. **C2** AetherGovernance.sol:711 → `p.citizenAgainst` 改 `p.citizenFor`，并修正 T5.2 测试 + IMPEACHMENT_QUORUM_BPS 4000→3000、IMPEACHMENT_PASS_BPS 6000→7000
3. **C3** Genesis.s.sol:119-140 → 实际调用 `ring.appointElder`
4. **H1** AetherGovernance.sol executeProposal → CEI 模式或 ReentrancyGuard
5. **H2** AetherGovernance.sol 构造函数 → `_grantRole(ADMIN_ROLE, address(this));`
6. **H3** AetherGovernance.sol advanceProposal → `if (p.pType == IMPEACHMENT) revert UseCreateImpeachmentProposal();`
7. **H4** AetherRing.sol:325 → `if (info.tier != RingTier.ELDER)` 守卫
8. **H11** ✅ 已修复 (v3.1) — 加权计票权重 120%→100%

### 🟠 部署前修复

8. **H5** Deploy.s.sol:56 → 强制 TREASURY 环境变量
9. **H6** Genesis.s.sol:113-117 → 实际铸 10 公民或删除
10. **H7** Genesis.s.sol:108 → 删除理事长 PROPOSER_ROLE 授予
11. **H8** Genesis.s.sol → 4 合约 DEFAULT_ADMIN_ROLE 转移给 Safe
12. **H9** DEPLOY.md → 全面重写对齐 v3
13. **H10** Integration.t.sol → 新增完整链路串联测试

### 🟡 主网前建议修复

14. **M1-M12** 见第四节详细修复建议

### 🟢 长期优化

15. **L1-L8 + I1** 代码质量与文档改进

---

## 十、部署 checklist（修复后）

```bash
# 1. 修复 Critical/High 后本地编译
cd contracts && forge build

# 2. 运行全部测试（修复 T5.2 期望后）
forge test -vvv

# 3. 覆盖率检查（目标 ≥ 90%）
forge coverage

# 4. slither 静态分析
slither .

# 5. 启动 Anvil 本地链
anvil --block-time 1 &

# 6. 部署（必设 TREASURY）
PRIVATE_KEY=0x... TREASURY=0x... \
forge script contracts/script/Deploy.s.sol:Deploy \
  --rpc-url http://127.0.0.1:8545 --broadcast -vvv

# 7. 运行创世脚本（必设全部地址 + SAFE）
RING=0x... GOV=0x... ELECTION=0x... DONATION=0x... SAFE=0x... \
PAR_SPEAKER_1=0x... ... ELDER_5=0x... \
forge script contracts/script/Genesis.s.sol:Genesis \
  --rpc-url http://127.0.0.1:8545 --broadcast -vvv

# 8. 验证：任命元老数应为 5
cast call <RING> "appointedElderCount()" --rpc-url http://127.0.0.1:8545

# 9. 配置 PayPal MINTER_ROLE
PAYPAL_SERVER=0x... \
cast send <DONATION> "grantMinterRole(address)" <PAYPAL_SERVER> \
  --rpc-url http://127.0.0.1:8545 --private-key <SAFE_KEY>

# 10. 转移 4 合约 DEFAULT_ADMIN_ROLE 给 Safe（deployer 后续 renounceRole）

# 11. 配置前端环境变量（5 个合约 + Safe）
# .env.local:
# NEXT_PUBLIC_AETHER_RING_421614_ADDRESS=0x...
# NEXT_PUBLIC_AETHER_GOVERNANCE_421614_ADDRESS=0x...
# NEXT_PUBLIC_AETHER_ELECTION_421614_ADDRESS=0x...
# NEXT_PUBLIC_AETHER_DONATION_421614_ADDRESS=0x...
# NEXT_PUBLIC_SAFE_WALLET_421614_ADDRESS=0x...

# 12. 前端构建
pnpm build
```

---

## 十一、审计覆盖度

| 维度 | 覆盖 | 发现问题数 |
|---|---|---|
| 合约重入 | ✅ | 2 (H1, M1) |
| 合约权限 | ✅ | 3 (H2, H3, H7) |
| 合约状态机 | ✅ | 4 (C2, H3, M4, M8) |
| 合约整数溢出 | ✅ | 0（无 unchecked，除法均防零） |
| 合约防女巫/防重放 | ✅ | 2 (M2, M3) |
| 合约 SBT 不可转让 | ✅ | 0（_update 正确） |
| 合约事件覆盖 | ✅ | 1 (I1) |
| 合约时间戳依赖 | ✅ | 0（合理使用） |
| AetherRing 关键检查 | ✅ | 4 (C1, H4, M7, L2) |
| Hooks-ABI 一致性 | ✅ | 0 |
| 部署脚本 | ✅ | 6 (C3, H5, H6, H7, H8, M9, M10, M12) |
| 跨合约角色授权 | ✅ | 1 (M11) |
| 集成测试覆盖 | ✅ | 2 (H10, appointToVacancy 未覆盖) |
| 配置与文档 | ✅ | 2 (H9, M11) |

---

**审计报告结束**

> 本审计为静态分析，未执行动态测试（沙箱无法安装 Foundry）。建议在真实环境执行 `forge test -vvv` + `forge coverage` + `slither` 后再次复核。所有 Critical/High 修复后需重新审计受影响模块。
