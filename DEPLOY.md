# Aether DAO 部署文档

> 三院分权治理 + Safe v1.4 多签 + 选举 + 弹劾
> 目标链：BNB Smart Chain (56) 主网 / BSC 测试网 (97) / 本地 Anvil (31337)
> （Arbitrum 为早期测试链，从未部署主网，v3.6 起支持已完全移除）

---

## 0. 部署前置清单

| # | 项 | 获取方式 |
|---|---|---|
| 1 | Foundry (`forge`, `cast`, `anvil`) | https://book.getfoundry.sh/getting-started/installation |
| 2 | Node.js 20+ + pnpm 9+ | https://nodejs.org / `npm i -g pnpm` |
| 3 | Deployer 私钥 | `cast wallet new`（推荐硬件钱包） |
| 4 | Deployer BNB 余额 | BSC 主网 ≥ 0.05 BNB |
| 5 | BSC RPC URL | 官方 `https://bsc-dataseed.binance.org` 或 NodeReal / Ankr / QuickNode 申请 |
| 6 | BscScan API Key | https://bscscan.com/myapikey |
| 7 | 5 个多签持有人地址 | 5 个独立硬件钱包 / 钱包 |
| 8 | WalletConnect Project ID | https://cloud.walletconnect.com |
| 9 | Pinata API Key + Secret | https://app.pinata.cloud |

环境变量模板（写入 `.env`，**永不入仓**）：

```bash
# .env（已在 .gitignore 中）
PRIVATE_KEY=0x...                                  # 部署私钥
BSC_RPC_URL=https://bsc-dataseed.binance.org
BSC_TESTNET_RPC_URL=https://data-seed-prebsc-1-s1.binance.org:8545
BSCSCAN_API_KEY=...
SAFE_OWNERS=0xAddr1,0xAddr2,0xAddr3,0xAddr4,0xAddr5
SAFE_THRESHOLD=3
```

---

## 1. 编译验证（本地无 Foundry 也能跑）

仓库自带 `scripts/verify-contracts.js`，用 solc-js 0.8.26 离线编译验证：

```bash
# 安装 solc-js + OpenZeppelin Contracts v5
mkdir -p /tmp/solc-verify && cd /tmp/solc-verify
npm init -y
npm i solc@0.8.26 @openzeppelin/contracts@5.0.2

# 回到项目跑验证
cd /workspace
node scripts/verify-contracts.js
```

预期输出：

```
[AetherRing]      compiled OK, 9931 bytes (40.4% of 24KB limit)
[AetherGovernance] compiled OK, 14538 bytes (59.2% of 24KB limit)
[AetherElection]  compiled OK, 6590 bytes (26.8% of 24KB limit)
```

如有 Foundry：`forge build` 即可。

---

## 2. 部署 Safe v1.4 多签（治理核心）

**Safe 必须先于合约部署**，因为 `setSafeWallet` 在合约初始化后才能调用，但治理流程强依赖 Safe。

### 方式 A（推荐）：用 Safe 官方 UI

1. 打开 https://app.safe.global → "Create Account"
2. 选 **BNB Smart Chain** 网络
3. 添加 5 个 Owner 地址，Threshold = 3
4. 部署（需要 Deployer 支付 gas，约 $2-5）
5. 记录 Safe 地址：`0x...`（这就是 `SAFE_WALLET_ADDRESS`）

### 方式 B：用 Safe SDK 脚本

```bash
# scripts/deploy-safe.js（可选，需要 @safe-global/protocol-kit）
# 略；推荐用 UI
```

### 验证 Safe

```bash
# 调用 ISafe.getOwners() 应返回 5 个地址
cast call <SAFE_ADDR> "getOwners()(address[])" --rpc-url $BSC_RPC_URL
# 调用 ISafe.getThreshold() 应返回 3
cast call <SAFE_ADDR> "getThreshold()(uint256)" --rpc-url $BSC_RPC_URL
```

Safe v1.4.1 官方支持 BNB Smart Chain 主网与测试网（单例地址与多链一致，
见 Safe 官方支持网络文档；部署后在 bscscan 复核）。

---

## 3. 部署 3 个合约

### 3.1 本地 Anvil（开发/测试）

```bash
# 终端 1：启动 Anvil
anvil --block-time 2

# 终端 2：部署
cd contracts
# 私钥从 Anvil 启动时打印的测试账户复制；生产环境从密钥管理注入，切勿硬编码
export PRIVATE_KEY=<Anvil-打印的第一个测试账户私钥>
forge script script/Deploy.s.sol:Deploy \
  --rpc-url http://127.0.0.1:8545 \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvv
```

