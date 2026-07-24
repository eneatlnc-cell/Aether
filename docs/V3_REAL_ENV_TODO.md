# Aether DAO v3.0 现实环境待解决问题清单

> **版本**：v3.0 Phase 1-6 完成后的遗留事项
> **日期**：2026年7月
> **说明**：以下问题需要在真实开发/部署环境（非沙箱）中处理，沙箱内已完成全部代码编写与编译验证（含 `tsc --noEmit` 0 错误）

---

## 一、测试执行（forge test）

### 1.1 安装 Foundry 工具链

**问题**：沙箱环境无法通过 `foundryup` 下载 Forge 二进制（GitHub SSL 连接不稳定）

**影响**：无法执行 `forge test` 验证测试逻辑正确性

**当前状态**：
- 全部 89 个测试函数已通过 `solc-js` 编译验证（0 errors）
- 测试文件列表：
  - `contracts/test/AetherRing.t.sol`（28 个测试）
  - `contracts/test/AetherDonation.t.sol`（15 个测试）
  - `contracts/test/AetherGovernance.t.sol`（30 个测试）
  - `contracts/test/AetherElection.t.sol`（11 个测试）
  - `contracts/test/Integration.t.sol`（5 个集成测试）

**待执行命令**：
```bash
# 1. 安装 Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# 2. 安装依赖（forge-std + openzeppelin）
cd contracts
forge install foundry-rs/forge-std --no-commit
forge install OpenZeppelin/openzeppelin-contracts --no-commit

# 3. 运行测试
forge test -vvv

# 4. 覆盖率检查（目标 ≥ 90%）
forge coverage
```

**预期**：测试可能发现少量逻辑 bug（如计票精度、时间窗口边界），需根据失败信息修复

---

## 二、合约部署

### 2.1 本地 Anvil 部署验证

**待执行命令**：
```bash
# 1. 启动本地链
anvil --block-time 1 &

# 2. 部署 4 合约
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
TREASURY=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
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
1. 在 Arbitrum 上创建 Safe v1.4.1 多签钱包（建议 3/5 阈值）
2. 将 Safe 地址配置到 `ring.setSafeWallet(<SAFE>)`
3. 通过 Safe 多签执行 5 次 `ring.appointElder(<elder>, "")`
4. 将 `donation.ADMIN_ROLE` 转移给 Safe

**参考**：https://app.safe.global/

### 2.3 Arbitrum Sepolia 测试网部署

**待执行命令**：
```bash
PRIVATE_KEY=0x... \
TREASURY=0x... \
forge script contracts/script/Deploy.s.sol:Deploy \
  --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
  --broadcast \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY
```

### 2.4 前端环境变量配置

部署完成后，在 Vercel 或 `.env.local` 中设置：
```bash
# Arbitrum Sepolia (421614)
NEXT_PUBLIC_AETHER_RING_421614_ADDRESS=0x...
NEXT_PUBLIC_AETHER_GOVERNANCE_421614_ADDRESS=0x...
NEXT_PUBLIC_AETHER_ELECTION_421614_ADDRESS=0x...
NEXT_PUBLIC_AETHER_DONATION_421614_ADDRESS=0x...
NEXT_PUBLIC_SAFE_WALLET_421614_ADDRESS=0x...

# Arbitrum One (42161) - 主网部署后
NEXT_PUBLIC_AETHER_RING_42161_ADDRESS=0x...
NEXT_PUBLIC_AETHER_GOVERNANCE_42161_ADDRESS=0x...
NEXT_PUBLIC_AETHER_ELECTION_42161_ADDRESS=0x...
NEXT_PUBLIC_AETHER_DONATION_42161_ADDRESS=0x...
NEXT_PUBLIC_SAFE_WALLET_42161_ADDRESS=0x...
```

---

## 三、外部服务集成

### 3.1 PayPal Webhook 服务端

**问题**：`AetherDonation.mintDonation` 仅允许 `MINTER_ROLE` 调用，需要 PayPal webhook 服务端验证交易后调用

**待实现**：
1. 服务端接收 PayPal webhook 事件（payment.completed）
2. 验证交易真实性（PayPal API 回查）
3. 提取：donor 地址、金额、paypalTxId、payer_id
4. 计算 `paypalAccountHash = keccak256(payer_id)`
5. 调用 `donation.mintDonation(donor, amount, paypalTxId, paypalAccountHash)`
6. 服务端持有 `donation.MINTER_ROLE`（通过 `donation.grantMinterRole(<SERVER>)`）

**安全要求**：
- 服务端私钥仅用于 mintDonation 调用，不持有资金
- webhook 验签防重放
- 金额单位：USD 6 decimals（$10 = 10000000）

### 3.2 IPFS 存储

**问题**：提案的 `ipfsHash` 需要前端上传到 IPFS 后获取

**待配置**：
- IPFS 网关：默认 `https://gateway.pinata.cloud/ipfs/`
- 上传服务：Pinata / Web3.Storage / nft.storage
- 环境变量：`NEXT_PUBLIC_IPFS_GATEWAY`

### 3.3 USDC 结算

**问题**：`settleDonation` 记录 USDC 数量，但实际 USDC 转账需 Safe 多签执行

**待实现**：
1. Safe 多签发起 USDC 转账（donor → treasury）
2. 转账确认后调用 `donation.settleDonation(tokenId, usdcAmount)`
3. USDC 合约地址：Arbitrum One `0xaf88d065e77c8cC2239327C5EDb3A432268e5831`（原生 USDC）
4. 金额精度：6 decimals

