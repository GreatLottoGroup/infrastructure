# ABI 同步到 interface 设计方案

> 状态:已评审通过(brainstorming 定稿),待 `writing-plans` 出实现计划
> 日期:2026-06-14
> 作者:kiritoweb3 + Claude
> 范围:GreatLottoGroup 4 仓工作区(infrastructure / ScratchCard / GreatLottoCore / interface)
> 关联:本方案是 [local-deploy-and-address-sync-design.md](./local-deploy-and-address-sync-design.md) 的姊妹件——地址同步管「部署产物地址」,本方案管「编译产物 ABI」。

## 1. 背景与目标

interface 经 `import X from '@/abi/X.json'` 消费各合约 ABI(文件位于 `interface/src/app/abi/*.json`,内容是**裸 ABI 数组**,非完整 hardhat artifact)。当前痛点:

- ABI 靠手工从各仓 `artifacts/contracts/<Sol>/<Name>.json` 拷 `.abi` 字段过去,合约接口一改就要逐个手动同步,极易漏(现状里多个文件停留在 2024-12,早已过时)。
- 文件名与合约名/源仓存在错位(`DAOCoin.json` ← `DaoCoin.sol`)、同名不同物(两个 `PrizePool`)、变体歧义(`GreatLottoCoin` vs 部署用的 `GreatLottoCoinTest`),手工同步时这些都是坑。
- interface abi 目录里还混着**已无对应合约的过时件**(`Callable` / `ExecutorReward` / `GreatLottoEth` / `BeneficiaryBase`)与**纯外部 ABI**(`permit_abi` / `usdt_abi` / `dai_abi` / `4byte.directory/`),无人能一眼看清哪些该同步、哪些是死件。

**目标**:

1. **独立可调用**:一条命令 `node scripts/sync-abi.mjs --write` 把三仓所有需要的合约 ABI 抽取并写到 interface,接口变更后随时重跑。
2. **集成进一键本地部署**:并入 [deploy-local.sh](../scripts/deploy-local.sh),本地联调时地址 + ABI 一并刷新。
3. **暴露死件**:同步之余报告 interface abi 目录里的「孤儿文件」(既非映射目标、又非已知外部件),把历史漂移显性化。

与地址同步**正交**:地址同步依赖部署产物 `deployed_addresses.json`,本方案只依赖编译产物 `artifacts/`,与具体链无关(唯一例外是 GLC 变体选择,见 §4)。

## 2. 关键决策(评审已定)

| # | 决策点 | 结论 |
|---|--------|------|
| A1 | 映射表之外的文件 | **同步 + 报告孤儿**:只写映射内的活合约;扫描 abi 目录,把「既不在 `mappings.file` 也不在 `external` 白名单」的 `.json` 列为孤儿告警(只报告不删) |
| A2 | ScratchCard 的 PrizePool ABI | **新增 `ScratchCardPrizePool.json`**:interface 现有的 `PrizePool.json` 维持指向 Core 奖池;ScratchCard 奖池(分离后)单列新文件 |
| A3 | GreatLottoCoin ABI 源 | **跟随部署变体**:`localhost` 取 `GreatLottoCoinTest`,非本地取生产 `GreatLottoCoin`(`--network` 判定) |
| A4 | 配置位置 | **独立 `abi.config.json`**:abi 映射与地址映射(`deploy.config.json`)物理分离;网络注册表仍单一事实源在 `deploy.config.json`,被本脚本复用 |

## 3. 架构

沿用地址同步的「纯函数核心 + CLI 外壳 + 声明式配置」三分:

```
infrastructure/scripts/
  ├─ abi.config.json        ← 声明式配置:abi 映射清单 + external 白名单
  ├─ abi-core.mjs           ← 纯函数:变体解析 / 孤儿分类 / diff 判定(无 IO,node --test 覆盖)
  ├─ sync-abi.mjs           ← CLI 外壳:读 artifact.abi → 比对 → dry-run/--write 落盘 → 报告
  ├─ test/abi-core.test.mjs ← node --test 单测
  └─ (既有)deploy.config.json / sync-core.mjs / sync-addresses.mjs / deploy-local.sh
```

