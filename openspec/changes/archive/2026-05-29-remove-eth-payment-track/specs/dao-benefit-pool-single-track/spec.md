# dao-benefit-pool-single-track

## ADDED Requirements

### Requirement: 分润合约仅支持稳定币（GLC）

`DaoBenefitPool` SHALL 仅持有并分发 `GreatLottoCoin` 余额，SHALL NOT 引用 `GreatLottoEth` 或任何原生 ETH 余额。

#### Scenario: 单币种分润执行

- **WHEN** 任意账户调用 `executeBenefit(deadline)` 且 `block.timestamp <= deadline`
- **AND** 合约的 GLC 余额 > 0
- **THEN** SHALL 按 `DaoCoin.getBeneficiaryList()` 与 `getBenefitAmount` 比例转账 GLC 给所有受益人
- **AND** SHALL emit `BenefitExecuted(executor, totalBenefitAmount)`（参数中不再包含 `bool isEth`）

#### Scenario: 无利润 revert

- **WHEN** GLC 余额为 0 时调用 `executeBenefit(deadline)`
- **THEN** SHALL revert `BenefitPoolNoBenefit`

### Requirement: 构造参数收敛

`DaoBenefitPool` 的构造函数 SHALL 接收 `(address coinAddr, address daoCoinAddr)` 两个参数，SHALL NOT 接收 `ethAddr` 或独立的 `governEth`。`GreatLottoCoinAddress` 与 `GovernCoinAddress` 设置后即 immutable。

#### Scenario: 双参数构造

- **WHEN** 部署脚本以 `new DaoBenefitPool(coinAddr, daoCoinAddr)` 实例化
- **THEN** SHALL 成功部署，且 `GreatLottoCoinAddress` / `GovernCoinAddress` 在后续生命周期中不可变更

#### Scenario: 旧三参数签名不复存在

- **WHEN** 使用旧 `new DaoBenefitPool(coinAddr, ethAddr, daoCoinAddr)` 三参数签名调用
- **THEN** SHALL 编译失败（构造函数 ABI 不匹配）
