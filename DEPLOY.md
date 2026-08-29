# Aether DAO 部署文档

> 三院分权治理 + Safe v1.4 多签 + 选举 + 弹劾 + 纯链上 USDC 捐款
> 目标链：BNB Smart Chain (56) 主网 / BSC 测试网 (97) / 本地 Anvil (31337)
> （Arbitrum 为早期测试链，从未部署主网，v3.6 起支持已完全移除）
>
> **版本**: v3.6（与合约/脚本代码逐项核对，本版重写修正了 v2 残留：
> 部署命令补齐必需变量、14 级权级表、加权计票、弹劾/选举真实流程、
> AetherDonation 合约与 Genesis 流程）

---

## 0. 部署前置清单

| # | 项 | 获取方式 |
|---|---|---|
| 1 | Foundry (`forge`, `cast`, `anvil`) | https://book.getfoundry.sh/getting-started/installation |
| 2 | Node.js 20+ + npm 10+ | https://nodejs.org（npm 随 Node 附带） |
| 3 | Deployer 私钥 | `cast wallet new`（推荐硬件钱包） |
| 4 | Deployer BNB 余额 | BSC 主网 ≥ 0.05 BNB |
| 5 | BSC RPC URL | 官方 `https://bsc-dataseed.binance.org` 或 NodeReal / Ankr / QuickNode 申请 |
| 6 | BscScan API Key | https://bscscan.com/myapikey |
| 7 | 5 个多签持有人地址 | 5 个独立硬件钱包 / 钱包 |
| 8 | WalletConnect Project ID | https://cloud.reown.com（原 cloud.walletconnect.com） |
| 9 | Pinata API Key + Secret | https://app.pinata.cloud |
| 10 | 国库地址（TREASURY） | 见 §2 —— USDC 捐款接收方 |
| 11 | 稳定币地址（USDC） | 见 §3.4 —— `donateAndMint` 链上转账用 |

环境变量模板（写入 `.env`，**永不入仓**）：

```bash
# .env（已在 .gitignore 中）
PRIVATE_KEY=0x...                                  # 部署私钥
TREASURY=0x...                                     # Safe 多签国库地址（必需，缺失即 revert）
SAFE=0x...                                         # Safe 多签钱包地址（必需）
USDC=0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d   # BSC 主网 Binance-Peg USDC（必需）
BSC_RPC_URL=https://bsc-dataseed.binance.org
BSC_TESTNET_RPC_URL=https://data-seed-prebsc-1-s1.binance.org:8545
BSCSCAN_API_KEY=...
SAFE_OWNERS=0xAddr1,0xAddr2,0xAddr3,0xAddr4,0xAddr5
SAFE_THRESHOLD=3
```

> **M12/H5 校验**：`Deploy.s.sol` 对 `TREASURY` / `SAFE` / `USDC` 三个必需变量
> 做零地址检查，**缺失任一即 revert `MissingEnv(...)`**，不会出现部分部署。

---

## 1. 编译验证（本地无 Foundry 也能跑）

仓库自带 `scripts/verify-contracts.js`，用 solc-js 0.8.26 离线编译验证：

```bash
# 安装 solc-js + OpenZeppelin Contracts v5
mkdir -p /tmp/solc-verify && cd /tmp/solc-verify
npm init -y
npm i solc@0.8.26 @openzeppelin/contracts@5.0.2

# 回到项目跑验证
cd <仓库根目录>
node scripts/verify-contracts.js
```

预期输出：

```
[AetherRing]      compiled OK, ...
[AetherGovernance] compiled OK, ...
[AetherElection]  compiled OK, ...
```

如有 Foundry：`forge build` 即可。

---

## 2. 部署 Safe v1.4 多签（治理核心）

**Safe 必须先于合约部署**：`Deploy.s.sol` 第 6 步会把 `DEFAULT_ADMIN_ROLE`
授予 Safe（H8），且 `ring.setSafeWallet` 要求目标地址上有合约代码。

### 方式 A（推荐）：用 Safe 官方 UI

