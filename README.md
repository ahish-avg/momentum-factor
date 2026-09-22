# Momentum Factor Replication & Transaction Cost Sensitivity

A reproducible empirical study replicating the Jegadeesh & Titman (1993) price momentum anomaly on U.S. common equities, extended with a parameter-robustness sweep and a transaction-cost sensitivity analysis. The full pipeline — data ingestion, signal construction, portfolio formation, and statistical inference — is implemented in MySQL 8 and R, orchestrated by `targets`, with automated data-integrity and look-ahead-bias tests via `testthat`.

[中文版 README](README.zh-CN.md)

## 1. Research Question

Does the 12-month/1-month-skip ("12-1") momentum strategy of Jegadeesh & Titman (1993) continue to generate abnormal returns in a modern, full-universe sample of U.S. common stocks? How sensitive is the result to the choice of formation and skip window, and how much of any abnormal return survives realistic transaction costs?

## 2. Data

| Series | Source | Coverage | Notes |
|---|---|---|---|
| Individual stock monthly returns | WRDS/CRSP, Stock-Version 2 (CIZ format, migrated 2024-11-22) → Monthly Stock File | 1990-01 to 2025-12 | Full-database query; universe restricted to common stock via `securitytype='EQTY' AND securitysubtype='COM'` (see §3.1) |
| Fama-French factors | WRDS → Fama-French Portfolios → 5 Factors Plus Momentum (Monthly) | 1990-01 to 2025-12 (432 months) | Values are stored as decimals in the WRDS export, not the percent-times-100 units used on the public Ken French data library |

Final loaded sample: **2,667,625** stock-month observations across **23,700** distinct securities (`permno`).

WRDS data is subject to redistribution restrictions and is not committed to this repository (`data/` is `.gitignore`d).

### 2.1 CIZ Migration and Universe Filter

CRSP's November 2024 migration from the legacy "SIZ" format to the new "CIZ" format removed the `shrcd` (share code) variable historically used to restrict the sample to common stock (`shrcd IN (10, 11)`). In its place, CIZ exposes `securitytype` and `securitysubtype`. This mapping was **not documented by WRDS in an easily discoverable form** and was established empirically for this project by querying known securities and cross-tabulating the returned fields:

| Ticker | Type | `securitytype` | `securitysubtype` | `sharetype` |
|---|---|---|---|---|
| AAPL, MSFT, IBM | Common stock | `EQTY` | `COM` | `NS` |
| SPY, VNQ | ETF | `FUND` | `ETF` | `NS` |

The distinction is carried entirely by `securitytype` (`EQTY` vs. `FUND`), with `securitysubtype` providing secondary confirmation; `sharetype` does not vary between the two classes and is not used as a filter. The filter applied at load time is `securitytype = 'EQTY' AND securitysubtype = 'COM'`.

### 2.2 Duplicate Records

CIZ documentation notes that a security experiencing more than one distribution event within a month can produce duplicate `(permno, mth)` rows. This was confirmed empirically (e.g. `permno=10001` at `1994-06-30` appears twice, with identical values). Duplicates are collapsed via `GROUP BY permno, mth` with `MAX(ret)`, under the assumption that duplicate rows carry an identical return — validated for the observed case, though not exhaustively verified across the full 2.67M-row dataset (see the validation query documented in `sql/02_load_wrds.sql`).

## 3. Methodology

### 3.1 Signal Construction

For each parameter pair (formation window *N*, skip window *S*), the momentum signal at month *t* is the compounded return over the preceding *N* months, excluding the most recent *S* months:

```sql
signal_t = EXP( SUM( LN(1 + ret) ) OVER (
             PARTITION BY permno ORDER BY mth
             ROWS BETWEEN (N+S-1) PRECEDING AND S PRECEDING
           ) ) - 1
```

This construction guarantees, by the semantics of MySQL's window-frame boundaries, that the current row (month *t*) is never included in the signal for any *S* ≥ 1, eliminating look-ahead bias by design. Four (formation, skip) configurations are computed: (3,1), (6,1), (12,1), (12,3), labeled `F3_S1`, `F6_S1`, `F12_S1`, `F12_S3`.

The correctness of this construction is independently verified — not merely asserted — by `R/tests/test-lookahead-bias.R`, which resamples signal rows from the database, independently recomputes each signal from the raw return series in R, and checks numerical equality to a tolerance of 1e-6.

### 3.2 Portfolio Formation and Overlapping Holding Periods

