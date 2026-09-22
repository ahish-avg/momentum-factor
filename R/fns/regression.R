# R/fns/regression.R
# FF3 回归 + Newey-West t 值（学术严谨性关键点，不用普通 OLS t 值）

#' 对单个 param_window 的 winner-loser (quintile=6) 组合做 FF3 回归
#' 返回 alpha、beta 及其 Newey-West t 值
run_ff3_regressions <- function(merged_data, param_windows) {
  results <- lapply(param_windows, function(pw) {
    d <- merged_data[merged_data$param_window == pw & merged_data$quintile == 6, ]
    d <- d[order(d$mth), ]
    if (nrow(d) < 24) {
      return(data.frame(
        param_window = pw, term = NA, estimate = NA, nw_t = NA, nw_p = NA, n_obs = nrow(d)
      ))
    }

    d$excess_ret <- d$ret - d$rf

    fit <- lm(excess_ret ~ mkt_rf + smb + hml, data = d)

    # Newey-West 稳健标准误，lag 用经验法则 floor(4*(T/100)^(2/9))
    n <- nrow(d)
    nw_lag <- max(1, floor(4 * (n / 100)^(2 / 9)))
    nw_vcov <- sandwich::NeweyWest(fit, lag = nw_lag, prewhite = FALSE, adjust = TRUE)
    nw_test <- lmtest::coeftest(fit, vcov. = nw_vcov)

    out <- as.data.frame(nw_test[, ])
    out$term <- rownames(nw_test)
    names(out) <- c("estimate", "std_error", "nw_t", "nw_p", "term")
    out$param_window <- pw
    out$n_obs <- n
    out[, c("param_window", "term", "estimate", "std_error", "nw_t", "nw_p", "n_obs")]
  })
  do.call(rbind, results)
}

#' 夏普比率、最大回撤（PerformanceAnalytics），针对 winner-loser 组合
compute_risk_metrics <- function(merged_data, param_windows) {
  results <- lapply(param_windows, function(pw) {
    d <- merged_data[merged_data$param_window == pw & merged_data$quintile == 6, ]
    d <- d[order(d$mth), ]
    if (nrow(d) < 2) {
      return(data.frame(param_window = pw, sharpe = NA, max_drawdown = NA))
    }
    ret_xts <- xts::xts(d$ret, order.by = d$mth)
    sharpe <- as.numeric(PerformanceAnalytics::SharpeRatio.annualized(ret_xts, Rf = mean(d$rf, na.rm = TRUE)))
    mdd <- as.numeric(PerformanceAnalytics::maxDrawdown(ret_xts))
    data.frame(param_window = pw, sharpe = sharpe, max_drawdown = mdd)
  })
  do.call(rbind, results)
}

#' 汇总参数稳健性表：alpha / NW t 值 / 夏普 并排展示
#' 诚实原则：不显著的窗口也照写，不做筛选或美化
build_robustness_table <- function(reg_results, risk_metrics) {
  alpha_rows <- reg_results[reg_results$term == "(Intercept)", ]
  merged <- dplyr::left_join(alpha_rows, risk_metrics, by = "param_window")
  merged[, c("param_window", "estimate", "nw_t", "nw_p", "sharpe", "max_drawdown", "n_obs")]
}
