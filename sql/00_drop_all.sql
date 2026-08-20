-- ============================================================
--  DROP ALL — Clean Reset
--  Run this to wipe the entire warehouse and start fresh.
--  USE WITH CAUTION — this deletes all data.
-- ============================================================

-- Drop marts first (depend on fact and dims)
DROP MATERIALIZED VIEW IF EXISTS marts.mart_delivery_performance;
DROP MATERIALIZED VIEW IF EXISTS marts.mart_product_profitability;
DROP MATERIALIZED VIEW IF EXISTS marts.mart_monthly_revenue;

-- Drop fact table (depends on dims)
DROP TABLE IF EXISTS warehouse.fact_orders CASCADE;

-- Drop all dimension tables
DROP TABLE IF EXISTS warehouse.dim_customer  CASCADE;
DROP TABLE IF EXISTS warehouse.dim_product   CASCADE;
DROP TABLE IF EXISTS warehouse.dim_date      CASCADE;
DROP TABLE IF EXISTS warehouse.dim_geography CASCADE;
DROP TABLE IF EXISTS warehouse.dim_shipping  CASCADE;

-- Drop staging
DROP TABLE IF EXISTS staging.stg_orders CASCADE;

-- Confirm everything is gone
SELECT schemaname, tablename
FROM pg_tables
WHERE schemaname IN ('staging', 'warehouse', 'marts')
ORDER BY schemaname, tablename;
-- Should return zero rows
