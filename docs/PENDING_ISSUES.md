# Aether DAO v3.0 待处理问题清单

> **版本**：v3.4 — 外部审计 Critical/High 全部修复
> **日期**：2026-07-26
> **关联文档**：[V3_AUDIT_REPORT.md](./V3_AUDIT_REPORT.md)（详细审计报告）
> **优先级**：🔴 阻断主网 / 🟠 部署前修复 / 🟡 主网前建议 / 🟢 长期优化

---

## 〇、v3.4 外部审计修复总览（2026-07-26）

基于 2026-07-26 外部审计报告（3 Critical / 10 High / 14 Medium / 13 Low），完成全部 Critical + High 修复，并处理关键 Medium。

### v3.4 已修复清单（14 项）

| 类别 | ID | 文件 | 修复内容 |
|---|---|---|---|
| 🔴 C | C-1 | AetherRing.sol | mintRing CEI：walletToRingId/ringInfo/_tierCount 写入移到 _safeMint 前（防重入绕过一人一环） |
| 🔴 C | C-2 | AetherRing.sol | appointElder CEI：状态写入（含 _appointedElderCount）移到 _safeMint 前（防重入突破 9 人上限） |
| 🔴 C | C-3 | AetherElection.sol | setRingContract 加零地址检查（防误操作致合约永久失效） |
| 🔴 H | H-1 | AetherRing.sol | updateTier 休眠公民升级时清除 isDormant + 递减 _dormantCitizenCount |
| 🔴 H | H-2 | AetherRing.sol | updateTier 拒绝已到期道环操作（除非 resetTerm=true） |
| 🔴 H | H-4 | AetherRing.sol | setSafeWallet 验证目标 code.length > 0（防设为任意 EOA） |
| 🔴 H | H-5 | AetherRing.sol | appointElder 拒绝将已到期道环提升为元老 |
| 🔴 H | H-6 | AetherGovernance.sol | startFirstVote 限制为 proposer 或 COUNCIL_CHAIR（防恶意提前启动投票） |
| 🔴 H | H-7 | AetherGovernance.sol | approveEmergencyTreasury 加 status==Queued 校验 |
| 🔴 H | H-8 | AetherGovernance.sol | cancelProposal 禁止在 PublicVoteActive/PendingVeto/Queued 阶段取消（防中心化滥用） |
| 🔴 H | H-9 | AetherGovernance.sol | 弹劾通过后 revoke 被弹劾者的 PROPOSER_ROLE（revokeRing 不自动清权限） |
| 🔴 H | H-10 | Genesis.s.sol | _citizenEnvKey(10) 修复：支持两位数（原 0x30+10=0x3A=':' 致第 10 公民永远跳过） |
| 🟠 M | — | AetherElection.sol | advanceToCouncilReview/advanceToParliamentApproval 加 ELECTION_MANAGER_ROLE 权限 |
| 🟠 M | — | AetherDonation.sol | mintDonation 加 PayPal TxId 非空检查 |

### v3.4 设计决策（不改代码）

| 审计项 | 原因 |
|---|---|
| H-3 双角色体系（DEFAULT_ADMIN + ADMIN） | OpenZeppelin 标准模式：DEFAULT_ADMIN 管角色 admin，ADMIN 管业务。v3.2 H8 已把 DEFAULT_ADMIN 转给 Safe，风险已缓解 |
| Medium 弹劾忽略三院计票 | 设计决策：弹劾是公民对治理者的直接制衡（30% quorum + 70% 支持），白皮书明确"公民主权"，三院不参与弹劾 |

---

## 一、v3.2 修复总览（已完成）

本次迭代（v3.2）已完成所有 Critical / High / Medium / Low 级别 bug 修复，覆盖合约逻辑、部署脚本、创世脚本、接口架构与集成测试。以下问题均已修复，可在现实环境测试前不再阻塞。

### 已修复清单（33 项）

