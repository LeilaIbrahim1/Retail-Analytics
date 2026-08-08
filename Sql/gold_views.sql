-- ============================================================================
-- SQL Script: Gold Layer Analytics Views
-- Purpose: Creates reusable Spark SQL views on top of the Gold dimensional
--          model for BI reporting (Databricks SQL & Power BI).
-- Database context is configured dynamically, but assumes the Gold database is active.
-- ============================================================================

-- 1. KPI Business Summary View
CREATE OR REPLACE VIEW v_kpi_summary AS
WITH order_stats AS (
  SELECT
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(DISTINCT customer_key) AS total_customers,
    SUM(price) AS total_revenue,
    SUM(price) / COUNT(DISTINCT order_id) AS avg_order_value,
    AVG(review_score) AS avg_review_score
  FROM FactSales
),
repeat_customers AS (
  -- Customers who have placed more than 1 distinct order
  SELECT COUNT(1) AS repeat_customer_count
  FROM (
    SELECT customer_key
    FROM FactSales
    GROUP BY customer_key
    HAVING COUNT(DISTINCT order_id) > 1
  )
)
SELECT 
  s.total_orders,
  s.total_customers,
  s.total_revenue,
  s.avg_order_value,
  s.avg_review_score,
  r.repeat_customer_count,
  (r.repeat_customer_count / s.total_customers) * 100 AS repeat_customer_rate_pct
FROM order_stats s
CROSS JOIN repeat_customers r;


-- 2. Delivery & Logistical Performance View
CREATE OR REPLACE VIEW v_delivery_kpis AS
SELECT
  order_status,
  COUNT(DISTINCT order_id) AS total_orders,
  AVG(actual_delivery_time_days) AS avg_delivery_time_days,
  AVG(estimated_delivery_time_days) AS avg_estimated_delivery_time_days,
  AVG(delivery_delay_days) AS avg_delivery_delay_days,
  -- Calculate percentage of orders delivered late
  (COUNT(CASE WHEN delivery_delay_days > 0 THEN 1 END) / COUNT(DISTINCT order_id)) * 100 AS late_delivery_rate_pct
FROM FactSales
WHERE order_status = 'delivered'
GROUP BY order_status;


-- 3. Monthly Sales and Order Trend View
CREATE OR REPLACE VIEW v_monthly_sales_trend AS
SELECT
  d.year,
  d.month,
  d.month_name,
  COUNT(DISTINCT f.order_id) AS total_orders,
  SUM(f.price) AS total_revenue,
  SUM(f.freight_value) AS total_freight,
  AVG(f.price) / COUNT(DISTINCT f.order_id) AS avg_order_value
FROM FactSales f
JOIN DimDate d ON f.order_purchase_date_key = d.date_key
GROUP BY d.year, d.month, d.month_name
ORDER BY d.year ASC, d.month ASC;


-- 4. Top Product Categories View
CREATE OR REPLACE VIEW v_top_product_categories AS
SELECT
  p.category_name_english AS product_category,
  COUNT(DISTINCT f.order_id) AS total_orders,
  SUM(f.price) AS total_revenue,
  AVG(f.review_score) AS avg_review_score,
  AVG(p.weight_g) AS avg_product_weight_g
FROM FactSales f
JOIN DimProduct p ON f.product_key = p.product_key
GROUP BY p.category_name_english
ORDER BY total_revenue DESC;


-- 5. Seller Performance and Geographic Breakdown View
CREATE OR REPLACE VIEW v_seller_performance AS
SELECT
  s.seller_id,
  s.city AS seller_city,
  s.state AS seller_state,
  COUNT(DISTINCT f.order_id) AS total_orders,
  SUM(f.price) AS total_revenue,
  AVG(f.review_score) AS avg_review_score,
  DENSE_RANK() OVER (ORDER BY SUM(f.price) DESC) as sales_rank
FROM FactSales f
JOIN DimSeller s ON f.seller_key = s.seller_key
GROUP BY s.seller_id, s.city, s.state;