1. 打开 https://app.safe.global → "Create Account"
2. 选 **BNB Smart Chain** 网络
3. 添加 5 个 Owner 地址，Threshold = 3
4. 部署（需要 Deployer 支付 gas，约 $2-5）
5. 记录 Safe 地址：`0x...`（这就是 `SAFE`；若同一地址兼作国库，也是 `TREASURY`）

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

> Safe 地址即 `SAFE` 环境变量。国库 `TREASURY` 可以与 Safe 同址（推荐，
> 捐款直接进多签），也可以是 Safe 管理下的独立地址 —— 但**不能是 deployer EOA**
> （H5 修复点：脚本不再用 deployer 兜底）。

---

## 3. 部署 4 个合约

部署脚本 `script/Deploy.s.sol` 自动完成：

1. 部署 **AetherRing**（SBT 身份内核，自带 admin/minter 角色）
2. 部署 **AetherGovernance**（引用 ring 地址）
3. 部署 **AetherElection**（引用 ring 地址）
4. 部署 **AetherDonation**（引用 ring + treasury + USDC + deployer 为初始 admin）
5. 交叉授权（6 项）：
   - `ring.ADMIN_ROLE → governance`（IMPEACHMENT execute 调 revokeRing）
   - `ring.ADMIN_ROLE → election`（选举成功调 updateTier）
   - `ring.MINTER_ROLE → election`（铸造新道环）
   - `ring.MINTER_ROLE → donation`（铸公民道环 + 重新激活休眠公民）
   - `ring.GOVERNANCE_ROLE → governance`（markVoteActivity）
   - `ring.ELECTION_ROLE → election`（markVoteActivity）
6. Safe 配置：
   - `ring.setSafeWallet(SAFE)`（必须在 Genesis 的 appointElder 之前）
   - 4 合约 `DEFAULT_ADMIN_ROLE → Safe`（H8；deployer 暂保留用于 Genesis）
   - `donation.ADMIN_ROLE → Safe`（M9：setTreasury / setRingContract / setUsdcToken 归 Safe 管）

> v3.3 起 `donateAndMint` 为 public，**无需** grantMinterRole；
> PayPal webhook 方案已整体移除，**不存在** `PAYPAL_SERVER` 变量。

### 3.1 本地 Anvil（开发/测试）

```bash
# 终端 1：启动 Anvil
anvil --block-time 2

# 终端 2：部署（TREASURY/SAFE/USDC 三个变量缺一不可）
cd contracts
# 私钥从 Anvil 启动时打印的测试账户复制；生产环境从密钥管理注入，切勿硬编码
PRIVATE_KEY=<Anvil-打印的第一个测试账户私钥> \
TREASURY=<任一测试地址> \
SAFE=<任一测试地址(需有代码，可用 anvil 部署的最简合约)> \
USDC=<部署一个 mock ERC20，或 0x0 占位仅当本地测试> \
forge script script/Deploy.s.sol:Deploy \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  -vvv
```

预期输出（关键四行 + 角色清单）：

```
AetherRing:      0x...
AetherGovernance:0x...
AetherElection:  0x...
AetherDonation:  0x...
```

> 注意：本地 Anvil 若用 0x0 占位 USDC，`donateAndMint` 不可用，仅验证部署链路。

### 3.2 BSC 测试网（chainId 97）

```bash
PRIVATE_KEY=0x... \
TREASURY=0x... SAFE=0x... USDC=<BSC测试网USDC地址> \
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $BSC_TESTNET_RPC_URL \
  --broadcast \
  --verify \
  --verifier-url https://api-testnet.bscscan.com/api \
  --etherscan-api-key $BSCSCAN_API_KEY \
  -vvv
```

### 3.3 BNB Smart Chain 主网（chainId 56）

```bash
PRIVATE_KEY=0x... \
TREASURY=0x... SAFE=0x... USDC=0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d \
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $BSC_RPC_URL \
  --broadcast \
  --verify \
  --verifier-url https://api.bscscan.com/api \
  --etherscan-api-key $BSCSCAN_API_KEY \
  --slow \
  -vvv
```

### 3.4 BSC 部署要点

1. 合约层零改动：代码不含任何链专属依赖（无 precompile / chainId 分支），
   直接换 RPC 部署即可。
