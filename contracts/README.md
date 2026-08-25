# Aether Foundation — 治理合约

Foundry 工程，实现 Aether DAO 三院分权制衡治理系统。

## 架构

```
AetherRing (SBT 身份凭证)  ←——isBearer/getTier——  AetherGovernance (治理主合约)
   │                                                  │
   │  10 级权级枚举                                    │  方案 B 计票：
   │  不可转让（OZ v5 _update override）              │  - 三院共识门槛 (≥2 院一致)
   │                                                  │  - 会员参与率 ≥ 30%
   │                                                  │  - 会员反对率 < 60% 绝对否决
   │                                                  │  - 总赞成权重 = 院方×(2/3) + 会员×(1/3) > 50%
   │                                                  │
   │                                                  │  Timelock: 资金类 48h / 信号类 12h
   │                                                  │  execute 扩展槽：SIGNAL ✅ / PARAM ✅ / TREASURY 预留
```

## 目录结构

```
contracts/
├── foundry.toml
├── src/
│   ├── AetherRing.sol                    # 道环 SBT
│   ├── AetherGovernance.sol              # 治理主合约
│   └── interfaces/
│       └── IAetherRing.sol               # 治理依赖的最小接口
├── test/
│   ├── AetherRing.t.sol                  # 道环单测（14 个用例）
│   └── AetherGovernance.t.sol            # 治理单测（21 个用例，5 大场景 + 边界）
├── script/
│   └── Deploy.s.sol                      # 部署脚本
└── lib/openzeppelin-contracts/           # forge install 后生成
```

## 计票规则速查

| 阶段 | 规则 | 失败结果 |
|---|---|---|
| 三院立场 | 每院内部按权重比较 For vs Against，多数决出 FOR / AGAINST / NEUTRAL | — |
| 院方共识 | ≥2 院 FOR → 共识 FOR；≥2 院 AGAINST → 共识 AGAINST；否则 NEUTRAL | NEUTRAL 直接 Defeated |
| 会员参与率 | `(For+Against+Abstain) / totalMembers ≥ 30%` | < 30% → Defeated |
| 会员反对率 | `memberAgainst / 总票数 < 60%` | ≥ 60% → 绝对否决 Defeated |
| 加权通过 | `院方(1 or 0)×(2/3) + 会员赞成率×(1/3) > 50%` | ≤ 50% → Defeated |

通过 → 进入 Timelock 队列（SIGNAL/PARAM 12h，TREASURY 48h）→ 到期后任何人可 execute。

## 本地运行

### 1. 安装 Foundry

**macOS / Linux：**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

**Windows：** 用 WSL2 跑上面同样的命令。

### 2. 进入工程目录

```bash
cd contracts
```

### 3. 安装 OpenZeppelin v5 依赖

```bash
forge install OpenZeppelin/openzeppelin-contracts --no-commit
```

> 这会在 `lib/openzeppelin-contracts/` 下拉取 v5 最新版。`foundry.toml` 已配好 remapping。

### 4. 编译

```bash
forge build
```

### 5. 跑测试

```bash
# 全部测试
forge test -vv

# 只跑治理测试 + 显示 trace
forge test --match-contract AetherGovernanceTest -vvv

# 只跑某个场景
forge test --match-test test_Scenario1_AllChambersFor_MembersFor_Passes -vvvv

# 跑覆盖率
forge coverage
```

### 6. 启动本地链 + 部署

```bash
# 一个终端跑 Anvil
anvil

# 另一个终端部署（私钥从 Anvil 启动时打印的测试账户复制，或从密钥管理注入；
# 切勿把真实私钥写入文档、脚本或命令历史）
export PRIVATE_KEY=<Anvil-打印的第一个测试账户私钥>
forge script script/Deploy.s.sol:Deploy \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  -vvv
```

部署后会输出两个合约地址，记下来给前端用。

> **BSC 主网部署（唯一目标链）**：合约不依赖任何链专属特性，
> `AetherDonation` 的捐款门槛按所配稳定币 `decimals()` 动态计算
> （BSC Binance-Peg USDC/USDT 为 18 decimals，$10 = 10 * 10^18）。
> 部署命令把 `--rpc-url` 换成 BSC RPC（如 `https://bsc-dataseed.binance.org`），
> `TREASURY` 用 BSC 上的 Safe 多签，`USDC` 传 Binance-Peg USDC
> `0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d`（或 USDT `0x55d398...7955`）即可。

### 7. 铸造初始道环（可选：初始化理事会）

```bash
# 给某个地址铸一个议长道环
cast send <RING_ADDRESS> "mintRing(address,uint8,string)" \
  0x70997970C51812dc3A010C7d01b50e0d17dc79C8 3 "" \
  --private-key $PRIVATE_KEY \
  --rpc-url http://127.0.0.1:8545
```

## 部署到 BSC 测试网

```bash
export PRIVATE_KEY=0x...你的测试网私钥

forge script script/Deploy.s.sol:Deploy \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
  --broadcast \
  --verify \
  --verifier etherscan \
  --verifier-url https://api-testnet.bscscan.com/api
```

## 测试覆盖

### AetherRing.t.sol（14 个用例）

- 铸造成功 / 非法接收方 / 重复铸 / 非 minter 角色
- 转让 revert / approve revert / setApprovalForAll revert
- 升降级 + 影响会员计数 / 非 admin / 非法 tier
- 撤销 / 撤销不存在
- getTotalMembers 跟踪铸/撤/升级
- setRingActive 暂停/恢复
- supportsInterface

### AetherGovernance.t.sol（21 个用例）

**5 大场景：**
1. ✅ 三院全赞成 + 会员多数赞成 → Queued
2. ✅ 三院 2:1 + 会员多数赞成 → Queued
3. ✅ 三院全赞成 + 会员参与率 < 30% → Defeated
4. ✅ 三院全赞成 + 会员反对率 ≥ 60% → Defeated（绝对否决）
5. ✅ 三院 1:1:1 无共识 → Defeated

**边界：**
- 无道环投票 / 重复投票 / 非法选项 / 投票窗口外
- finalize 投票未结束 / 二次 finalize
- 提案空标题 / TREASURY 零地址
- Timelock 未到不能 execute
- SIGNAL execute 无副作用
- PARAM execute 修改合约参数
- simulateFinalize 与实际结果一致
- 议长权重 20 > 9 议员权重 18
- cancelProposal 管理员专属
- 参与率正好 30% / 略低于 30%
