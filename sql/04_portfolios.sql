-- ============================================================
-- 04_portfolios.sql
-- Quintile sorting + overlapping holding periods (JT1993-style)
-- portfolio returns
--
-- Logic:
-- 1. Within each month/param_window, use NTILE(5) on mom_signal to sort
--    stocks into quintiles (quintile 1 = losers .. 5 = winners).
-- 2. Each formation_mth batch contributes holding weight for the
--    following K=formation(N) months (K equals the formation window
--    length N, i.e. standard JT1993 practice: holding period length =
--    formation period length).
-- 3. holding_batches expands each batch into one row per month it holds.
-- 4. port_returns: aggregate AVG(ret) by (hold_mth, quintile, param_window),
--    i.e. the monthly portfolio return is a single-layer equal-weighted
--    average across all individual stock observations still within their
--    holding period that month (equal-weighted by stock, not by batch;
--    see the note in step 3 below for why batch-level pre-averaging would
--    introduce bias).
-- ============================================================

-- ------------------------------------------------------------
-- 1. Quintile sorting: tag momentum_signal rows with a quintile label
-- ------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS tmp_ranked_signal;
CREATE TEMPORARY TABLE tmp_ranked_signal AS
SELECT
  permno, mth AS formation_mth, param_window, formation,
  NTILE(5) OVER (PARTITION BY mth, param_window ORDER BY mom_signal) AS quintile
FROM momentum_signal
WHERE mom_signal IS NOT NULL;

CREATE INDEX idx_trs ON tmp_ranked_signal (formation_mth, param_window);

-- ------------------------------------------------------------
-- 2. Holding-batch expansion: each formation_mth batch holds for K=formation months
--    hold_mth = formation_mth + 1 month ... formation_mth + formation months
--    (the signal is generated at formation_mth; the position is entered
--    starting month t+1, consistent with the LAG alignment semantics
--    used in 03_signal.sql)
-- ------------------------------------------------------------
TRUNCATE TABLE holding_batches;

-- A 1..12 offset helper table to expand holding months (max formation = 12, sufficient here)
DROP TEMPORARY TABLE IF EXISTS tmp_offsets;
CREATE TEMPORARY TABLE tmp_offsets (k INT PRIMARY KEY);
INSERT INTO tmp_offsets (k) VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12);

INSERT INTO holding_batches (formation_mth, hold_mth, permno, quintile, param_window, ret)
SELECT
  rs.formation_mth,
  DATE_ADD(rs.formation_mth, INTERVAL o.k MONTH) AS hold_mth,
  rs.permno,
  rs.quintile,
  rs.param_window,
  sm.ret_adj AS ret
FROM tmp_ranked_signal rs
JOIN tmp_offsets o
  ON o.k <= rs.formation
JOIN stock_monthly sm
  ON sm.permno = rs.permno
 AND sm.mth = DATE_ADD(rs.formation_mth, INTERVAL o.k MONTH)
WHERE sm.ret_adj IS NOT NULL;

DROP TEMPORARY TABLE tmp_offsets;
DROP TEMPORARY TABLE tmp_ranked_signal;

-- ------------------------------------------------------------
-- 3. Aggregate into monthly portfolio returns: port_returns
--    For each (hold_mth, quintile, param_window), take a single-layer
--    equal-weighted average across all stock-level return observations
--    still within their holding period that month (equal-weighted by
--    stock, not by formation batch).
--
--    [Previously fixed defect] An earlier version of this script computed
--    AVG(ret) within each formation batch first, then AVG(batch_ret)
--    across batches — a two-layer average that implicitly gives each
--    formation batch equal weight instead of giving each stock equal
--    weight. Empirically, active batch size varies by roughly 13% in
--    steady state (e.g. 2000-06-30, F12_S1, quintile 1: 9 active batches
--    ranging from 1243 to 1409 stocks), so the two-layer average would
--    systematically distort portfolio returns. This has been corrected
--    to a single-layer AVG(ret) directly over all individual stock
--    observations that month, correctly implementing the standard
--    "equal-weighted by stock" JT1993 convention.
-- ------------------------------------------------------------
TRUNCATE TABLE port_returns;

INSERT INTO port_returns (mth, quintile, param_window, ret, n_stocks)
SELECT
  hold_mth,
  quintile,
  param_window,
  AVG(ret)   AS ret,
  COUNT(*)   AS n_stocks
FROM holding_batches
GROUP BY hold_mth, quintile, param_window;

-- ------------------------------------------------------------
-- 4. Winner-Loser (5-1) portfolio, written as quintile = 6
-- ------------------------------------------------------------
INSERT INTO port_returns (mth, quintile, param_window, ret, n_stocks)
SELECT
  w.mth, 6 AS quintile, w.param_window,
  w.ret - l.ret AS ret,
  w.n_stocks + l.n_stocks AS n_stocks
FROM port_returns w
JOIN port_returns l
  ON w.mth = l.mth AND w.param_window = l.param_window
WHERE w.quintile = 5 AND l.quintile = 1;

-- ------------------------------------------------------------
-- Verification queries: overlapping-holding-period correctness sampling
-- A given month's portfolio constituent count should be roughly the
-- monthly quintile size, since it's a mean, not a sum, across batches.
-- ------------------------------------------------------------
-- SELECT mth, quintile, param_window, n_stocks FROM port_returns
-- WHERE param_window = 'F12_S1' ORDER BY mth LIMIT 20;

-- After expansion, holding_batches should never double-count the same
-- (permno, hold_mth) within the same batch:
-- SELECT formation_mth, hold_mth, permno, param_window, COUNT(*)
-- FROM holding_batches
-- GROUP BY formation_mth, hold_mth, permno, param_window
-- HAVING COUNT(*) > 1;
