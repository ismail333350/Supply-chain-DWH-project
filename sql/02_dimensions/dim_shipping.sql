-- ============================================================
--  dim_shipping — Shipping Dimension
--  SCD Type: SCD1 (drop and recreate on every run)
--  Grain   : One row per unique shipping combination
--  Source  : staging.stg_orders
--
--  Includes computed column delay_days:
--  delay_days = days_for_shipping_real - days_for_shipment_scheduled
--  Positive = late, Zero = on time, Negative = early
-- ============================================================

DROP TABLE IF EXISTS warehouse.dim_shipping;

CREATE TABLE warehouse.dim_shipping AS
SELECT
    ROW_NUMBER() OVER () AS shipping_id,
    shipping_mode,
    delivery_status,
    days_for_shipment_scheduled,
    days_for_shipping_real,
    (days_for_shipping_real - days_for_shipment_scheduled) AS delay_days
FROM (
    SELECT DISTINCT
        shipping_mode,
        delivery_status,
        days_for_shipment_scheduled,
        days_for_shipping_real
    FROM staging.stg_orders
) sub;

ALTER TABLE warehouse.dim_shipping ADD PRIMARY KEY (shipping_id);

-- Sanity check
SELECT COUNT(*) AS dim_shipping_rows FROM warehouse.dim_shipping;
SELECT * FROM warehouse.dim_shipping ORDER BY shipping_mode, delay_days;
