status: approved
reviewed: 2026-06-22
reviewer: 独立方案 review（flow-review-spec，全新视角）
change: sales-vault-admin-mint (infrastructure)

# 方案 Review — sales-vault-admin-mint

## 结论

**status: approved**（6/6 PASS）。

提案 scope 单一、breaking 标注如实、决策全部落到 task、下游经核查确为零打穿、资金/硬上限风险论证充分且 `maxMint` 复用逻辑正确、替代方案均有记录。无需回到方案阶段。仅给出 2 条非阻塞的实现/收尾期建议（见末尾），不影响 approved 判定。

## 六维逐项

### D1 Scope 单一 — PASS

proposal/design/tasks/spec 全部只围绕「在 1 亿硬上限内新增 admin 增铸入口补回被 redeem 烧掉的份额」一件事。Non-Goals 明确排除 adminBurn / sweep / pause / claim 账本 / 调 MAX_SHARES / 改 offset。改动面 = 一个继承 + 构造一行授权 + 一个函数，无搭车改动。

### D2 Breaking 标注 — PASS

- spec delta 如实 REMOVED「纯无特权——无 owner 后门」（基线 spec.md L114-126 确有此 Requirement），并 ADDED「admin 受上限约束增铸份额」，Reason/Migration 完整。Migration 还正向声明残留保证（仍无 sweep/rescue、仍无突破 MAX_SHARES 的路径），delta 与基线一一对应、无遗漏。
- ERC165 `supportsInterface` 变化：proposal Impact + design D1 + Risks 均覆盖，并论证下游不查接口（经核查属实，见 D4）。
- 构造行为变化（新增 `_grantRole`）：spec ADDED 的「部署即授予 owner 管理员角色」Scenario 覆盖，构造 `_mint(owner_, MAX_SHARES)` 明确保留不变。
- 下游打穿：proposal 声称零打穿，经 grep 核验属实（D4），无需下游 change。
- 基线其余 5 个 Requirement（ERC4626/硬上限/转入增值/redeem/公众申购/virtual shares）均未被 delta 触碰，正确——本变更不动这些行为。

### D3 决策覆盖 tasks — PASS

- D1（AccessControl + DEFAULT_ADMIN_ROLE）→ task 1.1（继承）+ 1.2（构造授权）+ 2.1（hasRole 断言）+ 2.5（非 admin revert）。
- D2（adminMint 复用 maxMint 校验）→ task 1.3（实现）+ 2.2/2.3/2.4（满额 revert / 腾额后可铸 / 超额 revert）。
- D3（免费铸接受稀释）→ task 2.3 显式断言「不收 GLC」+ task 1.4（注释写明安全用法/多签）+ 3.3（安全 review 核查稀释语义）。
- 反向核查：未发现 task 落在 design 未提之处。task 1.5（体积/ERC165 无冲突）、2.6（ERC4626 回归）、2.7/3.x（覆盖率+三道门）均为 design Impact/Risks 的合理延伸，非新决策。

### D4 跨仓一致性 — PASS

- 经 grep：ScratchCard 与 GreatLottoCore 的 `PrizePool.sol` 仅把 `salesVaultAddress` 作构造参数传给 `PrizePoolBase`，运行期经 `_salesVaultTransfer` 做 `safeTransfer`。两仓 ignition 模块亦仅注入地址、明确「SalesVault 无 PARTNER 角色、无需授权」。无任何下游对 SalesVault 内部接口 / ERC165 / 「无 AccessControl」属性的依赖。
- interface 仓当前无 `SalesVault`/`GLSV` 引用（ABI 同步仍是 DAO→Vault 替换的后置任务）；本变更新增 `adminMint` 不破坏 ERC4626/ERC20 ABI，前端后续按 artifacts 同步即可，无须为本变更新建下游 change。
- 现有协调文档 `2026Q2-sales-vault-replace-dao.md` 是上一轮 DAO→SalesVault 替换主题，与本变更无关；本变更既为单仓零打穿，无需建新协调文档（符合「≥2 仓落代码才算跨仓」的门槛）。

### D5 不可逆/资金风险 — PASS

- 份额 = 分润股权，adminMint 确属铸资金凭证，风险面真实。design 正面论证三点：
  1. **不破 1 亿硬上限**：`adminMint` 复用 `maxMint(to)`，而 override 的 `maxMint` 返回 `MAX_SHARES - totalSupply()`（顶满返 0）。校验 `shares <= MAX_SHARES - totalSupply()` ⟹ 铸后 `totalSupply() <= MAX_SHARES`。逻辑正确，无绕过路径——`adminMint` 用 public `maxMint(to)` 而非裸 `_mint`，与公众申购同一上限。
  2. **稀释语义**：design D3 + Risks 明确「金库有存量收益时给新地址免费铸 = 当场稀释老持有人」，并给出 mitigation（合约硬上限封顶 + 注释/runbook 限死「仅 redeem 腾额后补回同一持有人」+ 多签）。承认这是治理纪律而非合约强制，态度诚实、边界清晰。
  3. **私钥/权限风险**：Risks 列「私钥被盗→在腾出额度内增铸给攻击者」，mitigation 为 MAX_SHARES 封顶（不能凭空无限增发）+ Safe 多签 + 链下监控。
- 残留特权边界由 spec Migration 钉死：仍 SHALL NOT 有 sweep/rescue、仍 SHALL NOT 有突破 MAX_SHARES 的增铸，admin 唯一特权是硬上限内增铸份额。与当前 SalesVault.sol 现状（无任何特权入口）对照，本变更是受控的最小权限扩张。
- task 3.3 把上述全部列入 `/security-review` 必查项，符合资金合约纪律。

### D6 替代方案 — PASS

design 记录三个被否决方案及理由：
- **AccessControl vs Ownable**（D1）：选 AccessControl 与工作区其他合约风格一致、未来可扩多管理员；代价 ERC165 已评估。同时记录「不用 AccessControlPartnerContract」（PARTNER 只授合约，本场景管理员是 owner EOA/多签，语义不符）。
- **claim 账本式解耦**（Non-Goals）：明确不引入 MasterChef 式 `accRewardPerShare` 解耦「提收益」与「持股权」，改靠 admin 行政增铸维持比例——是核心方案取舍，已说明。
- **adminBurn / sweep / rescue / pause**（Non-Goals）：显式排除，与最小权限扩张目标一致。

## 非阻塞建议（实现/收尾期，不影响 approved）

1. **稀释护栏可考虑收紧（治理建议，非必须）**：design 已承认「给新地址免费铸即稀释」靠注释+runbook+多签约束，合约不强制。若后续安全 review 认为纪律约束不足，可评估把 adminMint 的 `to` 限制或加事件以便链下审计——但本变更明确以「最小改动」为目标，保持现状 approved，留给 `/security-review`（task 3.3）定夺即可。
2. **收尾确认 interface 同步**：本变更不改 ERC4626/ERC20 ABI，但若前端将来要暴露 adminMint，需在 interface 仓 ABI 同步时一并纳入 `SalesVault.json`——当前无须为此建 change，归档前在 task 3.4 一并核实即可。
