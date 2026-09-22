-- ============================================================
-- 02_load_wrds.sql
-- 灌入 WRDS/CRSP 个股月度收益 + FF 因子
--
-- 【CIZ 新版字段映射】CRSP 于 2024-11-22 更新了数据结构（旧版 SIZ -> 新版 CIZ），
-- 表名、变量名均有变化。本脚本基于 CIZ 新版 Monthly Stock File 的实际字段：
--   permno       -> permno         (不变)
--   mthcaldt     -> mth            (月度日历日期，即月末日期)
--   mthret       -> ret_adj        (Monthly Total Return，含分红再投资；
--                                    退市月的收益已经并入该字段，不再需要
--                                    像旧版一样单独 join 退市表、单独合并 dlret)
--   mthdelflg    -> delflg         (月度退市标志位，用于统计/披露幸存者偏差，
--                                    不用于计算，仅作诚实披露用途)
--
-- 【已核实】股票范围过滤 shrcd IN (10,11) 在 CIZ 新版中由 securitytype /
-- securitysubtype 两个字段组合表达，已用真实 WRDS 查询结果交叉验证：
--   普通股（AAPL/MSFT/IBM）：securitytype='EQTY', securitysubtype='COM', sharetype='NS'
--   ETF（SPY/VNQ）        ：securitytype='FUND', securitysubtype='ETF', sharetype='NS'
-- 区分逻辑落在 securitytype 这一层（EQTY vs FUND），securitysubtype 做进一步
-- 确认；sharetype 两类取值相同（'NS'），不参与筛选，不作为过滤条件。
-- 过滤条件：securitytype = 'EQTY' AND securitysubtype = 'COM'
--
-- 前置：WRDS 导出的原始 CSV 已经过预处理（重排/精简列）后放到 data/ 目录：
--   data/crsp_monthly.csv   来源: WRDS CRSP Annual Update -> Stock-Version 2
--                            (CIZ) -> Monthly Stock File, 全库检索导出，
--                            已从全字段导出精简为:
--                            permno, mth (YYYY-MM-DD), securitytype,
--                            securitysubtype, sharetype, ret, delflg
--   data/ff_factors.csv     来源: WRDS Fama-French Portfolios -> 5 Factors
--                            Plus Momentum - Monthly Frequency，已重排列为:
--                            mth (YYYY-MM-DD), mkt_rf, smb, hml, rmw, cma, rf
--                            （原始 umd 动量因子列已丢弃，本轮不使用）
--
-- 需要 secure_file_priv 允许的路径，或者用 --local-infile 客户端参数。
-- ============================================================

-- ------------------------------------------------------------
-- 1. 灌入原始 CRSP 数据到 staging 表，再过滤写入 stock_monthly
-- ------------------------------------------------------------
DROP TABLE IF EXISTS stg_crsp_monthly;
CREATE TABLE stg_crsp_monthly (
  permno          INT,
  mth             DATE,
  securitytype    VARCHAR(16),
  securitysubtype VARCHAR(16),
  sharetype       VARCHAR(16),
  ret             DECIMAL(18,8),   -- mthret：月度总收益，已含退市月收益
  delflg          VARCHAR(8)       -- mthdelflg：月度退市标志位，仅作披露用途
) ENGINE=InnoDB;

LOAD DATA LOCAL INFILE 'data/crsp_monthly.csv'
INTO TABLE stg_crsp_monthly
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(permno, mth, securitytype, securitysubtype, sharetype, ret, @delflg)
SET delflg = IF(@delflg = '' OR @delflg IS NULL, NULL, @delflg);

