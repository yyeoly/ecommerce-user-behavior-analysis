-- ============================================================
-- 第 6 层：面向业务分析的聚合表
-- 口径统一：
--   毛商品销售额 = is_product_sale = 1 的 line_revenue 之和
--   退货金额     = is_cancellation = 1 且 is_product = 1 的 line_revenue 绝对值
--   净销售额     = 毛销售额 - 退货金额
--   订单数       = 有效商品销售发票去重
--   客户数       = 可归属客户的商品销售客户去重
-- 货币：GBP
-- ============================================================

USE retail_ops;

-- ------------------------------------------------------------
-- 6.1 月度经营指标
-- ------------------------------------------------------------
DROP TABLE IF EXISTS agg_monthly_kpi;

CREATE TABLE agg_monthly_kpi AS
WITH month_base AS (
  SELECT
    d.month_key,
    MIN(d.full_date) AS month_start,
    MIN(d.month_name) AS month_name,
    MIN(d.is_complete_month) AS is_complete_month,
    SUM(CASE WHEN f.is_product_sale = 1 THEN f.line_revenue ELSE 0 END) AS gross_revenue,
    ABS(SUM(CASE WHEN f.is_cancellation = 1 AND f.is_product = 1 THEN f.line_revenue ELSE 0 END)) AS return_amount,
    COUNT(DISTINCT CASE WHEN f.is_product_sale = 1 THEN f.invoice_no END) AS orders,
    COUNT(DISTINCT CASE WHEN f.is_customer_sale = 1 THEN f.customer_key END) AS active_customers,
    SUM(CASE WHEN f.is_product_sale = 1 THEN f.quantity ELSE 0 END) AS units,
    SUM(CASE WHEN f.is_product_sale = 1 AND f.country <> 'United Kingdom' THEN f.line_revenue ELSE 0 END) AS international_revenue
  FROM fact_sales AS f
  JOIN dim_date AS d
    ON d.date_key = f.date_key
  GROUP BY d.month_key
),
first_order_month AS (
  SELECT
    DATE_FORMAT(first_order_date, '%Y-%m') AS month_key,
    COUNT(*) AS new_customers
  FROM dim_customer
  WHERE has_purchases = 1
  GROUP BY DATE_FORMAT(first_order_date, '%Y-%m')
),
monthly AS (
  SELECT
    b.*,
    b.gross_revenue - b.return_amount AS net_revenue,
    COALESCE(n.new_customers, 0) AS new_customers,
    GREATEST(b.active_customers - COALESCE(n.new_customers, 0), 0) AS returning_customers,
    CASE WHEN b.orders > 0 THEN b.gross_revenue / b.orders ELSE 0 END AS aov_gross,
    CASE WHEN b.orders > 0 THEN (b.gross_revenue - b.return_amount) / b.orders ELSE 0 END AS aov_net,
    CASE WHEN b.gross_revenue > 0 THEN b.return_amount / b.gross_revenue ELSE 0 END AS return_rate,
    CASE WHEN b.gross_revenue > 0 THEN b.international_revenue / b.gross_revenue ELSE 0 END AS international_share,
    CASE WHEN b.orders > 0 THEN b.units / b.orders ELSE 0 END AS avg_basket_units
  FROM month_base AS b
  LEFT JOIN first_order_month AS n
    ON n.month_key = b.month_key
)
SELECT
  m.*,
  LAG(m.gross_revenue) OVER (ORDER BY m.month_key) AS prev_gross_revenue,
  CASE
    WHEN LAG(m.gross_revenue) OVER (ORDER BY m.month_key) IS NULL
      OR LAG(m.gross_revenue) OVER (ORDER BY m.month_key) = 0 THEN NULL
    ELSE (m.gross_revenue - LAG(m.gross_revenue) OVER (ORDER BY m.month_key))
         / LAG(m.gross_revenue) OVER (ORDER BY m.month_key)
  END AS revenue_growth_pct,
  CASE
    WHEN LAG(m.orders) OVER (ORDER BY m.month_key) IS NULL
      OR LAG(m.orders) OVER (ORDER BY m.month_key) = 0 THEN NULL
    ELSE (m.orders - LAG(m.orders) OVER (ORDER BY m.month_key))
         / LAG(m.orders) OVER (ORDER BY m.month_key)
  END AS order_growth_pct