预期输出（关键三行）：

```
AetherRing:      0x...
AetherGovernance:0x...
AetherElection:  0x...
```

### 3.2 BNB Smart Chain 测试网（chainId 97，目标链测试网）

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $BSC_TESTNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --verifier-url https://api-testnet.bscscan.com/api \
  --etherscan-api-key $BSCSCAN_API_KEY \
  -vvv
```

### 3.3 BNB Smart Chain 主网（chainId 56，v3.5 目标主网）

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $BSC_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --verifier-url https://api.bscscan.com/api \
  --etherscan-api-key $BSCSCAN_API_KEY \
  --slow \
  -vvv
```

**BSC 部署要点**：

1. 合约层零改动：代码不含任何链专属依赖（无 precompile / chainId 分支），
   直接换 RPC 部署即可。
2. 稳定币精度：`AetherDonation` 构造时按 `USDC.decimals()` 动态计算
   `MIN_DONATION_USD`。BSC 上 Binance-Peg USDC/USDT 均为 **18 decimals**
   （$10 = 10 * 10^18）；合约对任意 ≤18 decimals 的稳定币语义一致。
3. 稳定币地址（BSC 主网）：
   - Binance-Peg USDC：`0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d`
   - Binance-Peg USDT：`0x55d398326f99059fF775485246999027B3197955`
4. Safe 多签：Safe v1.4.1 官方支持 BNB Smart Chain 主网与测试网
   （单例地址与多链一致，见 Safe 官方支持网络文档；部署后在 bscscan 复核）。
5. 前端配置：`NEXT_PUBLIC_CHAIN_ID=56`，金库地址必须显式配置
   （无代码内置默认金库，未配置时捐款入口自动禁用，fail-safe）。
6. 区块确认：BSC 出块约 3 秒（无最终性插槽，建议捐款验证按 1 个区块确认 +
   后端二次校验的现有方案即可；若对接交易所级最终性需求再提高确认数）。

部署脚本 `Deploy.s.sol` 自动完成：
1. 部署 AetherRing
2. 部署 AetherGovernance（引用 ring 地址）
3. 部署 AetherElection（引用 ring 地址）
4. 交叉授权：
   - `ring.ADMIN_ROLE → governance`（IMPEACHMENT execute 调 revokeRing）
   - `ring.ADMIN_ROLE → election`（选举成功调 updateTier / renewTerm）
   - `ring.MINTER_ROLE → election`（选举铸造新道环）

---

## 4. 部署后配置

### 4.1 设置 Safe 多签地址（关键！不设置则退休/复出/弹劾多签审查无法工作）

```bash
# 在 Ring 合约上设置
cast send <RING_ADDR> "setSafeWallet(address)" <SAFE_ADDR> \
  --rpc-url $BSC_RPC_URL --private-key $PRIVATE_KEY

# 在 Governance 合约上设置（弹劾多签审查）
cast send <GOVERNANCE_ADDR> "setSafeWallet(address)" <SAFE_ADDR> \
  --rpc-url $BSC_RPC_URL --private-key $PRIVATE_KEY
```

### 4.2 铸造初始道环（创始团队）

```bash
# 假设给 0xABC 铸一个 PARLIAMENT_SPEAKER (tier=3，议会高层)
cast send <RING_ADDR> \
  "mintRing(address,uint8,string)" \
  0xABC 3 "ipfs://QmFounderCovenantHash..." \
  --rpc-url $BSC_RPC_URL --private-key $PRIVATE_KEY
```

权级对照：
| Tier | 名称 | 中文 |
|---|---|---|
| 1 | PARLIAMENT_MEMBER | 议员（基层） |
| 2 | PARLIAMENT_SENIOR | 参议员（中层） |
| 3 | PARLIAMENT_SPEAKER | 议长（高层） |
| 4 | FEDERATION_MEMBER | 委员（基层） |
| 5 | FEDERATION_SENIOR | 委员长（中层） |
| 6 | FEDERATION_MINISTER | 部长（高层） |
| 7 | SENATE_ADVISOR | 顾问（基层） |
| 8 | SENATE_FELLOW | 研究员（中层） |
| 9 | SENATE_ELDER | 元老（高层） |
| 10 | GENERAL_MEMBER | 普通会员 |

### 4.3 授予初始 PROPOSER_ROLE

