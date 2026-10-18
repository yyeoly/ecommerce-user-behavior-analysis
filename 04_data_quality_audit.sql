-- ============================================================
-- 第 4 层：数据质量审计表
-- 这张表既用于项目报告，也用于向业务方解释“为什么要这样清洗”。
-- 注意：一行可能同时触发多个问题，因此各问题数量不能直接相加。
-- ============================================================

USE retail_ops;

DROP TABLE IF EXISTS data_quality_audit;

CREATE TABLE data_quality_audit AS
SELECT 1 AS metric_order, '原始行数' AS metric,
       COUNT(*) AS metric_value,
       100.00 AS pct_of_raw,
       '保留在 Staging 层' AS treatment,
       '作为全量审计基线' AS business_impact
FROM stg_online_retail
UNION ALL
SELECT 2, '重复行（额外出现次数）',
       SUM(is_duplicate),
       ROUND(100 * SUM(is_duplicate) / COUNT(*), 2),
       '仅保留首次出现',
       '避免重复计入销售额和销量'
FROM clean_transactions
UNION ALL
SELECT 3, '缺失客户ID',
       SUM(is_missing_customer),
       ROUND(100 * SUM(is_missing_customer) / COUNT(*), 2),
       '保留交易，客户分析时单独排除',
       '仍可用于总销售额，但不能归属到具体客户'
FROM clean_transactions
UNION ALL
SELECT 4, '取消/退货发票行',
       SUM(is_cancellation),
       ROUND(100 * SUM(is_cancellation) / COUNT(*), 2),
       '保留为负向流水，单独计算退货',
       '净销售额与退货率分析的基础'
FROM clean_transactions
UNION ALL
SELECT 5, '商品退货行',
       SUM(CASE WHEN is_cancellation = 1 AND is_product = 1 THEN 1 ELSE 0 END),
       ROUND(100 * SUM(CASE WHEN is_cancellation = 1 AND is_product = 1 THEN 1 ELSE 0 END) / COUNT(*), 2),
       '保留为负向商品流水',
       '用于商品退货率和净销售额'
FROM clean_transactions
UNION ALL
SELECT 6, '零价行',
       SUM(has_zero_price),
       ROUND(100 * SUM(has_zero_price) / COUNT(*), 2),
       '不进入销售额',
       '多为赠品、样品或系统占位记录'
FROM clean_transactions
UNION ALL
SELECT 7, '负价行',
       SUM(has_negative_price),
       ROUND(100 * SUM(has_negative_price) / COUNT(*), 2),
       '不进入销售额',
       '属于坏账调整，不能代表商品价格'
FROM clean_transactions
UNION ALL
SELECT 8, '非商品/服务行',
       SUM(CASE WHEN is_product = 0 THEN 1 ELSE 0 END),
       ROUND(100 * SUM(CASE WHEN is_product = 0 THEN 1 ELSE 0 END) / COUNT(*), 2),
       '保留收入审计，商品分析时排除',
       '邮费、手续费、折扣、礼品券等会扭曲商品结构'
FROM clean_transactions
UNION ALL
SELECT 9, '原始缺失描述',
       SUM(CASE WHEN description_raw IS NULL OR TRIM(description_raw) = '' THEN 1 ELSE 0 END),
       ROUND(100 * SUM(CASE WHEN description_raw IS NULL OR TRIM(description_raw) = '' THEN 1 ELSE 0 END) / COUNT(*), 2),
       '用同编码最常见描述补全',
       '保留商品可读性，仍保留 UNKNOWN PRODUCT 作为兜底'
FROM stg_online_retail
UNION ALL
SELECT 10, '仍无描述的商品行',
       SUM(CASE WHEN description = 'UNKNOWN PRODUCT' THEN 1 ELSE 0 END),
       ROUND(100 * SUM(CASE WHEN description = 'UNKNOWN PRODUCT' THEN 1 ELSE 0 END) / COUNT(*), 2),
       '保留并标记为 UNKNOWN PRODUCT',
       '不影响金额计算，但影响商品名称展示'
FROM clean_transactions
UNION ALL
SELECT 11, '有效商品销售行',
       SUM(is_product_sale),
       ROUND(100 * SUM(is_product_sale) / COUNT(*), 2),
       '进入销售额、订单和商品分析',
       '核心分析样本'
FROM clean_transactions
UNION ALL
SELECT 12, '可归属客户的商品销售行',
       SUM(is_customer_sale),
       ROUND(100 * SUM(is_customer_sale) / COUNT(*), 2),
       '进入客户、RFM、复购和 cohort 分析',
       '客户分析的样本边界'
FROM clean_transactions
UNION ALL
SELECT 13, '匿名商品销售行',
       SUM(CASE WHEN is_product_sale = 1 AND customer_id IS NULL THEN 1 ELSE 0 END),
       ROUND(100 * SUM(CASE WHEN is_product_sale = 1 AND customer_id IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2),
       '进入总销售额，不进入客户分析',
       '客户指标不能代表全部交易'
FROM clean_transactions
UNION ALL
SELECT 14, '同一发票多个时间戳的发票数',
       COUNT(*),
       ROUND(100 * COUNT(*) / (SELECT COUNT(DISTINCT invoice_no) FROM clean_transactions), 2),
       '保留，发票级分析使用 MIN/MAX 时间',
       '通常为分次录入，不视为脏数据'
FROM (
  SELECT invoice_no
  FROM clean_transactions
  GROUP BY invoice_no
  HAVING COUNT(DISTINCT invoice_datetime) > 1
) AS multi_time_invoices
UNION ALL
SELECT 15, '商品销售总额（GBP）',
       ROUND(SUM(CASE WHEN is_product_sale = 1 THEN line_revenue ELSE 0 END), 2),
       100.00,
       '作为毛销售额口径',
       '不含邮费、手续费、折扣和退货'
FROM clean_transactions
UNION ALL
SELECT 16, '商品退货金额（GBP，绝对值）',
       ROUND(ABS(SUM(CASE WHEN is_cancellation = 1 AND is_product = 1 THEN line_revenue ELSE 0 END)), 2),
       ROUND(
         100 * ABS(SUM(CASE WHEN is_cancellation = 1 AND is_product = 1 THEN line_revenue ELSE 0 END))
         / NULLIF(SUM(CASE WHEN is_product_sale = 1 THEN line_revenue ELSE 0 END), 0),
         2
       ),
       '从毛销售额中扣减',
       '退货率 = 退货金额 / 毛销售额'
FROM clean_transactions
UNION ALL
SELECT 17, '净商品销售额（GBP）',
       ROUND(
         SUM(CASE WHEN is_product_sale = 1 THEN line_revenue ELSE 0 END)
         + SUM(CASE WHEN is_cancellation = 1 AND is_product = 1 THEN line_revenue ELSE 0 END),
         2
       ),
       100.00,
       '毛销售额 - 退货金额',
       '用于经营结果和月度趋势'
FROM clean_transactions
UNION ALL
SELECT 18, '商品销售订单数',
       COUNT(DISTINCT CASE WHEN is_product_sale = 1 THEN invoice_no END),
       100.00,
       '按非取消发票去重',
       '订单数不使用行数，避免一单多行被重复计数'
FROM clean_transactions
UNION ALL
SELECT 19, '可识别客户数',
       COUNT(DISTINCT CASE WHEN is_customer_sale = 1 THEN customer_id END),
       100.00,
       '仅统计有商品购买且客户ID非空',
       '客户分析的有效样本'
FROM clean_transactions;

SELECT * FROM data_quality_audit ORDER BY metric_order;

