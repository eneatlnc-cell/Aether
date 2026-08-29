# Aether DAO v3.6 现实环境待解决问题清单

> **版本**：v3.6（v3.0 Phase 1-6 完成后的遗留事项，v3.6 文档校准更新）
> **日期**：2026-08-29
> **说明**：以下问题需要在真实开发/部署环境（非沙箱）中处理。沙箱内已完成：
> `eslint .` 0 问题、`tsc --noEmit` 0 错误、`npm run build` 生产构建通过、
> `forge test` 93/93 全绿（v3.6 通过代理安装 Foundry 1.8.1）
> **v3.6 校准**：forge test 沙箱内已执行并全绿（修复 1 个测试断言 bug）、
> 修正测试计数（93 个）、部署命令补齐 `SAFE`/`USDC` 必需变量、
> 前端变量后缀 421614/42161 → 97/56（Arbitrum 残留清除）、
> PayPal 章节（§3.1/§3.3）替换为纯链上捐款方案说明
> **v3.6 安全加固（P4 + 收尾）**：API 限流（record 10/min、citizens 60/min，
> 实例内固定窗口，见 `src/lib/rateLimit.ts`）、purpose 白名单+长度上限、
> 捐款 tx 时间窗口校验（拒未来区块/超 30 天旧交易）、500 响应去除 `detail` 回传、
> WC ProjectId 硬编码移除（生产缺配置构建 fail-fast）、双锁文件清理
> （删 `pnpm-lock.yaml`，统一 npm 并补 `lint`/`typecheck`/`test` 脚本）、
> React hooks 新规则 lint 全量修复（`useSyncExternalStore` 替代 mount 检测等）

---

## 一、测试执行（forge test）

### 1.1 安装 Foundry 工具链

**状态**：✅ **v3.6 已完成**（2026-08-29，通过沙箱 HTTP 代理安装 Foundry 1.8.1）

**已执行**：
```bash
# 1. 安装 Foundry（代理环境）
curl -L https://foundry.paradigm.xyz | bash
foundryup          # forge/cast/anvil 1.8.1

# 2. 安装依赖（forge-std v1.16.2 + openzeppelin v5.0.2）
cd contracts
forge install foundry-rs/forge-std --no-commit
git clone --depth 1 --branch v5.0.2 \
  https://github.com/OpenZeppelin/openzeppelin-contracts lib/openzeppelin-contracts

# 3. 运行测试
forge test
```

**结果**：**93 passed / 0 failed / 0 skipped**（5 个测试套件）

**已修复**：`AetherDonation.t.sol` 的
`test_Constructor_18Decimals_BscStablecoin` 原断言
`assertEq(bscUsdt.balanceOf(alice), 0)` 未计入 revert 分支铸入且未消耗的
`small`（9.99 USDT），已改为 `assertEq(bscUsdt.balanceOf(alice), small)`。
**合约逻辑本身无 bug**——唯一失败项是测试自身的断言疏漏。

**真实环境仍需执行**：
```bash
# 覆盖率检查（目标 ≥ 90%）
forge coverage

# invariant 测试（状态机所有路径）
forge test --match-test invariant -vvv
```

---

## 二、合约部署

### 2.1 本地 Anvil 部署验证

**待执行命令**：
```bash
# 1. 启动本地链
anvil --block-time 1 &

# 2. 部署 4 合约（私钥从 Anvil 启动时打印的测试账户复制；切勿硬编码真实私钥）
# TREASURY / SAFE / USDC 三个必需变量缺一不可（Deploy.s.sol M12 校验，缺失即 revert）
# 本地测试：SAFE 需为有代码的地址（H4 校验），可先用 Anvil 自动生成的合约地址；
#           USDC 可用 mock ERC20；0x0 占位时 donateAndMint 不可用，仅验证部署链路
PRIVATE_KEY=<Anvil-打印的第一个测试账户私钥> \
TREASURY=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
SAFE=0x... \
USDC=0x... \
forge script contracts/script/Deploy.s.sol:Deploy \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast -vvv

# 3. 运行创世脚本
RING=0x... GOV=0x... ELECTION=0x... DONATION=0x... \
SAFE=0x... \
PAR_SPEAKER_1=0x... PAR_SPEAKER_2=0x... \
FED_MINISTER_1=0x... FED_MINISTER_2=0x... \
TRIB_CHIEF_1=0x... TRIB_CHIEF_2=0x... \
COUNCIL_1=0x... COUNCIL_2=0x... \
COUNCIL_SENIOR_1=0x... COUNCIL_SENIOR_2=0x... \
COUNCIL_CHAIR=0x... \
ELDER_1=0x... ELDER_2=0x... ELDER_3=0x... ELDER_4=0x... ELDER_5=0x... \
forge script contracts/script/Genesis.s.sol:Genesis \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast -vvv
```

