# Active Context

## 当前状态
CI（repro.yml）已完全修复并转绿：12 步全通过。README §8 "verified in CI" 的承诺首次成为事实。

## 最近变更
- **CI 根因 1**：`renv::restore()` 编译 `igraph` 时缺 `libglpk.so.40`，ubuntu-latest 镜像未预装 `cmake`/`libglpk-dev`/`pandoc` → 补 apt 步骤
- **CI 根因 2**：`mysql` service 的 `--default-authentication-plugin` 被拼到 `docker create` 上被拒 → 移除（GH Actions service options 只能放镜像名之前，无法传给容器 CMD）
- **CI 根因 3（最实之一）**：`renv.lock` 未记录 plotly/htmlwidgets，CI restore 后 targets 报 "could not find packages" → `renv::snapshot()` 收口，锁文件 77 → 103 包
- **CI 从未真正验证过管线**：原工作流因 `data/` 无数据被 `if` 跳过 → 新增 `R/tests/fixtures/make_fixtures.R` 确定性合成数据，CI 首次真跑 SQL 01-05 + testthat + tar_make
- **`_targets.R` 移至项目根目录**：原先在 `R/` 下，README 承诺的 `targets::tar_make()` 在根目录根本跑不起来
- **`R/fns/plots.R`**：改为 `output_path()` 辅助函数按需创建 `output/`，不再假设目录存在
- **README 双语**：目录结构更新；测试数由误称的 15 更正为 8；补充 CI 与合成数据的说明

## 踩坑记录（重要，勿重犯）
1. **装新包必须 `renv::snapshot()`**：只在本地 renv library 装包而不更新锁文件，会让 CI 和所有 clone 者崩。本地那句 "project is out-of-sync" 警告不是可以忽略的噪音。
2. **GH Actions service options 不能传容器 CMD 参数**：`options` 字符串插在 `docker create` 的镜像名之前，mysqld 旗标会直接被 docker 拒绝。
3. **别让脚本写死 `data/`**：合成数据生成器初版会覆盖 137MB 真实 WRDS 导出，已加 >1MB 覆盖保护 + `--out` 参数。
4. **本地验证要用隔离库**：用 `MOMENTUM_DB_NAME=momentum_factor_ci` + 项目副本（排除 data/、renv 用符号链接），避免污染真实数据；测完 `DROP DATABASE`。

## 下一步
（无阻塞项）

## 待决策
- 可选：GitHub Pages 托管交互图表（目前 README 中是文件链接，非网页渲染）
- 可选：MySQL root 密码轮换（曾以明文提供）

## 安全提醒
仓库中无硬编码密码（`db.R` 全程 `Sys.getenv`）。CI 中的 `root`/`root` 仅为 GitHub Actions service container 的一次性容器凭证，非真实环境。
