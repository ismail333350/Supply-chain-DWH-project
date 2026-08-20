-- ============================================================
--  Data Marts — Materialized Views
--  Run AFTER fact_orders.sql completes successfully
--
--  Materialized views store pre-computed aggregation results
--  on disk. Analytical queries and Power BI reports run in
--  milliseconds instead of scanning 180,518 fact rows.
--
--  IMPORTANT: Run REFRESH commands after every pipeline run
--  to update the marts with the latest data.
-- ============================================================

-- Drop existing marts if they exist
DROP MATERIALIZED VIEW IF EXISTS marts.mart_delivery_performance;
DROP MATERIALIZED VIEW IF EXISTS marts.mart_product_profitability;
DROP MATERIALIZED VIEW IF EXISTS marts.mart_monthly_revenue;

-- ── Mart 1: Delivery Performance ──────────────────────────────
-- Business question:
-- Which markets and shipping modes have the highest late
-- delivery rates and longest average delays?

CREATE MATERIALIZED VIEW marts.mart_delivery_performance AS
SELECT
    g.market,
    g.order_region,
    s.shipping_mode,
    s.delivery_status,
    COUNT(*)                                            AS total_orders,
    SUM(f.late_delivery_risk)                           AS late_orders,
    ROUND(AVG(f.late_delivery_risk::numeric) * 100, 1)  AS late_rate_pct,
    ROUND(AVG(s.delay_days), 2)                         AS avg_delay_days,
    ROUND(MIN(s.delay_days), 0)                         AS min_delay_days,
    ROUND(MAX(s.delay_days), 0)                         AS max_delay_days
FROM warehouse.fact_orders f
JOIN warehouse.dim_geography g ON f.geography_id = g.geography_id
JOIN warehouse.dim_shipping  s ON f.shipping_id  = s.shipping_id
GROUP BY
    g.market,
    g.order_region,
    s.shipping_mode,
    s.delivery_status;

-- ── Mart 2: Product Profitability ─────────────────────────────
-- Business question:
-- Which product categories and departments generate the most
-- profit, revenue, and best margin?

CREATE MATERIALIZED VIEW marts.mart_product_profitability AS
SELECT
    p.department_name,
    p.category_name,
    COUNT(*)                            AS total_orders,
    SUM(f.quantity)                     AS total_units_sold,
    ROUND(SUM(f.sales), 2)              AS total_revenue,
    ROUND(SUM(f.profit), 2)             AS total_profit,
    ROUND(AVG(f.profit), 2)             AS avg_profit_per_order,
    ROUND(AVG(f.profit_ratio) * 100, 1) AS avg_margin_pct,
    ROUND(AVG(f.discount_rate) * 100, 1)AS avg_discount_pct
FROM warehouse.fact_orders f
JOIN warehouse.dim_product p ON f.product_sk = p.product_sk
GROUP BY
    p.department_name,
    p.category_name
ORDER BY total_profit DESC;

-- ── Mart 3: Monthly Revenue ───────────────────────────────────
-- Business question:
-- What is the month-over-month revenue and profit trend
-- for each market?

CREATE MATERIALIZED VIEW marts.mart_monthly_revenue AS
SELECT
    d.year,
    d.month,
    TRIM(d.month_name)                    AS month_name,
    d.quarter,
    g.market,
    COUNT(DISTINCT f.order_id)            AS total_orders,
    COUNT(*)                              AS total_line_items,
    ROUND(SUM(f.sales), 2)                AS total_revenue,
    ROUND(SUM(f.profit), 2)               AS total_profit,
    ROUND(AVG(f.profit_ratio) * 100, 1)   AS avg_margin_pct,
    ROUND(AVG(f.discount_rate) * 100, 1)  AS avg_discount_pct,
    SUM(f.late_delivery_risk)             AS late_deliveries
FROM warehouse.fact_orders f
JOIN warehouse.dim_date      d ON f.date_id      = d.date_id
JOIN warehouse.dim_geography g ON f.geography_id = g.geography_id
GROUP BY
    d.year,
    d.month,
    d.month_name,
    d.quarter,
    g.market
ORDER BY d.year, d.month;

-- ── Sanity checks ─────────────────────────────────────────────
SELECT 'mart_delivery_performance'  AS mart, COUNT(*) AS rows FROM marts.mart_delivery_performance
UNION ALL
SELECT 'mart_product_profitability' AS mart, COUNT(*) AS rows FROM marts.mart_product_profitability
UNION ALL
SELECT 'mart_monthly_revenue'       AS mart, COUNT(*) AS rows FROM marts.mart_monthly_revenue;

-- ── Refresh commands (run after every pipeline update) ────────
-- REFRESH MATERIALIZED VIEW marts.mart_delivery_performance;
-- REFRESH MATERIALIZED VIEW marts.mart_product_profitability;
-- REFRESH MATERIALIZED VIEW marts.mart_monthly_revenue;
