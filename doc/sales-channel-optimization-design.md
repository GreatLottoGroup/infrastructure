# SalesChannel 优化方案（status 下线 + 批量遍历 + 渠道分润记账自提）

> 仓：`infrastructure`（上游基础库）。本改动是**上游打穿**事件：改 `SalesChannel` / `ISalesChannel`
> 对外接口，且改 `PrizePoolBase._channelBenefitTransfer` 的分润语义（从「push 给渠道 EOA」改为
> 「转入 SalesChannel 合约记账，渠道自提」）。下游 ScratchCard / GreatLottoCore（经 `PrizePoolBase`）
> 与 interface（ABI + hooks + 渠道页）均受影响 → **须走跨仓流程 + `/flow-review-spec`**。
>
> 状态：草案（待 review）。建议 change-id：`2026Q2-sales-channel-accrual-withdraw`。

## 1. 背景与目标

当前 `SalesChannel.sol`（[contracts/SalesChannel.sol](../contracts/SalesChannel.sol)）是纯注册表：渠道方
`registerChannel` 登记 → 拿到自增 `chnId` → 购买流里 `PrizePoolBase._channelBenefitTransfer` 按
`channelBenefitRate` 把渠道分润**直接 `safeTransfer` 打给渠道地址（EOA）**。渠道还带一个 `bool status`
启用/禁用字段，owner 可 `disableChannel` / `enableChannel` 干预。

本次优化四项需求：

1. **去掉 owner 对渠道状态的干预** —— 删除 `disableChannel` / `enableChannel`。
2. **去掉渠道状态字段** —— `ChannelInfo.status` 删除（连带相关 error / event）。
3. **新增渠道批量遍历** —— 可分页批量获取渠道列表，单页最大 20。
4. **渠道分润改为记账 + 自提** —— 分润不再直接打给渠道 EOA，而是**转入 SalesChannel 合约按 `chnId` 记账**，
   渠道方自行 `withdraw` 提取累积收益。

目标：渠道从「被动收款的 EOA」升级为「合约托管 + 主动提取的账户」，与工作区 SalesVault / PrizePool 兜底
（`claimPayout`）的 pull-payment 范式对齐，规避 push 给恶意/无法收款渠道地址时的整笔交易 revert 风险。

## 2. 现状梳理（受影响面）

| 位置 | 现状 | 受影响点 |
|---|---|---|
| [SalesChannel.sol](../contracts/SalesChannel.sol) | 注册表 + status + disable/enable | 重构主体 |
| [ISalesChannel.sol](../contracts/interfaces/ISalesChannel.sol) | struct/error/event/函数签名 | 接口收窄 + 扩展 |
| [PrizePoolBase.sol:178-184](../contracts/base/PrizePoolBase.sol) `_channelBenefitTransfer` | `getChannelById` 读 status → `_transferTo(coin, chn, benefit)` 直接打 EOA | 改为转入 SalesChannel 并记账 |
| [PrizePoolBase.sol:204-225](../contracts/base/PrizePoolBase.sol) `_distributeChannelAndSalesBenefits` | 调 `_channelBenefitTransfer` | 调用点不变，被调函数内部改写 |
| ScratchCard `PrizePool.sol:104` / GreatLottoCore `PrizePool.sol:264` | 经 `_distributeChannelAndSalesBenefits` 间接用 | 无需改源码，但须重编译 + 重测 + ABI 重同步 |
| infra `test/foundry/SalesChannel.t.sol` | 覆盖 disable/enable/status | 重写 |
| infra `test/foundry/PrizePoolBase.t.sol` + harness | 校验渠道收款 | 改断言（渠道收款方变 SalesChannel + 记账） |
| interface `hooks/contracts/SalesChannel.js` + `channel/` 页 + `abi/SalesChannel.json` | disable/enable/statusEl | 删 disable/enable，加 withdraw + 列表 + 待提余额 |

> 关键约束：`PrizePoolBase` 构造已持有 `SalesChannelAddress`（immutable）与 `GreatLottoCoinAddress`，
> 分润基数以 GLC 计价。渠道分润 GLC 现由 PrizePool 持有 → 需转入 SalesChannel。**SalesChannel 此前不持币**，
> 改造后将托管 GLC，须引入资产币地址 + 访问控制（仅授权的 PrizePool 合约可记账）。

## 3. 设计

### 3.1 数据结构变更（需求 1、2）

`ChannelInfo` 去掉 `status`，新增累计/已提账本（账本不放进返回 struct 以省 calldata，单独 getter 暴露）：

