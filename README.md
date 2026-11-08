# 热门区块链的最优竞价策略

研究热门区块链上新池开盘时的交易排序、竞价与首笔成功买入策略。目前收录 Ethereum、BSC、Base、Solana 和 Robinhood Chain 论文，覆盖时间戳开盘、DEX 新池开盘和 Pump 已知 mint 的首买竞争。

## 阅读论文

### 以太坊 MEV Bundle 竞价与开盘执行（5 页）

- [阅读 PDF](papers/ethereum/ethereum-mev-bundle-execution-20261107.pdf)
- [可编辑文字版](papers/ethereum/ethereum-mev-bundle-execution-20261107.txt)

2026 年 11 月 7 日修订。包含三笔历史付款、1 ETH 买入算例、正点开盘的发送时序和低成本提前量试验。接入口往返与 relay 出价时间已有观测，主网最优提前量和首买胜率仍待对照验证。

### BSC 开盘竞价与首笔买入策略

- [阅读 PDF（10 页）](papers/bsc/bsc-launch-sniping-concise.pdf)
- [下载可编辑 Word 版](papers/bsc/bsc-launch-sniping-concise.docx)
- [V2 开盘买入合约源码与本地测试](https://github.com/wwin57519-lgtm/bsc-v2-launch-executor)

2026 年 10 月 31 日修订。以 CT 为案例，说明普通广播与私有 MEV bundle 的发送时序、钱包与 nonce 管理、Gas 和 tip 设置，以及两条入口共享的买入锁和首块限制。

### Base：参数与合约版（7 页）

- [在线阅读具体参数方案](papers/base/base-launch-sniping-parameters.md)
- [下载参数与合约版 PDF](papers/base/base-launch-sniping-parameters.pdf)
- [可编辑文字版](papers/base/base-launch-sniping-parameters.txt)
- [机器可读配置](papers/base/reference_profile.json)
- [参考合约与本地测试](papers/base/reference/README.md)

给出 gasLimit、动态 Max Fee、Max Priority、50 钱包发送节奏和 RPC 主备结构。nonce 采用启动时校准、发送时本地递增、后台异步对账；不逐笔查询 RPC，不固定限制在途笔数。既有 14 项本地合约测试通过；50 个模拟钱包触发后恰好 1 笔成功。历史成功路径分叉未通过，因此这些参数仍是研究起点，不能称为已验证的主网最优。

### Solana：新币首买最优竞价策略（v3.0 执行与案例版）

- [在线阅读](papers/solana/solana-launch-first-buy-v3.md)
- [下载 PDF（8 页）](papers/solana/solana-launch-first-buy-v3.pdf)
- [可编辑文字版](papers/solana/solana-launch-first-buy-v3.txt)
- [参考资料](papers/solana/sources.json) · [新增付款案例](papers/solana/case-payments-v3.json) · [校验清单](papers/solana/manifest.json)
- [历史 v2.1（13 页）](papers/solana/solana-launch-first-buy-v2.pdf)

六项设置集中为执行表：CU、gas / 优先费、tip、提前量、频率、官方收款账户。新增同一开盘内不同 tip 付款的链上核验及明示延迟假设的定时案例；将“固定其余条件后的预算上限最优”与尚未测得的 gas / tip 联合最优、主网首买胜率分开。提前 8ms 只属于设计模型；未知创建时间采用最早有效信号触发。

### Base：代币开盘狙击策略（简明版）

- [在线阅读：Base 代币开盘狙击策略（简明版）](papers/base/base-launch-sniping-concise.md)
- [下载 PDF（4 页）](papers/base/base-launch-sniping-concise.pdf)
- [可编辑文字版](papers/base/base-launch-sniping-concise.txt)
- [参考资料](papers/base/sources.json)

修订日期：**2026 年 10 月 29 日**。

## Base 论文结论

以不限制 gas 消耗、争取第一笔满足金额和价格约束的成功买入为目标，优先研究多钱包提前普通试单，并保留条件预提交作为补充。这是工程选型建议，尚未验证主网首买胜率排名。

LAPTOP 开盘区块中，与加池相同优先费的买入尝试紧随加池，略低优先费的交易排列其后。这支持将“匹配加池有效优先费”作为提前普通试单的基准；尚不能证明它优于更高出价，也不能证明发送频率越高、首买概率越高。

论文明确区分官方机制、链上案例和待检验推断。索引 86 为授权交易，不能当作目标池买单；多笔案例均来自同一次开盘，并非多个独立实验。

## 内容与校验

Base 简明版为 4 页、13 条参考资料，参数与合约版为 7 页、15 条参考资料；Solana v3.0 为 8 页、18 条第一方资料。上述 PDF 均已逐页检查排版，文字版与 Markdown 版由对应修订内容生成。Base 文件校验值见根目录 [manifest.json](manifest.json)，Solana 文件校验值见 [独立清单](papers/solana/manifest.json)。

本仓库存放论文、研究配置、参考合约和本地测试，不包含实盘机器人、待广播交易或账户凭据；链上案例中的签名为公开历史交易标识。仓库英文路径对应中文标题“热门区块链的最优竞价策略”。

## Robinhood Chain：开盘狙击案例与参数版（9 页）

- [阅读 PDF](papers/robinhood/robinhood-launch-sniping-parameters.pdf)
- [可编辑文字版](papers/robinhood/robinhood-launch-sniping-parameters.txt)
- [机器可读配置](papers/robinhood/reference_profile.json)
- [SHA-256 校验清单](papers/robinhood/manifest.json)

论文修订于 2026 年 10 月 29 日，上传于 2026 年 11 月 7 日。包含 TESTC2 案例、Gas 与费用上限、钱包与发送频率、nonce 管理、参考合约和 RPC 选型；新增与项目方开关或加流动性交易使用相同 maxPriorityFeePerGas 的配置，并明确同价不提供 FCFS 排序优势。参数为工程起点，未验证主网首买胜率或统计最优。