2. 稳定币精度：`AetherDonation` 构造时按 `USDC.decimals()` 动态计算
   `MIN_DONATION_USD`。BSC 上 Binance-Peg USDC/USDT 均为 **18 decimals**
   （$10 = 10 * 10^18）；合约对任意 ≤18 decimals 的稳定币语义一致。
3. 稳定币地址（**BSC 主网**，勿配 Arbitrum 地址）：
   - Binance-Peg USDC：`0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d`
   - Binance-Peg USDT：`0x55d398326f99059fF775485246999027B3197955`
   - BSC 测试网无官方 Binance-Peg 稳定币，需自行部署 mock 或用测试网
     USDT 合约，部署时经 `USDC` 变量传入。
4. Safe 多签：Safe v1.4.1 官方支持 BNB Smart Chain 主网与测试网。
5. 前端配置：`NEXT_PUBLIC_CHAIN_ID=56`，金库地址必须显式配置
   （无代码内置默认金库，未配置时捐款入口自动禁用，fail-safe）。
6. 区块确认：BSC 出块约 3 秒（无最终性插槽，建议捐款验证按 1 个区块确认 +
   后端二次校验的现有方案即可；若对接交易所级最终性需求再提高确认数）。

---

## 4. Genesis：铸造初始道环（创始团队）

v3.6 创始成员不再手工 `cast send mintRing`，而是用 `script/Genesis.s.sol`
一次性完成（幂等设计，重复跑会跳过已铸地址）：

```bash
cd contracts
PRIVATE_KEY=0x... \
RING=<AetherRing地址> \
GOV=<AetherGovernance地址> \
ELECTION=<AetherElection地址> \
DONATION=<AetherDonation地址> \
SAFE=<Safe地址> \
PAR_SPEAKER_1=0x... PAR_SPEAKER_2=0x... \
FED_MINISTER_1=0x... FED_MINISTER_2=0x... \
TRIB_CHIEF_1=0x... TRIB_CHIEF_2=0x... \
COUNCIL_1=0x... COUNCIL_2=0x... \
COUNCIL_SENIOR_1=0x... COUNCIL_SENIOR_2=0x... \
COUNCIL_CHAIR=0x... \
ELDER_1=0x... ELDER_2=0x... ELDER_3=0x... ELDER_4=0x... ELDER_5=0x... \
CITIZEN_1=0x... CITIZEN_2=0x... ... CITIZEN_10=0x... \
forge script script/Genesis.s.sol:Genesis \
  --rpc-url $BSC_RPC_URL \
  --broadcast \
  -vvv
```

Genesis 做的事（全部可选，变量未设则跳过）：

| 步骤 | 内容 | 数量 |
|---|---|---|
| 1 | 铸三院高层（tier 3 议长 / tier 6 执政 / tier 9 首席） | 各 2 人 |
| 2 | 铸理事会（tier 10 理事 / tier 11 常务 / tier 12 理事长） | 2/2/1 |
| 3 | 铸初始公民（tier 14，quorum 分母需要） | 至多 10 人 |
| 4 | 任命元老（实际调 `appointElder`，C3 修复） | 至多 5 人 |
| 5 | 授理事长 `election.COUNCIL_CHAIR_ROLE` | 1 人 |
| 6 | 授三院成员 `PROPOSER_ROLE`（H7：理事长不授，`createProposal` 限 tier 1-9） | 6 人 |

### 4.1 Genesis 后手动收尾（关键！不做则 deployer 保留 admin）

```bash
# deployer 在 4 个合约上逐个 renounce（deployer 自己发起交易）
cast send <RING_ADDR> "renounceRole(bytes32,address)" <ADMIN_ROLE_HASH> <DEPLOYER> \
  --rpc-url $BSC_RPC_URL --private-key $PRIVATE_KEY
# ADMIN_ROLE_HASH = keccak256("DEFAULT_ADMIN_ROLE")，用 cast keccak 生成
# 对 GOV / ELECTION / DONATION 重复上述调用
```

验证 Safe 已接管：

