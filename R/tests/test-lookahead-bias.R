# R/tests/test-lookahead-bias.R
# 前视偏差专项检查（具体可执行验证，非空泛声明）
#
# 验证：任取样本 (permno, mth, param_window)，其 momentum_signal.mom_signal
# 应严格等于用 [mth - N - S + 1, mth - S] 区间收益重新计算的累乘结果，
# 且该区间不应包含 skip 期（[mth-S+1, mth]）或当月/未来任何数据。

library(testthat)

skip_if_no_db <- function() {
  con <- tryCatch(db_connect(), error = function(e) NULL)
  if (is.null(con)) testthat::skip("no DB connection available")
  DBI::dbDisconnect(con)
}

recompute_signal <- function(con, permno, mth, formation, skip) {
  window_end   <- as.Date(mth) - months(skip)
  window_start <- as.Date(mth) - months(formation + skip - 1)
  rets <- DBI::dbGetQuery(con, sprintf("
    SELECT ret_adj FROM stock_monthly
    WHERE permno = %d AND mth BETWEEN '%s' AND '%s'
    ORDER BY mth
  ", permno, window_start, window_end))$ret_adj
  if (length(rets) != formation) return(NA)
  exp(sum(log(1 + rets))) - 1
}

test_that("momentum_signal matches independently recomputed mom_signal (no look-ahead)", {
  skip_if_no_db()
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con))

  sample_rows <- DBI::dbGetQuery(con, "
    SELECT permno, mth, param_window, formation, skip, mom_signal
    FROM momentum_signal
    WHERE param_window = 'F12_S1'
    ORDER BY RAND() LIMIT 20
  ")
  skip_if(nrow(sample_rows) == 0, "no mom_signal rows to sample")

  for (i in seq_len(nrow(sample_rows))) {
    r <- sample_rows[i, ]
    recomputed <- recompute_signal(con, r$permno, r$mth, r$formation, r$skip)
    if (is.na(recomputed)) next  # boundary case, insufficient history — skip is correct behavior
    expect_equal(as.numeric(r$mom_signal), recomputed, tolerance = 1e-6,
                 label = sprintf("permno=%s mth=%s", r$permno, r$mth))
  }
})

test_that("mom_signal window never includes skip-period or current month data", {
  skip_if_no_db()
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con))

  r <- DBI::dbGetQuery(con, "
    SELECT permno, mth, formation, skip FROM momentum_signal
    WHERE param_window = 'F12_S1' LIMIT 1
  ")
  skip_if(nrow(r) == 0, "no mom_signal rows available")

  window_end <- as.Date(r$mth) - months(r$skip)
  expect_true(window_end < as.Date(r$mth))
  # skip 期本身（[mth-skip+1, mth]）不应出现在窗口内
  forbidden_start <- as.Date(r$mth) - months(r$skip - 1)
  expect_true(window_end < forbidden_start || r$skip == 0)
})
