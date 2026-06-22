## 1. 合约改动（contracts/SalesVault.sol）

- [x] 1.1 import `@openzeppelin/contracts/access/AccessControl.sol`，`SalesVault` 增加 `is ... , AccessControl` 继承
- [x] 1.2 构造函数中新增 `_grantRole(DEFAULT_ADMIN_ROLE, owner_)`（保留现有 `_mint(owner_, MAX_SHARES)` 不变）
- [x] 1.3 新增 `adminMint(uint256 shares, address receiver) external onlyRole(DEFAULT_ADMIN_ROLE)`（参数顺序对齐 ERC4626 `mint(shares, receiver)`）：取 `maxMint(receiver)`，`shares > max` 时 revert `ERC4626ExceededMaxMint(receiver, shares, max)`，否则 `_mint(receiver, shares)`
- [x] 1.4 更新合约 NatSpec/注释：从「纯无特权 ERC4626」改为「公众申购天然封死 + admin 受 1 亿上限约束免费增铸」；标注 adminMint 安全用法（仅在 redeem 腾额后补回、建议 owner 用多签）
- [x] 1.5 确认编译通过（`npx hardhat compile`），核对合约体积仍在 EIP-170 内（SalesVault 4.955 KiB）、ERC165 `supportsInterface` 无冲突

## 2. 测试（test/foundry/）

- [x] 2.1 部署后 `hasRole(DEFAULT_ADMIN_ROLE, owner)` 为 true（`test_constructor_grantsAdminRoleToOwner`）
- [x] 2.2 满额时 `adminMint` revert `ERC4626ExceededMaxMint`（`maxMint == 0`）（`test_adminMint_revert_whenFull`）
- [x] 2.3 持有人 `redeem` 腾出额度后，admin `adminMint(receiver, s<=R)` 成功、`balanceOf(receiver)` 增加、不收 GLC、`totalSupply <= MAX_SHARES`（`test_adminMint_succeeds_inFreedRoom`）
- [x] 2.4 超额 `adminMint(receiver, s>R)` revert，`totalSupply` 不变（`test_adminMint_revert_whenExceedsRoom`）
- [x] 2.5 非 admin 调用 `adminMint` revert `AccessControlUnauthorizedAccount`（`test_adminMint_revert_whenNotAdmin`）
- [x] 2.6 既有 ERC4626 行为回归（deposit/mint 满额仍 revert、redeem/withdraw、virtual shares）不受影响（既有 14 用例 + fuzz 全绿）
- [x] 2.7 `forge test` 全绿（129/129）、`forge coverage` SalesVault 100%（16/16 行、1/1 分支、5/5 函数）

## 3. 流程门 / 收尾

- [x] 3.1 `openspec validate sales-vault-admin-mint --strict` 通过
- [x] 3.2 代码 review（`/code-review --effort high`）：合约无 correctness bug；修掉测试 NatSpec 文档腐烂（line 16）+ 冗余 assertLe（line 291）
- [x] 3.3 安全 review（`/security-review`）：无 HIGH/MEDIUM，6 类逐项核验；稀释为已文档化、信任门控的 accepted-by-design，见 security-review.md
- [x] 3.4 归档前确认下游零打穿：ScratchCard/GreatLottoCore 的 PrizePool 仅把 salesVaultAddress 传 PrizePoolBase 构造 + 经 _salesVaultTransfer(safeTransfer) 消费，无 SalesVault 内部接口/ERC165/无-AccessControl 依赖
