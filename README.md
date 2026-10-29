# 热门区块链的最优竞价策略

研究热门区块链上新池开盘时的交易排序、竞价与首笔成功买入策略。目前收录 Base 与 Solana 论文，覆盖 Uniswap / Aerodrome 新池开盘和 Pump 已知 mint 的首买竞争。

## 阅读论文

### Solana：开盘首买与最优竞价策略（案例与参数版）

- [在线阅读](papers/solana/solana-launch-first-buy-v2.md)
- [下载 PDF（13 页）](papers/solana/solana-launch-first-buy-v2.pdf)
- [可编辑文字版](papers/solana/solana-launch-first-buy-v2.txt)
- [参考资料](papers/solana/sources.json) · [链上证据](papers/solana/case-evidence.json) · [校验清单](papers/solana/manifest.json)

新增 gas / 优先费、tip / 收款账户、CU、提前量和发送频率的选择规则与完整数值演示，并补充总预算约束、首发前冻结与有效重试决策；区分官方机制、可核验案例与未实测起测档。案例发现首笔买入属于创建者同一账户，不能作为排除项目方后的外部首买胜出证据。尚未建立主网最优费率或首买胜率。

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

Base 论文为 4 页、13 条参考资料；Solana v2.1 为 13 页、17 条第一方资料。两篇 PDF 均已逐页检查排版，文字版与 Markdown 版由对应修订内容生成。Base 文件校验值见根目录 [manifest.json](manifest.json)，Solana 文件校验值见 [独立清单](papers/solana/manifest.json)。

本仓库存放论文及其参考资料，不包含实盘执行程序、待广播交易或账户凭据；链上案例中的签名为公开历史交易标识。仓库英文路径对应中文标题“热门区块链的最优竞价策略”。