三者职责:

- **`abi.config.json`** —— 声明「interface 的哪个 abi 文件,从哪个仓的哪个 artifact 取」。加/改合约只改这里。
- **`abi-core.mjs`** —— 纯读写普通对象:给定 mapping + 网络,解析出应取的 artifact 相对路径(处理变体);给定目录文件清单,分出孤儿;给定新旧 ABI,判是否变更。环境无关、可单测。
- **`sync-abi.mjs`** —— 定位工作区根、读 artifact 的 `.abi`、比对现有 interface 文件、打印每文件状态、`--write` 时落盘。

路径基准与地址同步一致:脚本以**工作区根**(`infrastructure/` 上级、4 仓父目录)为基准,经 `<scriptDir>/../..` 解析各仓。

> **网络注册表单一事实源**:local/remote 判定所需的 `networks`(chainId → `local` bool)仍只在 `deploy.config.json`。`sync-abi.mjs` 读 `deploy.config.json` 取网络注册表 + 读 `abi.config.json` 取 abi 映射,不复制网络表。

## 4. 组件 1:`abi.config.json`(映射清单)

```jsonc
{
  "interfaceAbiDir": "interface/src/app/abi",
  "mappings": [
    // ── ScratchCard 仓 ──
    { "file": "ScratchCard.json",         "source": "scratchcard", "artifact": "contracts/ScratchCard.sol/ScratchCard" },
    { "file": "ScratchCardNFT.json",       "source": "scratchcard", "artifact": "contracts/ScratchCardNFT.sol/ScratchCardNFT" },
    { "file": "ScratchCardPrizePool.json", "source": "scratchcard", "artifact": "contracts/PrizePool.sol/PrizePool" },   // 决策 A2 新增
    { "file": "IEntropyV2.json",           "source": "scratchcard", "artifact": "@pythnetwork/entropy-sdk-solidity/IEntropyV2.sol/IEntropyV2" },

    // ── GreatLottoCore 仓 ──
    { "file": "PrizePool.json",            "source": "core", "artifact": "contracts/PrizePool.sol/PrizePool" },          // 维持指向 Core 奖池
    { "file": "GreatLotto.json",           "source": "core", "artifact": "contracts/GreatLotto.sol/GreatLotto" },
    { "file": "GreatLottoNFT.json",        "source": "core", "artifact": "contracts/GreatLottoNFT.sol/GreatLottoNFT" },
    { "file": "InvestmentCoinBase.json",   "source": "core", "artifact": "contracts/base/InvestmentCoinBase.sol/InvestmentCoinBase" },

    // ── infrastructure 仓 ──
    { "file": "DAOCoin.json",              "source": "infrastructure", "artifact": "contracts/DaoCoin.sol/DaoCoin" },     // 文件名/合约名错位,显式映射
    { "file": "SalesChannel.json",         "source": "infrastructure", "artifact": "contracts/SalesChannel.sol/SalesChannel" },
    { "file": "BenefitPoolBase.json",      "source": "infrastructure", "artifact": "contracts/base/BenefitPoolBase.sol/BenefitPoolBase" },

    // ── GLC:跟随部署变体(决策 A3)──
    { "file": "GreatLottoCoin.json",       "source": "infrastructure",
      "variants": { "local":  "contracts/test/GreatLottoCoinTest.sol/GreatLottoCoinTest",
                    "remote": "contracts/GreatLottoCoin.sol/GreatLottoCoin" } }
  ],

  // 纯外部 / 手维护 ABI:不同步、不报孤儿。`4byte.directory` 为目录,整体跳过。
  "external": ["permit_abi.json", "usdt_abi.json", "dai_abi.json", "4byte.directory"]
}
```

### 4.1 artifact 解析规则

每条 mapping 解析为绝对路径:

```
<工作区根>/<repos[source]>/artifacts/<artifact>.json   →  读其 .abi 字段
```

