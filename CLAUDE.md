# CLAUDE.md

## Project Overview

AIDefiGuardian — AI 驱动的 DeFi 安全守护工具，为 Aave 等借贷协议用户提供自动化的仓位保护。

核心思路：用户在 Registry 中注册保护策略（健康因子阈值、单笔最大还款额、冷却期），当链上健康因子低于阈值时，由 Vault 合约自动执行还款操作。

## Tech Stack

- **语言:** Solidity ^0.8.20
- **框架:** Foundry (forge / forge-std v1.15.0)
- **依赖:** OpenZeppelin Contracts v5.6.1
- **测试:** forge test

## Project Structure

```
src/
  ├── GuardianRegistry.sol      — 用户策略注册表
  ├── GuardianVault.sol         — ERC-4626 保护预算金库 + 执行还款
  ├── AaveIntegration.sol       — 封装 Aave V3 交互
  └── interfaces/
      └── IAavePool.sol         — Aave V3 Pool 最小化接口
test/
  ├── GuardianRegistry.t.sol    — 23 tests
  ├── AaveIntegration.t.sol     — 13 tests
  ├── GuardianVault.t.sol       — 24 tests
  ├── integration/
  │   └── Guardian.fork.t.sol   — 8 fork tests (Sepolia Aave V3)
  └── mocks/
      ├── MockAavePool.sol      — 可控 HF/debt 的 Aave mock
      └── MockERC20.sol         — 可 mint 的 ERC20
script/                         — 部署脚本（待实现）
lib/                            — forge-std, openzeppelin-contracts
foundry.toml                    — Foundry 配置 & remappings
.env                            — RPC URL 等敏感配置（git ignored）
.env.example                    — .env 模板
```

## Architecture

### 合约职责

- **GuardianRegistry** — 用户策略注册表，管理 Policy（阈值、限额、冷却期），维护 registeredUsers 列表供 Agent 遍历
- **GuardianVault (ERC-4626)** — 托管用户 USDC 保护预算，执行 `executeRepayment` 核心保护逻辑，含 Pausable 紧急暂停
- **AaveIntegration** — 封装 Aave V3 交互（查 HF、查债务、代还款），隔离外部依赖

### 合约交互关系总览

```
┌──────────┐         ┌───────────────────┐         ┌──────────────────┐
│          │         │                   │         │                  │
│   User   │         │   Protocol Owner  │         │   AI Agent       │
│  (EOA)   │         │      (EOA)        │         │   (EOA)          │
│          │         │                   │         │                  │
└────┬─────┘         └────────┬──────────┘         └────────┬─────────┘
     │                        │                             │
     │  setPolicy()           │  deploy & setVault()        │  executeRepayment()
     │  deposit()             │  pause() / unpause()        │
     │  withdraw()            │  setProtocolAgent()         │
     │  deactivate()          │                             │
     ▼                        ▼                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         On-Chain Contracts                          │
│                                                                     │
│  ┌──────────────────┐    reads     ┌──────────────────────────┐    │
│  │ GuardianRegistry │◄────────────│     GuardianVault        │    │
│  │                  │             │     (ERC-4626)            │    │
│  │ • policies       │ recordExec  │                          │    │
│  │ • registeredUsers│◄────────────│ • protocolAgent          │    │
│  │ • vault          │             │ • protocolTreasury       │    │
│  │ • owner          │             │ • owner                  │    │
│  └──────────────────┘             └────────────┬─────────────┘    │
│                                                │                   │
│                                                │ transfer USDC     │
│                                                │ + repayOnBehalf() │
│                                                ▼                   │
│                                   ┌──────────────────────────┐    │
│                                   │   AaveIntegration        │    │
│                                   │                          │    │
│                                   │ • aavePool (immutable)   │    │
│                                   │ • usdc (immutable)       │    │
│                                   │ • vault                  │    │
│                                   └────────────┬─────────────┘    │
│                                                │                   │
└────────────────────────────────────────────────┼───────────────────┘
                                                 │ approve + repay()
                                                 │ getUserAccountData()
                                                 │ getReserveData()
                                                 ▼
                                   ┌──────────────────────────┐
                                   │   Aave V3 Pool           │
                                   │   (External Protocol)    │
                                   │                          │
                                   │ • 管理用户借贷仓位         │
                                   │ • healthFactor 计算       │
                                   │ • 接受代还款               │
                                   └──────────────────────────┘
```

### Flow 1：部署 & 初始化（Owner）

```
Owner
  │
  ├─① deploy GuardianRegistry ──────────────────► Registry created
  │                                                (owner = msg.sender)
  │
  ├─② deploy AaveIntegration(aavePool, usdc) ──► AaveIntegration created
  │                                                (owner = msg.sender)
  │
  ├─③ deploy GuardianVault(usdc, registry, ────► Vault created
  │     aaveIntegration, agent, treasury)          (owner = msg.sender)
  │
  ├─④ registry.setVault(vault) ────────────────► Registry.vault = vault ✅
  │     打破循环依赖：Vault 需要 Registry,
  │     Registry 需要知道 Vault 来限制 recordExecution
  │
  └─⑤ aaveIntegration.setVault(vault) ────────► AaveIntegration.vault = vault ✅
        同理：repayOnBehalf 只允许 Vault 调用

  ※ setVault 都是一次性的，设置后不可更改
```

