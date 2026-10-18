-- ============================================================
-- 第 6b 层：Power BI 专用聚合表
-- 运行前提：已经执行 06_aggregates.sql
-- 作用：把手工看板需要的 Top 商品、Top 退货、订单金额带
--       也变成 MySQL 表，保证所有 Power BI CSV 都可由 SQL 生成。
-- ============================================================

USE retail_ops;

-- ------------------------------------------------------------
-- 6b.1 Top 20 商品（按净销售额）
-- 字段与 Power BI 手动搭建步骤一致。
-- ------------------------------------------------------------
DROP TABLE IF EXISTS agg_top_products;

CREATE TABLE agg_top_products AS
SELECT
  stock_code,
  description,
  category,
  net_revenue,
  gross_revenue,
  return_amount,
  return_rate,
  orders,
  customers,
  abc_class,
  revenue_rank
FROM agg_product_summary
WHERE is_net_positive = 1
ORDER BY net_revenue DESC, stock_code
LIMIT 20;

ALTER TABLE agg_top_products
  ADD PRIMARY KEY (stock_code);

-- ------------------------------------------------------------
-- 6b.2 退货金额 Top 10
-- ------------------------------------------------------------
DROP TABLE IF EXISTS agg_top_returns;

CREATE TABLE agg_top_returns AS
SELECT
  stock_code,
  description,
  category,
  gross_revenue,
  net_revenue,
  return_amount,
  return_rate,
  full_return_flag
FROM agg_returns_product
ORDER BY return_amount DESC, stock_code
LIMIT 10;

ALTER TABLE agg_top_returns
  ADD PRIMARY KEY (stock_code);

-- ------------------------------------------------------------
-- 6b.3 订单金额带
-- 口径：按订单毛销售额分带，统计订单数、收入、订单占比、收入占比。
-- ------------------------------------------------------------
DROP TABLE IF EXISTS agg_order_value_bands;

CREATE TABLE agg_order_value_bands AS
WITH order_band_base AS (
  SELECT
    CASE
      WHEN gross_revenue < 100 THEN '<£100'
      WHEN gross_revenue < 250 THEN '£100-250'
      WHEN gross_revenue < 500 THEN '£250-500'
      WHEN gross_revenue < 1000 THEN '£500-1k'
      WHEN gross_revenue < 5000 THEN '£1k-5k'
      ELSE '£5k+'
    END AS order_value_band,
    COUNT(*) AS orders,
    SUM(gross_revenue) AS revenue
  FROM agg_order_summary
  GROUP BY
    CASE
      WHEN gross_revenue < 100 THEN '<£100'
      WHEN gross_revenue < 250 THEN '£100-250'
      WHEN gross_revenue < 500 THEN '£250-500'
      WHEN gross_revenue < 1000 THEN '£500-1k'
      WHEN gross_revenue < 5000 THEN '£1k-5k'
      ELSE '£5k+'
    END
)
SELECT
  order_value_band,
  orders,
  revenue,
  orders / SUM(orders) OVER () AS order_share,
  revenue / SUM(revenue) OVER () AS revenue_share
FROM order_band_base;

-- 质量检查
SELECT
  (SELECT COUNT(*) FROM agg_top_products) AS top_products,
  (SELECT COUNT(*) FROM agg_top_returns) AS top_returns,
  (SELECT COUNT(*) FROM agg_order_value_bands) AS order_bands,
  (SELECT ROUND(SUM(revenue), 2) FROM agg_order_value_bands) AS band_revenue,
  (SELECT ROUND(SUM(gross_revenue), 2) FROM agg_order_summary) AS order_revenue;

