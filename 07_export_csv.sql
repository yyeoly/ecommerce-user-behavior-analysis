-- ============================================================
-- 第 7 层：导出 CSV
-- 输出目录必须在 MySQL 的 secure_file_priv 之下。
-- 本机示例：work/mysql-exports/final
-- 每个文件第一行是字段名，编码 UTF-8，逗号分隔，字段用双引号包裹。
-- 若目录不存在或被占用，请修改路径后重新执行。
-- ============================================================

USE retail_ops;
SET NAMES utf8mb4;

-- 7.1 全量清洗明细（保留质量标记）
SELECT
  'line_id','source_row_id','invoice_no','stock_code','description','quantity',
  'invoice_datetime','unit_price','customer_id','country','line_revenue',
  'invoice_type','is_cancellation','is_product','is_missing_customer',
  'has_zero_price','has_negative_price','is_duplicate','is_valid_sale',
  'is_product_sale','is_customer_sale','quality_note'
UNION ALL
SELECT
  CAST(line_id AS CHAR), CAST(source_row_id AS CHAR), invoice_no, stock_code, description,
  CAST(quantity AS CHAR), DATE_FORMAT(invoice_datetime, '%Y-%m-%d %H:%i:%s'),
  CAST(unit_price AS CHAR), IFNULL(CAST(customer_id AS CHAR), ''), country,
  CAST(line_revenue AS CHAR), invoice_type, CAST(is_cancellation AS CHAR),
  CAST(is_product AS CHAR), CAST(is_missing_customer AS CHAR),
  CAST(has_zero_price AS CHAR), CAST(has_negative_price AS CHAR),
  CAST(is_duplicate AS CHAR), CAST(is_valid_sale AS CHAR),
  CAST(is_product_sale AS CHAR), CAST(is_customer_sale AS CHAR),
  IFNULL(quality_note, '')
FROM clean_transactions
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/clean_transactions.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7.2 只保留商品销售的分析底表
SELECT
  'line_id','invoice_no','stock_code','description','quantity','invoice_datetime',
  'unit_price','customer_id','country','line_revenue','is_customer_sale'
UNION ALL
SELECT
  CAST(line_id AS CHAR), invoice_no, stock_code, description, CAST(quantity AS CHAR),
  DATE_FORMAT(invoice_datetime, '%Y-%m-%d %H:%i:%s'), CAST(unit_price AS CHAR),
  IFNULL(CAST(customer_id AS CHAR), ''), country, CAST(line_revenue AS CHAR),
  CAST(is_customer_sale AS CHAR)
FROM clean_transactions
WHERE is_product_sale = 1
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/sales_transactions.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7.3 退货明细
SELECT
  'line_id','invoice_no','stock_code','description','quantity','invoice_datetime',
  'unit_price','customer_id','country','line_revenue'
UNION ALL
SELECT
  CAST(line_id AS CHAR), invoice_no, stock_code, description, CAST(quantity AS CHAR),
  DATE_FORMAT(invoice_datetime, '%Y-%m-%d %H:%i:%s'), CAST(unit_price AS CHAR),
  IFNULL(CAST(customer_id AS CHAR), ''), country, CAST(line_revenue AS CHAR)
FROM clean_transactions
WHERE is_cancellation = 1 AND is_product = 1
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/returns_transactions.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7.4 被排除的分析行（便于审计）
SELECT
  'line_id','invoice_no','stock_code','description','quantity','invoice_datetime',
  'unit_price','customer_id','country','line_revenue','quality_note'
UNION ALL
SELECT
  CAST(line_id AS CHAR), invoice_no, stock_code, description, CAST(quantity AS CHAR),
  DATE_FORMAT(invoice_datetime, '%Y-%m-%d %H:%i:%s'), CAST(unit_price AS CHAR),
  IFNULL(CAST(customer_id AS CHAR), ''), country, CAST(line_revenue AS CHAR),
  IFNULL(quality_note, '')
