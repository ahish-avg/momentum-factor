# Active Context

## 当前状态
CI（repro.yml）三道红灯已定位根因并修复，等待推送后验证转绿。

## 最近变更
- **CI 根因**：`renv::restore()` 编译 `igraph` 时缺 `libglpk.so.40`，ubuntu-latest 镜像未预装 `cmake`/`libglpk-dev`/`pandoc`，导致 renv 步骤即失败，后续测试全未执行
- **`.github/workflows/repro.yml`**：新增 apt 系统依赖步骤；新增 `SET GLOBAL local_infile=1`；改为真跑完整 SQL 01→05 + testthat + tar_make（此前因无数据被 `if` 跳过，CI 从未真正验证过管线）
- **`_targets.R` 移至项目根目录**：原先在 `R/` 下，导致 README 承诺的 `targets::tar_make()` 在根目录根本跑不起来
- **`R/fns/plots.R`**：绘图函数硬编码 `output/` 路径，目录不存在即崩；改为 `output_path()` 辅助函数按需建目录
- **新增 `R/tests/fixtures/make_fixtures.R`**：确定性合成数据生成器，含 ETF 过滤、短历史股票、重复行三类边界用例；带 `--force`/`--out` 参数与 >1MB 覆盖保护（防止误删真实 WRDS 导出）
- **README 双语**：目录结构更新；测试数由误称的 15 更正为 8；补充 CI 与合成数据的说明

## 下一步
- 推送后确认 CI 转绿
- 若 `mysql:8.0` + RMariaDB 的 `caching_sha2_password` 认证出问题，工作流已加 `--default-authentication-plugin=mysql_native_password` 兜底

## 待决策
- 合成数据跑出的数值无意义，是否在 README 中已足够强调（目前已说明）

## 安全提醒
MySQL root 密码曾以明文提供，建议轮换；仓库中无硬编码密码（`db.R` 全程 `Sys.getenv`）。CI 中的 `root`/`root` 仅为 GitHub Actions service container 的一次性容器凭证，非真实环境。
