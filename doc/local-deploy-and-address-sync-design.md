# 本地一键部署 + 跨仓地址同步 设计方案

> 状态:已评审通过(brainstorming 定稿),待 `writing-plans` 出实现计划
> 日期:2026-06-14
> 作者:kiritoweb3 + Claude
> 范围:GreatLottoGroup 4 仓工作区(infrastructure / ScratchCard / GreatLottoCore / interface)

## 1. 背景与目标

本地联调时,合约部署链路是:

```
infrastructure.js                          ScratchCardLocal.js / GreatLottoCoreLocal.js
  ├─ GreatLottoCoinTest (GLC)       →        需把上述 4 个地址作为构造/参数注入
  ├─ DaoCoin                        →        ↓
  ├─ DaoBenefitPool                 →    部署后产出 ScratchCard / ScratchCardNFT / PrizePool /
  └─ SalesChannel                   →        GreatLotto / GreatLottoNFT / MockEntropy 等地址
                                             ↓
                                       interface/src/app/launch/address.json 消费全部地址
```

当前痛点:

- ScratchCard / GreatLottoCore 的 `localhost.json` **硬编码**了"fresh 本地链上 account#0 首个部署 infrastructure 模块"得到的确定性地址(见 [ignition/parameters/README.md](../ignition/parameters/README.md) 末尾的下游依赖警告)。一旦 infrastructure 模块部署顺序变化,这些地址全部失效,需手工逐个回填。
- interface 的 `address.json[31337]` 里 ScratchCard / entropy 字段仍为空,需手工填。
- 起本地链 → 部署 infra → 回填下游参数 → 部署下游 → 回填 interface,5 步全手工,易错且重复。

**目标**:

1. **一键本地部署**:一条命令完成「起本地链 → 部署 infra → 同步地址 → 部署 ScratchCard/Core → 同步地址到 interface」。
2. **地址同步可复用**:写地址的逻辑对**所有环境**(localhost / baseSepolia / arbitrumSepolia / base / arbitrum)通用——测试网/主网部署后手动调一次同步器即可回填下游参数与 interface,无需手改。

## 2. 关键决策(评审已定)

| # | 决策点 | 结论 |
|---|--------|------|
| D1 | 同步覆盖范围 | **三仓参数 + interface(全链)**。同步器读各仓 `deployed_addresses.json`,写下游两仓 `parameters/<network>.json`,并回填 `interface/address.json` 对应 chainId 块 |
| D2 | 脚本位置 | **`infrastructure/scripts/`**(脚本与方案文档同放 infrastructure 仓)。脚本通过相对路径 `../<repo>` 向上访问同级的 ScratchCard / GreatLottoCore / interface 仓 |
| D3 | 本地链 | **`npx hardhat node`**(与 ignition 同生态);同步器读真实 `deployed_addresses.json`,不再依赖硬编码确定性地址 |
| D4 | 非本地写入防误 | **按网络区分**:`localhost` 自动写;测试网/主网写前打印 diff 并要求交互 `yes`(CI 传 `--yes` 跳过) |
| D5 | 一键脚本重跑策略 | **每次 `--reset` 全新部署**:起链前清三仓 `chain-31337/` 部署 + 重启 hardhat node,三仓部署均带 `--reset`,避免 journal 与新链不一致 |

## 3. 架构

```
infrastructure/scripts/
  ├─ README.md              ← 本方案配套使用文档(交付物之一)
  ├─ deploy.config.json     ← 唯一事实源:网络注册表 + 地址映射清单(纯声明)
  ├─ sync-addresses.mjs     ← 环境无关的同步器(可复用核心,Node ESM)
  └─ deploy-local.sh        ← 一键本地编排器(仅 31337,bash 串联)
```

> **`README.md`(交付物)**:与脚本同放 `infrastructure/scripts/`,面向使用者(非设计读者)。内容覆盖:① 一键本地部署怎么跑(前置条件 + 一条命令 + 预期输出);② 同步器在测试网/主网怎么单独用(dry-run → 确认 → `--write`);③ 加一条链 / 加一个合约时怎么改 `deploy.config.json`;④ 常见错误对照(节点起不来 / grantRole revert / 某仓未部署)。本设计文档(`doc/`)讲「为什么这么设计」,README 讲「怎么用」,两者不重复。

