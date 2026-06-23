status: approved
date: 2026-06-23

> 独立方案 review（`/flow-review-spec`，6 维）。Reviewer 非作者。本 change 改上游接口
> （`ISalesChannel` + `PrizePoolBase._channelBenefitTransfer`）且让 `SalesChannel` 首次托管 GLC，
> 属上游打穿 + 资金托管，按合约仓最高门槛审。

## 维度小结

| 维度 | 判定 | 证据 |
|---|---|---|
| **D1 Scope single** | PASS | 单一主题「SalesChannel 优化」：去 status 干预 + 分页遍历 + 渠道分润 push→pull 记账自提。四项需求同源于一个能力（渠道收款方升级），非杂烩。proposal「What Changes」全部围绕 SalesChannel/对应 `_channelBenefitTransfer`，未夹带无关改动。 |
| **D2 Breaking annotation** | PASS | proposal 5 处 **BREAKING** 标注真实（删 disable/enable、删 `status` 字段、收窄 getter 返回值、push→pull、`Ownable`→`AccessControlPartnerContract`）。下游打穿全部建账：ScratchCard/GreatLottoCore（§5/§6 任务）+ interface（§7）+ `PrizePoolBase` 解构同步改写（task 3.1）。prize-pool-base spec 用 `## MODIFIED Requirements` 正确标记，已核对其与现有 `openspec/specs/prize-pool-base/spec.md` 第 126–146 行的旧三元解构 `(bool status, address chn,)` 一致——delta 把它收窄为 `(address chn,)` 属真实 MODIFIED，无谎报。 |
| **D3 Decisions covered by tasks** | PASS | D1→task 2.1；D2→task 5.3/5.4/6.3/6.4；D3→task（全新部署，design Migration 覆盖，无遗留迁移任务，正确）；D4→task 2.7；D5→task 3.2；D6→task 2.3/3.1；D7→task 2.5/2.8/4.3；D8→task 2.4。反向核对：未发现 task 落在 design 未提及的领域。 |
| **D4 Cross-repo consistency** | PASS | 部署顺序 `GLC → SalesChannel → PrizePool → grantRole` 无环（D2），与现 `PrizePoolBase` 构造已持 immutable `SalesChannelAddress` 的事实一致；ABI 重同步（interface task 7.1）、grantRole（5.3/6.3）、本地模块（5.4/6.4）齐备。已实地核对 GreatLottoCore `PrizePool._collect`（L264）与 ScratchCard `PrizePool`（L104）确为经 `_distributeChannelAndSalesBenefits` 间接消费、源码确实无需改。 |
| **D5 Irreversible / fund risk** | PASS | SalesChannel 首次托管 GLC。偿付不变量显式给出（spec「偿付能力不变量」`balanceOf >= totalAccrued - totalWithdrawn` + 恒等式，task 4.3 invariant 测试）；`withdraw` CEI 先记账后转账（spec L116）+ `noDelegateCall` + 提到 `msg.sender` 自己拒任意 `to`（D4 防钓鱼）；`creditChannel` 锁 `PARTNER_CONTRACT_ROLE`；失败兜底=渠道私钥仍可后续 `withdraw`（pull 天然兜底，无 push-revert 阻塞购买的风险——正是本 change 的动机）。push→pull 对下游偿付假设「等价」的论断经实地核对成立（见下「非阻塞建议 1」的验证）。 |
| **D6 Alternatives** | PASS | design D1 记录并拒绝了「保留 Ownable + 自建 crediter 白名单」备选（理由：重复造轮子、与工作区不一致）。Migration 段含 Rollback（未上主网，回滚=不部署新合约）。 |

**总判定：6/6 PASS → `approved`。** 无 D2/D5 FAIL，方案可进入实现 + 代码 review。下列均为非阻塞精度建议，实现/代码 review 阶段收口即可，不打回 writing-plans。

## 重大缺陷 / 必须修改

无。未发现使 change 退回设计阶段的阻塞缺陷。

## 建议（非阻塞）

