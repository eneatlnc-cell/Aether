# Aether DAO v3.0 详细开发步骤

> **版本**：v3.0 开发步骤详化
> **日期**：2026年7月
> **基于**：V3_DESIGN_DISCUSSION.md（37 项决策已确认）+ V3 开发计划
> **原则**：不回避复杂任务 / 不重复开发环节 / 循序渐进 / 每步可验证

---

## 目录

- [开发总览](#开发总览)
- [第 1 轮：AetherRing v3（基础层）](#第-1-轮aetherring-v3基础层)
- [第 2 轮：AetherDonation（捐款模块）](#第-2-轮aetherdonation捐款模块)
- [第 3 轮：AetherGovernance v3（核心治理）](#第-3-轮aethergovernance-v3核心治理)
- [第 4 轮：AetherElection v3（选举模块）](#第-4-轮aetherelection-v3选举模块)
- [第 5 轮：跨合约集成与部署脚本](#第-5-轮跨合约集成与部署脚本)
- [第 6 轮：前端 ABI 与接口对接](#第-6-轮前端-abi-与接口对接)
- [质量门禁与验证标准](#质量门禁与验证标准)

---

## 开发总览

### 依赖关系图

```
        ┌─────────────────┐
        │ 第1轮 AetherRing │ ←── 全部基础
        └────────┬────────┘
                 │
       ┌─────────┼─────────┐
       ▼         ▼         ▼
  ┌─────────┐ ┌─────────┐ ┌─────────────────┐
  │ 第2轮   │ │ 第3轮   │ │ 第4轮           │
  │ Donation│ │ Govern  │ │ Election(部分)  │
  └────┬────┘ └────┬────┘ │ (依赖第3轮审批) │
       │           │      └────────┬────────┘
       │           │               │
       └───────────┴───────────────┘
                   │
                   ▼
         ┌─────────────────┐
         │ 第5轮 集成部署  │
         └────────┬────────┘
                  │
                  ▼
         ┌─────────────────┐
         │ 第6轮 前端对接  │
         └─────────────────┘
```

### 可并行性

- 第 2 轮（Donation）与第 3 轮（Governance）可并行（都只依赖第 1 轮）
- 第 4 轮的"删除 REELECTION + 新增 CITIZEN_TO_COUNCIL 类型"可在第 3 轮议会审批接口确定后并行
- 第 6 轮前端各 hook 可并行开发

### 每轮通用流程

```
1. 阅读决策依据 → 2. 编写合约 → 3. 编写测试 → 4. solc-js 验证编译
   → 5. 运行测试 → 6. 通过质量检查点 → 进入下一轮
```

---

## 第 1 轮：AetherRing v3（基础层）

**依赖**：无
**阻塞**：后续所有轮次
**目标**：14 级权级 + 席位 + 任期 + 退休转元老 + 休眠 + 任命元老 + 公民放弃

### 步骤 1.1：重构 RingTier enum（14 级权级）

**输入**：白皮书附录 B 权级表
**改动文件**：`contracts/src/AetherRing.sol`

**任务**：
1. 替换 enum RingTier 为 14 级：
```solidity
enum RingTier {
    NONE,                // 0
    PARLIAMENT_MEMBER,   // 1  议员（基层）
    PARLIAMENT_SENIOR,   // 2  参议员（中层）
    PARLIAMENT_SPEAKER,  // 3  议长（高层）
    FEDERATION_MEMBER,   // 4  委员（基层）
    FEDERATION_SENIOR,   // 5  委员长（中层）
    FEDERATION_MINISTER, // 6  执政（高层，原"部长"改名）
    TRIBUNAL_JUDGE,      // 7  法官（基层，替换原 SENATE_ADVISOR）
    TRIBUNAL_SENIOR,     // 8  大法官（中层，替换原 SENATE_FELLOW）
    TRIBUNAL_CHIEF,      // 9  首席（高层，替换原 SENATE_ELDER）
    COUNCIL_MEMBER,      // 10 理事（理事会基层，重定义原 GENERAL_MEMBER）
    COUNCIL_SENIOR,      // 11 常务理事
    COUNCIL_CHAIR,       // 12 理事长
    ELDER,               // 13 元老（独立机构）
    CITIZEN              // 14 公民（原 v2 tier 10）
}
```
2. 全局搜索替换原引用：`GENERAL_MEMBER → CITIZEN`，`SENATE_* → TRIBUNAL_*`
3. 同步更新 `_levelOf()` 函数按新 tier 分基层/中层/高层

**验证**：合约编译通过，无引用残留

---

### 步骤 1.2：席位上限常量调整

**改动文件**：`contracts/src/AetherRing.sol`

**任务**：
1. 修改现有常量：
```solidity
uint256 public constant GRASSROOTS_LIMIT = 60;  // v2: 20
uint256 public constant MID_LIMIT = 12;          // v2: 4
uint256 public constant HIGH_LIMIT = 2;          // 不变
```
2. 新增理事会席位：
```solidity
uint256 public constant COUNCIL_MEMBER_LIMIT = 12;
uint256 public constant COUNCIL_SENIOR_LIMIT = 4;
uint256 public constant COUNCIL_CHAIR_LIMIT = 2;
uint256 public constant APPOINTED_ELDER_LIMIT = 9;  // 任命元老上限
```
3. 重写 `_seatLimitOf(RingTier tier)` 函数：按具体 tier 返回上限（元老 13 与公民 14 返回 type(uint256).max）

**验证**：
- [ ] tier 1/4/7 上限 = 60
- [ ] tier 2/5/8 上限 = 12
- [ ] tier 3/6/9 上限 = 2
- [ ] tier 10/11/12 上限 = 12/4/2
- [ ] tier 13/14 不检查上限

---

### 步骤 1.3：任期与连任调整

**改动文件**：`contracts/src/AetherRing.sol`

**任务**：
1. 修改连任上限：
```solidity
uint8 public constant MAX_CONSECUTIVE_TERMS = 0;  // v2: 1 → v3: 0（不可连任）
```
2. 新增理事长任期常量（4 年，可连任）：
```solidity
uint256 public constant COUNCIL_CHAIR_TERM = 4 * 365 days;  // 理事长 4 年任期
```
3. 删除 `renewTerm()` 函数（v3 不可连任，无续期逻辑）
4. 修改 `mintRing()` 时根据 tier 设置 termEndAt：
   - 基层（1/4/7/10/11）：`block.timestamp + 365 days`
   - 中层（2/5/8）：`block.timestamp + 730 days`
   - 高层（3/6/9）：`type(uint64).max`
   - 理事长（12）：`block.timestamp + COUNCIL_CHAIR_TERM`
   - 元老（13）/公民（14）：`type(uint64).max`（无任期）

**验证**：
- [ ] 基层 mint 后 termEndAt = now + 365 days
- [ ] 高层 mint 后 termEndAt = max
- [ ] renewTerm 已删除，编译报错确认

---

### 步骤 1.4：RingInfo 新增字段

**改动文件**：`contracts/src/AetherRing.sol`

**任务**：扩展 RingInfo struct：
```solidity
struct RingInfo {
    uint256 tokenId;
    address holder;
    RingTier tier;
    string covenantHash;
    uint256 mintedAt;
    uint256 termEndAt;
    uint8 consecutiveTerms;
    bool isActive;
    bool isEmeritus;
    // ── v3 新增 ──
    bool isExpired;            // 任期到期标记
    uint256 lastActivityAt;    // 最后一次治理活动时间（休眠判断）
    bool isDormant;            // 是否休眠（仅公民）
    bool isRetiredElder;       // 退休元老（无治理权）
    bool isAppointedElder;     // 任命元老（有治理权）
}
```

**注意**：v2 的 `isExpired` 已存在则保留逻辑，否则新增。
mint 时初始化：`lastActivityAt = block.timestamp`，其余 bool 默认 false。

**验证**：
- [ ] mint 后所有新字段初始化正确
- [ ] getRingInfo 返回完整字段

---

### 步骤 1.5：退休转元老逻辑

**改动文件**：`contracts/src/AetherRing.sol`

**任务**：重写 `retireToEmeritus(uint256 tokenId)`：
```solidity
function retireToEmeritus(uint256 tokenId) external {
    _requireSafeWallet();  // 仅多签可调
    RingInfo storage info = ringInfo[tokenId];
    RingTier oldTier = info.tier;
    
    // 仅高层 3/6/9 + 理事长 12 可退休
    if (!_isRetirable(oldTier)) revert InvalidTier();
    
    // 原 tier 席位计数减 1
    _tierCount[uint8(oldTier)] -= 1;
    
    // 转为元老（tier=13），保留 covenantHash 和 mintedAt
    info.tier = RingTier.ELDER;
    info.isActive = false;            // 无投票权
    info.isEmeritus = true;
    info.isRetiredElder = true;       // 标记为退休元老（无治理权）
    info.isAppointedElder = false;
    info.termEndAt = type(uint64).max;
    // ELDER 无上限，不做席位检查
    
    emit RingRetired(tokenId, info.holder, oldTier);
}

function _isRetirable(RingTier tier) internal pure returns (bool) {
    return tier == RingTier.PARLIAMENT_SPEAKER
        || tier == RingTier.FEDERATION_MINISTER
        || tier == RingTier.TRIBUNAL_CHIEF
        || tier == RingTier.COUNCIL_CHAIR;
}
```

**验证**：
- [ ] tier 3/6/9/12 退休后 getTier 返回 13
- [ ] isRetiredElder = true，isAppointedElder = false
- [ ] 原 tier 席位计数 -1
- [ ] tier 1/2/4/5/7/8/10/11/14 退休 revert

---

### 步骤 1.6：公民自愿放弃 + 30 天冷却期

**改动文件**：`contracts/src/AetherRing.sol`

**任务**：
1. 新增常量与映射：
```solidity
uint256 public constant RENOUNCE_COOLDOWN = 30 days;
mapping(address => uint256) public lastRenouncedAt;
```
2. 实现 `renounceCitizenship()`：
```solidity
function renounceCitizenship() external {
    uint256 ringId = walletToRingId[msg.sender];
    if (ringId == 0) revert RingDoesNotExist(ringId);
    RingInfo storage info = ringInfo[ringId];
    if (info.tier != RingTier.CITIZEN) revert InvalidTier();
    
    _tierCount[uint8(RingTier.CITIZEN)] -= 1;
    walletToRingId[msg.sender] = 0;
    lastRenouncedAt[msg.sender] = block.timestamp;
    _burn(ringId);
    
    emit RingRevoked(ringId, msg.sender);
}
```
3. 新增查询函数：
```solidity
function canReacquireCitizenship(address user) external view returns (bool) {
    return lastRenouncedAt[user] == 0 
        || block.timestamp >= lastRenouncedAt[user] + RENOUNCE_COOLDOWN;
}
```

**验证**：
- [ ] 公民放弃后 _burn，walletToRingId = 0
- [ ] lastRenouncedAt 记录时间戳
- [ ] 30 天内 canReacquireCitizenship 返回 false
- [ ] 30 天后返回 true
- [ ] 非公民调用 revert

---

### 步骤 1.7：休眠机制

**改动文件**：`contracts/src/AetherRing.sol`

**任务**：
1. 新增常量：
```solidity
uint256 public constant DORMANCY_PERIOD = 2 * 365 days;  // 2 年
```
2. 实现被动休眠检查：
```solidity
function markDormantIfDue(uint256 tokenId) external {
    RingInfo storage info = ringInfo[tokenId];
    if (info.tier != RingTier.CITIZEN) revert NotCitizen();
    if (info.isDormant) revert AlreadyDormant();
    
    if (block.timestamp - info.lastActivityAt > DORMANCY_PERIOD) {
        info.isDormant = true;
        emit CitizenDormant(tokenId, info.holder);
    }
}
```
3. 实现治理活动回调（被 Governance/Election 调用）：
```solidity
function markVoteActivity(address voter) external {
    // 仅允许授权合约（governance/election）调用
    if (!hasRole(GOVERNANCE_ROLE, msg.sender) && !hasRole(ELECTION_ROLE, msg.sender)) {
        revert Unauthorized();
    }
    uint256 ringId = walletToRingId[voter];
    if (ringId == 0) return;
    RingInfo storage info = ringInfo[ringId];
    info.lastActivityAt = block.timestamp;
    if (info.isDormant) {
        info.isDormant = false;  // 重新激活（需配合捐款，见步骤 2.4）
    }
}
```
4. 新增 `getActiveCitizens()`：
```solidity
function getActiveCitizens() public view returns (uint256) {
    // 总公民数 - 休眠公民数
    return _tierCount[uint8(RingTier.CITIZEN)] - _dormantCitizenCount;
}
```
5. 维护 `_dormantCitizenCount`（在 markDormantIfDue 时 +1，重新激活时 -1）

**验证**：
- [ ] 2 年未活动后 markDormantIfDue 触发休眠
- [ ] 休眠公民不计入 getActiveCitizens
- [ ] markVoteActivity 更新 lastActivityAt
- [ ] 非授权合约调用 markVoteActivity revert

---

### 步骤 1.8：任命元老

**改动文件**：`contracts/src/AetherRing.sol`

**任务**：
1. 实现 `appointElder(address candidate)`：
```solidity
function appointElder(address candidate) external {
    _requireSafeWallet();  // 仅多签可调
    if (candidate == address(0)) revert ZeroAddress();
    
    uint256 appointedCount = _appointedElderCount;
    if (appointedCount >= APPOINTED_ELDER_LIMIT) revert AppointedElderLimitReached();
    
    uint256 ringId = walletToRingId[candidate];
    if (ringId == 0) {
        // 新任命，铸道环
        ringId = _mintInternal(candidate, RingTier.ELDER, "");
    } else {
        // 已有道环，升级为任命元老
        RingInfo storage info = ringInfo[ringId];
        RingTier oldTier = info.tier;
        if (oldTier != RingTier.ELDER) {
            _tierCount[uint8(oldTier)] -= 1;
            info.tier = RingTier.ELDER;
        }
        if (info.isRetiredElder) {
            info.isRetiredElder = false;
        }
    }
    
    RingInfo storage info = ringInfo[ringId];
    info.isAppointedElder = true;
    info.isActive = true;  // 任命元老有治理权
    info.termEndAt = type(uint64).max;
    _appointedElderCount += 1;
    
    emit ElderAppointed(ringId, candidate);
}
```

**验证**：
- [ ] 首次任命铸道环，isAppointedElder=true
- [ ] 已有公民道环者任命后 tier=13，原公民计数 -1
- [ ] 退休元老重新任命后 isRetiredElder=false，isAppointedElder=true
- [ ] 第 10 个任命 revert

---

### 步骤 1.9：接口扩展

**改动文件**：`contracts/src/interfaces/IAetherRing.sol`

**任务**：扩展接口：
```solidity
interface IAetherRing {
    // v2 保留
    function isBearer(address holder) external view returns (bool);
    function getTier(address holder) external view returns (uint8);
    function getRingId(address holder) external view returns (uint256);
    
    // v3 改名
    function getActiveCitizens() external view returns (uint256);  // 替代 getTotalMembers
    
    // v3 新增
    function isExpired(uint256 tokenId) external view returns (bool);
    function isElderActive(address holder) external view returns (bool);  // 任命元老
    function markVoteActivity(address voter) external;
    function canReacquireCitizenship(address user) external view returns (bool);
}
```

**验证**：
- [ ] Governance/Election/Donation 合约通过此接口调用，编译通过

---

### 步骤 1.10：单元测试

**改动文件**：`contracts/test/AetherRing.t.sol`（完全重写）

**测试用例清单**：

| # | 测试名 | 覆盖点 |
|---|---|---|
| T1.1 | test_MintRing_AllTiers_TermCorrect | 14 个 tier 各自任期正确 |
| T1.2 | test_SeatLimit_GrassrootsAt60 | 基层 60 席上限 |
| T1.3 | test_SeatLimit_MidAt12 | 中层 12 席上限 |
| T1.4 | test_SeatLimit_CouncilAt12_4_2 | 理事会 12/4/2 |
| T1.5 | test_SeatLimit_AppointedElderAt9 | 任命元老 9 人上限 |
| T1.6 | test_SeatLimit_CitizenAndElder_NoLimit | 公民/退休元老无上限 |
| T1.7 | test_RetireToEmeritus_HighTier_Success | tier 3/6/9 退休转 13 |
| T1.8 | test_RetireToEmeritus_CouncilChair_Success | 理事长 12 退休转 13 |
| T1.9 | test_RetireToEmeritus_LowTier_Revert | tier 1/2/4/5/7/8/10/11/14 退休 revert |
| T1.10 | test_RetireToEmeritus_SetsIsRetiredElder | isRetiredElder=true |
| T1.11 | test_RenounceCitizenship_Success | 公民放弃 |
| T1.12 | test_RenounceCitizenship_NonCitizen_Revert | 非公民放弃 revert |
| T1.13 | test_RenounceCitizenship_Cooldown30Days | 30 天内 canReacquire=false |
| T1.14 | test_MarkDormantIfDue_After2Years | 2 年后休眠 |
| T1.15 | test_MarkDormantIfDue_Before2Years_Revert | 2 年内不触发 |
| T1.16 | test_MarkVoteActivity_UpdatesLastActivityAt | 投票后时间更新 |
| T1.17 | test_GetActiveCitizens_ExcludesDormant | 休眠公民不计入 |
| T1.18 | test_AppointElder_NewCandidate | 新人任命 |
| T1.19 | test_AppointElder_ExistingCitizen | 已有公民任命升级 |
| T1.20 | test_AppointElder_RetiredElder_Reactivate | 退休元老重新任命 |
| T1.21 | test_AppointElder_Limit9_Revert | 第 10 个任命 revert |
| T1.22 | test_IsElderActive_OnlyAppointed | 任命元老 true，退休元老 false |
| T1.23 | test_SafeWallet_OnlyMultisig_RetireAppoint | 多签权限校验 |
| T1.24 | test_UpdateTier_ResetTerm_NewTerm | updateTier 重置任期 |
| T1.25 | test_MarkExpiredIfDue_AfterTermEnds | 任期到期标记 |

**验证**：
- [ ] 25 个测试全部通过
- [ ] forge coverage ≥ 90%

---

### 第 1 轮质量门禁

完成第 1 轮前必须满足：

```
✅ 14 tier enum 定义正确
✅ 席位上限：60/12/2 + 12/4/2 + 9（任命元老）
✅ MAX_CONSECUTIVE_TERMS = 0
✅ RingInfo 含 lastActivityAt/isDormant/isRetiredElder/isAppointedElder
✅ retireToEmeritus 仅 3/6/9/12 可调
✅ renounceCitizenship 30 天冷却期
✅ markDormantIfDue 2 年触发
✅ appointElder 上限 9 人
✅ getActiveCitizens 排除休眠
✅ 25 个测试通过
✅ solc-js 0.8.26 编译 0 错误
✅ 合约体积 < 24KB
```

---

## 第 2 轮：AetherDonation（捐款模块）

**依赖**：第 1 轮（AetherRing 的 mintRing + canReacquireCitizenship）
**目标**：ERC-721 SBT + PayPal 凭证 + 防女巫

### 步骤 2.1：合约骨架

**新建文件**：`contracts/src/AetherDonation.sol`

**任务**：
1. 继承 ERC721 + AccessControl
2. 定义角色：
```solidity
bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");    // 多签
bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");  // PayPal webhook 服务端
```
3. 引用 AetherRing：
```solidity
IAetherRing public ringContract;
address public treasury;  // Safe 多签国库地址
```
4. 构造函数：`constructor(address ring, address treasury, address admin)`

**验证**：
- [ ] 部署后角色正确分配
- [ ] ringContract 和 treasury 正确设置

---

### 步骤 2.2：Donation struct 与存储

**任务**：
```solidity
struct Donation {
    address donor;
    uint256 amount;          // USD 最小单位（6 decimals）
    uint256 usdcAmount;      // 实际注入国库 USDC（settle 时填）
    string paypalTxId;
    bytes32 paypalAccountHash;  // V8 防女巫
    uint256 timestamp;
    bool isSettled;
    // V8 担保快速通道
    uint8 sponsorCount;
    bool fastTrackActivated;
}

mapping(uint256 => Donation) public donations;
mapping(string => bool) public usedPaypalTxIds;        // V7 防重放
mapping(bytes32 => bool) public paypalAccountUsed;     // V8 PayPal 账户去重
mapping(address => uint256[]) public donorTokenIds;    // 同一 donor 多笔捐款
uint256 public nextTokenId = 1;
uint256 public constant MIN_DONATION_USD = 10 * 10**6;  // $10
```

**验证**：
- [ ] struct 字段完整
- [ ] 常量正确

---

### 步骤 2.3：mintDonation 核心

**任务**：实现 mintDonation：
```solidity
function mintDonation(
    address donor,
    uint256 amount,
    string calldata paypalTxId,
    bytes32 paypalAccountHash  // 服务端 keccak256(payer_id)
) external onlyRole(MINTER_ROLE) returns (uint256) {
    // 1. 金额校验
    if (amount < MIN_DONATION_USD) revert DonationTooSmall();
    
    // 2. PayPal TxId 防重放
    if (usedPaypalTxIds[paypalTxId]) revert DuplicatePayPalTx();
    usedPaypalTxIds[paypalTxId] = true;
    
    // 3. PayPal 账户去重（V8）
    if (paypalAccountUsed[paypalAccountHash]) revert DuplicatePayPalAccount();
    paypalAccountUsed[paypalAccountHash] = true;
    
    // 4. 捐款冷却期检查（V11）
    if (!ringContract.canReacquireCitizenship(donor)) revert RenounceCooldownActive();
    
    // 5. 铸捐款凭证 NFT
    uint256 tokenId = nextTokenId++;
    _safeMint(donor, tokenId);
    donations[tokenId] = Donation({
        donor: donor,
        amount: amount,
        usdcAmount: 0,
        paypalTxId: paypalTxId,
        paypalAccountHash: paypalAccountHash,
        timestamp: block.timestamp,
        isSettled: false,
        sponsorCount: 0,
        fastTrackActivated: false
    });
    donorTokenIds[donor].push(tokenId);
    
    // 6. 首次捐款铸公民道环（V7 去重）
    if (!ringContract.isBearer(donor)) {
        AetherRing(address(ringContract)).mintRing(donor, AetherRing.RingTier.CITIZEN, "");
    }
    
    emit DonationMinted(tokenId, donor, amount, paypalTxId);
    return tokenId;
}
```

**验证**：
- [ ] 金额 < $10 revert
- [ ] 重复 paypalTxId revert
- [ ] 重复 paypalAccountHash revert
- [ ] 冷却期内 mint revert
- [ ] 首次捐款铸公民道环
- [ ] 二次捐款不重复铸公民道环

---

### 步骤 2.4：settleDonation（多签结算）

**任务**：
```solidity
function settleDonation(uint256 tokenId, uint256 usdcAmount) external onlyRole(ADMIN_ROLE) {
    Donation storage d = donations[tokenId];
    if (d.donor == address(0)) revert DonationNotFound();
    if (d.isSettled) revert AlreadySettled();
    
    d.usdcAmount = usdcAmount;
    d.isSettled = true;
    
    emit DonationSettled(tokenId, usdcAmount);
}
```

**验证**：
- [ ] 非 ADMIN_ROLE 调用 revert
- [ ] 已 settle 的重复调用 revert
- [ ] settle 后 isSettled=true

---

### 步骤 2.5：3 公民担保快速通道（V8）

**任务**：
```solidity
uint256 public constant SPONSORS_REQUIRED = 3;
uint256 public constant FAST_TRACK_DELAY = 24 hours;
uint256 public constant NORMAL_TRACK_DELAY = 7 days;

mapping(uint256 => mapping(address => bool)) public hasSponsored;  // tokenId -> sponsor -> bool

function sponsorDonation(uint256 tokenId) external {
    Donation storage d = donations[tokenId];
    if (d.donor == address(0)) revert DonationNotFound();
    if (d.fastTrackActivated) revert AlreadyFastTrack();
    if (hasSponsored[tokenId][msg.sender]) revert AlreadySponsored();
    
    // 担保人必须是现有公民
    if (!ringContract.isBearer(msg.sender)) revert NotCitizen();
    if (ringContract.getTier(msg.sender) != uint8(AetherRing.RingTier.CITIZEN)) {
        revert NotCitizen();
    }
    
    hasSponsored[tokenId][msg.sender] = true;
    d.sponsorCount += 1;
    
    if (d.sponsorCount >= SPONSORS_REQUIRED && !d.fastTrackActivated) {
        d.fastTrackActivated = true;
        emit FastTrackActivated(tokenId);
    }
}

function canActivateCitizenship(uint256 tokenId) external view returns (bool) {
    Donation storage d = donations[tokenId];
    if (d.donor == address(0)) return false;
    if (ringContract.isBearer(d.donor)) return false;  // 已是公民
    
    uint256 delay = d.fastTrackActivated ? FAST_TRACK_DELAY : NORMAL_TRACK_DELAY;
    return block.timestamp >= d.timestamp + delay;
}
```

**说明**：fastTrack 决定公民道环铸造的等待期，但 mintDonation 已立即铸公民道环。此机制作为"二次捐款激活"或"放弃后重新获取"的快速通道。

**验证**：
- [ ] 3 个公民担保后 fastTrackActivated=true
- [ ] 非公民担保 revert
- [ ] 重复担保 revert

---

### 步骤 2.6：SBT 不可转让

**任务**：override `_update` 实现 SBT：
```solidity
function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
    address from = _ownerOf(tokenId);
    if (from != address(0) && to != address(0)) {
        revert NonTransferable();
    }
    return super._update(to, tokenId, auth);
}
```

**验证**：
- [ ] transferFrom revert
- [ ] safeTransferFrom revert
- [ ] mint 时 from=address(0) 允许
- [ ] burn 时 to=address(0) 允许

---

### 步骤 2.7：查询函数

**任务**：
```solidity
function getDonation(uint256 tokenId) external view returns (Donation memory);
function getDonationsByDonor(address donor) external view returns (uint256[] memory);
function getTotalDonations() external view returns (uint256);
function getUnsettledDonations() external view returns (uint256[] memory);  // 审计用
```

**验证**：
- [ ] 返回数据正确

---

### 步骤 2.8：接口文件

**新建文件**：`contracts/src/interfaces/IAetherDonation.sol`

```solidity
interface IAetherDonation {
    function mintDonation(address donor, uint256 amount, string calldata paypalTxId, bytes32 paypalAccountHash) external returns (uint256);
    function settleDonation(uint256 tokenId, uint256 usdcAmount) external;
    function getDonation(uint256 tokenId) external view returns (tuple);
    function canReacquireCitizenship(address user) external view returns (bool);  // 代理到 ring
}
```

---

### 步骤 2.9：单元测试

**新建文件**：`contracts/test/AetherDonation.t.sol`

| # | 测试名 | 覆盖点 |
|---|---|---|
| T2.1 | test_MintDonation_FirstTime_MintsCitizenRing | 首次捐款铸公民道环 |
| T2.2 | test_MintDonation_SecondTime_NoCitizenRing | 二次捐款不重复铸 |
| T2.3 | test_MintDonation_AmountLessThan10_Revert | 金额 < $10 revert |
| T2.4 | test_MintDonation_DuplicatePayPalTx_Revert | paypalTxId 防重放 |
| T2.5 | test_MintDonation_DuplicatePayPalAccount_Revert | paypalAccountHash 去重 |
| T2.6 | test_MintDonation_InCooldown_Revert | 放弃冷却期内 revert |
| T2.7 | test_SettleDonation_OnlyAdmin | 非 admin revert |
| T2.8 | test_SettleDonation_AlreadySettled_Revert | 重复 settle revert |
| T2.9 | test_SponsorDonation_3Sponsors_ActivatesFastTrack | 3 担保激活 |
| T2.10 | test_SponsorDonation_NonCitizen_Revert | 非公民担保 revert |
| T2.11 | test_Transfer_Revert | SBT 不可转让 |
| T2.12 | test_GetDonationsByDonor_ReturnsAllTokens | 多笔捐款查询 |
| T2.13 | test_GetUnsettledDonations_AuditList | 未 settle 列表 |

---

### 第 2 轮质量门禁

```
✅ mintDonation 金额/重放/去重/冷却期 4 重校验
✅ 首次捐款铸公民道环，二次不重复
✅ settleDonation 仅多签可调
✅ 3 公民担保快速通道
✅ SBT 不可转让
✅ 13 个测试通过
✅ solc-js 编译 0 错误
✅ 合约体积 < 24KB
```

---

## 第 3 轮：AetherGovernance v3（核心治理）

**依赖**：第 1 轮（AetherRing）
**最复杂的一轮**：12 状态 + 11 转换 + 新计票 + 5 种特殊流程
**注意**：每完成一个步骤立即写测试，避免最后批量调试

### 步骤 3.1：Proposal struct 重构

**改动文件**：`contracts/src/AetherGovernance.sol`

**任务**：
```solidity
struct Proposal {
    uint256 id;
    address proposer;
    ProposalType pType;
    string title;
    string ipfsHash;
    uint256 createdAt;
    
    // ── 两轮投票时间窗口 ──
    uint256 firstVoteStartAt;
    uint256 firstVoteEndAt;       // 5 days
    uint256 publicVoteStartAt;
    uint256 publicVoteEndAt;      // 7 days
    uint256 vetoWindowEndAt;      // publicVoteEndAt + 72h
    
    // ── 三院内部权重累积（一审 + 公投共用） ──
    uint256 parliamentFor;
    uint256 parliamentAgainst;
    uint256 federationFor;
    uint256 federationAgainst;
    uint256 tribunalFor;          // 原 senateFor
    uint256 tribunalAgainst;      // 原 senateAgainst
    
    // ── 公民投票（仅公投阶段）──
    uint256 citizenFor;
    uint256 citizenAgainst;
    uint256 citizenAbstain;
    uint256 citizenTotalSnapshot;  // startPublicVote 时快照
    
    // ── 法庭合规审查 ──
    uint256 complianceFor;
    uint256 complianceAgainst;
    mapping(address => bool) hasComplianceVoted;
    
    // ── finalize 结果 ──
    ChamberStance parliamentStance;
    ChamberStance federationStance;
    ChamberStance tribunalStance;
    bool citizenQuorumMet;
    bool passed;
    ProposalStatus status;
    
    // ── execute 扩展 ──
    address target;
    bytes calldataPayload;
    uint256 queuedAt;
    uint256 executeAfter;
    bool isExecuted;
    bool isConstitutional;        // V13 章程修订标记
    TreasuryUrgency urgency;       // V14 紧急拨款
    
    // ── IMPEACHMENT 专用 ──
    address impeachedTarget;
    uint256 requiredImpeachSignatures;  // 3
    uint256 currentImpeachSignatures;
    mapping(address => bool) hasImpeachSigned;
    
    // ── 元老否决 ──
    uint256 requiredVetoSignatures;     // 3
    uint256 currentVetoSignatures;
    mapping(address => bool) hasVetoed;
    
    // ── 理事会退回联署 ──
    uint256 requiredReturnSignatures;   // 2
    uint256 currentReturnSignatures;
    mapping(address => bool) hasSignedReturn;
}
```

**验证**：
- [ ] struct 编译通过
- [ ] 字段顺序合理（mapping 在末尾）

---

### 步骤 3.2：常量与枚举调整

**任务**：
```solidity
enum ProposalType {
    SIGNAL,       // 0
    PARAM,        // 1
    TREASURY,     // 2
    IMPEACHMENT   // 3
}

enum ProposalStatus {
    Drafting,            // 0
    PendingFirstVote,    // 1
    FirstVoteActive,     // 2
    PendingFormal,       // 3
    PendingCompliance,   // 4
    PublicVoteActive,    // 5
    PendingVeto,         // 6
    Queued,              // 7
    Executed,            // 8
    Defeated,            // 9
    Canceled,            // 10
    ReturnedToDraft      // 11
}

enum TreasuryUrgency { Normal, Emergency }

uint256 public constant CHAMBER_WEIGHT_BPS = 2_000;       // 每院 20%  // v3.1 已改为 1_666
uint256 public constant CITIZEN_WEIGHT_BPS = 6_000;       // 公民 60%  // v3.1 已改为 5_000
uint256 public constant PASS_THRESHOLD_BPS = 5_000;       // >50%
uint256 public constant CITIZEN_QUORUM_BPS = 2_000;       // ≥20%
uint256 public constant CONSTITUTIONAL_QUORUM_BPS = 5_000;  // V13 章程修订 50%
uint256 public constant BPS_DENOMINATOR = 10_000;

uint256 public constant FIRST_VOTE_PERIOD = 5 days;
uint256 public constant PUBLIC_VOTE_PERIOD = 7 days;
uint256 public constant VETO_WINDOW = 72 hours;
uint256 public constant TIMELOCK_NORMAL = 48 hours;
uint256 public constant TIMELOCK_EMERGENCY = 12 hours;     // V14

uint256 public constant IMPEACHMENT_SIGNATURES = 3;        // 元老发起 ≥3
uint256 public constant IMPEACHMENT_QUORUM_BPS = 4_000;    // 公民参与 ≥40%  // v3.1 已改为 3_000
uint256 public constant IMPEACHMENT_PASS_BPS = 6_000;      // 反对率 ≥60%  // v3.1 已改为 7_000
uint256 public constant VETO_SIGNATURES = 3;
uint256 public constant RETURN_SIGNATURES = 2;
uint256 public constant EMERGENCY_ELDER_APPROVALS = 3;
uint256 public constant EMERGENCY_TREASURY_LIMIT_BPS = 500;  // 国库 5%
```

**验证**：
- [ ] 所有常量值与决策一致

---

### 步骤 3.3：构造函数与 internalWeight 初始化

**任务**：
```solidity
constructor(address _ringAddress) {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
    _grantRole(PROPOSER_ROLE, msg.sender);
    ringContract = IAetherRing(_ringAddress);
    
    // 三院内部权重：1/3/10
    internalWeight[1] = 1;  // 议员
    internalWeight[2] = 3;  // 参议员
    internalWeight[3] = 10; // 议长
    internalWeight[4] = 1;  // 委员
    internalWeight[5] = 3;  // 委员长
    internalWeight[6] = 10; // 执政
    internalWeight[7] = 1;  // 法官
    internalWeight[8] = 3;  // 大法官
    internalWeight[9] = 10; // 首席
    // tier 10/11/12 理事会 = 0（不参与院内部投票）
    // tier 13 元老 = 0
    internalWeight[14] = 1; // 公民
}
```

**验证**：
- [ ] 权重值正确

---

### 步骤 3.4：createProposal（联邦提议入口）

**任务**：
```solidity
function createProposal(
    ProposalType pType,
    string calldata title,
    string calldata ipfsHash,
    address target,
    bytes calldata calldataPayload,
    bool isConstitutional,        // V13 章程修订标记（仅 PARAM 有效）
    TreasuryUrgency urgency       // V14 紧急标记（仅 TREASURY 有效）
) external onlyRole(PROPOSER_ROLE) onlyChamberMember returns (uint256) {
    if (pType == ProposalType.IMPEACHMENT) revert UseCreateImpeachmentProposal();
    if (bytes(title).length == 0) revert EmptyTitle();
    if (bytes(ipfsHash).length == 0) revert EmptyIpfs();
    if (pType == ProposalType.TREASURY && target == address(0)) revert TreasuryTargetZero();
    if (pType == ProposalType.PARAM) _checkParamWhitelist(calldataPayload);
    if (isConstitutional && pType != ProposalType.PARAM) revert ConstitutionalOnlyForParam();
    
    uint256 id = proposalCount++;
    Proposal storage p = proposals[id];
    p.id = id;
    p.proposer = msg.sender;
    p.pType = pType;
    p.title = title;
    p.ipfsHash = ipfsHash;
    p.createdAt = block.timestamp;
    p.status = ProposalStatus.Drafting;
    p.target = target;
    p.calldataPayload = calldataPayload;
    p.isConstitutional = isConstitutional;
    p.urgency = urgency;
    p.requiredReturnSignatures = RETURN_SIGNATURES;
    
    emit ProposalCreated(id, msg.sender, pType, title);
    return id;
}
```

**onlyChamberMember modifier**：tier 1-9 可提案，普通公民（14）/理事（10-12）/元老（13）不能直接发起普通提案。

**验证**：
- [ ] tier 1-9 可创建
- [ ] tier 10/11/12/13/14 创建 revert
- [ ] isConstitutional=true 且 pType != PARAM revert

---

### 步骤 3.5：理事会推进/退回（Q3 + V6）

**任务**：
```solidity
// 理事长推进
function advanceProposal(uint256 proposalId) external {
    Proposal storage p = proposals[proposalId];
    if (p.status != ProposalStatus.Drafting) revert NotDrafting();
    
    uint8 tier = ringContract.getTier(msg.sender);
    if (tier != 12) revert NotCouncilChair();
    
    p.status = ProposalStatus.PendingFirstVote;
    emit ProposalAdvanced(proposalId);
}

// ≥2 理事联署退回
function returnProposal(uint256 proposalId) external {
    Proposal storage p = proposals[proposalId];
    if (p.status != ProposalStatus.Drafting) revert NotDrafting();
    
    uint8 tier = ringContract.getTier(msg.sender);
    if (tier < 10 || tier > 12) revert NotCouncilMember();
    if (p.hasSignedReturn[msg.sender]) revert AlreadySigned();
    
    p.hasSignedReturn[msg.sender] = true;
    p.currentReturnSignatures += 1;
    
    if (p.currentReturnSignatures >= p.requiredReturnSignatures) {
        p.status = ProposalStatus.ReturnedToDraft;
        emit ProposalReturned(proposalId);
    }
}

// 退回后提议人修改重新推进
function resubmitFromReturn(uint256 proposalId, string calldata newTitle, string calldata newIpfs) external {
    Proposal storage p = proposals[proposalId];
    if (p.status != ProposalStatus.ReturnedToDraft) revert NotReturnedToDraft();
    if (msg.sender != p.proposer) revert NotProposer();
    
    p.title = newTitle;
    p.ipfsHash = newIpfs;
    p.currentReturnSignatures = 0;
    // 重置联署记录需额外 mapping，简化：用 proposalId+address 组合 key
    p.status = ProposalStatus.Drafting;
    emit ProposalResubmitted(proposalId);
}
```

**验证**：
- [ ] 非理事长 advance revert
- [ ] 2 理事联署触发 return
- [ ] 退回后只有原 proposer 可 resubmit

---

### 步骤 3.6：议会一审

**任务**：
```solidity
function startFirstVote(uint256 proposalId) external {
    Proposal storage p = proposals[proposalId];
    if (p.status != ProposalStatus.PendingFirstVote) revert NotPendingFirstVote();
    
    p.status = ProposalStatus.FirstVoteActive;
    p.firstVoteStartAt = block.timestamp;
    p.firstVoteEndAt = block.timestamp + FIRST_VOTE_PERIOD;
    emit FirstVoteStarted(proposalId);
}

function castFirstVote(uint256 proposalId, VoteOption option) external inFirstVoteWindow(proposalId) {
    Proposal storage p = proposals[proposalId];
    if (p.hasFirstVoted[msg.sender]) revert AlreadyVoted();
    
    uint8 tier = ringContract.getTier(msg.sender);
    if (!_isParliamentMember(tier)) revert NotParliamentMember();
    
    uint256 weight = internalWeight[tier];
    if (option == VoteOption.FOR) p.parliamentFor += weight;
    else if (option == VoteOption.AGAINST) p.parliamentAgainst += weight;
    
    p.hasFirstVoted[msg.sender] = true;
    ringContract.markVoteActivity(msg.sender);
    emit FirstVoteCast(proposalId, msg.sender, option);
}

function finalizeFirstVote(uint256 proposalId) external {
    Proposal storage p = proposals[proposalId];
    if (p.status != ProposalStatus.FirstVoteActive) revert NotFirstVoteActive();
    if (block.timestamp < p.firstVoteEndAt) revert FirstVoteNotEnded();
    
    bool passed = p.parliamentFor > p.parliamentAgainst;
    p.status = passed ? ProposalStatus.PendingFormal : ProposalStatus.Defeated;
    emit FirstVoteFinalized(proposalId, passed);
}
```

**注意**：一审只议会成员（tier 1/2/3）参与，复用 `parliamentFor/Against` 字段。

**验证**：
- [ ] 一审窗口 5 天
- [ ] 仅议会成员可投票
- [ ] FOR > AGAINST 通过
- [ ] 通过 → PendingFormal，未通过 → Defeated

---

### 步骤 3.7：正式提案提交 + 法庭合规审查

**任务**：
```solidity
function submitFormalProposal(uint256 proposalId) external {
    Proposal storage p = proposals[proposalId];
    if (p.status != ProposalStatus.PendingFormal) revert NotPendingFormal();
    if (msg.sender != p.proposer && ringContract.getTier(msg.sender) != 12) revert NotAuthorized();
    
    p.status = ProposalStatus.PendingCompliance;
    emit FormalProposalSubmitted(proposalId);
}

function startComplianceVote(uint256 proposalId) external {
    Proposal storage p = proposals[proposalId];
    if (p.status != ProposalStatus.PendingCompliance) revert NotPendingCompliance();
    
    p.status = ProposalStatus.PublicVoteActive;  // 直接进入公投，合规审查并行
    // 或者新增 ComplianceActive 状态，根据决策
    // 当前决策：法庭审查是独立阶段，复用投票基础设施
    p.complianceVoteStartAt = block.timestamp;
    p.complianceVoteEndAt = block.timestamp + 3 days;
    emit ComplianceVoteStarted(proposalId);
}

function castComplianceVote(uint256 proposalId, VoteOption option) external {
    Proposal storage p = proposals[proposalId];
    uint8 tier = ringContract.getTier(msg.sender);
    if (!_isTribunalMember(tier)) revert NotTribunalMember();
    if (p.hasComplianceVoted[msg.sender]) revert AlreadyVoted();
    
    uint256 weight = internalWeight[tier];
    if (option == VoteOption.FOR) p.complianceFor += weight;
    else if (option == VoteOption.AGAINST) p.complianceAgainst += weight;
    
    p.hasComplianceVoted[msg.sender] = true;
    emit ComplianceVoteCast(proposalId, msg.sender, option);
}

function finalizeCompliance(uint256 proposalId) external {
    Proposal storage p = proposals[proposalId];
    if (block.timestamp < p.complianceVoteEndAt) revert ComplianceNotEnded();
    
    bool compliant = p.complianceFor > p.complianceAgainst;
    if (compliant) {
        // 进入公投
        p.status = ProposalStatus.PublicVoteActive;
        p.publicVoteStartAt = block.timestamp;
        p.publicVoteEndAt = block.timestamp + PUBLIC_VOTE_PERIOD;
        // V3 快照：公投开始瞬间
        p.citizenTotalSnapshot = ringContract.getActiveCitizens();
    } else {
        // 退回草稿
        p.status = ProposalStatus.ReturnedToDraft;
    }
    emit ComplianceFinalized(proposalId, compliant);
}
```

**验证**：
- [ ] 仅法庭成员可投合规票
- [ ] 合规 → 进入公投 + 快照公民数
- [ ] 不合规 → ReturnedToDraft

---

### 步骤 3.8：公投投票（三院 + 公民）

**任务**：
```solidity
function castPublicVote(uint256 proposalId, VoteOption option) external inPublicVoteWindow(proposalId) {
    Proposal storage p = proposals[proposalId];
    if (p.hasPublicVoted[msg.sender]) revert AlreadyVoted();
    
    uint8 tier = ringContract.getTier(msg.sender);
    if (tier == 0) revert NotRingBearer();
    
    uint256 weight = internalWeight[tier];
    
    if (_isParliamentMember(tier)) {
        if (option == VoteOption.FOR) p.parliamentFor += weight;
        else if (option == VoteOption.AGAINST) p.parliamentAgainst += weight;
    } else if (_isFederationMember(tier)) {
        if (option == VoteOption.FOR) p.federationFor += weight;
        else if (option == VoteOption.AGAINST) p.federationAgainst += weight;
    } else if (_isTribunalMember(tier)) {
        if (option == VoteOption.FOR) p.tribunalFor += weight;
        else if (option == VoteOption.AGAINST) p.tribunalAgainst += weight;
    } else if (tier == 14) {
        // 公民一人一票
        if (option == VoteOption.FOR) p.citizenFor += 1;
        else if (option == VoteOption.AGAINST) p.citizenAgainst += 1;
        else if (option == VoteOption.ABSTAIN) p.citizenAbstain += 1;
    } else {
        revert NotEligibleVoter();  // 理事会/元老不参与公投
    }
    
    p.hasPublicVoted[msg.sender] = true;
    ringContract.markVoteActivity(msg.sender);
    emit PublicVoteCast(proposalId, msg.sender, option);
}
```

**注意**：一审已计入的 parliamentFor/Against 在公投阶段**重置**或**累加**？决策：**重置**（公投是独立阶段，一审结果仅决定是否进入公投）。

**修正**：在 `finalizeCompliance` 合规通过时重置三院计数：
```solidity
p.parliamentFor = 0;
p.parliamentAgainst = 0;
p.federationFor = 0;
p.federationAgainst = 0;
p.tribunalFor = 0;
p.tribunalAgainst = 0;
```

**验证**：
- [ ] 三院成员按权重投票
- [ ] 公民一人一票
- [ ] 理事会/元老 revert
- [ ] 重复投票 revert

---

### 步骤 3.9：finalizeProposal（新计票）

**任务**：
```solidity
function finalizeProposal(uint256 proposalId) external {
    Proposal storage p = proposals[proposalId];
    if (p.status != ProposalStatus.PublicVoteActive) revert NotPublicVoteActive();
    if (block.timestamp < p.publicVoteEndAt) revert PublicVoteNotEnded();
    
    // 1. 每院内部多数决
    p.parliamentStance = _stanceOf(p.parliamentFor, p.parliamentAgainst);
    p.federationStance = _stanceOf(p.federationFor, p.federationAgainst);
    p.tribunalStance = _stanceOf(p.tribunalFor, p.tribunalAgainst);
    
    // 2. 公民参与率检查
    uint256 citizenVotes = p.citizenFor + p.citizenAgainst + p.citizenAbstain;
    uint256 requiredQuorum = p.isConstitutional ? CONSTITUTIONAL_QUORUM_BPS : CITIZEN_QUORUM_BPS;
    p.citizenQuorumMet = p.citizenTotalSnapshot > 0 
        && (citizenVotes * BPS_DENOMINATOR) / p.citizenTotalSnapshot >= requiredQuorum;
    
    // 3. 加权计算
    uint256 chamberForCount = _countStance(p.parliamentStance, ChamberStance.FOR)
                            + _countStance(p.federationStance, ChamberStance.FOR)
                            + _countStance(p.tribunalStance, ChamberStance.FOR);
    uint256 chamberForBps = chamberForCount * CHAMBER_WEIGHT_BPS;
    
    uint256 citizenForBps = citizenVotes > 0
        ? (p.citizenFor * BPS_DENOMINATOR) / citizenVotes
        : 0;
    
    uint256 totalForBps = chamberForBps + (citizenForBps * CITIZEN_WEIGHT_BPS) / BPS_DENOMINATOR;
    
    p.passed = p.citizenQuorumMet && totalForBps > PASS_THRESHOLD_BPS;
    
    p.status = p.passed ? ProposalStatus.PendingVeto : ProposalStatus.Defeated;
    p.vetoWindowEndAt = block.timestamp + VETO_WINDOW;
    
    emit ProposalFinalized(proposalId, p.passed, ...);
}

function _stanceOf(uint256 forVotes, uint256 againstVotes) internal pure returns (ChamberStance) {
    if (forVotes > againstVotes) return ChamberStance.FOR;
    if (againstVotes > forVotes) return ChamberStance.AGAINST;
    return ChamberStance.NEUTRAL;
}

function _countStance(ChamberStance s, ChamberStance target) internal pure returns (uint256) {
    return s == target ? 1 : 0;
}
```

**验证**：
- [ ] 三院全 FOR + 公民 0% 参与 → 失败（quorum 未达）
- [ ] 三院全 FOR + 公民 30% 参与 + 公民 100% FOR → 60% + 60%×60%=36% = 96% > 50% → 通过
- [ ] 公民 quorum 20% 普通 / 50% 章程修订
- [ ] isConstitutional=true 时 quorum 提升至 50%

---

### 步骤 3.10：元老否决（Q2 + V5）

**任务**：
```solidity
function vetoProposal(uint256 proposalId) external {
    Proposal storage p = proposals[proposalId];
    if (p.status != ProposalStatus.PendingVeto) revert NotPendingVeto();
    
    // V5：IMPEACHMENT 不可否决
    if (p.pType == ProposalType.IMPEACHMENT) revert CannotVetoImpeachment();
    
    // 仅任命元老可否决（V10）
    if (!ringContract.isElderActive(msg.sender)) revert NotAppointedElder();
    if (p.hasVetoed[msg.sender]) revert AlreadyVetoed();
    
    p.hasVetoed[msg.sender] = true;
    p.currentVetoSignatures += 1;
    
    if (p.currentVetoSignatures >= p.requiredVetoSignatures) {
        p.status = ProposalStatus.Canceled;
        emit ProposalVetoed(proposalId);
    }
}

function finalizeVetoWindow(uint256 proposalId) external {
    Proposal storage p = proposals[proposalId];
    if (p.status != ProposalStatus.PendingVeto) revert NotPendingVeto();
    if (block.timestamp < p.vetoWindowEndAt) revert VetoWindowNotEnded();
    
    // 72h 未否决 → 进入 Timelock
    p.status = ProposalStatus.Queued;
    p.queuedAt = block.timestamp;
    // V14 紧急拨款 12h，普通 48h
    p.executeAfter = block.timestamp + (
        p.urgency == TreasuryUrgency.Emergency ? TIMELOCK_EMERGENCY : TIMELOCK_NORMAL
    );
    emit ProposalQueued(proposalId, p.executeAfter);
}
```

**验证**：
- [ ] 3 任命元老联署否决 → Canceled
- [ ] 退休元老否决 revert
- [ ] IMPEACHMENT 否决 revert
- [ ] 72h 超时 → Queued
- [ ] 紧急拨款 Timelock 12h

---

### 步骤 3.11：executeProposal

**任务**：
```solidity
function executeProposal(uint256 proposalId) external {
    Proposal storage p = proposals[proposalId];
    if (p.status != ProposalStatus.Queued) revert NotQueued();
    if (block.timestamp < p.executeAfter) revert TimelockNotElapsed();
    
    if (p.pType == ProposalType.SIGNAL) {
        // 信号性提案，无链上执行
        p.status = ProposalStatus.Executed;
    } else if (p.pType == ProposalType.PARAM) {
        // 白名单校验（已在创建时检查，这里再校验防绕过）
        _checkParamWhitelist(p.calldataPayload);
        (bool ok, bytes memory ret) = address(this).call(p.calldataPayload);
        if (!ok) revert ExecutionFailed(ret);
        p.status = ProposalStatus.Executed;
    } else if (p.pType == ProposalType.TREASURY) {
        // V14 紧急拨款需 3 元老快速批准
        if (p.urgency == TreasuryUrgency.Emergency && p.emergencyApprovals < EMERGENCY_ELDER_APPROVALS) {
            revert EmergencyApprovalNotMet();
        }
        (bool ok, bytes memory ret) = p.target.call(p.calldataPayload);
        if (!ok) revert ExecutionFailed(ret);
        p.status = ProposalStatus.Executed;
    }
    
    p.isExecuted = true;
    emit ProposalExecuted(proposalId, "");
}

function approveEmergencyTreasury(uint256 proposalId) external {
    Proposal storage p = proposals[proposalId];
    if (p.urgency != TreasuryUrgency.Emergency) revert NotEmergency();
    if (!ringContract.isElderActive(msg.sender)) revert NotAppointedElder();
    if (p.hasEmergencyApproved[msg.sender]) revert AlreadyApproved();
    
    p.hasEmergencyApproved[msg.sender] = true;
    p.emergencyApprovals += 1;
    emit EmergencyApproved(proposalId, msg.sender);
}
```

**验证**：
- [ ] Timelock 未到 revert
- [ ] 紧急拨款无 3 元老批准 revert
- [ ] 执行成功 → Executed

---

### 步骤 3.12：弹劾重写（Q9 + V5 + V10）

**任务**：
```solidity
function createImpeachmentProposal(
    address target,
    string calldata title,
    string calldata ipfsHash
) external returns (uint256) {
    // 仅任命元老可发起
    if (!ringContract.isElderActive(msg.sender)) revert NotAppointedElder();
    if (target == address(0)) revert ImpeachmentTargetInvalid();
    
    uint8 targetTier = ringContract.getTier(target);
    // V4：可弹劾 tier 1-13，不可弹劾公民 14
    if (targetTier == 0 || targetTier == 14) revert ImpeachmentTargetInvalid();
    
    uint256 id = proposalCount++;
    Proposal storage p = proposals[id];
    p.id = id;
    p.proposer = msg.sender;
    p.pType = ProposalType.IMPEACHMENT;
    p.title = title;
    p.ipfsHash = ipfsHash;
    p.createdAt = block.timestamp;
    p.status = ProposalStatus.Drafting;  // 联署阶段
    p.impeachedTarget = target;
    p.requiredImpeachSignatures = IMPEACHMENT_SIGNATURES;
    
    // 发起人自动联署
    p.hasImpeachSigned[msg.sender] = true;
    p.currentImpeachSignatures = 1;
    
    emit ProposalCreated(id, msg.sender, ProposalType.IMPEACHMENT, title);
    return id;
}

function signImpeachment(uint256 proposalId) external {
    Proposal storage p = proposals[proposalId];
    if (p.status != ProposalStatus.Drafting) revert NotDrafting();
    if (!ringContract.isElderActive(msg.sender)) revert NotAppointedElder();
    if (p.hasImpeachSigned[msg.sender]) revert AlreadySigned();
    
    p.hasImpeachSigned[msg.sender] = true;
    p.currentImpeachSignatures += 1;
    
    if (p.currentImpeachSignatures >= p.requiredImpeachSignatures) {
        // 联署满，直接进入公投（无多签审查，无法庭审查）
        p.status = ProposalStatus.PublicVoteActive;
        p.publicVoteStartAt = block.timestamp;
        p.publicVoteEndAt = block.timestamp + PUBLIC_VOTE_PERIOD;
        p.citizenTotalSnapshot = ringContract.getActiveCitizens();
        emit ImpeachmentToPublicVote(proposalId);
    }
}

function finalizeImpeachment(uint256 proposalId) external {
    Proposal storage p = proposals[proposalId];
    if (p.status != ProposalStatus.PublicVoteActive) revert NotPublicVoteActive();
    if (block.timestamp < p.publicVoteEndAt) revert PublicVoteNotEnded();
    
    // 弹劾计票：公民参与率 ≥40% + 反对率 ≥60%  (v3.1: 30%/70%)
    uint256 citizenVotes = p.citizenFor + p.citizenAgainst + p.citizenAbstain;
    bool quorumMet = (citizenVotes * BPS_DENOMINATOR) / p.citizenTotalSnapshot >= IMPEACHMENT_QUORUM_BPS;
    // 注意：弹劾的 FOR = 支持弹劾，AGAINST = 反对弹劾
    // 反对率 = citizenAgainst / citizenVotes
    bool passRateMet = citizenVotes > 0 
        && ((p.citizenAgainst * BPS_DENOMINATOR) / citizenVotes >= IMPEACHMENT_PASS_BPS);  // v3.1 已改为 p.citizenFor
    
    bool passed = quorumMet && passRateMet;
    
    if (passed) {
        // 撤销道环
        uint256 ringId = ringContract.getRingId(p.impeachedTarget);
        AetherRing(address(ringContract)).revokeRing(ringId);
        p.status = ProposalStatus.Executed;
    } else {
        p.status = ProposalStatus.Defeated;
    }
    
    emit ImpeachmentFinalized(proposalId, passed);
}
```

**注意**：弹劾跳过法庭审查和元老否决（V5），联署满直接公投。

**验证**：
- [ ] 任命元老发起，退休元老 revert
- [ ] 3 联署后进入公投
- [ ] 公民参与 ≥40% + 反对率 ≥60% → 通过撤销道环 (v3.1: 30%/70%)
- [ ] tier 14 不可弹劾

---

### 步骤 3.13：理事长信任投票（V6）

**任务**：
```solidity
struct ConfidenceVote {
    address chair;
    uint256 startedAt;
    uint256 forVotes;
    uint256 againstVotes;
    mapping(address => bool) hasVoted;
    bool resolved;
}

mapping(uint256 => ConfidenceVote) public confidenceVotes;
uint256 public confidenceVoteCount;
uint256 public constant CONFIDENCE_TRIGGER_SIGNATURES = 8;  // 12 理事的 2/3

function triggerConfidenceVote(address chair, string calldata reasonIpfs) external {
    // 8 理事联署触发
    require(_councilTriggerSignatures[chair] >= CONFIDENCE_TRIGGER_SIGNATURES, "Not enough signatures");
    
    uint256 id = confidenceVoteCount++;
    ConfidenceVote storage cv = confidenceVotes[id];
    cv.chair = chair;
    cv.startedAt = block.timestamp;
    
    emit ConfidenceVoteTriggered(id, chair);
}

function voteConfidence(uint256 voteId, bool support) external {
    ConfidenceVote storage cv = confidenceVotes[voteId];
    if (cv.resolved) revert AlreadyResolved();
    if (cv.hasVoted[msg.sender]) revert AlreadyVoted();
    
    uint8 tier = ringContract.getTier(msg.sender);
    if (tier != 10 && tier != 11) revert NotCouncilMember();  // 仅理事+常务理事
    
    cv.hasVoted[msg.sender] = true;
    if (support) cv.forVotes += 1;
    else cv.againstVotes += 1;
}

function finalizeConfidence(uint256 voteId) external {
    ConfidenceVote storage cv = confidenceVotes[voteId];
    if (cv.resolved) revert AlreadyResolved();
    if (block.timestamp < cv.startedAt + 7 days) revert ConfidenceVoteNotEnded();
    
    cv.resolved = true;
    bool passed = cv.forVotes > cv.againstVotes;
    
    if (!passed) {
        // 理事长 30 天内需辞职或接受弹劾
        // 标记理事长进入"待辞职"状态
        _chairPendingResign[cv.chair] = block.timestamp + 30 days;
        emit ChairConfidenceFailed(voteId, cv.chair);
    }
    
    emit ConfidenceVoteFinalized(voteId, passed);
}
```

**验证**：
- [ ] 8 理事联署触发
- [ ] 仅理事+常务理事可投票
- [ ] 简单多数决定
- [ ] 不通过 → 30 天辞职窗口

---

### 步骤 3.14：library 抽取（防超 24KB）

**新建文件**：`contracts/src/libraries/AetherGovernanceLib.sol`

**任务**：如果合约体积接近 24KB，抽取以下纯函数到 library：
- `_stanceOf` / `_countStance` / `_checkParamWhitelist`
- `_accumulateVote` 计票核心逻辑
- `_finalizeNormal` 加权计算

```solidity
library AetherGovernanceLib {
    function stanceOf(uint256 forVotes, uint256 againstVotes) internal pure returns (uint8) { ... }
    function calculateTotalFor(
        uint8 parliamentStance, uint8 federationStance, uint8 tribunalStance,
        uint256 citizenFor, uint256 citizenVotes
    ) internal pure returns (uint256) { ... }
    function checkParamWhitelist(bytes memory payload) internal pure { ... }
}
```

**验证**：
- [ ] 合约体积 < 24KB
- [ ] library 函数被正确调用

---

### 步骤 3.15：单元测试

**改动文件**：`contracts/test/AetherGovernance.t.sol`（完全重写）

**测试用例清单**（核心，不全列）：

| # | 测试名 | 覆盖点 |
|---|---|---|
| T3.1 | test_CreateProposal_FederationMember_Success | tier 4 创建成功 |
| T3.2 | test_CreateProposal_Citizen_Revert | tier 14 创建 revert |
| T3.3 | test_AdvanceProposal_OnlyChair_Success | 理事长推进 |
| T3.4 | test_AdvanceProposal_NonChair_Revert | 非理事长 revert |
| T3.5 | test_ReturnProposal_2Signatures_TriggersReturn | 2 理事退回 |
| T3.6 | test_FirstVote_ParliamentOnly | 仅议会一审 |
| T3.7 | test_FirstVote_Passes_ForGtAgainst | 通过进 PendingFormal |
| T3.8 | test_ComplianceVote_TribunalOnly | 仅法庭合规 |
| T3.9 | test_Compliance_Reject_ReturnsToDraft | 不合规退回 |
| T3.10 | test_PublicVote_AllChambersAndCitizens | 三院+公民投票 |
| T3.11 | test_PublicVote_CouncilAndElder_Revert | 理事会/元老 revert |
| T3.12 | test_Finalize_AllChambersFOR_Citizen0Pct_Fails | quorum 未达失败 |
| T3.13 | test_Finalize_AllFOR_Citizen30Pct_Passes | 通过场景 |
| T3.14 | test_Finalize_Constitutional_Quorum50Pct | 章程修订 quorum 50% |
| T3.15 | test_Veto_3AppointedElders_Cancels | 3 元老否决 |
| T3.16 | test_Veto_RetiredElder_Revert | 退休元老 revert |
| T3.17 | test_Veto_Impeachment_Revert | 弹劾不可否决 |
| T3.18 | test_VetoWindow_72hTimeout_Queued | 72h 超时进 Timelock |
| T3.19 | test_Execute_TimelockNotElapsed_Revert | Timelock 未到 revert |
| T3.20 | test_Execute_EmergencyTreasury_3ElderApprovals | 紧急拨款 3 元老批准 |
| T3.21 | test_Impeachment_Create_AppointedElderOnly | 仅任命元老发起 |
| T3.22 | test_Impeachment_3Signatures_ToPublicVote | 3 联署进公投 |
| T3.23 | test_Impeachment_40PctQuorum_60PctAgainst_Passes | 通过撤销道环 // v3.1 已重命名为 test_Impeachment_30PctQuorum_70PctFor_Passes |
| T3.24 | test_Impeachment_TargetCitizen_Revert | 弹劾公民 revert |
| T3.25 | test_ConfidenceVote_8Signatures_Trigger | 8 理事联署触发 |
| T3.26 | test_ConfidenceVote_CouncilOnly | 仅理事投票 |
| T3.27 | test_ConfidenceVote_NotPassed_30DayResign | 不通过 30 天辞职 |
| T3.28 | test_StateTransition_DraftingToPendingFirst | 状态转换 |
| T3.29 | test_StateTransition_Illegal_AllRevert | 非法转换全 revert |
| T3.30 | test_FullFlow_ProposalToExecution | 端到端流程 |

**验证**：
- [ ] 30 个测试通过
- [ ] forge coverage ≥ 90%

---

### 第 3 轮质量门禁

```
✅ 12 状态枚举 + 11 转换函数
✅ 非法转换全部 revert
✅ 计票公式：总赞成=(FOR院数×20%)+(公民赞成率×60%)>50% 且 公民参与≥20% (v3.1: =(FOR院数×1666)+(公民赞成率×5000/10000)>5000)
✅ quorum 快照在 startPublicVote（getActiveCitizens）
✅ 元老否决对 IMPEACHMENT 不可用
✅ 弹劾仅任命元老发起，3 联署，40%/60% (v3.1: 30%/70%)
✅ 章程修订 quorum 50%
✅ 紧急拨款 12h + 3 元老批准
✅ 信任投票 8 理事联署
✅ 合约体积 < 24KB（或已拆分 library）
✅ 30 个测试通过
✅ solc-js 编译 0 错误
```

---

## 第 4 轮：AetherElection v3（选举模块）

**依赖**：第 1 轮（AetherRing）+ 第 3 轮（议会审批接口）
**目标**：删 REELECTION + 新增 CITIZEN_TO_COUNCIL + 4 阶段状态机 + 空缺处理

### 步骤 4.1：删除 REELECTION

**改动文件**：`contracts/src/AetherElection.sol`

**任务**：
1. 删除 `REELECTION` 枚举值
2. 删除 `castReelectionAgainst()` 函数
3. 删除 `_applyReelection()` 函数
4. 删除 `reelectionTarget` 参数

**验证**：
- [ ] 编译无 REELECTION 引用残留

---

### 步骤 4.2：新增 CITIZEN_TO_COUNCIL

**任务**：
```solidity
enum ElectionType {
    MEMBER_TO_GRASSROOTS,   // 公民 → 三院基层
    GRASSROOTS_TO_MID,      // 三院基层 → 中层
    CITIZEN_TO_COUNCIL      // 公民 → 理事/常务理事（新增）
}

enum CouncilTargetTier {
    CouncilMember,      // tier 10
    CouncilSenior       // tier 11
}

struct Election {
    uint256 id;
    ElectionType eType;
    uint8 chamber;              // 1=议会 2=联邦 3=法庭 4=理事 5=常务理事
    uint256 seatCount;
    uint256 registrationStartAt;
    uint256 registrationEndAt;
    uint256 votingStartAt;
    uint256 votingEndAt;
    address[] candidates;
    mapping(address => uint256) candidateVotes;
    mapping(address => bool) hasVoted;
    address[] winners;
    ElectionStatus status;
    uint256 unfilledSeats;      // V12 空缺
}
```

---

### 步骤 4.3：4 阶段状态机

**任务**：
```solidity
enum ElectionStage {
    CandidateRegistration,  // 候选人注册/提名
    CouncilReview,          // 理事会整理
    ParliamentApproval,     // 议会审批
    Voting,                 // 实际投票
    Finalized
}

function createElection(ElectionType eType, uint8 chamber, uint256 seatCount) external onlyRole(ADMIN_ROLE) returns (uint256) {
    // 初始化为 CandidateRegistration 阶段
}

function registerCandidate(uint256 electionId) external {
    // 公民自荐（基层）/ 高层提名（中层）
}

function approveCandidate(uint256 electionId, address candidate) external {
    // 理事会整理阶段
}

function parliamentApproveCandidateList(uint256 electionId) external {
    // 议会审批阶段
}

function castVote(uint256 electionId, address candidate) external {
    // Voting 阶段
}

function finalizeElection(uint256 electionId) external {
    // 计票，选出 winners
    // V12：空缺处理
}
```

---

### 步骤 4.4：候选人资格放宽（V5）

**任务**：
```solidity
function _isEligibleCandidate(ElectionType eType, uint8 chamber, address candidate) internal view returns (bool) {
    uint8 tier = ringContract.getTier(candidate);
    
    if (eType == ElectionType.MEMBER_TO_GRASSROOTS) {
        // 公民或到期成员
        if (tier == 14) return true;
        if (tier >= 1 && tier <= 9) {
            uint256 ringId = ringContract.getRingId(candidate);
            return ringContract.isExpired(ringId);
        }
        return false;
    }
    if (eType == ElectionType.CITIZEN_TO_COUNCIL) {
        return tier == 14;
    }
    if (eType == ElectionType.GRASSROOTS_TO_MID) {
        if (chamber == 1) return tier == 1;
        if (chamber == 2) return tier == 4;
        if (chamber == 3) return tier == 7;
    }
    return false;
}
```

---

### 步骤 4.5：空缺处理（V12）

**任务**：
```solidity
function finalizeElection(uint256 electionId) external {
    Election storage e = elections[electionId];
    // ... 计票选出 winners[] ...
    
    uint256 filledSeats = e.winners.length;
    if (filledSeats < e.seatCount) {
        e.unfilledSeats = e.seatCount - filledSeats;
        e.status = ElectionStatus.PartiallyFilled;
        emit SeatsUnfilled(electionId, e.unfilledSeats);
    } else {
        e.status = ElectionStatus.Finalized;
    }
}

function appointToVacancy(uint256 electionId, address candidate) external onlyRole(COUNCIL_CHAIR_ROLE) {
    Election storage e = elections[electionId];
    if (e.status != ElectionStatus.PartiallyFilled) revert NoVacancy();
    if (e.unfilledSeats == 0) revert NoVacancy();
    
    // 议会审批（简化：直接调用 governance.createProposal 走审批流程）
    // 或在 election 合约内实现简化审批
    
    e.winners.push(candidate);
    e.unfilledSeats -= 1;
    
    // 任命，任期至下次选举
    AetherRing.RingTier targetTier = e.chamber == 4 ? AetherRing.RingTier.COUNCIL_MEMBER : AetherRing.RingTier.COUNCIL_SENIOR;
    uint256 ringId = ringContract.getRingId(candidate);
    AetherRing(address(ringContract)).updateTier(ringId, targetTier, true);
    
    if (e.unfilledSeats == 0) e.status = ElectionStatus.Finalized;
    emit VacancyFilled(electionId, candidate);
}
```

---

### 步骤 4.6：单元测试

| # | 测试名 | 覆盖点 |
|---|---|---|
| T4.1 | test_MemberToGrassroots_CitizenCanRegister | 公民可注册 |
| T4.2 | test_MemberToGrassroots_ExpiredMemberCanRegister | 到期成员可注册 |
| T4.3 | test_GrassrootsToMid_OnlyCorrespondingGrassroots | 仅对应院基层 |
| T4.4 | test_CitizenToCouncil_OnlyCitizen | 仅公民可参选理事 |
| T4.5 | test_CouncilReview_ApproveReject | 理事会整理 |
| T4.6 | test_ParliamentApproval_Vote | 议会审批 |
| T4.7 | test_Voting_TopNWinners | 前 N 名当选 |
| T4.8 | test_Finalize_PartiallyFilled | 名额不足空缺 |
| T4.9 | test_AppointToVacancy_ChairAppoints | 理事长填补 |
| T4.10 | test_NoCandidates_Extend7Days | 无人参选延长 |

---

### 第 4 轮质量门禁

```
✅ REELECTION 已删除
✅ CITIZEN_TO_COUNCIL 新增
✅ 4 阶段状态机
✅ 候选人资格放宽（公民/到期）
✅ 空缺处理 + 临时任命
✅ 10 个测试通过
✅ solc-js 编译 0 错误
✅ 合约体积 < 24KB
```

---

## 第 5 轮：跨合约集成与部署脚本

**依赖**：第 1-4 轮
**目标**：部署脚本 + 交叉授权 + 集成测试 + 创世数据

### 步骤 5.1：部署脚本

**改动文件**：`contracts/script/Deploy.s.sol`

**任务**：按依赖顺序部署 4 个合约：
```solidity
function run() external {
    // 1. AetherRing
    AetherRing ring = new AetherRing();
    
    // 2. AetherDonation
    AetherDonation donation = new AetherDonation(address(ring), treasury, msg.sender);
    
    // 3. AetherGovernance
    AetherGovernance governance = new AetherGovernance(address(ring));
    
    // 4. AetherElection
    AetherElection election = new AetherElection(address(ring));
    
    // 交叉授权
    ring.grantRole(ring.MINTER_ROLE(), address(donation));
    ring.grantRole(ring.ADMIN_ROLE(), address(governance));
    ring.grantRole(ring.ADMIN_ROLE(), address(election));
    ring.grantRole(ring.MINTER_ROLE(), address(election));
    ring.grantRole(ring.GOVERNANCE_ROLE(), address(governance));
    ring.grantRole(ring.ELECTION_ROLE(), address(election));
    
    // 输出地址
    console.log("AetherRing:", address(ring));
    console.log("AetherDonation:", address(donation));
    console.log("AetherGovernance:", address(governance));
    console.log("AetherElection:", address(election));
}
```

---

### 步骤 5.2：集成测试

**新建文件**：`contracts/test/Integration.t.sol`

**端到端流程**：

| # | 测试名 | 流程 |
|---|---|---|
| T5.1 | test_FullProposalFlow_DraftToExecute | 联邦提议→理事长推进→议会一审→法庭审查→公投→否决窗口→执行 |
| T5.2 | test_FullImpeachmentFlow | 元老发起→3联署→公投→撤销道环 |
| T5.3 | test_FullElectionFlow | 创建选举→候选人注册→理事会整理→议会审批→投票→finalize→任命 |
| T5.4 | test_DonationFlow_FirstDonation | PayPal捐款→铸公民道环→settle |
| T5.5 | test_CrossContract_RoleEnforcement | 跨合约角色权限校验 |

---

### 步骤 5.3：创世数据脚本

**新建文件**：`contracts/script/Genesis.s.sol`

**任务**：铸造初始道环（创世高层 + 任命元老）：
```solidity
// 三院高层各 2 人（共 6 人）
// 理事长 2 人
// 初始任命元老 5 人（启动治理）
// 初始公民 100 人（测试用）
```

---

### 第 5 轮质量门禁

```
✅ 部署脚本执行成功
✅ 4 合约地址输出
✅ 交叉授权正确
✅ 5 个集成测试通过
✅ 创世数据脚本可执行
```

---

## 第 6 轮：前端 ABI 与接口对接

**依赖**：第 5 轮
**目标**：ABI 重生成 + 枚举更新 + hooks

### 步骤 6.1：重新生成 ABI

**任务**：运行 `node scripts/regen-frontend-abi.js`，生成 4 个 .abi.ts：
- `src/lib/contracts/AetherRing.abi.ts`
- `src/lib/contracts/AetherDonation.abi.ts`
- `src/lib/contracts/AetherGovernance.abi.ts`
- `src/lib/contracts/AetherElection.abi.ts`

**验证**：
- [ ] 4 个文件生成
- [ ] tsc --noEmit 0 错误

---

### 步骤 6.2：枚举更新

**改动文件**：`src/lib/contracts/index.ts`

**任务**：
1. RingTier 枚举更新为 14 级
2. TIER_LABELS 更新（含中英文 + chamber）
3. chamberOf 函数更新（5 机构）
4. ProposalStatus 更新为 12 状态
5. ElectionType 更新（删 REELECTION，加 CITIZEN_TO_COUNCIL）
6. 新增 TreasuryUrgency / ElectionStage / CouncilTargetTier 枚举

---

### 步骤 6.3：config.ts 更新

**任务**：新增 AetherDonation 地址占位：
```typescript
export interface ContractAddresses {
    AetherRing: `0x${string}`;
    AetherGovernance: `0x${string}`;
    AetherElection: `0x${string}`;
    AetherDonation: `0x${string}`;  // 新增
    SafeWallet: `0x${string}`;
}
```

---

### 步骤 6.4：hooks 更新

| 文件 | 任务 |
|---|---|
| `src/hooks/useRingInfo.ts` | 适配 14 tier + 新字段（isDormant/isRetiredElder/isAppointedElder/lastActivityAt） |
| `src/hooks/useGovernance.ts` | 适配 7 阶段流程 + 12 状态 + 新转换函数 |
| `src/hooks/useImpeachment.ts` | 适配元老发起 + 3 联署 + 40%/60% |
| `src/hooks/useElection.ts` | 适配 4 阶段 + CITIZEN_TO_COUNCIL + 空缺处理 |
| `src/hooks/useDonation.ts`（新建） | mintDonation + settleDonation + sponsorDonation + 查询 |

---

### 第 6 轮质量门禁

```
✅ 4 个 ABI 文件生成
✅ index.ts 枚举完整（14 tier + 12 status + 新 ElectionType）
✅ config.ts 含 AetherDonation 地址
✅ 5 个 hooks 更新/新建
✅ tsc --noEmit 0 错误
✅ pnpm build 成功
```

---

## 质量门禁与验证标准

### 全局验证命令

每轮完成后执行：

```bash
# 1. 编译验证（solc-js 0.8.26）
node scripts/verify-contracts.js

# 2. 测试（需 forge，沙盒可能跳过）
forge test -vvv

# 3. 合约体积检查
node scripts/verify-contracts.js  # 输出含体积报告

# 4. 前端类型检查（第 6 轮）
npx tsc --noEmit

# 5. 前端构建（第 6 轮）
pnpm build
```

### 验收标准

| 项 | 标准 |
|---|---|
| 合约编译 | 0 错误，0 警告（或仅 setChamberWeights view 警告） |
| 合约体积 | 全部 < 24KB |
| 单元测试 | 全部通过，coverage ≥ 90% |
| 集成测试 | 端到端流程通过 |
| 前端类型 | tsc 0 错误 |
| 前端构建 | pnpm build 成功 |

### 交付物清单

1. ✅ 合约源码（4 个合约 + 接口 + library）
2. ✅ 单元测试（4 个 .t.sol）
3. ✅ 集成测试（Integration.t.sol）
4. ✅ 部署脚本（Deploy.s.sol + Genesis.s.sol）
5. ✅ 前端 ABI（4 个 .abi.ts）
6. ✅ 前端枚举与 hooks
7. ✅ 部署文档（DEPLOY.md 更新）
8. ✅ 迁移指南（v2 → v3）

---

## 风险与应对

| 风险 | 触发条件 | 应对 |
|---|---|---|
| 合约超 24KB | AetherGovernance 编译 >24KB | 步骤 3.14 library 抽取，必要时拆 AetherProposalFlow |
| 状态机测试覆盖不足 | 非法转换未被拦截 | Foundry invariant 测试覆盖所有路径 |
| 防女巫服务端延迟 | PayPal webhook 响应慢 | 链上基础逻辑先实现，服务端优化后置 |
| 公民休眠误判 | markDormantIfDue 被恶意触发 | 任何人可触发但仅标记，无资金损失；可重新捐款激活 |
| 计票精度问题 | BPS 万分比计算误差 | 用 1e18 精度计算，最后比较 |
| 跨合约权限错位 | 角色授权遗漏 | 部署脚本自动化 + 集成测试验证 |

---

**文档结束**

按照本步骤逐轮开发，每轮完成后对照质量门禁检查，全部通过后进入下一轮。
