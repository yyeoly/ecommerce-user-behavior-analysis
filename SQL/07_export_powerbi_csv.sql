-- ============================================================
-- Power BI 专用 CSV 导出
-- 运行前提：
--   1. 已执行 06_aggregates.sql；
--   2. 已执行 06b_powerbi_aggregates.sql；
--   3. 输出目录是 MySQL 的 secure_file_priv 目录。
--
-- 默认输出目录：
--   C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/
-- 如果你的 secure_file_priv 不是这个目录，请整体替换下面的路径。
-- ============================================================

USE retail_ops;
SET NAMES utf8mb4;

-- 7b.1 经营总览
SELECT
  'total_gross_revenue','total_return_amount','total_net_revenue','total_orders',
  'total_customers','active_products','total_units','overall_aov',
  'repeat_purchase_rate','overall_return_rate','international_revenue_share',
  'top10pct_customer_revenue_share','top20_product_revenue_share','top_category',
  'top_category_net_revenue','top_product','top_product_net_revenue',
  'top_international_country','median_order_value','p90_order_value',
  'full_return_products','full_return_gross_revenue','date_min','date_max',
  'active_months','complete_months'
UNION ALL
SELECT
  CAST(total_gross_revenue AS CHAR), CAST(total_return_amount AS CHAR),
  CAST(total_net_revenue AS CHAR), CAST(total_orders AS CHAR),
  CAST(total_customers AS CHAR), CAST(active_products AS CHAR),
  CAST(total_units AS CHAR), CAST(overall_aov AS CHAR),
  CAST(repeat_purchase_rate AS CHAR), CAST(overall_return_rate AS CHAR),
  CAST(international_revenue_share AS CHAR),
  CAST(top10pct_customer_revenue_share AS CHAR),
  CAST(top20_product_revenue_share AS CHAR), top_category,
  CAST(top_category_net_revenue AS CHAR), top_product,
  CAST(top_product_net_revenue AS CHAR), top_international_country,
  CAST(median_order_value AS CHAR), CAST(p90_order_value AS CHAR),
  CAST(full_return_products AS CHAR), CAST(full_return_gross_revenue AS CHAR),
  DATE_FORMAT(date_min, '%Y-%m-%d'), DATE_FORMAT(date_max, '%Y-%m-%d'),
  CAST(active_months AS CHAR), CAST(complete_months AS CHAR)
FROM agg_kpi_overview
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/agg_kpi_overview.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7b.2 月度 KPI
SELECT
  'month_key','month_start','month_name','is_complete_month','gross_revenue',
  'return_amount','orders','active_customers','units','international_revenue',
  'net_revenue','new_customers','returning_customers','aov_gross','aov_net',
  'return_rate','international_share','avg_basket_units','prev_gross_revenue',
  'revenue_growth_pct','order_growth_pct'
UNION ALL
SELECT
  month_key, DATE_FORMAT(month_start, '%Y-%m-%d'), month_name,
  CAST(is_complete_month AS CHAR), CAST(gross_revenue AS CHAR),
  CAST(return_amount AS CHAR), CAST(orders AS CHAR), CAST(active_customers AS CHAR),
  CAST(units AS CHAR), CAST(international_revenue AS CHAR), CAST(net_revenue AS CHAR),
  CAST(new_customers AS CHAR), CAST(returning_customers AS CHAR),
  CAST(aov_gross AS CHAR), CAST(aov_net AS CHAR), CAST(return_rate AS CHAR),
  CAST(international_share AS CHAR), CAST(avg_basket_units AS CHAR),
  IFNULL(CAST(prev_gross_revenue AS CHAR), ''),
  IFNULL(CAST(revenue_growth_pct AS CHAR), ''),
  IFNULL(CAST(order_growth_pct AS CHAR), '')
FROM agg_monthly_kpi
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/agg_monthly_kpi.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7b.3 类目汇总
SELECT
  'category','products','units_sold','gross_revenue','return_amount','net_revenue',
  'product_order_links','product_customer_links','return_rate','avg_unit_price',
  'gross_revenue_share','net_revenue_share','revenue_rank'