FROM monthly AS m;

ALTER TABLE agg_monthly_kpi
  ADD PRIMARY KEY (month_key);

-- ------------------------------------------------------------
-- 6.2 国家/地区分析
-- ------------------------------------------------------------
DROP TABLE IF EXISTS agg_country_summary;

CREATE TABLE agg_country_summary AS
WITH country_base AS (
  SELECT
    f.country,
    SUM(CASE WHEN f.is_product_sale = 1 THEN f.line_revenue ELSE 0 END) AS gross_revenue,
    ABS(SUM(CASE WHEN f.is_cancellation = 1 AND f.is_product = 1 THEN f.line_revenue ELSE 0 END)) AS return_amount,
    COUNT(DISTINCT CASE WHEN f.is_product_sale = 1 THEN f.invoice_no END) AS orders,
    COUNT(DISTINCT CASE WHEN f.is_customer_sale = 1 THEN f.customer_key END) AS customers,
    SUM(CASE WHEN f.is_product_sale = 1 THEN f.quantity ELSE 0 END) AS units
  FROM fact_sales AS f
  GROUP BY f.country
),
country_metrics AS (
  SELECT
    b.*,
    b.gross_revenue - b.return_amount AS net_revenue,
    CASE WHEN b.orders > 0 THEN b.gross_revenue / b.orders ELSE 0 END AS aov,
    CASE WHEN b.gross_revenue > 0 THEN b.return_amount / b.gross_revenue ELSE 0 END AS return_rate,
    CASE WHEN b.customers > 0 THEN b.gross_revenue / b.customers ELSE 0 END AS revenue_per_customer,
    CASE WHEN b.customers > 0 THEN b.orders / b.customers ELSE 0 END AS orders_per_customer,
    CASE WHEN b.country = 'United Kingdom' THEN 'Domestic' ELSE 'International' END AS country_type
  FROM country_base AS b
)
SELECT
  c.*,
  CASE WHEN SUM(c.gross_revenue) OVER () > 0
       THEN c.gross_revenue / SUM(c.gross_revenue) OVER () ELSE 0 END AS revenue_share,
  CASE WHEN SUM(c.customers) OVER () > 0
       THEN c.customers / SUM(c.customers) OVER () ELSE 0 END AS customer_share,
  RANK() OVER (ORDER BY c.gross_revenue DESC) AS revenue_rank
FROM country_metrics AS c;

-- ------------------------------------------------------------
-- 6.3 商品分析（含 ABC 排名）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS agg_product_summary;

CREATE TABLE agg_product_summary AS
SELECT
  p.*,
  RANK() OVER (ORDER BY p.net_revenue DESC) AS revenue_rank,
  CASE
    WHEN p.net_revenue > 0
     AND ROW_NUMBER() OVER (ORDER BY p.net_revenue DESC, p.stock_code) <= 20 THEN 1
    ELSE 0
  END AS top20_flag,
  CASE WHEN SUM(p.units_sold) OVER () > 0
       THEN p.units_sold / SUM(p.units_sold) OVER () ELSE 0 END AS unit_share,
  CASE WHEN p.net_revenue > 0 THEN 1 ELSE 0 END AS is_net_positive
FROM dim_product AS p
WHERE p.has_sales = 1;

ALTER TABLE agg_product_summary
  ADD PRIMARY KEY (stock_code);

-- ------------------------------------------------------------
-- 6.4 商品类目分析（关键词标签，属于分析用派生维度）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS agg_category_summary;