```solidity
struct ChannelInfo {
    uint256 id;
    address chn;
    string  name;
    // status 删除
}
```

合约内新增：

```solidity
// 渠道累计分润收益（GLC，按 chnId 记账）
mapping(uint256 chnId => uint256) private _accrued;   // 单渠道累计入账总额
mapping(uint256 chnId => uint256) private _withdrawn; // 单渠道累计已提总额
// 待提 = _accrued - _withdrawn
uint256 private _totalAccrued;                        // 全局累计入账总额 = Σ _accrued
uint256 private _totalWithdrawn;                      // 全局累计已提总额 = Σ _withdrawn
```

> **聚合账本（决策定稿）**：全局两个口径都暴露——累计入账 `totalAccrued`（仅 `creditChannel` 自增）+
> 累计已提 `totalWithdrawn`（仅 `withdraw` 自增）；全局待提 = `totalAccrued − totalWithdrawn`，
> 即合约内尚未提走的渠道分润总额，供偿付能力不变量参照。单渠道明细三个口径：
> 累计入账 `accruedOf` / 累计已提 `withdrawnOf` / 当前待提 `pendingOf`。

删除：`disableChannel` / `enableChannel`（需求 1）；error `SalesChannelAlreadyDisabled` /
`SalesChannelAlreadyEnabled`；event `SalesChannelDisabled` / `SalesChannelEnabled`（需求 2）。
`changeChannelName` 中 `status == false` 守卫一并删除（渠道不再有禁用态）。

视图 getter 返回签名收窄（去掉 status 布尔）：
- `getChannelByAddr(address) → (uint id, string name)`（不存在返回 `(0, "")`）
- `getChannelById(uint) → (address chn, string name)`（不存在返回 `(address(0), "")`）

> ⚠️ **签名变更 → ABI 打穿**：`PrizePoolBase._channelBenefitTransfer` 当前解构 `(bool status, address chn, )`，
> 必须同步改为 `(address chn, ) = getChannelById(chnId)`，存在性判据从 `status==false && chn==address(0)`
> 改为 `chn == address(0)`。

### 3.2 批量遍历（需求 3）

渠道 id 从 1 连续自增，`getChannelCount() = _nextId - 1`，天然支持分页：

```solidity
uint256 public constant MAX_CHANNEL_PAGE = 20;

/// @notice 分页批量读取渠道（按 chnId 升序，含 startId，最多 count 个）。
/// @param  startId 起始 chnId（>=1）
/// @param  count   本页数量，超过 MAX_CHANNEL_PAGE revert SalesChannelPageTooLarge
/// @return list    ChannelInfo 数组（实际长度按剩余裁剪，可能 < count）
function getChannelsPaged(uint256 startId, uint256 count)
    external view returns (ChannelInfo[] memory list);
```

实现：`count > 20` revert `SalesChannelPageTooLarge(count)`；`startId == 0` 规整为 1；`end = min(startId+count-1, _nextId-1)`；
`startId > end` 返回空数组；否则填充。与 ScratchCard `getCardOverviewBatch`（batch ≤ 20）的上限语义保持一致。

### 3.3 渠道分润记账 + 自提（需求 4）

**收款方变更**：`PrizePoolBase._channelBenefitTransfer` 由「push 给渠道 EOA」改为「transfer 给 SalesChannel
合约 + 调记账方法」。

新增 `SalesChannel` 持币 + 记账接口（仅授权 PrizePool 可调）：

```solidity
/// @notice PrizePool 在分润时调用：把已转入本合约的渠道分润按 chnId 记账。
/// @dev    仅 PARTNER_CONTRACT_ROLE（授给各 PrizePool 合约）可调；调用前 PrizePool 已把 GLC safeTransfer 入本合约。
function creditChannel(uint256 chnId, uint256 amount) external onlyRole(PARTNER_CONTRACT_ROLE);

/// @notice 渠道方提取累计分润（pull payment）。
/// @dev    msg.sender 必须是 chnId 的注册地址；提 _accrued - _withdrawn 全额，safeTransfer GLC。
function withdraw() external noDelegateCall;

/// @notice 查询某渠道待提取分润（_accrued - _withdrawn）。
function pendingOf(uint256 chnId) external view returns (uint256);

/// @notice 查询某渠道历史累计入账分润（_accrued，含已提）。
function accruedOf(uint256 chnId) external view returns (uint256);

/// @notice 查询某渠道历史累计已提分润（_withdrawn）。
function withdrawnOf(uint256 chnId) external view returns (uint256);

/// @notice 平台全局累计入账分润总额（Σ accruedOf）。
function totalAccrued() external view returns (uint256);

/// @notice 平台全局累计已提分润总额（Σ withdrawnOf）。
function totalWithdrawn() external view returns (uint256);
```