1. **[已验证，仅补文档]push→pull「偿付等价」论断成立，但建议在 design 风险段补一句证据。**
   design 最后一条风险 bullet 称下游 PrizePool 偿付假设「等价」。我实地核对了两处下游：
   - GreatLottoCore `PrizePool._collect`（L264）：`netAfterChannelSales = _distribute...(amountByCoin, channelId)`，channelBenefit 在该 helper 内**已转出**合约（push 时转给 EOA，pull 时转给 SalesChannel——两者都离开本合约），随后 `_checkInvariant()`（L549）左侧 `ΣpoolRemaining + Σaccrued + contractPool + pendingPayoutTotal` 本就**不含** channelBenefit。故两模型下 invariant 左右两侧均不变，等价成立。
   - ScratchCard `PrizePool`（L104）同形。
   论断正确，但 design 只给结论未给「invariant 左侧从不含 channel 档」这一关键证据；建议补一行，便于安全 review 复核时不必重走。

2. **`withdraw()` 的 chnId 解析机制在 spec delta 里未写明，未注册调用方的分支只是「暗示安全」。**
   design §3.3 / D4 说「取调用方注册的 chnId」，但 sales-channel spec「渠道自提分润」的 Scenario「非渠道地址提取 revert」只写「`msg.sender` 无对应 chnId」，没有点明实现是 `_channelAddress[msg.sender]`（现合约 L20 已有此映射）→ 未注册得 `chnId == 0` → `pendingOf(0)`。需要论证 `pendingOf(0)` 必为 0：chnId 从 1 起（现合约 L14），且 `channelId == 0` 路径在 `_distributeChannelAndSalesBenefits`（L213）走「不调 `_channelBenefitTransfer`」分支，故 `creditChannel(0, …)` 永不被调，`_accrued[0]` 恒 0 → `withdraw()` 走 `SalesChannelNothingToWithdraw(0)` revert。结论**安全**，但建议在 spec 该 Scenario 显式写「未注册地址解析到 chnId 0，`pendingOf(0)==0` 故 revert `SalesChannelNothingToWithdraw(0)`」，避免实现者误加一条多余的「`chnId==0` 显式 revert」分支或漏掉零值保护。task 2.7 可补一句解析口径。

3. **`creditChannel` 与「PrizePool 已先行转入等额 GLC」是约定耦合而非合约强制，建议在 spec 标注信任边界。**
   `_channelBenefitTransfer`（design L144）是「先 `_transferTo(SalesChannel, benefit)` 再 `creditChannel(chnId, benefit)`」两次独立调用。`creditChannel` 自身不校验本合约 GLC 实到账，纯靠 PARTNER 合约自律配对。这在 PARTNER 仅授给受信 PrizePool 的前提下可接受（与工作区既有 PARTNER 信任模型一致），但偿付不变量的成立**依赖** caller 永远「转账在前、记账等额」。建议 spec「渠道分润记账」Requirement 把这条不变量前置条件写成显式 MUST（「调用方 MUST 在 `creditChannel` 前已把等额 GLC 转入本合约」已在 spec L105 描述性提及，建议升格为 MUST 并在 `/security-review` 清单点名核对 `_channelBenefitTransfer` 的转账/记账顺序与金额一致）。注意：顺序「转账→记账」对 reentrancy 无害（creditChannel 只动内部账本、不外呼），反向「记账→转账」才需警惕，实现须保持 design 给出的顺序。

4. **`getChannelById` 返回值收窄会改变 `PrizePoolBase` 的 ABI 选择器消费方；确认 interface task 覆盖了 `getChannelById`/`getChannelByAddr` 的去 status 解构（task 7.2 已列），无补充。** 仅提示代码 review 时核对 interface `hooks/contracts/SalesChannel.js` 所有读这两个 getter 的点位都改了三元→二元解构（MEMORY 记录过 DAO hooks 曾因 arity 漂移静默显示 0 的前车）。

5. **合约体积**：SalesChannel 从纯注册表升级为持币 + 账本 + 分页 + AccessControl，体积上升。task 8.5 已列 EIP-170 复核，保留即可。

---

## 代码 review（独立 subagent，新上下文，2026-06-23）

