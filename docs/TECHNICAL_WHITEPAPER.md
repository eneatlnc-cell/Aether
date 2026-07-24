# Aether DAO v3.0 技术白皮书

> **版本**：v3.0
> **日期**：2026-07-24
> **链**：Arbitrum One（L2 Rollup）
> **状态**：Phase 1-6 开发完成，待主网部署

---

## 一、项目概述

### 1.1 愿景

Aether Foundation 是一个部署于 Arbitrum 区块链的非营利 DAO，致力于去中心化基础设施与 AI 研究的长期资助。通过链上治理系统，实现资金的透明分配与社区共治，避免传统基金会的中心化信任问题。

### 1.2 核心目标

- **透明**：所有资金流动、提案投票、角色任命均上链可审计
- **分权**：三院制衡 + 元老否决 + 公民公投，避免单点权力集中
- **抗女巫**：PayPal 实名捐款 + 3 公民担保，防止身份攻击
- **可持续**：2 年休眠机制 + 任期限制，保持社区活跃

### 1.3 技术栈

| 层 | 技术 |
|---|---|
| 区块链 | Arbitrum One（EVM 兼容，低 gas，~1s 确认）|
| 智能合约 | Solidity 0.8.26 + OpenZeppelin Contracts v5 |
| 开发框架 | Foundry（forge / anvil / cast）|
| 多签金库 | Safe v1.4.1（3/5 阈值）|
| 前端 | Next.js 15 + TypeScript + wagmi v2 + Viem |
| 国际化 | next-intl（8 语言）|
| 存储 | IPFS（Pinata 网关，提案内容存储）|

---

## 二、系统架构

### 2.1 合约关系图

```
┌─────────────────────────────────────────────────────────────┐
│                     Safe 多签金库 (3/5)                       │
│  ─ 任命元老 / 退休转元老                                      │
│  ─ DEFAULT_ADMIN_ROLE 持有者（4 合约）                        │
│  ─ USDC 接收方（donation.treasury）                          │
└─────────────────────────────────────────────────────────────┘
            │ appointElder / retireToEmeritus
            ▼
┌──────────────────────┐  MINTER_ROLE   ┌──────────────────────┐
│   AetherRing (SBT)   │ ◄──────────── │  AetherDonation      │
│  14 级权级道环        │                │  PayPal 捐款凭证 NFT  │
│  ─ mintRing          │  ADMIN_ROLE   │  ─ mintDonation      │
│  ─ updateTier        │ ◄──────────── │  ─ settleDonation    │
│  ─ revokeRing        │                │  ─ sponsorDonation   │
│  ─ appointElder      │                └──────────────────────┘
│  ─ markVoteActivity  │                         ▲
└──────────────────────┘                         │ MINTER_ROLE
        ▲       ▲                                │（PayPal webhook）
        │       │
   ADMIN_ROLE  GOVERNANCE_ROLE / ELECTION_ROLE
        │       │
┌───────┴───────┴──┐                ┌──────────────────────┐
│ AetherGovernance │  ADMIN_ROLE    │  AetherElection      │
│ 三院分权治理      │ ◄──────────── │  4 阶段选举           │
│ ─ 7 阶段提案流程  │   (ring)       │  ─ MEMBER_TO_GRASSROOTS │
│ ─ 弹劾 / 否决     │                │  ─ GRASSROOTS_TO_MID    │
│ ─ 信任投票        │ ─────────────► │  ─ CITIZEN_TO_COUNCIL   │
│ ─ 紧急拨款        │  markVoteActivity              ─ appointToVacancy │
└──────────────────┘                └──────────────────────┘
```

### 2.2 四大核心合约

| 合约 | 职责 | 体积 |
|---|---|---|
| **AetherRing** | 14 级权级 SBT 道环，身份与任期管理 | 13.9 KB |
| **AetherGovernance** | 三院分权制衡治理，7 阶段提案流程 | 19.2 KB |
| **AetherElection** | 4 阶段选举状态机，空缺处理 | 10.1 KB |
| **AetherDonation** | PayPal 捐款凭证 NFT，公民身份发放 | 10.1 KB |

---

## 三、身份系统：AetherRing

### 3.1 14 级权级体系

