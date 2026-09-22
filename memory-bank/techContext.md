# Tech Context

## 技术栈
| 层 | 技术 |
|---|---|
| 数据库 | MySQL 8（`/usr/local/mysql/bin/mysql`，非 Homebrew，不在默认 PATH） |
| 数据库驱动 | R `RMariaDB` via `DBI` |
| 组合构建 | SQL 窗口函数 + `holding_batches` 中间表 |
| 统计 | `sandwich`（Newey-West）、`lmtest`、`PerformanceAnalytics` |
| 编排 | R `targets`，脚本位于 `R/_targets.R`（**非项目根目录**） |
| 绘图 | `ggplot2`（PNG）+ `plotly` + `htmlwidgets`（HTML） |
| 测试 | `testthat`，15 用例 |
| 依赖管理 | `renv` |

## 常用命令
```bash
# targets 管线（需显式指定 script，且脚本不在根目录）
MOMENTUM_DB_PASSWORD='***' Rscript -e 'targets::tar_make(script = "R/_targets.R")'

# 测试
Rscript -e 'testthat::test_dir("R/tests")'
```

## 环境变量
`MOMENTUM_DB_HOST` / `MOMENTUM_DB_PORT` / `MOMENTUM_DB_NAME` / `MOMENTUM_DB_USER` / `MOMENTUM_DB_PASSWORD`
（默认值 127.0.0.1:3306 / momentum_factor / root，密码无默认，必须显式提供）

## 已知坑
- `mysql` CLI 需用绝对路径 `/usr/local/mysql/bin/mysql`
- targets 的 `pattern = map(x)` 中 `x` 必须是已声明的 `tar_target`，不能是全局对象
- `htmlwidgets::saveWidget(selfcontained = TRUE)` 仍会顺带生成 `*_files/` 目录，可安全删除（HTML 已内联）
- CI 需 `--local-infile=1`（客户端）与 `SET GLOBAL local_infile=1`（服务端）

## 数据规模
2,667,625 条个股月度观测，23,700 个 permno，1990-01 至 2025-12（432 个月）。WRDS 数据在 `data/`，已 gitignore。
