-- ============================================================
--  dim_date — Static Date Dimension
--  SCD Type: Static (never changes)
--  Grain   : One row per unique order date
--  Source  : staging.stg_orders
-- ============================================================

DROP TABLE IF EXISTS warehouse.dim_date;

CREATE TABLE warehouse.dim_date AS
SELECT DISTINCT
    TO_CHAR(order_date_dateorders::date, 'YYYYMMDD')::int   AS date_id,
    order_date_dateorders::date                              AS full_date,
    EXTRACT(YEAR    FROM order_date_dateorders::date)::int   AS year,
    EXTRACT(MONTH   FROM order_date_dateorders::date)::int   AS month,
    TO_CHAR(order_date_dateorders::date, 'Month')            AS month_name,
    EXTRACT(QUARTER FROM order_date_dateorders::date)::int   AS quarter,
    EXTRACT(DOW     FROM order_date_dateorders::date)::int   AS day_of_week,
    TO_CHAR(order_date_dateorders::date, 'Day')              AS day_name
FROM staging.stg_orders
WHERE order_date_dateorders IS NOT NULL;

ALTER TABLE warehouse.dim_date ADD PRIMARY KEY (date_id);

-- Sanity check
SELECT COUNT(*) AS dim_date_rows FROM warehouse.dim_date;
