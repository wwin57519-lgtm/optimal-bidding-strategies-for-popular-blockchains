# Solana 新币首买最优竞价策略

最新：**v3.0，2026-10-29，8 页，18 项第一方参考资料**。

- [在线阅读](solana-launch-first-buy-v3.md)
- [PDF](solana-launch-first-buy-v3.pdf)
- [可编辑文字版](solana-launch-first-buy-v3.txt)
- [文献与配置假设](sources.json) · [QA](qa.json) · [文件校验](manifest.json)
- [新增付款案例原始指令与两 RPC 核验](case-payments-v3.json)

新增同一开盘中 Sender / Jito 指定账户付款的对照，给出请求 CU、实耗 CU、CU 单价、原生优先费、tip 和总费用复算。它是付款案例，不是排除项目方后的首买胜率基准：创建者自己先买，其他账户归属和私有 bundle 未知，无法反推发送时间及频率。

操作案例明确假设有效路径延迟均匀在 8-12ms、对手到达在开盘后 15ms、时钟无误差；在该模型里，提前 8ms 是满足全窗口覆盖的最早发包点。它不是实测主网提前量。未知创建时间时，以最早有效创建信号触发为主。

固定其余条件、tip 被服务接受且排序对 tip 单调不减时，纯首买概率目标可把 tip 取到费用预算余量上限；论文明确这没有求解 gas 与 tip 的联合最优，也不是净利润最优。200,000 CU、0.01 SOL 优先费、0.1 SOL tip、25ms 间隔均为附条件演示档。

只读复核：读取 finalized 完整区块 `462631103`（索引 11）与 `462631108`（索引 179、181），索引从 0 开始。使用 `getBlock`、`encoding=jsonParsed`、`transactionDetails=full`、`maxSupportedTransactionVersion=1`。按 Pump 官方 IDL 与 ComputeBudget 指令解码；仅将匹配当日官方收款列表的 system transfer 标为识别出的 tip，不据此断言私有提交路径。

未包含账户凭据、待广播交易、签名生成器或实盘发送程序。案例 JSON 中的签名和原始记录均为公开历史交易。

## 历史版本

- [v2.1：13 页 PDF](solana-launch-first-buy-v2.pdf) · [文字版](solana-launch-first-buy-v2.txt)
- [v2.1 说明](README-v2.md) · [文献](sources-v2.json) · [QA](qa-v2.json) · [重命名路径后的历史校验](manifest-v2.json)
- [原始创建与首买边界案例](case-evidence.json)
