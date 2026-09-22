-- ============================================================
-- 05_turnover.sql
-- 换手率：相邻两期同一 (quintile, param_window) 分位成员集合差异计数
-- 供 P4 交易成本敏感性分析使用
--
-- 定义：turnover_t = |members_t \ members_{t-1}| / |members_t|
--   即当月分位成员中，上月不在该分位（新进场）的比例
-- 用 holding_batches 展开后的当月成员集合（而非 formation 原始信号），
-- 因为持仓组合的实际成分是重叠批次的并集，换手率应反映实际持仓变化。
-- ============================================================

TRUNCATE TABLE turnover;

-- 用普通表（非 TEMPORARY）承载成员集合，避开 MySQL 对 TEMPORARY TABLE
-- 在同一查询内被自 JOIN + 相关子查询重复引用时报 "Can't reopen table" 的限制。
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

-- 用 LAG 得到每个成员上一次出现在该 (quintile, param_window) 的月份后，
-- 换手率 = 当月新进场成员数（上月不在同一分位）/ 当月成员总数。
-- 新进场判定：该成员的 prev_mth 不是"上一个自然月"（即上月未持仓该分位）。
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

-- 把换手率同步写回 port_returns.turnover，方便 R 层一次读表拿全部字段
UPDATE port_returns pr
JOIN turnover t
  ON t.mth = pr.mth AND t.quintile = pr.quintile AND t.param_window = pr.param_window
SET pr.turnover = t.turnover;
