# Aether DAO v3.6 部署说明

> **版本**：v3.6（BSC 单链，Arbitrum 支持已移除；v3.3 起捐款为纯链上 USDC，PayPal 方案已删除）
> **日期**：2026-08-29
> **适用环境**：本地 Anvil / BSC 测试网（97）/ BNB Smart Chain 主网（56）
> **链变更**：Arbitrum 为早期测试链（从未部署主网），v3.6 起支持已完全移除
> **前置文档**：先阅读 [V3_AUDIT_REPORT.md](./V3_AUDIT_REPORT.md) 确认 Critical/High 问题已修复

---

## 一、环境准备

### 1.1 工具链安装

```bash
# 1. Foundry（合约编译/部署/测试）
curl -L https://foundry.paradigm.xyz | bash
foundryup

# 2. Node.js 20+（前端，npm 10+ 随 Node 附带）
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# 3. 验证
forge --version    # forge 0.2.x
node --version     # v20.x
npm --version      # 10.x
```

> 包管理器已统一为 **npm**（仓库内 `package-lock.json` + `packageManager: npm@10.9.4`；
> v3.6 清理了早期残留的 `pnpm-lock.yaml` 双锁文件，Vercel 会按 lockfile 自动识别）。

### 1.2 代码克隆与依赖

```bash
git clone <repo-url> aether-dao
cd aether-dao

# 合约依赖
cd contracts
forge install foundry-rs/forge-std --no-commit
forge install OpenZeppelin/openzeppelin-contracts --no-commit
cd ..

# 前端依赖
npm install
```

### 1.3 环境变量模板

复制 `.env.example` 为 `.env`，填入以下变量：

```bash
# ─── 部署私钥（切勿提交）───
PRIVATE_KEY=0x0000000000000000000000000000000000000000000000000000000000000000

# ─── 国库地址（Safe 多签，必填）───
TREASURY=0x0000000000000000000000000000000000000000

# ─── RPC ───
BSC_RPC_URL=https://bsc-dataseed.binance.org
BSC_TESTNET_RPC_URL=https://data-seed-prebsc-1-s1.binance.org:8545
ANVIL_RPC_URL=http://127.0.0.1:8545

# ─── BscScan API（验证合约）───
BSCSCAN_API_KEY=your_api_key

# ─── 创世成员地址（Genesis 脚本）───
PAR_SPEAKER_1=0x...
PAR_SPEAKER_2=0x...
FED_MINISTER_1=0x...
FED_MINISTER_2=0x...
TRIB_CHIEF_1=0x...
TRIB_CHIEF_2=0x...
COUNCIL_1=0x...
COUNCIL_2=0x...
COUNCIL_SENIOR_1=0x...
COUNCIL_SENIOR_2=0x...
COUNCIL_CHAIR=0x...
ELDER_1=0x...
ELDER_2=0x...
ELDER_3=0x...
ELDER_4=0x...
ELDER_5=0x...

# ─── 前端环境变量 ───
# 链专属变量后缀格式：_<CHAINID>_ADDRESS（56=BSC 主网，97=BSC 测试网）
NEXT_PUBLIC_AETHER_RING_97_ADDRESS=0x...
NEXT_PUBLIC_AETHER_GOVERNANCE_97_ADDRESS=0x...
NEXT_PUBLIC_AETHER_ELECTION_97_ADDRESS=0x...
NEXT_PUBLIC_AETHER_DONATION_97_ADDRESS=0x...
NEXT_PUBLIC_SAFE_WALLET_97_ADDRESS=0x...
NEXT_PUBLIC_IPFS_GATEWAY=https://gateway.pinata.cloud/ipfs/
```

> **v3.3 变更**：PayPal webhook 方案已整体移除（`mintDonation` /
> `settleDonation` / `grantMinterRole` 均已删除），**不存在 `PAYPAL_SERVER`
> 变量**；捐款走 `AetherDonation.donateAndMint`（public，纯链上 USDC 转账）。
> 新增必需变量 `SAFE` 与 `USDC`（`Deploy.s.sol` M12 校验，缺失即 revert）。

---

## 二、本地 Anvil 部署（开发测试）

### 2.1 启动本地链

```bash
anvil --block-time 1 &
# 默认 10 个账户，私钥 0xac09...f2ff80 是第一个
```

### 2.2 部署合约

```bash
# 私钥从 Anvil 启动时打印的测试账户复制（或从密钥管理注入）；切勿硬编码真实私钥
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
```

**预期输出**（4 个合约地址）：

