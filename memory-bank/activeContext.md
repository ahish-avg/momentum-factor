# Active Context

## 当前状态
交互式图表功能已完成并推送至 GitHub（commit `a4a0ee4`）。

## 最近变更
- `R/fns/plots.R`：新增 `plot_robustness_table_plotly()` 与 `plot_cost_sensitivity_plotly()`，通过 `htmlwidgets::saveWidget(selfcontained = TRUE)` 生成自包含 HTML
- `R/_targets.R`：`param_windows` 从全局对象改为显式 `tar_target`（targets 要求 pattern 只能分支于已声明 target）；`tar_option_set` 增加 `plotly`、`htmlwidgets`
- `.gitignore`：移除 `output/*.png`（静态图需入库）；新增 `_targets/`
- `README.md` / `README.zh-CN.md`：新增 §5.1 图表小节，双语并列给出静态 PNG 与交互 HTML 链接

## 下一步
- 可选项：把交互图表迁到 GitHub Pages（`output/*.html` 目前是文件链接，非网页渲染）
- 可选项：`renv::snapshot()` 收口 plotly/htmlwidgets 依赖（当前提示 out-of-sync）

## 待决策
- 是否将 README 中的图表从文件链接改为 GitHub Pages 托管页面

## 安全提醒
MySQL root 密码在会话中以明文提供，建议轮换；仓库中未发现硬编码密码（`db.R` 全部走 `Sys.getenv`）。
