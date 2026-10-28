# Read-only reproduction / 只读复核

修订：2026-10-29。全文见 [论文](solana-launch-first-buy-v2.md)，排版见 [PDF](solana-launch-first-buy-v2.pdf)。

本案例不能用来证明排除项目方后的外部首买胜率：第一笔买入与创建者使用同一 user / fee payer，跨交易 bundle 归属未知。发送时刻与频率无法由区块读数反推。数值参数属于未实测的起测配置。

`case-evidence.json` 包含四笔相关原始交易、完整解码摘要、两 RPC 交叉读回结果，以及本地原始证据的 SHA-256；其他无关区块交易未打包上传。

使用 `getBlock`，依次读取 slot `462631102`、`462631103`，参数为 `commitment=finalized`、`encoding=jsonParsed`、`transactionDetails=full`、`maxSupportedTransactionVersion=1`、`rewards=false`。示例公共端点：`https://api.mainnet-beta.solana.com`、`https://solana-rpc.publicnode.com`；未来历史保留、访问额度和接口可用性可能变化。

第一块检查从 0 计数的索引 41、42、43；第二块检查索引 11。按 Pump 官方 IDL 的程序 ID 与 discriminator 解码，核对 user、指令次序、签名和费用；不能只按日志中的 Create 字样筛选。

legacy/v0 的 CU limit 为 ComputeBudget 指令 discriminator 2 后的小端 u32，CU price 为 discriminator 3 后的小端 u64。优先费 lamports = ceil(limit × price / 1,000,000)。分别得到 150000、150000、150000、333000；再加签名基础费与 `meta.fee` 比对。

tip 只将 system transfer 的收款人匹配到当日官方账户列表；匹配不代表证明具体私有发送路径，未匹配也不代表没有其他付款。

未包含账户凭据、签名生成器或交易发送程序。校验值见 [manifest.json](manifest.json)；文献清单见 [sources.json](sources.json)。