```bash
cast call <RING_ADDR> "hasRole(bytes32,address)" <DEFAULT_ADMIN_ROLE_HASH> <SAFE_ADDR> \
  --rpc-url $BSC_RPC_URL   # → true
cast call <RING_ADDR> "hasRole(bytes32,address)" <DEFAULT_ADMIN_ROLE_HASH> <DEPLOYER> \
  --rpc-url $BSC_RPC_URL   # → false
```

### 4.2 权级对照（v3：14 级）

| Tier | 名称 | 中文 | 院 | 席位上限 | 任期 | 投票权重 |
|---|---|---|---|---|---|---|
| 1 | PARLIAMENT_MEMBER | 议员 | 议会基层 | 60 | 1 年 | 1 |
| 2 | PARLIAMENT_SENIOR | 参议员 | 议会中层 | 12 | 2 年 | 3 |
| 3 | PARLIAMENT_SPEAKER | 议长 | 议会高层 | 2 | 终生 | 10 |
| 4 | FEDERATION_MEMBER | 委员 | 联邦基层 | 60 | 1 年 | 1 |
| 5 | FEDERATION_SENIOR | 委员长 | 联邦中层 | 12 | 2 年 | 3 |
| 6 | FEDERATION_MINISTER | 执政 | 联邦高层 | 2 | 终生 | 10 |
| 7 | TRIBUNAL_JUDGE | 法官 | 法庭基层 | 60 | 1 年 | 1 |
| 8 | TRIBUNAL_SENIOR | 大法官 | 法庭中层 | 12 | 2 年 | 3 |
| 9 | TRIBUNAL_CHIEF | 首席 | 法庭高层 | 2 | 终生 | 10 |
| 10 | COUNCIL_MEMBER | 理事 | 理事会 | 12 | 1 年 | 0 |
| 11 | COUNCIL_SENIOR | 常务理事 | 理事会 | 4 | 1 年 | 0 |
| 12 | COUNCIL_CHAIR | 理事长 | 理事会 | 2 | 4 年 | 0 |
| 13 | ELDER | 元老 | 独立机构 | 9（任命）/退休无上限 | 终生 | 0 |
| 14 | CITIZEN | 公民 | 基金会 | 无上限 | 无任期（2 年不活动休眠） | 1 |

> v2 的 10 级表（SENATE_ADVISOR / SENATE_FELLOW / SENATE_ELDER /
> GENERAL_MEMBER）已废弃，全部链上以本表 14 级为准
> （`AetherRing.sol:30-46`）。

### 4.3 验证部署

```bash
# 检查 Ring 合约状态
cast call <RING_ADDR> "getTierCount(uint8)" 3 --rpc-url $BSC_RPC_URL  # 已铸议长数
cast call <RING_ADDR> "getActiveCitizens()" --rpc-url $BSC_RPC_URL    # 活跃公民数(v3:替代 getTotalMembers)
cast call <RING_ADDR> "safeWallet()(address)" --rpc-url $BSC_RPC_URL  # 应返回 Safe 地址

# 检查 Governance
cast call <GOV_ADDR> "proposalCount()" --rpc-url $BSC_RPC_URL   # 应为 0
# 检查 Election
cast call <ELECTION_ADDR> "electionCount()" --rpc-url $BSC_RPC_URL  # 应为 0
# 检查 Donation
cast call <DONATION_ADDR> "treasury()(address)" --rpc-url $BSC_RPC_URL  # 应返回 TREASURY
cast call <DONATION_ADDR> "usdcToken()(address)" --rpc-url $BSC_RPC_URL # 应返回 USDC
cast call <DONATION_ADDR> "minDonationUsd()(uint256)" --rpc-url $BSC_RPC_URL # 18 decimals 链上为 10e18
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
NEXT_PUBLIC_AETHER_DONATION_ADDRESS=0x...   # AetherDonation（donateAndMint 入口）
NEXT_PUBLIC_SAFE_WALLET_ADDRESS=0x...
NEXT_PUBLIC_TREASURY_ADDRESS=0x...          # BSC 上必须显式配置（无代码默认值）
NEXT_PUBLIC_IPFS_GATEWAY=https://gateway.pinata.cloud/ipfs/
```

