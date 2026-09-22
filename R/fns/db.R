# R/fns/db.R
# Database read functions: the R layer is read-only and performs no
# portfolio construction or recomputation of its own. All portfolio
# construction, quintile sorting, and aggregation happen in SQL
# (sql/03_signal.sql through sql/05_turnover.sql).

db_connect <- function() {
  DBI::dbConnect(
    RMariaDB::MariaDB(),
    host     = Sys.getenv("MOMENTUM_DB_HOST", "127.0.0.1"),
    port     = as.integer(Sys.getenv("MOMENTUM_DB_PORT", "3306")),
    dbname   = Sys.getenv("MOMENTUM_DB_NAME", "momentum_factor"),
    user     = Sys.getenv("MOMENTUM_DB_USER", "root"),
    password = Sys.getenv("MOMENTUM_DB_PASSWORD", "")
  )
}

#' Read monthly portfolio returns (quintiles 1-6; 6 is the winner-loser spread)
load_port_returns <- function() {
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con))
  DBI::dbGetQuery(con, "SELECT mth, quintile, param_window, ret, n_stocks, turnover FROM port_returns")
}

#' Read Fama-French factors
load_ff_factors <- function() {
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con))
  DBI::dbGetQuery(con, "SELECT mth, mkt_rf, smb, hml, rmw, cma, rf FROM ff_factors")
}

#' Read turnover (grouped by param_window)
load_turnover <- function() {
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con))
  DBI::dbGetQuery(con, "SELECT mth, quintile, param_window, turnover FROM turnover")
}

#' Merge portfolio returns with Fama-French factors (aligned by month);
#' this is a pure join, no recomputation of any values
merge_port_ff <- function(port_returns, ff_factors) {
  port_returns$mth <- as.Date(port_returns$mth)
  ff_factors$mth <- as.Date(ff_factors$mth)
  dplyr::inner_join(port_returns, ff_factors, by = "mth")
}
