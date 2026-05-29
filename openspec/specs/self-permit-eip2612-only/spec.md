# self-permit-eip2612-only Specification

## Purpose
TBD - created by archiving change remove-eth-payment-track. Update Purpose after archive.
## Requirements
### Requirement: SelfPermit 仅暴露 EIP-2612 分支

`SelfPermit` 抽象合约 SHALL 仅暴露 `selfPermit` 与 `selfPermitIfNecessary` 两个 EIP-2612 标准函数。`selfPermitAllowed` 与 `selfPermitAllowedIfNecessary` 这两个 DAI/CHAI 风格的 `(holder, spender, nonce, expiry, allowed, v, r, s)` permit 入口 SHALL 从合约与 `ISelfPermit` 接口中删除。

#### Scenario: EIP-2612 permit 仍可用

- **WHEN** 调用方携带有效 EIP-2612 签名调用 `selfPermitIfNecessary(owner, token, value, deadline, v, r, s)`
- **AND** `IERC20(token).allowance(owner, address(this)) < value`
- **THEN** SHALL 触发 `IERC20Permit(token).permit(owner, address(this), value, deadline, v, r, s)`

#### Scenario: DAI/CHAI 风格入口已下线

- **WHEN** 任意调用方尝试调用 `selfPermitAllowed(...)` 或 `selfPermitAllowedIfNecessary(...)` selector
- **THEN** SHALL 因函数不存在而由 fallback 拒绝（合约无 fallback 时 EVM 直接 revert）
- **AND** 编译期任何 import 这两个函数的合约 SHALL 报错

### Requirement: IERC20PermitAllowed 接口已删除

`contracts/interfaces/IERC20PermitAllowed.sol` SHALL 从源码与编译产物中移除；任何引用该接口的下游代码 SHALL 重构为标准 `IERC20Permit`，否则编译失败。

#### Scenario: 接口文件已下线

- **WHEN** 下游合约 `import "@greatlotto/infrastructure/contracts/interfaces/IERC20PermitAllowed.sol"`
- **THEN** SHALL 编译失败（文件不存在）

### Requirement: 不再依赖 token 地址区分 permit 路径

`GreatLottoCoin.mint(... permit args)` 与未来任何 `SelfPermit` 派生合约 SHALL NOT 通过 `if(token == _tokens[i])` 或类似硬编码判定切换 permit 类型。permit 行为 SHALL 由 `IERC20Permit` 接口语义决定，不可 permit 的 token（如主网 USDT）SHALL 由调用方走非 permit 入口。

#### Scenario: GLC mint permit 入口无 token 分支

- **WHEN** 审阅 `GreatLottoCoin.mint(token, amount, payer, deadline, v, r, s)` 实现
- **THEN** 函数体 SHALL 仅含一次 `selfPermitIfNecessary(...)` 调用 + `_depositFor(...)`，SHALL NOT 出现 `if(token == _tokens[N])` 或基于 token 地址的分支

