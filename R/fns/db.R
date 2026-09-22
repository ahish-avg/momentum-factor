# R/fns/db.R
# 数据库读取函数：R 层只读，不做任何组合构建/重算逻辑
# 组合构建、分位分组、聚合全部已在 SQL 层完成（sql/03_signal.sql ~ 05_turnover.sql）

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

#' 读取组合月收益（含 quintile 1-6，6 为 winner-loser）
load_port_returns <- function() {
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con))
  DBI::dbGetQuery(con, "SELECT mth, quintile, param_window, ret, n_stocks, turnover FROM port_returns")
}

#' 读取 FF 因子
load_ff_factors <- function() {
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con))
  DBI::dbGetQuery(con, "SELECT mth, mkt_rf, smb, hml, rmw, cma, rf FROM ff_factors")
}

#' 读取换手率（按 param_window 分组）
load_turnover <- function() {
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con))
  DBI::dbGetQuery(con, "SELECT mth, quintile, param_window, turnover FROM turnover")
}

#' 合并组合收益与 FF 因子（按月对齐），仅做 join，不做任何数值重算
merge_port_ff <- function(port_returns, ff_factors) {
  port_returns$mth <- as.Date(port_returns$mth)
  ff_factors$mth <- as.Date(ff_factors$mth)
  dplyr::inner_join(port_returns, ff_factors, by = "mth")
}