`withdraw` 必须校验 `msg.sender == _channel[chnId].chn`（取调用方注册的 chnId，提到调用方自己，**不接受任意 `to`**），
待提为 0 时 revert `SalesChannelNothingToWithdraw(chnId)`。

`PrizePoolBase._channelBenefitTransfer` 改写为：

```solidity
function _channelBenefitTransfer(ICoinBase coin, uint256 benefit, uint256 chnId) internal {
    (address chn, ) = ISalesChannel(SalesChannelAddress).getChannelById(chnId);
    if (chn == address(0)) {
        revert ISalesChannel.SalesChannelInvalid(chn);
    }
    if (benefit == 0) return;                          // 0 分润不记账
    _transferTo(coin, SalesChannelAddress, benefit);   // 资金转入 SalesChannel
    ISalesChannel(SalesChannelAddress).creditChannel(chnId, benefit); // 记账
}
```

**访问控制（D1 定稿：用 `AccessControlPartnerContract`）**：`SalesChannel` 改继承
`AccessControlPartnerContract`（替换 `Ownable`），把记账入口 `creditChannel` 锁给 `PARTNER_CONTRACT_ROLE`，
部署后 owner（`DEFAULT_ADMIN_ROLE`）给两个 PrizePool（ScratchCard + GreatLottoCore）各授一次。
`registerChannel` / `changeChannelName` / `withdraw` 仍是 EOA 自助、无角色门。owner 语义从 `owner()` 迁为
`DEFAULT_ADMIN_ROLE`，与工作区 PrizePool / NFT 的 PARTNER 模式一致。

**资产币地址**：`SalesChannel` 构造新增 `address coin`（GLC 地址），`withdraw` / `creditChannel` 用
`SafeERC20` 转账。需求与 `PrizePoolBase.GreatLottoCoinAddress` 同源。

### 3.4 偿付能力不变量

引入 `_accrued / _withdrawn` 后，`SalesChannel` 持有的 GLC 余额恒应 ≥ 全局待提
`_totalAccrued - _totalWithdrawn`。新增 invariant 测试（对标 PrizePool 偿付能力）：任意 credit/withdraw
序列后 `coin.balanceOf(SalesChannel) >= _totalAccrued - _totalWithdrawn`。另两条恒等式：
`_totalAccrued == Σ accruedOf(chnId)`、`_totalWithdrawn == Σ withdrawnOf(chnId)`。

## 4. 接口最终形态（ISalesChannel）

```solidity
interface ISalesChannel {
    error SalesChannelAlreadyExists(address);
    error SalesChannelNotExists(address);
    error SalesChannelInvalid(address);
    error SalesChannelPageTooLarge(uint256);     // 新增
    error SalesChannelNothingToWithdraw(uint256); // 新增
    // 删除：SalesChannelAlreadyDisabled / SalesChannelAlreadyEnabled

    struct ChannelInfo { uint256 id; address chn; string name; } // 去 status

    event SalesChannelRegistered(address indexed addr, uint256 id, string name);
    event SalesChannelNameChanged(address indexed addr, uint256 id, string name);
    event SalesChannelCredited(uint256 indexed id, uint256 amount);   // 新增
    event SalesChannelWithdrawn(uint256 indexed id, address indexed chn, uint256 amount); // 新增
    // 删除：SalesChannelDisabled / SalesChannelEnabled

    function registerChannel(string memory name, uint256 deadline) external returns (bool);
    function changeChannelName(string memory name, uint256 deadline) external returns (bool);
    function getChannelByAddr(address chn) external view returns (uint, string memory);   // 去 bool
    function getChannelById(uint chnId) external view returns (address, string memory);   // 去 bool
    function getChannelCount() external view returns (uint);
    function getChannelsPaged(uint256 startId, uint256 count) external view returns (ChannelInfo[] memory); // 新增
    function creditChannel(uint256 chnId, uint256 amount) external;   // 新增（PARTNER）
    function withdraw() external;                                     // 新增
    function pendingOf(uint256 chnId) external view returns (uint256);   // 新增（待提）
    function accruedOf(uint256 chnId) external view returns (uint256);   // 新增（单渠道累计入账）
    function withdrawnOf(uint256 chnId) external view returns (uint256); // 新增（单渠道累计已提）
    function totalAccrued() external view returns (uint256);            // 新增（全局累计入账）
    function totalWithdrawn() external view returns (uint256);          // 新增（全局累计已提）
    // 删除：disableChannel / enableChannel
}
```