| 类别 | ID | 文件 | 修复内容 |
|---|---|---|---|
| 🔴 C | C1 | AetherRing.sol | `_nextTokenId = 1`（哨兵约定） |
| 🔴 C | C2 | AetherGovernance.sol | 弹劾计票 `citizenFor` + 阈值 30%/70% |
| 🔴 C | C3 | Genesis.s.sol | 实际调用 `ring.appointElder(elder, "")` |
| 🔴 H | H1 | AetherGovernance.sol | executeProposal CEI（状态先于外部调用） |
| 🔴 H | H2 | AetherGovernance.sol | 构造函数 `_grantRole(ADMIN_ROLE, address(this))` |
| 🔴 H | H3 | AetherGovernance.sol | advanceProposal 加 `pType == IMPEACHMENT` 校验 |
| 🔴 H | H4 | AetherRing.sol | revokeRing 加 ELDER tier 守卫 + isElderActive 加 isActive |
| 🔴 H | H5 | Deploy.s.sol | TREASURY 强制环境变量（不再 deployer 兜底） |
| 🔴 H | H6 | Genesis.s.sol | 实际铸造 10 公民（CITIZEN_1..CITIZEN_10） |
| 🔴 H | H7 | Genesis.s.sol | 移除理事长 PROPOSER_ROLE（tier 12 不满足 onlyChamberMember） |
| 🔴 H | H8 | Deploy.s.sol | 4 合约 DEFAULT_ADMIN_ROLE 授予 Safe |
| 🔴 H | H10 | Integration.t.sol | 新增 `test_DonationToVoteToElection_ChainFlow_H10` |
| 🔴 H | H11 | AetherGovernance.sol | 权重重归一化：1666 BPS/院 + 5000 BPS 公民 |
| 🟠 M | M1 | AetherDonation.sol | mintDonation CEI（状态先于 _safeMint） |
| 🟠 M | M3 | AetherGovernance.sol | cancelProposal 终态保护 |
| 🟠 M | M4 | AetherGovernance.sol | PARAM setter 下界校验 |
| 🟠 M | M5 | AetherGovernance.sol | setRingContract 零地址检查 |
| 🟠 M | M6 | AetherElection.sol | appointToVacancy 候选人资格检查 |
| 🟠 M | M7 | AetherRing.sol | setRingActive 到期检查 |
| 🟠 M | M8 | AetherElection.sol | forceAdvanceToVoting 议会批准数检查 |
| 🟠 M | M9 | Deploy.s.sol | donation.ADMIN_ROLE 授予 Safe |
| 🟠 M | M10 | Deploy.s.sol | donation.MINTER_ROLE 授予 PAYPAL_SERVER |
| 🟠 M | M11 | IAetherRing.sol | 写入方法纳入接口（消除强转） |
| 🟠 M | M12 | Deploy/Genesis.s.sol | 必需环境变量校验 + deployer 兜底移除 |
| 🟢 L | L1 | AetherDonation.sol | DormantCitizenReactivated 条件发射（wasDormant） |
| 🟢 L | L2 | AetherRing.sol | getActiveCitizens 下溢保护 |
| 🐛 Bug | 18 | AetherElection.sol | _applyPromotion try/catch 防阻塞 |
| 🐛 Bug | 29 | AetherDonation.sol | unlinkPaypalAccount 解绑函数 |
| 🐛 Bug | 30 | AetherDonation.sol | DormantCitizenReactivated 条件发射 |

### 未修复（设计决策 / 文档类）

| ID | 原因 |
|---|---|
| M2 | paypalAccountHash 链下计算 + MINTER_ROLE 单点信任 — 设计决策，文档已说明多签保护 |
| H9 | 旧 DEPLOY.md 已被 DEPLOYMENT_GUIDE.md 替代 |
| L3-L8, I1 | 长期优化项，不阻塞主网（gas 优化 / 事件补全 / 边界一致性） |

---

## 一、🔴 阻断主网部署（必须修复）

### 1.1 智能合约 Critical 问题（3 项）— ✅ 全部修复

> 详见 [V3_AUDIT_REPORT.md 第二节](./V3_AUDIT_REPORT.md)