FROM clean_transactions
WHERE is_product_sale = 0 AND is_cancellation = 0
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/excluded_transactions.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7.5 星型模型：事实表
SELECT
  'line_id','invoice_no','date_key','invoice_datetime','customer_key','stock_code',
  'country_key','country','quantity','unit_price','line_revenue','invoice_type',
  'is_cancellation','is_product','is_valid_sale','is_product_sale',
  'is_customer_sale','is_missing_customer','is_duplicate','has_zero_price',
  'has_negative_price','order_hour','day_of_week','day_name'
UNION ALL
SELECT
  CAST(line_id AS CHAR), invoice_no, CAST(date_key AS CHAR),
  DATE_FORMAT(invoice_datetime, '%Y-%m-%d %H:%i:%s'), CAST(customer_key AS CHAR),
  stock_code, CAST(country_key AS CHAR), country, CAST(quantity AS CHAR),
  CAST(unit_price AS CHAR), CAST(line_revenue AS CHAR), invoice_type,
  CAST(is_cancellation AS CHAR), CAST(is_product AS CHAR), CAST(is_valid_sale AS CHAR),
  CAST(is_product_sale AS CHAR), CAST(is_customer_sale AS CHAR),
  CAST(is_missing_customer AS CHAR), CAST(is_duplicate AS CHAR),
  CAST(has_zero_price AS CHAR), CAST(has_negative_price AS CHAR),
  CAST(order_hour AS CHAR), CAST(day_of_week AS CHAR), day_name
FROM fact_sales
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/fact_sales.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7.6 星型模型：客户维度
SELECT
  'customer_key','customer_id','country','first_order_date','last_order_date',
  'orders','units','gross_revenue','return_amount','net_revenue','aov',
  'recency_days','r_score','f_score','m_score','segment','segment_order','has_purchases'
UNION ALL
SELECT
  CAST(customer_key AS CHAR), IFNULL(CAST(customer_id AS CHAR), ''), country,
  IFNULL(DATE_FORMAT(first_order_date, '%Y-%m-%d'), ''),
  IFNULL(DATE_FORMAT(last_order_date, '%Y-%m-%d'), ''),
  CAST(orders AS CHAR), CAST(units AS CHAR), CAST(gross_revenue AS CHAR),
  CAST(return_amount AS CHAR), CAST(net_revenue AS CHAR), CAST(aov AS CHAR),
  IFNULL(CAST(recency_days AS CHAR), ''), CAST(r_score AS CHAR),
  CAST(f_score AS CHAR), CAST(m_score AS CHAR), segment, CAST(segment_order AS CHAR),
  CAST(has_purchases AS CHAR)
FROM dim_customer
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/dim_customer.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7.7 星型模型：商品维度
SELECT
  'stock_code','description','category','first_sale_date','last_sale_date',
  'units_sold','gross_revenue','net_revenue','net_units','orders','customers',
  'return_units','return_amount','return_rate','avg_selling_price',
  'gross_revenue_share','net_revenue_share','cumulative_net_share',
  'abc_class','has_sales'
UNION ALL
SELECT
  stock_code, description, category,
  IFNULL(DATE_FORMAT(first_sale_date, '%Y-%m-%d'), ''),
  IFNULL(DATE_FORMAT(last_sale_date, '%Y-%m-%d'), ''),
  CAST(units_sold AS CHAR), CAST(gross_revenue AS CHAR), CAST(net_revenue AS CHAR),
  CAST(net_units AS CHAR), CAST(orders AS CHAR), CAST(customers AS CHAR),
  CAST(return_units AS CHAR), CAST(return_amount AS CHAR), CAST(return_rate AS CHAR),
  CAST(avg_selling_price AS CHAR), CAST(gross_revenue_share AS CHAR),
  CAST(net_revenue_share AS CHAR), CAST(cumulative_net_share AS CHAR),
  abc_class, CAST(has_sales AS CHAR)
FROM dim_product
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/dim_product.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7.8 星型模型：日期维度
SELECT
  'date_key','full_date','year_number','quarter_number','month_number',
  'month_name','month_key','day_of_week','day_name','is_weekend','is_complete_month'
UNION ALL
SELECT
  CAST(date_key AS CHAR), DATE_FORMAT(full_date, '%Y-%m-%d'),
  CAST(year_number AS CHAR), CAST(quarter_number AS CHAR), CAST(month_number AS CHAR),
  month_name, month_key, CAST(day_of_week AS CHAR), day_name,
  CAST(is_weekend AS CHAR), CAST(is_complete_month AS CHAR)