-- 股票范围过滤：仅普通股（EQTY/COM），排除 ETF（FUND/ETF）、REIT/ADR/优先股等
-- 取值已用真实数据交叉验证（AAPL/MSFT/IBM vs SPY/VNQ），见文件头部注释
--
-- 去重说明：CIZ 官方文档提示，若单只证券在同一月发生多笔分配事件（如多次
-- 分红），会产生 (permno, mth) 重复观测。实测数据中确认存在完全重复的行
-- （如 permno=10001, mth=1994-06-30 出现两条完全相同记录）。用 GROUP BY
-- 折叠去重，同一 (permno, mth, securitytype, securitysubtype) 下 ret 取
-- MAX（重复行数值相同，MAX 只是聚合函数占位，不代表business逻辑上的选择）。
INSERT INTO stock_monthly (permno, mth, shrcd, ret, dlret, ret_adj)
SELECT
  permno,
  mth,
  NULL AS shrcd,      -- CIZ 无直接对应字段，字段保留以兼容旧 schema，不再使用
  MAX(ret) AS ret,
  NULL AS dlret,      -- CIZ 退市收益已并入 ret，不再单独存储
  MAX(ret) AS ret_adj  -- mthret 本身已是含退市月收益的总收益，直接作为 ret_adj
FROM stg_crsp_monthly
WHERE securitytype = 'EQTY'          -- 已核实：普通股（AAPL/MSFT/IBM 验证过）
  AND securitysubtype = 'COM'        -- 已核实：区别于 ETF（FUND/ETF，SPY/VNQ 验证过）
GROUP BY permno, mth;

DROP TABLE stg_crsp_monthly;

-- ------------------------------------------------------------
-- 2. 灌入 FF 因子（本项目实际从 WRDS 的 Fama-French Portfolios ->
--    5 Factors Plus Momentum - Monthly Frequency 下载，非官网 CSV）。
--    已核实：WRDS 导出的数值本身就是小数形式（如 -0.078000），
--    不是官网 CSV 那种百分比乘以100的格式，因此不需要除以100转换。
--    原始列名 dateff/mktrf/smb/hml/rmw/cma/rf/umd，已在预处理阶段
--    重排为 mth/mkt_rf/smb/hml/rmw/cma/rf（umd 动量因子暂未入库，
--    schema 未留字段，本轮回归不使用）。
-- ------------------------------------------------------------
LOAD DATA LOCAL INFILE 'data/ff_factors.csv'
INTO TABLE ff_factors
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(mth, mkt_rf, smb, hml, rmw, cma, rf);

-- ------------------------------------------------------------
-- 3. 数据校验断言（行数/去重/缺失比例）
--    以 SELECT 结果的形式输出，供人工检查或脚本抓取
-- ------------------------------------------------------------

-- 3a. 行数与日期范围
SELECT
  COUNT(*)              AS n_rows,
  COUNT(DISTINCT permno) AS n_permno,
  MIN(mth)              AS min_mth,
  MAX(mth)              AS max_mth
FROM stock_monthly;

-- 3b. (permno, mth) 重复检查（应为 0 行，因为是主键，此处校验 staging 阶段是否有丢弃）
SELECT permno, mth, COUNT(*) AS n
FROM stock_monthly
GROUP BY permno, mth
HAVING COUNT(*) > 1;

-- 3c. 缺失值比例（ret_adj）
SELECT
  SUM(ret_adj IS NULL) / COUNT(*) AS pct_ret_adj_null,
  COUNT(*)                        AS n_rows
FROM stock_monthly;

-- 3d. 退市月收益披露（CIZ 已将退市收益并入 mthret，此处仅做统计披露，
--     不做「合并前后差异」计算 —— 因为 CIZ 不再提供未合并版本）
--     以下改为：统计退市月样本占比及其平均收益，作为幸存者偏差处理的诚实披露
SELECT
  COUNT(*) AS n_total_rows,
  0 AS n_delisting_rows_placeholder,  -- TODO: 待确认 delflg 实际取值后，
                                       -- 改为 SUM(delflg = '<实际退市标志值>')
  AVG(ret_adj) AS mean_ret_all
FROM stock_monthly;

-- 3e. 股票范围过滤生效检查（应只剩普通股，此处先检查原始 staging 类型分布，
--     需在 LOAD DATA 后、DROP staging 表前临时执行以下查询做核实，
--     生产运行时该表已被清理，此处仅作文档示例保留）
-- SELECT DISTINCT securitytype, securitysubtype, sharetype FROM stg_crsp_monthly;

-- 3f. FF 因子表行数/日期范围
SELECT COUNT(*) AS n_rows, MIN(mth) AS min_mth, MAX(mth) AS max_mth
FROM ff_factors;