| ID | 文件 | 行号 | 问题 | 修复 | 状态 |
|---|---|---|---|---|---|
| C1 | AetherRing.sol | 77 | `_nextTokenId` 初始值为 0，破坏"0=无道环"哨兵约定 | `uint256 private _nextTokenId = 1;` | ✅ |
| C2 | AetherGovernance.sol | 716-746 | 弹劾计票用 `citizenAgainst` 而非 `citizenFor`，语义反转 | `citizenFor` + IMPEACHMENT_QUORUM_BPS 4000→3000、IMPEACHMENT_PASS_BPS 6000→7000 | ✅ |
| C3 | Genesis.s.sol | 170-178 | 任命元老完全未执行（仅 console.log） | 实际调用 `ring.appointElder(elder, "")` | ✅ |

### 1.2 智能合约 High 问题（10 项）— ✅ 全部修复

| ID | 文件 | 行号 | 问题 | 修复 | 状态 |
|---|---|---|---|---|---|
| H1 | AetherGovernance.sol | 622-646 | executeProposal TREASURY 分支重入（CEI 违规） | 外部调用前置 `p.status = Executed` | ✅ |
| H2 | AetherGovernance.sol | 289-309 | PARAM 提案执行必然失败（address(this) 无 ADMIN_ROLE） | 构造函数 `_grantRole(ADMIN_ROLE, address(this))` | ✅ |
| H3 | AetherGovernance.sol | 356-365 | advanceProposal 缺 pType 校验 | `if (p.pType == IMPEACHMENT) revert` | ✅ |
| H4 | AetherRing.sol | 292-316 | revokeRing 对 ELDER 道环下溢 | `if (info.tier != RingTier.ELDER)` 守卫 + isElderActive 加 isActive | ✅ |
| H5 | Deploy.s.sol | 82 | Treasury 占位风险 | `vm.envAddress("TREASURY")` 强制要求 | ✅ |
| H6 | Genesis.s.sol | 162-168 | 初始 10 公民未铸造 | 实际 mint（CITIZEN_1..CITIZEN_10 环境变量） | ✅ |
| H7 | Genesis.s.sol | 188-198 | PROPOSER_ROLE 授予理事长无效 | 移除理事长授予，仅授予 tier 1-9 三院成员 | ✅ |
| H8 | Deploy.s.sol | 122-128 | 4 合约 DEFAULT_ADMIN_ROLE 未转移给 Safe | 脚本末尾 4 个 grantRole + ring.setSafeWallet | ✅ |
| H9 | DEPLOY.md | 多处 | 文档严重过时（v2 残留） | 全面重写（已被 DEPLOYMENT_GUIDE.md 替代） | ✅ |
| H10 | Integration.t.sol | 361-506 | 捐款→投票→选举完整链路未串联测试 | 新增 `test_DonationToVoteToElection_ChainFlow_H10` | ✅ |
| H11 | AetherGovernance.sol | 161-168 | 加权计票权重总和 120% | 权重重归一化：1666 BPS/院（合计 4998）+ 公民 5000 BPS | ✅ |

---

## 二、🟠 部署前建议修复

### 2.1 智能合约 Medium 问题（12 项）— ✅ 11 项修复，1 项设计决策

