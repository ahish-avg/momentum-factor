-- ============================================================
-- 05_turnover.sql
-- Turnover: membership difference between consecutive periods within
-- the same (quintile, param_window), used for transaction cost
-- sensitivity analysis
--
-- Definition: turnover_t = |members_t \ members_{t-1}| / |members_t|
--   i.e. the fraction of this month's quintile membership that was not
--   in the same quintile last month (newly entered positions).
-- Uses the expanded monthly membership set from holding_batches (not
-- the raw formation-time signal ranking), because the actual composition
-- of a held portfolio is the union of overlapping batches, and turnover
-- should reflect the realized change in holdings, not just the change
-- in newly-formed signal rankings.
-- ============================================================

TRUNCATE TABLE turnover;

-- Use a regular table (not TEMPORARY) to hold the membership set, to
-- avoid MySQL's "Can't reopen table" error, which occurs when a
-- TEMPORARY TABLE is referenced more than once within the same query
-- via a self-join plus correlated subquery.
DROP TABLE IF EXISTS stg_members;
CREATE TABLE stg_members (
  mth          DATE,
  quintile     TINYINT,
  param_window VARCHAR(16),
  permno       INT,
  prev_mth     DATE,
  PRIMARY KEY (mth, quintile, param_window, permno)
) ENGINE=InnoDB;

INSERT INTO stg_members (mth, quintile, param_window, permno, prev_mth)
SELECT
  hold_mth AS mth, quintile, param_window, permno,
  LAG(hold_mth) OVER (
    PARTITION BY permno, quintile, param_window ORDER BY hold_mth
  ) AS prev_mth
FROM (SELECT DISTINCT hold_mth, quintile, param_window, permno FROM holding_batches) dedup;

-- After using LAG to find each member's last appearance in this
-- (quintile, param_window), turnover = (count of members newly entering
-- this quintile this month) / (total members this month). "Newly
-- entering" means the member's prev_mth is not "the immediately
-- preceding calendar month" (i.e. it was not held in this quintile last
-- month).
DROP TABLE IF EXISTS stg_prev_month_by_window;
CREATE TABLE stg_prev_month_by_window (
  mth          DATE,
  param_window VARCHAR(16),
  prev_mth     DATE,
  PRIMARY KEY (mth, param_window)
) ENGINE=InnoDB;

INSERT INTO stg_prev_month_by_window (mth, param_window, prev_mth)
SELECT mth, param_window,
  LAG(mth) OVER (PARTITION BY param_window ORDER BY mth) AS prev_mth
FROM (SELECT DISTINCT mth, param_window FROM stg_members) distinct_months;

INSERT INTO turnover (mth, quintile, param_window, turnover)
SELECT
  m.mth, m.quintile, m.param_window,
  SUM(CASE WHEN m.prev_mth IS NULL OR m.prev_mth <> w.prev_mth THEN 1 ELSE 0 END) / COUNT(*) AS turnover
FROM stg_members m
JOIN stg_prev_month_by_window w
  ON w.mth = m.mth AND w.param_window = m.param_window
GROUP BY m.mth, m.quintile, m.param_window;

DROP TABLE stg_members;
DROP TABLE stg_prev_month_by_window;

-- Write turnover back into port_returns.turnover, so the R layer can
-- read every field it needs from a single table.
UPDATE port_returns pr
JOIN turnover t
  ON t.mth = pr.mth AND t.quintile = pr.quintile AND t.param_window = pr.param_window
SET pr.turnover = t.turnover;
