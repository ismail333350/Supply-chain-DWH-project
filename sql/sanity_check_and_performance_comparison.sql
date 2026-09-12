-- ============================================================
--  FULL SANITY CHECK
--  Run after the entire pipeline completes to confirm
--  everything loaded correctly.
-- ============================================================

-- 1. Row counts across all tables
SELECT 'staging.stg_orders'       AS table_name, COUNT(*) AS rows FROM staging.stg_orders
UNION ALL SELECT 'warehouse.dim_customer',  COUNT(*) FROM warehouse.dim_customer
UNION ALL SELECT 'warehouse.dim_product',   COUNT(*) FROM warehouse.dim_product
UNION ALL SELECT 'warehouse.dim_date',      COUNT(*) FROM warehouse.dim_date
UNION ALL SELECT 'warehouse.dim_geography', COUNT(*) FROM warehouse.dim_geography
UNION ALL SELECT 'warehouse.dim_shipping',  COUNT(*) FROM warehouse.dim_shipping
UNION ALL SELECT 'warehouse.fact_orders',   COUNT(*) FROM warehouse.fact_orders
ORDER BY table_name;

-- 2. Orphan check — must return 0
SELECT COUNT(*) AS orphaned_rows
FROM warehouse.fact_orders
WHERE customer_sk IS NULL OR product_sk IS NULL;

-- 3. Duplicate customer check — must return 0 rows
SELECT customer_id, COUNT(*) AS versions
FROM warehouse.dim_customer
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- 4. Duplicate product check — must return 0 rows
SELECT product_id, COUNT(*) AS versions
FROM warehouse.dim_product
GROUP BY product_id
HAVING COUNT(*) > 1;

-- 5. Geography uniqueness check — must return 0 rows
SELECT order_city, order_country, order_region, COUNT(*)
FROM warehouse.dim_geography
GROUP BY order_city, order_country, order_region
HAVING COUNT(*) > 1;

-- 6. Year distribution — confirm all years loaded
SELECT
    d.year,
    COUNT(*) AS orders,
    ROUND(SUM(f.sales), 0)  AS total_revenue,
    ROUND(SUM(f.profit), 0) AS total_profit
FROM warehouse.fact_orders f
JOIN warehouse.dim_date d ON f.date_id = d.date_id
GROUP BY d.year
ORDER BY d.year;

-- 7. Top 5 categories by profit
SELECT category_name, total_profit, avg_margin_pct
FROM marts.mart_product_profitability
ORDER BY total_profit DESC
LIMIT 5;

-- 8. Late delivery rate by shipping mode
SELECT
    shipping_mode,
    SUM(total_orders)   AS total_orders,
    SUM(late_orders)    AS late_orders,
    ROUND(AVG(late_rate_pct), 1) AS late_rate_pct,
    ROUND(AVG(avg_delay_days), 2) AS avg_delay
FROM marts.mart_delivery_performance
GROUP BY shipping_mode
ORDER BY late_rate_pct DESC;


--  QUERY PERFORMANCE COMPARISON
--  Before Dimensional Modeling vs After Dimensional Modeling
--  DataCo Supply Chain DWH — PostgreSQL

-- Version A execution plan
-- Look for: Seq Scan on stg_orders — reads all 180,518 rows
EXPLAIN (ANALYZE, FORMAT TEXT)
WITH market_segment AS (
    SELECT
        market,
        EXTRACT(YEAR FROM order_date_dateorders::date)::int AS year,
        customer_segment,
        ROUND(SUM(sales::numeric), 2)                       AS revenue,
        ROUND(AVG(late_delivery_risk::numeric)*100, 1)      AS late_rate_pct
    FROM staging.stg_orders
    WHERE order_date_dateorders IS NOT NULL
    GROUP BY market,
             EXTRACT(YEAR FROM order_date_dateorders::date),
             customer_segment
)
SELECT * FROM market_segment ORDER BY year, market, revenue DESC;



-- Version B execution plan
-- Look for: Index Scan — jumps directly to matching rows
EXPLAIN (ANALYZE, FORMAT TEXT)
WITH market_segment AS (
    SELECT
        g.market,
        d.year,
        c.segment                                      AS customer_segment,
        ROUND(SUM(f.sales), 2)                         AS revenue,
        ROUND(AVG(f.late_delivery_risk::numeric)*100,1) AS late_rate_pct
    FROM warehouse.fact_orders f
    JOIN warehouse.dim_date      d ON f.date_id      = d.date_id
    JOIN warehouse.dim_geography g ON f.geography_id = g.geography_id
    JOIN warehouse.dim_customer  c ON f.customer_sk  = c.customer_sk
    GROUP BY g.market, d.year, c.segment
)
SELECT * FROM market_segment ORDER BY year, market, revenue DESC;