Following Jegadeesh & Titman (1993), each month's ranked stocks are sorted into quintiles (`NTILE(5)`, quintile 1 = losers, quintile 5 = winners) and held for *K* = *N* months (the holding period equals the formation window length), with a new portfolio formed every month. This produces overlapping holding-period portfolios: at any given calendar month, the realized return is a blend of positions initiated in each of the preceding *N* formation months.

This overlapping structure is implemented via an explicit intermediate table, `holding_batches(formation_mth, hold_mth, permno, quintile, param_window, ret)`, which expands each formation batch into one row per month it contributes to the held portfolio. The monthly portfolio return is then a **single-layer, equal-weighted average across all individual stock-month observations** active in a given `(hold_mth, quintile, param_window)` — i.e., every stock receives equal weight, regardless of which formation batch it originated from.

> **Note on an earlier implementation defect.** An initial version of this aggregation computed the mean return within each formation batch first, then averaged those batch-level means across batches — a two-layer average that implicitly gives every *formation batch* equal weight rather than every *stock* equal weight. Because active batch sizes vary by roughly 13% in steady state (e.g., 9 active batches ranging from 1,243 to 1,409 constituent stocks were observed for `F12_S1`, quintile 1, at `2000-06-30`), this introduced a measurable aggregation bias. It was identified during code review, confirmed empirically, and corrected to the single-layer average described above; the results reported in §5 reflect the corrected computation. The magnitude of the bias in the originally-reported numbers was small (differences at the fourth decimal place) but the correction is retained as the methodologically correct specification.

The winner-minus-loser spread portfolio (quintile 5 − quintile 1) is stored as `quintile = 6` in `port_returns`.

### 3.3 Delisting and Survivorship Bias

Under the legacy CRSP format, delisting returns (`dlret`) required manual merging with regular returns to avoid survivorship bias. Under CIZ, the `mthret` field already incorporates the delisting-month return, so no separate merge step is required. This is a structural improvement over the legacy pipeline design but does not eliminate broader sample-selection considerations inherent to the CRSP universe (see §6).

### 3.4 Statistical Inference

Winner-loser portfolio returns are regressed on the Fama-French three factors (Mkt-RF, SMB, HML). Standard errors are computed using the Newey-West (1987) heteroskedasticity- and autocorrelation-consistent estimator (`sandwich::NeweyWest`), with lag length chosen via the common rule of thumb ⌊4·(T/100)^(2/9)⌋, rather than relying on plain OLS standard errors — a point of deliberate academic rigor given the strongly overlapping, autocorrelated nature of the return series induced by the holding-period construction.

### 3.5 Turnover and Transaction Cost Sensitivity

Turnover is computed from the realized holding_batches membership (not the raw formation-time ranking), as the fraction of a quintile's membership in a given month that was not held in the same quintile the previous month. Net alpha under a round-trip transaction cost *c* is modeled as:

```
net_alpha(c) = gross_alpha - avg_turnover × c × 2
```

and evaluated over *c* ∈ [0, 50] bps in 1bp increments, with the breakeven cost (where net alpha first reaches zero) identified by linear interpolation.

### 3.6 Design Principle: Portfolio Construction Lives in SQL

All quintile sorting, holding-period expansion, return aggregation, and turnover calculation are performed in SQL (`sql/`). The R layer (`R/fns/`) is strictly read-only with respect to portfolio-level quantities — it performs regression, risk-metric computation, and plotting, but never recomputes or re-derives a portfolio return.

## 4. Repository Structure

```
momentum-factor/
├── sql/
│   ├── 01_schema.sql        Table definitions
│   ├── 02_load_wrds.sql     CRSP + Fama-French ingestion, universe filter, validation queries
│   ├── 03_signal.sql        Momentum signal computation (4 parameter windows)
│   ├── 04_portfolios.sql    Quintile sorting + overlapping-holding-period aggregation
│   └── 05_turnover.sql      Turnover computation
├── R/
│   ├── _targets.R           Pipeline definition
│   ├── fns/                 Regression, risk metrics, cost sensitivity, plotting
│   └── tests/                testthat suite: data validation, look-ahead-bias check, boundary cases
├── data/                    WRDS exports (gitignored; must be supplied locally)
├── output/                  Generated figures
├── .github/workflows/       CI: schema smoke test + testthat suite
└── README.md / README.zh-CN.md
```

## 5. Results

Sample: 1990-01 to 2025-12, 2,667,625 stock-month observations, 23,700 distinct securities. Winner-loser (quintile 5 − 1) portfolio regressed on the Fama-French three factors:

| Window (formation-skip) | Monthly α | Newey-West t | Newey-West p | Ann. Sharpe | Max Drawdown | Cost Breakeven |
|---|---|---|---|---|---|---|
| F3_S1 (3-1) | 0.21% | 0.93 | 0.352 | −0.03 | 55% | 0 bps (loss-making even cost-free) |
| **F6_S1 (6-1)** | **0.62%** | **2.60** | **0.010** | **0.22** | 58% | Net alpha remains positive across the full 0–50 bps range tested |
| F12_S1 (12-1, standard JT1993 specification) | −0.19% | −0.72 | 0.469 | −0.27 | 87% | 0 bps |
| F12_S3 (12-3) | −0.32% | −1.23 | 0.221 | −0.33 | 91% | 0 bps |

**Headline finding.** The classical 12-1 formation-skip specification of Jegadeesh & Titman (1993) does *not* replicate in this 1990–2025 full-universe U.S. sample: the winner-loser alpha is negative, statistically insignificant, and accompanied by a maximum drawdown exceeding 85%. The only parameter configuration that is both statistically significant (at the 1% level under Newey-West standard errors) and economically robust to transaction costs is the shorter **6-month formation, 1-month skip** window.

A supplementary diagnostic (holding-period return decomposed by month within the holding period) shows that the momentum effect is concentrated in the first one to two months after formation — winners outperform losers in these early months — but decays and frequently reverses over the remainder of a 12-month holding period. Longer holding windows therefore average in a larger share of the decayed/reversed period, which fully offsets the early-period alpha for the 12-month specifications. This is reported as a substantive finding, not a data or implementation artifact; it is consistent with the well-documented literature on momentum crash and decay dynamics, though a formal decomposition by sub-period or market regime is left to future work (§6).

## 6. Limitations and Future Work

- **No liquidity or market-capitalization screen.** Micro-cap stocks, which can exhibit exaggerated momentum-like patterns driven by illiquidity and wide bid-ask spreads, are not excluded in this iteration.
- **No pre/post-2008 sub-period analysis.** The well-documented 2008-era "momentum crash" is not separately analyzed; given the decay pattern identified in §5, a sub-period breakdown could clarify whether the observed failure of the 12-month specification is concentrated in specific historical regimes.
- **Survivorship bias.** CIZ's `mthret` folds in delisting-month returns, mitigating the primary source of survivorship bias relative to the legacy pipeline design, but broader CRSP sample-composition effects are not further corrected for.
- **Holding-period decay decomposition.** The observed early-period momentum effect and its subsequent decay are documented but not further decomposed by sector, market regime, or other conditioning variables.
- **Tableau presentation.** Optional; if pursued, note that WRDS-sourced data cannot be published via Tableau Public — a public-facing version would require an alternative data source or static screenshots.

## 7. Reproducing the Results

1. Provision a MySQL 8 instance and set the environment variables `MOMENTUM_DB_HOST`, `MOMENTUM_DB_PORT`, `MOMENTUM_DB_NAME`, `MOMENTUM_DB_USER`, `MOMENTUM_DB_PASSWORD`.
2. Export data from WRDS (CRSP CIZ Monthly Stock File, full-database query; Fama-French 5 Factors Plus Momentum, Monthly), and preprocess into the column layout documented at the top of `sql/02_load_wrds.sql`, saving as `data/crsp_monthly.csv` and `data/ff_factors.csv`.
3. Run the SQL pipeline in order (requires `--local-infile=1` on the client and `SET GLOBAL local_infile=1` on the server):
   ```bash
   mysql < sql/01_schema.sql
   mysql --local-infile=1 < sql/02_load_wrds.sql
   mysql < sql/03_signal.sql
   mysql < sql/04_portfolios.sql
   mysql < sql/05_turnover.sql
   ```
4. Run the R pipeline:
   ```r
   renv::restore()
   targets::tar_make()
   testthat::test_dir("R/tests")
   ```
   All 15 `testthat` cases pass against the live database, including an independently-recomputed look-ahead-bias check and boundary-condition tests (insufficient-history stocks correctly excluded; no double-counting in `holding_batches`).

## 8. Reproducibility Checklist

- [x] One-command reproduction: `targets::tar_make()`, verified in CI
- [x] Look-ahead bias check with an independent recomputation, not a design-only assertion (`R/tests/test-lookahead-bias.R`)
- [x] Delisting-return handling made explicit and documented (§3.3)
- [x] Newey-West standard errors rather than plain OLS (§3.4)
- [x] Insignificant or negative results reported as-is, with no filtering (§5)
- [x] Data provenance and limitations documented in a dedicated section (§2, §6)