UNION ALL
SELECT
  category, CAST(products AS CHAR), CAST(units_sold AS CHAR),
  CAST(gross_revenue AS CHAR), CAST(return_amount AS CHAR),
  CAST(net_revenue AS CHAR), CAST(product_order_links AS CHAR),
  CAST(product_customer_links AS CHAR), CAST(return_rate AS CHAR),
  CAST(avg_unit_price AS CHAR), CAST(gross_revenue_share AS CHAR),
  CAST(net_revenue_share AS CHAR), CAST(revenue_rank AS CHAR)
FROM agg_category_summary
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/agg_category_summary.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7b.4 国家/地区汇总
SELECT
  'country','gross_revenue','return_amount','orders','customers','units',
  'net_revenue','aov','return_rate','revenue_per_customer','orders_per_customer',
  'country_type','revenue_share','customer_share','revenue_rank'
UNION ALL
SELECT
  country, CAST(gross_revenue AS CHAR), CAST(return_amount AS CHAR),
  CAST(orders AS CHAR), CAST(customers AS CHAR), CAST(units AS CHAR),
  CAST(net_revenue AS CHAR), CAST(aov AS CHAR), CAST(return_rate AS CHAR),
  CAST(revenue_per_customer AS CHAR), CAST(orders_per_customer AS CHAR),
  country_type, CAST(revenue_share AS CHAR), CAST(customer_share AS CHAR),
  CAST(revenue_rank AS CHAR)
FROM agg_country_summary
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/agg_country_summary.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7b.5 订单金额带
SELECT
  order_value_band,
  orders,
  revenue,
  order_share,
  revenue_share
FROM (
  SELECT
    'order_value_band' AS order_value_band,
    'orders' AS orders,
    'revenue' AS revenue,
    'order_share' AS order_share,
    'revenue_share' AS revenue_share,
    0 AS sort_key
  UNION ALL
  SELECT
    order_value_band,
    CAST(orders AS CHAR),
    CAST(revenue AS CHAR),
    CAST(order_share AS CHAR),
    CAST(revenue_share AS CHAR),
    CASE order_value_band
      WHEN '<£100' THEN 1
      WHEN '£100-250' THEN 2
      WHEN '£250-500' THEN 3
      WHEN '£500-1k' THEN 4
      WHEN '£1k-5k' THEN 5
      WHEN '£5k+' THEN 6
      ELSE 99
    END
  FROM agg_order_value_bands
) AS ordered_bands
ORDER BY sort_key
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/agg_order_value_bands.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7b.6 Top 20 商品
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
FROM (
  SELECT
    'stock_code' AS stock_code,
    'description' AS description,
    'category' AS category,
    'net_revenue' AS net_revenue,
    'gross_revenue' AS gross_revenue,
    'return_amount' AS return_amount,
    'return_rate' AS return_rate,
    'orders' AS orders,
    'customers' AS customers,
    'abc_class' AS abc_class,
    'revenue_rank' AS revenue_rank,
    999999999 AS sort_key
  UNION ALL
  SELECT
    stock_code,
    description,
    category,
    CAST(net_revenue AS CHAR),
    CAST(gross_revenue AS CHAR),
    CAST(return_amount AS CHAR),
    CAST(return_rate AS CHAR),
    CAST(orders AS CHAR),
    CAST(customers AS CHAR),
    abc_class,
    CAST(revenue_rank AS CHAR),
    net_revenue
  FROM agg_top_products
) AS ordered_products
ORDER BY sort_key DESC
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/agg_top_products.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7b.7 Top 10 退货商品
SELECT
  stock_code,
  description,
  category,
  gross_revenue,
  net_revenue,
  return_amount,
  return_rate,
  full_return_flag
FROM (
  SELECT
    'stock_code' AS stock_code,
    'description' AS description,
    'category' AS category,
    'gross_revenue' AS gross_revenue,
    'net_revenue' AS net_revenue,
    'return_amount' AS return_amount,
    'return_rate' AS return_rate,
    'full_return_flag' AS full_return_flag,
    999999999 AS sort_key
  UNION ALL
  SELECT
    stock_code,
    description,
    category,
    CAST(gross_revenue AS CHAR),
    CAST(net_revenue AS CHAR),
    CAST(return_amount AS CHAR),
    CAST(return_rate AS CHAR),
    CAST(full_return_flag AS CHAR),
    return_amount
  FROM agg_top_returns
) AS ordered_returns
ORDER BY sort_key DESC
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/agg_top_returns.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7b.8 RFM 分层
SELECT
  'segment','segment_order','customers','net_revenue','gross_revenue',
  'return_amount','avg_orders','avg_recency_days','avg_customer_value',
  'avg_order_value','customer_share','revenue_share','return_rate'