```bash
# 给创始议员授提案权
cast send <GOVERNANCE_ADDR> "grantProposerRole(address)" 0xDEF \
  --rpc-url $BSC_RPC_URL --private-key $PRIVATE_KEY
```

### 4.4 验证部署

```bash
# 检查 Ring 合约状态
cast call <RING_ADDR> "getTierCount(uint8)" 3 --rpc-url $BSC_RPC_URL  # 应返回已铸的议长数
cast call <RING_ADDR> "getTotalMembers()" --rpc-url $BSC_RPC_URL       # 普通会员总数
cast call <RING_ADDR> "safeWallet()" --rpc-url $BSC_RPC_URL            # 应返回 Safe 地址

# 检查 Governance
cast call <GOVERNANCE_ADDR> "proposalCount()" --rpc-url $BSC_RPC_URL   # 应为 0
cast call <GOVERNANCE_ADDR> "safeWallet()" --rpc-url $BSC_RPC_URL      # 应返回 Safe 地址

# 检查 Election
cast call <ELECTION_ADDR> "electionCount()" --rpc-url $BSC_RPC_URL     # 应为 0
```

---

## 5. 前端配置

### 5.1 创建 `.env.local`（本地开发）

```bash
# .env.local
NEXT_PUBLIC_CHAIN_ID=56
NEXT_PUBLIC_WC_PROJECT_ID=<WalletConnect Project ID>
NEXT_PUBLIC_AETHER_RING_ADDRESS=0x...
NEXT_PUBLIC_AETHER_GOVERNANCE_ADDRESS=0x...
NEXT_PUBLIC_AETHER_ELECTION_ADDRESS=0x...
NEXT_PUBLIC_SAFE_WALLET_ADDRESS=0x...
NEXT_PUBLIC_TREASURY_ADDRESS=0x...   # BSC 上必须显式配置（无代码默认值）
NEXT_PUBLIC_IPFS_GATEWAY=https://gateway.pinata.cloud/ipfs/
```

> 多链部署可用链专属变量覆盖：`NEXT_PUBLIC_AETHER_RING_ADDRESS_97=0x...`
> BSC 主网稳定币默认 Binance-Peg USDC（18 decimals），可用
> `NEXT_PUBLIC_STABLECOIN_ADDRESS` / `_SYMBOL` / `_DECIMALS` 换成 USDT 等。

### 5.2 启动开发服务器

```bash
pnpm install
pnpm dev
# 访问 http://localhost:3000
```

### 5.3 生产构建

```bash
pnpm build
pnpm start
```

---

## 6. Vercel 部署

1. https://vercel.com → New Project → Import `eneatlnc-cell/Aether`
2. Settings → Environment Variables，把 `.env.local` 内容全部粘贴进去（Production + Preview + Development 三个环境都打勾）
3. Deploy

域名配置（可选）：
- Settings → Domains → 添加 `aether.foundation`
- DNS 提供商：CNAME → `cname.vercel-dns.com`

---

## 7. 合约验证清单（部署后逐项确认）

| # | 检查项 | 命令 / 验证 |
|---|---|---|
| ✅ | AetherRing 已部署 | `cast call <RING> "name()(string)"` → "Aether Ring" |
| ✅ | AetherRing 已设 Safe | `cast call <RING> "safeWallet()(address)"` → 非 0 |
| ✅ | AetherRing 已授权 Governance | `cast call <RING> "hasRole(bytes32,address)" <ADMIN_ROLE> <GOV>` → true |
| ✅ | AetherRing 已授权 Election | `cast call <RING> "hasRole(bytes32,address)" <ADMIN_ROLE> <ELECTION>` → true |
| ✅ | Governance 已设 Safe | `cast call <GOV> "safeWallet()(address)"` → 非 0 |
| ✅ | Governance PROPOSER_ROLE 已授 | `cast call <GOV> "hasRole(bytes32,address)" <PROPOSER_ROLE> <addr>` → true |
| ✅ | BscScan 源码已验证 | 访问合约页面应显示绿色 ✓ Source Code Submitted |
| ✅ | 前端读取合约地址 | 浏览器控制台 `process.env.NEXT_PUBLIC_AETHER_RING_ADDRESS` 应为合约地址 |
| ✅ | WalletConnect 可连接 | 点击 "Connect Wallet" 能拉起钱包 |
| ✅ | Safe 多签可签名 | 用任一 Owner 在 Safe UI 发起交易，3 个签名后执行 |

---

## 8. 关键地址收集模板（部署后填写）

