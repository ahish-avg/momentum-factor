# Progress

## 已完成
- [x] SQL 管线 01-05（schema / 加载 / 信号 / 组合 / 换手）在 MySQL 8 实测通过
- [x] R targets 管线：FF3 + Newey-West 回归、风险指标、交易成本敏感性
- [x] testthat 用例通过（实测 8 个用例 / 13-14 个断言；含独立重算的前视偏差检查）
- [x] 代码审查发现并修复 `sql/04_portfolios.sql` 两层平均聚合偏差（改单层平均）
- [x] SQL/R 注释中译英
- [x] 学术双语 README（`README.md` + `README.zh-CN.md`）
- [x] GitHub 仓库创建并推送：https://github.com/ahish-avg/momentum-factor
- [x] 交互式 plotly 图表（`output/robustness_alpha.html`、`output/cost_sensitivity.html`，各约 3.8MB 自包含）
- [x] 静态 PNG 纳入 git 追踪并推送（原 `.gitignore` 误将 `output/*.png` 排除）
- [x] README 双语新增 §5.1 图表小节
- [x] 管线幂等性验证（二次运行全部 skipped）
- [x] 初始化 memory-bank（6 文件）
- [x] **CI 修复**：定位 renv 因缺 `libglpk-dev` 等系统库而失败的根因；补 apt 依赖
- [x] **CI 修复**：`_targets.R` 移至根目录，使 README 承诺的 `tar_make()` 真实可用
- [x] **CI 修复**：新增合成数据生成器，CI 首次能真正跑完整管线（此前全程 skip）
- [x] **CI 修复**：`plots.R` 改为按需创建 `output/` 目录
- [x] **文档纠错**：README 测试数 15 → 8（实测值）
- [x] 本地隔离库 `momentum_factor_ci` 全流程验证通过（SQL 01-05 + 8 测试 + tar_make）
- [x] **CI 转绿**：repro 工作流 12 步全通过（系统依赖 → renv → local_infile → 合成数据 → SQL 01-05 → testthat → tar_make）
- [x] `renv::snapshot()` 收口 plotly/htmlwidgets（锁文件 77 → 103 包），修复"clone 后 restore 必崩"的可复现性缺陷

## 进行中
（无）

## 待办
- [ ] 可选：GitHub Pages 托管交互图表
- [ ] 可选：`renv::snapshot()` 固化 plotly / htmlwidgets 版本
- [ ] 研究层面（README §6 已列）：流动性/市值筛选、2008 前后子区间分析、持仓期衰减按市场环境拆解

## 核心结论
仅 F6_S1（6-1）显著（NW t=2.60, p=0.010）；F12_S1 / F12_S3 未能复现 JT1993（alpha 为负、回撤 >85%）。
