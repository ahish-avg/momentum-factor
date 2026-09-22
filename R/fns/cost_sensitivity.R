# R/fns/cost_sensitivity.R
# 交易成本敏感性：换手率 x 0-50bps 成本区间 -> alpha 衰减曲线，标出 breakeven cost

#' net_alpha(cost) = gross_alpha - turnover * cost * 2  (买卖双边)
#' cost 以小数表示（例如 0.0050 = 50bps）
run_cost_sensitivity <- function(merged_data, turnover_by_window, param_windows) {
  costs <- seq(0, 0.0050, by = 0.0001)  # 0-50bps，步长 1bp

  results <- lapply(param_windows, function(pw) {
    d <- merged_data[merged_data$param_window == pw & merged_data$quintile == 6, ]
    if (nrow(d) == 0) return(NULL)

    gross_alpha_monthly <- mean(d$ret - d$rf, na.rm = TRUE)

    tw <- turnover_by_window[turnover_by_window$param_window == pw, ]
    avg_turnover <- mean(tw$turnover, na.rm = TRUE)
    if (is.na(avg_turnover)) avg_turnover <- 0

    df <- data.frame(
      param_window = pw,
      cost_bps = costs * 10000,
      gross_alpha = gross_alpha_monthly,
      avg_turnover = avg_turnover,
      net_alpha = gross_alpha_monthly - avg_turnover * costs * 2
    )
    df
  })
  out <- do.call(rbind, results[!sapply(results, is.null)])

  # breakeven cost：net_alpha 首次 <= 0 的成本水平（线性插值近似）
  breakeven <- do.call(rbind, lapply(param_windows, function(pw) {
    d <- out[out$param_window == pw, ]
    if (nrow(d) == 0 || all(d$net_alpha > 0)) {
      return(data.frame(param_window = pw, breakeven_bps = NA))
    }
    idx <- which(d$net_alpha <= 0)[1]
    if (idx == 1) {
      bps <- d$cost_bps[1]
    } else {
      x0 <- d$cost_bps[idx - 1]; y0 <- d$net_alpha[idx - 1]
      x1 <- d$cost_bps[idx];     y1 <- d$net_alpha[idx]
      bps <- x0 + (0 - y0) * (x1 - x0) / (y1 - y0)
    }
    data.frame(param_window = pw, breakeven_bps = bps)
  }))

  list(curve = out, breakeven = breakeven)
}
