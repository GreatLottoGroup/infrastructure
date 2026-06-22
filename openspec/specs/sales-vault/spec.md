# sales-vault Specification

## Purpose

`SalesVault` 是承载销售利润的 ERC4626 金库：底层资产币为 GLC，份额固定硬上限 1 亿，部署时一次性全部铸给 owner。销售分润不再「遍历受益人主动打款」，而是由 `PrizePoolBase` 经标准 `transfer` 把 GLC 打入金库地址——抬高 `totalAssets` 而不动 `totalSupply`，使每份额对应资产按比例自动增值。金库对所有份额持有人无门槛开放标准 `redeem`/`withdraw`，并开放公众现价 `deposit`/`mint`（受 1 亿硬上限约束、`_decimalsOffset()=6` 防 inflation attack），份额可自由二级流转，取代旧 `DaoBenefitPool` 的主动分发模型。金库继承 `AccessControl`，owner 持 `DEFAULT_ADMIN_ROLE`，唯一特权入口 `adminMint` 可在 1 亿硬上限内免费增铸份额（用于持有人 `redeem` 烧份额后补回股权）；除此之外无 `adminBurn`/没收、无 `sweep`/`rescue` 资金后门、无 `pause`。

## Requirements

### Requirement: 金库为 ERC4626，资产币 GLC

`SalesVault` SHALL 继承 OpenZeppelin `ERC4626`，其底层 `asset()` SHALL 等于构造时传入的 GLC 地址。金库 SHALL NOT 在内部对收到的 GLC 再做 `getAmount` 放大——金库账本以底层 wei 级 GLC 计量，与 `PrizePoolBase` 转入侧的 wei 单位贯通。

#### Scenario: 部署设定资产币

- **GIVEN** 构造参数 `(asset_, owner_)`，`asset_` 为 GLC 地址
- **WHEN** `SalesVault` 部署
- **THEN** `asset()` MUST 返回 `asset_`

#### Scenario: 份额代币元数据

- **WHEN** 查询金库 ERC20 元数据
- **THEN** `name()` / `symbol()` MUST 返回固定的份额币名称与符号（如 `GreatLotto Sales Vault` / `GLSV`）

### Requirement: 份额硬上限 1 亿 + owner 初始全持

`SalesVault` SHALL 定义常量 `MAX_SHARES = 100_000_000 * 1e18`。构造时 SHALL 一次性 `_mint(owner_, MAX_SHARES)`，使初始 `totalSupply() == MAX_SHARES` 且 owner 持有全部份额。

#### Scenario: 部署即铸满给 owner

- **WHEN** `SalesVault` 部署，构造参数 `owner_`
- **THEN** `totalSupply()` MUST 等于 `MAX_SHARES`
- **AND** `balanceOf(owner_)` MUST 等于 `MAX_SHARES`

#### Scenario: MAX_SHARES 与 GLC 小数对齐

- **WHEN** 读取 `MAX_SHARES`
- **THEN** MUST 等于 `100_000_000 * 1e18`（1 亿份，18 位小数，与 GLC 底层小数一致）

### Requirement: 销售分润经转入自动增值

`SalesVault` SHALL 依赖标准 ERC4626 `totalAssets()`（= `asset().balanceOf(vault)`）实现分润：外部（PrizePool）向金库地址 `transfer` GLC 会抬高 `totalAssets`、不改变 `totalSupply`，使每份额对应资产按 `convertToAssets(shares)` 比例增值。金库 SHALL NOT 提供任何「主动遍历受益人逐个打款」式的分发函数。

#### Scenario: 转入抬升单份额价值

- **GIVEN** 初始 `totalSupply == MAX_SHARES`、`totalAssets == A`
- **WHEN** 外部向金库 `transfer` `B` 个 wei 级 GLC（B > 0）
- **THEN** `totalAssets()` MUST 增加 `B`
- **AND** `totalSupply()` MUST 不变
- **AND** 任一持有人的 `convertToAssets(balanceOf(holder))` MUST 按比例增加

#### Scenario: 无主动分发入口

- **WHEN** 检视金库对外函数
- **THEN** MUST NOT 存在 `executeBenefit` 或等价的「遍历受益人列表打款」函数

