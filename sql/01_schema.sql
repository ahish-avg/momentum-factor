-- ============================================================
-- 01_schema.sql
-- Momentum Factor Replication — MySQL 8 schema
-- ============================================================

DROP TABLE IF EXISTS holding_batches;
DROP TABLE IF EXISTS port_returns;
DROP TABLE IF EXISTS turnover;
DROP TABLE IF EXISTS momentum_signal;
DROP TABLE IF EXISTS ff_factors;
DROP TABLE IF EXISTS stock_monthly;

-- ------------------------------------------------------------
-- Individual stock monthly returns (CRSP-style panel)
-- shrcd: legacy share code used to filter common stock (10,11),
-- excluding REITs/ADRs/preferred shares. Kept for schema
-- compatibility; see sql/02_load_wrds.sql for why this column
-- is NULL under the CIZ data format.
-- ------------------------------------------------------------
CREATE TABLE stock_monthly (
  permno  INT            NOT NULL,
  mth     DATE            NOT NULL,   -- End-of-month date
  shrcd   SMALLINT        NULL,       -- Legacy share code; 10/11 = common stock
  ret     DECIMAL(18,8)   NULL,       -- Total return including dividends
  dlret   DECIMAL(18,8)   NULL,       -- Delisting return (survivorship-bias handling)
  ret_adj DECIMAL(18,8)   NULL,       -- COALESCE(ret,0)+COALESCE(dlret,0), precomputed at load time; R layer reads this only
  PRIMARY KEY (permno, mth),
  KEY idx_stock_monthly_mth (mth)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- Fama-French factors (loaded from WRDS export)
-- ------------------------------------------------------------
CREATE TABLE ff_factors (
  mth    DATE PRIMARY KEY,
  mkt_rf DECIMAL(18,8), smb DECIMAL(18,8), hml DECIMAL(18,8),
  rmw    DECIMAL(18,8), cma DECIMAL(18,8), rf  DECIMAL(18,8)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- Momentum signal (parameterized: multiple formation/skip windows)
-- param_window naming convention: 'F{formation}_S{skip}', e.g. 'F12_S1'
-- ------------------------------------------------------------
CREATE TABLE momentum_signal (
  permno       INT           NOT NULL,
  mth          DATE          NOT NULL,   -- Signal formation month (end of formation period)
  param_window VARCHAR(16)   NOT NULL,
  formation    TINYINT       NOT NULL,   -- N: formation window length in months
  skip         TINYINT       NOT NULL,   -- S: skip period length in months
  mom_signal   DECIMAL(18,8) NULL,       -- Cumulative return over the past N months
                                          -- (skipping the most recent S months);
                                          -- named mom_signal to avoid the MySQL
                                          -- reserved word "signal"
  PRIMARY KEY (permno, mth, param_window),
  KEY idx_signal_mth_param (mth, param_window)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- Holding-batch expansion table (core intermediate table for
-- overlapping holding periods)
-- Each formation batch is expanded into one row per month it
-- contributes to the held portfolio.
-- ------------------------------------------------------------
CREATE TABLE holding_batches (
  formation_mth DATE        NOT NULL,   -- Formation (signal generation) month
  hold_mth      DATE        NOT NULL,   -- Month this batch contributes holding weight to
  permno        INT         NOT NULL,
  quintile      TINYINT     NOT NULL,   -- 1-5, quintile assignment within this batch
  param_window  VARCHAR(16) NOT NULL,
  ret           DECIMAL(18,8) NULL,     -- ret_adj for this stock during hold_mth, denormalized for aggregation
  PRIMARY KEY (formation_mth, hold_mth, permno, param_window),
  KEY idx_hb_hold (hold_mth, quintile, param_window)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- Portfolio monthly returns (computed and written back by SQL;
-- the R layer only reads this table)
-- ------------------------------------------------------------
CREATE TABLE port_returns (
  mth          DATE          NOT NULL,
  quintile     TINYINT       NOT NULL,   -- 1-5; 6 is reserved for the 5-1 winner-loser portfolio
  param_window VARCHAR(16)   NOT NULL,
  ret          DECIMAL(18,8) NULL,
  n_stocks     INT           NULL,
  turnover     DECIMAL(10,4) NULL,
  PRIMARY KEY (mth, quintile, param_window)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- Turnover (grouped by param_window, used for transaction cost
-- sensitivity analysis)
-- ------------------------------------------------------------
CREATE TABLE turnover (
  mth          DATE          NOT NULL,
  quintile     TINYINT       NOT NULL,
  param_window VARCHAR(16)   NOT NULL,
  turnover     DECIMAL(10,4) NULL,      -- Fraction of quintile membership that changed between consecutive periods
  PRIMARY KEY (mth, quintile, param_window)
) ENGINE=InnoDB;
