-- ============================================================
-- 04_portfolios.sql
-- 分位分组 + 重叠持仓（JT1993 overlapping holding periods）组合收益
--
-- 逻辑：
-- 1. 每月每个 param_window 下，用 NTILE(5) 按 mom_signal 分五档（quintile 1=loser..5=winner）
-- 2. 每个 formation_mth 的建仓批次，在接下来 K=formation(N) 个月内都贡献一份持仓权重
--    （K 取 formation 窗口月数 N，即 JT1993 标准做法：持有期 = formation 期长度）
-- 3. holding_batches 展开每个批次到其持有的每个 hold_mth
-- 4. port_returns：按 (hold_mth, quintile, param_window) 聚合 AVG(ret)
--    即当月组合收益 = 当月仍在持仓期内的所有批次的等权平均（批次间等权，批次内股票等权）
-- ============================================================

-- ------------------------------------------------------------
-- 1. 分位分组：在 momentum_signal 基础上打 quintile 标签
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
-- 2. 建仓批次展开表：formation_mth 批次持有 K=formation 个月
--    hold_mth = formation_mth + 1 月 ... formation_mth + formation 月
--    （信号在 formation_mth 生成，t+1 月开始建仓持有，与 03_signal 的 LAG 对齐语义一致）
-- ------------------------------------------------------------
TRUNCATE TABLE holding_batches;

-- 用一个 1..12 的偏移辅助表展开持有月份（MAX formation = 12，够用）
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
-- 3. 聚合成组合月收益：port_returns
--    每个 (hold_mth, quintile, param_window) 下，先按批次(formation_mth)算批次内等权均值，
--    再对所有仍在持仓期内的批次取等权均值（JT1993 标准两层等权）
-- ------------------------------------------------------------
TRUNCATE TABLE port_returns;

INSERT INTO port_returns (mth, quintile, param_window, ret, n_stocks)
SELECT
  hold_mth,
  quintile,
  param_window,
  AVG(batch_ret) AS ret,
  SUM(batch_n)   AS n_stocks
FROM (
  SELECT
    hold_mth, quintile, param_window, formation_mth,
    AVG(ret)   AS batch_ret,
    COUNT(*)   AS batch_n
  FROM holding_batches
  GROUP BY hold_mth, quintile, param_window, formation_mth
) batch_level
GROUP BY hold_mth, quintile, param_window;

-- ------------------------------------------------------------
-- 4. Winner-Loser (5-1) 组合，写入 quintile = 6
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
-- 验证查询：重叠持仓正确性抽样检查
-- 某月组合成分股数量应 ≈ 该月 5 档股票数（因为是均值合成非累加）
-- ------------------------------------------------------------
-- SELECT mth, quintile, param_window, n_stocks FROM port_returns
-- WHERE param_window = 'F12_S1' ORDER BY mth LIMIT 20;

-- holding_batches 展开后同一批次不应对同一 (permno, hold_mth) 重复计入两次
-- SELECT formation_mth, hold_mth, permno, param_window, COUNT(*)
-- FROM holding_batches
-- GROUP BY formation_mth, hold_mth, permno, param_window
-- HAVING COUNT(*) > 1;