CREATE TABLE agg_category_summary AS
WITH category_base AS (
  SELECT
    category,
    COUNT(*) AS products,
    SUM(units_sold) AS units_sold,
    SUM(gross_revenue) AS gross_revenue,
    SUM(return_amount) AS return_amount,
    SUM(net_revenue) AS net_revenue,
    SUM(orders) AS product_order_links,
    SUM(customers) AS product_customer_links
  FROM dim_product
  WHERE has_sales = 1
  GROUP BY category
),
category_metrics AS (
  SELECT
    b.*,
    CASE WHEN b.gross_revenue > 0 THEN b.return_amount / b.gross_revenue ELSE 0 END AS return_rate,
    CASE WHEN b.units_sold > 0 THEN b.gross_revenue / b.units_sold ELSE 0 END AS avg_unit_price
  FROM category_base AS b
)
SELECT
  c.*,
  CASE WHEN SUM(c.gross_revenue) OVER () > 0
       THEN c.gross_revenue / SUM(c.gross_revenue) OVER () ELSE 0 END AS gross_revenue_share,
  CASE WHEN SUM(c.net_revenue) OVER () > 0
       THEN c.net_revenue / SUM(c.net_revenue) OVER () ELSE 0 END AS net_revenue_share,
  RANK() OVER (ORDER BY c.net_revenue DESC) AS revenue_rank
FROM category_metrics AS c;

-- ------------------------------------------------------------
-- 6.5 客户明细与价值分层
-- ------------------------------------------------------------
DROP TABLE IF EXISTS agg_customer_summary;

CREATE TABLE agg_customer_summary AS
SELECT
  c.*,
  RANK() OVER (ORDER BY c.net_revenue DESC) AS revenue_rank,
  NTILE(10) OVER (ORDER BY c.net_revenue DESC) AS value_decile,
  CASE WHEN NTILE(10) OVER (ORDER BY c.net_revenue DESC) <= 2 THEN 1 ELSE 0 END AS is_top20pct
FROM dim_customer AS c
WHERE c.has_purchases = 1;

ALTER TABLE agg_customer_summary
  ADD PRIMARY KEY (customer_key);

-- ------------------------------------------------------------
-- 6.6 RFM 分层汇总
-- ------------------------------------------------------------
DROP TABLE IF EXISTS agg_rfm_segments;

CREATE TABLE agg_rfm_segments AS
WITH segment_base AS (
  SELECT
    segment,
    MIN(segment_order) AS segment_order,
    COUNT(*) AS customers,
    SUM(net_revenue) AS net_revenue,
    SUM(gross_revenue) AS gross_revenue,
    SUM(return_amount) AS return_amount,
    AVG(orders) AS avg_orders,
    AVG(recency_days) AS avg_recency_days,
    AVG(net_revenue) AS avg_customer_value,
    AVG(aov) AS avg_order_value
  FROM dim_customer
  WHERE has_purchases = 1
  GROUP BY segment
)
SELECT
  s.*,
  CASE WHEN SUM(s.customers) OVER () > 0
       THEN s.customers / SUM(s.customers) OVER () ELSE 0 END AS customer_share,
  CASE WHEN SUM(s.net_revenue) OVER () > 0
       THEN s.net_revenue / SUM(s.net_revenue) OVER () ELSE 0 END AS revenue_share,
  CASE WHEN s.gross_revenue > 0 THEN s.return_amount / s.gross_revenue ELSE 0 END AS return_rate
FROM segment_base AS s
ORDER BY s.segment_order;

-- ------------------------------------------------------------
-- 6.7 客户月度 cohort 留存
-- ------------------------------------------------------------
DROP TABLE IF EXISTS agg_cohort_retention;

CREATE TABLE agg_cohort_retention AS
WITH first_order AS (
  SELECT
    customer_key,
    CAST(DATE_FORMAT(first_order_date, '%Y-%m-01') AS DATE) AS cohort_month
  FROM dim_customer
  WHERE has_purchases = 1
),
activity AS (
  SELECT
    customer_key,
    CAST(DATE_FORMAT(invoice_datetime, '%Y-%m-01') AS DATE) AS activity_month,
    SUM(line_revenue) AS revenue,
    COUNT(DISTINCT invoice_no) AS orders
  FROM fact_sales
  WHERE is_product_sale = 1
    AND customer_key <> 0
  GROUP BY
    customer_key,
    CAST(DATE_FORMAT(invoice_datetime, '%Y-%m-01') AS DATE)
),
cohort_activity AS (
  SELECT
    f.cohort_month,
    TIMESTAMPDIFF(MONTH, f.cohort_month, a.activity_month) AS period_index,
    a.activity_month,
    COUNT(DISTINCT a.customer_key) AS active_customers,
    SUM(a.revenue) AS revenue,
    SUM(a.orders) AS orders
  FROM first_order AS f
  JOIN activity AS a
    ON a.customer_key = f.customer_key
  GROUP BY
    f.cohort_month,
    a.activity_month,
    TIMESTAMPDIFF(MONTH, f.cohort_month, a.activity_month)
),
cohort_size AS (
  SELECT
    cohort_month,
    COUNT(*) AS cohort_customers
  FROM first_order
  GROUP BY cohort_month
)
SELECT
  c.cohort_month,
  c.period_index,
  c.activity_month,
  s.cohort_customers,
  c.active_customers,
  c.active_customers / s.cohort_customers AS retention_rate,
  c.revenue,
  c.orders,
  CASE WHEN c.activity_month = '2011-12-01' THEN 1 ELSE 0 END AS is_partial_activity_month
