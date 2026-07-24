# Aether DAO v3.0 部署说明

> **版本**：v3.0
> **日期**：2026-07-24
> **适用环境**：本地 Anvil / Arbitrum Sepolia 测试网 / Arbitrum One 主网
> **前置文档**：先阅读 [V3_AUDIT_REPORT.md](./V3_AUDIT_REPORT.md) 确认 Critical/High 问题已修复

---

## 一、环境准备

### 1.1 工具链安装

```bash
# 1. Foundry（合约编译/部署/测试）
curl -L https://foundry.paradigm.xyz | bash
foundryup

# 2. Node.js 20+ 与 pnpm（前端）
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
npm install -g pnpm

# 3. 验证
forge --version    # forge 0.2.x
node --version     # v20.x
pnpm --version     # 9.x
```

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
pnpm install
```

### 1.3 环境变量模板

复制 `.env.example` 为 `.env`，填入以下变量：

```bash
# ─── 部署私钥（切勿提交）───
PRIVATE_KEY=0x0000000000000000000000000000000000000000000000000000000000000000

# ─── 国库地址（Safe 多签，必填）───
TREASURY=0x0000000000000000000000000000000000000000

# ─── RPC ───
ARBITRUM_RPC_URL=https://arb1.arbitrum.io/rpc
SEPOLIA_RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
ANVIL_RPC_URL=http://127.0.0.1:8545

# ─── Arbiscan API（验证合约）───
ARBISCAN_API_KEY=your_api_key

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

# ─── PayPal webhook 服务端地址（部署后配置）───
PAYPAL_SERVER=0x...

# ─── 前端环境变量 ───
NEXT_PUBLIC_AETHER_RING_421614_ADDRESS=0x...
NEXT_PUBLIC_AETHER_GOVERNANCE_421614_ADDRESS=0x...
NEXT_PUBLIC_AETHER_ELECTION_421614_ADDRESS=0x...
NEXT_PUBLIC_AETHER_DONATION_421614_ADDRESS=0x...
NEXT_PUBLIC_SAFE_WALLET_421614_ADDRESS=0x...
NEXT_PUBLIC_IPFS_GATEWAY=https://gateway.pinata.cloud/ipfs/
```

---

## 二、本地 Anvil 部署（开发测试）

### 2.1 启动本地链

```bash
anvil --block-time 1 &
# 默认 10 个账户，私钥 0xac09...f2ff80 是第一个
```

### 2.2 部署合约

```bash
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
TREASURY=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
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
2. 选择 **Arbitrum** 网络
3. 创建新 Safe：
   - 名称：`Aether Treasury`
   - 签名者：5 个地址（建议基金会核心成员）
   - 阈值：**3/5**（3 人同意即可执行）
4. 记录 Safe 地址

### 3.2 Safe 单例地址

Arbitrum One 上 Safe v1.4.1 单例：

```
0x41675C099F32341bf84BFc5382aF534df5C7461a
```

### 3.3 Safe 作为国库

Safe 地址将用于：

- `ring.setSafeWallet(<SAFE>)` — 任命元老权限
- `donation` 合约的 `treasury` — USDC 接收方
- 4 个合约的 `DEFAULT_ADMIN_ROLE` 持有者

---

## 四、Arbitrum Sepolia 测试网部署

### 4.1 获取测试币

从水龙头获取 Sepolia ETH：

- https://faucet.quicknode.com/arbitrum/sepolia
- https://www.alchemy.com/faucets/arbitrum-sepolia

### 4.2 部署合约

```bash
PRIVATE_KEY=0x... \
TREASURY=<SAFE_ADDRESS> \
forge script contracts/script/Deploy.s.sol:Deploy \
  --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
  --broadcast \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY \
  -vvv
```

### 4.3 验证合约

部署后自动验证。手动验证：

```bash
forge verify-contract <RING_ADDR> AetherRing \
  --chain-id 421614 \
  --verifier etherscan \
  --etherscan-api-key $ARBISCAN_API_KEY
```

### 4.4 运行创世脚本

同 2.3，但 RPC 改为 Sepolia：

```bash
RING=0x... GOV=0x... ELECTION=0x... DONATION=0x... SAFE=0x... \
# ... 地址 \
forge script contracts/script/Genesis.s.sol:Genesis \
  --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
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

### 5.2 配置 PayPal MINTER_ROLE

```bash
cast send $DONATION "grantMinterRole(address)" $PAYPAL_SERVER \
  --rpc-url $RPC --private-key $PRIVATE_KEY
```

### 5.3 deployer 放弃角色（可选，建议确认 Safe 工作正常后）

```bash
# 仅当 Safe 角色确认生效后执行
cast send $RING "renounceRole(bytes32,address)" \
  $(cast keccak "DEFAULT_ADMIN_ROLE") $DEPLOYER \
  --rpc-url $RPC --private-key $PRIVATE_KEY
# ... 对 4 个合约重复
```

---

## 六、Arbitrum One 主网部署

> **⚠️ 前置条件**：[V3_AUDIT_REPORT.md](./V3_AUDIT_REPORT.md) 中所有 Critical/High 问题已修复 + 测试网运行稳定至少 7 天 + 外部审计完成

### 6.1 部署合约

```bash
PRIVATE_KEY=0x... \
TREASURY=<SAFE_ADDRESS> \
forge script contracts/script/Deploy.s.sol:Deploy \
  --rpc-url https://arb1.arbitrum.io/rpc \
  --broadcast \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY \
  -vvv