### 2.2 Safe 多签创建

**问题**：`appointElder` 和 `retireToEmeritus` 要求 `msg.sender == Safe`，需要先创建 Safe 多签钱包

**待执行**：
1. 在 BNB Smart Chain 上创建 Safe v1.4.1 多签钱包（建议 3/5 阈值）
2. 将 Safe 地址配置到 `ring.setSafeWallet(<SAFE>)`
3. 通过 Safe 多签执行 5 次 `ring.appointElder(<elder>, "")`
4. 将 `donation.ADMIN_ROLE` 转移给 Safe

**参考**：https://app.safe.global/

### 2.3 BSC 测试网部署

**待执行命令**：
```bash
PRIVATE_KEY=0x... \
TREASURY=0x... \
SAFE=0x... \
USDC=0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d \
forge script contracts/script/Deploy.s.sol:Deploy \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
  --broadcast \
  --verify \
  --etherscan-api-key $BSCSCAN_API_KEY
```

> 测试网 USDC 建议自行部署 mock ERC20（18 decimals）后替换地址。

### 2.4 前端环境变量配置

部署完成后，在 Vercel 或 `.env.local` 中设置：
```bash
# BSC 测试网 (97)
NEXT_PUBLIC_AETHER_RING_97_ADDRESS=0x...
NEXT_PUBLIC_AETHER_GOVERNANCE_97_ADDRESS=0x...
NEXT_PUBLIC_AETHER_ELECTION_97_ADDRESS=0x...
NEXT_PUBLIC_AETHER_DONATION_97_ADDRESS=0x...
NEXT_PUBLIC_SAFE_WALLET_97_ADDRESS=0x...

# BNB Smart Chain (56) - 主网部署后
NEXT_PUBLIC_AETHER_RING_56_ADDRESS=0x...
NEXT_PUBLIC_AETHER_GOVERNANCE_56_ADDRESS=0x...
NEXT_PUBLIC_AETHER_ELECTION_56_ADDRESS=0x...
NEXT_PUBLIC_AETHER_DONATION_56_ADDRESS=0x...
NEXT_PUBLIC_SAFE_WALLET_56_ADDRESS=0x...
```

---

## 三、外部服务集成

### 3.1 捐款链上化（原 PayPal Webhook 已移除）

**v3.3 变更**：PayPal webhook 方案已整体移除（`mintDonation` / `settleDonation` /
`grantMinterRole` / `MINTER_ROLE` 均已从合约删除），**不存在服务端铸币环节**，
无需部署任何后端服务、无需管理服务端私钥。

**现行流程（纯链上）**：
1. 捐款人在前端 `approve` USDC 给 `AetherDonation` 合约
2. 前端调用 `donation.donateAndMint(amount)`（public，任何人可调）
3. 合约内完成：USDC `transferFrom` → 铸捐款凭证 NFT → 铸公民道环
4. 金额下限 $10（`MIN_DONATION_USD`），放弃冷却期内 revert

**仍需真实环境处理的**：
- BSC 主网 Binance-Peg USDC 地址确认（`0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d`，18 decimals）
- USDC `approve` 流程的前端 UI（DonationModal 接入 `useErc20Approve`）
- `donateAndMint` 交易失败的用户提示与重试

### 3.2 IPFS 存储

**问题**：提案的 `ipfsHash` 需要前端上传到 IPFS 后获取

