-- ============================================================
-- 03_signal.sql
-- Momentum signal computation: 4 parameter windows (formation N, skip S)
--   F3_S1, F6_S1, F12_S1, F12_S3  i.e. (3,1)/(6,1)/(12,1)/(12,3)
--
-- Signal definition: the signal at month t only uses returns from
-- [t-S-N, t-S-1] (skipping the most recent S months). Window alignment
-- eliminates look-ahead bias:
--   signal_t = EXP(SUM(LN(1+ret)) OVER (
--                PARTITION BY permno ORDER BY mth
--                ROWS BETWEEN (N+S-1) PRECEDING AND S PRECEDING
--              )) - 1
-- Note: ROWS BETWEEN bounds are relative to the "current row", which is
-- month t itself; skipping the most recent S months means excluding the
-- S rows [t-S+1, t], then counting N rows backward starting from t-S.
-- Hence the window should be ROWS BETWEEN (N+S-1) PRECEDING AND S PRECEDING.
-- Example: N=12, S=1 -> window = 12 PRECEDING to 1 PRECEDING (t-12 through
-- t-1), which excludes month t itself.
-- Uses ret_adj (delisting return already merged in) as the return input
-- to mitigate survivorship bias.
-- ============================================================

TRUNCATE TABLE momentum_signal;

-- Parameter sweep: MySQL 8 has no native array parameterization, so the
-- four window configurations are written out via UNION-style repeated
-- INSERT statements rather than a single parameterized query.

INSERT INTO momentum_signal (permno, mth, param_window, formation, skip, mom_signal)
SELECT permno, mth, 'F3_S1', 3, 1, mom_signal FROM (
  SELECT
    permno, mth,
    EXP(SUM(LN(1 + ret_adj)) OVER (
      PARTITION BY permno ORDER BY mth
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    )) - 1 AS mom_signal,
    COUNT(*) OVER (
      PARTITION BY permno ORDER BY mth
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS n_avail
  FROM stock_monthly
  WHERE ret_adj IS NOT NULL AND ret_adj > -1
) t
WHERE n_avail = 3;   -- Exclude stocks with insufficient history within the formation window (start-of-series boundary case)

INSERT INTO momentum_signal (permno, mth, param_window, formation, skip, mom_signal)
SELECT permno, mth, 'F6_S1', 6, 1, mom_signal FROM (
  SELECT
    permno, mth,
    EXP(SUM(LN(1 + ret_adj)) OVER (
      PARTITION BY permno ORDER BY mth
      ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
    )) - 1 AS mom_signal,
    COUNT(*) OVER (
      PARTITION BY permno ORDER BY mth
      ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
    ) AS n_avail
  FROM stock_monthly
  WHERE ret_adj IS NOT NULL AND ret_adj > -1
) t
WHERE n_avail = 6;

INSERT INTO momentum_signal (permno, mth, param_window, formation, skip, mom_signal)
SELECT permno, mth, 'F12_S1', 12, 1, mom_signal FROM (
  SELECT
    permno, mth,
    EXP(SUM(LN(1 + ret_adj)) OVER (
      PARTITION BY permno ORDER BY mth
      ROWS BETWEEN 12 PRECEDING AND 1 PRECEDING
    )) - 1 AS mom_signal,
    COUNT(*) OVER (
      PARTITION BY permno ORDER BY mth
      ROWS BETWEEN 12 PRECEDING AND 1 PRECEDING
    ) AS n_avail
  FROM stock_monthly
  WHERE ret_adj IS NOT NULL AND ret_adj > -1
) t
WHERE n_avail = 12;

INSERT INTO momentum_signal (permno, mth, param_window, formation, skip, mom_signal)
SELECT permno, mth, 'F12_S3', 12, 3, mom_signal FROM (
  SELECT
    permno, mth,
    EXP(SUM(LN(1 + ret_adj)) OVER (
      PARTITION BY permno ORDER BY mth
      ROWS BETWEEN 14 PRECEDING AND 3 PRECEDING
    )) - 1 AS mom_signal,
    COUNT(*) OVER (
      PARTITION BY permno ORDER BY mth
      ROWS BETWEEN 14 PRECEDING AND 3 PRECEDING
    ) AS n_avail
  FROM stock_monthly
  WHERE ret_adj IS NOT NULL AND ret_adj > -1
) t
WHERE n_avail = 12;

-- ------------------------------------------------------------
-- Look-ahead bias check (a concrete, executable verification step,
-- not just a design-principle statement)
-- Sample: pick any (permno, mth, param_window) row and manually confirm
-- that its mom_signal equals the compounded return over ret_adj in the
-- window [mth-N-S+1, mth-S].
-- The query below provides the raw return detail needed for manual or
-- scripted verification; comparing it against momentum_signal.mom_signal
-- confirms whether any return from the skip period or outside the
-- formation window has leaked in. (See also R/tests/test-lookahead-bias.R
-- for an automated, independently-recomputed version of this check.)
-- ------------------------------------------------------------
-- Example (F12_S1): pick one signal row
-- SELECT * FROM momentum_signal WHERE param_window='F12_S1' LIMIT 1;
-- Corresponding verification window (assuming that row has mth = :m, permno = :p):
-- SELECT mth, ret_adj FROM stock_monthly
-- WHERE permno = :p AND mth BETWEEN DATE_SUB(:m, INTERVAL 12 MONTH) AND DATE_SUB(:m, INTERVAL 1 MONTH)
-- ORDER BY mth;
-- Assertion: the interval above must not contain month :m itself or any
-- later data (i.e. neither the skip period nor the current month is used).
