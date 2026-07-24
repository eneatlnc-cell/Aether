# Aether DAO v3.0 待处理问题清单

> **版本**：v3.0 Phase 1-6 完成后
> **日期**：2026-07-24
> **关联文档**：[V3_AUDIT_REPORT.md](./V3_AUDIT_REPORT.md)（详细审计报告）
> **优先级**：🔴 阻断主网 / 🟠 部署前修复 / 🟡 主网前建议 / 🟢 长期优化

---

## 一、🔴 阻断主网部署（必须修复）

### 1.1 智能合约 Critical 问题（3 项）

> 详见 [V3_AUDIT_REPORT.md 第二节](./V3_AUDIT_REPORT.md)

| ID | 文件 | 行号 | 问题 | 修复 |
|---|---|---|---|---|
| C1 | AetherRing.sol | 113 | `_nextTokenId` 初始值为 0，破坏"0=无道环"哨兵约定，首个铸道环地址可重复 mint | `uint256 private _nextTokenId = 1;` |
| C2 | AetherGovernance.sol | 711 | 弹劾计票用 `citizenAgainst` 而非 `citizenFor`，语义反转（60% 反对时反而通过）| `p.citizenAgainst` → `p.citizenFor`，并修正 T5.2 测试期望 + IMPEACHMENT_QUORUM_BPS 4000→3000、IMPEACHMENT_PASS_BPS 6000→7000 |
| C3 | Genesis.s.sol | 119-140 | 任命元老完全未执行（仅 console.log），部署后无任命元老，弹劾/否决/紧急拨款全部瘫痪 | 实际调用 `ring.appointElder(elder, "")` |

### 1.2 智能合约 High 问题（10 项）

| ID | 文件 | 行号 | 问题 | 修复 |
|---|---|---|---|---|
| H1 | AetherGovernance.sol | 606-628 | executeProposal TREASURY 分支重入（CEI 违规，可双重转账）| 外部调用前置 `p.status = Executed`，或加 ReentrancyGuard |
| H2 | AetherGovernance.sol | 613-616 + 281-285 | PARAM 提案执行必然失败（address(this) 无 ADMIN_ROLE）| 构造函数 `_grantRole(ADMIN_ROLE, address(this));` |
| H3 | AetherGovernance.sol | 345-352 | advanceProposal 缺 pType 校验，理事长可绕过 3 元老联署启动弹劾 | `if (p.pType == IMPEACHMENT) revert UseCreateImpeachmentProposal();` |
| H4 | AetherRing.sol | 325 | revokeRing 对 ELDER 道环下溢（`_tierCount[13]` 从未自增），弹劾元老失败 | `if (info.tier != RingTier.ELDER) { _tierCount[...] -= 1; }` |
| H5 | Deploy.s.sol | 56 | Treasury 占位风险（未设 TREASURY 时用 deployer 兜底）| 改为 `vm.envAddress("TREASURY")` 强制要求 |
| H6 | Genesis.s.sol | 113-117 | 初始 10 公民未铸造（循环体为空），测试网 quorum 失效 | 实际 mint 或彻底删除并说明 |
| H7 | Genesis.s.sol | 108 | PROPOSER_ROLE 授予理事长无效（tier 12 不满足 onlyChamberMember tier 1-9）| 删除该授予 |
| H8 | Genesis.s.sol | — | 4 合约 DEFAULT_ADMIN_ROLE 未转移给 Safe | 脚本末尾增加 4 个 grantRole |
| H9 | DEPLOY.md | 多处 | 文档严重过时（v2 残留：tier 表/弹劾流程/REELECTION/setSafeWallet 不存在）| 全面重写（已被本 DEPLOYMENT_GUIDE.md 替代）|
| H10 | Integration.t.sol | — | 捐款→投票→选举完整链路未串联测试 | 新增 `test_DonationToVoteToElection_ChainFlow` |

---

## 二、🟠 部署前建议修复

### 2.1 智能合约 Medium 问题（12 项）

| ID | 文件 | 问题 | 修复建议 |
|---|---|---|---|
| M1 | AetherDonation.sol:161-174 | mintDonation 违反 CEI（_safeMint 后才写状态）| 状态写入移到 _safeMint 前，或改用 _mint |
| M2 | AetherDonation.sol:138 | paypalAccountHash 离链计算，MINTER_ROLE 单点信任 | 合约内计算 `keccak256(payer_id)`，或文档明确多签保护 |
| M3 | AetherDonation.sol:68 | PayPal TxId 跨链重放风险（多链部署时）| TxId 编码 chainId |
| M4 | AetherGovernance.sol:951-955 | cancelProposal 无终态保护（可对已 Executed 提案 cancel）| `if (status == Executed \|\| Canceled) revert` |
| M5 | AetherGovernance.sol:919 + AetherElection.sol:609 | setRingContract 无零地址检查 | `if (_ring == address(0)) revert ZeroAddress();` |
| M6 | AetherElection.sol:487-511 | appointToVacancy 可任命被拒/未注册候选人 | 增加 `if (!c.isNominated) revert` + `if (c.isRejected) revert` |
| M7 | AetherRing.sol:339-344 | setRingActive 可激活到期道环 | 检查 isExpired 和 termEndAt |
| M8 | AetherElection.sol:392-402 | forceAdvanceToVoting 使议会审批形同虚设 | 确认设计意图，或改为未达阈值即取消 |
| M9 | Deploy.s.sol:113 | donation ADMIN_ROLE 未转交 Safe | 脚本末尾 grantRole |
| M10 | Deploy.s.sol:113 | PayPal MINTER_ROLE 未配置 | 脚本读 PAYPAL_SERVER 环境变量并 grantMinterRole |
| M11 | IAetherRing.sol | 4 个写入方法未纳入接口，强转调用 | 将 revokeRing/mintRing/updateTier/reactivateDormantCitizen 声明加入接口 |
| M12 | Genesis.s.sol:65-97 | 环境变量默认 deployer 导致 AlreadyHasRing revert | 开头校验所有地址非 deployer |