### Requirement: 标准 redeem/withdraw 对所有份额持有人开放

`SalesVault` SHALL 保留 ERC4626 标准 `redeem` / `withdraw`，对所有份额持有人无门槛开放，按当前比例提走 GLC 并 `_burn` 对应份额。份额 SHALL 可经标准 ERC20 `transfer` 二级流转，无转让限制。

#### Scenario: 按比例赎回

- **GIVEN** 持有人 `h` 持有 `s` 份额，金库 `totalAssets == A`、`totalSupply == S`
- **WHEN** `h` 调用 `redeem(s, h, h)`
- **THEN** MUST 向 `h` 转出约 `convertToAssets(s)` 个 GLC
- **AND** `totalSupply()` MUST 减少 `s`

#### Scenario: 份额可二级流转

- **GIVEN** owner 持有全部份额
- **WHEN** owner 调用 `transfer(other, x)`
- **THEN** MUST 成功，`balanceOf(other)` 增加 `x`，`other` 此后可独立 `redeem`

### Requirement: 开放公众现价申购，受 1 亿硬上限约束

`SalesVault` SHALL 开放标准 ERC4626 公众 `deposit` / `mint`，按当前 `totalSupply/totalAssets` 比例给份额（现价申购，稳态下不稀释现有持有人、不白嫖存量分润）。`SalesVault` SHALL override `maxMint(address)` 返回 `MAX_SHARES - totalSupply()`（顶满时 0），并 override `maxDeposit(address)` 返回其对应 assets 换算值，使任何会令 `totalSupply` 超过 `MAX_SHARES` 的申购被 OpenZeppelin 标准上限校验拒绝。

#### Scenario: 顶满时禁止申购

- **GIVEN** `totalSupply() == MAX_SHARES`（如部署后初始状态）
- **WHEN** 任意账户调用 `deposit(amount, receiver)` 或 `mint(shares, receiver)`，amount/shares > 0
- **THEN** `maxMint(receiver)` MUST 返回 0，`maxDeposit(receiver)` MUST 返回 0
- **AND** 申购 MUST revert（`ERC4626ExceededMaxMint` / `ERC4626ExceededMaxDeposit`）

#### Scenario: redeem 腾出额度后可申购

- **GIVEN** 某持有人已 `redeem` 使 `totalSupply() < MAX_SHARES`，腾出额度 `R = MAX_SHARES - totalSupply()`
- **WHEN** 账户按现价 `mint(s, receiver)` 且 `s <= R`
- **THEN** MUST 成功铸出 `s` 份额，收取对应现价 GLC
- **AND** 铸后 `totalSupply()` MUST NOT 超过 `MAX_SHARES`

#### Scenario: 现价申购不稀释现有持有人

- **GIVEN** 金库已累积分润使单份额价值 > 初始（`totalAssets/totalSupply` 抬升），且存在腾出的申购额度
- **WHEN** 新账户按现价 `deposit(assets, receiver)`
- **THEN** 其获得的份额 MUST 等于 `convertToShares(assets)`（现价比例）
- **AND** 现有持有人的 `convertToAssets(balanceOf(holder))` MUST NOT 因该申购而下降

### Requirement: virtual shares 防 inflation attack

`SalesVault` SHALL override `_decimalsOffset()` 返回 `6`，借 OpenZeppelin ERC4626 的 virtual shares/assets 机制，将「supply 被赎到极低时抢首存 + 捐赠抬价吞掉后续存入者本金」的 inflation attack 成本抬到不可行。

#### Scenario: offset 生效

- **WHEN** 读取 `_decimalsOffset()`（或经 `decimals()` 推断）
- **THEN** MUST 反映 offset = 6（份额小数 = 资产小数 + 6）

#### Scenario: 极低 supply 下抵御抢跑

- **GIVEN** 经大额 `redeem` 使 `totalSupply()` 降至极低，攻击者抢先 `deposit` 极小额、再直接向金库捐赠大额 GLC 抬高单份额价格
- **WHEN** 正常用户随后按现价 `deposit` 合理金额
- **THEN** 正常用户获得的份额 MUST NOT 因取整被吞为 0（virtual shares 吸收取整误差）
- **AND** 攻击者 MUST NOT 通过该序列净获利

