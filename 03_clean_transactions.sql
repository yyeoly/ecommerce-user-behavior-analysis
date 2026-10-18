-- ============================================================
-- 第 3 层：清洗与标准化
-- 设计原则：
--   1. 不直接删除“有问题”的行，而是打标签并保留，便于审计；
--   2. 只对明确的重复行做去重；
--   3. 商品、退货、邮费/调整分别用字段标记；
--   4. 销售额统一使用 quantity * unit_price，货币为英镑 GBP。
-- ============================================================

USE retail_ops;

-- ------------------------------------------------------------
-- 3.1 商品描述字典
-- 目的：同一 StockCode 可能有多条描述，选择出现次数最多的描述，
--       用于补全缺失描述。若出现次数相同，按描述字母序稳定选择。
-- ------------------------------------------------------------
DROP TABLE IF EXISTS product_description_map;

CREATE TABLE product_description_map AS
SELECT stock_code, description
FROM (
  SELECT
    stock_code,
    description,
    cnt,
    ROW_NUMBER() OVER (
      PARTITION BY stock_code
      ORDER BY cnt DESC, description ASC
    ) AS rn
  FROM (
    SELECT
      UPPER(TRIM(stock_code_raw)) AS stock_code,
      TRIM(description_raw) AS description,
      COUNT(*) AS cnt
    FROM stg_online_retail
    WHERE description_raw IS NOT NULL
      AND TRIM(description_raw) <> ''
    GROUP BY
      UPPER(TRIM(stock_code_raw)),
      TRIM(description_raw)
  ) AS description_counts
) AS ranked_descriptions
WHERE rn = 1;

ALTER TABLE product_description_map
  ADD PRIMARY KEY (stock_code);

-- ------------------------------------------------------------
-- 3.2 清洗后的交易明细
-- ------------------------------------------------------------
DROP TABLE IF EXISTS clean_transactions;

