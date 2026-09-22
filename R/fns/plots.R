# R/fns/plots.R
# Plotting functions: parameter robustness comparison + transaction cost decay curve

plot_robustness_table <- function(robustness_table) {
  path <- "output/robustness_alpha.png"
  p <- ggplot2::ggplot(robustness_table, ggplot2::aes(x = param_window, y = estimate)) +
    ggplot2::geom_col(fill = "#2c7fb8") +
    ggplot2::geom_errorbar(
      ggplot2::aes(ymin = estimate - 1.96 * (estimate / nw_t), ymax = estimate + 1.96 * (estimate / nw_t)),
      width = 0.2
    ) +
    ggplot2::labs(
      title = "Winner-Loser Alpha by Parameter Window (Newey-West 95% CI)",
      x = "Parameter Window (Formation-Skip)", y = "Monthly Alpha"
    ) +
    ggplot2::theme_minimal()
  ggplot2::ggsave(path, p, width = 7, height = 5)
  path
}

plot_cost_sensitivity <- function(cost_sensitivity) {
  path <- "output/cost_sensitivity.png"
  curve <- cost_sensitivity$curve
  p <- ggplot2::ggplot(curve, ggplot2::aes(x = cost_bps, y = net_alpha, color = param_window)) +
    ggplot2::geom_line() +
    ggplot2::geom_hline(yintercept = 0, linetype = "dashed", color = "gray40") +
    ggplot2::labs(
      title = "Alpha Decay Under Transaction Cost (0-50bps)",
      x = "Round-trip Cost (bps)", y = "Net Monthly Alpha", color = "Window"
    ) +
    ggplot2::theme_minimal()
  ggplot2::ggsave(path, p, width = 7, height = 5)
  path
}
