-- ============================================================
--  dim_date — Static Date Dimension
--  SCD Type: Static (never changes)
--  Grain   : One row per unique order date
--  Source  : staging.stg_orders
-- ============================================================

DROP TABLE IF EXISTS warehouse.dim_date;

CREATE TABLE warehouse.dim_date AS
SELECT
    TO_CHAR(full_date, 'YYYYMMDD')::int AS date_id,
    full_date,
    EXTRACT(YEAR FROM full_date)::int AS year,
    EXTRACT(MONTH FROM full_date)::int AS month,
    TRIM(TO_CHAR(full_date, 'Month')) AS month_name,
    EXTRACT(QUARTER FROM full_date)::int AS quarter,
    EXTRACT(DOW FROM full_date)::int AS day_of_week,
    TRIM(TO_CHAR(full_date, 'Day')) AS day_name
FROM GENERATE_SERIES(
    (SELECT MIN(order_date_dateorders::date)
     FROM staging.stg_orders
     WHERE order_date_dateorders IS NOT NULL),
    (SELECT MAX(order_date_dateorders::date)
     FROM staging.stg_orders
     WHERE order_date_dateorders IS NOT NULL),
    INTERVAL '1 day'
) AS dates(full_date);

ALTER TABLE warehouse.dim_date
ADD PRIMARY KEY (date_id);

-- Sanity check
SELECT COUNT(*) AS dim_date_rows FROM warehouse.dim_date;
