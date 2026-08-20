-- ============================================================
--  dim_geography — Geography Dimension
--  SCD Type: SCD1 (drop and recreate on every run)
--  Grain   : One row per unique city/country/region combination
--  Source  : staging.stg_orders
--
--  CRITICAL DESIGN DECISION:
--  GROUP BY on join key columns ONLY (order_city, order_country,
--  order_region). Do NOT include latitude/longitude in GROUP BY —
--  float precision variations cause a fan trap that multiplies
--  fact rows by hundreds. Use AVG() for coordinates instead.
-- ============================================================

DROP TABLE IF EXISTS warehouse.dim_geography;

CREATE TABLE warehouse.dim_geography AS
SELECT
    ROW_NUMBER() OVER (
        ORDER BY order_country, order_region, order_city
    )                                   AS geography_id,
    order_city,
    MIN(order_state)                    AS order_state,
    order_country,
    order_region,
    MIN(market)                         AS market,
    ROUND(AVG(latitude)::numeric,  4)   AS latitude,
    ROUND(AVG(longitude)::numeric, 4)   AS longitude
FROM staging.stg_orders
WHERE order_city    IS NOT NULL
  AND order_country IS NOT NULL
  AND order_region  IS NOT NULL
GROUP BY
    order_city,
    order_country,
    order_region;

ALTER TABLE warehouse.dim_geography ADD PRIMARY KEY (geography_id);

CREATE INDEX idx_geo_lookup
    ON warehouse.dim_geography(order_city, order_country, order_region);

-- Sanity check — must return ZERO rows
-- If this returns rows the fan trap is still present
SELECT
    order_city,
    order_country,
    order_region,
    COUNT(*) AS duplicate_count
FROM warehouse.dim_geography
GROUP BY order_city, order_country, order_region
HAVING COUNT(*) > 1;

SELECT COUNT(*) AS dim_geography_rows FROM warehouse.dim_geography;
