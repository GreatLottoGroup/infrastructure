## Why

`AccessControlPartnerContract.grantRole` 把「被授予者必须是合约地址」（`_isContract`，`code.length > 1000`）这条校验**无差别套在所有角色**上。该守卫本意只对 `PARTNER_CONTRACT_ROLE` 有意义（partner 调用方必须是审计过的合约、绝不能是 EOA）；无差别施加后连 `DEFAULT_ADMIN_ROLE` 也被卡住——owner 无法在部署后把管理员转移/追加给一个 EOA（或普通地址形态的多签）。此问题在做「管理员转移」前端面板时暴露：对继承本基类的 7 个合约调用 `grantRole(DEFAULT_ADMIN_ROLE, <EOA>)` 会 revert `ErrorInvalidAddress`。

## What Changes

- 把 `AccessControlPartnerContract.grantRole` 里的 `_isContract` 校验**按角色 gate**，仅在 `role == PARTNER_CONTRACT_ROLE` 时生效。其它角色（含 `DEFAULT_ADMIN_ROLE`）不再要求合约地址，与原生 OpenZeppelin `AccessControl` 一致。
- **零地址拒绝保持全局**：任何角色都不得授予 `address(0)`。
- **BREAKING（运行时行为，非 ABI）**：`grantRole(<非 PARTNER 角色>, <EOA>)` 现在会成功，此前会 revert `ErrorInvalidAddress`。函数选择器/签名不变 → 无 ABI 变化，下游无需重新同步接口。
- `revokeRole` / `renounceRole` 未被 override、保持不变（本就接受任意地址）。
- 补正/反向测试锁定新行为；包版本 `0.1.2 → 0.1.3`。

## Capabilities

### New Capabilities
- `access-control-partner-contract`：共享基类 `AccessControlPartnerContract` 的「按角色 gate 被授予者校验」——PARTNER 角色要求合约地址；所有角色拒绝零地址；其它角色沿用原生 AccessControl。

### Modified Capabilities
<!-- 无：现有 spec 均未owning 本基类的 grantRole 行为。sales-channel / prize-pool-base / coin-base 等 spec 里「PARTNER 绝不授 EOA」的不变量本次予以保留（PARTNER 仍受合约地址守卫）。 -->

## Impact

- **合约**：`contracts/base/AccessControlPartnerContract.sol`（`grantRole` override）。构造函数走内部 `_grantRole`，不受影响。
- **测试**：`test/foundry/AccessControlPartnerContract.t.sol`（+2 用例）。现有所有 EOA/零地址 revert 用例都针对 PARTNER，本仓与下游（ScratchCard / GreatLottoCore）均保持全绿。
- **下游（symlink `@greatlotto/infrastructure`）**：ScratchCard + GreatLottoCore 下次编译即生效，无需改源码。ABI 不变 → `interface` 的 ABI 不变。
- **interface（关联仓）**：管理员面板里「仅合约管理员 / EOA 会 revert」的 badge 与 `eoaWarning` 文案在重新部署后对 `DEFAULT_ADMIN_ROLE` 失准 → 作为连带收尾一并去除。测试网（arbitrumSepolia / 本地）需重新部署，放宽行为才生效。
- **治理**：需过 `/security-review`（合约仓必跑）。属访问控制放宽——review 需确认只解锁预期角色、PARTNER 仍受合约地址约束、零地址守卫仍在。
