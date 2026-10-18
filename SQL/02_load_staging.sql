-- ============================================================
-- 第 2 层：把 CSV 装入 Staging
-- 运行前请确认：
--   1. CSV 路径存在；
--   2. 用 mysql 客户端连接时加 --local-infile=1；
--   3. 服务端 local_infile=ON。
-- 源文件编码为 Latin-1，因此这里显式声明 CHARACTER SET latin1。
-- ============================================================

USE retail_ops;

TRUNCATE TABLE stg_online_retail;

LOAD DATA LOCAL INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/data.csv'
INTO TABLE stg_online_retail
CHARACTER SET latin1
FIELDS TERMINATED BY ','
       OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(
  invoice_no_raw,
  stock_code_raw,
  description_raw,
  quantity_raw,
  invoice_date_raw,
  unit_price_raw,
  customer_id_raw,
  country_raw
);

-- 导入后应看到 541909 行。
SELECT COUNT(*) AS staging_row_count
FROM stg_online_retail;