### Flow 2：用户注册 + 存入预算

```
User
  │
  ├─① registry.setPolicy(1.3e18, 500e6, 3600)
  │     │
  │     ├─ require: 1.05e18 ≤ threshold ≤ 1.8e18  ✅
  │     ├─ require: maxRepay > 0                    ✅
  │     ├─ require: cooldown ≥ 3600                 ✅
  │     ├─ registeredUsers.push(user)  ← AI Agent 用来遍历
  │     └─ emit PolicySet(user, 1.3e18, 500e6)
  │
  │  此时 Registry 中:
  │  policies[user] = {
  │    healthFactorThreshold: 1.3e18,   ← HF 低于 1.3 就保护
  │    maxRepayPerTx: 500e6,            ← 单次最多还 500 USDC
  │    cooldownPeriod: 3600,            ← 两次保护间隔 ≥ 1 小时
  │    lastExecutionTime: 0,            ← 未执行过
  │    active: true
  │  }
  │
  ├─② usdc.approve(vault, 1000e6)
  │
  └─③ vault.deposit(1000e6, user)
        │
        ├─ USDC: User ──1000 USDC──► Vault
        ├─ gUSDC: mint 1000 gUSDC ──► User
        └─ emit Deposit(user, 1000e6, 1000e6)

  用户现在：
  • Registry 中有激活的策略
  • Vault 中有 1000 USDC 保护预算
  • 持有 1000 gUSDC 份额代币
```

### Flow 3：AI 自动保护（核心流程）

```
            链下                                    链上
  ┌─────────────────────┐
  │ AI Agent (TypeScript)│
  │                      │
  │ 每隔 30s 循环:       │
  │  1. 读 registeredUsers│
  │  2. 逐个查 HF        │
  │  3. HF < 阈值?       │
  │     → Claude 分析决策 │
  │     → 调用合约        │
  └──────────┬───────────┘
             │
             │  vault.executeRepayment(user, 500e6, "ETH dropped 8%...")
             ▼
  ┌─────────────────────────────────────────────────────────────┐
  │  GuardianVault.executeRepayment()                           │
  │                                                             │
  │  ① require(msg.sender == protocolAgent)     ← 只有 Agent   │
  │                                                             │
  │  ② policy = registry.getPolicy(user) ──────► Registry      │
  │     require(policy.active)                    (staticcall)  │
  │                                                             │
  │  ③ hfBefore = aaveIntegration ──► AaveIntegration           │
  │       .getHealthFactor(user)        │                       │
  │                                     └──► Aave Pool          │
  │                                          .getUserAccountData│
  │                                          returns HF=1.2e18  │
  │                                                             │
  │  ④ 冷却期检查（两级设计）:                                    │
  │     lastExecTime > 0 ?                                      │
  │       ├─ NO → 首次执行，跳过冷却 ✅                           │
  │       └─ YES → block.timestamp < lastExec + cooldown ?      │
  │                  ├─ NO → 冷却已过 ✅                         │
  │                  └─ YES → 在冷却中 ⚠️                       │
  │                            └─ HF < threshold - 0.2e18 ?    │
  │                                 ├─ YES → 紧急豁免 ✅        │
  │                                 └─ NO → REVERT ❌           │
  │                                                             │
  │  ⑤ require(repayAmount ≤ maxRepayPerTx)                     │
  │                                                             │
  │  ⑥ require(userAssets ≥ repayAmount)      ← gUSDC 换算     │
  │                                                             │
  │  ⑦ actualRepay = min(repayAmount, userDebt)                 │
  │     require(actualRepay > 0)                                │
  │                                                             │
  │  ⑧ 资金操作:                                                │
  │     fee = actualRepay × 0.1%                                │
  │                                                             │
  │     _withdraw() → burn user 的 gUSDC 份额                   │
  │                                                             │
  │     USDC 分配:                                              │
  │     ┌─────────┐    fee(0.5 USDC)    ┌──────────┐           │
  │     │  Vault  │ ──────────────────► │ Treasury │           │
  │     │         │   499.5 USDC        └──────────┘           │
  │     │         │ ──────────────────► AaveIntegration         │
  │     └─────────┘                      │                      │
  │                                      │ .repayOnBehalf()     │
  │                                      ▼                      │
  │                              ┌───────────────┐              │
  │                              │AaveIntegration│              │
  │                              │               │              │
  │                              │ approve(pool) │              │
  │                              │ pool.repay()  │──► Aave Pool │
  │                              │  (代 user 还) │   (还 USDC)  │
  │                              └───────────────┘              │
  │                                                             │
  │  ⑨ registry.recordExecution(user) ──► lastExecutionTime更新 │
  │                                                             │
  │  ⑩ emit ProtectionExecuted(user, 500e6, 1.2e18, 1.45e18,  │
  │         "ETH dropped 8%, repaying to restore HF", timestamp)│
  │                                                             │
  │  ⑪ remaining < maxRepayPerTx ?                              │
  │       └─ YES → emit BudgetLow(user, remaining)             │
  └─────────────────────────────────────────────────────────────┘
```