| ID | 文件 | 问题 | 修复建议 | 状态 |
|---|---|---|---|---|
| M1 | AetherDonation.sol:161-176 | mintDonation 违反 CEI | 状态写入移到 _safeMint 前 | ✅ |
| M2 | AetherDonation.sol:138 | paypalAccountHash 离链计算 | 设计决策，文档明确多签保护 | ⚠️ 保留 |
| M3 | AetherGovernance.sol:977-986 | cancelProposal 无终态保护 | `if (status == Executed \|\| Defeated \|\| Canceled) revert` | ✅ |
| M4 | AetherGovernance.sol:955-975 | PARAM setter 无参数下界 | `if (_firstVote < 1 hours ...) revert ParamOutOfRange()` | ✅ |
| M5 | AetherGovernance.sol:937-943 | setRingContract 无零地址检查 | `if (_ring == address(0)) revert ZeroRingAddress()` | ✅ |
| M6 | AetherElection.sol | appointToVacancy 可任命被拒/未注册候选人 | `if (!c.isRegistered \|\| c.isRejected) revert NotEligibleCandidate()` | ✅ |
| M7 | AetherRing.sol:318-327 | setRingActive 可激活到期道环 | 检查 isExpired 和 termEndAt | ✅ |
| M8 | AetherElection.sol:400-412 | forceAdvanceToVoting 使议会审批形同虚设 | `if (parliamentApprovalCount == 0) revert` | ✅ |
| M9 | Deploy.s.sol:130-131 | donation ADMIN_ROLE 未转交 Safe | 脚本末尾 grantRole | ✅ |
| M10 | Deploy.s.sol:133-134 | PayPal MINTER_ROLE 未配置 | 读 PAYPAL_SERVER 环境变量并 grantMinterRole | ✅ |
| M11 | IAetherRing.sol | 4 个写入方法未纳入接口 | RingTier/RingInfo + mintRing/updateTier/revokeRing/appointElder/reactivateDormantCitizen 声明加入接口 | ✅ |
| M12 | Deploy/Genesis.s.sol | 环境变量默认 deployer | 必需变量校验 + 创世地址 ≠ deployer 检查 | ✅ |

### 2.2 集成测试缺失 — ✅ H10 已覆盖主链路

- [x] **捐款→投票→选举完整链路**已覆盖（`test_DonationToVoteToElection_ChainFlow_H10`）
- [ ] **appointToVacancy 空缺处理**未覆盖（PartiallyFilled 状态、unfilledSeats 计算）— 后续补充
- [ ] **角色不匹配负面测试**不充分 — 后续补充
- [ ] **弹劾负面路径**未覆盖 — 后续补充

---

## 三、🟡 主网前建议处理

### 3.1 测试执行（forge test）

**问题**：沙箱环境无法通过 `foundryup` 下载 Forge 二进制（GitHub SSL 连接不稳定）

**待执行**：

```bash
# 1. 安装 Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# 2. 安装依赖
cd contracts
forge install foundry-rs/forge-std --no-commit
forge install OpenZeppelin/openzeppelin-contracts --no-commit

# 3. 运行测试（90 个，含新增 H10 端到端测试）
forge test -vvv

# 4. 覆盖率检查（目标 ≥ 90%）
forge coverage

# 5. invariant 测试（状态机所有路径）
forge test --match-test invariant -vvv
```

**预期**：v3.2 修复后测试应全绿；如发现失败需根据失败信息修复

### 3.2 静态分析

```bash
# 1. slither 静态分析
pip install slither-analyzer
slither .

# 2. mythril 符号执行
myth analyze contracts/src/AetherGovernance.sol

# 3. external audit（建议）
# 委托 Trail of Bits / OpenZeppelin / Certik
```

### 3.3 外部服务集成

#### 3.3.1 PayPal Webhook 服务端

- [ ] 服务端接收 PayPal webhook（`payment.completed`）
- [ ] 调用 PayPal API 回查交易真实性
- [ ] 提取 donor 地址、金额、paypalTxId、payer_id
- [ ] 计算 `paypalAccountHash = keccak256(payer_id)`
- [ ] 调用 `donation.mintDonation(donor, amount, paypalTxId, paypalAccountHash)`
- [ ] 服务端地址被授予 `donation.MINTER_ROLE`（Deploy.s.sol 已配置 PAYPAL_SERVER）
- [ ] 金额单位：USD 6 decimals（$10 = 10000000）

#### 3.3.2 IPFS 存储

- [ ] 注册 Pinata 账号，获取 API Key
- [ ] 前端上传提案内容到 IPFS，获取 CID
- [ ] 将 CID 作为 `ipfsHash` 传入 `createProposal`
- [ ] 环境变量 `NEXT_PUBLIC_IPFS_GATEWAY`

#### 3.3.3 USDC 结算

