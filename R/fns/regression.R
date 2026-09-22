# R/fns/regression.R
# FF3 regression + Newey-West t-statistics (a key academic rigor point;
# plain OLS t-statistics are not used)

#' Run an FF3 regression on the winner-loser (quintile=6) portfolio for
#' a single param_window.
#' Returns alpha, betas, and their Newey-West t-statistics.
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

    # Newey-West robust standard errors; lag chosen via the rule of
    # thumb floor(4*(T/100)^(2/9))
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

#' Sharpe ratio and maximum drawdown (via PerformanceAnalytics) for the
#' winner-loser portfolio
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

#' Assemble the parameter robustness table: alpha / Newey-West t / Sharpe
#' side by side.
#' Honesty principle: windows with insignificant alphas are reported
#' as-is, with no filtering or cosmetic adjustment.
build_robustness_table <- function(reg_results, risk_metrics) {
  alpha_rows <- reg_results[reg_results$term == "(Intercept)", ]
  merged <- dplyr::left_join(alpha_rows, risk_metrics, by = "param_window")
  merged[, c("param_window", "estimate", "nw_t", "nw_p", "sharpe", "max_drawdown", "n_obs")]
}