FROM cohort_activity AS c
JOIN cohort_size AS s
  ON s.cohort_month = c.cohort_month
ORDER BY c.cohort_month, c.period_index;

-- ------------------------------------------------------------
-- 6.8 星期 × 小时
-- 说明：这里的“小时”是发票/订单录入时间，不是用户浏览时间。
-- ------------------------------------------------------------
DROP TABLE IF EXISTS agg_weekday_hour;

CREATE TABLE agg_weekday_hour AS
WITH time_base AS (
  SELECT
    f.day_of_week,
    f.day_name,
    f.order_hour,
    SUM(f.line_revenue) AS gross_revenue,
    COUNT(DISTINCT f.invoice_no) AS orders,
    COUNT(DISTINCT CASE WHEN f.is_customer_sale = 1 THEN f.customer_key END) AS customers,
    SUM(f.quantity) AS units
  FROM fact_sales AS f
  WHERE f.is_product_sale = 1
  GROUP BY f.day_of_week, f.day_name, f.order_hour
)
SELECT
  t.*,
  CASE WHEN t.day_of_week >= 6 THEN 'Weekend' ELSE 'Weekday' END AS day_type,
  CASE WHEN SUM(t.gross_revenue) OVER () > 0
       THEN t.gross_revenue / SUM(t.gross_revenue) OVER () ELSE 0 END AS revenue_share
FROM time_base AS t;

-- ------------------------------------------------------------
-- 6.9 退货月度与商品退货
-- ------------------------------------------------------------
DROP TABLE IF EXISTS agg_returns_monthly;

CREATE TABLE agg_returns_monthly AS
WITH return_base AS (
  SELECT
    d.month_key,
    COUNT(DISTINCT CASE WHEN f.is_cancellation = 1 AND f.is_product = 1 THEN f.invoice_no END) AS return_invoices,
    SUM(CASE WHEN f.is_cancellation = 1 AND f.is_product = 1 THEN 1 ELSE 0 END) AS return_lines,
    ABS(SUM(CASE WHEN f.is_cancellation = 1 AND f.is_product = 1 THEN f.quantity ELSE 0 END)) AS return_units,
    ABS(SUM(CASE WHEN f.is_cancellation = 1 AND f.is_product = 1 THEN f.line_revenue ELSE 0 END)) AS return_amount,
    SUM(CASE WHEN f.is_product_sale = 1 THEN f.line_revenue ELSE 0 END) AS gross_revenue,
    COUNT(DISTINCT CASE WHEN f.is_product_sale = 1 THEN f.invoice_no END) AS orders
  FROM fact_sales AS f
  JOIN dim_date AS d
    ON d.date_key = f.date_key
  GROUP BY d.month_key
)
SELECT
  r.*,
  r.gross_revenue - r.return_amount AS net_revenue,
  CASE WHEN r.gross_revenue > 0 THEN r.return_amount / r.gross_revenue ELSE 0 END AS return_rate,
  CASE WHEN r.orders > 0 THEN r.return_invoices / r.orders ELSE 0 END AS return_invoice_rate,
  CASE WHEN r.return_invoices > 0 THEN r.return_amount / r.return_invoices ELSE 0 END AS avg_return_value
FROM return_base AS r;

DROP TABLE IF EXISTS agg_returns_product;

