# System Patterns

## 架构分层

```
sql/ (01→05)              R/fns/                  R/_targets.R
  schema                    db.R (只读连接)    ──►  编排 + tar_target
  load WRDS                 regression.R (FF3+NW)      │
  momentum signal           risk_metrics               ▼
  portfolios + batches      cost_sensitivity       output/
  turnover                  plots.R (ggplot2+plotly)
```

## 关键设计决策

### 1. 组合构建全部在 SQL，R 层只读
R 绝不重新计算组合收益。所有分位排序、持仓期展开、收益聚合、换手率均在 SQL 完成。这保证了单点真相，也让 SQL 层的审查独立于统计层。

### 2. 前视偏差靠窗口帧边界语义消除
`signal_t` 用 `ROWS BETWEEN (N+S-1) PRECEDING AND S PRECEDING`，只要 S≥1 当前行必然被排除。这不是靠事后断言，而是靠 SQL 语义保证；正确性再由 `test-lookahead-bias.R` 独立重算验证。

### 3. 重叠持仓期用显式中间表
`holding_batches(formation_mth, hold_mth, permno, quintile, param_window, ret)` 把每个建仓批次展开为每月一行，使"单层等权平均"可被 SQL 直接表达。

### 4. 聚合必须是单层平均
**曾出现的缺陷**：先在批内求均值、再跨批求均值，隐含给"批次"而非"股票"等权。稳态月份活跃批次规模波动约 13%（如 F12_S1 quintile 1 在 2000-06-30 有 9 个活跃批次，1,243~1,409 只不等），引入了可量化偏差。已修正为单层 `AVG`。

### 5. 图表双轨模式
每个绘图函数成对存在：`plot_X()` → PNG（ggplot2），`plot_X_plotly()` → 自包含 HTML。两者消费同一份上游数据，保证数字一致。

### 6. targets 参数化模式
`param_windows` 必须声明为 `tar_target` 才能用于 `pattern = map()`。

## 代码风格约定
- 注释用英文（曾为中译英后的状态）
- 学术化命名：`nw_t`、`nw_p`、`param_window`、`gross_alpha`、`net_alpha`
- 函数头部用 roxygen 风格 `#'` 说明输入输出与设计理由