其中 `repos` 复用 `deploy.config.json` 已有的仓路径表(`infrastructure` / `scratchcard` / `core`)。`artifact` 字段是 hardhat artifact 在 `artifacts/` 下的相对路径(不含 `.json`),形如 `contracts/<Sol>/<Name>` 或 `@pythnetwork/.../<Name>`(`IEntropyV2` 即在 node_modules 依赖下,编译后落 `artifacts/@pythnetwork/...`)。

> 已逐一核对(2026-06-14):上表 12 条映射的 artifact 路径在各仓 `artifacts/` 下均存在。`IEntropyV2` 取自 ScratchCard 仓的 `artifacts/@pythnetwork/...`(infrastructure 仓亦有,二者同源,任取其一)。

### 4.2 变体解析(决策 A3)

带 `variants` 的 mapping(目前仅 `GreatLottoCoin`):按 `--network` 解析出的 `network.local` 选 `variants.local` 或 `variants.remote`。无 `variants` 的 mapping 用 `artifact` 字段,与网络无关。

## 5. 组件 2:`sync-abi.mjs`(CLI 外壳)

### 5.1 调用约定

```bash
node infrastructure/scripts/sync-abi.mjs [--network <name|chainId>] [--write]
```

| 参数 | 含义 |
|------|------|
| `--network` | 可选,默认 `localhost`。**仅影响带 `variants` 的 mapping(GLC)的变体选择**,其余合约 ABI 与网络无关 |
| `--write` | 真正写文件。缺省为 dry-run(只打印每文件状态) |

无 `--yes` 闸门:ABI 是代码派生物、非敏感地址,不需要非本地交互确认(与地址同步的写入闸门差异点)。

### 5.2 主流程

```
1. 解析 --network(默认 localhost)→ 从 deploy.config.json 的 networks 取 { local }
2. 载入 abi.config.json + deploy.config.json 的 repos
3. 对每条 mapping:
     a. 变体解析 → artifact 相对路径
     b. 读 <root>/<repo>/artifacts/<artifact>.json
        缺文件 → 标记「⚠️ artifact 缺失」,跳过(提示去该仓 npx hardhat compile),不写空
     c. 取 .abi → newText = JSON.stringify(abi, null, 2) + "\n"
     d. 读现有 interface/<interfaceAbiDir>/<file>:
        不存在 → 状态「新建」
        内容 != newText → 状态「变更」
        相同 → 状态「无变化」
4. 孤儿扫描(决策 A1):列 interfaceAbiDir 下所有 .json,
     凡既不在 mappings.file、又不在 external → 状态「⚠️ 孤儿」(只报告)
5. 打印每文件状态汇总
6. 未带 --write → 结束(dry-run)
   带 --write → 仅对「新建 / 变更」的 mapping 文件落盘(孤儿、external、缺失件均不动)
```

### 5.3 写入安全细则

- **只碰映射目标**:孤儿文件、`external` 白名单、`4byte.directory/` 目录一律不写不删。
- **绝不写空**:artifact 缺失或 `.abi` 为空时跳过该文件,保留 interface 现有内容(避免把已有 ABI 刷成空)。
- **格式对齐**:`JSON.stringify(abi, null, 2) + "\n"`,2 空格缩进 + 末尾换行,与现有 abi 文件一致。
- **幂等**:无变更时不写、状态全「无变化」。

## 6. 组件 3:集成进 `deploy-local.sh`

ABI 只依赖编译产物,而三仓 `ignition deploy` 已隐式编译。在现有**步骤 7(同步三仓地址 → interface)之后**新增一步:

```bash
# 7b) 同步三仓 ABI → interface(本地变体:GLC=GreatLottoCoinTest)
log "同步 ABI → interface..."
node "$SCRIPT_DIR/sync-abi.mjs" --network localhost --write
```

要点:

- 放在地址同步之后、收尾之前;此时三仓已编译(部署即编译),artifact 必新鲜。
- 本地 `--network localhost` ⇒ GLC 取 Test 变体,与本地实际部署的 `GreatLottoCoinTest` 一致(决策 A3)。
- 不新增预检/拆链逻辑:沿用既有 `set -euo pipefail` + trap,sync-abi 非零退出即触发现有失败处理。