CREATE TABLE clean_transactions (
  line_id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '清洗后行ID',
  source_row_id      BIGINT UNSIGNED NOT NULL COMMENT '对应 Staging 原始行',
  invoice_no         VARCHAR(32)  NOT NULL COMMENT '标准化发票号',
  stock_code         VARCHAR(32)  NOT NULL COMMENT '标准化商品编码',
  description        VARCHAR(255) NOT NULL COMMENT '补全后的商品描述',
  quantity           INT          NOT NULL COMMENT '数量，退货为负数',
  invoice_datetime   DATETIME     NOT NULL COMMENT '发票时间',
  unit_price         DECIMAL(12,2) NOT NULL COMMENT '单价 GBP',
  customer_id        INT          NULL COMMENT '客户ID，匿名交易为NULL',
  country            VARCHAR(64)  NOT NULL COMMENT '标准化国家/地区',
  line_revenue       DECIMAL(14,2) NOT NULL COMMENT '行销售额 GBP',
  invoice_type       VARCHAR(16)  NOT NULL COMMENT 'Sale/Return/Adjustment',
  is_cancellation    TINYINT(1)   NOT NULL COMMENT '是否取消/退货发票',
  is_product         TINYINT(1)   NOT NULL COMMENT '是否商品行（0=邮费/折扣/手续费等）',
  is_missing_customer TINYINT(1)  NOT NULL COMMENT '客户ID是否缺失',
  has_zero_price     TINYINT(1)   NOT NULL COMMENT '单价是否为0',
  has_negative_price TINYINT(1)   NOT NULL COMMENT '单价是否为负',
  is_duplicate       TINYINT(1)   NOT NULL COMMENT '是否重复行（1=需排除）',
  is_valid_sale      TINYINT(1)   NOT NULL COMMENT '是否有效正向销售行',
  is_product_sale    TINYINT(1)   NOT NULL COMMENT '是否商品销售行',
  is_customer_sale   TINYINT(1)   NOT NULL COMMENT '是否可归属客户的商品销售行',
  quality_note       VARCHAR(255) NULL COMMENT '数据质量说明',
  PRIMARY KEY (line_id),
  KEY idx_clean_invoice (invoice_no),
  KEY idx_clean_stock (stock_code),
  KEY idx_clean_customer (customer_id),
  KEY idx_clean_datetime (invoice_datetime),
  KEY idx_clean_sale_flags (is_product_sale, is_cancellation)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_0900_ai_ci
  COMMENT='清洗后的 Online Retail 交易明细';

INSERT INTO clean_transactions (
  source_row_id,
  invoice_no,
  stock_code,
  description,
  quantity,
  invoice_datetime,
  unit_price,
  customer_id,
  country,
  line_revenue,
  invoice_type,
  is_cancellation,
  is_product,
  is_missing_customer,
  has_zero_price,
  has_negative_price,
  is_duplicate,
  is_valid_sale,
  is_product_sale,
  is_customer_sale,
  quality_note
)
WITH normalized AS (
  SELECT
    s.source_row_id,
    UPPER(TRIM(s.invoice_no_raw)) AS invoice_no,
    UPPER(TRIM(s.stock_code_raw)) AS stock_code,
    COALESCE(
      NULLIF(TRIM(s.description_raw), ''),
      m.description,
      CASE
        WHEN UPPER(TRIM(s.stock_code_raw)) LIKE 'GIFT\_0001\_%' ESCAPE '\\'
          THEN 'GIFT VOUCHER'
        ELSE 'UNKNOWN PRODUCT'
      END
    ) AS description,
    CAST(s.quantity_raw AS SIGNED) AS quantity,
    STR_TO_DATE(TRIM(s.invoice_date_raw), '%m/%d/%Y %H:%i') AS invoice_datetime,
    CAST(s.unit_price_raw AS DECIMAL(12,2)) AS unit_price,
    CAST(NULLIF(TRIM(s.customer_id_raw), '') AS UNSIGNED) AS customer_id,
    CASE UPPER(TRIM(s.country_raw))
      WHEN 'EIRE' THEN 'Ireland'
      WHEN 'RSA' THEN 'South Africa'
      WHEN 'USA' THEN 'United States'
      ELSE TRIM(s.country_raw)
    END AS country
  FROM stg_online_retail AS s
  LEFT JOIN product_description_map AS m
    ON m.stock_code = UPPER(TRIM(s.stock_code_raw))
  WHERE s.invoice_date_raw IS NOT NULL
    AND TRIM(s.invoice_date_raw) <> ''
),
typed AS (
  SELECT
    n.*,
    CASE
      WHEN n.invoice_no LIKE 'C%' THEN 'Return'
      WHEN n.invoice_no REGEXP '^[0-9]+$' THEN 'Sale'
      ELSE 'Adjustment'
    END AS invoice_type,
    CASE
      WHEN UPPER(n.description) = 'EBAY' THEN 0
      WHEN UPPER(n.description) LIKE 'UNSALEABLE%' THEN 0
      WHEN n.stock_code IN (
        'POST', 'DOT', 'M', 'D', 'S', 'C2',
        'BANK CHARGES', 'AMAZONFEE', 'CRUK', 'B'
      ) THEN 0
      WHEN n.stock_code LIKE 'GIFT\_0001\_%' ESCAPE '\\' THEN 0
      ELSE 1
    END AS is_product
  FROM normalized AS n
),
ranked AS (
  SELECT
    t.*,
    ROW_NUMBER() OVER (
      PARTITION BY
        invoice_no,
        stock_code,
        quantity,
        invoice_datetime,
        unit_price,
        COALESCE(customer_id, 0)
      ORDER BY source_row_id
    ) AS duplicate_rank
  FROM typed AS t
),
flagged AS (
  SELECT
    r.*,
    CASE WHEN r.duplicate_rank > 1 THEN 1 ELSE 0 END AS is_duplicate,
    CASE
      WHEN r.invoice_type = 'Sale'
       AND r.quantity > 0
       AND r.unit_price > 0
       AND r.duplicate_rank = 1
        THEN 1 ELSE 0
    END AS is_valid_sale,
    CASE
      WHEN r.invoice_type = 'Sale'
       AND r.quantity > 0
       AND r.unit_price > 0
       AND r.duplicate_rank = 1
       AND r.is_product = 1
        THEN 1 ELSE 0
    END AS is_product_sale,
    CASE
      WHEN r.invoice_type = 'Sale'
       AND r.quantity > 0
       AND r.unit_price > 0
       AND r.duplicate_rank = 1
       AND r.is_product = 1
       AND r.customer_id IS NOT NULL
        THEN 1 ELSE 0
    END AS is_customer_sale
  FROM ranked AS r
)
SELECT
  source_row_id,
  invoice_no,
  stock_code,
  description,
  quantity,
  invoice_datetime,
  unit_price,
  customer_id,
  country,
  ROUND(quantity * unit_price, 2) AS line_revenue,
  invoice_type,
  CASE WHEN invoice_type = 'Return' THEN 1 ELSE 0 END AS is_cancellation,
  is_product,
  CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END AS is_missing_customer,
  CASE WHEN unit_price = 0 THEN 1 ELSE 0 END AS has_zero_price,
  CASE WHEN unit_price < 0 THEN 1 ELSE 0 END AS has_negative_price,
  is_duplicate,
  is_valid_sale,
  is_product_sale,
  is_customer_sale,
  CONCAT_WS(
    '; ',
    CASE WHEN duplicate_rank > 1 THEN 'duplicate' END,
    CASE WHEN invoice_type = 'Return' THEN 'cancellation/return' END,
    CASE WHEN invoice_type = 'Adjustment' THEN 'non-sale adjustment' END,
    CASE WHEN quantity < 0 THEN 'negative quantity' END,
    CASE WHEN unit_price = 0 THEN 'zero price' END,
    CASE WHEN unit_price < 0 THEN 'negative price' END,
    CASE WHEN customer_id IS NULL THEN 'missing customer' END,
    CASE WHEN is_product = 0 THEN 'non-product/service line' END
  ) AS quality_note
FROM flagged;

-- 质量检查：清洗后行数应等于原始行数，因为这里只做标记和去重标记，
-- 不物理删除行。后续分析层再通过 WHERE 条件选择需要的记录。
SELECT
  (SELECT COUNT(*) FROM stg_online_retail) AS staging_rows,
  (SELECT COUNT(*) FROM clean_transactions) AS clean_rows,
  (SELECT SUM(is_duplicate) FROM clean_transactions) AS duplicate_rows,
  (SELECT SUM(is_product_sale) FROM clean_transactions) AS product_sale_rows,
  (SELECT SUM(is_cancellation) FROM clean_transactions) AS cancellation_rows;

