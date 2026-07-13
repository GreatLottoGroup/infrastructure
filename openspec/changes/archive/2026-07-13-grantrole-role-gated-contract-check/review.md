status: approved

# 方案 Review — grantrole-role-gated-contract-check

- 日期：2026-07-13
- 审查人：独立方案 reviewer（非本 change 作者）
- 审查对象：`openspec/changes/grantrole-role-gated-contract-check/`（proposal / design / tasks / specs）+ 实际合约 `contracts/base/AccessControlPartnerContract.sol` + `IErrorsBase.sol` + 现有测试 `test/foundry/AccessControlPartnerContract.t.sol`
- 结论：**approved**（6 维全 PASS；两条非阻塞改进建议见文末）

---

## 核验到的事实（用于支撑各维判定）

- 全工作区（infra + ScratchCard + GreatLottoCore）仅存在一个自定义角色 `PARTNER_CONTRACT_ROLE`；无任何合约定义其它自定义角色 → design D1「用 `role == PARTNER_CONTRACT_ROLE` 相等判断而非映射/白名单」的前提成立。
- 全工作区仅有一处 `grantRole` override（即本基类）。
- 继承本基类的合约（按 grep）：`GreatLottoCoin` / `SalesChannel` / `PrizePoolBase`（其下 ScratchCard.PrizePool、GreatLottoCore.PrizePool）/ `ScratchCardNFT` / `GreatLottoNFT` / `InvestmentPosition`。
- 现有 spec 中 **无任何** 定义本基类 grantRole 强制机制的 requirement。`sales-channel` spec（L108-110）仅有运营口径不变量「`PARTNER_CONTRACT_ROLE` MUST 只授予经审计合约、绝不授予 EOA」——本 change **保留**该不变量（PARTNER 分支仍走 `_isContract`），未与之冲突。
- 合约 L13 构造函数确用内部 `_grantRole` → 绕过 public override，spec「构造期初始 admin 不受守卫影响」属实。
- tasks 引用的下游位点均真实存在：`doc/entropy-consumer-base-design.md` L455 的 grantRole 描述、`GreatLottoCore/test/foundry/InvestmentPosition.t.sol` L18-20 注释、interface `adminRoleM.js` L66/L105-108 的 `contractOnly` badge（在用）、`eoaWarning`（i18n 中定义但源码未引用，属死键）；`contractOnly` 与 `eoaWarning` 两键在全部 7 份 locale 中均存在（task 5.2 覆盖正确）。
- `.claude-workspace/coordination/` 下无本 topic 的协调文档。

---

## D1 Scope 单一 — PASS

change 只解决一件事：把 `grantRole` 的「被授予者必须是合约」校验按角色 gate 到 `PARTNER_CONTRACT_ROLE`。tasks 中的文档更正（3.x）与 interface 收尾（5.x）都是同一行为变更的直接涟漪（删除因放宽而失准的旧描述/旧 UI 文案），版本 bump 属记账，不构成第二个目标。

## D2 Breaking 标注 — PASS

- proposal 诚实标注「**BREAKING（运行时行为，非 ABI）**」，且方向为**放宽**（此前 revert 的调用现在成功），对既有调用方向后兼容；函数选择器/签名不变，下游无需重新同步 ABI，与 Impact 一致。
- **ADDED-新能力 建模正确**：经核验现有 6 份 spec 中无任何 requirement 定义本基类 grantRole 的强制机制；旧的「所有角色都拒 EOA」是从未落 spec 的实现细节。`sales-channel` 的 PARTNER-绝不-EOA 不变量被本 change 保留而非修改。故不存在应被 MODIFIED 的既有 spec；以 ADDED 新建 `access-control-partner-contract` 能力、并在 proposal「Modified Capabilities」显式声明「无：现有 spec 均未 owning 本基类 grantRole 行为」，是准确建模。
- **下游无未吸收的破坏**：ScratchCard 无源码改动、PARTNER 测试不受影响；GreatLottoCore 仅一处注释更正；interface 的 `contractOnly` badge 会因放宽而失准（但只是 UI 文案偏差，非功能破坏），其吸收任务（5.1/5.2）已在本 change 内。仅在测试网/本地存在「重部署 vs 去 badge」的短暂顺序窗口，主网未部署、无资金面，风险低且 Migration Plan step 4 已将二者同批排期。

## D3 决策覆盖 tasks — PASS（含 1 条轻微 gap 提示）

