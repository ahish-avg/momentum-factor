-- ============================================================
-- 02_load_wrds.sql
-- Load WRDS/CRSP individual stock monthly returns + Fama-French factors
--
-- [CIZ field mapping] CRSP migrated its data structure on 2024-11-22
-- (legacy SIZ -> new CIZ format); table and variable names changed.
-- This script targets the actual CIZ Monthly Stock File fields:
--   permno       -> permno         (unchanged)
--   mthcaldt     -> mth            (monthly calendar date, i.e. end-of-month)
--   mthret       -> ret_adj        (Monthly Total Return, includes reinvested
--                                    dividends; delisting-month returns are
--                                    already folded in, so unlike the legacy
--                                    format there is no separate delisting
--                                    table to join or dlret to merge)
--   mthdelflg    -> delflg         (monthly delisting flag; retained for
--                                    disclosure/statistics, not used in
--                                    any calculation)
--
-- [Verified] The legacy shrcd IN (10,11) universe filter is expressed in
-- CIZ via the combination of securitytype / securitysubtype, cross-validated
-- against real WRDS query results:
--   Common stock (AAPL/MSFT/IBM): securitytype='EQTY', securitysubtype='COM', sharetype='NS'
--   ETF (SPY/VNQ):                securitytype='FUND', securitysubtype='ETF', sharetype='NS'
-- The distinction lives at the securitytype level (EQTY vs FUND);
-- securitysubtype provides a secondary confirmation. sharetype is identical
-- across both classes ('NS') and is therefore not used as a filter.
-- Filter condition: securitytype = 'EQTY' AND securitysubtype = 'COM'
--
-- Prerequisite: the raw WRDS export CSVs have been preprocessed (columns
-- reordered/trimmed) and placed under data/:
--   data/crsp_monthly.csv   Source: WRDS CRSP Annual Update -> Stock-Version 2
--                            (CIZ) -> Monthly Stock File, full-database query,
--                            trimmed from the full field export down to:
--                            permno, mth (YYYY-MM-DD), securitytype,
--                            securitysubtype, sharetype, ret, delflg
--   data/ff_factors.csv     Source: WRDS Fama-French Portfolios -> 5 Factors
--                            Plus Momentum - Monthly Frequency, columns
--                            reordered to:
--                            mth (YYYY-MM-DD), mkt_rf, smb, hml, rmw, cma, rf
--                            (the original umd momentum-factor column was
--                            dropped; not used in this study)
--
-- Requires a secure_file_priv-permitted path, or the --local-infile client flag.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Load raw CRSP data into a staging table, then filter into stock_monthly
-- ------------------------------------------------------------
DROP TABLE IF EXISTS stg_crsp_monthly;
CREATE TABLE stg_crsp_monthly (
  permno          INT,
  mth             DATE,
  securitytype    VARCHAR(16),
  securitysubtype VARCHAR(16),
  sharetype       VARCHAR(16),
  ret             DECIMAL(18,8),   -- mthret: monthly total return, already includes delisting-month return
  delflg          VARCHAR(8)       -- mthdelflg: monthly delisting flag, disclosure only
) ENGINE=InnoDB;

LOAD DATA LOCAL INFILE 'data/crsp_monthly.csv'
INTO TABLE stg_crsp_monthly
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(permno, mth, securitytype, securitysubtype, sharetype, ret, @delflg)
SET delflg = IF(@delflg = '' OR @delflg IS NULL, NULL, @delflg);

-- Optional pre-check: confirm the MAX(ret) dedup assumption below actually
-- holds (i.e. duplicate (permno, mth) rows always carry an identical ret).
-- Run this BEFORE the INSERT if you want to audit the raw data; it should
-- return zero rows. If it returns any rows, do not trust MAX(ret) blindly —
-- decide on an explicit tie-breaking rule instead.
--   SELECT permno, mth, MIN(ret) AS min_ret, MAX(ret) AS max_ret
--   FROM stg_crsp_monthly
--   WHERE securitytype = 'EQTY' AND securitysubtype = 'COM'
--   GROUP BY permno, mth
--   HAVING MIN(ret) <> MAX(ret);

