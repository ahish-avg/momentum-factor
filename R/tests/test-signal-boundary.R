# R/tests/test-signal-boundary.R
# 边界情况：时间序列开头不足窗口长度的股票应被排除（mom_signal 计算层面）

library(testthat)

skip_if_no_db <- function() {
  con <- tryCatch(db_connect(), error = function(e) NULL)
  if (is.null(con)) testthat::skip("no DB connection available")
  DBI::dbDisconnect(con)
}

test_that("stocks with insufficient formation-window history produce no mom_signal row", {
  skip_if_no_db()
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con))

  # 找一个刚上市不久的 permno（历史长度 < 12 个月）
  short_hist <- DBI::dbGetQuery(con, "
    SELECT permno, COUNT(*) AS n_months, MIN(mth) AS first_mth
    FROM stock_monthly
    GROUP BY permno
    HAVING COUNT(*) < 12
    LIMIT 1
  ")
  skip_if(nrow(short_hist) == 0, "no short-history stock found in current dataset")

  p <- short_hist$permno[1]
  first_mth <- short_hist$first_mth[1]

  sig_count <- DBI::dbGetQuery(con, sprintf("
    SELECT COUNT(*) AS n FROM momentum_signal
    WHERE permno = %d AND param_window = 'F12_S1'
      AND mth <= DATE_ADD('%s', INTERVAL 12 MONTH)
  ", p, first_mth))$n

  expect_equal(sig_count, 0)
})

test_that("holding_batches never double-counts a (permno, hold_mth) within the same batch", {
  skip_if_no_db()
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con))

  dup <- DBI::dbGetQuery(con, "
    SELECT formation_mth, hold_mth, permno, param_window, COUNT(*) AS n
    FROM holding_batches
    GROUP BY formation_mth, hold_mth, permno, param_window
    HAVING COUNT(*) > 1
    LIMIT 5
  ")
  expect_equal(nrow(dup), 0)
})
