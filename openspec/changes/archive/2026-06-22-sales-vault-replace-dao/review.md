status: approved
date: 2026-06-22
reviewer: independent subagent

> 方案 review（`/flow-review-spec`）——独立 reviewer，6 维审查。审查对象：infrastructure change `sales-vault-replace-dao`（用 `SalesVault is ERC4626` 替换 DAO 分红机制，上游打穿 ScratchCard / GreatLottoCore / interface）。

## D1 Scope 单一 — PASS

change 的「一件事」= 把销售分润的承载机制从「GLDC + DaoBenefitPool 主动分发」换成「ERC4626 金库被动增值」。删 DAO 链路（DaoCoin / DaoBenefitPool / BenefitPoolBase / BeneficiaryBase）与上 SalesVault 是同一件事的「拆旧 + 立新」两面，不是夹带：删 DAO 是因为收益权改由金库份额承载（proposal §What Changes、design D1/D2/D6）。未见无关改动——proposal 与 Non-Goals 明确**不动**渠道分润语义、softpay/claimPayout 兜底、`_colletWithCoin`/`_transferTo`、Core 的 INVESTOR 68% 档（design Non-Goals + tasks 6.3）。已核对 `GreatLottoCore/contracts/PrizePool.sol`：68% 走独立的 `_accrueInvestorBenefit`，`netAmount = netAfterChannelDao - amount68` 仅用到 helper 返回值，helper 改名/改目标地址确实正交，「不受影响」属实。

## D2 Breaking 标注 — PASS（含 1 项需修正的 delta 结构瑕疵）

逐项核对（对照真实源 `contracts/base/PrizePoolBase.sol`）：

- **(a) PrizePoolBase 构造签名变更 / 删 `_mintDaoCoinToPayer` / helper 改名**——均如实体现。
  - 源构造确为 7 参 `(coin, daoCoinAddr, daoBenefitPoolAddr, salesChannelAddr, owner_, chRate, sellRate)`（PrizePoolBase.sol L48-65），delta 的「暴露奖池配置 immutable 与分润率」MODIFIED 改为 6 参并显式声明「SHALL NOT 再暴露 `DaoCoinAddress`/`DaoBenefitPoolAddress`」+ 加「编译失败」Scenario，标注准确。
  - `_mintDaoCoinToPayer`（源 L203-205）在 delta 以 `## REMOVED Requirements` 列出，含 Reason + Migration（点名下游 ScratchCard `_afterCollectForBuy` / Core `_collect` 删调用），准确。
  - `_daoBenefitTransfer`→`_salesVaultTransfer`、`_distributeChannelAndDaoBenefits`→`_distributeChannelAndSalesBenefits` 在 delta 有对应 ADDED-语义需求 + 「历史 helper 已删除/编译失败」Scenario。
- **(b) 下游打穿点名 + change 占位**——proposal Impact 三段（ScratchCard / Core / interface）均点名 BREAKING；协调文档 `2026Q2-sales-vault-replace-dao.md` 接口契约表两端签名一致、依赖顺序无环、四仓 change 行齐全（Core/ScratchCard/interface 标 `<待建>` 占位）。tasks 6.2–6.4 落占位清单。属实。
- **(c) 删 DaoCoin/DaoBenefitPool 两个 REMOVED capability**——`dao-coin-pricing-single-track` 与 `dao-benefit-pool-single-track` 两份 delta 均为纯 `## REMOVED Requirements`，每条含 Reason + Migration。属实。

**需修正的瑕疵（不阻塞，建议阶段③顺手修）**：delta `specs/prize-pool-base/spec.md` 把 `_salesVaultTransfer` 与 `_distributeChannelAndSalesBenefits` 两个**新 header** 放在 `## MODIFIED Requirements` 下，但它们的 header 与 baseline（`openspec/specs/prize-pool-base/spec.md`）的 `### Requirement: \`_daoBenefitTransfer\` DAO 利润池打款` / `### Requirement: \`_distributeChannelAndDaoBenefits\` 渠道+DAO 两段分润 pipeline` **不字面匹配**。后果：baseline 这两条 DAO 命名的 requirement 既未被 MODIFIED（header 不符）也未被 REMOVED，归档合并后可能在 prize-pool-base 能力里**残留两条死的 DAO requirement**。`openspec validate --strict` 本地实测**通过**（validator 不强校验 MODIFIED header 命中 baseline），故不破坏 task 7.1，仅是规格清洁度问题。建议二选一修：把这两条改放 `## REMOVED Requirements`（删旧名）+ 在 `sales-vault` 或本 delta 用 `## ADDED Requirements` 立新名；或保持 header 为旧名做真正的 MODIFIED（仅改正文）。

