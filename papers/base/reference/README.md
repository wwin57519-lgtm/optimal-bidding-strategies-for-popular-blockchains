# 固定池参考合约与测试

这是论文的研究代码，不是实盘机器人。没有审计，也没有通过 LAPTOP 开盘成功路径的历史分叉验证。

## 文件

- `FixedPoolLaunchBuyer.sol`：固定 V3 兼容池、固定本金和收币地址、触发钱包白名单、一次成功锁与回调支付检查。
- `MockLaunch.sol`：仅供本地测试的池与代币。
- `test_contract.cjs`：编译并在内存 Ganache 中执行 14 项测试，不连接主网。
- `contract_test_report.json`：本地结果及 gas；不能当主网入块或成功路径 gas 证明。
- `rpc_read_probe.json`：小样本公开 RPC 只读计时，不是交易提交基准。
- `historical_fork_report.json`：失败的历史重放记录，保留未验证状态。

## 运行本地测试

需要 Node.js。进入本目录后执行：

```sh
npm install --prefix evm --ignore-scripts --no-audit --no-fund
node test_contract.cjs
```

依赖固定为 solc 0.8.30、ethers 6.15.0、ganache 7.9.2。测试使用临时模拟账户。某些 Node 版本会让 Ganache 改用 JavaScript 网络实现；本文没有用它测排序性能。

## 本次结果

14 项测试通过，包括未开盘失败、失败回执消耗 nonce、最低到账回滚、回调鉴权、取消、禁止触发钱包提款，以及 50 个钱包触发共享合约后恰好一笔购买成功。

模拟池成功购买使用 148,195 gas。真实成功购买的 gasLimit 仍应通过相应真实状态的完整成功分叉估算，并保留余量。源码未实现 EOA nonce 调度、交易签名、RPC 提交或首买排名策略。