FROM dim_date
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/dim_date.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7.9 星型模型：国家维度
SELECT 'country_key','country'
UNION ALL
SELECT CAST(country_key AS CHAR), country
FROM dim_country
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/dim_country.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7.10 经营总览
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

-- 7.11 月度 KPI
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

-- 7.12 国家汇总
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

-- 7.13 商品汇总
SELECT
  'stock_code','description','category','first_sale_date','last_sale_date',
  'units_sold','gross_revenue','net_revenue','net_units','orders','customers',
  'return_units','return_amount','return_rate','avg_selling_price',
  'gross_revenue_share','net_revenue_share','cumulative_net_share','abc_class',
  'has_sales','revenue_rank','top20_flag','unit_share','is_net_positive'
UNION ALL
SELECT
  stock_code, description, category,
  IFNULL(DATE_FORMAT(first_sale_date, '%Y-%m-%d'), ''),
  IFNULL(DATE_FORMAT(last_sale_date, '%Y-%m-%d'), ''),
  CAST(units_sold AS CHAR), CAST(gross_revenue AS CHAR), CAST(net_revenue AS CHAR),
  CAST(net_units AS CHAR), CAST(orders AS CHAR), CAST(customers AS CHAR),
  CAST(return_units AS CHAR), CAST(return_amount AS CHAR), CAST(return_rate AS CHAR),
  CAST(avg_selling_price AS CHAR), CAST(gross_revenue_share AS CHAR),
  CAST(net_revenue_share AS CHAR), CAST(cumulative_net_share AS CHAR), abc_class,
  CAST(has_sales AS CHAR), CAST(revenue_rank AS CHAR), CAST(top20_flag AS CHAR),
  CAST(unit_share AS CHAR), CAST(is_net_positive AS CHAR)
FROM agg_product_summary
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/agg_product_summary.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7.14 类目汇总
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

-- 7.15 客户汇总
SELECT
  'customer_key','customer_id','country','first_order_date','last_order_date',
  'orders','units','gross_revenue','return_amount','net_revenue','aov',
  'recency_days','r_score','f_score','m_score','segment','segment_order',
  'has_purchases','revenue_rank','value_decile','is_top20pct'
UNION ALL
SELECT
  CAST(customer_key AS CHAR), CAST(customer_id AS CHAR), country,
  DATE_FORMAT(first_order_date, '%Y-%m-%d'), DATE_FORMAT(last_order_date, '%Y-%m-%d'),
  CAST(orders AS CHAR), CAST(units AS CHAR), CAST(gross_revenue AS CHAR),
  CAST(return_amount AS CHAR), CAST(net_revenue AS CHAR), CAST(aov AS CHAR),
  CAST(recency_days AS CHAR), CAST(r_score AS CHAR), CAST(f_score AS CHAR),
  CAST(m_score AS CHAR), segment, CAST(segment_order AS CHAR),
  CAST(has_purchases AS CHAR), CAST(revenue_rank AS CHAR),
  CAST(value_decile AS CHAR), CAST(is_top20pct AS CHAR)
FROM agg_customer_summary
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/agg_customer_summary.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7.16 RFM 分层汇总
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

-- 7.17 Cohort 留存
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

-- 7.18 星期 × 小时
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

-- 7.19 退货月度
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

-- 7.20 商品退货
SELECT
  'stock_code','description','category','gross_revenue','net_revenue',
  'return_amount','return_invoices','return_lines','return_units','return_rate',
  'full_return_flag','return_rank'
UNION ALL
SELECT
  stock_code, description, category, CAST(gross_revenue AS CHAR),
  CAST(net_revenue AS CHAR), CAST(return_amount AS CHAR),
  CAST(return_invoices AS CHAR), CAST(return_lines AS CHAR),
  CAST(return_units AS CHAR), CAST(return_rate AS CHAR),
  CAST(full_return_flag AS CHAR), CAST(return_rank AS CHAR)
FROM agg_returns_product
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/agg_returns_product.csv'
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n';

-- 7.21 订单级汇总
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

-- 7.22 数据质量审计
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

SELECT 'CSV export completed' AS status;

