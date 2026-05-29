# Tasks

## 1. 合约删除

- [x] 1.1 删除 `contracts/GreatLottoEth.sol`
- [x] 1.2 删除 `contracts/interfaces/IGreatLottoEth.sol`
- [x] 1.3 删除 `contracts/test/GreatLottoEthTest.sol`
- [x] 1.4 在 `contracts/test/PartnerTest.sol` 中删除 GLETH 相关 partner 入口
- [x] 1.5 删除 `contracts/interfaces/IERC20PermitAllowed.sol`

## 2. DaoCoin 单价格收敛

- [x] 2.1 `DaoCoin.sol`：删除 `coinPriceEth`；`mintToUser(account, assets)`、`changePrice(price)` 单签名
- [x] 2.2 `IDaoCoin.sol`：同步删除 isEth 参数与 event 字段
- [x] 2.3 单元测试：验证 `mintToUser` 仅按 `coinPrice` 计算 shares；旧 isEth=true 调用应 compile-error / revert

## 3. BenefitPool 单轨收敛

- [x] 3.1 `base/BenefitPoolBase.sol`：删除 `GreatLottoEthAddress` / `GovernEthAddress`；`executeBenefit(uint deadline)` 单签名；event 收敛
- [x] 3.2 `interfaces/IBenefitPoolBase.sol`：同步签名
- [x] 3.3 `DaoBenefitPool.sol`：构造改为 `(coinAddr, daoCoinAddr)`
- [x] 3.4 单元测试：覆盖单币种分润 + revert 场景

## 4. GreatLottoCoin DAI 收敛

- [x] 4.1 `contracts/GreatLottoCoin.sol`：mainnet `_tokens` 数组移除 DAI（保留 USDT + USDC），sepolia 注释行同步收敛
- [x] 4.2 删除 `mint(token, amount, payer, deadline, v, r, s)` 中 `if(token == _tokens[2]) selfPermitAllowedIfNecessary(...)` 分支，统一走 `selfPermitIfNecessary`
- [x] 4.3 单元测试：DAI 地址传入 `mint` / `withdraw` revert `ErrorUnsupportedToken`；USDC permit 路径继续工作

## 5. SelfPermit / ISelfPermit 收敛

- [x] 5.1 `contracts/base/SelfPermit.sol`：删除 `selfPermitAllowed` / `selfPermitAllowedIfNecessary`，删除 `import '../interfaces/IERC20PermitAllowed.sol'`
- [x] 5.2 `contracts/interfaces/ISelfPermit.sol`：同步删除两个 DAI 风格函数声明
- [x] 5.3 单元测试：`selfPermitAllowed(...)` selector 调用应 revert（fallback 不存在或 selector 不匹配）

## 6. Ignition / 部署

- [x] 6.1 `ignition/modules/infrastructure.js`：删除 `greatLottoEth` 部署与 return 字段；`DaoBenefitPool` 构造收敛
- [x] 6.2 在本地 hardhat node 演练部署成功

## 7. 测试与文档

- [x] 7.1 `test/runTest/*.js`：删除 ETH wrap/unwrap、isEth=true、DAI permit 用例；补"GLETH 已下线"、"DAI 已下线"、"`selfPermitAllowed` 不存在"的负向断言
- [x] 7.2 `test/utils/getCoin.js`：删除 `DAI_ADDRESS` / `getDAICoin` / `approveDAICoin` / `DAI_DECIMALS` / `DAI_ABI` 等导出；删除 `test/abi/dai_abi.json` 与 `test/abi/weth_abi.json`；同步清理 `getCoin.js` 内 WETH 相关 helper
- [x] 7.3 `test/utils/permitUtils.js`：删除 `if(token == DAI_ADDRESS)` 分支
- [x] 7.4 `test/scripts/initTestCoin.js` / `approveTestCoin.js`：删除 DAI 调用
- [x] 7.5 `npx hardhat test test/runTest/*.js` 全绿（34 用例 passing）
- [x] 7.6 `npx hardhat coverage` 覆盖率不低于改造前基线（statements 98.6% / functions 96.2% / lines 95.2%）
- [x] 7.7 更新 `CLAUDE.md`：移除 `GreatLottoEth` / `GLETH` / `coinPriceEth` / DAI 描述
- [~] 7.8 ~~更新 `WhitePaper_EN.md` / `WhitePaper_ZH.md`：DAI 表述刷新为 USDT + USDC~~ — **跨仓挪移**：WhitePaper 文件位于 `GreatLottoCore` 仓库，已转入 `GreatLottoCore/openspec/changes/drop-eth-investment-and-prizepool-track/tasks.md` §7.2

## 8. 验收

- [x] 8.1 在 `openspec/changes/remove-eth-payment-track/specs/` 四个 capability 文档已落地（含新增 `self-permit-eip2612-only`）
- [x] 8.2 跨仓方案 §3 的 "阶段 A 验收" 项全部勾选（编译 ✓ / 34 用例全绿 ✓ / coverage 不降 ✓ / 部署演练 ✓ / `checkToken` 三态校验 ✓）
- [x] 8.3 部署后 `checkToken(USDT) === true && checkToken(USDC) === true && checkToken(DAI) === false` ✓（在 `GreatLottoCoin` 主合约上验证，非 Test 子类）
