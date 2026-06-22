# 安全 review — sales-vault-admin-mint

status: passed（无 HIGH / MEDIUM 发现）
date: 2026-06-22
scope: 仅 `contracts/SalesVault.sol` 工作树改动（adminMint + AccessControl 继承 + 构造授权）+ 其测试。分支历史其余提交为已 review 的前置工作，不在本次范围。

## 结论

**无新引入的可利用安全漏洞（>80% 置信）。** 唯一实质性风险是「免费 adminMint 对现有持有人的按比例稀释」——属**已文档化、完全受 `DEFAULT_ADMIN_ROLE` 信任门控的中心化风险，accepted-by-design**，非漏洞。

## 逐类核查

1. **访问控制 / 上限绕过 — 健全**
   - `adminMint` 由 `onlyRole(DEFAULT_ADMIN_ROLE)` 门控，非 admin revert `AccessControlUnauthorizedAccount`（`test_adminMint_revert_whenNotAdmin`）。
   - 上限经 `maxMint(receiver)` 校验：`maxMint = MAX_SHARES - totalSupply()`（饱和到 0），`shares > maxShares` 即 revert；`_mint` 增 supply，故铸后 `totalSupply ≤ MAX_SHARES` 恒成立（`testFuzz_adminMint_neverExceedsCap` 验证）。无绕过路径。
   - `receiver == address(0)`：`_mint` 自然 revert `ERC20InvalidReceiver`。铸给自身无害。

2. **权限升级（grant/renounce）— accepted-by-design**
   owner 持 `DEFAULT_ADMIN_ROLE` 可授他人 / renounce，属 OZ AccessControl 标准语义；**无对非 admin 开放的升级路径**。文档建议多签。

3. **经济 / 记账攻击 — accepted-by-design，已文档化**
   免费铸对老持有人按比例稀释，已在 NatSpec 显式标注「不要在金库有存量收益时给新地址免费铸」+ 多签建议。**admin 无法超出按比例稀释窃取资产**：无 adminBurn / sweep / rescue / pause，admin 取 GLC 只能像普通持有人一样持份额 redeem；blast radius 受 `MAX_SHARES` 封顶。

4. **重入 — 无**
   `maxMint` 为 view；`_mint`→`_update` 对纯 ERC20 无外部回调 / receiver hook（非 ERC777/ERC1363）。无重入面。

5. **ERC165 / 继承解析 — 干净**
   OZ v5.6.1 的 ERC4626/ERC20 不声明 `supportsInterface`，加 AccessControl 无 override 冲突；hardhat compile 通过证明 C3 线性化解析正确。无 auth 绕过。

6. **inflation-attack 防护（offset=6）— 未削弱**
   offset 作用于 public deposit/mint 的 virtual-shares 换算；adminMint 直接铸 raw shares、不收资产，完全绕过换算，不与 offset 交互。公众申购仍受 offset 保护、且部署即满额天然封死。

## 操作性备注（非发现）

adminMint 的安全使用依赖运维纪律（仅在 redeem 腾出的额度内补回、勿在金库有未分配 GLC 时给新地址铸）——已在 NatSpec + 部署建议中正确呈现。建议 `owner_` 用 Safe 多签。