| Tier | 名称 | 院 | 层 | 权重 | 任期 | 席位上限 |
|---|---|---|---|---|---|---|
| 1 | 议员 PARLIAMENT_MEMBER | 议会 | 基层 | 1 | 1 年 | 60 |
| 2 | 参议员 PARLIAMENT_SENIOR | 议会 | 中层 | 3 | 2 年 | 12 |
| 3 | 议长 PARLIAMENT_SPEAKER | 议会 | 高层 | 10 | 终身 | 2 |
| 4 | 委员 FEDERATION_MEMBER | 联邦 | 基层 | 1 | 1 年 | 60 |
| 5 | 委员长 FEDERATION_SENIOR | 联邦 | 中层 | 3 | 2 年 | 12 |
| 6 | 执政 FEDERATION_MINISTER | 联邦 | 高层 | 10 | 终身 | 2 |
| 7 | 法官 TRIBUNAL_JUDGE | 法庭 | 基层 | 1 | 1 年 | 60 |
| 8 | 大法官 TRIBUNAL_SENIOR | 法庭 | 中层 | 3 | 2 年 | 12 |
| 9 | 首席 TRIBUNAL_CHIEF | 法庭 | 高层 | 10 | 终身 | 2 |
| 10 | 理事 COUNCIL_MEMBER | 理事会 | 基层 | 0 | 1 年 | 12 |
| 11 | 常务理事 COUNCIL_SENIOR | 理事会 | 中层 | 0 | 1 年 | 4 |
| 12 | 理事长 COUNCIL_CHAIR | 理事会 | 高层 | 0 | 4 年 | 2 |
| 13 | 元老 ELDER | 元老院 | — | 0 | 终身 | 任命 9 / 退休无限 |
| 14 | 公民 CITIZEN | 基金会 | — | 1 | 无任期 | 无上限 |

### 3.2 SBT 不可转让

AetherRing 继承 ERC721，重写 `_update` 阻止所有非铸造/销毁的转让路径：

```solidity
function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
    address from = _ownerOf(tokenId);
    if (from != address(0) && to != address(0)) revert NonTransferable();
    return super._update(to, tokenId, auth);
}
```

`approve` / `setApprovalForAll` 直接 revert，确保道环与身份永久绑定。

### 3.3 任期与到期机制

- **被动到期**：`isBearer` / `getTier` 直接比较 `block.timestamp >= termEndAt`，无需主动触发
- **主动标记**：`markExpiredIfDue` 任何人可调用，置 `isExpired=true` 并 emit 事件
- **不可连任**：`MAX_CONSECUTIVE_TERMS = 0`，到期后必须重新选举

### 3.4 公民休眠机制

- **触发**：公民 2 年（`DORMANCY_PERIOD = 730 days`）未参与任何治理活动（投票/提案）
- **效果**：`isDormant=true`，不计入 `getActiveCitizens()`，不参与 quorum 分母
- **解除**：捐款时 `reactivateDormantCitizen` 重新激活，或主动调用
- **目的**：防止僵尸公民膨胀导致 quorum 失效

### 3.5 元老双轨制

- **退休元老**（`isRetiredElder`）：tier 3/6/9/12 高层退休自动转 tier 13，**无治理权**
- **任命元老**（`isAppointedElder`）：Safe 多签 `appointElder` 任命，**有治理权**（否决/弹劾发起/紧急拨款批准）
- **上限**：任命元老最多 9 人（`APPOINTED_ELDER_LIMIT`），退休元老无上限

---

## 四、治理系统：AetherGovernance

### 4.1 三院分权制衡

```
┌─────────────────────────────────────────────────────────────┐
│                       加权计票                                │
│                                                              │
│   议会（20%）    联邦（20%）    法庭（20%）    公民（60%）    │
│   ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐     │
│   │权重 1/3/10│   │权重 1/3/10│   │权重 1/3/10│   │  每人 1  │     │
│   │多数决    │    │多数决    │    │多数决    │    │  票      │     │
│   └───┬────┘    └───┬────┘    └───┬────┘    └───┬────┘     │
│       │              │              │              │          │
│       └──────────────┴──────┬───────┴──────────────┘          │
│                              ▼                                │
│                   总支持率 = 三院支持率 + 公民支持率            │
│                   通过门槛 > 50%（PASS_THRESHOLD_BPS = 5000）  │
└─────────────────────────────────────────────────────────────┘
```

- **三院内部权重**：基层 1 / 中层 3 / 高层 10，多数决出 FOR/AGAINST/NEUTRAL
- **公民 quorum**：普通提案 ≥20%，章程修订 ≥50%
- **公民票权重 60%**：三院各 20%（共 60%），公民 60%

### 4.2 七阶段提案流程（12 状态）

```
Drafting ──advance──► PendingFirstVote ──startFirstVote──► FirstVoteActive
   │                                                                          │
   │                                                                          │ finalizeFirstVote
   │ returnProposal                                                           │ (议会多数决)
   │ (2 理事联署)                                                              ▼
   ▼                                                              Passed ──► PendingFormal
ReturnedToDraft                                                              │
   │                                                                          │ submitFormalProposal
   │ resubmitFromReturn                                                       ▼
   └──────────────────────────────► Drafting                       PendingCompliance
                                                                              │ finalizeCompliance
                                                                              │ (法庭合规)
                                                                              ▼
                                                                    PublicVoteActive
                                                                              │ finalizeProposal
                                                                              │ (加权计票)
                                                                              ▼
                                                                   PendingVeto ◄── vetoProposal
                                                                              │     (3 元老联署)
                                                                              │ finalizeVetoWindow
                                                                              │ (72h 窗口结束)
                                                                              ▼
                                                                         Queued
                                                                              │ executeProposal
                                                                              │ (Timelock 到期)
                                                                              ▼
                                                                        Executed

失败路径：Defeated（一审/公投未过）/ Canceled（被否决/取消）
```

