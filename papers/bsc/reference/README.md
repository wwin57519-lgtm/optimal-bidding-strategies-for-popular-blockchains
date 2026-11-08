# BSC V2 开盘买入执行合约

[V2LaunchExecutor.sol](V2LaunchExecutor.sol) 是一个可独立编译的参考实现。每轮接受一次成功买入，资金来自合约预存的 ERC-20。主买单按配置把代币发给指定地址，也可以留在合约里供管理员卖出。设计参考了已部署合约的公开买入、试买试卖和提款流程。 [链上参考合约](https://bscscan.com/address/0x83b0a2478b82897e1d6fb31e43ff43f8e736fe27)

新版使用本地所有权与轮次管理，买入入口可设为仅管理员或公开触发。轮次编号绑定一组配置和截止时间，重置或改配置后，旧轮次的交易会回滚。每次兑换只授予该次输入量，完成后清零授权。

## 使用

1. 用 Solidity `0.8.30` 编译，部署时传入 `initialOwner`。本地测试使用 `paris` EVM 目标和优化器 200 runs。
2. 将支付币转入合约。使用 BNB 作为本金时，先转换成 WBNB 再转入。BSC PancakeSwap V2 Router 为 `0x10ED43C718714eb63d5aA57B78B54704E256024E`，WBNB 为 `0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c`。 [PancakeSwap V2 路由](https://docs.pancakeswap.finance/welcome-to-pancakeswap/contact-us/faq/troubleshooting)
3. 管理员调用 `configure(config, deadline)` 创建轮次。可在池子创建前完成配置。截止时间使用 Unix 秒。发单方读取 `roundId()` 并调用 `buy(roundId)`。
4. 需要由合约卖出时，把 `recipient` 配置为合约自身。主买单成功后，管理员调用 `sell(roundId, minOut, deadline)` 卖出合约持有的全部目标币，支付币回到合约。

| 配置字段 | 含义 |
| --- | --- |
| `paymentToken`、`targetToken`、`router` | 单跳 V2 交易使用的支付币、目标币和路由 |
| `recipient` | 主买单收款地址 |
| `maxBuyIn` | 试买和主买入的合计支付上限，以支付币最小单位计 |
| `minPaymentReserve` | 池中已同步的支付币储备下限，以支付币最小单位计 |
| `minBuyOut` | 主买单实际到账下限，以目标币最小单位计，必须大于零 |
| `maxQuoteShortfallBps` | 实际到账相对当次路由报价允许少收的基点数。`10000` 只使用绝对到账下限 |
| `probeBuyBps`、`probeSellBps` | 试买占可用买入预算的比例，以及试卖占本次试买实际到账的比例。`100` 表示 1%，两个值均为零时关闭试买试卖 |
| `publicBuy` | `true` 允许任何地址触发。两种模式均按 `recipient` 交付 |

试卖要求至少回收一个最小单位的支付币。试买、试卖或主买入任一步失败，整笔交易回滚。报价使用交易执行时的池状态，绝对到账下限由 `minBuyOut` 单独约束。兑换走 V2 的转账税兼容入口，并按余额变化核对实际支付和到账。支付币与卖出的目标币须按名义输入金额扣款。 [路由源码](https://github.com/pancakeswap/pancake-swap-periphery/blob/master/contracts/PancakeRouter.sol)

管理员可以用 `cancelBuy(roundId)` 取消尚未成交的轮次，或用 `init(deadline)` 沿用配置开启新轮次。使用 `withdrawToken(token, amount)` 和 `withdrawBNB(amount)` 提款，`type(uint256).max` 表示全额。所有权转移由现任管理员提名，再由被提名人接受。

## 本地验证

进入本目录，在 Node.js 环境运行以下命令。

```sh
npm install --ignore-scripts --no-audit --no-fund
npm test
```

9 项回归覆盖池子尚未开放、并发只成交一次、重入、转账税及最低到账、试卖失败回滚、卖出、过期轮次和提款权限。另在本地 EVM 加载 BSC 区块 `132403232` 的 PancakeSwap V2 Router 与 Factory 运行字节码，用模拟转账税代币和本地新池跑通了试买、试卖、主买入与卖出。验证范围为本地 EVM。 [字节码取样区块](https://bscscan.com/block/132403232)