### Flow 4：用户取回预算 / 停用保护

```
场景 A：取回部分预算
  User ── vault.withdraw(300e6, user, user) ──► 300 USDC 回到 User
                                                burn 对应 gUSDC

场景 B：停用保护
  User ── registry.deactivate() ──► policy.active = false
                                    emit PolicyDeactivated(user)
     ※ AI Agent 查到 active=false 就跳过此用户
     ※ Vault 里的 USDC 不受影响，用户随时可以 withdraw

场景 C：重新激活
  User ── registry.setPolicy(...) ──► active = true
                                      lastExecutionTime 保留
                                      ※ 会在 registeredUsers 多 push 一次（已知行为）
```

### Flow 5：紧急暂停

```
发现漏洞 / 异常时:

  Owner ── vault.pause() ──► _paused = true

  此后:
  • Agent 调 executeRepayment() → REVERT (EnforcedPause)
  • 用户 deposit/withdraw 不受影响（ERC4626 没加 whenNotPaused）

  修复后:
  Owner ── vault.unpause() ──► 恢复正常
```

### 权限矩阵

| 函数 | 调用者 |
|------|--------|
| Registry.setPolicy / deactivate | 任何人（为自己） |
| Registry.setVault | Owner（仅一次） |
| Registry.recordExecution | 仅 Vault |
| AaveIntegration.setVault | Owner（仅一次） |
| AaveIntegration.repayOnBehalf | 仅 Vault |
| AaveIntegration.getHealthFactor / getUserDebt | 任何人（view） |
| Vault.deposit / withdraw | 任何人（为自己） |
| Vault.executeRepayment | 仅 protocolAgent |
| Vault.pause / unpause / setProtocolAgent | 仅 Owner |

### 循环依赖解决

Vault 需要 Registry 和 AaveIntegration 的地址（构造函数传入），而 Registry 和 AaveIntegration 需要知道 Vault 地址（限制 `onlyVault`）。解决方案：先部署三个合约，再调用 `registry.setVault(vault)` 和 `aaveIntegration.setVault(vault)` 打破循环。`setVault` 只能调一次。

## Commands

- `forge build` — 编译合约
- `forge test` — 运行全部单元测试（60 tests，不需要 RPC）
- `forge test -vvv` — 详细测试输出
- `forge test --match-contract GuardianForkTest -vvv` — 运行 fork 集成测试（8 tests，需要 .env 中的 SEPOLIA_RPC_URL）
- `forge test --no-match-contract GuardianForkTest` — 只跑单元测试，跳过 fork 测试

Foundry 会自动读取项目根目录的 `.env` 文件，不需要手动 `source .env`。

## Aave V3 Sepolia 地址

| 合约 | 地址 |
|------|------|
| Pool | `0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951` |
| USDC | `0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8` |
| WETH | `0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c` |
| PoolAddressesProvider | `0x012bAC54348C0E635dCAc9D5FB99f06F24136C9A` |
| Oracle | 通过 AddressesProvider.getPriceOracle() 动态获取 |

## Fork 测试注意事项

- Sepolia USDC 池子流动性有限且供应上限已满，fork 测试中通过 `deal(USDC, aTokenAddress, amount)` 直接注入流动性
- Aave Oracle 地址不要硬编码，通过 `AddressesProvider.getPriceOracle()` 动态获取
- 模拟价格下跌用 `vm.mockCall(oracle, getAssetPrice(WETH), newPrice)`，价格精度为 8 位（如 ETH=$2200 → `2200e8`）
- Aave 内部精度舍入可能导致 1 wei 差异，断言用近似值
- Sepolia ETH 价格约 $4000（8 位精度），计算 HF 公式：`HF = (ETH_price × LT) / debt`，LT（清算阈值）约 0.825

## 金额精度速查

| 类型 | decimals | 示例 | 含义 |
|------|----------|------|------|
| USDC 金额 | 6 | `500e6` | 500 USDC |
| ETH 金额 | 18 | `1e18` | 1 ETH |
| 健康因子 | 18 | `1.3e18` | HF = 1.3 |
| Aave Oracle 价格 | 8 | `2200e8` | $2,200 |

## Conventions

- 合约代码优先考虑安全性和可读性
- 不添加多余注释和文档，除非明确要求
- Solidity "Stack too deep" 用 scoped block `{}` 解决，减少同时存在的局部变量
- ERC4626 内部 `_withdraw(caller, receiver, owner, ...)` 中 caller==owner 时跳过 allowance 检查
