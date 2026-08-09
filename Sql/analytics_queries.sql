-- ============================================================================
-- SQL Script: Advanced Retail Analytics Queries
-- Purpose: Practical Spark SQL queries using CTEs, Window Functions, and
--          aggregations to resolve core retail questions.
-- Catalog: workspace  |  Schemas: retail_gold, retail_silver
-- Run in: Databricks SQL Editor (attach to your Serverless SQL Warehouse)
-- ============================================================================
 
USE CATALOG workspace;
 
-- 1. Correlation between Delivery Performance and Customer Review Scores
-- Question: Does late delivery directly affect the review scores left by customers?
WITH delivery_groups AS (
  SELECT
    order_id,
    review_score,
    actual_delivery_time_days,
    delivery_delay_days,
    CASE
      WHEN delivery_delay_days <= 0 THEN 'On-Time / Early'
      WHEN delivery_delay_days BETWEEN 1 AND 3 THEN '1-3 Days Late'
      WHEN delivery_delay_days BETWEEN 4 AND 7 THEN '4-7 Days Late'
      ELSE 'More than a Week Late'
    END AS delivery_status
  FROM retail_gold.FactSales
  WHERE order_status = 'delivered' AND review_score IS NOT NULL
)
SELECT
  delivery_status,
  COUNT(DISTINCT order_id) AS total_orders,
  ROUND(AVG(review_score), 2) AS average_review_score,
  ROUND(AVG(actual_delivery_time_days), 1) AS average_transit_days
FROM delivery_groups
GROUP BY delivery_status
ORDER BY average_review_score DESC;
 
 
-- 2. Top Performing Product Category in Each State
-- Question: What product category generates the highest revenue in each customer state?
WITH state_category_revenue AS (
  SELECT
    c.state AS customer_state,
    p.category_name_english AS product_category,
    SUM(f.price) AS total_revenue,
    ROW_NUMBER() OVER (PARTITION BY c.state ORDER BY SUM(f.price) DESC) AS rank_in_state
  FROM retail_gold.FactSales f
  JOIN retail_gold.DimCustomer c ON f.customer_key = c.customer_key
  JOIN retail_gold.DimProduct p ON f.product_key = p.product_key
  WHERE p.category_name_english IS NOT NULL
  GROUP BY c.state, p.category_name_english
)
SELECT
  customer_state,
  product_category,
  ROUND(total_revenue, 2) AS state_revenue
FROM state_category_revenue
WHERE rank_in_state = 1
ORDER BY state_revenue DESC;
 
 
-- 3. Customer Lifetime Value (CLV) Deciles
-- Question: What is the distribution of total spend across customer deciles?
WITH customer_spending AS (
  SELECT
    c.customer_unique_id,
    SUM(f.price + f.freight_value) AS total_spend,
    NTILE(10) OVER (ORDER BY SUM(f.price + f.freight_value) DESC) AS spending_decile
  FROM retail_gold.FactSales f
  JOIN retail_gold.DimCustomer c ON f.customer_key = c.customer_key
  GROUP BY c.customer_unique_id
)
SELECT
  spending_decile,
  COUNT(1) AS customer_count,
  ROUND(SUM(total_spend), 2) AS decile_revenue,
  ROUND(AVG(total_spend), 2) AS average_spend_per_customer
FROM customer_spending
GROUP BY spending_decile
ORDER BY spending_decile ASC;
 
 
-- 4. Order Status Breakdown
-- Question: What share of orders fall into each status (delivered, canceled, shipped, etc.),
-- and what revenue value is tied to each?
SELECT
  order_status,
  COUNT(DISTINCT order_id) AS total_orders,
  ROUND(SUM(price), 2) AS value_at_stake,
  ROUND((COUNT(DISTINCT order_id) / SUM(COUNT(DISTINCT order_id)) OVER ()) * 100, 2) AS pct_of_total_orders
FROM retail_gold.FactSales
GROUP BY order_status
ORDER BY total_orders DESC;
 
 
-- 5. Payment Types Popularity and Average Installments
-- Question: How do customers pay for orders, and how many installments do they select?
-- (Reads from the Silver layer directly, since payment_type/installments aren't modeled into Gold)
SELECT
  payment_type,
  COUNT(DISTINCT order_id) AS transaction_count,
  ROUND(SUM(payment_value), 2) AS total_payment_amount,
  ROUND(AVG(payment_installments), 1) AS average_installments,
  ROUND((SUM(payment_value) / SUM(SUM(payment_value)) OVER ()) * 100, 2) AS revenue_share_pct
FROM retail_silver.order_payments
GROUP BY payment_type
ORDER BY total_payment_amount DESC;
 
 
-- 6. Pipeline Health Check (new — matches this project's logging/quarantine design)
-- Question: How did the last 7 automated runs behave, and did anything get quarantined?
SELECT
  layer,
  task_name,
  status,
  message,
  rows_affected,
  log_timestamp
FROM retail_ops.pipeline_logs
WHERE log_timestamp >= current_timestamp() - INTERVAL 7 DAYS
ORDER BY log_timestamp DESC;
 