## 7. 组件 4:`abi-core.mjs` 纯函数(可单测)

| 导出 | 职责 |
|------|------|
| `parseArgs(argv)` | 解析 `--network` / `--write`(network 缺省 `localhost`) |
| `resolveArtifactRel(mapping, network)` | 带 `variants` → 按 `network.local` 选;否则返回 `mapping.artifact` |
| `classifyDir(fileNames, mappings, external)` | 返回 `{ orphans }`:既不在 `mappings.file`、又不在 `external` 的文件名 |
| `abiText(abi)` | `JSON.stringify(abi, null, 2) + "\n"`(统一格式化口径) |
| `statusOf(newText, oldTextOrNull)` | `"新建" / "变更" / "无变化"` |

`sync-abi.mjs` 负责一切 IO(读 artifact、读 abi 目录、写文件),调用上述纯函数;`abi-core.mjs` 不碰文件系统,便于 `node --test` 覆盖。

## 8. 错误处理汇总

| 场景 | 表现 | 处理 |
|------|------|------|
| 某仓未编译 / artifact 缺失 | 读 `artifacts/<artifact>.json` 失败 | 标「⚠️ artifact 缺失」,跳过该文件,提示去对应仓 `npx hardhat compile`,非致命 |
| abi 目录有死件 | —— | 「⚠️ 孤儿」告警,只报告不删(`Callable` / `ExecutorReward` / `GreatLottoEth` / `BeneficiaryBase` 等) |
| `.abi` 字段为空 / 缺失 | —— | 跳过该文件,不覆盖已有内容 |
| `artifact` 路径写错(配置漂移) | 同「artifact 缺失」 | 告警暴露,提示核对 `abi.config.json` 的 `artifact` 与实际编译产物 |

## 9. 验收标准

- [ ] `node scripts/sync-abi.mjs`(不带 `--write`)打印每文件状态(新建/变更/无变化/缺失/孤儿),不改任何文件。
- [ ] `node scripts/sync-abi.mjs --write` 后再跑一次 dry-run,所有映射文件状态为「无变化」(幂等)。
- [ ] `ScratchCard.json` / `ScratchCardNFT.json` / `ScratchCardPrizePool.json`(新增)/ `IEntropyV2.json` 内容与各仓 artifact 的 `.abi` 一致。
- [ ] `DAOCoin.json` 取自 `DaoCoin.sol`、`GreatLottoCoin.json` 在 `--network localhost` 下取自 `GreatLottoCoinTest`、在 `--network base` 下取自 `GreatLottoCoin`。
- [ ] 孤儿告警列出 abi 目录里的死件;`permit_abi`/`usdt_abi`/`dai_abi`/`4byte.directory` 不出现在孤儿列表(已在 `external`)。
- [ ] `deploy-local.sh` 跑完,interface abi 目录里映射文件均与三仓最新编译产物一致。
- [ ] `npm run test:scripts` 通过(含新增 `abi-core.test.mjs`)。

## 10. YAGNI 边界(本方案不做)

- **不自动 `hardhat compile`**:三仓编译慢且意外;artifact 缺失只告警,由使用者自行编译。
- **不删孤儿、不改 interface 源码 import**:死件清理是 interface 仓独立议题,本工具只暴露不处置。
- **不解决 `payToken` 本地稳定币占位**:见地址同步方案 §8 item 1,独立议题。
- **GLC 之外暂不引入变体**:目前只有 GLC 有 Test/生产分叉;若将来更多合约出现变体,沿用 `variants` 字段扩展即可。

## 11. 关联文档

- [local-deploy-and-address-sync-design.md](./local-deploy-and-address-sync-design.md) —— 姊妹方案(地址同步),网络注册表与仓路径表的事实源
- [local-deploy-and-address-sync-plan.md](./local-deploy-and-address-sync-plan.md) —— 地址同步实现计划(本方案的 `writing-plans` 产物将与之并列)
- 本仓脚本目录:[../scripts/](../scripts/)(脚本 + 配置落此)
- 工作区协调层:`.claude-workspace/CLAUDE.md`(跨仓约定参考)