### 2.2 集成测试缺失

- [ ] **appointToVacancy 空缺处理**未覆盖（PartiallyFilled 状态、unfilledSeats 计算）
- [ ] **角色不匹配负面测试**不充分：
  - donation 无 MINTER_ROLE 时 mintDonation revert
  - election 无 ADMIN_ROLE 时 createElection revert
  - 非 Safe 调 appointElder revert
  - 非 PROPOSER_ROLE 创建提案 revert
  - 非三院成员（tier 10-14）createProposal revert
- [ ] **弹劾负面路径**未覆盖：
  - 参与率 <30% 不通过
  - 支持率 <70% 不通过
  - 弹劾公民（tier 14）revert `ImpeachmentTargetInvalid`
  - 弹劾 ELDER（tier 13）允许

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

# 3. 运行测试（89 个）
forge test -vvv

# 4. 覆盖率检查（目标 ≥ 90%）
forge coverage

# 5. invariant 测试（状态机所有路径）
forge test --match-test invariant -vvv
```

**预期**：测试可能发现少量逻辑 bug（计票精度、时间窗口边界），需根据失败信息修复

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
- [ ] 服务端地址被授予 `donation.MINTER_ROLE`
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
- 修复 H1/H2/H3 后体积可能略增，需重新检查

---

## 四、🟢 长期优化

### 4.1 Low/Info 问题（9 项）

| ID | 文件 | 问题 |
|---|---|---|
| L1 | AetherDonation.sol:182-187 | DormantCitizenReactivated 事件误报（非休眠也 emit） |
| L2 | AetherRing.sol:609-611 | getActiveCitizens 潜在下溢风险 |
| L3 | AetherRing.sol:228-251 | mintRing/appointElder _safeMint 违反 CEI |
| L4 | AetherElection.sol:291,354 | advanceToCouncilReview/advanceToParliamentApproval 复用 CouncilReviewFinalized 事件 |
| L5 | AetherElection.sol:446 | finalizeElection 时间边界 `<=` 与 castVote `>` 不一致（1 秒死区）|
| L6 | AetherElection.sol:756-780 | _sortCandidatesByVotes O(n²) 冒泡排序，n≤60 接近 gas 边界 |
| L7 | AetherGovernance.sol:312,332,596 | urgency=Emergency 未限制为 TREASURY 类型 |
| L8 | AetherGovernance.sol:596-599 | Timelock 可被矿工缩短约 15 秒（0.03%，可忽略）|
| I1 | 多文件 | grantMinterRole/setVotingPeriods/setInternalWeight/grantCouncilChairRole 等管理函数缺自定义事件 |

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

| 优先级 | 类别 | 数量 | 负责人 |
|---|---|---|---|
| 🔴 阻断主网 | 合约 Critical | 3 | 合约开发 |
| 🔴 阻断主网 | 合约 High | 10 | 合约开发 |
| 🟠 部署前 | 合约 Medium | 12 | 合约开发 |
| 🟠 部署前 | 集成测试补充 | 3 类 | 测试 |
| 🟡 主网前 | forge test 执行 | 1 | 开发 |
| 🟡 主网前 | 静态分析 | 3 | 安全 |
| 🟡 主网前 | 外部服务集成 | 3 | 后端 |
| 🟡 主网前 | 前端待处理 | 5 | 前端 |
| 🟢 长期 | Low/Info | 9 | 长期 |
| 🟢 长期 | 运维 | 3 | 运维 |

---

## 六、最高优先级行动项（立即执行）

1. **修复 C1**：AetherRing.sol:113 `_nextTokenId = 1`
2. **修复 C2**：AetherGovernance.sol:711 `citizenAgainst` → `citizenFor` + 修正 T5.2 测试
3. **修复 C3**：Genesis.s.sol 实际调用 `ring.appointElder`
4. **修复 H1**：executeProposal 改 CEI 模式
5. **修复 H2**：构造函数 `_grantRole(ADMIN_ROLE, address(this))`
6. **修复 H3**：advanceProposal 加 pType 校验
7. **修复 H4**：revokeRing 加 ELDER 守卫
8. **本地执行 `forge test -vvv`** 验证全部测试
9. **创建 Safe 多签** 并完成 Arbitrum Sepolia 部署
10. **真实环境执行 `pnpm build`** + UI 组件适配 v3 枚举

---

**文档结束**

> 详细审计发现请参考 [V3_AUDIT_REPORT.md](./V3_AUDIT_REPORT.md)。部署流程请参考 [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md)。
