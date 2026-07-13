# access-control-partner-contract Specification

## Purpose
TBD - created by archiving change grantrole-role-gated-contract-check. Update Purpose after archive.
## Requirements
### Requirement: grantRole 按角色 gate 合约地址校验

`AccessControlPartnerContract` SHALL override `grantRole(bytes32 role, address account)`，在委托给 `super.grantRole` 之前施加两级校验，且「被授予者必须是合约地址」这一级 **仅** 对 `PARTNER_CONTRACT_ROLE` 生效：

1. **零地址守卫（全局，所有角色）**：`account == address(0)` 时 MUST revert `ErrorZeroAddress()`。
2. **合约地址守卫（仅 `PARTNER_CONTRACT_ROLE`）**：当 `role == PARTNER_CONTRACT_ROLE` 且 `account` 不是合约（`_isContract` 判定 `code.length > 1000` 为 false）时 MUST revert `ErrorInvalidAddress(account)`。
3. 其它角色（含 `DEFAULT_ADMIN_ROLE`）MUST NOT 受合约地址守卫约束——可授予 EOA / 多签，与原生 OpenZeppelin `AccessControl` 行为一致。

调用方权限仍由 `onlyRole(getRoleAdmin(role))` 强制（仅相应角色的管理员可授予）。`revokeRole` / `renounceRole` MUST NOT 被 override（沿用 OZ 原生实现，接受任意地址）。构造函数中的初始 `DEFAULT_ADMIN_ROLE` 授予经内部 `_grantRole` 完成，MUST NOT 经过本 override（即部署期初始 admin 设定不受这些守卫影响）。

#### Scenario: 授予 PARTNER_CONTRACT_ROLE 给合约成功

- **GIVEN** 调用方持有 `DEFAULT_ADMIN_ROLE`（`PARTNER_CONTRACT_ROLE` 的角色管理员）
- **AND** `account` 是一个 `code.length > 1000` 的合约地址
- **WHEN** 调用 `grantRole(PARTNER_CONTRACT_ROLE, account)`
- **THEN** MUST 成功，`hasRole(PARTNER_CONTRACT_ROLE, account)` 为 true

#### Scenario: 授予 PARTNER_CONTRACT_ROLE 给 EOA revert

- **GIVEN** 调用方持有 `DEFAULT_ADMIN_ROLE`
- **AND** `account` 是一个 EOA（无合约代码）
- **WHEN** 调用 `grantRole(PARTNER_CONTRACT_ROLE, account)`
- **THEN** MUST revert `ErrorInvalidAddress(account)`

#### Scenario: 授予 PARTNER_CONTRACT_ROLE 给不足字节阈值的合约 revert

- **GIVEN** `account` 是一个 `code.length > 0` 但 `<= 1000` 的合约
- **WHEN** 调用 `grantRole(PARTNER_CONTRACT_ROLE, account)`
- **THEN** MUST revert `ErrorInvalidAddress(account)`

#### Scenario: 授予 DEFAULT_ADMIN_ROLE 给 EOA 成功

- **GIVEN** 调用方持有 `DEFAULT_ADMIN_ROLE`
- **AND** `account` 是一个 EOA（无合约代码）
- **WHEN** 调用 `grantRole(DEFAULT_ADMIN_ROLE, account)`
- **THEN** MUST 成功，`hasRole(DEFAULT_ADMIN_ROLE, account)` 为 true（管理员可转移/追加给 EOA/多签）

#### Scenario: 任意角色授予零地址 revert

- **GIVEN** 调用方持有对应角色的管理员权限
- **WHEN** 调用 `grantRole(role, address(0))`（无论 role 是 `PARTNER_CONTRACT_ROLE` 还是 `DEFAULT_ADMIN_ROLE`）
- **THEN** MUST revert `ErrorZeroAddress()`

#### Scenario: 非管理员调用 grantRole revert

- **GIVEN** 调用方不持有 `getRoleAdmin(role)`
- **WHEN** 调用 `grantRole(role, account)`
- **THEN** MUST revert `AccessControlUnauthorizedAccount(caller, getRoleAdmin(role))`

#### Scenario: 构造期初始 admin 不受守卫影响

- **WHEN** 部署继承 `AccessControlPartnerContract` 的合约，构造参数 `owner_` 为一个 EOA
- **THEN** 该 EOA MUST 持有 `DEFAULT_ADMIN_ROLE`（初始授予经内部 `_grantRole`，绕过 public override 的守卫）

