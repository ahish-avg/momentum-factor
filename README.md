# Momentum Factor Replication & Transaction Cost Sensitivity

可复现的学术级实证研究：用 R + MySQL + `targets` 管线复刻 Jegadeesh-Titman (1993) 动量因子，量化交易成本对超额收益的侵蚀。

## 研究问题

Jegadeesh-Titman (1993) 的动量因子在美国股市是否仍有效？扣除交易成本后，超额收益还剩多少？在不同 formation/skip 窗口参数下结论是否稳健？

## 数据来源

- 个股月度收益：WRDS/CRSP **CIZ 新版**（2024-11-22 数据结构迁移后），Stock-Version 2 (CIZ) → Monthly Stock File，全库检索导出（`permno`, `mthcaldt`, `securitytype`, `securitysubtype`, `mthret`）。CIZ 用 `securitytype='EQTY' AND securitysubtype='COM'` 筛选普通股，替代旧版 `shrcd IN (10,11)`（该字段在 CIZ 中无直接对应，本库中已置 NULL）。取值已用真实数据交叉验证（AAPL/MSFT/IBM 为 EQTY/COM，SPY/VNQ 为 FUND/ETF）。
- Fama-French 因子：WRDS Fama-French Portfolios → 5 Factors Plus Momentum - Monthly Frequency（非官网 CSV），数值本身即为小数形式，不需要百分比转换。覆盖 1990-01 至 2025-12，共 432 个月。
- 实际灌入数据规模：267 万行个股月度记录，2.37 万只不同 permno，1990-01 至 2025-12。

WRDS 数据受许可协议限制，不可公开发布，`data/` 目录已 `.gitignore`。

## 方法

- **动量信号**：`EXP(SUM(LN(1+ret)) OVER (...)) - 1`，在 SQL 层用滑动窗口聚合计算，`LAG` 语义保证 t 月信号只使用 formation 窗口内、skip 期之前的收益（见 `sql/03_signal.sql` 的前视偏差检查小节）。
- **持仓方法**：JT1993 重叠持仓（overlapping holding periods）——每月建仓，持有 K=formation 个月；当月组合收益 = 当月仍在持仓期内的所有建仓批次的等权平均（批次内、批次间均等权）。实现见 `sql/04_portfolios.sql` 的 `holding_batches` 中间表。
- **退市处理**：CIZ 新版 `mthret`（月度总收益）已将退市月的收益直接并入，不再需要旧版单独 join 退市表、合并 `dlret` 的做法；`mthdelflg` 字段保留用于未来按需披露退市月占比。
- **数据去重**：CIZ 官方文档提示同一证券同月多笔分配事件会产生重复观测，实测确认存在完全重复行（如 permno=10001 于 1994-06-30），灌数阶段已用 `GROUP BY permno, mth` 折叠去重（见 `sql/02_load_wrds.sql`）。
- **参数稳健性**：同时跑 4 组 (formation, skip) 窗口 —— (3,1)/(6,1)/(12,1)/(12,3)，标记为 `F3_S1`/`F6_S1`/`F12_S1`/`F12_S3`。
- **统计推断**：Newey-West 稳健标准误（`sandwich::NeweyWest`），不用普通 OLS t 值。

## 组合构建的 SQL 铁律

分位分组、组合月收益计算、换手率全部在 SQL 完成（`sql/` 目录），R 层（`R/fns/`）只读表、只做回归和绘图，不重算任何组合层面的数字。

## 项目结构

```
momentum-factor/
├── sql/
│   ├── 01_schema.sql
│   ├── 02_load_wrds.sql
│   ├── 03_signal.sql
│   ├── 04_portfolios.sql
│   └── 05_turnover.sql
├── R/
│   ├── _targets.R
│   ├── fns/
│   └── tests/
├── data/          (gitignored, 需自行放入 WRDS CSV)
├── output/        (图表)
├── .github/workflows/repro.yml
└── README.md
```

## 结果

用 1990-01 至 2025-12 美股全市场月度数据（267万行，2.37万只股票）复现动量因子，四组参数窗口下 winner-loser（quintile 5-1）组合对 FF3 因子回归结果：