### 4.3 提案类型

| 类型 | 用途 | 执行方式 |
|---|---|---|
| SIGNAL | 信号提案（无链上执行） | 仅记录投票结果 |
| PARAM | 参数修改（治理参数） | 调用 `setVotingPeriods` / `setTimelocks` / `setInternalWeight` |
| TREASURY | 金库操作（转账） | `target.call{value}(calldataPayload)` |
| IMPEACHMENT | 弹劾（特殊流程） | `ring.revokeRing(targetRingId)` |

### 4.4 弹劾机制

```
3 任命元老发起 ──► createImpeachmentProposal (Drafting)
                              │
3 任命元老联署 ──► signImpeachment (达 3 签名自动进入 PublicVoteActive)
                              │
                     公投（公民参与 ≥40% + 支持率 ≥60%）
                              │
                              ▼ finalizeImpeachment
                    通过 → revokeRing（撤销道环）/ 不通过 → Defeated
```

- **不可否决**：弹劾提案排除元老否决权（V5 决策）
- **快照**：`signImpeachment` 达阈值时快照 `getActiveCitizens()`

### 4.5 紧急拨款

- **触发**：提案标记 `urgency = Emergency`
- **批准**：3 任命元老 `approveEmergencyTreasury`
- **Timelock**：12 小时（普通 48 小时）
- **执行**：`executeProposal` 检查 `emergencyApprovals >= 3`

### 4.6 理事长信任投票

- **触发**：8 理事联署 `signConfidenceTrigger`
- **投票**：理事投 FOR/AGAINST，7 天窗口
- **结果**：不通过则理事长 30 天内辞职

---

## 五、选举系统：AetherElection

### 5.1 三种选举类型

| 类型 | 候选人资格 | 选举人资格 | 目标 |
|---|---|---|---|
| MEMBER_TO_GRASSROOTS | 公民或到期三院成员 | 全体活跃公民 | 三院基层（1/4/7）|
| GRASSROOTS_TO_MID | 对应院基层 | 对应院基层 | 三院中层（2/5/8）|
| CITIZEN_TO_COUNCIL | 仅公民 | 全体活跃公民 | 理事/常务理事（10/11）|

### 5.2 四阶段状态机

```
Pending ──advanceToCouncilReview──► CouncilReview ──advanceToParliamentApproval──► ParliamentApproval
(候选人注册)                          (理事会审批)                                   (议会审批)
                                                                                        │
                                                                                        │ forceAdvanceToVoting
                                                                                        ▼
                                                               Active ◄── parliamentApproveCandidateList
                                                              (投票)
                                                                │ finalizeElection
                                                                ▼
                                                    ┌───────────────────────┐
                                                    │                       │
                                              Finalized              PartiallyFilled
                                            (满席当选)                (未满，理事长 appointToVacancy 填补)
```

### 5.3 时间窗口

| 阶段 | 时长 |
|---|---|
| 候选人注册 | 7 天 |
| 理事会审查 | 3 天 |
| 议会审批 | 3 天 |
| 投票 | 7 天 |
| 无人参选延长 | +7 天（仅一次）|

### 5.4 当选规则

- 得票前 N 名（N=seatCount）
- 平票按注册时间先后（早者排前）
- 候选人少于席位 → `PartiallyFilled`，理事长可 `appointToVacancy` 填补

### 5.5 任期不可连任

v3 删除了 `REELECTION` 类型和 `renewTerm` 函数，所有任期到期后必须重新走选举流程。

---

## 六、捐款系统：AetherDonation

### 6.1 捐款流程

```
1. 用户在 PayPal 完成 ≥$10 捐款
2. PayPal webhook 服务端验证交易
3. 服务端调用 donation.mintDonation(donor, amount, paypalTxId, paypalAccountHash)
4. 合约四重校验：
   ─ amount >= $10 (MIN_DONATION_USD)
   ─ usedPaypalTxIds[paypalTxId] == false (防重放)
   ─ paypalAccountToWallet[hash] 未绑定其他钱包 (防女巫)
   ─ ring.canReacquireCitizenship(donor) (30 天冷却期)
5. 铸捐款凭证 NFT（每笔都铸）
6. 首次捐款 → ring.mintRing(donor, CITIZEN, "") 铸公民道环
   休眠公民 → ring.reactivateDormantCitizen(donor) 重新激活
   已活跃公民 → 仅铸捐款凭证
7. Safe 多签 USDC 转账后，donation.settleDonation(tokenId, usdcAmount)
```