> 多链部署可用链专属变量覆盖：`NEXT_PUBLIC_AETHER_RING_ADDRESS_97=0x...`
> BSC 主网稳定币默认 Binance-Peg USDC（18 decimals），可用
> `NEXT_PUBLIC_STABLECOIN_ADDRESS` / `_SYMBOL` / `_DECIMALS` 换成 USDT 等。
> **换币务必同时配 `_DECIMALS`**（覆盖已知地址而漏配精度会静默差 12 个数量级）。

### 5.2 启动开发服务器

```bash
npm install
npm run dev
# 访问 http://localhost:3000
```

### 5.3 生产构建

```bash
npm run build
npm run start
```

---

## 6. Vercel 部署

1. https://vercel.com → New Project → Import `eneatlnc-cell/Aether`
2. Settings → Environment Variables，把 `.env.local` 内容全部粘贴进去（Production + Preview + Development 三个环境都打勾）
3. 若使用捐款记录 API（`/api/donations/record`）与公民页 API（`/api/citizens/[address]`），
   还需创建 Vercel Postgres（Storage → Postgres），`DATABASE_URL` 由平台自动注入
4. Deploy

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
| ✅ | AetherDonation 已授权 MINTER | `cast call <RING> "hasRole(bytes32,address)" <MINTER_ROLE> <DONATION>` → true |
| ✅ | Governance 已部署 | `cast call <GOV> "proposalCount()"` → 0 |
| ✅ | Election 已部署 | `cast call <ELECTION> "electionCount()"` → 0 |
| ✅ | Donation treasury 正确 | `cast call <DONATION> "treasury()(address)"` → TREASURY |
| ✅ | Donation USDC 正确 | `cast call <DONATION> "usdcToken()(address)"` → USDC |
| ✅ | Genesis 后 deployer 已 renounce | `hasRole(DEFAULT_ADMIN_ROLE, deployer)` → 4 个合约全 false |
| ✅ | Safe 持有全部 admin | `hasRole(DEFAULT_ADMIN_ROLE, SAFE)` → 4 个合约全 true |
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

# 合约地址（Deploy.s.sol 输出，共 4 个）
AETHER_RING_ADDRESS=0x...
AETHER_GOVERNANCE_ADDRESS=0x...
AETHER_ELECTION_ADDRESS=0x...
AETHER_DONATION_ADDRESS=0x...

# 捐款稳定币（BSC 主网 Binance-Peg USDC 18 decimals；勿用 Arbitrum 地址）
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

## 9. 治理流程速查（v3 真实参数）

### 9.1 七阶段提案流（普通提案 SIGNAL / PARAM / TREASURY）

| 阶段 | 时长 | 参与方 |
|---|---|---|
| 一审（FirstVote） | 5 天 | 对应院成员 |
| 公投（PublicVote） | 7 天 | 全体公民 |
| 合规审查（Compliance） | 3 天 | 法庭成员 |
| 否决窗（Veto） | 72 小时 | 元老（3 联署） |
| Timelock（普通） | 48 小时 | — |
| Timelock（紧急） | 12 小时 | 需 3 位元老批准 |

### 9.2 加权计票（v3：三院/公民 50/50 制衡）

```
每院权重 1666 BPS（三院合计 4998）+ 公民 5000 BPS
通过门槛：合计 > 5000 BPS（严格大于）
公民 quorum：普通提案 ≥20%，章程修订 ≥50%
```

设计意图（`AetherGovernance.sol:162-165`）：三院全 FOR 只有 4998，通过
不了；公民 100% FOR 恰好 5000，也不通过（不大于）—— 任何提案都**必须**
跨院 + 公民合作。v2 的"方案 B（三院共识 ≥2 + 反对率 <60%）"已废弃。

### 9.3 提案权限

- `createProposal`：需 `PROPOSER_ROLE` **且**是三院成员（tier 1-9，
  `onlyChamberMember` 修饰器；理事长 tier 12 即使有角色也 revert）
- PARAM 提案仅白名单 3 个 selector（setVotingPeriods / setTimelocks /
  setInternalWeight），经 `address(this).call` 自执行

