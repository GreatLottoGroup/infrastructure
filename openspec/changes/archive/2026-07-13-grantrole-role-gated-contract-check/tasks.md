## 1. infrastructure 合约改动

- [x] 1.1 修改 `contracts/base/AccessControlPartnerContract.sol` 的 `grantRole`：零地址检查保持全局；`_isContract` 检查仅在 `role == PARTNER_CONTRACT_ROLE` 时生效（其它角色委托 `super.grantRole`）。附中文注释说明按角色 gate 的意图。
- [x] 1.2 `infrastructure/package.json` 版本 `0.1.2 → 0.1.3`。

## 2. infrastructure 测试

- [x] 2.1 在 `test/foundry/AccessControlPartnerContract.t.sol` 新增 `test_grantRole_success_forEOA_whenAdminRole`：owner 对 EOA 授 `DEFAULT_ADMIN_ROLE` 成功，`hasRole(DEFAULT_ADMIN_ROLE, alice) == true`。
- [x] 2.2 新增 `test_grantRole_revert_whenZeroAddress_forAdminRole`：对 `DEFAULT_ADMIN_ROLE` 授 `address(0)` 仍 revert `ErrorZeroAddress`（锁定全局零地址守卫）。
- [x] 2.3 确认现有 PARTNER 相关用例（`test_grantRole_revert_whenEOA` / `_whenZeroAddress` / `_whenContractBelowByteThreshold` / `_success_forContractOverThreshold`）不改仍全绿。
- [x] 2.4 `forge test`（infra）全绿（148 passed）；`forge test --mc AccessControlPartnerContract` 11 passed。

## 3. 文档注释更正（doc-only）

- [x] 3.1 更新 `doc/entropy-consumer-base-design.md`（约 L455）中「grantRole override 不受影响」的描述为「按角色 gate（仅 PARTNER 要求合约地址）」。
- [x] 3.2 更正 `GreatLottoCore/test/foundry/InvestmentPosition.t.sol:19-20` 里「grantRole 无条件要求合约」的注释为「仅 PARTNER 要求合约」。

## 4. 下游回归（经 symlink 即时生效，无需改源码）

- [x] 4.1 `cd ScratchCard && forge test` 全绿（211 passed）。
- [x] 4.2 `cd GreatLottoCore && forge test` 全绿（236 passed）。

## 5. interface 连带收尾（`interface` 仓）

- [x] 5.1 `src/app/launch/management/components/adminRoleM.js`：删除 `contractOnly` 推导与「contractOnly badge」渲染块（十个合约行为统一）。caveat 保留「主网建议用 Safe 多签」作为建议。
- [x] 5.2 从 7 份 `messages/{en,zh-CN,zh-HK,ja,pt,fr,es}.json` 删除 `Management.adminRole.contractOnly` 与 `Management.adminRole.eoaWarning` 两键（脚本化删除，diff 纯净、JSON 可解析）。
- [x] 5.3 `pnpm test:run` 通过（535 passed）。⚠️ `pnpm build` 受本地正在运行的 `pnpm dev` 占用 `.next` 阻塞，未复验（停 dev 后 `rm -rf .next && pnpm build` 即可）。

## 6. 部署与评审门

- [x] 6.1 对 infra 合约 diff 跑 `/security-review`（合约仓必跑）——无 HIGH/MEDIUM findings，改动安全（放宽仅作用于被授予者、调用方门禁不变、PARTNER 不变严、零地址守卫仍在）。
- [ ] 6.2 （部署，待办）重新部署测试网 / 本地（`deploy-local-and-sync` 起链重部 + 回填地址），使放宽行为生效。
- [ ] 6.3 （部署后手动验证，待办）owner 在 `/launch/management/admin-role` 对某 partner-contract（如 ScratchCardNFT）输入一个 EOA → Grant，此前 revert、现在应成功，Check 显示「持有」。

## 7. 归档

- [x] 7.1 `openspec validate --strict` 通过；方案 review + 代码实现 + 下游回归 + 安全 review 全过后归档。（6.2/6.3 为部署期操作，待重部署时执行。）