---

## 四、前端 hooks 适配（Phase 6 — 已完成）

### 4.1 hooks 更新情况

| 文件 | 状态 | 实现要点 |
|---|---|---|
| `src/hooks/useRingInfo.ts` | ✅ 完成 | 14 tier 枚举 + RingInfo 12 字段（含 isDormant/isRetiredElder/isAppointedElder/lastActivityAt）+ useActiveCitizens + useCanReacquireCitizenship |
| `src/hooks/useGovernance.ts` | ✅ 完成 | 7 阶段流程 + 12 状态 + 21 个写入方法 + 6 个读取 hooks（含信任投票 confidence vote）|
| `src/hooks/useImpeachment.ts` | ✅ 完成 | 元老发起（createImpeachmentProposal）+ 3 联署（signImpeachment）+ 30%/70%（citizenFor）计票（finalizeImpeachment）|
| `src/hooks/useElection.ts` | ✅ 完成 | 4 阶段状态机 + CITIZEN_TO_COUNCIL + appointToVacancy 空缺处理 + 8 个读取 hooks |
| `src/hooks/useDonation.ts` | ✅ 完成 | 保留旧版 ETH 转账 hook（DonationModal 兼容）+ 12 个 v3 读取 hooks + useDonationWrite 写入 hook（mint/settle/sponsor/setTreasury/setRingContract/grantMinterRole/revokeMinterRole）|

### 4.2 v2 残留引用（已清理）

以下函数/字段在 v3 已删除，已从 hooks 中清理：
- `castReelectionAgainst` → 已删除（v3 不可连任）
- `renewTerm` → 已删除
- `approveImpeachmentByMultisig` → 改为 `createImpeachmentProposal` + `signImpeachment`
- `hasSigned` (impeachment) → 改为 `hasImpeachSigned`
- `GENERAL_MEMBER` → `CITIZEN`
- `SENATE_ADVISOR/FELLOW/ELDER` → `TRIBUNAL_JUDGE/SENIOR/CHIEF`

### 4.3 已知前端待处理（真实环境）

- **useDonation 旧版 ETH 转账**：当前 `useDonation()` 仍保留 ETH 直接转账到 `TREASURY_ADDRESSES.arbitrum`（占位地址 `0x000…AeTh`）。真实部署后应：
  1. 将 `TREASURY_ADDRESSES.arbitrum` 替换为真实 Safe 多签地址，或改为读取 `useDonationTreasury()` 返回值
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
- [ ] `pnpm build` 成功（待真实环境执行，沙箱仅验证 tsc）
- [ ] UI 组件适配新枚举（tier 标签、proposal 状态流转图、election 阶段指示器）
- [ ] 钱包连接与交易签名流程测试

### 7.3 Phase 6 新增 hooks 速览

**useDonation.ts 新增导出**（v3 合约集成）：

| Hook | 类型 | 对应合约函数 |
|---|---|---|
| `useDonationInfo(tokenId)` | 读 | `getDonation`（9 字段 struct）|
| `useDonationsByDonor(donor)` | 读 | `getDonationsByDonor` |
| `useTotalDonations()` | 读 | `getTotalDonations` |
| `useNextDonationTokenId()` | 读 | `nextTokenId` |
| `useSponsorCount(tokenId)` | 读 | `getSponsorCount`（含 thresholdMet）|
| `useIsFastTrackActivated(tokenId)` | 读 | `isFastTrackActivated` |
| `useHasSponsored(tokenId, sponsor)` | 读 | `hasSponsoredDonation` |
| `useCanReacquireCitizenship(user)` | 读 | `canReacquireCitizenship`（代理 ring）|
| `useDonationTreasury()` | 读 | `treasury` |
| `useUnsettledDonations()` | 读 | `getUnsettledDonations`（审计）|
| `useUsedPaypalTxId(txId)` | 读 | `usedPaypalTxIds` |
| `usePaypalAccountWallet(hash)` | 读 | `paypalAccountToWallet` |
| `useDonorStatus(donor)` | 读（批量）| 3 合约调用合并 |
| `useDonationWrite()` | 写 | mintDonation / settleDonation / sponsorDonation / setTreasury / setRingContract / grantMinterRole / revokeMinterRole |

---

## 总结

| 类别 | 数量 | 优先级 |
|---|---|---|
| 测试执行 | 1 项（forge test） | 🔴 高 |
| 合约部署 | 4 项（Anvil/Sepolia/Mainnet/Safe） | 🔴 高 |
| 外部服务 | 3 项（PayPal/IPFS/USDC） | 🟡 中 |
| 前端 hooks | 5 个（Phase 6 — ✅ 已完成） | 🟢 低 |
| 前端 UI 适配 | 3 项（tier 标签/状态流转图/选举指示器 + pnpm build） | 🟡 中 |
| 安全审计 | 3 项（审计/invariant/slither） | 🟡 中 |
| 已知 bug | 0 项 | ✅ v3.1 已全部修复 |
| 运维 | 3 项（角色转移/监控/升级） | 🟢 低 |

**最高优先级**：
1. ✅ 已完成 (v3.1)
2. 本地执行 `forge test` 验证全部 89 个测试
3. 创建 Safe 多签并完成 Arbitrum Sepolia 部署
4. 真实环境执行 `pnpm build` + UI 组件适配 v3 枚举

---

**文档结束**
