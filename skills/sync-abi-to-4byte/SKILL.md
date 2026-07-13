---
name: sync-abi-to-4byte
description: 把 GreatLottoGroup 三仓(infrastructure / ScratchCard / GreatLottoCore)主合约的 ABI 提交到 www.4byte.directory 公共签名库(函数选择器 + 事件签名),让区块浏览器能反解本项目交易的 calldata / 日志;并把实际提交内容刷新为本地 interface/src/app/abi/4byte.directory/ 快照做留档。当合约接口变更后要重新登记签名、或首次向 4byte 登记时使用。
---

# sync-abi-to-4byte —— 提交三仓主合约签名到 4byte.directory

这个 skill 自包含本套脚本(脚本本体就在本目录),是这套工具的唯一事实源。
它做两件事:① 把合约 ABI 里的函数/事件签名 POST 到公共库 [4byte.directory](https://www.4byte.directory)(浏览器靠它把 `0x` calldata / 日志 topic 反解成人类可读签名);② 把实际提交的裸 ABI 数组刷新到 `interface/src/app/abi/4byte.directory/` 做可审计快照。

> **路径基准**:所有命令以 **`infrastructure/` 为 cwd**;脚本以**工作区根**(`infrastructure/` 的上级、4 仓父目录)为基准访问 ScratchCard / GreatLottoCore / interface。

| 文件 | 作用 |
|------|------|
| `4byte.config.json` | 声明式配置:端点 + 本地快照目录 + 仓路径表 + 提交合约清单(加/改合约只改这里) |
| `4byte-core.mjs` | 纯函数核心(无 IO / 无网络,`node --test` 覆盖) |
| `submit-4byte.mjs` | CLI:读 artifact.abi → 计数 + 比对快照 → dry-run / `--write` / `--submit` |
| `test/4byte-core.test.mjs` | 核心纯函数单测 |

## 前置

对应仓已 `npx hardhat compile`(读 `artifacts/` 的 `.abi`;缺 artifact 会告警并跳过该合约,不影响其余)。4byte API **无需鉴权**。

## 场景 1 —— dry-run(默认,纯离线)

打印每合约的函数/事件/错误签名计数 + 本地快照状态(新建/变更/无变化/缺失)+ 快照目录里的孤儿(历史死件),**不联网、不写盘**。

```bash
cd infrastructure
node skills/sync-abi-to-4byte/submit-4byte.mjs
```

## 场景 2 —— 只刷新本地快照(可逆,不联网)

把三仓最新 `.abi` 写到 `interface/src/app/abi/4byte.directory/`(只写「新建/变更」,幂等)。用于准备/预览要提交的内容,或单纯让本地留档跟上合约。

```bash
cd infrastructure
node skills/sync-abi-to-4byte/submit-4byte.mjs --write
```

## 场景 3 —— 真提交到 4byte(对外、不可逆)

逐个合约 POST 到 4byte.directory,打印每合约返回的 `imported / duplicates / ignored` 计数;**同时隐含刷新本地快照**(快照 = 实际提交内容)。因为是对公共库的不可撤销写入,默认要交互输入 `yes` 确认;CI / 免确认加 `--yes`。

```bash
cd infrastructure

# 交互确认后提交全部合约
node skills/sync-abi-to-4byte/submit-4byte.mjs --submit

# 免确认(CI)
node skills/sync-abi-to-4byte/submit-4byte.mjs --submit --yes

# 只提交部分合约(逗号分隔,用 config 里的 name)
node skills/sync-abi-to-4byte/submit-4byte.mjs --submit --only ScratchCard.json,GreatLotto.json
```

- 首次提交多为 `imported`;重跑同一 ABI 应几乎全 `duplicates`(4byte 全局去重,重复提交无害)。
- 抽查是否登记成功:`curl 'https://www.4byte.directory/api/v1/signatures/?text_signature=<某函数签名>'`。
- **提交前 ABI 会自动净化**(`sanitizeAbiForImport`):4byte 校验器只认 `function`/`event`,原样含 `type:"error"` 会整包报 400「Could not validate ABI」。自定义 error 与 function 共用同一 4-byte 选择器,故 error 被改标为 function 一并提交(浏览器据此反解 revert);`constructor`/`receive`/`fallback` 无选择器被丢弃。**本地快照写的就是这份净化后的 ABI,与实际提交给 4byte 的内容逐字节一致**(便于 diff 核对提交内容);计划表里的 `fn/ev/err` 计数仍按原始 ABI 展示,方便看清合约签名构成。

## 加 / 改一个提交合约

改 `4byte.config.json` 的 `contracts`:`name`(本地快照文件名)+ `source`(`infrastructure`/`scratchcard`/`core`)+ `artifact`(该仓 `artifacts/` 下相对路径,不含 `.json`)。清单与同级 `deploy-local-and-sync/abi.config.json` 有意分离(本工具面向真实上链的生产合约,GLC 取生产版 `GreatLottoCoin` 而非 Test,且不提交 Pyth 的 `IEntropyV2`)。

## 跑核心单测

```bash
cd infrastructure && npm run test:scripts   # node --test 跑 skills 下所有 *-core 单测
```

## 常见错误

| 现象 | 原因 / 处理 |
|------|------------|
| 某合约标「⚠️ 缺失」 | 对应仓未 `npx hardhat compile`(无 artifacts),或 `4byte.config.json` 的 `artifact` 路径写错;告警跳过,不影响其余合约 |
| `--submit` 后无提交 | 交互未输入 `yes`(取消);或全部合约缺 artifact |
| 某合约提交 `❌ HTTP 4xx/5xx` 或网络错误 | 逐个跳过继续,末尾进程非零退出;检查网络 / 稍后重试(4byte 幂等,重跑安全) |
| 「⚠️ 孤儿」告警 | 快照目录里既非本工具生成、又是 `.json` 的历史死件(如 `Callable.json` / `GreatLottoEth.json` / `DAOCoin.json`);**只报告不删**,清理属 interface 仓议题 |

## 备选方案(本工具不采用)

4byte 支持在仓库配 GitHub webhook,每次 push 自动拉取源码解析签名。但本工作区合约仓私有、且我们要「curl 式主动、按需」同步生产合约,故采用 ABI 主动提交(`/api/v1/import-abi/`)而非 webhook / 源码解析。
