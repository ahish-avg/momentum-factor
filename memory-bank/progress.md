# Progress

## 已完成
- [x] SQL 管线 01-05（schema / 加载 / 信号 / 组合 / 换手）在 MySQL 8 实测通过
- [x] R targets 管线：FF3 + Newey-West 回归、风险指标、交易成本敏感性
- [x] 15 项 testthat 用例通过（含独立重算的前视偏差检查）
- [x] 代码审查发现并修复 `sql/04_portfolios.sql` 两层平均聚合偏差（改单层平均）
- [x] SQL/R 注释中译英
- [x] 学术双语 README（`README.md` + `README.zh-CN.md`）
- [x] GitHub 仓库创建并推送：https://github.com/ahish-avg/momentum-factor
- [x] 交互式 plotly 图表（`output/robustness_alpha.html`、`output/cost_sensitivity.html`，各约 3.8MB 自包含）
- [x] 静态 PNG 纳入 git 追踪并推送
- [x] README 双语新增 §5.1 图表小节
- [x] 管线幂等性验证（二次运行 19 skipped / 0 completed）

## 进行中
（无）

## 待办
- [ ] 可选：GitHub Pages 托管交互图表
- [ ] 可选：`renv::snapshot()` 固化 plotly / htmlwidgets 版本
- [ ] 研究层面（README §6 已列）：流动性/市值筛选、2008 前后子区间分析、持仓期衰减按市场环境拆解

## 核心结论
仅 F6_S1（6-1）显著（NW t=2.60, p=0.010）；F12_S1 / F12_S3 未能复现 JT1993（alpha 为负、回撤 >85%）。