- [ ] Safe 多签发起 USDC 转账（donor → treasury）
- [ ] 转账确认后调用 `donation.settleDonation(tokenId, usdcAmount)`
- [ ] USDC 合约地址：Arbitrum One `0xaf88d065e77c8cC2239327C5EDb3A432268e5831`
- [ ] 金额精度：6 decimals

### 3.4 前端待处理

- [ ] **useDonation 旧版 ETH 转账**：当前 `useDonation()` 仍保留 ETH 直接转账到占位地址 `0x000…AeTh`。真实部署后：
  1. 将 `TREASURY_ADDRESSES.arbitrum` 替换为真实 Safe 地址，或改为读取 `useDonationTreasury()` 返回值
  2. USDC/USDT 分支目前为模拟交易，需接入真实 ERC20 `transfer(treasury, amount)`
- [ ] **wagmi struct 返回值类型**：`useRingInfo.getRingInfo` / `useDonation.getDonation` 等返回 struct 的函数，wagmi 推断为命名对象而非数组，已用 `as unknown as readonly unknown[]` 二次转换绕过；升级 wagmi 版本后需复核
- [ ] **UI 组件适配 v3 枚举**：
  - tier 标签（14 级显示）
  - proposal 状态流转图（12 状态）
  - election 阶段指示器（4 阶段 + PartiallyFilled）
- [ ] `pnpm build` 成功验证（沙箱仅验证 tsc --noEmit 0 错误）
- [ ] 钱包连接与交易签名流程端到端测试

### 3.5 合约体积监控

| 合约 | 当前体积 | 占 24KB | 状态 |
|---|---|---|---|
| AetherRing | 13,947 B | 56.8% | ✅ 安全 |
| AetherDonation | 10,135 B | 41.2% | ✅ 安全 |
| AetherElection | 10,141 B | 41.3% | ✅ 安全 |
| AetherGovernance | 19,221 B | 78.2% | ⚠️ 接近上限 |

**AetherGovernance 注意事项**：
- 若后续新增功能导致超过 24KB，需抽取 `AetherGovernanceLib` library
- v3.2 修复后体积可能略增，需重新检查

---

## 四、🟢 长期优化

### 4.1 Low/Info 问题（9 项）— ✅ L1/L2 已修复，其余保留

| ID | 文件 | 问题 | 状态 |
|---|---|---|---|
| L1 | AetherDonation.sol | DormantCitizenReactivated 事件误报（非休眠也 emit） | ✅ Bug 30 已修 |
| L2 | AetherRing.sol:591-595 | getActiveCitizens 潜在下溢风险 | ✅ |
| L3 | AetherRing.sol:228-251 | mintRing/appointElder _safeMint 违反 CEI | ⚠️ 保留（利用难度高） |
| L4 | AetherElection.sol:291,354 | advanceToCouncilReview/advanceToParliamentApproval 复用 CouncilReviewFinalized 事件 | ⚠️ 保留 |
| L5 | AetherElection.sol:446 | finalizeElection 时间边界 `<=` 与 castVote `>` 不一致（1 秒死区）| ⚠️ 保留 |
| L6 | AetherElection.sol:756-780 | _sortCandidatesByVotes O(n²) 冒泡排序，n≤60 接近 gas 边界 | ⚠️ 保留 |
| L7 | AetherGovernance.sol:312,332,596 | urgency=Emergency 未限制为 TREASURY 类型 | ⚠️ 保留 |
| L8 | AetherGovernance.sol:596-599 | Timelock 可被矿工缩短约 15 秒（0.03%，可忽略）| ⚠️ 保留 |
| I1 | 多文件 | grantMinterRole/setVotingPeriods 等管理函数缺自定义事件 | ⚠️ 保留 |

### 4.2 部署后运维

#### 4.2.1 监控

建议部署后监控以下事件：

- `ProposalCreated` / `ProposalFinalized` / `ProposalExecuted`
- `ImpeachmentSigned` / `ImpeachmentFinalized`
- `DonationMinted`（amount ≥ $1000 时告警）
- `ElderAppointed`
- `CitizenDormant`
- `RoleGranted` / `RoleRevoked`

