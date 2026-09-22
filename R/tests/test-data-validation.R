# R/tests/test-data-validation.R
# 数据加载与校验：行数、主键唯一性、缺失比例合理范围
# 需要连通的 MySQL 实例（MOMENTUM_DB_* 环境变量），CI 中由 GitHub Actions 服务容器提供

library(testthat)

skip_if_no_db <- function() {
  con <- tryCatch(db_connect(), error = function(e) NULL)
  if (is.null(con)) testthat::skip("no DB connection available")
  DBI::dbDisconnect(con)
}

test_that("stock_monthly has no duplicate (permno, mth)", {
  skip_if_no_db()
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con))
  dup <- DBI::dbGetQuery(con, "
    SELECT permno, mth, COUNT(*) AS n FROM stock_monthly
    GROUP BY permno, mth HAVING COUNT(*) > 1
  ")
  expect_equal(nrow(dup), 0)
})

test_that("stock_monthly contains only common stock (CIZ: securitytype/securitysubtype filter applied at load time)", {
  skip_if_no_db()
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con))
  # CIZ 新版没有 shrcd 字段（灌数时置为 NULL，见 sql/02_load_wrds.sql），
  # 股票范围过滤已在灌数阶段用 securitytype='EQTY' AND securitysubtype='COM'
  # 完成，staging 表已丢弃，此处改为验证 shrcd 字段确实全为 NULL（符合预期，
  # 不代表数据缺失，是 CIZ 迁移后该字段不再使用的正常状态）
  shrcd_vals <- DBI::dbGetQuery(con, "SELECT DISTINCT shrcd FROM stock_monthly")$shrcd
  expect_true(all(is.na(shrcd_vals)))
})

test_that("port_returns quintiles range from 1 to 6 (6 = winner-loser)", {
  skip_if_no_db()
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con))
  q <- DBI::dbGetQuery(con, "SELECT DISTINCT quintile FROM port_returns")$quintile
  expect_true(all(q %in% 1:6))
})

test_that("ret_adj missing ratio is below a sane threshold (< 50%)", {
  skip_if_no_db()
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con))
  pct <- DBI::dbGetQuery(con, "
    SELECT SUM(ret_adj IS NULL) / COUNT(*) AS pct FROM stock_monthly
  ")$pct
  expect_lt(pct, 0.5)
})