```
== Return ==
ringAddress: address 0x5FbDB2315678afecb367f032d93F642f64180aa3
governanceAddress: address 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
electionAddress: address 0x9fE46736679d2D9e6512b4F48B3d8E7B1f3A1234
donationAddress: address 0xCf7Ed3AccA5a467e9e704C703E8D5F4e9fA1BcD2
```

记录这 4 个地址，后续步骤会用到。

### 2.3 运行创世脚本

```bash
RING=0x5FbDB2315678afecb367f032d93F642f64180aa3 \
GOV=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 \
ELECTION=0x9fE46736679d2D9e6512b4F48B3d8E7B1f3A1234 \
DONATION=0xCf7Ed3AccA5a467e9e704C703E8D5F4e9fA1BcD2 \
SAFE=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
PAR_SPEAKER_1=0x... \
ELDER_1=0x... \
# ... 其余地址 \
forge script contracts/script/Genesis.s.sol:Genesis \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast -vvv
```

> **⚠️ 注意**：当前 Genesis.s.sol 存在 Critical 问题（appointElder 未实际执行），部署前请先修复 [V3_AUDIT_REPORT.md](./V3_AUDIT_REPORT.md) 中的 C3 问题。

### 2.4 验证部署

```bash
# 1. 验证合约地址
cast call $RING "safeWallet()" --rpc-url http://127.0.0.1:8545
# 应返回 Safe 地址

# 2. 验证任命元老数（应为 5）
cast call $RING "appointedElderCount()" --rpc-url http://127.0.0.1:8545

# 3. 验证活跃公民数
cast call $RING "getActiveCitizens()" --rpc-url http://127.0.0.1:8545

# 4. 验证提案计数
cast call $GOV "proposalCount()" --rpc-url http://127.0.0.1:8545

# 5. 验证选举计数
cast call $ELECTION "electionCount()" --rpc-url http://127.0.0.1:8545

# 6. 验证国库地址
cast call $DONATION "treasury()" --rpc-url http://127.0.0.1:8545
```

### 2.5 运行测试

```bash
cd contracts
forge test -vvv
# 预期：89 个测试全部通过

# 覆盖率
forge coverage
# 目标 ≥ 90%
```

---

## 三、Safe 多签钱包创建

### 3.1 创建 Safe

1. 访问 https://app.safe.global/
2. 选择 **BNB Smart Chain** 网络
3. 创建新 Safe：
   - 名称：`Aether Treasury`
   - 签名者：5 个地址（建议基金会核心成员）
   - 阈值：**3/5**（3 人同意即可执行）
4. 记录 Safe 地址

### 3.2 Safe 单例地址

Safe v1.4.1 官方支持 BNB Smart Chain 主网与测试网（单例地址与多链一致，部署后在 BscScan 复核）：

```
0x41675C099F32341bf84BFc5382aF534df5C7461a
```

### 3.3 Safe 作为国库

Safe 地址将用于：

- `ring.setSafeWallet(<SAFE>)` — 任命元老权限
- `donation` 合约的 `treasury` — USDC 接收方
- 4 个合约的 `DEFAULT_ADMIN_ROLE` 持有者

---

## 四、BSC 测试网部署

### 4.1 获取测试币

从水龙头获取 BSC 测试网 tBNB：

- https://testnet.bnbchain.org/faucet-smart（BSC 测试网水龙头）

### 4.2 部署合约

```bash
PRIVATE_KEY=0x... \
TREASURY=<SAFE_ADDRESS> \
forge script contracts/script/Deploy.s.sol:Deploy \
  --rpc-url $BSC_TESTNET_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $BSCSCAN_API_KEY \
  -vvv
```

### 4.3 验证合约

部署后自动验证。手动验证：

```bash
forge verify-contract <RING_ADDR> AetherRing \
  --chain-id 97 \
  --verifier etherscan \
  --etherscan-api-key $BSCSCAN_API_KEY
```

### 4.4 运行创世脚本

同 2.3，但 RPC 改为 BSC 测试网：

```bash
RING=0x... GOV=0x... ELECTION=0x... DONATION=0x... SAFE=0x... \
# ... 地址 \
forge script contracts/script/Genesis.s.sol:Genesis \
  --rpc-url $BSC_TESTNET_RPC_URL \
  --broadcast -vvv
```

---

## 五、角色转移给 Safe

部署后，deployer 持有所有合约的 `DEFAULT_ADMIN_ROLE`。需转移给 Safe 多签：

### 5.1 授予 Safe 角色