status: **approved（ship-ready）** — 无 BLOCKER、无 SHOULD-FIX。

跨 4 仓 diff 全审。逐一核实：
- `getChannelsPaged` 边界数学（startId==0/count==0/count>20/尾裁/越界）四个 spec 场景均有对应通过测试。
- `pendingOf` 无下溢风险：`withdraw` 只把 `_accrued-_withdrawn` 加进 `_withdrawn`，恒有 `_withdrawn<=_accrued`；solvency invariant（12800 calls/0 revert）佐证。
- `withdraw` CEI（先记账后转账）+ noDelegateCall + 零解析 revert，已测。
- `_channelBenefitTransfer`：存在性检查（chn==0 revert）置于 benefit==0 早退**之前**，符合 spec（无效 id 即便 0 benefit 也 revert）；转账→记账顺序正确。
- interface：`getChannelByAddr`→`[chnId,name]`、`getChannelById`→`[addr,name]` 二元解构与新 ABI 一致；`channelList` 读 `c.id/c.chn/c.name` 匹配 ChannelInfo 结构；无残留 `.status`/statusEl/disable/enable；bigint 比较与 formatAmount(18) 正确。
- 部署模块：infrastructure.js `[greatLottoCoin, owner]` 顺序正确（greatLottoCoin 先声明）；两个本地模块 grant SalesChannel PARTNER 给 PrizePool 角色/顺序正确；README 授权清单 3→4 一致。
- 测试质量：MockPrizePool/Crediter 继承 AccessControlPartnerContract 以过 >1000 字节 _isContract 门槛，手法可靠且镜像真实 PrizePool；断言核实新行为（资金入 SalesChannel + pendingOf，渠道 EOA 恒为 0）。

NIT（1，非阻塞，pre-existing）：`interface/.../issue/components/channel.js:14` `Number(chn) != NaN` 死比较（被 `> 0` 守卫兜住，无害；M1 引入非本次）。建议 cleanup 为 `!Number.isNaN(...)`。

非本次引入的既有缺口：interface 渠道组件无单测（JS 改动靠手动 QA / build 通过验证）。

## 安全 review（独立 subagent，新上下文，2026-06-23）

status: **approved — 无 HIGH/MEDIUM 高置信可利用漏洞。**

逐一追踪 7 个攻击面（资金托管为本次新增重点）：
1. creditChannel 访问控制：onlyRole(PARTNER)，grantRole 的 _isContract>1000 字节门槛 + 仅 DEFAULT_ADMIN 可授 → 无 EOA 路径；两仓部署只把 SalesChannel PARTNER 授给受审 PrizePool。over-credit 偷他人资金需 PrizePool 有 bug（转账=记账等额且原子，已核）或 admin 妥协（受信角色滥用，pre-existing，越界）。安全。
2. withdraw：chnId 由 `_channelAddress[msg.sender]` 解析、收款恒为 msg.sender（无任意 to）；未注册→chnId0→amount0→revert；GLC 为 OZ ERC20Permit 无转账回调（非 ERC777），严格 CEI，无重入。安全。
3. credit 不存在/chnId0：`_channelBenefitTransfer` 先验 chn!=0；chnId0 永不入账；后注册者拿 _nextId(≥1)，无法领 chnId0 幻影余额。安全。
4. 偿付不变量：每次 credit 前有等额原子转账；withdraw 只付本渠道差额；外部直转 GLC 只增余额（捐赠），不能让 A 渠道取 B 的账。安全（新 invariant 测试佐证）。
5. getChannelsPaged 边界：count 上限、startId 规整、越界早退、end 钳到 lastId，无 OOB。安全。
6. init/admin 接管：constructor 即授 DEFAULT_ADMIN，无 initializer→无抢跑窗口。安全。
7. 跨合约原子性：PrizePool 转账→记账与 buy/collect 同一 tx，credit revert 则整笔回滚。安全。

运维要求（非漏洞，已记 NatSpec）：creditChannel 不校验实到账，安全性依赖「PARTNER 仅授受审 PrizePool」——务必绝不把 SalesChannel PARTNER 授给未审计合约。