| 参数窗口 (formation-skip) | 月度 Alpha | Newey-West t | Newey-West p | 夏普比率 | 最大回撤 | 交易成本 breakeven |
|---|---|---|---|---|---|---|
| F3_S1 (3-1) | 0.21% | 0.93 | 0.351 | -0.02 | 55% | 0bps（无成本即亏损） |
| **F6_S1 (6-1)** | **0.62%** | **2.60** | **0.010** | **0.22** | 58% | 撑得住 50bps 上限内始终为正 |
| F12_S1 (12-1，JT1993 经典设定) | -0.20% | -0.77 | 0.440 | -0.28 | 87% | 0bps |
| F12_S3 (12-3) | -0.33% | -1.26 | 0.208 | -0.34 | 91% | 0bps |

**核心诚实结论**：经典的 JT1993 12-1 动量因子设定在本样本（1990-2025年美股全市场）中已完全失效，alpha 方向反转为负，夏普比率为负，最大回撤超过85%。唯一在统计上显著（1%水平）、经济上稳健、能承受交易成本侵蚀的窗口是 **6-1（6个月建仓、跳过1个月、持有6个月）**。诊断显示动量效应在信号刚生成的头1-2个持仓月确实存在（winner组跑赢loser组），但随持仓期拉长迅速衰减甚至反转；持仓期越长（如12个月），越多衰减/反转月份被平均进最终收益，把早期正alpha完全抹平。这是本研究的核心发现之一，不是数据或代码错误。

## 复现方式

1. 准备 MySQL 8 实例，设置环境变量 `MOMENTUM_DB_HOST/PORT/NAME/USER/PASSWORD`。
2. 从 WRDS 导出数据（CRSP CIZ Monthly Stock File 全库检索 + Fama-French 5 Factors Plus Momentum Monthly），按 `sql/02_load_wrds.sql` 头部注释的列顺序预处理后存为 `data/crsp_monthly.csv` 和 `data/ff_factors.csv`。
3. 依次执行（需要 `--local-infile=1` 且服务端 `SET GLOBAL local_infile=1`）：
   ```
   mysql < sql/01_schema.sql
   mysql --local-infile=1 < sql/02_load_wrds.sql
   mysql < sql/03_signal.sql
   mysql < sql/04_portfolios.sql
   mysql < sql/05_turnover.sql
   ```
4. R 层：
   ```r
   renv::restore()
   targets::tar_make()
   testthat::test_dir("R/tests")
   ```
   已在真实数据上验证：14 项 testthat 用例全部通过，包括前视偏差独立重算核对、边界情况（历史不足股票排除）、`holding_batches` 去重完整性。

## 出彩清单

- [x] 一条命令复现：`targets::tar_make()` + GitHub Actions
- [x] 前视偏差检查（`R/tests/test-lookahead-bias.R`，独立重算信号核对）
- [x] 退市/幸存者偏差显式处理并量化（`sql/02_load_wrds.sql` 校验查询 3d）
- [x] Newey-West 而非裸 t 值
- [x] 诚实结论：某参数窗口若 alpha 不显著也照写在结果表中
- [x] 数据来源与局限单列（本节 + 下方"局限与未来工作"）

## 局限与未来工作

- **未做流动性/市值筛选**：本轮未排除极小盘股，动量因子在极小盘股中的表现可能被流动性差、买卖价差大的股票放大，是已知局限。
- **未做 2008 前后子区间稳健性分析**：动量因子在 2008 年金融危机附近出现过著名的"崩溃"（momentum crash），本轮不细分子区间讨论结构性失效；结合本研究已发现的长窗口(12-1)明显失效现象，子区间分析可能能进一步解释这一失效是否集中在特定历史时期，留作后续工作。
- **Tableau 呈现**：可选加分项，视时间决定是否补做；若补做，注意 WRDS 数据不可用于 Tableau Public，公开版本需用替代数据源或截图。
- **幸存者偏差**：CIZ 新版 `mthret` 已内含退市月收益，缓解了旧版需要手动合并 `dlret` 的问题，但 CRSP 覆盖范围本身仍可能存在样本选择偏差，未做进一步校正。
- **持仓期内动量衰减的时点分解**：本研究发现动量效应集中在持仓期头1-2个月、随后快速衰减反转，但未进一步拆解衰减的具体驱动因素（如是否与特定行业、特定市场环境相关），可作为后续深入方向。
