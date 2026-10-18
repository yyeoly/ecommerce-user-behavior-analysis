-- ============================================================
-- 第 1 层：原始落地层（Staging）
-- 目标：先把 CSV 原样装入 MySQL，不在此层做业务判断。
-- 所有字段先使用文本类型，避免 MySQL 在导入时静默截断或转换。
-- ============================================================

USE retail_ops;

DROP TABLE IF EXISTS stg_online_retail;

CREATE TABLE stg_online_retail (
  source_row_id   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '导入顺序号，用于追溯原始行',
  invoice_no_raw  VARCHAR(32)  NULL COMMENT '原始发票号',
  stock_code_raw  VARCHAR(32)  NULL COMMENT '原始商品编码',
  description_raw VARCHAR(255) NULL COMMENT '原始商品描述',
  quantity_raw    VARCHAR(32)  NULL COMMENT '原始数量',
  invoice_date_raw VARCHAR(32) NULL COMMENT '原始发票时间',
  unit_price_raw  VARCHAR(32)  NULL COMMENT '原始单价',
  customer_id_raw VARCHAR(32)  NULL COMMENT '原始客户ID',
  country_raw     VARCHAR(64)  NULL COMMENT '原始国家/地区',
  PRIMARY KEY (source_row_id)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Online Retail 原始数据落地表';

