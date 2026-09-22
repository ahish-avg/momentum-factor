library(targets)

tar_option_set(
  packages = c("DBI", "RMariaDB", "dplyr", "tidyr", "broom", "sandwich", "lmtest", "PerformanceAnalytics", "ggplot2", "plotly", "htmlwidgets")
)

source("R/fns/db.R")
source("R/fns/regression.R")
source("R/fns/cost_sensitivity.R")
source("R/fns/plots.R")

list(
  tar_target(param_windows, c("F3_S1", "F6_S1", "F12_S1", "F12_S3")),
  tar_target(port_returns_raw, load_port_returns()),
  tar_target(ff_factors_raw, load_ff_factors()),

  tar_target(
    merged_data,
    merge_port_ff(port_returns_raw, ff_factors_raw)
  ),

  tar_target(
    reg_results,
    run_ff3_regressions(merged_data, param_windows),
    pattern = map(param_windows)
  ),

  tar_target(
    risk_metrics,
    compute_risk_metrics(merged_data, param_windows),
    pattern = map(param_windows)
  ),

  tar_target(
    robustness_table,
    build_robustness_table(reg_results, risk_metrics)
  ),

  tar_target(
    turnover_by_window,
    load_turnover()
  ),

  tar_target(
    cost_sensitivity,
    run_cost_sensitivity(merged_data, turnover_by_window, param_windows)
  ),

  tar_target(
    plot_robustness,
    plot_robustness_table(robustness_table),
    format = "file"
  ),

  tar_target(
    plot_cost_curve,
    plot_cost_sensitivity(cost_sensitivity),
    format = "file"
  ),

  tar_target(
    plot_robustness_plotly,
    plot_robustness_table_plotly(robustness_table),
    format = "file"
  ),

  tar_target(
    plot_cost_curve_plotly,
    plot_cost_sensitivity_plotly(cost_sensitivity),
    format = "file"
  )
)
