# Aether DAO v3.0 升级设计议论文档

> **版本**：v3.0 设计定稿
> **日期**：2026年7月
> **基于**：Aether基金会链上治理系统技术白皮书 v3.0 + 现有 v2 代码库
> **状态**：✅ 全部决策已确认（23 项设计决策 + 14 项漏洞补丁 = 37 项，v3.0 开发无阻塞）

---

## 目录

1. [概述](#1-概述)
2. [白皮书 v3.0 核心变化](#2-白皮书-v30-核心变化)
3. [已确认决策（Q1-Q10 + R1-R10 + 补充）](#3-已确认决策)
4. [选举三层产生机制（补充确认）](#4-选举三层产生机制)
5. [AetherRing v3 改动分析](#5-aetherring-v3-改动分析)
6. [AetherGovernance v3 改动分析](#6-aethergovernance-v3-改动分析)
7. [AetherElection v3 改动分析](#7-aetherelection-v3-改动分析)
8. [AetherDonation 新合约设计](#8-aetherdonation-新合约设计)
9. [跨合约依赖与接口变更](#9-跨合约依赖与接口变更)
10. [技术难点与风险](#10-技术难点与风险)
11. [最终开发顺序](#11-最终开发顺序)
12. [决策追踪表（全部已确认）](#12-决策追踪表)

---

## 1. 概述

v3.0 白皮书相比 v2 是一次**架构级重构**，核心变化：

- 权级体系：10 级 → 14 级
- 机构：3 院 → 5 机构（议会/联邦/法庭/理事会/元老院）
- 治理流程：4 阶段 → 7 阶段
- 计票规则：方案 B（三院共识 + 加权）→ 新方案（三院各 20% + 公民 60%）
- 新增合约：AetherDonation（PayPal 捐款 NFT 凭证）
- 任期：可连任 1 次 → 不可连任

复杂度较 v2 增加 **2-3 倍**，主要在治理流程与多机构制衡。

---

## 2. 白皮书 v3.0 核心变化

### 2.1 权级体系：10 级 → 14 级

| tier | v2 | v3 | 变化 |
|---|---|---|---|
| 1 | 议员 | 议员 | ✅ 不变 |
| 2 | 参议员 | 参议员 | ✅ 不变 |
| 3 | 议长 | 议长 | ✅ 不变 |
| 4 | 委员 | 委员 | ✅ 不变 |
| 5 | 委员长 | 委员长 | ✅ 不变 |
| 6 | 部长（FEDERATION_MINISTER） | 执政 | 🔄 改名 |
| 7 | 顾问（元老院） | 法官（法庭） | 🔴 替换 |
| 8 | 研究员（元老院） | 大法官（法庭） | 🔴 替换 |
| 9 | 元老（元老院高层） | 首席（法庭高层） | 🔴 替换 |
| 10 | 普通会员（GENERAL_MEMBER） | 理事（理事会基层） | 🔴 重定义 |
| 11 | — | 常务理事 | 🆕 新增 |
| 12 | — | 理事长 | 🆕 新增 |
| 13 | — | 元老（独立机构） | 🆕 新增 |
| 14 | — | 公民（原 v2 tier 10） | 🆕 新增 |

### 2.2 机构：3 院 → 5 机构

| v2 | v3 |
|---|---|
| 议会 / 联邦 / 元老院 | 议会 / 联邦 / **法庭** / **理事会** / **元老院** |

元老院从"tier 7-9 的一个院"变成"独立 tier 13 的监督机构"。

### 2.3 席位上限

| 层级 | v2 | v3 |
|---|---|---|
| 三院基层（每院） | 20 | **60** |
| 三院中层（每院） | 4 | **12** |
| 三院高层（每院） | 2 | 2 |
| 理事会理事 | — | 12 |
| 理事会常务理事 | — | 4 |
| 理事会理事长 | — | 2 |
| 元老 | — | ∞（无上限） |
| 公民 | ∞ | ∞ |

总席位：v2=78 → v3=222（三院）+ 18（理事会）+ 元老无上限 + 公民变量。

### 2.4 任期 & 连任

| 项 | v2 | v3 |
|---|---|---|
| 基层任期 | 365 days | 365 days |
| 中层任期 | 730 days | 730 days |
| 高层任期 | 终生 | 终生，可荣誉退休 |
| 连任上限 | 1 次 | **0（不可连任）** |

### 2.5 内部投票权重

| 层级 | v2 | v3 |
|---|---|---|
| 基层 | 2 | **1** |
| 中层 | 5 | **3** |
| 高层 | 20 | **10** |
| 理事会 | — | **0** |
| 元老 | — | **0** |
| 公民 | 1 | **1** |

### 2.6 计票规则

**v2 方案 B**：
```
三院共识 ≥2 院 + 会员参与率 ≥30% + 反对率 <60% + 加权(院2/3 + 会员1/3) > 50%
```

**v3 新方案**：
```
议会 20% + 联邦 20% + 法庭 20% + 公民 60% = 100%
每院内部多数决（1/3/10 加权）→ FOR/AGAINST
总赞成 = Σ(FOR院 × 20%) + 公民赞成率 × 60%
通过 = 总赞成 > 50% 且 公民参与率 ≥ 20%
```

### 2.7 治理流程：4 阶段 → 7 阶段

**v2**：createProposal → vote → finalize → execute

**v3**：
```
联邦发起提议 → 理事会整理 → 议会第一轮投票 → 理事会发起正式提案 → 法庭合规审查 → 三院+公民公投 → 元老院否决窗口 → 国库执行
```

### 2.8 新增合约

| 合约 | 状态 |
|---|---|
| AetherRing.sol | 🔴 需 v3 重构 |
| AetherGovernance.sol | 🔴 需 v3 重构 |
| AetherElection.sol | 🟡 需调整 |
| **AetherDonation.sol** | 🆕 全新 |

---

## 3. 已确认决策

全部 21 项决策已确认（Q1-Q10 + R1-R10 + R3-补充 + 选举三层机制 + 捐款门槛）。

### 3.1 白皮书模糊点（Q1-Q10）

| 编号 | 议题 | 决策 |
|---|---|---|
| Q1 | 法庭合规审查 | 链上投票（复用现有基础设施） |
| Q2 | 元老院否决 | 72h 窗口，≥3 人联署，内部多数决，永久终止 |
| Q3 | 理事会整理/退回 | 理事长可推进，≥2 理事联署可退回 |
| Q4 | 一审 vs 公投 | 同一 proposalId，分阶段，独立窗口（5天+7天） |
| Q5 | 公民身份 | 捐赠即获得，无任期，可自愿放弃 |
| Q6 | 理事会任命 | 理事/常务理事由公民选举；理事长由多签任命（见 R3-补充） |
| Q7 | 公民 quorum | ≥20% 参与率，未达标自动失败 |
| Q8 | Donation NFT | ERC-721 SBT，不可转让，不分档，链下兑换+链上 settle |
| Q9 | 弹劾 | 元老院发起（≥3人），公民投票 ≥40%/≥60% 通过 |
| Q10 | internalWeight | 理事会/元老=0，公民=1，三院=1/3/10 |

### 3.2 实现细节（R1-R10 + R3-补充）

#### R1. 计票公式 ✅

- **公式**：`总赞成 = (FOR 的院数 × 20%) + (公民赞成率 × 60%)`
- **通过**：`总赞成 > 50% 且 公民参与率 ≥ 20%`
- 院方 AGAINST **不减分**，只是该院不贡献 20% 赞成权重
- 三院全 FOR + 公民 0% 参与 = 60% 赞成，但因 quorum 未达标（0% < 20%）→ **失败**
- 公民 quorum 分母 = **全体公民快照**（提案进入公投阶段时的公民总数）

#### R2. 法庭不合规后处理 ✅

退回 Drafting（草稿状态），允许提议人修改后重新走流程。合规审查目的是指出问题、退回修改，而非一票否决。

#### R3. 理事任期 ✅

理事（tier 10）和常务理事（tier 11）由公民选举产生：
- 选举类型：`CITIZEN_TO_COUNCIL`
- 选举人：全体公民
- 任期：365 天，不可连任
- 当选规则：得票前 N 名（理事 12 名，常务理事 4 名）

#### R3-补充. 理事长任命 ✅

理事长（tier 12）由多签钱包直接任命，需三院高层 2/3 同意。

**流程**：
1. 多签提名理事长候选人
2. 三院高层审议（议长/执政/首席共 6 人，需 ≥4 人同意）
3. 多签执行任命，铸造 `COUNCIL_CHAIR` 道环

**任期与轮换**：
- 任期：**4 年**
- 可连任，但需重新走完整的任命流程
- 可荣誉退休，退休后编入元老院
- 适用通用弹劾流程

#### R4. 弹劾目标范围 ✅

可弹劾 tier 1-13（三院 + 理事会 + 元老），**不可弹劾公民（tier 14）**。公民持有"投票权"而非"治理权力"，滥用投票权由 quorum 和投票机制本身制衡。

#### R5. 到期后重新参选资格 ✅

方案 B：保留原 tier + isExpired 标记。
- 到期后：tier 不变，`isExpired = true`
- 选举合约资格检查放宽：`tier == 14（公民）或 isExpired == true` 均可参选基层
- 省 Gas，保留历史身份（链上可追溯"曾担任过什么职务"）

#### R6. 元老否决窗口与 Timelock ✅

**串行**：
```
公投通过 → PendingVeto(72h) → 否决或超时 → Queued(Timelock 48h) → Executed
```
否决窗口内不执行任何操作，避免状态混乱。

#### R7. 退休后 tier ✅

方案 A：tier 改为 13（ELDER）。
- 退休后：`tier = 13`，`isActive = false`
- 原 tier 的席位计数减 1
- ELDER 无上限，不做席位检查
- 符合白皮书"→ 元老"，getTier 返回 13 即可被外部识别为元老

#### R8. AetherDonation MINTER_ROLE ✅

方案 A + 限制：
- MINTER_ROLE 归属 PayPal webhook 服务端
- 限制：只能 mint 未 settle 状态的凭证，无法伪造 USDC 注入
- `settleDonation` 权限归属多签（ADMIN_ROLE），仅多签可调用，且 USDC 真实到账后才可 settle

**风险缓解**：
- MINTER_ROLE 泄露 → 只能伪造未 settle 凭证（影响有限，无资金损失）
- `paypalTxId` 防重放（合约记录已用 ID）
- 定期审计未 settle 凭证

#### R9. 公民放弃身份后 ✅

- 放弃 = 撤销道环（`_burn`）
- 可再次捐赠获取公民身份（**≥ $10**，见 §3.3）
- 历史投票记录保留（按地址历史，链上数据不可抹除）

#### R10. 合约拆分策略 ✅

方案 A 优先，编译后评估；若超限则采用方案 B。
- **第一步**：将计票逻辑、状态转换逻辑抽取为 `AetherGovernanceLib` library
- **第二步**：编译后检查字节码体积
- **第三步**：若仍超 24KB，拆分为 AetherGovernance（核心）+ AetherProposalFlow（7 阶段流程）

### 3.3 捐款门槛 ✅（补充确认）

- 公民身份获取门槛：**PayPal 捐款 ≥ $10**
- AetherDonation 合约常量：`MIN_DONATION_USD = 10 * 10**6`（USDC 6 decimals）
- mintDonation 时检查 `amount >= MIN_DONATION_USD`，不达标 revert

---

## 4. 选举三层产生机制

### 4.1 基层产生（公民自荐 → 选举）

```
公民自荐 → 理事会整理候选人名单 → 议会审批 → 理事会发起提案 → 全体公民投票 → 得票前 60 名当选
```

- **适用 tier**：1（议员）/ 4（委员）/ 7（法官）/ 10（理事）/ 11（常务理事）
- **选举人**：全体公民（tier 14）
- **候选人**：公民自荐（tier 14）或到期成员（isExpired）
- **当选规则**：得票前 N 名（三院基层 N=60/院；理事 N=12；常务理事 N=4）
- **任期**：365 天，不可连任

### 4.2 中层产生（高层提名 → 选举）

```
高层提名候选人（须为现任基层）→ 议会审批 → 理事会发起提案 → 对应院基层投票 → 得票前 12 名当选
```

- **适用 tier**：2（参议员）/ 5（委员长）/ 8（大法官）
- **选举人**：对应院的基层成员（如选参议员 = 议员投票）
- **候选人**：由高层提名，须为现任基层（tier 1/4/7）
- **当选规则**：得票前 12 名
- **任期**：730 天，不可连任

### 4.3 高层产生（创世制定 / 递补）

```
创世：多签直接制定
递补：多签提名候选人 → 三院现任高层 2/3 同意 → 任命
```

- **适用 tier**：3（议长）/ 6（执政）/ 9（首席）/ 12（理事长）
- **创世**：部署时由多签直接制定
- **递补**：多签提名 → 三院现任高层（议长+执政+首席共 6 人，理事长任命需含理事长）≥ 2/3 同意（≥4 人）→ 多签执行任命
- **任期**：终生（理事长 4 年，可连任），可荣誉退休

### 4.4 对 AetherElection 合约的影响

选举流程从 v2 的"单步选举"变为**多阶段流程**：

```
候选人注册/提名 → 理事会整理（approve/reject）→ 议会审批（链上投票）→ 公民/院基层投票 → finalize
```

**实现方案**（待第 7 章详述）：
- AetherElection 引入 `ElectionStage` 状态机：`CandidateRegistration → CouncilReview → ParliamentApproval → Voting → Finalized`
- 候选人审批（理事会整理 + 议会审批）作为选举的前置阶段，链上留痕
- 实际投票阶段才计算得票

---

## 5. AetherRing v3 改动分析

### 5.1 权级枚举重构（破坏性）

```solidity
enum RingTier {
    NONE,                    // 0
    PARLIAMENT_MEMBER,       // 1  议员（基层）
    PARLIAMENT_SENIOR,       // 2  参议员（中层）
    PARLIAMENT_SPEAKER,      // 3  议长（高层）
    FEDERATION_MEMBER,       // 4  委员（基层）
    FEDERATION_SENIOR,       // 5  委员长（中层）
    FEDERATION_MINISTER,     // 6  执政（高层，原"部长"改名）
    TRIBUNAL_JUDGE,          // 7  法官（基层，原"顾问"替换）
    TRIBUNAL_SENIOR,         // 8  大法官（中层，原"研究员"替换）
    TRIBUNAL_CHIEF,          // 9  首席（高层，原"元老"替换）
    COUNCIL_MEMBER,          // 10 理事（理事会基层，原"普通会员"重定义）
    COUNCIL_SENIOR,          // 11 常务理事
    COUNCIL_CHAIR,           // 12 理事长
    ELDER,                   // 13 元老（独立机构）
    CITIZEN                  // 14 公民（原 v2 tier 10）
}
```

**影响文件**：
- `AetherRing.sol` enum + `_levelOf` + `_seatLimitOf`
- `index.ts` `RingTier` + `TIER_LABELS` + `chamberOf`
- `AetherGovernance.sol` `internalWeight` 初始化 + `_accumulateVote`

### 5.2 席位上限调整

```solidity
uint256 public constant GRASSROOTS_LIMIT = 60;  // v2: 20
uint256 public constant MID_LIMIT = 12;          // v2: 4
uint256 public constant HIGH_LIMIT = 2;          // 不变

// 新增理事会席位
uint256 public constant COUNCIL_MEMBER_LIMIT = 12;
uint256 public constant COUNCIL_SENIOR_LIMIT = 4;
uint256 public constant COUNCIL_CHAIR_LIMIT = 2;

// 元老无上限（不检查）
// 公民无上限（不检查）
```

`_seatLimitOf` 需按具体 tier 细分，不再只按 TierLevel。

### 5.3 任期 & 连任

```solidity
uint8 public constant MAX_CONSECUTIVE_TERMS = 0;  // v2: 1，v3: 0（不可连任）
```

**连锁影响**：
- `renewTerm` 函数逻辑需调整（或删除）
- AetherElection 的 `REELECTION` 类型应删除

### 5.4 EMERITUS 退休 → 自动转元老

v2 退休逻辑：保留原 tier + isEmeritus 标记。

v3 退休逻辑：
- 退休 = tier 变为 13（ELDER）
- 退休资格：三院高层（3/6/9）+ 理事长（12）
- tierCount 维护：原 tier -1，ELDER 不检查上限

```solidity
function retireToEmeritus(uint256 tokenId) external {
    _requireSafeWallet();
    RingInfo storage info = ringInfo[tokenId];
    RingTier oldTier = info.tier;
    
    // 仅高层 + 理事长可退休
    if (!_isRetirable(oldTier)) revert InvalidTier();
    
    _tierCount[uint8(oldTier)] -= 1;
    info.tier = RingTier.ELDER;  // 转为元老
    info.isActive = false;       // 无投票权
    info.isEmeritus = true;
    // ELDER 无上限，不做席位检查
    
    emit RingRetired(tokenId, holder);
}
```

### 5.5 新增 renounceCitizenship（公民自愿放弃）

```solidity
function renounceCitizenship() external {
    uint256 ringId = walletToRingId[msg.sender];
    if (ringId == 0) revert RingDoesNotExist(ringId);
    RingInfo storage info = ringInfo[ringId];
    if (info.tier != RingTier.CITIZEN) revert InvalidTier();
    
    _tierCount[uint8(RingTier.CITIZEN)] -= 1;
    walletToRingId[msg.sender] = 0;
    _burn(ringId);
    emit RingRevoked(ringId, msg.sender);
}
```

### 5.6 getTotalMembers → getTotalCitizens

v2 `getTotalMembers()` 返回 tier 10 计数。v3 改为 `getTotalCitizens()` 返回 tier 14 计数，用于治理合约公投 quorum 分母。

---

## 6. AetherGovernance v3 改动分析

### 6.1 计票规则重写

**Proposal struct 调整**：
```solidity
struct Proposal {
    // ... 原有字段
    uint256 tribunalFor;       // 原 senateFor
    uint256 tribunalAgainst;   // 原 senateAgainst
    uint256 citizenFor;        // 原 memberFor
    uint256 citizenAgainst;    // 原 memberAgainst
    uint256 citizenAbstain;    // 原 memberAbstain
    uint256 citizenTotalSnapshot;
    // ...
}
```

**常量调整**：
```solidity
uint256 public constant CHAMBER_WEIGHT_BPS = 2_000;  // 每院 20%（v2: 6_667）
uint256 public constant CITIZEN_WEIGHT_BPS = 6_000;  // 公民 60%（v2: 3_333）
uint256 public constant PASS_THRESHOLD_BPS = 5_000;  // >50%（不变）
uint256 public constant CITIZEN_QUORUM_BPS = 2_000;  // ≥20%（v2: 3_000）
// 删除 MEMBER_VETO_BPS（v3 无绝对否决）
```

**计票逻辑**：
```solidity
function _finalizeNormal(uint256 proposalId, Proposal storage p) internal {
    // 1. 每院内部多数决
    ChamberStance parliamentStance = _stanceOf(p.parliamentFor, p.parliamentAgainst);
    ChamberStance federationStance = _stanceOf(p.federationFor, p.federationAgainst);
    ChamberStance tribunalStance = _stanceOf(p.tribunalFor, p.tribunalAgainst);
    
    // 2. 公民参与率检查
    uint256 citizenVotes = p.citizenFor + p.citizenAgainst + p.citizenAbstain;
    bool quorumMet = (citizenVotes * BPS_DENOMINATOR) / p.citizenTotalSnapshot >= CITIZEN_QUORUM_BPS;
    
    // 3. 加权计算
    uint256 chamberForBps = (_countStance(parliamentStance, FOR) 
                            + _countStance(federationStance, FOR)
                            + _countStance(tribunalStance, FOR)) * CHAMBER_WEIGHT_BPS;
    
    uint256 citizenForBps = citizenVotes > 0 
        ? (p.citizenFor * BPS_DENOMINATOR) / citizenVotes 
        : 0;
    
    uint256 totalFor = (chamberForBps + citizenForBps * CITIZEN_WEIGHT_BPS) / BPS_DENOMINATOR;
    
    bool passed = quorumMet && totalFor > PASS_THRESHOLD_BPS;
    // ...
}
```

### 6.2 7 阶段状态机

```solidity
enum ProposalStatus {
    Drafting,            // 0  联邦提议
    PendingFirstVote,    // 1  理事长已推进，等议会一审开始
    FirstVoteActive,     // 2  议会一审投票中（5天）
    PendingFormal,       // 3  一审通过，等理事会提交正式版
    PendingCompliance,   // 4  正式版已提交，等法庭审查
    PublicVoteActive,    // 5  公投中（7天，三院+公民）
    PendingVeto,         // 6  公投通过，元老否决窗口（72h）
    Queued,              // 7  Timelock
    Executed,            // 8  终态
    Defeated,            // 9  终态
    Canceled,            // 10 终态（含元老否决）
    ReturnedToDraft      // 11 理事会退回 / 法庭不合规退回
}
```

**状态转换函数**：
- `advanceProposal(id)`：Drafting → PendingFirstVote（理事长调）
- `returnProposal(id)`：Drafting → ReturnedToDraft（≥2 理事联署）
- `startFirstVote(id)`：PendingFirstVote → FirstVoteActive
- `finalizeFirstVote(id)`：FirstVoteActive → PendingFormal / Defeated
- `submitFormalProposal(id)`：PendingFormal → PendingCompliance
- `startComplianceVote(id)`：PendingCompliance → 法庭审查投票
- `finalizeCompliance(id)`：通过 → PublicVoteActive / 不合规 → ReturnedToDraft
- `finalizeProposal(id)`：PublicVoteActive → PendingVeto / Defeated
- `vetoProposal(id)`：PendingVeto 期间元老联署，≥3 → Canceled
- `finalizeVetoWindow(id)`：72h 到 → Queued
- `executeProposal(id)`：Queued → Executed

### 6.3 法庭合规审查

复用投票基础设施：
- 法庭成员（tier 7/8/9）投票：合规/不合规
- 内部权重 1/3/10
- 通过 = 赞成权重 > 反对权重
- 不合规 → ReturnedToDraft

Proposal struct 新增：
```solidity
uint256 tribunalComplianceFor;
uint256 tribunalComplianceAgainst;
mapping(address => bool) hasComplianceVoted;
```

### 6.4 元老否决

```solidity
// Proposal struct 新增
uint256 vetoSignatures;
uint256 requiredVetoSignatures;  // 3
mapping(address => bool) hasVetoed;

function vetoProposal(uint256 proposalId) external {
    Proposal storage p = proposals[proposalId];
    if (p.status != ProposalStatus.PendingVeto) revert NotPendingVeto();
    
    uint8 tier = ringContract.getTier(msg.sender);
    if (tier != 13) revert NotElder();  // 仅元老可否决
    if (p.hasVetoed[msg.sender]) revert AlreadyVetoed();
    
    p.hasVetoed[msg.sender] = true;
    p.vetoSignatures += 1;
    
    if (p.vetoSignatures >= p.requiredVetoSignatures) {
        p.status = ProposalStatus.Canceled;
        emit ProposalVetoed(proposalId);
    }
}
```

### 6.5 理事会整理/退回

```solidity
function advanceProposal(uint256 proposalId) external {
    Proposal storage p = proposals[proposalId];
    if (p.status != ProposalStatus.Drafting) revert NotDrafting();
    
    uint8 tier = ringContract.getTier(msg.sender);
    if (tier != 12) revert NotCouncilChair();  // 仅理事长可推进
    
    p.status = ProposalStatus.PendingFirstVote;
}

function returnProposal(uint256 proposalId) external {
    Proposal storage p = proposals[proposalId];
    if (p.status != ProposalStatus.Drafting) revert NotDrafting();
    
    uint8 tier = ringContract.getTier(msg.sender);
    if (tier < 10 || tier > 12) revert NotCouncilMember();
    if (p.hasSignedReturn[msg.sender]) revert AlreadySigned();
    
    p.hasSignedReturn[msg.sender] = true;
    p.returnSignatures += 1;
    
    if (p.returnSignatures >= 2) {
        p.status = ProposalStatus.ReturnedToDraft;
    }
}
```

### 6.6 两轮投票

```solidity
// Proposal struct 新增时间字段
uint256 firstVoteStartAt;
uint256 firstVoteEndAt;     // 5 days
uint256 publicVoteStartAt;
uint256 publicVoteEndAt;    // 7 days
uint256 vetoWindowEndAt;    // publicVoteEndAt + 72h
```

`inVotingPeriod` modifier 需根据当前阶段判断用哪个窗口。

### 6.7 弹劾重写

| 项 | v2 | v3 |
|---|---|---|
| 发起人 | 任何会员 | **元老（tier 13）** |
| 联署门槛 | 100 会员 | **3 元老** |
| 多签审查 | Safe 5/3 | **取消** |
| 公民 quorum | 50% | **40%** |
| 反对率 | 70% | **60%** |
| 目标范围 | 高层 3/6/9 | **待 R4 确认** |

```solidity
uint256 public constant IMPEACHMENT_VETO_SIGNATURES = 3;  // 元老联署
uint256 public constant IMPEACHMENT_QUORUM_BPS = 4_000;   // ≥40%
uint256 public constant IMPEACHMENT_PASS_BPS = 6_000;     // ≥60% 反对即弹劾成立

function createImpeachmentProposal(address target, string title, string ipfsHash) external {
    uint8 tier = ringContract.getTier(msg.sender);
    if (tier != 13) revert NotElder();  // 仅元老可发起
    // ...
}

function signImpeachment(uint256 proposalId) external {
    uint8 tier = ringContract.getTier(msg.sender);
    if (tier != 13) revert NotElder();  // 仅元老可联署
    // ...
}
```

### 6.8 合约体积风险 ⚠️

v2 AetherGovernance = **14.5KB（59.2%）**

v3 新增：
- 5 个状态转换函数 ~2KB
- 法庭审查投票 ~1KB
- 元老否决联署 ~1.5KB
- 理事会推进/退回 ~1KB
- 新计票 ~1KB
- 预计 **~21KB**，接近 24KB 限制

**应对**：见 R10，优先方案 A（library 抽取），超限则方案 B（拆合约）。

---

## 7. AetherElection v3 改动分析

### 7.1 删除 REELECTION

v3 不可连任 → `REELECTION` 类型 + `castReelectionAgainst` + `_applyReelection` 全部删除。

到期后重新参选走 `MEMBER_TO_GRASSROOTS`。

### 7.2 新增 CITIZEN_TO_COUNCIL（R3 决策）

理事和常务理事由公民选举产生：

```solidity
enum ElectionType {
    MEMBER_TO_GRASSROOTS,   // 公民 → 三院基层（原 MEMBER_TO_GRASSROOTS）
    GRASSROOTS_TO_MID,      // 三院基层 → 中层
    CITIZEN_TO_COUNCIL      // 公民 → 理事会理事/常务理事（新增）
    // 删除 REELECTION
}
```

```solidity
function createElection(
    ElectionType eType,
    uint8 targetChamber,     // 1=议会 2=联邦 3=法庭 4=理事 5=常务理事
    uint256 seatCount,
    address[] calldata candidates,
    address reelectionTarget // 删除此参数
) external onlyRole(ADMIN_ROLE) returns (uint256);
```

**CITIZEN_TO_COUNCIL 规则**：
- 选举人：全体公民（tier 14）
- 候选人：公民（tier 14）
- 当选：得票前 N 名
- 任期：365 days，不可连任

### 7.3 候选人资格放宽

```solidity
function _isEligibleCandidate(ElectionType eType, uint8 chamber, address candidate) internal view returns (bool) {
    uint8 tier = ringContract.getTier(candidate);
    bool isExpired = AetherRing(address(ringContract)).isExpired(ringContract.getRingId(candidate));
    
    if (eType == ElectionType.MEMBER_TO_GRASSROOTS) {
        return tier == 14 || (tier >= 1 && tier <= 9 && isExpired);  // 公民或到期成员
    }
    if (eType == ElectionType.CITIZEN_TO_COUNCIL) {
        return tier == 14;  // 仅公民可参选理事
    }
    if (eType == ElectionType.GRASSROOTS_TO_MID) {
        if (chamber == 1) return tier == 1;
        if (chamber == 2) return tier == 4;
        if (chamber == 3) return tier == 7;
    }
    return false;
}
```

### 7.4 tier 映射更新

```solidity
function _applyPromotion(ElectionType eType, uint8 chamber, address winner) internal {
    AetherRing.RingTier newTier;
    
    if (eType == ElectionType.MEMBER_TO_GRASSROOTS) {
        if (chamber == 1) newTier = AetherRing.RingTier.PARLIAMENT_MEMBER;
        else if (chamber == 2) newTier = AetherRing.RingTier.FEDERATION_MEMBER;
        else newTier = AetherRing.RingTier.TRIBUNAL_JUDGE;  // 原 SENATE_ADVISOR
    } else if (eType == ElectionType.GRASSROOTS_TO_MID) {
        if (chamber == 1) newTier = AetherRing.RingTier.PARLIAMENT_SENIOR;
        else if (chamber == 2) newTier = AetherRing.RingTier.FEDERATION_SENIOR;
        else newTier = AetherRing.RingTier.TRIBUNAL_SENIOR;  // 原 SENATE_FELLOW
    } else if (eType == ElectionType.CITIZEN_TO_COUNCIL) {
        if (chamber == 4) newTier = AetherRing.RingTier.COUNCIL_MEMBER;
        else newTier = AetherRing.RingTier.COUNCIL_SENIOR;
    }
    
    AetherRing(address(ringContract)).updateTier(ringId, newTier, true);
}
```

---

## 8. AetherDonation 新合约设计

### 8.1 合约结构

```solidity
contract AetherDonation is ERC721, AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    struct Donation {
        address donor;
        uint256 amount;        // USD 最小单位（6 decimals）
        uint256 usdcAmount;    // 实际注入国库 USDC
        string paypalTxId;
        uint256 timestamp;
        bool isSettled;
    }
    
    mapping(uint256 => Donation) public donations;
    IAetherRing public ringContract;  // 联动铸公民道环
    address public treasury;          // Safe 多签国库
    
    function mintDonation(
        address donor,
        uint256 amount,
        string calldata paypalTxId
    ) external onlyRole(MINTER_ROLE) returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(donor, tokenId);
        
        donations[tokenId] = Donation({
            donor: donor,
            amount: amount,
            usdcAmount: 0,
            paypalTxId: paypalTxId,
            timestamp: block.timestamp,
            isSettled: false
        });
        
        // 联动铸公民道环（如果 donor 还没有道环）
        if (!ringContract.isBearer(donor)) {
            ringContract.mintRing(donor, AetherRing.RingTier.CITIZEN, "");
        }
        
        emit DonationMinted(tokenId, donor, amount, paypalTxId);
        return tokenId;
    }
    
    function settleDonation(uint256 tokenId, uint256 usdcAmount) external onlyRole(ADMIN_ROLE) {
        Donation storage d = donations[tokenId];
        d.usdcAmount = usdcAmount;
        d.isSettled = true;
        emit DonationSettled(tokenId, usdcAmount);
    }
}
```

### 8.2 SBT 不可转让

复用 AetherRing 的 `_update` override 模式。

### 8.3 PayPal webhook 链上接入

```
PayPal 支付 → PayPal webhook → Vercel Serverless Function 
  → 持 MINTER_ROLE 私钥调 mintDonation(donor, amount, paypalTxId)
  → 多签注入 USDC 到国库后调 settleDonation(tokenId, usdcAmount)
```

**安全模型**：
- MINTER_ROLE 只能 mint 未 settle 状态（不能伪造 USDC 注入）
- settle 必须多签确认（USDC 真实到账后才 settle）
- 风险：MINTER_ROLE 泄露 → 伪造未 settle 捐款凭证（影响有限，无资金损失）

---

## 9. 跨合约依赖与接口变更

### 9.1 IAetherRing 接口扩展

v2：
```solidity
interface IAetherRing {
    function isBearer(address) external view returns (bool);
    function getTier(address) external view returns (uint8);
    function getRingId(address) external view returns (uint256);
    function getTotalMembers() external view returns (uint256);
}
```

v3：
```solidity
interface IAetherRing {
    function isBearer(address) external view returns (bool);
    function getTier(address) external view returns (uint8);
    function getRingId(address) external view returns (uint256);
    function getTotalCitizens() external view returns (uint256);  // 改名
    function isExpired(uint256 tokenId) external view returns (bool);
    function isEmeritus(address) external view returns (bool);
    // 新增 renounceCitizenship() 由公民直接调，不需要在 interface
}
```

### 9.2 部署依赖顺序

```
AetherRing 
  ↓
AetherDonation（grant MINTER_ROLE on AetherRing）
  ↓
AetherGovernance（grant ADMIN_ROLE on AetherRing）
  ↓
AetherElection（grant ADMIN_ROLE + MINTER_ROLE on AetherRing）
```

Deploy.s.sol 需新增 AetherDonation 部署 + 4 合约交叉授权。

### 9.3 前端 ABI 全部重新生成

- 3 个 .abi.ts 文件重新生成 + 新增 AetherDonation.abi.ts
- index.ts 枚举更新：14 tier + 新 ProposalStatus + 新 ElectionType + DonationStatus

---

## 10. 技术难点与风险

### 10.1 7 阶段状态机易出 bug

- 12 个状态 + 11 个转换函数
- 每个转换有严格的前置条件
- 需画完整状态图 + 全路径测试

**应对**：用 Foundry invariant 测试覆盖所有非法状态转换。

### 10.2 合约体积逼近 24KB

- AetherGovernance v3 预计 ~21KB
- 加测试覆盖后可能超限

**应对**：优先 library 抽取计票逻辑；超限则拆 AetherProposalFlow。

### 10.3 三机构权限交叉

- 理事会（理事长推进 / 理事联署退回）
- 法庭（合规审查投票）
- 元老院（否决联署）

需仔细设计 modifier，避免权限错位。

### 10.4 AetherDonation 链下链上衔接

- PayPal webhook → 服务端 → 链上 mint
- 私钥管理风险
- PayPal TxId 防重放

**应对**：服务端私钥隔离 + 合约记录已用 paypalTxId 防重放。

### 10.5 公民 quorum 分母

- 公民数量动态变化（捐赠随时增加）
- 公投开始时快照 citizenTotalSnapshot
- 防止投票中途新增公民稀释 quorum

---

## 11. 建议开发顺序

确认 R1-R10 后按以下顺序推进：

### 第 1 轮：AetherRing v3
- 14 tier enum
- 席位 60/12/2 + 理事会 12/4/2
- 不可连任（MAX_CONSECUTIVE_TERMS = 0）
- 退休转元老（tier → 13）
- renounceCitizenship
- getTotalCitizens

### 第 2 轮：AetherDonation（新合约，独立）
- ERC-721 SBT
- mintDonation + settleDonation
- 公民道环联动
- paypalTxId 防重放

### 第 3 轮：AetherGovernance v3
- 7 阶段流程
- 新计票（三院各 20% + 公民 60%）
- 法庭审查
- 元老否决
- 新弹劾（元老发起）
- 编译后检查体积，超 24KB 则拆分

### 第 4 轮：AetherElection v3
- 删除 REELECTION
- 新增 CITIZEN_TO_COUNCIL
- 候选人资格放宽（公民或到期成员）
- tier 映射更新

### 第 5 轮：测试 + 部署脚本 + 前端
- 4 个 .t.sol 重写
- Deploy.s.sol 更新
- 前端 ABI 重新生成
- hooks 更新（useRingInfo / useDonation / useGovernance / useElection）

---

## 12. 决策追踪表（全部已确认）

| 编号 | 议题 | 决策 | 状态 |
|---|---|---|---|
| Q1 | 法庭合规审查 | 链上投票 | ✅ |
| Q2 | 元老院否决 | 72h，≥3人，永久终止 | ✅ |
| Q3 | 理事会整理/退回 | 理事长推进，≥2理事退回 | ✅ |
| Q4 | 一审 vs 公投 | 同 proposalId，5天+7天 | ✅ |
| Q5 | 公民身份 | 捐赠即获得，可放弃 | ✅ |
| Q6 | 理事会任命 | 理事/常务理事公民选举；理事长多签任命 | ✅ |
| Q7 | 公民 quorum | ≥20% | ✅ |
| Q8 | Donation NFT | ERC-721 SBT，链下兑换+链上 settle | ✅ |
| Q9 | 弹劾 | 元老发起(≥3)，公民 40%/60% | ✅ |
| Q10 | internalWeight | 三院 1/3/10，理事会/元老 0，公民 1 | ✅ |
| R1 | 计票公式 | 总赞成=(FOR院数×20%)+(公民赞成率×60%)>50% 且 公民参与≥20%；quorum分母=公民快照 | ✅ |
| R2 | 法庭不合规后 | 退回 Drafting | ✅ |
| R3 | 理事任期 | 公民选举，365 days，不可连任 | ✅ |
| R3-补充 | 理事长任命 | 多签任命，三院高层 2/3 同意，任期 4 年可连任 | ✅ |
| R4 | 弹劾目标范围 | tier 1-13，不可弹劾公民 | ✅ |
| R5 | 到期后参选资格 | 保留 tier + isExpired | ✅ |
| R6 | 否决窗口与 Timelock | 串行（Veto 72h → Timelock 48h） | ✅ |
| R7 | 退休后 tier | 改为 13（ELDER），isActive=false | ✅ |
| R8 | MINTER_ROLE 归属 | 服务端持有，只能 mint 未 settle；settle 多签 | ✅ |
| R9 | 公民放弃后 | _burn，可再次捐赠（≥$10）获取 | ✅ |
| R10 | 合约拆分 | library 优先，超限拆 AetherProposalFlow | ✅ |
| 补充1 | 选举三层机制 | 基层公民普选 / 中层院基层选 / 高层多签任命 | ✅ |
| 补充2 | 捐款门槛 | ≥ $10（MIN_DONATION_USD = 10 * 10^6） | ✅ |

**全部 23 项决策已确认，可进入开发阶段。**

---

## 13. 漏洞与补丁分析

用户在决策确认后复审发现 14 项漏洞与优化建议。逐项分析如下，每项标注：
- **严重度**：🔴 高 / 🟡 中 / 🟢 低
- **类型**：漏洞 / 设计缺失 / 优化建议
- **状态**：✅ 采纳（已有方案）/ ⏳ 待用户拍板

---

### V1. 公民（tier 14）任期缺失 — 休眠机制

| 项 | 值 |
|---|---|
| 严重度 | 🔴 高 |
| 类型 | 设计缺失 |
| 状态 | ✅ 已确认 |

**问题**：公民无任期，quorum 分母会无限膨胀，长期看会让 20% 参与率门槛越来越难达成。

**用户建议**：连续 2 年未投票 → 标记"休眠公民"，不计入 quorum 分母，投票资格暂停。重新参与需新捐赠（≥$10）激活。

**技术分析**：

实现方式 — 在 `AetherRing.RingInfo` 新增字段：
```solidity
uint256 lastVoteAt;        // 最后一次投票时间戳
bool isDormant;            // 是否休眠
```

- `vote()` 调用时由 Governance 合约回调 `ring.markVoteActivity(voter)` 更新 `lastVoteAt`
- `getTotalCitizens()` 返回 `!isDormant` 的公民计数
- 任何人可调 `markDormantIfDue(tokenId)`：`block.timestamp - lastVoteAt > 2 years` → `isDormant = true`
- 休眠后再次捐赠 ≥$10 → 重置 `lastVoteAt`，`isDormant = false`

**我的补充建议**：

- "连续 2 年未投票"的标准建议改为"**连续 2 年未参与任何治理活动**"（投票 / 提案联署 / 选举投票），覆盖更全面
- Gas 成本：`markDormantIfDue` 被动检查（任何人触发），不需要定时器
- 配套：`citizenTotalSnapshot` 在公投开始时取 `getActiveCitizens()` 而非 `getTotalCitizens()`

**待确认**：
- 休眠周期 2 年是否合适？（建议 2 年，可配置）
- 激活门槛是否仍为 $10？（建议是）

---

### V2. 7 阶段状态机非法转换 — 补充状态转换图

| 项 | 值 |
|---|---|
| 严重度 | 🟡 中 |
| 类型 | 设计缺失 |
| 状态 | ✅ 采纳 |

**问题**：11 个状态转换函数未明确非法转换路径。

**补丁**：补充完整状态转换图（见下方），并在合约里用 `require(p.status == ExpectedStatus)` 强制前置状态。

**状态转换图**：

```
                        ┌──────────────┐
                        │  Drafting    │ ←── 创建（联邦提议）
                        │  (0)         │ ←── ReturnedToDraft 回流
                        └──────┬───────┘
                               │ advanceProposal (理事长)
                               ▼
                        ┌──────────────┐
                        │ PendingFirst │
                        │ Vote (1)     │
                        └──────┬───────┘
                               │ startFirstVote
                               ▼
                        ┌──────────────┐
              ┌─────────│ FirstVote    │─────────┐
              │         │ Active (2)   │         │
              │         └──────────────┘         │
              │ finalizeFirstVote (通过)         │ finalizeFirstVote (未通过)
              ▼                                  ▼
        ┌──────────────┐                  ┌──────────────┐
        │ PendingFormal│                  │  Defeated    │
        │ (3)          │                  │  (9) 终态     │
        └──────┬───────┘                  └──────────────┘
               │ submitFormalProposal            ▲
               ▼                                  │
        ┌──────────────┐                          │
        │ PendingCompl │                          │
        │ iance (4)    │                          │
        └──────┬───────┘                          │
               │ startComplianceVote              │
               ▼                                  │
        ┌──────────────┐                          │
        │  Tribunal    │──────── 不合规 ───────► ReturnedToDraft (11)
        │  Review      │                          │
        └──────┬───────┘                          │
               │ finalizeCompliance (合规)         │
               ▼                                  │
        ┌──────────────┐                          │
        │ PublicVote   │                          │
        │ Active (5)   │                          │
        └──────┬───────┘                          │
               │ finalizeProposal (通过)           │
               ▼                                  │
        ┌──────────────┐                          │
        │ PendingVeto  │                          │
        │ (6) 72h      │                          │
        └──────┬───────┘                          │
               │                                  │
        ┌──────┴───────┐                          │
        │              │                          │
       否决           超时                         │
        │              │                          │
        ▼              ▼                          │
   ┌──────────┐  ┌──────────┐                     │
   │ Canceled │  │ Queued   │                     │
   │ (10)终态 │  │ (7)      │                     │
   └──────────┘  └────┬─────┘                     │
                      │ executeProposal           │
                      ▼                           │
                ┌──────────┐                      │
                │ Executed │                      │
                │ (8) 终态 │                      │
                └──────────┘                      │
                                                  │
   Drafting 阶段被 ≥2 理事联署退回 ──────────────► ReturnedToDraft (11)
                                                  │
   ReturnedToDraft → proposer edit → advanceProposal → PendingFirstVote (1)
                                                  │
   公投未通过 finalizeProposal (未达标) ──────────┘ Defeated (9)
```

**非法转换（全部 revert）**：
- Drafting → 任何非 PendingFirstVote / ReturnedToDraft
- Defeated / Executed / Canceled → 任何状态（终态）
- PublicVoteActive → FirstVoteActive（不能倒退）
- Queued → PendingVeto（不能倒退）

---

### V3. 公民 quorum 分母快照时机

| 项 | 值 |
|---|---|
| 严重度 | 🔴 高 |
| 类型 | 设计缺失 |
| 状态 | ✅ 采纳 |

**问题**：R1 决策"分母 = 全体公民快照"未说明快照时机。

**补丁**：在 `startPublicVote(proposalId)` 时快照：
```solidity
function startPublicVote(uint256 proposalId) external {
    Proposal storage p = proposals[proposalId];
    // ... 状态检查 ...
    p.citizenTotalSnapshot = ringContract.getTotalCitizens();  // 公投开始瞬间快照
    p.status = ProposalStatus.PublicVoteActive;
    p.publicVoteStartAt = block.timestamp;
    p.publicVoteEndAt = block.timestamp + 7 days;
}
```

**理由**：与 Compound Governor Bravo 实践一致；投票期间新增公民不影响本次投票分母。

**附加补丁**（与 V1 联动）：快照取 `getActiveCitizens()`（排除休眠公民），而非 `getTotalCitizens()`。

---

### V4. 法庭事后仲裁职能缺失

| 项 | 值 |
|---|---|
| 严重度 | 🟡 中 |
| 类型 | 设计缺失 |
| 状态 | ✅ 已确认 |

**问题**：白皮书说法庭职责是"仲裁、合规审查"，但当前合约只有事前合规审查，缺事后仲裁。

**用户建议**：新增仲裁机制 — 公民提交仲裁请求（附证据）→ 法庭投票裁决 → 触发道环撤销/提案冻结/赔偿。

**技术分析**：

仲裁是独立流程，不应塞进 AetherGovernance（已经接近 24KB）。建议**新建 AetherArbitration.sol 合约**：

```solidity
contract AetherArbitration is AccessControl {
    enum ArbitrationType { MemberMisconduct, ProposalDispute, ContractBreach }
    enum ArbitrationStatus { Filed, UnderReview, Ruled, Dismissed }
    enum RulingAction { None, RevokeRing, FreezeProposal, Compensate }
    
    struct Arbitration {
        uint256 id;
        address plaintiff;       // 起诉人
        address defendant;       // 被起诉人
        ArbitrationType aType;
        string evidenceIpfs;     // 证据 IPFS
        uint256 filedAt;
        ArbitrationStatus status;
        RulingAction rulingAction;
        // 法庭成员投票
        uint256 tribunalFor;
        uint256 tribunalAgainst;
        mapping(address => bool) hasVoted;
    }
}
```

**我的建议**：
- **v3.0 先不实现仲裁**，作为 v3.1 单独迭代。理由：
  1. AetherGovernance 已逼近 24KB，仲裁再加 6-8KB 必须拆分
  2. 仲裁涉及赔偿逻辑（资金转移），安全风险高，需独立审计
  3. 当前 7 阶段治理 + 弹劾已覆盖核心治理争议
- **建议**：文档中标记"v3.0 不含事后仲裁，预留 AetherArbitration 合约接口；v3.1 实现"

**待确认**：是否同意 v3.0 暂不实现仲裁，作为 v3.1 独立迭代？

---

### V5. 元老否决对象范围

| 项 | 值 |
|---|---|
| 严重度 | 🟡 中 |
| 类型 | 设计缺失 |
| 状态 | ✅ 已确认 |

**问题**：元老否决权是否对所有提案类型适用？

**用户建议**：资金/战略可否决；成员任免/弹劾不可否决（避免利益冲突）。

**技术分析**：

实现方式 — 在 `vetoProposal` 增加类型检查：
```solidity
function vetoProposal(uint256 proposalId) external {
    Proposal storage p = proposals[proposalId];
    if (p.status != ProposalStatus.PendingVeto) revert NotPendingVeto();
    
    // 弹劾提案不可被元老否决（避免利益冲突）
    if (p.pType == ProposalType.IMPEACHMENT) revert CannotVetoImpeachment();
    
    // ...
}
```

**我的补充**：
- SIGNAL（信号性提案）：✅ 可否决（虽然是信号，但代表 DAO 立场）
- PARAM（参数修改）：✅ 可否决
- TREASURY（资金）：✅ 可否决
- IMPEACHMENT（弹劾）：❌ **不可否决**（元老不能否决对自己的弹劾）

**待确认**：上述分类是否同意？特别是 SIGNAL 是否需要元老否决？

---

### V6. 理事长任期与理事会协调 — 信任投票

| 项 | 值 |
|---|---|
| 严重度 | 🟡 中 |
| 类型 | 设计缺失 |
| 状态 | ✅ 已确认 |

**问题**：理事长 4 年任期 vs 理事 1 年任期，换届后可能治理僵局。

**用户建议**：理事换届后 3 个月内，理事长需接受理事会信任投票（简单多数），未通过则 30 天内辞职或弹劾。

**技术分析**：

实现方式 — 在 AetherRing 或 AetherGovernance 新增 `councilConfidenceVote`：
```solidity
struct ConfidenceVote {
    uint256 startedAt;
    uint256 forVotes;     // 理事 + 常务理事 加权
    uint256 againstVotes;
    bool resolved;
}

mapping(address => ConfidenceVote) public chairConfidenceVotes;  // 理事长地址 → 信任投票

function startConfidenceVote(address chair) external onlyRole(ADMIN_ROLE) { ... }
function voteConfidence(address chair, bool support) external { 
    // 仅 tier 10/11 可投票
}
function finalizeConfidence(address chair) external {
    // 简单多数，未过 → 触发 30 天辞职窗口
}
```

**我的建议**：
- **同意**新增信任投票，但建议**简化触发条件**：不强制每届理事换届都做，而是**理事联署发起**（≥8 理事联署，即 12 理事中的 2/3）
- 理由：强制信任投票会增加治理开销，联署触发更灵活

**待确认**：强制每届换届 vs 联署触发，选哪个？

---

### V7. 捐款凭证 NFT 去重逻辑

| 项 | 值 |
|---|---|
| 严重度 | 🟢 低 |
| 类型 | 设计缺失 |
| 状态 | ✅ 采纳 |

**问题**：同一地址多次捐款，每次都铸 NFT 还是只铸一次？

**补丁**：

- **首次捐款**（≥$10，且 donor 无道环）：铸公民道环 + 捐款凭证 NFT（同一笔交易）
- **后续捐款**：铸新的捐款凭证 NFT（记录金额），**不再铸公民道环**（已存在）

实现（AetherDonation.sol）：
```solidity
function mintDonation(address donor, uint256 amount, string calldata paypalTxId) 
    external onlyRole(MINTER_ROLE) returns (uint256) {
    if (amount < MIN_DONATION_USD) revert DonationTooSmall();
    if (usedPaypalTxIds[paypalTxId]) revert DuplicatePayPalTx();
    usedPaypalTxIds[paypalTxId] = true;
    
    // 铸捐款凭证 NFT（每笔捐款都铸）
    uint256 tokenId = _nextTokenId++;
    _safeMint(donor, tokenId);
    donations[tokenId] = Donation({ ... });
    
    // 仅首次捐款铸公民道环
    if (!ringContract.isBearer(donor)) {
        AetherRing(address(ringContract)).mintRing(donor, AetherRing.RingTier.CITIZEN, "");
    }
    
    return tokenId;
}
```

---

### V8. 防女巫机制缺失

| 项 | 值 |
|---|---|
| 严重度 | 🔴 高 |
| 类型 | 设计缺失 |
| 状态 | ✅ 已确认 |

**问题**：$10 门槛低，同一实体可多地址女巫攻击，操纵 60% 公民投票权重。

**用户建议**：方案 A（PayPal 账户去重）/ 方案 B（3 公民担保）/ 方案 C（提升至 $100）。

**技术分析**：

| 方案 | 实现 | 防御强度 | 用户体验 |
|---|---|---|---|
| A. PayPal 账户去重 | 服务端记录 PayPal account ID → 唯一钱包；MINTER_ROLE 校验 | 中 | 好 |
| B. 3 公民担保 | 链上 `sponsorships`，新公民需 3 个现有公民签名 | 高 | 差（冷启动难） |
| C. 门槛提升至 $100 | 改 `MIN_DONATION_USD = 100 * 10^6` | 低 | 差（降低参与度） |
| **D. A+B 组合（推荐）** | PayPal 去重 + 可选担保加分 | 高 | 中 |

**我的推荐**：**方案 D**
- 强制：PayPal account ID → 唯一钱包映射（服务端强制，链上记录 `paypalAccountHash`）
- 激励：有 3 公民担保的新公民可享受"快速通道"（24h 内激活，否则 7 天观察期）
- 链上：`AetherDonation` 新增 `mapping(bytes32 => bool) paypalAccountUsed`，`paypalAccountHash = keccak256(paypalAccountEmail)`

**待确认**：选哪个方案？

---

### V9. 弹劾范围与公民被排除的逻辑不一致

| 项 | 值 |
|---|---|
| 严重度 | 🟡 中 |
| 类型 | 设计漏洞（逻辑不一致） |
| 状态 | ✅ 已确认 |

**问题**：用户指出"公民无权力"论证不成立 — 公民有 60% 投票权重，是最大权力。

**我的分析**：用户说得对，但需要区分两种"权力"：
- **直接治理权**（提案/审批/执行）：公民无 → 无需弹劾
- **投票影响力**（公投 60%）：公民有 → 需要制衡，但**弹劾不是正确机制**

理由：
- 弹劾是撤销道环 = 撤销身份，但公民身份是"捐款获得"的，撤销等于没收捐款凭证
- 女巫攻击的本质是"一个实体多地址"，应该用 V8 防女巫机制解决，不是弹劾
- 真正需要撤销公民身份的场景：确认某地址是女巫 / 违规

**我的推荐**：**方案 B（公民身份复议）**
- 不扩展弹劾到公民
- 新增"公民身份复议"流程：理事会联署（≥4 理事）→ 法庭裁决（简单多数）→ 撤销公民道环
- 撤销的公民 NFT 保留（链上可查），但公民身份失效

这与 V4（法庭仲裁）联动，建议作为仲裁机制的一部分。

**待确认**：同意方案 B 吗？

---

### V10. 退休元老 vs 任命元老权限区分

| 项 | 值 |
|---|---|
| 严重度 | 🔴 高 |
| 类型 | 设计漏洞 |
| 状态 | ✅ 已确认 |

**问题**：退休元老自动编入元老院，若与任命元老权限一致，元老院会被退休人员填满，失去监督效力。

**用户建议**：退休元老仅名誉（无否决/弹劾权）；任命元老有完整权限。

**技术分析**：

实现方式 — 在 `RingInfo` 新增字段：
```solidity
struct RingInfo {
    RingTier tier;
    // ...
    bool isRetiredElder;   // 退休元老（无治理权）
    bool isAppointedElder; // 任命元老（有治理权）
}
```

- `retireToEmeritus()` 设置 `isRetiredElder = true`
- 新增 `appointElder(address)` 由多签调用，设置 `isAppointedElder = true`
- `vetoProposal()` 检查 `isAppointedElder`，退休元老不能否决
- `createImpeachmentProposal()` / `signImpeachment()` 检查 `isAppointedElder`

**我的补充建议**：
- 退休元老的 tier 仍为 13（保持名誉），但加 `isRetiredElder` 标记区分权限
- 任命元老有席位上限（建议 9 人，奇数便于表决），退休元老无上限
- `getTotalActiveElders()` 返回 `isAppointedElder` 计数，用于弹劾联署分母

**待确认**：
- 任命元老上限 9 人是否合适？
- 退休元老完全无治理权，还是保留"咨询权"（可发言不可投票）？

---

### V11. 公民放弃后重新获取的冷却期

| 项 | 值 |
|---|---|
| 严重度 | 🟢 低 |
| 类型 | 设计缺失 |
| 状态 | ✅ 采纳 |

**问题**：放弃后无冷却期，可立即重新捐赠获取。

**补丁**：在 `AetherRing` 新增 `renounceCooldown`：
```solidity
uint256 public constant RENOUNCE_COOLDOWN = 30 days;
mapping(address => uint256) public lastRenouncedAt;

function renounceCitizenship() external {
    // ... burn 逻辑 ...
    lastRenouncedAt[msg.sender] = block.timestamp;
}

// AetherDonation.mintDonation 调用前检查
function canReacquireCitizenship(address user) external view returns (bool) {
    return block.timestamp >= lastRenouncedAt[user] + RENOUNCE_COOLDOWN;
}
```

---

### V12. 选举无人参选或名额不足

| 项 | 值 |
|---|---|
| 严重度 | 🟡 中 |
| 类型 | 设计缺失 |
| 状态 | ✅ 已确认 |

**问题**：候选人不足 / 无人参选时治理瘫痪。

**用户建议**：名额不足 → 理事长临时指定（议会批准）；无人参选 → 紧急递补（理事长提名 + 议会批准 + 多签任命）。

**技术分析**：

实现方式 — 在 AetherElection 的 `finalizeElection` 增加空缺处理：
```solidity
function finalizeElection(uint256 electionId) external {
    // ... 正常计票，选出 winners[] ...
    
    uint256 filledSeats = winners.length;
    uint256 requiredSeats = election.seatCount;
    
    if (filledSeats < requiredSeats) {
        election.unfilledSeats = requiredSeats - filledSeats;
        election.status = ElectionStatus.PartiallyFilled;  // 新增状态
        emit SeatsUnfilled(electionId, election.unfilledSeats);
    } else {
        election.status = ElectionStatus.Finalized;
    }
}

// 理事长临时指定（仅对未填满的席位）
function appointToVacancy(uint256 electionId, address candidate) 
    external onlyRole(COUNCIL_CHAIR_ROLE) {
    Election storage e = elections[electionId];
    if (e.status != ElectionStatus.PartiallyFilled) revert NoVacancy();
    // ... 议会批准流程 ...
}
```

**我的建议**：
- **同意**用户建议的紧急递补机制
- 但"理事长临时指定"应限制：临时任命者任期至**下次定期选举**（非完整任期），避免权力滥用
- 无人参选时，应先延长候选人注册期 7 天，再考虑紧急递补

**待确认**：临时任命者任期 = 至下次选举（非完整任期），同意吗？

---

### V13. 提案类别扩展

| 项 | 值 |
|---|---|
| 严重度 | 🟢 低 |
| 类型 | 优化建议 |
| 状态 | ✅ 已确认 |

**问题**：当前 4 类（SIGNAL/PARAM/TREASURY/IMPEACHMENT）是否新增"合规审查"和"章程修订"？

**我的分析**：
- **合规审查**：法庭主动发起的事前审查已内嵌在 7 阶段流程（PendingCompliance），不需要独立提案类型
- **章程修订**：本质是 PARAM 提案的子集（修改治理参数），但章程修订应**更高门槛**

建议：不新增提案类型，但给 PARAM 加 `isConstitutional` 标记：
```solidity
struct Proposal {
    // ...
    bool isConstitutional;  // 章程修订（PARAM 子类）
}

// 章程修订：公民 quorum 提升至 50%（vs 普通 PARAM 20%）
uint256 public constant CONSTITUTIONAL_QUORUM_BPS = 5_000;
```

**待确认**：是否同意"章程修订作为 PARAM 子类 + 更高 quorum"？

---

### V14. Timelock 区分紧急 vs 常规拨款

| 项 | 值 |
|---|---|
| 严重度 | 🟢 低 |
| 类型 | 优化建议 |
| 状态 | ✅ 采纳 |

**问题**：所有 TREASURY 都是 48h Timelock，紧急拨款（安全漏洞修复）太慢。

**补丁**：

```solidity
enum TreasuryUrgency { Normal, Emergency }

struct Proposal {
    // ...
    TreasuryUrgency urgency;
}

// 紧急拨款：12h Timelock + 元老院快速批准
uint256 public constant EMERGENCY_TIMELOCK = 12 hours;
uint256 public constant EMERGENCY_ELDER_APPROVALS = 3;  // 3 位任命元老快速批准

function createTreasuryProposal(
    string title, string ipfs, address target, bytes payload,
    TreasuryUrgency urgency  // 新增参数
) external { ... }
```

紧急流程：
1. 创建 TREASURY 提案时标记 `urgency = Emergency`
2. 公投通过后 → 3 位任命元老快速批准 → 12h Timelock → Executed
3. 限制：紧急拨款金额 ≤ 国库 5%（防滥用）

---

### 13.15 漏洞修复对开发计划的影响

| 漏洞 | 影响模块 | 是否阻塞开发 |
|---|---|---|
| V1 休眠公民 | AetherRing + AetherGovernance | 阻塞（quorum 分母逻辑） |
| V2 状态转换图 | AetherGovernance | 不阻塞（设计阶段产出） |
| V3 快照时机 | AetherGovernance | 不阻塞（实现细节） |
| V4 仲裁机制 | 新合约 AetherArbitration | 不阻塞（v3.1 实现） |
| V5 否决范围 | AetherGovernance | 不阻塞（小改动） |
| V6 信任投票 | AetherGovernance | 不阻塞（可后置） |
| V7 NFT 去重 | AetherDonation | 不阻塞（实现细节） |
| V8 防女巫 | AetherDonation + 服务端 | ⚠️ 半阻塞（影响 Donation 合约接口） |
| V9 公民复议 | v3.1 仲裁机制 | 不阻塞 |
| V10 元老权限 | AetherRing + AetherGovernance | 阻塞（权限模型核心） |
| V11 冷却期 | AetherRing + AetherDonation | 不阻塞（小改动） |
| V12 选举空缺 | AetherElection | 不阻塞（可后置） |
| V13 章程修订 | AetherGovernance | 不阻塞（小改动） |
| V14 紧急拨款 | AetherGovernance | 不阻塞（小改动） |

**阻塞项**：V1（休眠公民）、V10（元老权限）、V8（防女巫，影响 Donation 接口）— 这 3 项需在开发前确认。

---

## 14. 漏洞补丁已确认汇总（V1-V13）

全部 13 项漏洞补丁已确认，可进入开发阶段。

| 编号 | 议题 | 最终决策 | 状态 |
|---|---|---|---|
| V1 | 公民休眠机制 | 2 年未参与治理活动 → 休眠；激活需重新捐赠 ≥$10；getActiveCitizens() 替代 getTotalCitizens() | ✅ |
| V2 | 状态转换图 | 12 状态 + 11 转换函数 + 非法转换列表（见 §13.V2） | ✅ |
| V3 | quorum 快照时机 | startPublicVote() 时调用 getActiveCitizens() 快照 | ✅ |
| V4 | 法庭仲裁机制 | v3.0 不实现，预留接口；v3.1 独立 AetherArbitration 合约 | ✅ |
| V5 | 元老否决范围 | TREASURY/PARAM/SIGNAL 可否决；IMPEACHMENT 不可（利益冲突） | ✅ |
| V6 | 理事长信任投票 | ≥8 理事联署发起 → 理事会简单多数 → 不通过则 30 天内辞职或弹劾；被弹劾后由元老院指定任命元老代行 30 天 | ✅ |
| V7 | NFT 去重 | 首次捐款铸公民道环 + 凭证 NFT；后续仅铸凭证 NFT | ✅ |
| V8 | 防女巫机制 | 方案 D：PayPal 账户去重（强制）+ 3 公民担保快速通道（激励，24h 激活 vs 7 天观察期） | ✅ |
| V9 | 公民身份复议 | 方案 B：≥4 理事联署 → 法庭裁决 → 撤销公民道环（NFT 保留）；v3.1 实现 | ✅ |
| V10 | 元老权限区分 | 退休元老无上限仅名誉无权；任命元老上限 9 人有完整权限；RingInfo 新增 isRetiredElder/isAppointedElder | ✅ |
| V11 | 放弃冷却期 | 30 天冷却期；renounceCitizenship 记录 lastRenouncedAt | ✅ |
| V12 | 选举空缺处理 | 名额不足 → 理事长提名 + 议会批准，任期至下次选举；无人参选 → 延长注册 7 天 + 紧急递补 | ✅ |
| V13 | 章程修订类别 | PARAM 子类 isConstitutional，公民 quorum 提升至 50% | ✅ |
| V14 | 紧急拨款 Timelock | 紧急 12h + 3 任命元老快速批准 + 金额 ≤ 国库 5% | ✅ |

**全部 23 项设计决策 + 14 项漏洞补丁 = 37 项决策已确认，v3.0 开发无阻塞。**

---

## 附录 A：v2 → v3 文件改动清单

| 文件 | 改动程度 | 说明 |
|---|---|---|
| `contracts/src/AetherRing.sol` | 🔴 重构 | 14 tier + 席位 + 任期 + 退休转元老 |
| `contracts/src/AetherGovernance.sol` | 🔴 重构 | 7 阶段 + 新计票 + 法庭/元老/理事会 |
| `contracts/src/AetherElection.sol` | 🟡 调整 | 删 REELECTION + 新增 CITIZEN_TO_COUNCIL |
| `contracts/src/AetherDonation.sol` | 🆕 新建 | PayPal NFT 凭证 |
| `contracts/src/interfaces/IAetherRing.sol` | 🟡 调整 | getTotalCitizens + isExpired |
| `contracts/src/interfaces/IAetherDonation.sol` | 🆕 新建 | |
| `contracts/script/Deploy.s.sol` | 🟡 调整 | 4 合约 + 跨授权 |
| `contracts/test/AetherRing.t.sol` | 🔴 重写 | |
| `contracts/test/AetherGovernance.t.sol` | 🔴 重写 | |
| `contracts/test/AetherElection.t.sol` | 🔴 重写 | |
| `contracts/test/AetherDonation.t.sol` | 🆕 新建 | |
| `src/lib/contracts/AetherRing.abi.ts` | 🔴 重新生成 | |
| `src/lib/contracts/AetherGovernance.abi.ts` | 🔴 重新生成 | |
| `src/lib/contracts/AetherElection.abi.ts` | 🔴 重新生成 | |
| `src/lib/contracts/AetherDonation.abi.ts` | 🆕 新建 | |
| `src/lib/contracts/index.ts` | 🔴 重写 | 14 tier + 新枚举 |
| `src/lib/contracts/config.ts` | 🟡 调整 | 新增 AetherDonation 地址 |
| `src/hooks/useRingInfo.ts` | 🔴 重写 | |
| `src/hooks/useImpeachment.ts` | 🔴 重写 | |
| `src/hooks/useElection.ts` | 🔴 重写 | |
| `src/hooks/useDonation.ts` | 🆕 新建 | |
| `src/hooks/useGovernance.ts` | 🆕 新建 | 7 阶段流程 |

---

## 附录 B：白皮书 v3.0 权级完整表

| 编码 | 权级名称 | 所属组织 | 人数 | 任期 | 连任 | 投票权重 |
|---|---|---|---|---|---|---|
| 1 | 议员 | 议会 | 60 | 1年 | ❌ | 内部 1 |
| 2 | 参议员 | 议会 | 12 | 2年 | ❌ | 内部 3 |
| 3 | 议长 | 议会 | 2 | 终生 | — | 内部 10 |
| 4 | 委员 | 联邦 | 60 | 1年 | ❌ | 内部 1 |
| 5 | 委员长 | 联邦 | 12 | 2年 | ❌ | 内部 3 |
| 6 | 执政 | 联邦 | 2 | 终生 | — | 内部 10 |
| 7 | 法官 | 法庭 | 60 | 1年 | ❌ | 内部 1 |
| 8 | 大法官 | 法庭 | 12 | 2年 | ❌ | 内部 3 |
| 9 | 首席 | 法庭 | 2 | 终生 | — | 内部 10 |
| 10 | 理事 | 理事会 | 12 | 1年 | ❌ | 无（管理） |
| 11 | 常务理事 | 理事会 | 4 | 1年 | ❌ | 无（管理） |
| 12 | 理事长 | 理事会 | 2 | 终生 | — | 无（管理） |
| 13 | 元老 | 元老院 | ∞ | 终生 | — | 无（否决） |
| 14 | 公民 | 基金会 | 变量 | — | — | 总投票 1 |

---

**文档结束**

下一步：请确认 R1-R10 + R3-补充（理事长任命方式），即可开始第 1 轮 AetherRing v3 开发。