## D3 决策覆盖 tasks — PASS

design 决策 ↔ task 双向核对：
- D1（转入即增值 / 无主动分发）→ tasks 1.1 + 5.2 + spec「无主动分发入口」Scenario。✓
- D2（删整条 DAO 链路）→ tasks 3.1–3.5（含 grep 残留）+ 4.1–4.2（部署去接线）。✓
- D3（开放现价申购 + 1 亿硬上限 + offset=6）→ tasks 1.2/1.3 + 5.3/5.4。✓
- D4（标准 redeem/withdraw 全持有人开放、纯无特权）→ task 1.4 + spec「纯无特权」「标准 redeem/withdraw」两 Requirement。✓
- D5（PrizePoolBase 改造，正交保持）→ tasks 2.1–2.6。✓
- D6（单位贯通 wei 级 GLC、不二次 getAmount、MAX_SHARES 对齐 18 位）→ task 1.1（MAX_SHARES）+ 5.2（asset 对齐）+ design Risks「单位贯通」+ 协调文档跨仓 review 勾项。✓
- 删 DAO / 开放申购 / offset=6 均有 task。
- 反向：未见「task 落在 design 没提的地方」。tasks 1.5（合约体积）/ 2.6（NatSpec）/ 5.6（coverage）属常规工程门，design Risks/Migration 已隐含，不算 design 漏项。

## D4 跨仓一致性 — PASS

- 协调文档四仓 change 同步存在（infra `proposed`，其余 `<待建>` 占位），依赖顺序 `infrastructure → 发包/symlink → {ScratchCard, Core} → interface` 成立、无环；明确「infra PrizePoolBase 构造签名是契约源，必须先定稿发包，否则两下游编译失败」。
- 接口契约表两端签名一致：上游定义 6 参构造 vs 两下游 `PrizePool.sol` 调用。已核对真实下游源——`ScratchCard/contracts/PrizePool.sol` L22-38 与 `GreatLottoCore/contracts/PrizePool.sol` L63-74 当前均传 7 参（含 `daoCoinAddress_`/`daoBenefitPoolAddress_`）且各自调 `_mintDaoCoinToPayer` + `_distributeChannelAndDaoBenefits`，正是契约表/Migration 点名要改的位置，两端对齐描述属实。
- 「infra 先发包」合并顺序避免中间态编译失败，协调文档「合并/部署顺序」与「跨仓一致性 review」勾项齐全。

## D5 不可逆 / 资金风险 — PASS

触及资金路径（销售分润转向 + 金库收款 + ERC4626 攻击面 + 删合约不可逆），design 显式论证了失败兜底与攻击缓解，且经真实 OZ 源核对无误：