```bash
# 1. AetherRing
cast send $RING "grantRole(bytes32,address)" \
  $(cast keccak "DEFAULT_ADMIN_ROLE") $SAFE \
  --rpc-url $RPC --private-key $PRIVATE_KEY

cast send $RING "grantRole(bytes32,address)" \
  $(cast keccak "ADMIN_ROLE") $SAFE \
  --rpc-url $RPC --private-key $PRIVATE_KEY

# 2. AetherGovernance
cast send $GOV "grantRole(bytes32,address)" \
  $(cast keccak "DEFAULT_ADMIN_ROLE") $SAFE \
  --rpc-url $RPC --private-key $PRIVATE_KEY

# 3. AetherElection
cast send $ELECTION "grantRole(bytes32,address)" \
  $(cast keccak "DEFAULT_ADMIN_ROLE") $SAFE \
  --rpc-url $RPC --private-key $PRIVATE_KEY

# 4. AetherDonation
cast send $DONATION "grantRole(bytes32,address)" \
  $(cast keccak "DEFAULT_ADMIN_ROLE") $SAFE \
  --rpc-url $RPC --private-key $PRIVATE_KEY

cast send $DONATION "grantRole(bytes32,address)" \
  $(cast keccak "ADMIN_ROLE") $SAFE \
  --rpc-url $RPC --private-key $PRIVATE_KEY
```

### 5.2 捐款合约权限（v3.3 起无需额外配置）

> v3.3 起捐款为纯链上路径：`donateAndMint` 为 **public** 函数，
> 捐款人自己发起 USDC `transferFrom` + 合约铸凭证 NFT，
> **不存在** `grantMinterRole` / PayPal 服务端授权。
> `donation.ADMIN_ROLE`（setTreasury / setRingContract / setUsdcToken）
> 已由 `Deploy.s.sol` 第 8 步授予 Safe（M9）。

### 5.3 deployer 放弃角色（可选，建议确认 Safe 工作正常后）

```bash
# 仅当 Safe 角色确认生效后执行
cast send $RING "renounceRole(bytes32,address)" \
  $(cast keccak "DEFAULT_ADMIN_ROLE") $DEPLOYER \
  --rpc-url $RPC --private-key $PRIVATE_KEY
# ... 对 4 个合约重复
```

---

## 六、BNB Smart Chain 主网部署

> **⚠️ 前置条件**：[V3_AUDIT_REPORT.md](./V3_AUDIT_REPORT.md) 中所有 Critical/High 问题已修复 + 测试网运行稳定至少 7 天 + 外部审计完成

### 6.1 部署合约

```bash
PRIVATE_KEY=0x... \
TREASURY=<SAFE地址或Safe管理的国库地址> \
SAFE=<Safe多签地址> \
USDC=0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d \
forge script contracts/script/Deploy.s.sol:Deploy \
  --rpc-url $BSC_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $BSCSCAN_API_KEY \
  --slow \
  -vvv
```

### 6.2 主网合约地址记录

部署完成后，在 `docs/CONTRACT_ADDRESSES.md` 记录：

```markdown
# BNB Smart Chain 合约地址

- AetherRing: 0x...
- AetherGovernance: 0x...
- AetherElection: 0x...
- AetherDonation: 0x...
- Safe Treasury: 0x...
- USDC (Binance-Peg, 18 decimals): 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d
```

### 6.3 角色转移

同第五节，RPC 改为主网。

---

## 七、前端部署

### 7.1 配置环境变量

在 `.env.local`（本地开发）或 Vercel 环境变量（生产）中设置：

```bash
# BNB Smart Chain (56) — 主网
NEXT_PUBLIC_AETHER_RING_56_ADDRESS=0x...
NEXT_PUBLIC_AETHER_GOVERNANCE_56_ADDRESS=0x...
NEXT_PUBLIC_AETHER_ELECTION_56_ADDRESS=0x...
NEXT_PUBLIC_AETHER_DONATION_56_ADDRESS=0x...
NEXT_PUBLIC_SAFE_WALLET_56_ADDRESS=0x...

# BSC 测试网 (97)
NEXT_PUBLIC_AETHER_RING_97_ADDRESS=0x...
NEXT_PUBLIC_AETHER_GOVERNANCE_97_ADDRESS=0x...
NEXT_PUBLIC_AETHER_ELECTION_97_ADDRESS=0x...
NEXT_PUBLIC_AETHER_DONATION_97_ADDRESS=0x...
NEXT_PUBLIC_SAFE_WALLET_97_ADDRESS=0x...

# IPFS
NEXT_PUBLIC_IPFS_GATEWAY=https://gateway.pinata.cloud/ipfs/

# WalletConnect（移动端钱包扫码；生产环境缺失会导致构建 fail-fast）
NEXT_PUBLIC_WC_PROJECT_ID=...
```

