# tests/fixtures/make_fixtures.R
#
# Deterministic synthetic WRDS-shaped fixture generator.
#
# PURPOSE: the real WRDS exports under data/ are gitignored (redistribution
# restrictions), so CI has no data to run the pipeline against. This script
# generates a small, fully deterministic synthetic panel with the exact same
# column layout as the real exports, so the CI can execute the entire
# SQL 01->05 + targets + testthat path end-to-end.
#
# THIS IS NOT REAL MARKET DATA. Do not use it for any inference. It exists
# purely so that schema, signal construction, portfolio aggregation, turnover,
# regression, and plotting code paths are all exercised on every push.
#
# Design notes on the synthetic panel:
#   - Per-stock returns are AR(1) in the latent component, which produces
#     genuine cross-sectional autocorrelation, i.e. a real (if artificial)
#     momentum signal. Without this the quintile spread would be degenerate.
#   - n_stocks = 40 and n_months = 72 gives F12_S1 roughly 60 months of
#     portfolio returns, comfortably above the 24-month regression floor in
#     run_ff3_regressions(), so no window silently degrades to NA.
#   - Deliberate edge cases included, each exercising a documented code path:
#       * permno 90001, 90002 are ETFs (securitytype='FUND') -> must be
#         excluded by the universe filter in sql/02_load_wrds.sql
#       * permno 90003 appears only in the final 8 months -> must produce no
#         momentum_signal row for F12_S1 (insufficient-history boundary)
#       * permno 10001 at the second month is duplicated verbatim -> must be
#         collapsed by the GROUP BY / MAX(ret) dedup without a PK violation
#
# Usage:  Rscript R/tests/fixtures/make_fixtures.R [--out DIR] [--force]
#
#   --out DIR    write fixtures to DIR instead of ./data
#   --force      overwrite existing fixture files (default: refuse)
#
# SAFETY: ./data/ normally holds the real (137MB, gitignored) WRDS exports.
# Running this script with the default output path would clobber them, so the
# script refuses to overwrite an existing non-trivial file unless --force is
# given. In CI, data/ is empty and the default path is used.
#
# Output: <out>/crsp_monthly.csv, <out>/ff_factors.csv

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) {
  i <- which(args == flag)
  if (length(i) == 0) return(default)
  if (i == length(args)) stop(sprintf("missing value for %s", flag))
  args[i + 1]
}
out_dir  <- get_arg("--out", "data")
force    <- "--force" %in% args

suppressPackageStartupMessages({
  ok <- requireNamespace("lubridate", quietly = TRUE)
  if (!ok) stop("lubridate is required (available via renv). Run renv::restore() first.")
})

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

crsp_path <- file.path(out_dir, "crsp_monthly.csv")
ff_path   <- file.path(out_dir, "ff_factors.csv")

# Refuse to clobber anything that looks like a real WRDS export.
check_safe <- function(path) {
  if (!file.exists(path)) return(invisible(NULL))
  size_mb <- file.size(path) / 1024^2
  if (!force && size_mb > 1) {
    stop(sprintf(
      paste0("refusing to overwrite %s (%.1f MB) — this looks like a real ",
             "WRDS export, not a fixture. Re-run with --force if you really ",
             "mean it, or use --out to write elsewhere."),
      path, size_mb
    ), call. = FALSE)
  }
}
check_safe(crsp_path)
check_safe(ff_path)

set.seed(19930101)

n_stocks <- 40
n_months <- 72
month_ends <- lubridate::ceiling_date(
  seq(as.Date("1990-01-01"), by = "month", length.out = n_months), "month"
) - lubridate::days(1)

# --- Latent return-generating process -------------------------------------
# AR(1) market factor
mkt <- numeric(n_months)
mkt_eps <- rnorm(n_months, mean = 0.005, sd = 0.045)
for (t in 2:n_months) mkt[t] <- 0.10 * mkt[t - 1] + mkt_eps[t]

# Per-stock AR(1) idiosyncratic component -> cross-sectional momentum
idio <- matrix(0, n_stocks, n_months)
for (i in seq_len(n_stocks)) {
  e <- rnorm(n_months, mean = 0, sd = 0.045)
  for (t in 2:n_months) idio[i, t] <- 0.20 * idio[i, t - 1] + e[t]
}
rets <- mkt[col(idio)] + idio

# --- Common stock rows ----------------------------------------------------
crsp <- data.frame(
  permno          = rep(10001L + seq_len(n_stocks) - 1L, each = n_months),
  mth             = rep(format(month_ends, "%Y-%m-%d"), times = n_stocks),
  securitytype    = "EQTY",
  securitysubtype = "COM",
  sharetype       = "NS",
  ret             = sprintf("%.8f", as.numeric(t(rets))),
  delflg          = "",
  stringsAsFactors = FALSE
)

# --- Edge case 1: ETFs, must be filtered out by securitytype --------------
etf <- data.frame(
  permno          = c(90001L, 90002L),
  mth             = rep(format(month_ends[1:6], "%Y-%m-%d"), each = 2),
  securitytype    = "FUND",
  securitysubtype = "ETF",
  sharetype       = "NS",
  ret             = sprintf("%.8f", 0.01),
  delflg          = "",
  stringsAsFactors = FALSE
)

# --- Edge case 2: short-history stock, must yield no F12_S1 signal --------
short <- data.frame(
  permno          = 90003L,
  mth             = format(month_ends[(n_months - 7):n_months], "%Y-%m-%d"),
  securitytype    = "EQTY",
  securitysubtype = "COM",
  sharetype       = "NS",
  ret             = sprintf("%.8f", rnorm(8, 0.005, 0.04)),
  delflg          = "",
  stringsAsFactors = FALSE
)

# --- Edge case 3: verbatim duplicate (permno, mth) row, must be collapsed --
dup <- crsp[crsp$permno == 10001 & crsp$mth == format(month_ends[2], "%Y-%m-%d"), ]

crsp_all <- rbind(crsp, etf, short, dup)
write.csv(crsp_all, file.path(out_dir, "crsp_monthly.csv"), row.names = FALSE, quote = FALSE)

# --- Fama-French factors (decimal units, matching the real WRDS export) ---
ff <- data.frame(
  mth    = format(month_ends, "%Y-%m-%d"),
  mkt_rf = sprintf("%.8f", mkt),
  smb    = sprintf("%.8f", rnorm(n_months, 0.002, 0.02)),
  hml    = sprintf("%.8f", rnorm(n_months, 0.001, 0.02)),
  rmw    = sprintf("%.8f", rnorm(n_months, 0.001, 0.015)),
  cma    = sprintf("%.8f", rnorm(n_months, 0.001, 0.015)),
  rf     = sprintf("%.8f", rnorm(n_months, 0.003, 0.001))
)
write.csv(ff, file.path(out_dir, "ff_factors.csv"), row.names = FALSE, quote = FALSE)

cat(sprintf("wrote %s (%d rows) and %s (%d rows)\n",
            file.path(out_dir, "crsp_monthly.csv"), nrow(crsp_all),
            file.path(out_dir, "ff_factors.csv"), nrow(ff)))