-- Universe filter: common stock only (EQTY/COM), excluding ETFs (FUND/ETF),
-- REITs/ADRs/preferred shares, etc. Values cross-validated against real
-- data (AAPL/MSFT/IBM vs SPY/VNQ), see file header comment.
--
-- Deduplication note: CIZ documentation states that a security with more
-- than one distribution event in the same month can produce duplicate
-- (permno, mth) observations. Confirmed in practice (e.g. permno=10001 at
-- 1994-06-30 has two fully identical rows). Collapsed via GROUP BY; ret
-- uses MAX() under the assumption that duplicate rows carry identical
-- values (validated for the observed case above, but not exhaustively
-- verified across the full dataset — see the pre-check query above).
INSERT INTO stock_monthly (permno, mth, shrcd, ret, dlret, ret_adj)
SELECT
  permno,
  mth,
  NULL AS shrcd,      -- No direct CIZ equivalent; column retained for schema compatibility, unused
  MAX(ret) AS ret,
  NULL AS dlret,      -- CIZ delisting return is already folded into ret; not stored separately
  MAX(ret) AS ret_adj  -- mthret is already the total return including delisting-month return
FROM stg_crsp_monthly
WHERE securitytype = 'EQTY'          -- Verified: common stock (validated with AAPL/MSFT/IBM)
  AND securitysubtype = 'COM'        -- Verified: distinguishes from ETFs (FUND/ETF, validated with SPY/VNQ)
GROUP BY permno, mth;

DROP TABLE stg_crsp_monthly;

-- ------------------------------------------------------------
-- 2. Load Fama-French factors (downloaded from WRDS's Fama-French
--    Portfolios -> 5 Factors Plus Momentum - Monthly Frequency,
--    not the official Ken French website CSV).
--    Verified: the WRDS export values are already in decimal form
--    (e.g. -0.078000), unlike the official website CSV which uses
--    percent-times-100 units, so no /100 conversion is needed here.
--    Original column names dateff/mktrf/smb/hml/rmw/cma/rf/umd were
--    reordered during preprocessing to mth/mkt_rf/smb/hml/rmw/cma/rf
--    (the umd momentum factor is not loaded; no schema column exists
--    for it and it is not used in this study's regressions).
-- ------------------------------------------------------------
LOAD DATA LOCAL INFILE 'data/ff_factors.csv'
INTO TABLE ff_factors
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(mth, mkt_rf, smb, hml, rmw, cma, rf);

-- ------------------------------------------------------------
-- 3. Data validation assertions (row counts / dedup / missing ratios)
--    Output as SELECT results for manual inspection or scripted checks
-- ------------------------------------------------------------

-- 3a. Row count and date range
SELECT
  COUNT(*)              AS n_rows,
  COUNT(DISTINCT permno) AS n_permno,
  MIN(mth)              AS min_mth,
  MAX(mth)              AS max_mth
FROM stock_monthly;

-- 3b. (permno, mth) duplicate check (should be 0 rows, since it's the
--     primary key; this checks whether any dedup was dropped at the
--     staging step)
SELECT permno, mth, COUNT(*) AS n
FROM stock_monthly
GROUP BY permno, mth
HAVING COUNT(*) > 1;

-- 3c. Missing-value ratio (ret_adj)
SELECT
  SUM(ret_adj IS NULL) / COUNT(*) AS pct_ret_adj_null,
  COUNT(*)                        AS n_rows
FROM stock_monthly;

-- 3d. Delisting-month return disclosure (CIZ already folds delisting
--     returns into mthret, so we no longer compute a "before/after merge"
--     comparison as under the legacy format — that comparison is not
--     possible since CIZ does not expose an unmerged version).
--     Instead: report overall sample size and mean return as an honest
--     disclosure point for survivorship-bias handling.
SELECT
  COUNT(*) AS n_total_rows,
  0 AS n_delisting_rows_placeholder,  -- TODO: once the exact delflg values
                                       -- are confirmed, replace with
                                       -- SUM(delflg = '<actual delisting flag value>')
  AVG(ret_adj) AS mean_ret_all
FROM stock_monthly;

-- 3e. Universe filter effectiveness check (should contain only common
--     stock; run this against the staging table's type distribution
--     BEFORE it is dropped if you want to audit the raw composition;
--     kept here for documentation purposes only, since the staging
--     table has already been dropped by the time this script runs
--     end-to-end)
-- SELECT DISTINCT securitytype, securitysubtype, sharetype FROM stg_crsp_monthly;

-- 3f. Fama-French factor table row count and date range
SELECT COUNT(*) AS n_rows, MIN(mth) AS min_mth, MAX(mth) AS max_mth
FROM ff_factors;