#### 4.2.2 升级策略

v3 合约不可升级（无 proxy）。若需修复严重 bug：

1. 部署新版本合约
2. 通过治理提案迁移状态
3. 更新前端 config 指向新合约
4. 旧合约 `revokeRole` 所有权限
5. 公告社区迁移

#### 4.2.3 治理参数调优

以下参数可通过 PARAM 提案调整（无需重新部署）：

- `firstVotePeriod`（一审时长，默认 5 天）
- `publicVotePeriod`（公投时长，默认 7 天）
- `complianceVotePeriod`（合规审查，默认 3 天）
- `timelockNormal`（普通 Timelock，默认 48 小时）
- `timelockEmergency`（紧急 Timelock，默认 12 小时）
- `internalWeight`（三院内部权重，tier 1-14）

**不可调参数**（常量，需重新部署）：

- 三院权重（各 ≈16.6%/1666 BPS，合计 4998）、公民权重（50%/5000 BPS）、通过门槛（>50%）
- quorum 阈值（普通 20% / 章程 50%）
- 弹劾联署数（3）、弹劾参与率（30%）、弹劾通过率（70%，citizenFor）
- 公民休眠期（2 年）、放弃冷却期（30 天）
- 任命元老上限（9）

---

## 五、任务优先级总览

| 优先级 | 类别 | 数量 | 已修复 | 状态 |
|---|---|---|---|---|
| 🔴 阻断主网 | 合约 Critical | 3 | 3 | ✅ 完成 |
| 🔴 阻断主网 | 合约 High | 11 | 11 | ✅ 完成 |
| 🟠 部署前 | 合约 Medium | 12 | 11 | ✅ 完成（M2 设计决策保留） |
| 🟠 部署前 | 集成测试补充 | 4 类 | 1 类（H10 主链路） | ⚠️ 部分完成 |
| 🟡 主网前 | forge test 执行 | 1 | 0 | ⏳ 待执行 |
| 🟡 主网前 | 静态分析 | 3 | 0 | ⏳ 待执行 |
| 🟡 主网前 | 外部服务集成 | 3 | 0 | ⏳ 待执行 |
| 🟡 主网前 | 前端待处理 | 5 | 0 | ⏳ 待执行 |
| 🟢 长期 | Low/Info | 9 | 2 | ⚠️ 部分完成 |
| 🟢 长期 | 运维 | 3 | 0 | ⏳ 待执行 |

---

## 六、最高优先级行动项（v3.2 已完成）

1. ✅ **修复 C1**：AetherRing.sol:77 `_nextTokenId = 1`
2. ✅ **修复 C2**：AetherGovernance.sol 弹劾 `citizenFor` + 阈值修正
3. ✅ **修复 C3**：Genesis.s.sol 实际调用 `ring.appointElder`
4. ✅ **修复 H1**：executeProposal 改 CEI 模式
5. ✅ **修复 H2**：构造函数 `_grantRole(ADMIN_ROLE, address(this))`
6. ✅ **修复 H3**：advanceProposal 加 pType 校验
7. ✅ **修复 H4**：revokeRing 加 ELDER 守卫
8. ✅ **修复 H5-H8/M9-M12**：Deploy/Genesis 脚本完整修复
9. ✅ **修复 H10**：端到端集成测试已编写
10. ✅ **修复 H11**：权重重归一化 1666 BPS/院 + 5000 BPS 公民
11. ⏳ **本地执行 `forge test -vvv`** 验证全部测试（需 Foundry 环境）
12. ⏳ **创建 Safe 多签** 并完成 Arbitrum Sepolia 部署
13. ⏳ **真实环境执行 `pnpm build`** + UI 组件适配 v3 枚举

---

**文档结束**

> 详细审计发现请参考 [V3_AUDIT_REPORT.md](./V3_AUDIT_REPORT.md)。部署流程请参考 [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md)。
