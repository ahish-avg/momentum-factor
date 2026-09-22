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
-- 个股月度收益（CRSP 风格）
-- shrcd: share code, 用于筛选普通股 (10,11)，排除 REIT/ADR/优先股
-- ------------------------------------------------------------
CREATE TABLE stock_monthly (
  permno  INT            NOT NULL,
  mth     DATE            NOT NULL,   -- 月末日期
  shrcd   SMALLINT        NULL,       -- 股票类型代码，10/11 为普通股
  ret     DECIMAL(18,8)   NULL,       -- 含股息总收益
  dlret   DECIMAL(18,8)   NULL,       -- 退市收益（处理幸存者偏差用）
  ret_adj DECIMAL(18,8)   NULL,       -- COALESCE(ret,0)+COALESCE(dlret,0)，加载时算好，R 只读
  PRIMARY KEY (permno, mth),
  KEY idx_stock_monthly_mth (mth)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- FF 因子（官网 CSV 灌入）
-- ------------------------------------------------------------
CREATE TABLE ff_factors (
  mth    DATE PRIMARY KEY,
  mkt_rf DECIMAL(18,8), smb DECIMAL(18,8), hml DECIMAL(18,8),
  rmw    DECIMAL(18,8), cma DECIMAL(18,8), rf  DECIMAL(18,8)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 动量信号（参数化：多组 formation/skip 窗口）
-- param_window 命名约定：'F{formation}_S{skip}'，如 'F12_S1'
-- ------------------------------------------------------------
CREATE TABLE momentum_signal (
  permno       INT           NOT NULL,
  mth          DATE          NOT NULL,   -- 信号生成月（formation 期末）
  param_window VARCHAR(16)   NOT NULL,
  formation    TINYINT       NOT NULL,   -- N：formation 窗口月数
  skip         TINYINT       NOT NULL,   -- S：跳过月数
  mom_signal   DECIMAL(18,8) NULL,       -- 过去 N 月累计收益（跳过最近 S 月），
                                          -- 列名避开 MySQL 保留字 signal
  PRIMARY KEY (permno, mth, param_window),
  KEY idx_signal_mth_param (mth, param_window)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 建仓批次展开表（重叠持仓核心中间表）
-- 每个 formation_mth 的建仓批次，展开到其持有的每个 hold_mth
-- ------------------------------------------------------------
CREATE TABLE holding_batches (
  formation_mth DATE        NOT NULL,   -- 建仓（信号生成）月
  hold_mth      DATE        NOT NULL,   -- 该批次贡献持仓权重的月份
  permno        INT         NOT NULL,
  quintile      TINYINT     NOT NULL,   -- 1-5，该批次内该股所属分位
  param_window  VARCHAR(16) NOT NULL,
  ret           DECIMAL(18,8) NULL,     -- hold_mth 当月该股票的 ret_adj，冗余存一份便于聚合
  PRIMARY KEY (formation_mth, hold_mth, permno, param_window),
  KEY idx_hb_hold (hold_mth, quintile, param_window)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 组合月收益（SQL 算出来写回，R 只读）
-- ------------------------------------------------------------
CREATE TABLE port_returns (
  mth          DATE          NOT NULL,
  quintile     TINYINT       NOT NULL,   -- 1-5；6 保留给 5-1 winner-loser 组合
  param_window VARCHAR(16)   NOT NULL,
  ret          DECIMAL(18,8) NULL,
  n_stocks     INT           NULL,
  turnover     DECIMAL(10,4) NULL,
  PRIMARY KEY (mth, quintile, param_window)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 换手率（按 param_window 分组，供 P4 成本敏感性用）
-- ------------------------------------------------------------
CREATE TABLE turnover (
  mth          DATE          NOT NULL,
  quintile     TINYINT       NOT NULL,
  param_window VARCHAR(16)   NOT NULL,
  turnover     DECIMAL(10,4) NULL,      -- 相邻两期分位成员变化比例
  PRIMARY KEY (mth, quintile, param_window)
) ENGINE=InnoDB;