### Requirement: admin 受上限约束增铸份额

`SalesVault` SHALL 继承 OpenZeppelin `AccessControl`，构造时 SHALL `_grantRole(DEFAULT_ADMIN_ROLE, owner_)`，使 `owner_` 成为唯一初始管理员（构造仍 `_mint(owner_, MAX_SHARES)`，`MAX_SHARES` 不变）。

`SalesVault` SHALL 暴露 `adminMint(uint256 shares, address receiver)`（参数顺序对齐 ERC4626 `mint(shares, receiver)`），`onlyRole(DEFAULT_ADMIN_ROLE)`。该函数 SHALL 在铸造前以 `maxMint(receiver)` 校验额度：当 `shares > maxMint(receiver)` 时 MUST revert（`ERC4626ExceededMaxMint`），否则 `_mint(receiver, shares)`。因此 `adminMint` SHALL NOT 使 `totalSupply()` 超过 `MAX_SHARES`，即 admin 增铸受与公众申购同一条 1 亿硬上限约束；满额时 `adminMint` MUST revert。

`adminMint` 是免费铸造（不收取 `receiver` 任何对价），仅由 `redeem` 腾出额度后用于把份额补回，实现「持有人提收益（烧份额）后不丧失股权」。

金库除 `adminMint` 外 SHALL NOT 暴露其他 owner/admin 专属入口：SHALL NOT 存在绕过份额比例直接转走金库 GLC 的 `sweep`/`rescue`，SHALL NOT 存在没收持有人份额的 `adminBurn`，SHALL NOT 存在 `pause`，且 SHALL NOT 存在突破 `MAX_SHARES` 的增铸路径——admin 的唯一特权是在硬上限内增铸份额。

#### Scenario: admin 在腾出额度内增铸

- **GIVEN** 某持有人已 `redeem` 使 `totalSupply() < MAX_SHARES`，腾出额度 `R = MAX_SHARES - totalSupply()`
- **AND** 调用方持有 `DEFAULT_ADMIN_ROLE`
- **WHEN** 调用 `adminMint(s, receiver)` 且 `s <= R`
- **THEN** MUST 成功 `_mint(receiver, s)`，`balanceOf(receiver)` 增加 `s`，不收取 `receiver` 任何 GLC
- **AND** 铸后 `totalSupply()` MUST NOT 超过 `MAX_SHARES`

#### Scenario: 满额时 adminMint revert

- **GIVEN** `totalSupply() == MAX_SHARES`（如部署后初始状态）
- **AND** 调用方持有 `DEFAULT_ADMIN_ROLE`
- **WHEN** 调用 `adminMint(s, receiver)`，`s > 0`
- **THEN** `maxMint(receiver)` MUST 返回 0
- **AND** MUST revert（`ERC4626ExceededMaxMint`）

#### Scenario: 超额增铸 revert

- **GIVEN** 腾出额度 `R = MAX_SHARES - totalSupply()`，`R > 0`
- **AND** 调用方持有 `DEFAULT_ADMIN_ROLE`
- **WHEN** 调用 `adminMint(s, receiver)` 且 `s > R`
- **THEN** MUST revert（`ERC4626ExceededMaxMint`），`totalSupply()` 不变

#### Scenario: 非 admin 调用 revert

- **GIVEN** 调用方不持有 `DEFAULT_ADMIN_ROLE`
- **WHEN** 调用 `adminMint(s, receiver)`
- **THEN** MUST revert（`AccessControlUnauthorizedAccount`）

#### Scenario: 部署即授予 owner 管理员角色

- **WHEN** `SalesVault` 部署，构造参数 `owner_`
- **THEN** `hasRole(DEFAULT_ADMIN_ROLE, owner_)` MUST 为 `true`

#### Scenario: 无其他资金后门

- **WHEN** 检视金库对外函数
- **THEN** MUST NOT 存在绕过份额比例、由 owner/admin 直接转走金库 GLC 的函数（如 `sweep` / `rescue`），亦 MUST NOT 存在 `adminBurn` / `pause`
