# Design — remove-eth-payment-track

## 背景

详见跨仓方案 [`infrastructure/doc/remove-eth-support-plan.md`](../../../doc/remove-eth-support-plan.md) §1–§2.1。

## 接口前后对比

### DaoCoin

```solidity
// before
uint256 public coinPrice = 1 * 10**18;
uint256 public coinPriceEth = 5 * 10**14;
function mintToUser(address account, uint256 assets, bool isEth) external;
function changePrice(uint256 price, bool isEth) external returns (bool);
event PriceChanged(uint256 price, bool isEth);

// after
uint256 public coinPrice = 1 * 10**18;
function mintToUser(address account, uint256 assets) external;
function changePrice(uint256 price) external returns (bool);
event PriceChanged(uint256 price);
```

### BenefitPoolBase

```solidity
// before
address public immutable GreatLottoCoinAddress;
address public immutable GreatLottoEthAddress;
address public immutable GovernCoinAddress;
address public immutable GovernEthAddress;
function executeBenefit(bool isEth, uint256 deadline) external returns (bool);
event BenefitExecuted(address indexed executor, bool isEth, uint256 totalBenefitAmount);

// after
address public immutable GreatLottoCoinAddress;
address public immutable GovernCoinAddress;
function executeBenefit(uint256 deadline) external returns (bool);
event BenefitExecuted(address indexed executor, uint256 totalBenefitAmount);
```

### DaoBenefitPool

```solidity
// before
constructor(address coinAddr, address ethAddr, address daoCoinAddr) { ... }

// after
constructor(address coinAddr, address daoCoinAddr) { ... }
```

### GreatLottoCoin（DAI 收敛）

```solidity
// before — Mainnet
address[] internal _tokens = [
    0xdAC17F958D2ee523a2206206994597C13D831ec7,  // USDT
    0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,  // USDC
    0x6B175474E89094C44Da98b954EedeAC495271d0F   // DAI ← 删除
];
function mint(address token, uint256 amount, address payer, uint deadline, uint8 v, bytes32 r, bytes32 s) external returns (bool) {
    if (token == _tokens[2]) {                                            // ← DAI 分支删除
        selfPermitAllowedIfNecessary(payer, token, IERC20Permit(token).nonces(payer), deadline, v, r, s);
    } else {
        selfPermitIfNecessary(payer, token, getAmount(token, amount), deadline, v, r, s);
    }
    _depositFor(token, amount, payer, _msgSender());
    return true;
}

// after — Mainnet
address[] internal _tokens = [
    0xdAC17F958D2ee523a2206206994597C13D831ec7,  // USDT
    0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48   // USDC
];
function mint(address token, uint256 amount, address payer, uint deadline, uint8 v, bytes32 r, bytes32 s) external returns (bool) {
    selfPermitIfNecessary(payer, token, getAmount(token, amount), deadline, v, r, s);
    _depositFor(token, amount, payer, _msgSender());
    return true;
}
```

> 注：USDT 主网无 EIP-2612 permit，调用 permit 入口时 `selfPermitIfNecessary` 中的 `IERC20Permit(token).permit(...)` 会 revert；用户走 USDT 时 SHOULD 直接用 `mint(token, amount, payer)` 三参版本（先 `approve`）。这与现状一致，不在本 change 修改。

### SelfPermit / ISelfPermit / IERC20PermitAllowed

```solidity
// before
abstract contract SelfPermit is ISelfPermit {
    function selfPermit(...) public payable;                        // EIP-2612
    function selfPermitIfNecessary(...) public payable;             // EIP-2612
    function selfPermitAllowed(...) public payable;                 // ← DAI/CHAI 删除
    function selfPermitAllowedIfNecessary(...) public payable;      // ← DAI/CHAI 删除
}
// + interfaces/IERC20PermitAllowed.sol     ← 整文件删除

// after
abstract contract SelfPermit is ISelfPermit {
    function selfPermit(...) public payable;
    function selfPermitIfNecessary(...) public payable;
}
```

## 决策点

1. **不保留 `bool isEth = false` 默认参数兼容层**：理由是新链全新部署，没有任何调用方需要旧签名；保留兼容层会污染 ABI 并掩盖未迁移的下游代码。
2. **`SelfPermit` 收敛为 EIP-2612 only**：DAI 退出后剩余的 USDC 是标准 EIP-2612；USDT 主网无 permit，原本就不走 `selfPermitAllowed`。删除 `selfPermitAllowed` / `selfPermitAllowedIfNecessary` 与 `IERC20PermitAllowed` 后，permit 路径只剩一条线，行为更可预测。
3. **`GovernCoinAddress` / `GovernEthAddress` 在原实现中传入同一个 `daoCoin`**（见 `DaoBenefitPool.sol:14-15`），所以删除 `GovernEthAddress` 没有任何业务损失。
4. **`PriceChanged` event 不再发 `isEth` 字段**：前端 indexer 因事件 topic hash 变化必须重建，但这与 §1 的 Breaking Change 立场一致。
5. **DAI 不通过 `_tokens` 索引切换 permit 分支**：原实现用 `_tokens[2]` 硬编码 DAI，强耦合数组顺序；本次彻底删除，避免未来加 token 时索引漂移。
6. **不保留"DAI 仍在白名单只是不能 permit"的折中**：DAI 与 ETH 同步下线是业务决策，半下线（permit 不行但 `mint` 三参版本仍能走）会让支持矩阵更复杂。

## 测试策略

- 删除 `test/runTest/GreatLottoEth*.js` 全部用例。
- 在 `test/runTest/DaoCoin.js`（如不存在则新建）覆盖：
  - `mintToUser(account, assets)` 按 `coinPrice` 计算 shares 正确
  - `changePrice(0)` revert `ErrorInvalidAmount`
  - 非 `PARTNER_CONTRACT_ROLE` 调 `mintToUser` revert
- `test/runTest/DaoBenefitPool.js`：覆盖单币种分润、`BenefitPoolNoBenefit` revert。
- `test/runTest/PartnerTest.js`：删除 ETH 路径，保留稳定币 mint 测试。
- `test/runTest/GreatLottoCoin.js`：
  - 删除 DAI mint / DAI permit 用例
  - 新增"传入 DAI 地址 → revert `ErrorUnsupportedToken`"
  - 新增"调用 `selfPermitAllowed(...)` selector 应 revert（fallback 不存在）"
  - 验证 USDC permit 路径继续工作
- `test/utils/getCoin.js` / `permitUtils.js` / `scripts/initTestCoin.js` / `scripts/approveTestCoin.js`：删除 DAI helper 与 fixture 调用。