**待配置**：
- IPFS 网关：默认 `https://gateway.pinata.cloud/ipfs/`
- 上传服务：Pinata / Web3.Storage / nft.storage
- 环境变量：`NEXT_PUBLIC_IPFS_GATEWAY`

### 3.3 USDC 到账核对（原 settleDonation 流程已移除）

**v3.3 变更**：`settleDonation` 已删除。USDC 在 `donateAndMint` 内实时
`transferFrom` 到 treasury，**不存在链下结算环节**，Safe 多签无需手动执行转账。

**仍需真实环境处理的**：
- 部署后在 BscScan 复核 treasury 收款地址与 Safe 多签一致
- 监控 `DonationMinted` 事件与 USDC 转账日志逐笔对账（金额 ≥ $1000 告警）
- USDC 合约地址通过 `donation.setUsdcToken(<USDC>)` 配置（ADMIN_ROLE）

---

## 四、前端 hooks 适配（Phase 6 — 已完成）

### 4.1 hooks 更新情况

| 文件 | 状态 | 实现要点 |
|---|---|---|
| `src/hooks/useRingInfo.ts` | ✅ 完成 | 14 tier 枚举 + RingInfo 12 字段（含 isDormant/isRetiredElder/isAppointedElder/lastActivityAt）+ useActiveCitizens + useCanReacquireCitizenship |
| `src/hooks/useGovernance.ts` | ✅ 完成 | 7 阶段流程 + 12 状态 + 21 个写入方法 + 6 个读取 hooks（含信任投票 confidence vote）|
| `src/hooks/useImpeachment.ts` | ✅ 完成 | 元老发起（createImpeachmentProposal）+ 3 联署（signImpeachment）+ 30%/70%（citizenFor）计票（finalizeImpeachment）|
| `src/hooks/useElection.ts` | ✅ 完成 | 4 阶段状态机 + CITIZEN_TO_COUNCIL + appointToVacancy 空缺处理 + 8 个读取 hooks |
| `src/hooks/useDonation.ts` | ✅ 完成 | 保留旧版 ETH 转账 hook（DonationModal 兼容）+ 11 个 v3 读取 hooks + useDonationWrite 写入 hook（donateAndMint/sponsorDonation/setTreasury/setRingContract/setUsdcToken）|

### 4.2 v2 残留引用（已清理）

以下函数/字段在 v3 已删除，已从 hooks 中清理：
- `castReelectionAgainst` → 已删除（v3 不可连任）
- `renewTerm` → 已删除
- `approveImpeachmentByMultisig` → 改为 `createImpeachmentProposal` + `signImpeachment`
- `hasSigned` (impeachment) → 改为 `hasImpeachSigned`
- `GENERAL_MEMBER` → `CITIZEN`
- `SENATE_ADVISOR/FELLOW/ELDER` → `TRIBUNAL_JUDGE/SENIOR/CHIEF`

### 4.3 已知前端待处理（真实环境）

- **金额精度（✅ v3.6 已修复）**：三处浮点换算已改用 viem 精确函数——
  `DonationModal.handleSubmit` 用 `parseUnits`（消除 `parseFloat * 10**18` 舍入误差）、
  `verifyDonationTx` / `generateDonationReceipt` 用 `formatUnits`
  （消除 18 decimals 大数先过 `Number()` 的精度丢失）
- **PDF 凭证 CJK 字体（✅ v3.6 已修复）**：zh-Hant/ko/ja 凭证嵌入
  Noto Sans CJK 子集字体（`public/fonts/NotoSansCJK-Receipt.ttf`，315KB 懒加载），
  三语文本经 pdftotext 验证完整还原（此前 helvetica 兜底显示乱码）。
  文案更新后重建字体：`python3 scripts/build-receipt-font.py`
- **useDonation 旧版 ETH 转账**：当前 `useDonation()` 仍保留 ETH 直接转账到占位地址（`0x000…AeTh`，v3.6 已移除该分支的链特定引用）。真实部署后应：
  1. 将 `TREASURY_ADDRESSES.bsc` 替换为真实 Safe 多签地址，或改为读取 `useDonationTreasury()` 返回值
  2. USDC/USDT 分支目前为模拟交易，需接入真实 ERC20 `transfer(treasury, amount)`（建议另建 `useErc20Transfer` hook）