### 9.4 弹劾（IMPEACHMENT，v4 重写）

1. **仅任命元老**可发起 `createImpeachmentProposal(target, title, ipfsHash)`
   - target 可为 tier 1-13，**不可弹劾公民（tier 14）**
2. 3 名任命元老联署 `signImpeachment(proposalId)`（含发起人）
3. 联署满 3 → **直接进入公投**（无法庭审查、无元老否决、无 Safe 审批环节）
4. 公投 7 天（`publicVotePeriod`）
5. 投票结束任何人调 `finalizeImpeachment(proposalId)`：
   - **通过 = 公民参与率 ≥30% 且 支持率 ≥70%**（FOR = 支持弹劾）
6. 通过后**立即执行**（弹劾跳过 Timelock 和否决窗）：
   - `ring.revokeRing(targetRingId)` 撤销道环
   - 同时撤销被弹劾者的 `PROPOSER_ROLE`（H-9 修复）

> v2 文档中"任何活跃会员可发起 / 100 名联署 / Safe 多签审批 / 反对率 ≥70%
> 通过"的说法**全部作废**，以本节为准。

### 9.5 选举（3 种类型，v3）

| 类型 | 路径 | 选举人 |
|---|---|---|
| MEMBER_TO_GRASSROOTS | 公民 → 三院基层 | 全体公民（普选） |
| GRASSROOTS_TO_MID | 三院基层 → 中层 | 对应院基层（院选） |
| CITIZEN_TO_COUNCIL | 公民 → 理事/常务理事 | 全体公民（普选） |

状态机：`Pending（候选人注册）→ CouncilReview（理事会整理）→
ParliamentApproval（议会审批）→ Active（投票）→ Finalized /
PartiallyFilled / Canceled`

- 候选人审核与空缺补任限 `COUNCIL_CHAIR_ROLE`
- 阶段推进限 `ELECTION_MANAGER_ROLE`
- `finalizeElection`：按票数 + 注册时间排序，`_applyPromotion` 逐个
  try/catch（失败者计入空缺，不足席位进 `PartiallyFilled`，可
  `appointToVacancy` 补任）
- v2 的 `REELECTION` 类型已删除，勿再引用

---

## 10. 故障排查

| 现象 | 原因 | 解决 |
|---|---|---|
| `MissingEnv("TREASURY"/"SAFE"/"USDC")` | 必需环境变量缺失（M12） | 在命令前补齐三个变量，见 §3 |
| `setSafeWallet` revert | 调用方无 ADMIN_ROLE 或目标无代码（H4） | 用 deployer 调；确认 Safe 已部署 |
| 选举 `_applyPromotion` revert | 选举合约无 ring.ADMIN_ROLE | 检查 `Deploy.s.sol` 是否完整跑完 |
| `SeatLimitExceeded` | 该 tier 席位已满 | 见 §4.2 席位上限表 |
| `TermLimitReached` | 不可连任（MAX_CONSECUTIVE_TERMS = 0） | 换人当选 |
| 前端读不到合约地址 | 环境变量未注入 | 检查 Vercel env vars / `.env.local` |
| 前端捐款按钮禁用 | `NEXT_PUBLIC_TREASURY_ADDRESS` 未配 | 金库地址必须显式配置（fail-safe） |
| `cast call` 返回 0x | 合约地址错或未部署 | 用 BscScan 确认地址 |
| Genesis 跳过某人 | 幂等设计 | 该地址已有同 tier 道环或已是元老 |

---

## 11. 升级路径

当前合约**不可升级**（无 proxy）。如需升级：
1. 部署新版合约（保留旧合约状态快照）
2. 通过 PARAM 提案把前端 `NEXT_PUBLIC_*_ADDRESS` 切到新地址
3. 通过 Safe 多签把旧合约的角色迁移到新合约
4. 通过 `setRingContract` 把 Governance / Election 指向新 Ring

未来若引入 UUPS 代理，建议只对 Election 和 Governance 做，Ring 因 SBT 不可变性强依赖地址稳定。

---

部署问题 → GitHub Issues: https://github.com/eneatlnc-cell/Aether/issues