```

### 6.2 主网合约地址记录

部署完成后，在 `docs/CONTRACT_ADDRESSES.md` 记录：

```markdown
# Arbitrum One 合约地址

- AetherRing: 0x...
- AetherGovernance: 0x...
- AetherElection: 0x...
- AetherDonation: 0x...
- Safe Treasury: 0x...
- USDC: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831
```

### 6.3 角色转移

同第五节，RPC 改为主网。

---

## 七、前端部署

### 7.1 配置环境变量

在 `.env.local`（本地开发）或 Vercel 环境变量（生产）中设置：

```bash
# Arbitrum One (42161) — 主网
NEXT_PUBLIC_AETHER_RING_42161_ADDRESS=0x...
NEXT_PUBLIC_AETHER_GOVERNANCE_42161_ADDRESS=0x...
NEXT_PUBLIC_AETHER_ELECTION_42161_ADDRESS=0x...
NEXT_PUBLIC_AETHER_DONATION_42161_ADDRESS=0x...
NEXT_PUBLIC_SAFE_WALLET_42161_ADDRESS=0x...

# Arbitrum Sepolia (421614) — 测试网
NEXT_PUBLIC_AETHER_RING_421614_ADDRESS=0x...
NEXT_PUBLIC_AETHER_GOVERNANCE_421614_ADDRESS=0x...
NEXT_PUBLIC_AETHER_ELECTION_421614_ADDRESS=0x...
NEXT_PUBLIC_AETHER_DONATION_421614_ADDRESS=0x...
NEXT_PUBLIC_SAFE_WALLET_421614_ADDRESS=0x...

# IPFS
NEXT_PUBLIC_IPFS_GATEWAY=https://gateway.pinata.cloud/ipfs/

# WalletConnect（可选）
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=...
```

### 7.2 本地开发

```bash
pnpm dev
# 访问 http://localhost:3000
```

### 7.3 生产构建

```bash
pnpm build
pnpm start
```

### 7.4 Vercel 部署

1. 在 Vercel 导入 GitHub 仓库
2. 配置环境变量（同 7.1）
3. Framework Preset: **Next.js**
4. Build Command: `pnpm build`
5. 部署

---

## 八、外部服务集成

### 8.1 PayPal Webhook 服务端

**职责**：验证 PayPal 交易后调用 `donation.mintDonation`

**实现要点**：

1. 接收 PayPal webhook 事件（`payment.completed`）
2. 调用 PayPal API 回查交易真实性（防伪造）
3. 提取：`donor` 地址、`amount`、`paypalTxId`、`payer_id`
4. 计算 `paypalAccountHash = keccak256(payer_id)`
5. 调用 `donation.mintDonation(donor, amount, paypalTxId, paypalAccountHash)`

**安全要求**：

- 服务端私钥仅用于 `mintDonation`，不持有资金
- webhook 验签防重放
- 金额单位：USD 6 decimals（$10 = 10000000）
- 服务端地址需被授予 `donation.MINTER_ROLE`

**参考实现**（Node.js + ethers）：

```javascript
import { ethers } from "ethers";

const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(PAYPAL_SERVER_KEY, provider);
const donation = new ethers.Contract(DONATION_ADDR, ABI, wallet);

// PayPal webhook handler
app.post("/webhook", async (req, res) => {
  const event = req.body;
  if (event.event_type !== "payments.payment.completed") return res.sendStatus(200);

  const payment = event.resource;
  const verified = await verifyPayPalPayment(payment.id);
  if (!verified) return res.status(400).send("Invalid payment");

  const donor = extractDonorAddress(payment);
  const amount = parseAmount(payment.amount); // 6 decimals
  const txId = payment.id;
  const payerId = payment.payer_info.payer_id;
  const accountHash = ethers.keccak256(ethers.toUtf8Bytes(payerId));

  await donation.mintDonation(donor, amount, txId, accountHash);
  res.sendStatus(200);
});
```

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

### 8.3 USDC 结算

**流程**：

1. 用户在 PayPal 捐款（USDC 金额记录在 donation NFT）
2. Safe 多签发起 USDC 转账（donor → treasury）
3. 转账确认后，Safe 调用 `donation.settleDonation(tokenId, usdcAmount)`

**USDC 合约地址**：

- Arbitrum One：`0xaf88d065e77c8cC2239327C5EDb3A432268e5831`（原生 USDC）
- 金额精度：6 decimals

---

## 九、部署后验证清单

### 9.1 合约层

- [ ] `ring.safeWallet()` 返回 Safe 地址
- [ ] `ring.appointedElderCount()` 返回 5（或预期数量）
- [ ] `ring.getActiveCitizens()` 返回合理值
- [ ] `donation.treasury()` 返回 Safe 地址
- [ ] `donation` 的 MINTER_ROLE 已授予 PayPal 服务端
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

- [ ] `pnpm build` 成功
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

## 十二、重要地址清单（Arbitrum One）

| 资源 | 地址 |
|---|---|
| Safe v1.4.1 单例 | `0x41675C099F32341bf84BFc5382aF534df5C7461a` |
| USDC（原生）| `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` |
| USDT | `0xFd086bC7CD5C481D9C376f8B1a1c1f3a5f3a5f3a` |
| WETH | `0x82aF49447D8a07e3bd95BD0d56f35241523fBab1` |
| Arbiscan | https://arbiscan.io |

---

**部署说明结束**

> 部署遇到问题请参考 [V3_AUDIT_REPORT.md](./V3_AUDIT_REPORT.md) 和 [PENDING_ISSUES.md](./PENDING_ISSUES.md)。