脚本运行时以**工作区根**(`infrastructure/` 的上级目录,即 4 仓共同父目录)为基准解析各仓路径:`<scriptDir>/../../<repo>`。`deploy-local.sh` 与 `sync-addresses.mjs` 启动时先把 cwd 锚定到工作区根,再按 §4.2 的相对路径拼接。

三者职责:

- **`deploy.config.json`** —— 声明"哪个合约的地址,从哪个仓的哪个 ignition key 读,写到哪些目的地"。加链 / 加合约只改这里。
- **`sync-addresses.mjs`** —— 纯读写 JSON。给定 `--network`,把来源地址按清单同步到所有目的地。环境无关,任何链都能跑。
- **`deploy-local.sh`** —— 仅本地:起链 + 串联三仓 `ignition deploy` + 两次调 `sync-addresses.mjs`。

## 4. 组件 1:`deploy.config.json`(映射清单)

两张表。

### 4.1 网络注册表 `networks`

把 chainId / 网络名 / 各仓参数文件名 / ignition 模块名 绑定到一起:

```jsonc
{
  "networks": {
    "localhost":       { "chainId": 31337,    "scModule": "ScratchCardLocalModule", "coreModule": "GreatLottoCoreLocal", "local": true },
    "baseSepolia":     { "chainId": 84532,    "scModule": "ScratchCardModule",      "coreModule": "GreatLottoCore",      "local": false },
    "arbitrumSepolia": { "chainId": 421614,   "scModule": "ScratchCardModule",      "coreModule": "GreatLottoCore",      "local": false },
    "base":            { "chainId": 8453,     "scModule": "ScratchCardModule",      "coreModule": "GreatLottoCore",      "local": false },
    "arbitrum":        { "chainId": 42161,    "scModule": "ScratchCardModule",      "coreModule": "GreatLottoCore",      "local": false }
  }
}
```

- 参数文件名约定为 `<network>.json`(localhost / baseSepolia / …),与现有 `ignition/parameters/` 一致。
- `--network` 既接受网络名也接受 chainId,内部统一解析。

### 4.2 仓路径表 `repos`

各仓相对工作区根的路径(同步器据此拼 `ignition/deployments/chain-<id>/deployed_addresses.json` 与 `ignition/parameters/<network>.json`):

```jsonc
{
  "repos": {
    "infrastructure": "infrastructure",
    "scratchcard":    "ScratchCard",
    "core":           "GreatLottoCore",
    "interface":      "interface/src/app/launch/address.json"   // interface 直接给 address.json 路径
  }
}
```

### 4.3 地址映射 `mappings`

逻辑合约 → 来源仓 + ignition key(数组,容忍 Test/生产别名,先命中者胜)→ 各目的地字段:

```jsonc
{
  "mappings": [
    {
      "logical": "GreatLottoCoin",
      "source": "infrastructure",
      "keys": ["Infrastructure#GreatLottoCoinTest", "Infrastructure#GreatLottoCoin"],
      "targets": {
        "scParam":   "greatLottoCoinAddress",
        "coreParam": "greatLottoCoinAddress",
        "interface": "contracts.GreatCoinContractAddress"
      }
    },
    {
      "logical": "DaoCoin",
      "source": "infrastructure",
      "keys": ["Infrastructure#DaoCoin"],
      "targets": {
        "scParam":   "daoCoinAddress",
        "coreParam": "daoCoinAddress",
        "interface": "contracts.DaoCoinContractAddress"
      }
    },
    {
      "logical": "DaoBenefitPool",
      "source": "infrastructure",
      "keys": ["Infrastructure#DaoBenefitPool"],
      "targets": {
        "scParam":   "daoBenefitPoolAddress",
        "coreParam": "daoBenefitPoolAddress",
        "interface": "contracts.DaoBenefitPoolContractAddress"
      }
    },
    {
      "logical": "SalesChannel",
      "source": "infrastructure",
      "keys": ["Infrastructure#SalesChannel"],
      "targets": {
        "scParam":   "salesChannelAddress",
        "coreParam": "salesChannelAddress",
        "interface": "contracts.SalesChannelContractAddress"
      }
    },

    // ── ScratchCard 产出 ──
    {
      "logical": "ScratchCard",
      "source": "scratchcard",
      "keys": ["ScratchCardLocalModule#ScratchCard", "ScratchCardModule#ScratchCard"],
      "targets": { "interface": "contracts.ScratchCardContractAddress" }
    },
    {
      "logical": "ScratchCardNFT",
      "source": "scratchcard",
      "keys": ["ScratchCardLocalModule#ScratchCardNFT", "ScratchCardModule#ScratchCardNFT"],
      "targets": { "interface": "contracts.ScratchCardNFTContractAddress" }
    },
    // 注:ScratchCard 的 PrizePool 与 Core 的 PrizePool 是两个不同合约;interface 的
    //     PrizePoolContractAddress 当前对应 Core 的奖池。ScratchCard 奖池若 interface 需要,
    //     需新增字段(见 §8 待确认)。

    // ── GreatLottoCore 产出 ──
    {
      "logical": "GreatLotto",
      "source": "core",
      "keys": ["GreatLottoCoreLocal#GreatLotto", "GreatLottoCore#GreatLotto"],
      "targets": { "interface": "contracts.GreatLottoContractAddress" }
    },
    {
      "logical": "GreatLottoNFT",
      "source": "core",
      "keys": ["GreatLottoCoreLocal#GreatLottoNFT", "GreatLottoCore#GreatLottoNFT"],
      "targets": { "interface": "contracts.GreatNftContractAddress" }
    },
    {
      "logical": "CorePrizePool",
      "source": "core",
      "keys": ["GreatLottoCoreLocal#PrizePool", "GreatLottoCore#PrizePool"],
      "targets": { "interface": "contracts.PrizePoolContractAddress" }
    },
    {
      "logical": "InvestmentCoin",
      "source": "core",
      "keys": ["GreatLottoCoreLocal#InvestmentCoin", "GreatLottoCore#InvestmentCoin"],
      "targets": { "interface": "contracts.InvestmentCoinContractAddress" }
    },
    {
      "logical": "InvestmentBenefitPool",
      "source": "core",
      "keys": ["GreatLottoCoreLocal#InvestmentBenefitPool", "GreatLottoCore#InvestmentBenefitPool"],
      "targets": { "interface": "contracts.InvestmentBenefitPoolContractAddress" }
    },

    // entropy 不在 mappings 内 —— 因其地址/provider 来源随本地/非本地而变(见 §5.4),
    // 单列为下方独立 `entropy` 配置块处理。
  ],

  "entropy": {
    "interfaceAddressKey": "entropy.entropyAddress",
    "interfaceProviderKey": "entropy.entropyProvider",
    // 本地:address 取自部署的 MockEntropy(产出),provider 取自 SC 参数文件占位
    "local":  { "addressFromDeployed": { "source": "scratchcard", "keys": ["ScratchCardLocalModule#MockEntropy"] },
                "providerFromScParam": "entropyProvider" },
    // 非本地:address/provider 均是部署输入,从 SC 参数文件读出再推进 interface
    "remote": { "addressFromScParam": "entropyAddress", "providerFromScParam": "entropyProvider" }
  }
}
```

> 上表的逻辑合约清单需在实现时与三仓**最新** ignition 模块 + interface `address.json` 字段逐一核对补全(本文件列主干,实现阶段补齐 InvestmentEth / GreatEth / GuaranteePool 等 interface 现存字段或显式标注本地不部署 → 留空)。

## 5. 组件 2:`sync-addresses.mjs`(同步器)

### 5.1 调用约定

```bash
node infrastructure/scripts/sync-addresses.mjs --network <name|chainId> [--write] [--yes] [--only sc,core,interface]
```

| 参数 | 含义 |
|------|------|
| `--network` | 必填。网络名或 chainId |
| `--write` | 真正写文件。**缺省为 dry-run**(只打印 diff) |
| `--yes` | 跳过非本地的交互确认(CI 用) |
| `--only` | 可选,限定只同步部分目的地(`sc` / `core` / `interface`) |

### 5.2 主流程