```bash
# === 部署记录 ===
DEPLOY_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DEPLOYER=0x...
BSC_RPC_URL=https://bsc-dataseed.binance.org

# Safe v1.4
SAFE_WALLET_ADDRESS=0x...
SAFE_OWNERS="0xA,0xB,0xC,0xD,0xE"
SAFE_THRESHOLD=3

# 合约地址（Deploy.s.sol 输出）
AETHER_RING_ADDRESS=0x...
AETHER_GOVERNANCE_ADDRESS=0x...
AETHER_ELECTION_ADDRESS=0x...

# 捐款稳定币（BSC 默认 Binance-Peg USDC 18 decimals）
STABLECOIN_ADDRESS=0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d
TREASURY_ADDRESS=0x...

# 前端
NEXT_PUBLIC_CHAIN_ID=56
NEXT_PUBLIC_WC_PROJECT_ID=...
NEXT_PUBLIC_IPFS_GATEWAY=https://gateway.pinata.cloud/ipfs/

# Pinata
PINATA_API_KEY=...
PINATA_API_SECRET=...
```

---

## 9. 治理流程速查

### 创建普通提案（SIGNAL/PARAM/TREASURY）
- 权限：`PROPOSER_ROLE` + 三院成员（tier 1-9）
- 投票期：7 天
- Timelock：SIGNAL/PARAM 12h，TREASURY 48h
- 计票：方案 B（三院共识 ≥2 + 会员参与率 ≥30% + 反对率 <60% + 加权 >50%）

### 创建弹劾提案（IMPEACHMENT）
1. 任何活跃会员调 `createImpeachmentProposal(target, title, ipfsHash)`
   - target 必须是高层（tier 3/6/9）
   - 进入 Drafting 状态
2. 100 名活跃会员（tier==10）调 `signImpeachment(proposalId)` 联署
3. 联署满 100 → 自动进入 PendingMultisig
4. Safe 多签 3/5 调 `approveImpeachmentByMultisig(proposalId)` → 进入 Active 投票
   - 或调 `rejectImpeachmentByMultisig(proposalId)` → Canceled
5. 投票期 24h
6. 投票结束任何人调 `finalize(proposalId)`
   - 参与率 ≥50% + 反对率 ≥70% → 通过 → Queued
7. Timelock 24h 后任何人调 `execute(proposalId)`
   - 自动调 `ring.revokeRing(targetRingId)` 撤销道环

### 选举（3 种类型）
1. **MEMBER_TO_GRASSROOTS**：会员 → 基层（普选）
   - 选举人：全体活跃会员（tier==10）
   - 当选：得票前 N 名
2. **GRASSROOTS_TO_MID**：基层 → 中层（院选）
   - 选举人：对应院的基层
   - 当选：得票前 N 名
3. **REELECTION**：连任选举
   - 当选：FOR > AGAINST

所有选举由 `ADMIN_ROLE`（多签）发起，投票期 7 天，到期任何人可 `finalizeElection`。

---

## 10. 故障排查

| 现象 | 原因 | 解决 |
|---|---|---|
| `setSafeWallet` revert | 调用方无 ADMIN_ROLE | 用 deployer 调，或先 `grantRole` |
| 弹劾 `NotSafeWallet` | 非 Safe 钱包直接调 approve | 必须由 Safe `execTransaction` 调 |
| 选举 `_applyPromotion` revert | 选举合约无 ring.ADMIN_ROLE | 检查 `Deploy.s.sol` 是否完整跑完 |
| `SeatLimitExceeded` | 该 tier 席位已满 | 退还或先撤销他人 |
| `TermLimitReached` | 已连任 1 次 | 不可再 renewTerm |
| 前端读不到合约地址 | 环境变量未注入 | 检查 Vercel env vars / `.env.local` |
| `cast call` 返回 0x | 合约地址错或未部署 | 用 BscScan 确认地址 |

---

## 11. 升级路径（v2 之后）

v2 合约目前**不可升级**（无 proxy）。如需升级：
1. 部署新版合约（保留旧合约状态快照）
2. 通过 PARAM 提案把前端 `NEXT_PUBLIC_*_ADDRESS` 切到新地址
3. 通过 Safe 多签把旧合约的角色迁移到新合约
4. 通过 `setRingContract` 把 Governance / Election 指向新 Ring

未来若引入 UUPS 代理，建议只对 Election 和 Governance 做，Ring 因 SBT 不可变性强依赖地址稳定。

---

部署问题 → GitHub Issues: https://github.com/eneatlnc-cell/Aether/issues
