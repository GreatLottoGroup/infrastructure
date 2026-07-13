## Context

`AccessControlPartnerContract`（`GreatLottoCoin`、`SalesChannel`、`PrizePoolBase`、`ScratchCardNFT`、`GreatLottoNFT`、`InvestmentPosition` 的基类）override 了 `grantRole`，强制被授予者必须是合约地址：

```solidity
function grantRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
    if(account == address(0)){ revert ErrorZeroAddress(); }
    else if(!_isContract(account)){ revert ErrorInvalidAddress(account); }
    super.grantRole(role, account);
}
```

其本意（`sales-channel` spec：PARTNER「绝不授予 EOA」）是让 `PARTNER_CONTRACT_ROLE` 只落在审计过的合约手里。但该守卫忽略了 `role`，于是连 `grantRole(DEFAULT_ADMIN_ROLE, <EOA>)` 也被挡下。初始 admin 在构造函数中经内部 `_grantRole` 授予（绕过本 override），所以部署可正常进行；守卫只在**部署后**转移/追加管理员时才发作——这恰恰是管理员转移流程需要的操作。

跨仓核验（infra + ScratchCard + GreatLottoCore）：`PARTNER_CONTRACT_ROLE` 是唯一必须保持合约地址约束的角色；无任何合约定义其它自定义角色；所有现存 EOA/零地址 `grantRole` revert 测试都针对 PARTNER；部署模块也只把 PARTNER 授予合约地址。下游经 symlink 消费 infra，故修复下次编译即生效、无需 republish；`grantRole` 签名不变，故无 ABI 变化。

## Goals / Non-Goals

**Goals:**
- `grantRole(DEFAULT_ADMIN_ROLE, <EOA 或多签>)` 在部署后可成功（支撑管理员转移）。
- `PARTNER_CONTRACT_ROLE` 继续拒绝非合约被授予者（不变量保留）。
- 任何角色都不得授予 `address(0)`（全局兜底守卫保留）。
- 对三仓所有现存测试与部署保持行为不变。

**Non-Goals:**
- 不动 `revokeRole` / `renounceRole`（从未 override；已接受任意地址）。
- 不新增角色、不改 `_setRoleAdmin`、不引入两步式管理员转移原语。
- 不改构造函数的初始 admin 授予。
- 不引入 `AccessControlEnumerable`（管理员枚举仍不在范围内）。

## Decisions

**D1 — 合约地址校验按角色 gate；零地址校验保持全局。**

```solidity
function grantRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
    if (account == address(0)) {
        revert ErrorZeroAddress();
    }
    // 仅 PARTNER_CONTRACT_ROLE 的被授予者必须是合约（EOA 永不可作 partner）。
    // 其它角色（含 DEFAULT_ADMIN_ROLE）可为 EOA/多签——与原生 OZ 一致。
    if (role == PARTNER_CONTRACT_ROLE && !_isContract(account)) {
        revert ErrorInvalidAddress(account);
    }
    super.grantRole(role, account);
}
```

- *为何零地址守卫保持全局（而非同样只在 PARTNER 分支）：* 对任意角色拒绝 `address(0)` 是一条零成本、普遍可取的防呆；保留它也让现有 `test_grantRole_revert_whenZeroAddress`（PARTNER）语义更宽。备选方案（纯 OZ：两条检查都放进 PARTNER 分支）已考虑并否决——那样会允许把管理员误设成 `0x0`。
- *为何用 role 相等判断，而非 role→bool 映射 / 虚函数钩子：* 只有一个角色需要该限制、也不预期新增；单个 `role == PARTNER_CONTRACT_ROLE` 比较是最小、最易审计的形式。可配置白名单会为当前不存在的需求增加治理面。

**D2 — 新建 `access-control-partner-contract` capability spec 归属。** 现无 spec owning 本基类的 `grantRole` 行为，故新增一个 capability spec 明确「按角色 gate 被授予者」规则。`sales-channel` 的「PARTNER 绝不授 EOA」不变量得以保留，并首次有了明确的上游归属。

**D3 — 版本 `0.1.2 → 0.1.3`。** 已发布基类的 public 运行时行为发生变化（放宽）。下游 pin `^0.1.2` 可接纳 `0.1.3`，故下游 `package.json` 无需改；bump 仅为记录/可追溯。

## Risks / Trade-offs

- [放宽管理员授予可能把管理员误设成非预期 EOA] → 这是 OZ 标准行为，且受 `onlyRole(getRoleAdmin(role))` 调用方门禁约束（只有现任管理员能授予）。管理员转移 UX（分步 授予→校验→撤销、确认弹窗）缓解操作失误；非合约层问题。
- [PARTNER 不变量被误放宽] → 显式 `role == PARTNER_CONTRACT_ROLE` 分支保留原检查；新增正向测试断言 EOA-admin 成功、同时现有 PARTNER-EOA-revert 测试保持全绿，两侧都被钉住。
- [已部署测试网字节码仍执行旧规则] → 行为仅在重新部署后改变；interface 收尾（去 badge）与测试网重部署一起排期。已文档化，非静默。
- [下游编译产物过期] → symlink 使下次 `forge`/`hardhat` 编译即拾取；验证会在 ScratchCard + GreatLottoCore 跑 `forge test`。

## Migration Plan

1. 改 `AccessControlPartnerContract.sol`；补 2 条测试；bump 版本。
2. infra 跑 `forge test`，再跑 ScratchCard + GreatLottoCore（经 symlink 回归）。
3. 对合约 diff 跑 `/security-review`（合约仓必跑）。
4. 连带 interface 收尾（去 `contractOnly` badge + `contractOnly`/`eoaWarning` i18n）+ 测试网/本地重新部署，使放宽行为上线。
5. 回滚：还原这一处单文件合约改动（及版本 bump）；因行为只是放宽接受面，无状态/迁移需要回退。

## Open Questions

- 无阻塞项。（是否额外把 `0.1.3` 发布到 registry，还是继续依赖 symlink，属运维偏好；当前工作区用 symlink 即可。）