CREATE TABLE agg_returns_product AS
WITH return_lines AS (
  SELECT
    stock_code,
    COUNT(DISTINCT CASE WHEN is_cancellation = 1 AND is_product = 1 THEN invoice_no END) AS return_invoices,
    SUM(CASE WHEN is_cancellation = 1 AND is_product = 1 THEN 1 ELSE 0 END) AS return_lines,
    ABS(SUM(CASE WHEN is_cancellation = 1 AND is_product = 1 THEN quantity ELSE 0 END)) AS return_units,
    ABS(SUM(CASE WHEN is_cancellation = 1 AND is_product = 1 THEN line_revenue ELSE 0 END)) AS return_amount
  FROM fact_sales
  WHERE is_product = 1
  GROUP BY stock_code
)
SELECT
  p.stock_code,
  p.description,
  p.category,
  p.gross_revenue,
  p.net_revenue,
  p.return_amount,
  r.return_invoices,
  r.return_lines,
  r.return_units,
  CASE WHEN p.gross_revenue > 0 THEN p.return_amount / p.gross_revenue ELSE 0 END AS return_rate,
  CASE WHEN p.net_revenue <= 0 AND p.gross_revenue > 0 THEN 1 ELSE 0 END AS full_return_flag,
  RANK() OVER (ORDER BY p.return_amount DESC) AS return_rank
FROM dim_product AS p
JOIN return_lines AS r
  ON r.stock_code = p.stock_code
WHERE p.has_sales = 1
  AND r.return_amount > 0;

-- ------------------------------------------------------------
-- 6.10 订单级汇总（用于客单价分布和订单结构分析）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS agg_order_summary;

CREATE TABLE agg_order_summary AS
WITH order_base AS (
  SELECT
    f.invoice_no,
    MIN(f.invoice_datetime) AS order_datetime,
    MIN(f.date_key) AS date_key,
    MAX(f.customer_key) AS customer_key,
    MAX(f.country) AS country,
    COUNT(*) AS line_count,
    SUM(f.quantity) AS units,
    SUM(f.line_revenue) AS gross_revenue,
    CASE WHEN MAX(f.is_customer_sale) = 1 THEN 1 ELSE 0 END AS is_customer_order,
    HOUR(MIN(f.invoice_datetime)) AS order_hour,
    WEEKDAY(MIN(f.invoice_datetime)) + 1 AS day_of_week
  FROM fact_sales AS f
  WHERE f.is_product_sale = 1
  GROUP BY f.invoice_no
)
SELECT
  o.*,
  CASE
    WHEN o.gross_revenue < 100 THEN '<£100'
    WHEN o.gross_revenue < 250 THEN '£100-250'
    WHEN o.gross_revenue < 500 THEN '£250-500'
    WHEN o.gross_revenue < 1000 THEN '£500-1k'
    WHEN o.gross_revenue < 5000 THEN '£1k-5k'
    ELSE '£5k+'
  END AS order_value_band
FROM order_base AS o;

ALTER TABLE agg_order_summary
  ADD PRIMARY KEY (invoice_no);

-- ------------------------------------------------------------
-- 6.11 单行经营总览（Power BI 卡片和 PPT 数字来源）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS agg_kpi_overview;

