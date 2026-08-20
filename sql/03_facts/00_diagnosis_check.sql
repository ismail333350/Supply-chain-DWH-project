-- ============================================================
--  DIAGNOSIS CHECK — Run BEFORE fact_orders.sql
--  This query must return ZERO rows before you proceed
--  to load the fact table.
--
--  If it returns rows it means one or more dimensions are
--  producing multiple matches for the same staging row.
--  The match_count column tells you how many duplicates
--  that order item would produce in the fact table.
--
--  Fix the offending dimension before loading facts.
--  A single duplicate dimension row causes thousands of
--  duplicate fact rows — fact load will fail with a
--  primary key violation.
-- ============================================================

SELECT
    o.order_item_id,
    COUNT(*) AS match_count
FROM staging.stg_orders o
JOIN warehouse.dim_customer c
    ON c.customer_id = o.customer_id
JOIN warehouse.dim_product p
    ON p.product_id  = o.product_card_id
LEFT JOIN warehouse.dim_geography g
    ON  g.order_city    = o.order_city
    AND g.order_country = o.order_country
    AND g.order_region  = o.order_region
LEFT JOIN warehouse.dim_shipping s
    ON  s.shipping_mode               = o.shipping_mode
    AND s.delivery_status             = o.delivery_status
    AND s.days_for_shipment_scheduled = o.days_for_shipment_scheduled
    AND s.days_for_shipping_real      = o.days_for_shipping_real
GROUP BY o.order_item_id
HAVING COUNT(*) > 1
ORDER BY match_count DESC
LIMIT 10;

-- ── If the above returns rows use this to find which dimension ──
-- Uncomment and run each block separately to isolate the culprit

/*
-- Test geography
SELECT order_city, order_country, order_region, COUNT(*) AS rows
FROM warehouse.dim_geography
GROUP BY order_city, order_country, order_region
HAVING COUNT(*) > 1
ORDER BY rows DESC LIMIT 10;

-- Test shipping
SELECT shipping_mode, delivery_status,
       days_for_shipment_scheduled, days_for_shipping_real,
       COUNT(*) AS rows
FROM warehouse.dim_shipping
GROUP BY shipping_mode, delivery_status,
         days_for_shipment_scheduled, days_for_shipping_real
HAVING COUNT(*) > 1
ORDER BY rows DESC LIMIT 10;

-- Test customer
SELECT customer_id, COUNT(*) AS rows
FROM warehouse.dim_customer
GROUP BY customer_id
HAVING COUNT(*) > 1
ORDER BY rows DESC LIMIT 10;

-- Test product
SELECT product_id, COUNT(*) AS rows
FROM warehouse.dim_product
GROUP BY product_id
HAVING COUNT(*) > 1
ORDER BY rows DESC LIMIT 10;
*/
