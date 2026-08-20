-- ============================================================
--  fact_orders — Central Fact Table
--  Grain   : One row per order line item (order_item_id)
--  Source  : staging.stg_orders + all dimension tables
--
--  JOIN STRATEGY:
--  INNER JOIN on dim_customer and dim_product — every fact row
--  MUST have a customer and product. Missing = data quality issue.
--
--  LEFT JOIN on dim_geography and dim_shipping — enrichment
--  dimensions. If no match found, FK is NULL but the fact row
--  is still retained. Revenue and profit are not lost.
--
--  ON CONFLICT DO NOTHING — safety net against duplicate
--  order_item_id values. Should not trigger if diagnosis
--  check passed, but prevents pipeline failure if it does.
--
--  ALWAYS run the diagnosis check in 00_diagnosis_check.sql
--  BEFORE running this script. If diagnosis returns any rows
--  fix the dimension causing duplicates first.
-- ============================================================

-- Step 1: Add performance indexes on staging before the join
CREATE INDEX IF NOT EXISTS idx_stg_customer
    ON staging.stg_orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_stg_product
    ON staging.stg_orders(product_card_id);
CREATE INDEX IF NOT EXISTS idx_stg_date
    ON staging.stg_orders(order_date_dateorders);
CREATE INDEX IF NOT EXISTS idx_stg_city
    ON staging.stg_orders(order_city, order_country, order_region);
CREATE INDEX IF NOT EXISTS idx_stg_shipping
    ON staging.stg_orders(shipping_mode, delivery_status,
       days_for_shipment_scheduled, days_for_shipping_real);
CREATE INDEX IF NOT EXISTS idx_cust_sk
    ON warehouse.dim_customer(customer_id);
CREATE INDEX IF NOT EXISTS idx_prod_sk
    ON warehouse.dim_product(product_id);

-- Step 2: Create the fact table
DROP TABLE IF EXISTS warehouse.fact_orders;

CREATE TABLE warehouse.fact_orders (
    order_item_id      INT PRIMARY KEY,
    order_id           INT,
    customer_sk        INT REFERENCES warehouse.dim_customer(customer_sk),
    product_sk         INT REFERENCES warehouse.dim_product(product_sk),
    date_id            INT REFERENCES warehouse.dim_date(date_id),
    geography_id       INT REFERENCES warehouse.dim_geography(geography_id),
    shipping_id        INT REFERENCES warehouse.dim_shipping(shipping_id),
    quantity           INT,
    unit_price         NUMERIC(10,2),
    discount_amount    NUMERIC(10,2),
    discount_rate      NUMERIC(6,4),
    line_total         NUMERIC(12,2),
    sales              NUMERIC(12,2),
    benefit            NUMERIC(12,2),
    profit             NUMERIC(12,2),
    profit_ratio       NUMERIC(6,4),
    late_delivery_risk INT,
    order_status       VARCHAR(50),
    payment_type       VARCHAR(50)
);

-- Step 3: Populate the fact table
INSERT INTO warehouse.fact_orders
SELECT
    o.order_item_id,
    o.order_id,
    c.customer_sk,
    p.product_sk,
    TO_CHAR(o.order_date_dateorders::date, 'YYYYMMDD')::int,
    g.geography_id,
    s.shipping_id,
    o.order_item_quantity,
    o.order_item_product_price,
    o.order_item_discount,
    o.order_item_discount_rate,
    o.order_item_total,
    o.sales,
    o.benefit_per_order,
    o.order_profit_per_order,
    o.order_item_profit_ratio,
    o.late_delivery_risk,
    o.order_status,
    o.type
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
ON CONFLICT (order_item_id) DO NOTHING;

-- Step 4: Add indexes on fact table for fast analytical joins
CREATE INDEX idx_fact_customer  ON warehouse.fact_orders(customer_sk);
CREATE INDEX idx_fact_product   ON warehouse.fact_orders(product_sk);
CREATE INDEX idx_fact_date      ON warehouse.fact_orders(date_id);
CREATE INDEX idx_fact_geography ON warehouse.fact_orders(geography_id);
CREATE INDEX idx_fact_shipping  ON warehouse.fact_orders(shipping_id);

-- Step 5: Sanity checks
SELECT COUNT(*) AS fact_orders_rows FROM warehouse.fact_orders;

-- Must return 0 — no orphaned rows
SELECT COUNT(*) AS orphaned_rows
FROM warehouse.fact_orders
WHERE customer_sk IS NULL OR product_sk IS NULL;

-- Year distribution — confirm all years loaded
SELECT
    d.year,
    COUNT(*) AS orders
FROM warehouse.fact_orders f
JOIN warehouse.dim_date d ON f.date_id = d.date_id
GROUP BY d.year
ORDER BY d.year;
