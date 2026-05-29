# dao-coin-pricing-single-track

## ADDED Requirements

### Requirement: DaoCoin 单一定价

`DaoCoin` SHALL 维护单一价格 `coinPrice`（默认 `1 * 10**18`，即 1 USD 锚定 1 GLDC），SHALL NOT 维护 `coinPriceEth` 或任何按支付币种分叉的价格。

#### Scenario: mintToUser 计算 shares

- **WHEN** 持有 `PARTNER_CONTRACT_ROLE` 的合作合约调用 `mintToUser(account, assets)`
- **THEN** SHALL 按 `shares = assets * 10**decimals() / coinPrice` 计算并 `_mint(account, shares)`

#### Scenario: changePrice 单参数

- **WHEN** `DEFAULT_ADMIN_ROLE` 调用 `changePrice(price)` 且 `price > 0`
- **THEN** SHALL 更新 `coinPrice = price` 并 emit `PriceChanged(price)`（无 `isEth` 字段）

#### Scenario: 无效价格 revert

- **WHEN** `changePrice(0)`
- **THEN** SHALL revert `ErrorInvalidAmount(0)`

### Requirement: 旧 isEth 签名不再可用

`mintToUser(address, uint256, bool)` 与 `changePrice(uint256, bool)` SHALL 从 `IDaoCoin` 接口与实现中移除；任何继承自此接口的下游合约编译时 SHALL 出现链接错误而非静默兼容。

#### Scenario: 三参数 mintToUser 已删除

- **WHEN** 下游合约调用 `daoCoin.mintToUser(account, assets, isEth)`
- **THEN** SHALL 编译失败（selector 不存在）

#### Scenario: 双参数 changePrice 已删除

- **WHEN** 下游合约调用 `daoCoin.changePrice(price, isEth)`
- **THEN** SHALL 编译失败（selector 不存在）