CREATE TABLE agg_kpi_overview AS
WITH ordered_orders AS (
  SELECT
    gross_revenue,
    ROW_NUMBER() OVER (ORDER BY gross_revenue, invoice_no) AS rn,
    COUNT(*) OVER () AS cnt
  FROM agg_order_summary
)
SELECT
  (SELECT ROUND(SUM(line_revenue), 2) FROM fact_sales WHERE is_product_sale = 1) AS total_gross_revenue,
  (SELECT ROUND(ABS(SUM(line_revenue)), 2) FROM fact_sales WHERE is_cancellation = 1 AND is_product = 1) AS total_return_amount,
  (SELECT ROUND(
      SUM(CASE WHEN is_product_sale = 1 THEN line_revenue ELSE 0 END)
      - ABS(SUM(CASE WHEN is_cancellation = 1 AND is_product = 1 THEN line_revenue ELSE 0 END)),
      2)
   FROM fact_sales) AS total_net_revenue,
  (SELECT COUNT(DISTINCT invoice_no) FROM fact_sales WHERE is_product_sale = 1) AS total_orders,
  (SELECT COUNT(*) FROM dim_customer WHERE has_purchases = 1) AS total_customers,
  (SELECT COUNT(*) FROM dim_product WHERE has_sales = 1) AS active_products,
  (SELECT ROUND(SUM(CASE WHEN is_product_sale = 1 THEN quantity ELSE 0 END), 0) FROM fact_sales) AS total_units,
  (SELECT ROUND(
      SUM(CASE WHEN is_product_sale = 1 THEN line_revenue ELSE 0 END)
      / NULLIF(COUNT(DISTINCT CASE WHEN is_product_sale = 1 THEN invoice_no END), 0),
      2)
   FROM fact_sales) AS overall_aov,
  (SELECT ROUND(
      SUM(CASE WHEN orders >= 2 THEN 1 ELSE 0 END)
      / NULLIF(SUM(CASE WHEN orders >= 1 THEN 1 ELSE 0 END), 0),
      4)
   FROM dim_customer WHERE has_purchases = 1) AS repeat_purchase_rate,
  (SELECT ROUND(
      ABS(SUM(CASE WHEN is_cancellation = 1 AND is_product = 1 THEN line_revenue ELSE 0 END))
      / NULLIF(SUM(CASE WHEN is_product_sale = 1 THEN line_revenue ELSE 0 END), 0),
      4)
   FROM fact_sales) AS overall_return_rate,
  (SELECT ROUND(
      SUM(CASE WHEN is_product_sale = 1 AND country <> 'United Kingdom' THEN line_revenue ELSE 0 END)
      / NULLIF(SUM(CASE WHEN is_product_sale = 1 THEN line_revenue ELSE 0 END), 0),
      4)
   FROM fact_sales) AS international_revenue_share,
  (SELECT ROUND(
      SUM(CASE WHEN value_decile = 1 THEN net_revenue ELSE 0 END)
      / NULLIF(SUM(net_revenue), 0),
      4)
   FROM agg_customer_summary) AS top10pct_customer_revenue_share,
  (SELECT ROUND(
      SUM(CASE WHEN top20_flag = 1 THEN GREATEST(net_revenue, 0) ELSE 0 END)
      / NULLIF(SUM(GREATEST(net_revenue, 0)), 0),
      4)
   FROM agg_product_summary) AS top20_product_revenue_share,
  (SELECT category FROM agg_category_summary ORDER BY net_revenue DESC LIMIT 1) AS top_category,
  (SELECT net_revenue FROM agg_category_summary ORDER BY net_revenue DESC LIMIT 1) AS top_category_net_revenue,
  (SELECT description FROM agg_product_summary ORDER BY net_revenue DESC LIMIT 1) AS top_product,
  (SELECT net_revenue FROM agg_product_summary ORDER BY net_revenue DESC LIMIT 1) AS top_product_net_revenue,
  (SELECT country FROM agg_country_summary WHERE country <> 'United Kingdom' ORDER BY net_revenue DESC LIMIT 1) AS top_international_country,
  (SELECT ROUND(AVG(gross_revenue), 2)
   FROM ordered_orders
   WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2))) AS median_order_value,
  (SELECT gross_revenue
   FROM ordered_orders
   WHERE rn = CEIL(cnt * 0.90)
   LIMIT 1) AS p90_order_value,
  (SELECT COUNT(*) FROM dim_product
   WHERE has_sales = 1 AND gross_revenue > 0 AND net_revenue <= 0) AS full_return_products,
  (SELECT ROUND(SUM(gross_revenue), 2) FROM dim_product
   WHERE has_sales = 1 AND gross_revenue > 0 AND net_revenue <= 0) AS full_return_gross_revenue,
  (SELECT MIN(DATE(invoice_datetime)) FROM fact_sales) AS date_min,
  (SELECT MAX(DATE(invoice_datetime)) FROM fact_sales) AS date_max,
  (SELECT COUNT(*) FROM agg_monthly_kpi) AS active_months,
  (SELECT COUNT(*) FROM agg_monthly_kpi WHERE is_complete_month = 1) AS complete_months;

-- 输出关键数字，便于人工复核。
SELECT * FROM agg_kpi_overview;