UNION ALL
SELECT
  segment, CAST(segment_order AS CHAR), CAST(customers AS CHAR),
  CAST(net_revenue AS CHAR), CAST(gross_revenue AS CHAR),
  CAST(return_amount AS CHAR), CAST(avg_orders AS CHAR),
  CAST(avg_recency_days AS CHAR), CAST(avg_customer_value AS CHAR),
  CAST(avg_order_value AS CHAR), CAST(customer_share AS CHAR),
  CAST(revenue_share AS CHAR), CAST(return_rate AS CHAR)
FROM agg_rfm_segments
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/agg_rfm_segments.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7b.9 Cohort 留存
SELECT
  'cohort_month','period_index','activity_month','cohort_customers',
  'active_customers','retention_rate','revenue','orders','is_partial_activity_month'
UNION ALL
SELECT
  DATE_FORMAT(cohort_month, '%Y-%m-%d'), CAST(period_index AS CHAR),
  DATE_FORMAT(activity_month, '%Y-%m-%d'), CAST(cohort_customers AS CHAR),
  CAST(active_customers AS CHAR), CAST(retention_rate AS CHAR),
  CAST(revenue AS CHAR), CAST(orders AS CHAR),
  CAST(is_partial_activity_month AS CHAR)
FROM agg_cohort_retention
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/agg_cohort_retention.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7b.10 星期 × 小时
SELECT
  'day_of_week','day_name','order_hour','gross_revenue','orders','customers',
  'units','day_type','revenue_share'
UNION ALL
SELECT
  CAST(day_of_week AS CHAR), day_name, CAST(order_hour AS CHAR),
  CAST(gross_revenue AS CHAR), CAST(orders AS CHAR), CAST(customers AS CHAR),
  CAST(units AS CHAR), day_type, CAST(revenue_share AS CHAR)
FROM agg_weekday_hour
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/agg_weekday_hour.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7b.11 退货月度
SELECT
  'month_key','return_invoices','return_lines','return_units','return_amount',
  'gross_revenue','orders','net_revenue','return_rate','return_invoice_rate',
  'avg_return_value'
UNION ALL
SELECT
  month_key, CAST(return_invoices AS CHAR), CAST(return_lines AS CHAR),
  CAST(return_units AS CHAR), CAST(return_amount AS CHAR),
  CAST(gross_revenue AS CHAR), CAST(orders AS CHAR), CAST(net_revenue AS CHAR),
  CAST(return_rate AS CHAR), CAST(return_invoice_rate AS CHAR),
  CAST(avg_return_value AS CHAR)
FROM agg_returns_monthly
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/agg_returns_monthly.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7b.12 订单级汇总（可选，用于更细的订单分析）
SELECT
  'invoice_no','order_datetime','date_key','customer_key','country','line_count',
  'units','gross_revenue','is_customer_order','order_hour','day_of_week',
  'order_value_band'
UNION ALL
SELECT
  invoice_no, DATE_FORMAT(order_datetime, '%Y-%m-%d %H:%i:%s'),
  CAST(date_key AS CHAR), CAST(customer_key AS CHAR), country,
  CAST(line_count AS CHAR), CAST(units AS CHAR), CAST(gross_revenue AS CHAR),
  CAST(is_customer_order AS CHAR), CAST(order_hour AS CHAR),
  CAST(day_of_week AS CHAR), order_value_band
FROM agg_order_summary
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/agg_order_summary.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7b.13 数据质量审计
SELECT
  'metric_order','metric','metric_value','pct_of_raw','treatment','business_impact'
UNION ALL
SELECT
  CAST(metric_order AS CHAR), metric, CAST(metric_value AS CHAR),
  CAST(pct_of_raw AS CHAR), treatment, business_impact
FROM data_quality_audit
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/data_quality_audit.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

SELECT 'Power BI CSV export completed' AS status;

