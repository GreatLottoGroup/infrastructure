# coin-base-stable-only Specification

## Purpose
TBD - created by archiving change remove-eth-payment-track. Update Purpose after archive.
## Requirements
### Requirement: 仅保留稳定币资产币

`infrastructure` 层 SHALL 仅提供一种资产币合约 `GreatLottoCoin`（GLC），SHALL NOT 部署 `GreatLottoEth` 或任何 wrap/unwrap 原生 ETH 的合约。

#### Scenario: 稳定币铸造路径

- **WHEN** 持有 `PARTNER_CONTRACT_ROLE` 的合作合约调用 `GreatLottoCoin.mint(token, amount, payer)`
- **AND** `token` 在 GLC 白名单（USDT 或 USDC）中
- **THEN** SHALL 从 `payer` 转入 `amount` 该 token 并 mint 等额 GLC 给调用方

#### Scenario: ETH 路径不再可用

- **WHEN** 任意调用方尝试 import `IGreatLottoEth` 或调用 `GreatLottoEth.wrap()`
- **THEN** 编译期 SHALL 报错（接口与实现已删除）

### Requirement: 白名单仅含 USDT 与 USDC

`GreatLottoCoin._tokens` SHALL 仅包含 USDT 与 USDC 两个地址（mainnet：`0xdAC17F958D2ee523a2206206994597C13D831ec7` / `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`）；DAI（mainnet `0x6B175474E89094C44Da98b954EedeAC495271d0F`、sepolia `0x68194a729C2450ad26072b3D33ADaCbcef39D574`）SHALL 从所有网络的数组与注释中移除。

#### Scenario: DAI 已下线

- **WHEN** 任何调用方将 DAI 地址传入 `mint(token, amount, payer)` / `mint(token, amount, payer, deadline, v, r, s)` / `withdraw(token, amount)`
- **THEN** SHALL revert `ErrorUnsupportedToken(token)`（白名单不命中）

#### Scenario: recover 不再遍历 DAI

- **WHEN** owner 调用 `recover()`
- **THEN** 内部循环 `_tokens` 时 SHALL 仅遍历 USDT、USDC 两个地址；DAI 余额不参与差额铸币计算

#### Scenario: 白名单可用性约束

- **WHEN** 部署后任意调用方调用 `checkToken(USDT)` / `checkToken(USDC)`
- **THEN** SHALL 返回 `true`
- **AND** `checkToken(DAI)` / `checkToken(任何非白名单地址)` SHALL 返回 `false`

### Requirement: permit 入口仅保留标准 EIP-2612 分支

`GreatLottoCoin.mint(token, amount, payer, deadline, v, r, s)` SHALL 直接调用 `selfPermitIfNecessary(payer, token, getAmount(token, amount), deadline, v, r, s)`，SHALL NOT 包含基于 `_tokens[2]` 或任何 token 地址比较的 DAI/CHAI 风格 `selfPermitAllowedIfNecessary` 分支。

#### Scenario: USDC permit 铸造

- **WHEN** 合作合约通过 `mint(token, amount, payer, deadline, v, r, s)` 调用，`token` 为 USDC，签名有效
- **THEN** SHALL 走 `selfPermitIfNecessary` 完成 EIP-2612 permit 后再扣款 mint

#### Scenario: USDT 走非 permit 入口

- **WHEN** 用户走 USDT 入金时
- **THEN** SHOULD 调用 `mint(token, amount, payer)` 三参版本（先 `approve`）；调用 permit 版本会因 USDT 主网无 EIP-2612 而 revert（与 GLC 合约本身行为无关）

### Requirement: SelfPermit 服务剩余稳定币

`SelfPermit.selfPermit` 与 `selfPermitIfNecessary` SHALL 保留，用于支持 USDC 等标准 ERC20Permit 稳定币的免授权批量交易。具体的接口契约由 [self-permit-eip2612-only](#) capability 进一步约束。

#### Scenario: 标准 EIP-2612 入口仍可调用

- **WHEN** 调用方携带 USDC 的有效 EIP-2612 签名调用 `GreatLottoCoin.mint(token, amount, payer, deadline, v, r, s)`
- **THEN** SHALL 走 `selfPermitIfNecessary` 完成 permit 后扣款 mint，全程不需 `approve` 单独交易