- **wagmi struct 返回值类型**：`useRingInfo.getRingInfo` / `useDonation.getDonation` 等返回 struct 的函数，wagmi 推断为命名对象而非数组，已用 `as unknown as readonly unknown[]` 二次转换绕过；升级 wagmi 版本后需复核此 cast 是否仍必要。

---

## 五、合约优化与安全审计

### 5.1 合约体积监控

| 合约 | 当前体积 | 占 24KB | 状态 |
|---|---|---|---|
| AetherRing | 13,947 B | 56.8% | ✅ 安全 |
| AetherDonation | 10,135 B | 41.2% | ✅ 安全 |
| AetherElection | 10,141 B | 41.3% | ✅ 安全 |
| AetherGovernance | 19,221 B | 78.2% | ⚠️ 接近上限 |

**AetherGovernance 注意事项**：
- 若后续新增功能导致超过 24KB，需抽取 `AetherGovernanceLib` library
- 建议在 Phase 6 前不再向 Governance 添加大功能

### 5.2 已知潜在问题（需测试验证）

1. **弹劾计票逻辑**（`AetherGovernance.finalizeImpeachment`）：✅ 已修复 (v3.1)：使用 citizenFor + 30%/70%

2. **公民 quorum 分母**（`AetherGovernance.finalizeProposal`）：
   - `citizenTotalSnapshot` 在 `startPublicVote` 时快照 `getActiveCitizens()`
   - 若公投期间有公民休眠或放弃，分母不变（合理）
   - 若公投期间有新公民加入（捐款），不参与本次公投（合理）

3. **选举平票处理**：
   - 当前：平票按注册时间先后（早者排前）
   - 边界：完全相同时间戳注册（同区块）按 candidates 数组顺序
   - 可接受，但需测试覆盖

### 5.3 安全审计建议

部署到主网前建议进行：
1. **外部审计**：委托专业审计公司（如 Trail of Bits / OpenZeppelin）
2. ** invariant 测试**：使用 Foundry invariant 测试覆盖状态机所有路径
3. **slither 静态分析**：`slither .` 检查常见漏洞
4. **重入检查**：所有外部调用（`ring.mintRing` / `ring.updateTier` / `ring.revokeRing`）均在状态变更之后
5. **权限矩阵测试**：验证每个函数的角色检查完整

---

## 六、部署后运维

### 6.1 角色转移

部署后需将管理员角色从 deployer 转移到 Safe 多签：

```solidity
// 1. ring DEFAULT_ADMIN_ROLE → Safe
ring.grantRole(ring.DEFAULT_ADMIN_ROLE(), <SAFE>);
ring.renounceRole(ring.DEFAULT_ADMIN_ROLE(), deployer);

// 2. donation ADMIN_ROLE → Safe
donation.grantRole(donation.ADMIN_ROLE(), <SAFE>);
donation.renounceRole(donation.ADMIN_ROLE(), deployer);

// 3. gov ADMIN_ROLE → Safe
gov.grantRole(gov.DEFAULT_ADMIN_ROLE(), <SAFE>);
gov.renounceRole(gov.DEFAULT_ADMIN_ROLE(), deployer);

// 4. election ADMIN_ROLE → Safe
election.grantRole(election.DEFAULT_ADMIN_ROLE(), <SAFE>);
election.renounceRole(election.DEFAULT_ADMIN_ROLE(), deployer);
```

### 6.2 监控

建议部署后监控：
- 提案状态变化事件（`ProposalCreated` / `ProposalFinalized` / `ProposalExecuted`）
- 弹劾事件（`ImpeachmentSigned` / `ImpeachmentFinalized`）
- 大额捐款（`DonationMinted` amount ≥ $1000）
- 任命元老事件（`ElderAppointed`）
- 公民休眠事件（`CitizenDormant`）

### 6.3 升级策略

v3 合约不可升级（无 proxy）。若需修复严重 bug：
1. 部署新版本合约
2. 通过治理提案迁移状态
3. 更新前端 config 指向新合约
4. 旧合约 `revokeRole` 所有权限