```
1. 解析 --network → { networkName, chainId, local, scModule, coreModule }
2. 载入 deploy.config.json
3. 对每个来源仓 ∈ {infrastructure, scratchcard, core}:
     读 <repo>/ignition/deployments/chain-<chainId>/deployed_addresses.json
     缺文件 → 记为"该仓未部署",其依赖的 mapping 跳过并警告
4. 解析逻辑地址:遍历 mappings,对每条按 keys 顺序在来源仓字典里找,先命中者为该逻辑地址值
     localOnly 的 mapping 在非本地网络跳过
5. 计算 diff:对每个目的地文件,逐 target 字段对比 旧值 vs 解析值
     - SC 参数:  <ScratchCard>/ignition/parameters/<network>.json → 顶层 [scModule][scParam]
     - Core 参数: <GreatLottoCore>/ignition/parameters/<network>.json → 顶层 [coreModule][coreParam]
     - interface: <address.json>[chainId].<interface 点路径>
6. 打印 diff(始终):  file :: key : 旧值 → 新值(无变化的不打印)
7. 写入闸门:
     - local==true            → 直接写
     - local==false 且无 --yes → 打印 diff,提示输入 yes 确认;非 yes 即中止
     - local==false 且有 --yes → 直接写
   未带 --write → 永远只到第 6 步(dry-run),不写
8. 写文件:仅替换映射到的 key,其余 key 原样保留;2 空格缩进 + 末尾换行(与现有文件风格一致)
```

### 5.3 写入安全细则

- **不重排 key、不删 key**:用「读 JSON → 改对象 → `JSON.stringify(obj, null, 2)`」,只动目标字段。
- **零地址/空串识别**:解析到的来源值若为空或 `0x000...0`,视为"未部署",跳过该字段并警告(避免把空值刷掉已有真实值)。
- **幂等**:重复跑同一网络结果一致,无变化时 diff 为空、不写。

### 5.4 entropy 的方向差异(关键)

| 环境 | `entropyAddress` 来源 | `entropyProvider` 来源 |
|------|----------------------|----------------------|
| **localhost** | 部署产出的 **MockEntropy**(`deployed_addresses.json` 读) → 推进 interface | 本地为占位 `0x..01`,从 SC/Core `localhost.json` 读 → 推进 interface |
| **测试网/主网** | **输入**:从 SC/Core `<network>.json` 的 `entropyAddress` 读 → 推进 interface | 同左,从参数文件读 → 推进 interface |

即:非本地时 entropy 不是"部署产出",而是部署**输入**(Pyth 当日官方地址),同步器把它从参数文件搬到 interface。实现上把 entropy 两个字段建模为「来源可为 deployed_addresses 或参数文件」的特殊 mapping。

## 6. 组件 3:`deploy-local.sh`(一键本地编排,仅 31337)

```
步骤                                                   失败处理
──────────────────────────────────────────────────────────────────
0. set -euo pipefail;定位工作区根                       任一步非零退出即中止
1. 预检                                                 缺失即报错并给修复命令
   - SC/Core 的 node_modules/@greatlotto/infrastructure 软链接在位
   - 三仓 node_modules 已装(否则提示 pnpm i)
2. 清旧部署                                              —
   - rm -rf {infra,SC,Core}/ignition/deployments/chain-31337
3. 起本地链                                              端口占用/起不来 → 报错退出
   - (cd infrastructure && npx hardhat node) & 记 NODE_PID
   - 轮询 http://127.0.0.1:8545 (eth_chainId) 至就绪,超时 ~30s 报错
4. 部署 infrastructure                                  ignition 非零 → trap 拆链退出
   - cd infrastructure && npx hardhat ignition deploy ignition/modules/infrastructure.js \
       --network localhost --parameters ignition/parameters/localhost.json --reset
5. 同步 infra → SC/Core localhost.json                  —
   - node infrastructure/scripts/sync-addresses.mjs --network localhost --write --only sc,core
6. 部署 ScratchCardLocal + GreatLottoCoreLocal          grantRole revert → 提示 account#0 须持 ADMIN
   - cd ScratchCard     && npx hardhat ignition deploy ignition/modules/ScratchCardLocal.js \
       --network localhost --parameters ignition/parameters/localhost.json --reset
   - cd GreatLottoCore  && npx hardhat ignition deploy ignition/modules/GreatLottoCoreLocal.js \
       --network localhost --parameters ignition/parameters/localhost.json --reset
7. 同步 三仓 → interface address.json[31337]            —
   - node infrastructure/scripts/sync-addresses.mjs --network localhost --write --only interface
8. 收尾                                                 —
   - 打印各合约地址汇总 + NODE_PID + "停止: kill $NODE_PID"
   - 节点保留运行(interface dev 需要);trap ERR/INT → kill 节点后退出
```

要点:

