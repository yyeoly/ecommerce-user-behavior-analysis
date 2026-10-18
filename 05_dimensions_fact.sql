-- ============================================================
-- 第 5 层：星型模型
-- fact_sales + dim_date + dim_customer + dim_product + dim_country
-- 这样 Power BI 可以用“一个事实表 + 多个维度表”建模，
-- 避免把 50 多万行明细做成难以维护的大宽表。
-- ============================================================

USE retail_ops;

-- ------------------------------------------------------------
-- 5.1 日期维度
-- ------------------------------------------------------------
SET @min_date = (SELECT MIN(DATE(invoice_datetime)) FROM clean_transactions);
SET @max_date = (SELECT MAX(DATE(invoice_datetime)) FROM clean_transactions);

DROP TABLE IF EXISTS dim_date;

CREATE TABLE dim_date (
  date_key          INT         NOT NULL COMMENT 'YYYYMMDD',
  full_date         DATE        NOT NULL,
  year_number       SMALLINT    NOT NULL,
  quarter_number    TINYINT     NOT NULL,
  month_number      TINYINT     NOT NULL,
  month_name        VARCHAR(16) NOT NULL,
  month_key         CHAR(7)     NOT NULL COMMENT 'YYYY-MM',
  day_of_week       TINYINT     NOT NULL COMMENT '1=Monday ... 7=Sunday',
  day_name          VARCHAR(16) NOT NULL,
  is_weekend        TINYINT(1)  NOT NULL,
  is_complete_month TINYINT(1)  NOT NULL COMMENT '0=数据截止月不完整',
  PRIMARY KEY (date_key),
  UNIQUE KEY uk_dim_date_full_date (full_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO dim_date (
  date_key,
  full_date,
  year_number,
  quarter_number,
  month_number,
  month_name,
  month_key,
  day_of_week,
  day_name,
  is_weekend,
  is_complete_month
)
WITH RECURSIVE calendar AS (
  SELECT @min_date AS d
  UNION ALL
  SELECT DATE_ADD(d, INTERVAL 1 DAY)
  FROM calendar
  WHERE d < @max_date
)
SELECT
  CAST(DATE_FORMAT(d, '%Y%m%d') AS UNSIGNED) AS date_key,
  d AS full_date,
  YEAR(d) AS year_number,
  QUARTER(d) AS quarter_number,
  MONTH(d) AS month_number,
  MONTHNAME(d) AS month_name,
  DATE_FORMAT(d, '%Y-%m') AS month_key,
  WEEKDAY(d) + 1 AS day_of_week,
  DAYNAME(d) AS day_name,
  CASE WHEN WEEKDAY(d) >= 5 THEN 1 ELSE 0 END AS is_weekend,
  CASE WHEN d < '2011-12-01' THEN 1 ELSE 0 END AS is_complete_month
FROM calendar;

-- ------------------------------------------------------------
-- 5.2 国家维度
-- ------------------------------------------------------------
DROP TABLE IF EXISTS dim_country;

CREATE TABLE dim_country (
  country_key INT         NOT NULL AUTO_INCREMENT,
  country     VARCHAR(64) NOT NULL,
  PRIMARY KEY (country_key),
  UNIQUE KEY uk_dim_country (country)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO dim_country (country)
SELECT DISTINCT country
FROM clean_transactions
ORDER BY country;

-- ------------------------------------------------------------
-- 5.3 客户维度 + RFM
-- 快照日 = 数据最后一天 + 1 天，避免把最后一天算成“流失”。
-- 货币单位为 GBP。
-- ------------------------------------------------------------
SET @snapshot_date = (
  SELECT DATE_ADD(MAX(DATE(invoice_datetime)), INTERVAL 1 DAY)
  FROM clean_transactions
);

-- GROUP_CONCAT 默认长度只有 1024 字节，客户交易多时会被截断。
-- 这里只需要取最近一次国家，但仍先放大上限，避免隐式截断。
SET SESSION group_concat_max_len = 1000000;

DROP TABLE IF EXISTS dim_customer;

CREATE TABLE dim_customer (
  customer_key      INT          NOT NULL COMMENT '0=匿名客户',
  customer_id       INT          NULL,
  country           VARCHAR(64)  NOT NULL,
  first_order_date  DATE         NULL,
  last_order_date   DATE         NULL,
  orders            INT          NOT NULL,
  units             INT          NOT NULL,
  gross_revenue     DECIMAL(14,2) NOT NULL,
  return_amount     DECIMAL(14,2) NOT NULL,
  net_revenue       DECIMAL(14,2) NOT NULL,
  aov               DECIMAL(14,2) NOT NULL,
  recency_days      INT          NULL,
  r_score           TINYINT      NOT NULL,
  f_score           TINYINT      NOT NULL,
  m_score           TINYINT      NOT NULL,
  segment           VARCHAR(32)  NOT NULL,
  segment_order     TINYINT      NOT NULL,
  has_purchases     TINYINT(1)   NOT NULL,
  PRIMARY KEY (customer_key),
  KEY idx_dim_customer_segment (segment),
  KEY idx_dim_customer_country (country)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO dim_customer (
  customer_key,
  customer_id,
  country,
  first_order_date,
  last_order_date,
  orders,
  units,
  gross_revenue,
  return_amount,
  net_revenue,
  aov,
  recency_days,
  r_score,
  f_score,
  m_score,
  segment,
  segment_order,
  has_purchases
)
WITH customer_base AS (
  SELECT
    customer_id,
    SUBSTRING_INDEX(
      GROUP_CONCAT(country ORDER BY invoice_datetime DESC SEPARATOR '|'),
      '|',
      1
    ) AS country,
    MIN(CASE WHEN is_customer_sale = 1 THEN DATE(invoice_datetime) END) AS first_order_date,
    MAX(CASE WHEN is_customer_sale = 1 THEN DATE(invoice_datetime) END) AS last_order_date,
    COUNT(DISTINCT CASE WHEN is_customer_sale = 1 THEN invoice_no END) AS orders,
    SUM(CASE WHEN is_customer_sale = 1 THEN quantity ELSE 0 END) AS units,
    SUM(CASE WHEN is_customer_sale = 1 THEN line_revenue ELSE 0 END) AS gross_revenue,
    MAX(DATE(invoice_datetime)) AS last_activity_date
  FROM clean_transactions
  WHERE customer_id IS NOT NULL
  GROUP BY customer_id
),
customer_returns AS (
  SELECT
    customer_id,
    ABS(SUM(CASE WHEN is_cancellation = 1 AND is_product = 1 THEN line_revenue ELSE 0 END)) AS return_amount
  FROM clean_transactions
  WHERE customer_id IS NOT NULL
  GROUP BY customer_id
),
customer_metrics AS (
  SELECT
    b.customer_id,
    b.country,
    b.first_order_date,
    b.last_order_date,
    b.orders,
    b.units,
    b.gross_revenue,
    COALESCE(r.return_amount, 0) AS return_amount,
    b.gross_revenue - COALESCE(r.return_amount, 0) AS net_revenue,
    CASE WHEN b.orders > 0 THEN b.gross_revenue / b.orders ELSE 0 END AS aov,
    DATEDIFF(
      @snapshot_date,
      COALESCE(b.last_order_date, b.last_activity_date)
    ) AS recency_days
  FROM customer_base AS b
  LEFT JOIN customer_returns AS r
    ON r.customer_id = b.customer_id
),
customer_scored AS (
  SELECT
    m.*,
    CASE
      WHEN m.orders = 0 THEN 1
      ELSE 6 - NTILE(5) OVER (
        ORDER BY CASE WHEN m.orders > 0 THEN m.recency_days ELSE 99999 END ASC
      )
    END AS r_score,
    NTILE(5) OVER (ORDER BY m.orders ASC) AS f_score,
    NTILE(5) OVER (ORDER BY m.net_revenue ASC) AS m_score
  FROM customer_metrics AS m
),
customer_segmented AS (
  SELECT
    s.*,
    CASE
      WHEN s.orders = 0 THEN 'Returns Only'
      WHEN s.r_score >= 4 AND s.f_score >= 4 AND s.m_score >= 4 THEN 'Champions'
      WHEN s.r_score >= 3 AND s.f_score >= 3 THEN 'Loyal Customers'
      WHEN s.r_score >= 4 AND s.f_score <= 2 THEN 'Potential Loyalists'
      WHEN s.r_score <= 2 AND s.f_score >= 3 THEN 'At Risk'
      WHEN s.r_score <= 2 AND s.f_score <= 2 THEN 'Hibernating'
      WHEN s.r_score = 3 AND s.f_score <= 2 THEN 'Need Attention'
      ELSE 'Others'
    END AS segment
  FROM customer_scored AS s
)
SELECT
  customer_id AS customer_key,
  customer_id,
  country,
  first_order_date,
  last_order_date,
  orders,
  units,
  ROUND(gross_revenue, 2),
  ROUND(return_amount, 2),
  ROUND(net_revenue, 2),
  ROUND(aov, 2),
  recency_days,
  r_score,
  f_score,
  m_score,
  segment,
  CASE segment
    WHEN 'Champions' THEN 1
    WHEN 'Loyal Customers' THEN 2
    WHEN 'Potential Loyalists' THEN 3
    WHEN 'Need Attention' THEN 4
    WHEN 'At Risk' THEN 5
    WHEN 'Hibernating' THEN 6
    WHEN 'Others' THEN 7
    WHEN 'Returns Only' THEN 8
    ELSE 9
  END AS segment_order,
  CASE WHEN orders > 0 THEN 1 ELSE 0 END AS has_purchases
FROM customer_segmented;

-- 匿名客户：让匿名交易也能在 Power BI 中建立关系，
-- 但不参与客户数、复购率、RFM 等客户指标。
INSERT INTO dim_customer (
  customer_key, customer_id, country, first_order_date, last_order_date,
  orders, units, gross_revenue, return_amount, net_revenue, aov,
  recency_days, r_score, f_score, m_score, segment, segment_order, has_purchases
) VALUES (
  0, NULL, 'Anonymous', NULL, NULL,
  0, 0, 0, 0, 0, 0,
  NULL, 1, 1, 1, 'Anonymous', 9, 0
);

-- ------------------------------------------------------------
-- 5.4 商品维度 + ABC 分类
-- 分类是按描述关键词生成的分析标签，不是源数据官方类目。
-- ------------------------------------------------------------
DROP TABLE IF EXISTS dim_product;

CREATE TABLE dim_product (
  stock_code        VARCHAR(32)  NOT NULL,
  description       VARCHAR(255) NOT NULL,
  category          VARCHAR(40)  NOT NULL,
  first_sale_date   DATE         NULL,
  last_sale_date    DATE         NULL,
  units_sold        INT          NOT NULL,
  gross_revenue     DECIMAL(14,2) NOT NULL,
  net_revenue       DECIMAL(14,2) NOT NULL,
  net_units         INT          NOT NULL,
  orders            INT          NOT NULL,
  customers         INT          NOT NULL,
  return_units      INT          NOT NULL,
  return_amount     DECIMAL(14,2) NOT NULL,
  return_rate       DECIMAL(8,4) NOT NULL,
  avg_selling_price DECIMAL(10,2) NOT NULL,
  gross_revenue_share DECIMAL(10,6) NOT NULL,
  net_revenue_share DECIMAL(10,6) NOT NULL,
  cumulative_net_share DECIMAL(10,6) NOT NULL,
  abc_class         CHAR(1)      NOT NULL,
  has_sales         TINYINT(1)   NOT NULL,
  PRIMARY KEY (stock_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO dim_product (
  stock_code,
  description,
  category,
  first_sale_date,
  last_sale_date,
  units_sold,
  gross_revenue,
  net_revenue,
  net_units,
  orders,
  customers,
  return_units,
  return_amount,
  return_rate,
  avg_selling_price,
  gross_revenue_share,
  net_revenue_share,
  cumulative_net_share,
  abc_class,
  has_sales
)
WITH product_metrics AS (
  SELECT
    c.stock_code,
    COALESCE(MAX(m.description), MAX(c.description)) AS description,
    MIN(CASE WHEN c.is_product_sale = 1 THEN DATE(c.invoice_datetime) END) AS first_sale_date,
    MAX(CASE WHEN c.is_product_sale = 1 THEN DATE(c.invoice_datetime) END) AS last_sale_date,
    SUM(CASE WHEN c.is_product_sale = 1 THEN c.quantity ELSE 0 END) AS units_sold,
    SUM(CASE WHEN c.is_product_sale = 1 THEN c.line_revenue ELSE 0 END) AS gross_revenue,
    COUNT(DISTINCT CASE WHEN c.is_product_sale = 1 THEN c.invoice_no END) AS orders,
    COUNT(DISTINCT CASE WHEN c.is_customer_sale = 1 THEN c.customer_id END) AS customers,
    ABS(SUM(CASE WHEN c.is_cancellation = 1 THEN c.quantity ELSE 0 END)) AS return_units,
    ABS(SUM(CASE WHEN c.is_cancellation = 1 THEN c.line_revenue ELSE 0 END)) AS return_amount,
    SUM(CASE WHEN c.is_product_sale = 1 THEN c.line_revenue ELSE 0 END)
      - ABS(SUM(CASE WHEN c.is_cancellation = 1 THEN c.line_revenue ELSE 0 END)) AS net_revenue,
    SUM(CASE WHEN c.is_product_sale = 1 THEN c.quantity ELSE 0 END)
      - ABS(SUM(CASE WHEN c.is_cancellation = 1 THEN c.quantity ELSE 0 END)) AS net_units
  FROM clean_transactions AS c
  LEFT JOIN product_description_map AS m
    ON m.stock_code = c.stock_code
  WHERE c.is_product = 1
  GROUP BY c.stock_code
),
product_with_share AS (
  SELECT
    p.*,
    GREATEST(p.net_revenue, 0) AS positive_net_revenue,
    CASE
      WHEN p.gross_revenue = 0 THEN 0
      ELSE p.gross_revenue / SUM(p.gross_revenue) OVER ()
    END AS gross_revenue_share,
    CASE
      WHEN SUM(p.net_revenue) OVER () = 0 THEN 0
      ELSE p.net_revenue / SUM(p.net_revenue) OVER ()
    END AS net_revenue_share,
    CASE
      WHEN p.units_sold > 0 THEN p.gross_revenue / p.units_sold
      ELSE 0
    END AS avg_selling_price,
    CASE
      WHEN p.gross_revenue > 0 THEN p.return_amount / p.gross_revenue
      ELSE 0
    END AS return_rate
  FROM product_metrics AS p
),
product_ranked AS (
  SELECT
    w.*,
    SUM(w.positive_net_revenue) OVER (
      ORDER BY w.positive_net_revenue DESC, w.stock_code
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS positive_cumulative_revenue
  FROM product_with_share AS w
)
SELECT
  stock_code,
  description,
  CASE
    WHEN UPPER(description) REGEXP 'CHRISTMAS|XMAS|SANTA|ADVENT|REINDEER|SNOWMAN|NOEL|MISTLETOE|STOCKING' THEN 'Christmas & Seasonal'
    WHEN UPPER(description) REGEXP 'MUG|CUP|PLATE|BOWL|TEAPOT|JUG|CUTLERY|KITCHEN|CAKE|TEA |COFFEE|JAR|BOTTLE|GLASS|BAKING|COOK|SPOON|FORK|KNIFE|NAPKIN|EGG|MILK|SUGAR|TRAY|COASTER' THEN 'Kitchen & Dining'
    WHEN UPPER(description) REGEXP 'SOAP|BATH|HAND CREAM|COSMETIC|WASH|SPONGE|BRUSH|COMB|PERFUME|LOTION' THEN 'Bath & Beauty'
    WHEN UPPER(description) REGEXP 'CUSHION|COVER|TOWEL|APRON|BLANKET|FABRIC|PILLOW|DUVET|THROW|MAT|RUG|TABLECLOTH' THEN 'Textiles'
    WHEN UPPER(description) REGEXP 'BOX|BASKET|BAG|TIN|CASE|HANGER|DRAWER|CHEST|TRUNK|ORGANISER|ORGANIZER|POUCH|WASHBAG' THEN 'Storage & Organization'
    WHEN UPPER(description) REGEXP 'CARD|NOTEBOOK|PEN|PENCIL|PARTY|GARLAND|BUNTING|STICKER|WRAP|RIBBON|ENVELOPE|JOURNAL|DIARY|PAPER|CHALK|BALLOON' THEN 'Stationery & Party'
    WHEN UPPER(description) REGEXP 'TOY|DOLL|GAME|CHILD|KIDS|BABY|PLAYHOUSE|TEDDY|PUZZLE|SKIPPING|BALL|KITE|JIGSAW|BLOCKS' THEN 'Kids & Toys'
    WHEN UPPER(description) REGEXP 'GARDEN|PLANT|FLOWER|BIRD|OUTDOOR|PARASOL|WATERING|SEED|POT|WINDMILL|WIND CHIME' THEN 'Garden & Outdoor'
    WHEN UPPER(description) REGEXP 'NECKLACE|BRACELET|EARRING|RING|JEWEL|HAIR|SCARF|UMBRELLA|GLOVE|PURSE|WALLET|BELT|HAT|SHOES|SLIPPERS|COLLAR|LEAD' THEN 'Jewellery & Accessories'
    WHEN UPPER(description) REGEXP 'CANDLE|HOLDER|LIGHT|LANTERN|FRAME|CLOCK|VASE|ORNAMENT|HEART|SIGN|WALL|MIRROR|DOOR|HOOK|HANGING|DECORATION|FIGURE|STATUE' THEN 'Home Decor & Lighting'
    ELSE 'Other'
  END AS category,
  first_sale_date,
  last_sale_date,
  units_sold,
  ROUND(gross_revenue, 2),
  ROUND(net_revenue, 2),
  net_units,
  orders,
  customers,
  return_units,
  ROUND(return_amount, 2),
  ROUND(return_rate, 4),
  ROUND(avg_selling_price, 2),
  ROUND(gross_revenue_share, 6),
  ROUND(net_revenue_share, 6),
  ROUND(
    positive_cumulative_revenue
    / NULLIF(SUM(positive_net_revenue) OVER (), 0),
    6
  ) AS cumulative_net_share,
  CASE
    WHEN net_revenue <= 0 THEN 'C'
    WHEN (positive_cumulative_revenue - positive_net_revenue)
         / NULLIF(SUM(positive_net_revenue) OVER (), 0) < 0.80 THEN 'A'
    WHEN (positive_cumulative_revenue - positive_net_revenue)
         / NULLIF(SUM(positive_net_revenue) OVER (), 0) < 0.95 THEN 'B'
    ELSE 'C'
  END AS abc_class,
  CASE WHEN units_sold > 0 THEN 1 ELSE 0 END AS has_sales
FROM product_ranked;

-- ------------------------------------------------------------
-- 5.5 销售事实表
-- 保留全部清洗后行；Power BI 通过 is_product_sale / is_cancellation
-- 等字段切换口径，而不是为不同口径复制多张事实表。
-- ------------------------------------------------------------
DROP TABLE IF EXISTS fact_sales;

CREATE TABLE fact_sales (
  line_id          BIGINT UNSIGNED NOT NULL,
  invoice_no       VARCHAR(32)  NOT NULL,
  date_key         INT          NOT NULL,
  invoice_datetime DATETIME     NOT NULL,
  customer_key     INT          NOT NULL,
  stock_code       VARCHAR(32)  NOT NULL,
  country_key      INT          NOT NULL,
  country          VARCHAR(64)  NOT NULL,
  quantity         INT          NOT NULL,
  unit_price       DECIMAL(12,2) NOT NULL,
  line_revenue     DECIMAL(14,2) NOT NULL,
  invoice_type     VARCHAR(16)  NOT NULL,
  is_cancellation  TINYINT(1)   NOT NULL,
  is_product       TINYINT(1)   NOT NULL,
  is_valid_sale    TINYINT(1)   NOT NULL,
  is_product_sale  TINYINT(1)   NOT NULL,
  is_customer_sale TINYINT(1)   NOT NULL,
  is_missing_customer TINYINT(1) NOT NULL,
  is_duplicate     TINYINT(1)   NOT NULL,
  has_zero_price   TINYINT(1)   NOT NULL,
  has_negative_price TINYINT(1) NOT NULL,
  order_hour       TINYINT      NOT NULL,
  day_of_week      TINYINT      NOT NULL,
  day_name         VARCHAR(16)  NOT NULL,
  PRIMARY KEY (line_id),
  KEY idx_fact_date (date_key),
  KEY idx_fact_customer (customer_key),
  KEY idx_fact_product (stock_code),
  KEY idx_fact_country (country_key),
  KEY idx_fact_sale_flags (is_product_sale, is_cancellation)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO fact_sales
SELECT
  c.line_id,
  c.invoice_no,
  CAST(DATE_FORMAT(c.invoice_datetime, '%Y%m%d') AS UNSIGNED) AS date_key,
  c.invoice_datetime,
  COALESCE(c.customer_id, 0) AS customer_key,
  c.stock_code,
  dc.country_key,
  c.country,
  c.quantity,
  c.unit_price,
  c.line_revenue,
  c.invoice_type,
  c.is_cancellation,
  c.is_product,
  c.is_valid_sale,
  c.is_product_sale,
  c.is_customer_sale,
  c.is_missing_customer,
  c.is_duplicate,
  c.has_zero_price,
  c.has_negative_price,
  HOUR(c.invoice_datetime) AS order_hour,
  WEEKDAY(c.invoice_datetime) + 1 AS day_of_week,
  DAYNAME(c.invoice_datetime) AS day_name
FROM clean_transactions AS c
LEFT JOIN dim_country AS dc
  ON dc.country = c.country;

-- 星型模型完整性检查。
SELECT
  (SELECT COUNT(*) FROM fact_sales) AS fact_rows,
  (SELECT COUNT(*) FROM dim_customer) AS customer_rows,
  (SELECT COUNT(*) FROM dim_product) AS product_rows,
  (SELECT COUNT(*) FROM dim_date) AS date_rows,
  (SELECT COUNT(*) FROM dim_country) AS country_rows,
  (SELECT COUNT(*) FROM fact_sales f LEFT JOIN dim_customer c ON c.customer_key = f.customer_key WHERE c.customer_key IS NULL) AS orphan_customers,
  (SELECT COUNT(*) FROM fact_sales f LEFT JOIN dim_product p ON p.stock_code = f.stock_code WHERE f.is_product = 1 AND p.stock_code IS NULL) AS orphan_products;