## 5. 下游适配清单（跨仓）

### infrastructure（本仓）
- [ ] 重写 `SalesChannel.sol`（去 status/disable/enable，加分页 + credit/withdraw + 持币 + PARTNER）
- [ ] 收窄 + 扩展 `ISalesChannel.sol`
- [ ] 改 `PrizePoolBase._channelBenefitTransfer`（收款方 → SalesChannel + `creditChannel`，解构去 status）
- [ ] 重写 `SalesChannel.t.sol`；改 `PrizePoolBase.t.sol` + harness 断言；加偿付能力 invariant
- [ ] `forge test` 全绿 + `forge coverage`

### ScratchCard
- [ ] 无源码改动（经 `_distributeChannelAndSalesBenefits` 间接调用），但须重编译 + `forge test` 全绿
- [ ] 部署脚本：部署后给 ScratchCard `PrizePool` 授 SalesChannel 的 `PARTNER_CONTRACT_ROLE`
- [ ] **本地部署文件补授（D2）**：`ignition/modules/ScratchCardLocal.js` 加 SalesChannel 部署 + grantRole；
      `ignition/parameters/localhost.json` 补 SalesChannel/GLC 地址参数
- [ ] `PrizePool.t.sol` 分润断言：渠道分润收款方从渠道 EOA 改为 SalesChannel 合约 + `pendingOf` 增长

### GreatLottoCore
- [ ] 同 ScratchCard：无源码改动，重编译 + 重测 + 部署后授 PARTNER + 分润断言改写
- [ ] **本地部署文件补授（D2）**：本地部署模块加 SalesChannel grantRole + 参数文件补地址

### interface
- [ ] `abi/SalesChannel.json` 重新从 artifacts 同步
- [ ] `hooks/contracts/SalesChannel.js`：删 `disableChannel`/`enableChannel`/`statusEl`，加
      `getChannelsPaged` / `withdraw` / `pendingOf`；`getChannelByAddr`/`getChannelById` 返回值去 status 解构
- [ ] `channel/` 页：渠道列表改用分页遍历；渠道详情加「待提收益 + 提取按钮」；移除启用/禁用 UI

## 6. 风险与决策点

- **D1（定稿：`AccessControlPartnerContract`）**：`SalesChannel` 从 `Ownable` 迁到
  `AccessControlPartnerContract`，复用工作区 PARTNER 模式；owner 语义改 `DEFAULT_ADMIN_ROLE`。
- **D2（定稿：补授 + 写本地部署文件）**：`SalesChannel` 构造需 GLC 地址；PrizePool 构造已需 SalesChannel 地址。
  无环（GLC → SalesChannel → PrizePool）。部署后**必须**给两个 PrizePool 补授 SalesChannel 的
  `PARTNER_CONTRACT_ROLE`。本地部署文件（各仓 `ScratchCardLocal.js` / GreatLottoCore 本地模块 + 对应
  `ignition/parameters/localhost.json`）须补充授权步骤与 SalesChannel/GLC 地址，否则本地分润记账会因缺角色 revert。
- **D3（定稿：全新处理）**：新合约全新部署（id 从 1 起），不做历史迁移；旧 EOA 收款数据不继承。
- **D4（定稿：校验 + 提到自己）**：`withdraw` 强制 `msg.sender == _channel[chnId].chn`，全额提到调用方自己，
  不接受任意 `to`，规避钓鱼授权。
- **D5 0 分润**：`benefit == 0`（极小额或费率被调 0）时 `_channelBenefitTransfer` 早退不记账，避免空转账 + 空事件。
- **D6 status 移除的副作用**：原 `_channelBenefitTransfer` 用 status 做存在性判据；移除后改用 `chn == address(0)`
  判存在性，语义等价（注册必写 chn，未注册读零地址）。链下若依赖 `status` 字段需同步下线。

## 7. 验收

- `forge test`（infra/ScratchCard/GreatLottoCore）全绿；覆盖率不低于现状
- 偿付能力 invariant：`balanceOf(SalesChannel) >= Σ pendingOf`
- 合约体积仍在 EIP-170 内
- `/flow-review-spec` 6 维过 → `requesting-code-review` → `/security-review`（合约仓必跑）
- interface ABI 同步后渠道页可注册 / 改名 / 分页列出 / 查看待提 / 提取
