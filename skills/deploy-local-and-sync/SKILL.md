---
name: deploy-local-and-sync
description: 在 GreatLottoGroup 4 仓工作区做本地一键部署(起 hardhat 链 + 部署 infrastructure/ScratchCard/Core + 回填地址 + 同步 ABI),或单独跑跨仓地址同步 / ABI 同步到 interface。当需要起本地链联调、把新部署的合约地址回填到下游参数与 address.json、或把合约 ABI 同步到前端时使用。
---

# deploy-local-and-sync —— 本地一键部署 + 跨仓地址/ABI 同步

这个 skill 自包含本套脚本(脚本本体就在本目录),是这套工具的唯一事实源。
设计动机见 [../../doc/local-deploy-and-address-sync-design.md](../../doc/local-deploy-and-address-sync-design.md)(讲「为什么」);本文件讲「怎么用」。

> **路径基准**:所有命令以 **`infrastructure/` 为 cwd**;脚本以**工作区根**(`infrastructure/` 的上级、4 仓父目录)为基准访问 ScratchCard / GreatLottoCore / interface。

| 文件 | 作用 |
|------|------|
| `deploy.config.json` | 网络注册表 + 地址映射(加链/加合约只改这里) |
| `sync-core.mjs` | 纯函数核心(单测覆盖) |
| `sync-addresses.mjs` | 地址同步 CLI |
| `sync-abi.mjs` | ABI 同步 CLI(三仓 artifact → interface) |
| `abi-core.mjs` | ABI 纯函数核心(单测覆盖) |
| `abi.config.json` | ABI 映射(加/改合约 abi 改这里) |
| `deploy-local.sh` | 一键本地部署(仅 31337) |
| `test/` | 核心纯函数单测(`npm run test:scripts`) |

## 场景 1 —— 一键本地部署

前置:三仓已装依赖,且 ScratchCard / GreatLottoCore 的 `node_modules/@greatlotto/infrastructure` 软链接在位。

```bash
cd infrastructure
bash skills/deploy-local-and-sync/deploy-local.sh
```

它会:清三仓 `chain-31337` 旧部署 → 起 `hardhat node` → 部署 infrastructure → 同步地址到两仓 `localhost.json` → 部署 ScratchCardLocal + GreatLottoCoreLocal → 回填 `interface/src/app/launch/address.json` 的 `31337` 块(含 MockEntropy) → 同步三仓 ABI 到 interface(本地变体:GLC=GreatLottoCoinTest)。

跑完**本地链保留运行**(interface dev 需要);停止用结尾打印的 `kill <pid>`。失败/Ctrl-C 会自动拆掉节点。

## 场景 2 —— 单独跑地址同步(任意网络)

```bash
cd infrastructure

# dry-run(默认):只打印 diff,不写文件
node skills/deploy-local-and-sync/sync-addresses.mjs --network baseSepolia

# 落盘:非本地网络会先要求交互输入 yes 确认
node skills/deploy-local-and-sync/sync-addresses.mjs --network baseSepolia --write

# CI / 跳过确认
node skills/deploy-local-and-sync/sync-addresses.mjs --network baseSepolia --write --yes

# 只同步部分目的地
node skills/deploy-local-and-sync/sync-addresses.mjs --network localhost --write --only sc,core
node skills/deploy-local-and-sync/sync-addresses.mjs --network localhost --write --only interface
```

- `localhost` 网络:`--write` 直接落盘,无需确认。
- 非本地网络:`--write` 默认要交互确认(防误改含真实地址的参数文件);`--yes` 跳过。
- `--network` 接受网络名(`localhost`/`baseSepolia`/…)或 chainId(`31337`/`84532`/…)。

典型测试网流程:先 `ignition deploy` 三仓 → 再 `node skills/deploy-local-and-sync/sync-addresses.mjs --network <net> --write` 回填下游参数与 interface。

## 场景 3 —— 单独跑 ABI 同步

把三仓 hardhat 编译产物(`artifacts/`)里的合约 ABI 抽取(只取 `.abi` 数组)写到 `interface/src/app/abi/`。

```bash
cd infrastructure

# dry-run(默认):打印每文件状态(新建/变更/无变化/缺失/孤儿),不写
node skills/deploy-local-and-sync/sync-abi.mjs

# 落盘
node skills/deploy-local-and-sync/sync-abi.mjs --write

# 非本地变体(影响 GreatLottoCoin:base/arbitrum 取生产合约,localhost 取 Test)
node skills/deploy-local-and-sync/sync-abi.mjs --network base --write
```

- `--network` 可选,默认 `localhost`,**仅影响带变体的 mapping(目前只有 `GreatLottoCoin`)**;其余合约 ABI 与网络无关。
- 前置:对应仓已 `npx hardhat compile`(artifact 缺失会告警并跳过该文件)。`deploy-local.sh` 里 `ignition deploy` 已隐式编译,故一键流程无需额外编译。
- **孤儿告警**:abi 目录里既不在 `abi.config.json` 映射、又不在 `external` 白名单的文件(历史死件,如 `Callable.json`)会被列出,**只报告不删**。

## 加 / 改一个合约 ABI

改 `abi.config.json` 的 `mappings`:`file`(interface 目标文件名)+ `source`(`scratchcard`/`core`/`infrastructure`)+ `artifact`(`artifacts/` 下相对路径,不含 `.json`)。有 Test/生产变体的用 `variants.{local,remote}` 代替 `artifact`。

## 加一条链 / 加一个合约

只改 `deploy.config.json`:

- **加链**:在 `networks` 加一项(chainId / scModule / coreModule / local);确保各仓有同名 `ignition/parameters/<network>.json`。
- **加合约**:在 `mappings` 加一项(`logical` / `source` / `keys` / `targets`)。`keys` 是 `deployed_addresses.json` 里的 ignition key 数组,按序匹配(用于容忍 Test/生产合约别名)。

## 跑核心单测

```bash
cd infrastructure && npm run test:scripts   # node --test 跑 test/ 下纯函数单测
```

## 常见错误

| 现象 | 原因 / 处理 |
|------|------------|
| `缺 @greatlotto/infrastructure 软链接` | 在对应仓 `pnpm i` 或 `npm link @greatlotto/infrastructure` |
| `hardhat node 30s 未就绪` | 端口被占:`lsof -i:8545`;或看 `skills/deploy-local-and-sync/.hardhat-node.log` |
| 部署 ScratchCardLocal 时 `grantRole` revert | account#0 须持 GLC/DaoCoin 的 `DEFAULT_ADMIN_ROLE`(本地补授权前提) |
| 同步告警 `未解析到 <合约>` | 该仓 `chain-<id>` 未部署,或 `deploy.config.json` 的 `keys` 与 ignition key 不符 |
| 测试网误跑 `--write` | 默认会交互确认;未输入 `yes` 不会写 |
| `sync-abi` 全量 `missing` | 对应仓未 `npx hardhat compile`(无 artifacts) |

## 已知坑(非本工具范围)

- `interface address.json[31337].payToken` 硬编码主网稳定币,本地链上不存在;本地真实支付币是 `GreatLottoCoinTest`。
- interface 仅一个 `PrizePoolContractAddress`,本工具默认指向 **Core** 奖池;ScratchCard 奖池若前端需要,需先在 `address.json` 新增字段再补 mapping。