- **节点跑完保留**:interface 本地开发依赖 `:8545`,脚本正常结束不杀节点,只在**出错/中断**时 trap 拆链。
- **hardhat node 由 infrastructure 起**:任一仓 hardhat node 都是同一条 31337 链;选 infra 作宿主,避免三仓各起一条。
- **`--reset` 全程**:配合步骤 2 清 journal,保证每次跑都是干净链上的确定性部署。

## 7. 错误处理汇总

| 场景 | 表现 | 处理 |
|------|------|------|
| hardhat node 起不来 / 端口占用 | RPC 轮询超时 | 明确报"`:8545` 未就绪",提示先 `lsof -i:8545` |
| infra 部署后 account#0 非 ADMIN | 步骤 6 `grantRole` revert | 同步器/脚本提示:本地补授权要求 account#0 持 GLC/DaoCoin 的 `DEFAULT_ADMIN_ROLE`(见 `ScratchCardLocal.js` 前提注释) |
| 某仓未部署就同步 | `deployed_addresses.json` 缺失 | 同步器指明"<repo> chain-<id> 未部署",跳过其 mapping,非致命 |
| 非本地误跑 `--write` | —— | D4 闸门:非本地无 `--yes` 必须交互确认才写 |
| 来源地址为空/零地址 | —— | 跳过该字段,不覆盖目的地已有真实值,打印警告 |

## 8. 已知坑 / 待确认(实现阶段处理)

1. **interface `address.json[31337].payToken` 硬编码主网稳定币**(USDT/USDC/DAI/WETH),全新本地链上不存在;本地真实支付币是 `GreatLottoCoinTest`。本方案**不修**,仅在此标注——本地若要走支付流程,需另行决定把 `GreatCoinContractAddress` 当支付币,或在 payToken 里补本地 GLC 地址。属独立议题。
2. **两个 PrizePool 同名不同物**:ScratchCard 的 PrizePool 与 Core 的 PrizePool 是不同合约;interface `PrizePoolContractAddress` 现仅一处。本方案默认它指向 **Core** 奖池;若 interface 需要 ScratchCard 奖池地址,需在 interface `address.json` 新增字段(如 `ScratchCardPrizePoolContractAddress`),再补一条 mapping。需产品/前端确认。
3. **interface 字段全量核对**:`address.json` 还有 `GreatEthContractAddress` / `InvestmentEthContractAddress` / `GuaranteePoolContractAddress` 等。需在实现阶段确认本地是否部署对应合约——不部署的显式留空并在清单注明,避免遗漏被误读为"漏同步"。
4. **`deploy.config.json` 与 ignition 模块漂移**:ignition key 形如 `<模块名>#<合约名>`,模块改名或合约增减会令 keys 失配。同步器在解析不到任一 key 时应**显式警告**(而非静默留空),把漂移暴露出来。

## 9. 验收标准

- [ ] 全新环境跑 `deploy-local.sh` 一条命令,三仓部署成功,interface `address.json[31337]` 的 contracts(本地部署的)+ entropy 全部非空且与链上一致。
- [ ] `sync-addresses.mjs --network localhost`(不带 `--write`)打印 diff 不写文件;带 `--write` 后再跑一次 diff 为空(幂等)。
- [ ] `sync-addresses.mjs --network baseSepolia`(非本地)默认 dry-run;`--write` 无 `--yes` 时要求交互确认。
- [ ] 改 infrastructure 模块部署顺序后重跑一键脚本,下游 `localhost.json` 与 interface 自动跟随新地址,无需手改。
- [ ] 出错/Ctrl-C 时 hardhat node 被 trap 干净拆除,无僵尸进程。
- [ ] `infrastructure/scripts/README.md` 已交付,覆盖一键部署用法 / 同步器单独用法 / 改 `deploy.config.json` 指引 / 常见错误对照。

## 10. 关联文档

- [ignition/parameters/README.md](../ignition/parameters/README.md) —— 下游 localhost 地址依赖警告(本方案正是要消除这个手工依赖)
- ScratchCard:`ignition/modules/ScratchCardLocal.js`(本地模块 + 本地补授权前提)
- GreatLottoCore:`ignition/modules/GreatLottoCoreLocal.js`
- 本仓脚本目录:`infrastructure/scripts/`(脚本 + 配置落此;经 `../../<repo>` 访问同级三仓)
- 工作区协调层:`.claude-workspace/CLAUDE.md`(跨仓约定参考)