- D1（按角色 gate）→ task 1.1 ✓
- D2（新建 capability spec）→ 交付物即 `specs/access-control-partner-contract/spec.md`，并由 task 7.1 `openspec validate --strict` 把关 ✓
- D3（版本 0.1.2 → 0.1.3）→ task 1.2 ✓（现 package.json 仍为 0.1.2，待实现时改）
- 测试 tasks 2.1/2.2 精确对应 spec 新增的两个 Scenario（EOA-admin 成功、admin-零地址 revert），2.3 钉住现有 PARTNER 用例。
- 轻微 gap：task 3.1（entropy-consumer-base-design.md L455 文档更正）与 3.2（GreatLottoCore 测试注释更正）在 design.md 的 Decisions / Migration Plan 中未被点名，仅作为 doc-only 涟漪出现在 tasks。核心决策全部落 task，故不判 FAIL；建议在 design.md Migration Plan 补一行提及这两处文档同步（见文末）。

## D4 跨仓一致性 — PASS（含协调文档取舍说明）

- 下游 follow-up 齐备且依赖顺序正确：Migration Plan 排序为「改合约 → infra forge test → 下游 ScratchCard/GreatLottoCore 回归 → /security-review → interface 去 badge/i18n + 测试网重部署」，无功能性倒序风险（interface 收尾在 infra 行为放宽前后均可工作，无 ABI 依赖）。
- **是否需独立协调文档 / 独立 interface change 的判断**：按工作区约定「≥2 仓落代码」本 change 确属跨仓，惯例是建 `.claude-workspace/coordination/<topic>.md` + 每仓独立 change/worktree。但此处下游落地仅为 (a) 注释更正与 (b) 纯外观 UI + i18n 死键清理，**无 ABI/事件/接口变化、无功能耦合**，协调文档的核心价值（跨仓依赖图/worktree 隔离）在此边际很低。因此把 interface 收尾折进本 change 的 tasks.md **是充分的**，无需强制拆出独立 interface OpenSpec change。判 PASS；是否补一份轻量协调文档属可选（见文末建议）。

## D5 不可逆 / 资金风险 — PASS

- 本 change **不触及** entropy fee / 奖池清零 / burn-mint 配对 / pending 推进 / 任何资金或不可逆路径，纯访问控制 grantRole gating，无状态迁移、无回退负担（回滚仅还原单文件 + 版本）。
- 放宽 DEFAULT_ADMIN_ROLE 授予的安全性论证完整：① **调用方门禁**——仍受 `onlyRole(getRoleAdmin(role))` 约束，仅现任管理员可授（design Risks 显式点出）；② **PARTNER 不变量保留**——`role == PARTNER_CONTRACT_ROLE` 分支原样保留 `_isContract`，正反测试双向钉住；③ **无 admin-bricking**——放宽仅**扩大**可接受被授予者集合，不移除任何管理能力，`revokeRole`/`renounceRole`/构造初始 admin 均不动；④ **零地址防呆保留**——显式否决了「纯 OZ 把两检查都塞进 PARTNER 分支」的备选（那会允许 admin 误设为 `0x0`），零地址守卫保持全局。
- task 6.1 仍要求 `/security-review`，方案 review 不越俎代庖替代安全 review，路由正确。

## D6 替代方案 — PASS

design.md D1 明确记录并否决了两组备选，正是本维应覆盖的：① 「纯 OZ：零地址与合约地址两检查都放进 PARTNER 分支」→ 否决理由「会允许把管理员误设成 0x0」；② 「role→bool 映射 / 虚函数钩子 / 可配置白名单」→ 否决理由「仅一个角色需要该限制且不预期新增，role 相等比较最小最易审计；白名单为不存在的需求增加治理面」。两组理由充分。

---

## 非阻塞改进建议（不影响 approved 结论）

1. **design.md（可选）**：在 Migration Plan 或 Impact 补一行点名 task 3.1/3.2 两处 doc-only 文档同步（entropy-consumer-base-design.md L455 + GreatLottoCore InvestmentPosition.t.sol 注释），消除 D3 的轻微 design↔tasks gap。
2. **proposal.md（trivial）**：正文称「继承本基类的 7 个合约」，design.md 具名列了 6 个（把抽象基类 `PrizePoolBase` 记为一项、未展开其两个具体 PrizePool 子类）。二者口径统一即可，无正确性影响。
3. **协调文档（可选）**：如严格遵循工作区「≥2 仓 = 跨仓走 `.claude-workspace/coordination/`」惯例，可补一份轻量 `coordination/<topic>.md` 记录 infra→interface 的重部署顺序；鉴于下游为 doc + 外观改动、无 ABI 耦合，此项价值边际低，不做亦可。