---

## 七、Phase 6 前端对接清单

### 7.1 已完成（Phase 3-5）

- ✅ 4 个 ABI 文件生成（`src/lib/contracts/*.abi.ts`）
- ✅ `index.ts` 枚举对齐 v3（14 tier + 12 status + 新 ElectionType + CouncilTargetTier + TreasuryUrgency）
- ✅ `config.ts` 含 AetherDonation 地址与环境变量读取
- ✅ 4 合约地址辅助函数（ringAddress / governanceAddress / electionAddress / donationAddress）

### 7.2 已完成（Phase 6）

- [x] 5 个 hooks 更新/新建（见 4.1）
- [x] `tsc --noEmit` 0 错误（修复 useDonation.ts / useRingInfo.ts 的 struct 返回值类型转换）
- [x] `npm run build` 成功（v3.6 沙箱已验证：`eslint .` 0 问题 / `tsc` 0 错误 / 生产构建通过）
- [ ] UI 组件适配新枚举（tier 标签、proposal 状态流转图、election 阶段指示器）
- [ ] 钱包连接与交易签名流程测试

### 7.3 Phase 6 新增 hooks 速览

**useDonation.ts 导出清单**（v3.3 纯链上捐款版，与合约逐项核对）：

| Hook | 类型 | 对应合约函数 |
|---|---|---|
| `useDonationInfo(tokenId)` | 读 | `getDonation`（5 字段 struct：donor/amount/timestamp/sponsorCount/fastTrackActivated）|
| `useDonationsByDonor(donor)` | 读 | `getDonationsByDonor` |
| `useTotalDonations()` | 读 | `getTotalDonations` |
| `useSponsorCount(tokenId)` | 读 | `getSponsorCount` |
| `useIsFastTrackActivated(tokenId)` | 读 | `isFastTrackActivated` |
| `useHasSponsored(tokenId, sponsor)` | 读 | `hasSponsoredDonation` |
| `useCanReacquireCitizenship(user)` | 读 | `canReacquireCitizenship`（代理 ring）|
| `useDonationTreasury()` | 读 | `treasury` |
| `useDonorStatus(donor)` | 读（批量）| 3 合约调用合并 |
| `useRingInfo(holder)` | 读（内部）| ring 3 字段合并查询 |
| `useDonation()` | 写（旧版）| ETH 转账（DonationModal 兼容，待真实环境替换）|
| `useDonationWrite()` | 写 | donateAndMint / sponsorDonation / setTreasury / setRingContract / setUsdcToken |

> **v3.3 清理**：`useNextDonationTokenId` / `useUnsettledDonations` /
> `useUsedPaypalTxId` / `usePaypalAccountWallet` 已随 PayPal 方案删除，
> `useDonationWrite` 中的 `mintDonation` / `settleDonation` /
> `grantMinterRole` / `revokeMinterRole` 同步移除。

---

## 总结

| 类别 | 数量 | 优先级 |
|---|---|---|
| 测试执行 | ✅ 已完成（93/93 通过，v3.6） | 🟢 低 |
| 合约部署 | 4 项（Anvil/BSC测试网/Mainnet/Safe） | 🔴 高 |
| 外部服务 | 2 项（IPFS/USDC 核对；PayPal 已移除） | 🟡 中 |
| 前端 hooks | 5 个（Phase 6 — ✅ 已完成） | 🟢 低 |
| 前端 UI 适配 | 3 项（tier 标签/状态流转图/选举指示器） | 🟡 中 |
| 安全审计 | 3 项（审计/invariant/slither） | 🟡 中 |
| 已知 bug | 0 项 | ✅ v3.1 已全部修复 |
| 运维 | 3 项（角色转移/监控/升级） | 🟢 低 |

**最高优先级**：
1. ✅ 已完成 (v3.1)
2. ✅ `forge test` 全部 93 个测试通过（v3.6 沙箱代理环境，Foundry 1.8.1）
3. 创建 Safe 多签并完成 BSC 测试网部署
4. UI 组件适配 v3 枚举（`npm run build` 已在沙箱验证通过）

---

**文档结束**