### 7.2 本地开发

```bash
npm run dev
# 访问 http://localhost:3000
```

### 7.3 生产构建

```bash
npm run build
npm run start
```

### 7.4 Vercel 部署

1. 在 Vercel 导入 GitHub 仓库
2. 配置环境变量（同 7.1）
3. Framework Preset: **Next.js**
4. Build Command: `npm run build`
5. 部署

> **WalletConnect 注意**：v3.6 起代码不再内置默认 Project ID，
> `NEXT_PUBLIC_WC_PROJECT_ID` 未配置时生产构建直接报错（与金库地址同款 fail-fast 策略）；
> 开发环境仅告警并禁用移动端扫码（桌面注入钱包不受影响）。
> 在 https://cloud.reown.com（原 cloud.walletconnect.com）申请。

---

## 八、外部服务集成

### 8.1 捐款链路（v3.3 起纯链上，无外部服务端）

> **v3.3 变更**：PayPal webhook 方案已整体移除。原 8.1 的
> "PayPal Webhook 服务端 + `mintDonation`" 流程作废，
> 以下为当前真实链路。

**流程**（单笔交易完成，无中转服务）：

1. 用户在前端 `DonationModal` 输入金额、选用途
2. 前端调 `AetherDonation.donateAndMint(purpose)`，合约内部：
   - 校验金额 ≥ `MIN_DONATION_USD`（按 `USDC.decimals()` 动态计算，$10）
   - USDC `transferFrom(donor → treasury)`（带返回值检查）
   - 铸捐款凭证 NFT 给 donor
   - 首捐者自动铸公民道环（tier 14）；休眠公民自动重激活
3. 交易确认后前端拉凭证信息，本地生成 PDF 收据（jsPDF）

**安全属性**：

- 捐款人自签自付（`transferFrom` 需 donor 的 USDC approve），无代付冒名
- 合约 CEI 顺序 + 返回值检查，无重入面
- `MIN_DONATION_USD` 构造时按 decimals 动态计算，链无关
- 后端 `/api/donations/record` 仅做**展示层**记账（链上验证后入 KV/DB），
  不参与资金流

### 8.2 IPFS 存储（Pinata）

**用途**：存储提案内容（title + 正文）

**配置**：

1. 注册 Pinata 账号：https://app.pinata.cloud/
2. 获取 API Key
3. 前端上传提案内容到 IPFS，获取 CID
4. 将 CID 作为 `ipfsHash` 传入 `createProposal`

```javascript
import pinata from "@pinata/sdk";

const pinataClient = pinata(process.env.PINATA_API_KEY, process.env.PINATA_SECRET);

async function uploadProposal(content) {
  const result = await pinataClient.pinJSONToIPFS(content);
  return result.IpfsHash; // CID
}
```

### 8.3 稳定币参考地址（BSC 主网，18 decimals）

- BNB Smart Chain（Binance-Peg USDC，18 decimals）：`0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d`
- BNB Smart Chain（Binance-Peg USDT，18 decimals）：`0x55d398326f99059fF775485246999027B3197955`
- 金额精度：全部按代币 `decimals()`（BSC 上两者均为 18），
  合约构造时动态计算门槛，前端换币时**必须**同时配置
  `NEXT_PUBLIC_STABLECOIN_DECIMALS`（漏配会静默差 12 个数量级）

> 原本节的 "PayPal 侧 USD 6 decimals / Safe 手动 settleDonation" 流程
> 已随 v3.3 移除 —— 现在捐款入账即入金库，无需结算步骤。

---

## 九、部署后验证清单

### 9.1 合约层

- [ ] `ring.safeWallet()` 返回 Safe 地址
- [ ] `ring.appointedElderCount()` 返回 5（或预期数量）
- [ ] `ring.getActiveCitizens()` 返回合理值
- [ ] `donation.treasury()` 返回 Safe 地址
- [ ] `donation.usdcToken()` 返回正确稳定币地址
- [ ] `donation.minDonationUsd()` 为 10 × 10^decimals（18 decimals 链上 1e19）
- [ ] 4 个合约的 `DEFAULT_ADMIN_ROLE` 已授予 Safe
- [ ] deployer 已 `renounceRole`（可选）

### 9.2 跨合约授权

