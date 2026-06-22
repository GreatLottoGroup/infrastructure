## ADDED Requirements

### Requirement: admin 受上限约束增铸份额

`SalesVault` SHALL 继承 OpenZeppelin `AccessControl`，构造时 SHALL `_grantRole(DEFAULT_ADMIN_ROLE, owner_)`，使 `owner_` 成为唯一初始管理员（构造仍 `_mint(owner_, MAX_SHARES)`，`MAX_SHARES` 不变）。

`SalesVault` SHALL 暴露 `adminMint(uint256 shares, address to)`（参数顺序对齐 ERC4626 `mint(shares, receiver)`），`onlyRole(DEFAULT_ADMIN_ROLE)`。该函数 SHALL 在铸造前以 `maxMint(to)` 校验额度：当 `shares > maxMint(to)` 时 MUST revert（`ERC4626ExceededMaxMint`），否则 `_mint(to, shares)`。因此 `adminMint` SHALL NOT 使 `totalSupply()` 超过 `MAX_SHARES`，即 admin 增铸受与公众申购同一条 1 亿硬上限约束；满额时 `adminMint` MUST revert。

`adminMint` 是免费铸造（不收取 `to` 任何对价），仅由 `redeem` 腾出额度后用于把份额补回，实现「持有人提收益（烧份额）后不丧失股权」。

#### Scenario: admin 在腾出额度内增铸

- **GIVEN** 某持有人已 `redeem` 使 `totalSupply() < MAX_SHARES`，腾出额度 `R = MAX_SHARES - totalSupply()`
- **AND** 调用方持有 `DEFAULT_ADMIN_ROLE`
- **WHEN** 调用 `adminMint(to, s)` 且 `s <= R`
- **THEN** MUST 成功 `_mint(to, s)`，`balanceOf(to)` 增加 `s`，不收取 `to` 任何 GLC
- **AND** 铸后 `totalSupply()` MUST NOT 超过 `MAX_SHARES`

#### Scenario: 满额时 adminMint revert

- **GIVEN** `totalSupply() == MAX_SHARES`（如部署后初始状态）
- **AND** 调用方持有 `DEFAULT_ADMIN_ROLE`
- **WHEN** 调用 `adminMint(to, s)`，`s > 0`
- **THEN** `maxMint(to)` MUST 返回 0
- **AND** MUST revert（`ERC4626ExceededMaxMint`）

#### Scenario: 超额增铸 revert

- **GIVEN** 腾出额度 `R = MAX_SHARES - totalSupply()`，`R > 0`
- **AND** 调用方持有 `DEFAULT_ADMIN_ROLE`
- **WHEN** 调用 `adminMint(to, s)` 且 `s > R`
- **THEN** MUST revert（`ERC4626ExceededMaxMint`），`totalSupply()` 不变

#### Scenario: 非 admin 调用 revert

- **GIVEN** 调用方不持有 `DEFAULT_ADMIN_ROLE`
- **WHEN** 调用 `adminMint(to, s)`
- **THEN** MUST revert（`AccessControlUnauthorizedAccount`）

#### Scenario: 部署即授予 owner 管理员角色

- **WHEN** `SalesVault` 部署，构造参数 `owner_`
- **THEN** `hasRole(DEFAULT_ADMIN_ROLE, owner_)` MUST 为 `true`

## REMOVED Requirements

### Requirement: 纯无特权——无 owner 后门

**Reason**: 本变更为解决「提收益（`redeem` 烧份额）即丧失股权」痛点，新增受 `maxMint` 上限约束的 admin 专属增铸入口 `adminMint`，故金库不再「纯无特权、无任何 owner 后门」。

**Migration**: `SalesVault` 现继承 `AccessControl`，`owner_` 持 `DEFAULT_ADMIN_ROLE` 并可调用 `adminMint`（受 1 亿硬上限约束、免费铸、仅在 `redeem` 腾额后可铸）。仍 SHALL NOT 存在绕过份额比例直接转走金库 GLC 的 `sweep`/`rescue` 函数，亦 SHALL NOT 存在突破 `MAX_SHARES` 的增铸路径——admin 的唯一特权是在硬上限内增铸份额。