### 6.2 防女巫机制

- **PayPal 账户去重**：`paypalAccountToWallet[keccak256(payer_id)]` 绑定钱包，一个 PayPal 账户只能对应一个钱包
- **同一钱包可多次捐款**：绑定后允许同钱包重复捐款
- **3 公民担保快速通道**：3 名公民 `sponsorDonation` 可激活 24 小时快速通道（否则 7 天普通通道）

### 6.3 捐款凭证 SBT

- 不可转让（同 AetherRing）
- 永久记录捐款历史
- 含 `isSettled` 字段标记 USDC 是否已结算

---

## 七、安全设计

### 7.1 角色权限矩阵

| 角色 | 持有者 | 权限 |
|---|---|---|
| DEFAULT_ADMIN_ROLE | Safe 多签 | 授予/撤销其他角色 |
| ADMIN_ROLE | Safe 多签 | setTreasury / setRingContract / grantMinterRole / settleDonation |
| MINTER_ROLE | PayPal webhook 服务端 | mintDonation |
| PROPOSER_ROLE | 三院成员（tier 1-9）| createProposal |
| COUNCIL_CHAIR_ROLE | 理事长 | approveCandidate / rejectCandidate / appointToVacancy |
| GOVERNANCE_ROLE | Governance 合约 | ring.markVoteActivity |
| ELECTION_ROLE | Election 合约 | ring.markVoteActivity |

### 7.2 Timelock 机制

| 类型 | Timelock |
|---|---|
| 普通金库操作 | 48 小时 |
| 紧急金库操作 | 12 小时（+ 3 元老批准）|
| 元老否决窗口 | 72 小时 |

### 7.3 已知审计状态

详见 [V3_AUDIT_REPORT.md](./V3_AUDIT_REPORT.md)。主网部署前需修复 3 个 Critical + 10 个 High 问题。

---

## 八、前端架构

### 8.1 技术栈

- Next.js 15（App Router）
- wagmi v2 + Viem（以太坊交互）
- next-intl（8 语言国际化）
- Tailwind CSS（样式）

### 8.2 Hooks 层

5 个核心 hooks 对接 4 个合约：

| Hook | 合约 | 功能 |
|---|---|---|
| useRingInfo | AetherRing | 身份查询、14 tier、休眠状态 |
| useGovernance | AetherGovernance | 7 阶段提案、投票、否决 |
| useImpeachment | AetherGovernance | 弹劾发起、联署、公投 |
| useElection | AetherElection | 4 阶段选举、空缺填补 |
| useDonation | AetherDonation | 捐款查询、担保、结算 |

### 8.3 配置层

- `config.ts`：支持 Arbitrum One / Sepolia / Anvil，链专属 + 通用环境变量两级回退
- `index.ts`：14 tier + 12 status + 新枚举定义，与合约 ABI 对齐

---

## 九、治理参数速查

| 参数 | 值 | 可调 |
|---|---|---|
| 三院权重 | 各 20% | 否（常量）|
| 公民权重 | 60% | 否（常量）|
| 通过门槛 | >50% | 否（常量）|
| 普通 quorum | 20% | 否（常量）|
| 章程 quorum | 50% | 否（常量）|
| 一审时长 | 5 天 | 是（PARAM）|
| 公投时长 | 7 天 | 是（PARAM）|
| 合规审查 | 3 天 | 是（PARAM）|
| 普通 Timelock | 48 小时 | 是（PARAM）|
| 紧急 Timelock | 12 小时 | 是（PARAM）|
| 元老否决窗口 | 72 小时 | 否（常量）|
| 弹劾联署 | 3 任命元老 | 否（常量）|
| 弹劾参与率 | ≥40% | 否（常量）|
| 弹劾通过率 | ≥60% | 否（常量）|
| 公民休眠期 | 2 年 | 否（常量）|
| 公民放弃冷却 | 30 天 | 否（常量）|
| 任命元老上限 | 9 | 否（常量）|

---

## 十、路线图

- **Phase 1-6**：✅ 完成（AetherRing / Donation / Governance / Election / 集成测试 / 前端对接）
- **Phase 7**：安全审计修复 + 主网部署（待执行）
- **Phase 8**：PayPal webhook 服务端开发 + IPFS 集成
- **Phase 9**：UI 组件适配 v3 枚举 + 移动端优化
- **Phase 10**：外部审计公司复核（Trail of Bits / OpenZeppelin）

---

**白皮书结束**

> 本白皮书基于 v3.0 代码库编写。最新版本请参考 [GitHub 仓库](https://github.com/)。