- [ ] `ring.hasRole(ring.MINTER_ROLE(), donation)` == true
- [ ] `ring.hasRole(ring.MINTER_ROLE(), election)` == true
- [ ] `ring.hasRole(ring.ADMIN_ROLE(), governance)` == true
- [ ] `ring.hasRole(ring.ADMIN_ROLE(), election)` == true
- [ ] `ring.hasRole(ring.GOVERNANCE_ROLE(), governance)` == true
- [ ] `ring.hasRole(ring.ELECTION_ROLE(), election)` == true

### 9.3 功能测试

- [ ] 创建一个 SIGNAL 提案，走完 7 阶段流程
- [ ] 创建一个选举，走完 4 阶段流程
- [ ] 模拟捐款（测试网）铸公民道环
- [ ] 公民投票测试
- [ ] 弹劾流程测试（测试网）

### 9.4 前端

- [x] `npm run build` 成功（v3.6 沙箱已验证：lint 0 问题 / tsc 0 错误 / build 通过）
- [ ] 钱包连接正常
- [ ] 合约地址读取正确
- [ ] 提案列表显示
- [ ] 选举列表显示
- [ ] 捐款流程正常

---

## 十、故障排查

### 10.1 常见错误

| 错误 | 原因 | 解决 |
|---|---|---|
| `AccessControlUnauthorizedAccount` | 调用者无所需角色 | 检查角色授予 |
| `AlreadyHasRing` | 地址已持有道环 | 每个地址只能有一个道环 |
| `NotSafeWallet` | 非 Safe 调用 appointElder | 通过 Safe 多签执行 |
| `NonTransferable` | 尝试转让 SBT | SBT 不可转让 |
| `DuplicatePayPalTx` | PayPal TxId 已使用 | 检查交易唯一性 |
| `ElectionNotPending` | 选举状态错误 | 检查当前状态 |
| `NotChamberMember` | 非三院成员创建提案 | 仅 tier 1-9 可提案 |

### 10.2 调试命令

```bash
# 查看合约角色
cast call $RING "hasRole(bytes32,address)" $(cast keccak "ADMIN_ROLE") $ADDR --rpc-url $RPC

# 查看道环信息
cast call $RING "getRingInfo(uint256)" 1 --rpc-url $RPC

# 查看提案
cast call $GOV "getProposal(uint256)" 0 --rpc-url $RPC

# 查看选举
cast call $ELECTION "getElection(uint256)" 0 --rpc-url $RPC

# 查看捐款
cast call $DONATION "getDonation(uint256)" 1 --rpc-url $RPC
```

---

## 十一、升级策略

v3 合约**不可升级**（无 proxy）。若需修复严重 bug：

1. 部署新版本合约
2. 通过治理提案迁移状态（需旧合约 ADMIN_ROLE 配合）
3. 更新前端 `config.ts` 指向新合约
4. 旧合约 `revokeRole` 所有权限
5. 公告社区迁移

> 建议主网部署前完成全部审计，避免上线后被迫迁移。

---

## 十二、重要地址清单（BNB Smart Chain）

> ⚠️ v3.6 修正：本清单旧版误列了 Arbitrum One 的 USDC/WETH/USDT 地址，
> 已全部替换为 BSC 主网地址。

| 资源 | 地址 |
|---|---|
| Safe v1.4.1 单例（BSC）| `0x41675C099F32341bf84BFc5382aF534df5C7461a`（部署后在 bscscan 复核，以 Safe 官方支持网络文档为准）|
| Binance-Peg USDC（18 decimals）| `0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d` |
| Binance-Peg USDT（18 decimals）| `0x55d398326f99059fF775485246999027B3197955` |
| BSC 公共 RPC | `https://bsc-dataseed.binance.org`（测试网 `https://data-seed-prebsc-1-s1.binance.org:8545`）|
| BscScan | https://bscscan.com（测试网 https://testnet.bscscan.com）|

> BSC 测试网（97）无官方 Binance-Peg 稳定币，需自行部署 mock ERC20
> （18 decimals）作为 `USDC` 传入。**切勿**把 Arbitrum 地址
> （`0xaf88d…` USDC / `0x82aF…` WETH / `0xFd08…` USDT）配进任何
> BSC 环境变量 —— 那是 v3.6 已移除的早期测试链残留。

---

**部署说明结束**

> 部署遇到问题请参考 [V3_AUDIT_REPORT.md](./V3_AUDIT_REPORT.md) 和 [PENDING_ISSUES.md](./PENDING_ISSUES.md)。