- **offset=6 挡 inflation attack**——核对 `@openzeppelin/contracts@5.6.1` ERC4626.sol：`_convertToShares = assets.mulDiv(totalSupply + 10**offset, totalAssets + 1, rounding)`（L249）。offset=6 引入 `10**6` virtual shares + `+1` virtual asset，与 design D2b 描述一致；OZ 注释（L33-39）明确「larger offset → attack orders of magnitude more expensive than profitable」。叠加初始 supply 1 亿（须先大额 redeem 才逼近 0）。判定：offset=6 论证成立，且 tasks 5.4 强制覆盖「大额 redeem→supply 极低→恶意 deposit+捐赠→正常用户份额不被吞为 0、攻击者不净利」攻击序列。✓
- **「初始即满 → maxDeposit==0」副作用**——核对 OZ `deposit` 路径（L194-204）：`assets > maxDeposit(receiver)` → revert `ERC4626ExceededMaxDeposit`。`maxDeposit = _convertToAssets(maxMint, Floor)`，顶满时 `maxMint==0 → maxDeposit==0 → 任意 amount>0 revert`。design/spec 把「初始即满 deposit 总 revert」明确标为**硬上限的预期行为**并要求前端/文档明示，非遗漏。✓
- **maxDeposit floor 换算不破 1 亿硬上限**——上限锚定 **shares**（`maxMint = MAX_SHARES - totalSupply`，精确）；`maxDeposit` 由 shares floor 换算成 assets 是**偏保守**（宁少铸）。两条铸造路径：`mint(s)` 直接受 `maxMint` 卡 `s<=remaining`；`deposit(a<=maxDeposit)` 铸 `previewDeposit(a)=convertToShares(a,Floor)<=maxMint`。两路径铸后 `totalSupply` 均 `<= MAX_SHARES`。floor 不会越限，design Risks「上限换算精度」论证正确，tasks 5.3 fuzz 覆盖极限附近。✓
- **删 DAO 链路反向依赖**——实测 `grep -rE 'DaoCoin|DaoBenefitPool|BenefitPoolBase|BeneficiaryBase|IDaoCoin|IBeneficiaryBase|IBenefitPoolBase' contracts/`：被删 4 合约/3 接口仅相互引用 + 被 `PrizePoolBase`（删 `import IDaoCoin` + `DaoCoinAddress` + `_mintDaoCoinToPayer`）引用，infra 内**无其它 keeper 合约** import 这些被删文件（GreatLottoCoin / DaoCoin 之外无外溢）。task 3.5 的全仓 grep 守住残留。reverse-dep 在 infra 内自洽，不会留悬空 import。✓
- **单位贯通**——sales-vault spec 显式「SHALL NOT 在内部再做 getAmount，金库账本以 wei 级 GLC 计量」；design Risks + 协调文档 review 勾项 + tasks 5.2「asset() 与 GLC 对齐」「转入抬升单份额价值」覆盖。下游 PrizePool 转入侧确为 `getAmount` 放大后 wei（如 ScratchCard `_setPrizePool` / `_afterCollectForBuy`），两端单位一致。✓
- **不可逆论证**——design D2「删合约不可逆；未来需链上治理须重新引入治理币（已确认不需）」+ Migration「回滚=还原 feature 分支，已部署测试网作废重部」。✓

## D6 替代方案 — PASS

design 每个决策均记被否方案 + 理由，足以判断决策质量：
- D1：保留 `executeBenefit` 主动分发（否——O(n) gas/列表维护/≥10k 门槛正是要消除的）。
- D2：保守保留 DaoCoin 供治理仅断增发（否——用户确认治理不用 GLDC）。
- D3：替代 A 永久禁用 deposit/mint（否——用户要「赎回后可再入金」）；替代 B owner-only 无偿 topUp（否——已累积分润时无偿补铸稀释他人）。
- D4：禁 redeem 只留 owner sweep（否——放弃「份额=可流转收益权」的 ERC4626 核心价值）。
- D5/D7：保留旧 helper/immutable 名减少 churn（否——「Dao」命名误导，下游本就改构造，顺手改干净）。
背景 doc §6 决策记录列 6 项已锁定 + Open Questions「无」。

## 结论

整体 **approved**。6 维全 PASS（无 FAIL、无 N/A）。change scope 单一、breaking 标注完整且经真实源核对属实、决策与 tasks 双向覆盖、跨仓四仓占位与依赖顺序自洽、资金/攻击面（offset=6 inflation 防护、硬上限 floor 不越限、删合约 reverse-dep 自洽、单位贯通）均经 OZ 真实实现与下游源验证无误、替代方案记录充分。可进入阶段④实现（infrastructure 先行）。

**非阻塞建议（实现/归档前顺手修，无须回 writing-plans）**：

1. **[D2 delta 结构]** `specs/prize-pool-base/spec.md` 把 `_salesVaultTransfer` / `_distributeChannelAndSalesBenefits` 两个新 header 误置于 `## MODIFIED Requirements`，与 baseline 旧 header（`_daoBenefitTransfer ...` / `_distributeChannelAndDaoBenefits ...`）不字面匹配，归档后或在 prize-pool-base 能力里残留两条死的 DAO requirement。`openspec validate --strict` 本地实测通过、不阻塞 task 7.1，但建议二选一修干净：(a) 把旧名两条放 `## REMOVED Requirements` + 新名两条放 `## ADDED Requirements`；或 (b) 保持旧 header 做真 MODIFIED（仅改正文，header 不变）。归档前确认合并后的 prize-pool-base spec 不含 `_daoBenefitTransfer` / `_distributeChannelAndDaoBenefits` 残留。
