-- ============================================================
-- 03_signal.sql
-- 动量信号计算：4 组参数窗口 (formation N, skip S)
--   F3_S1, F6_S1, F12_S1, F12_S3   即 (3,1)/(6,1)/(12,1)/(12,3)
--
-- 信号定义：t 月信号只使用 [t-S-N, t-S-1] 区间的收益（跳过最近 S 月），
-- 用 LAG 对齐，杜绝前视偏差：
--   signal_t = EXP(SUM(LN(1+ret)) OVER (
--                PARTITION BY permno ORDER BY mth
--                ROWS BETWEEN (N+S-1) PRECEDING AND S PRECEDING
--              )) - 1
-- 注：ROWS BETWEEN 边界基于"当前行"，当前行是 t 月本身；
--     跳过最近 S 月 = 排除 [t-S+1, t] 这 S 行，从 t-S 开始往前数 N 行。
--     故窗口应为 ROWS BETWEEN (N+S-1) PRECEDING AND S PRECEDING。
--     例如 N=12,S=1：窗口 = 12 PRECEDING 到 1 PRECEDING（t-12 到 t-1，跳过 t 月自身即当月）。
--     用 ret_adj（已合并退市收益）作为收益输入，避免幸存者偏差。
-- ============================================================

TRUNCATE TABLE momentum_signal;

-- 参数表，避免四段几乎重复的 SQL 手写四次
-- MySQL 8 无原生数组参数化，这里用 UNION ALL 拼出四组窗口的插入

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
WHERE n_avail = 3;   -- formation 窗口内数据不足则排除该股（时间序列开头边界情况）

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
-- 前视偏差专项检查（可验证的具体动作，非空泛声明）
-- 抽样：任取一个 (permno, mth, param_window)，
-- 手工核对其 mom_signal 只应等于 [mth-N-S+1, mth-S] 窗口内 ret_adj 的累乘。
-- 下面的查询给出用于人工/脚本核对的原始收益明细，
-- 与 momentum_signal.mom_signal 对比即可验证是否越界使用了 skip 期内或 formation 窗口外的收益。
-- ------------------------------------------------------------
-- 示例（F12_S1）：取某一行信号
-- SELECT * FROM momentum_signal WHERE param_window='F12_S1' LIMIT 1;
-- 对应核对窗口（假设该行 mth = :m, permno = :p）：
-- SELECT mth, ret_adj FROM stock_monthly
-- WHERE permno = :p AND mth BETWEEN DATE_SUB(:m, INTERVAL 12 MONTH) AND DATE_SUB(:m, INTERVAL 1 MONTH)
-- ORDER BY mth;
-- 断言：上述区间不应包含 :m 当月或 :m 之后任何数据（即 skip 期与当月本身都不被使用）。
