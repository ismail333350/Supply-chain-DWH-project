-- ============================================================
--  dim_product — Product Dimension
--  SCD Type: SCD1 (latest value wins — no history tracking)
--  Grain   : One row per unique product
--  Source  : staging.stg_orders
--
--  DESIGN DECISION:
--  Uses ROW_NUMBER() OVER (PARTITION BY product_card_id ORDER BY
--  order_date_dateorders DESC) to guarantee exactly one row per
--  product regardless of price or category variations across orders.
--  Most recent record wins — reflects current product attributes.
-- ============================================================

DROP TABLE IF EXISTS warehouse.dim_product;

CREATE TABLE warehouse.dim_product (
    product_sk      SERIAL PRIMARY KEY,
    product_id      INT            NOT NULL UNIQUE,
    product_name    VARCHAR(200),
    category_name   VARCHAR(100),
    department_name VARCHAR(100),
    product_price   NUMERIC(10,2)
);

CREATE INDEX idx_dim_product_id ON warehouse.dim_product(product_id);

INSERT INTO warehouse.dim_product (
    product_id, product_name, category_name,
    department_name, product_price
)
SELECT
    product_id,
    product_name,
    category_name,
    department_name,
    product_price
FROM (
    SELECT
        product_card_id                   AS product_id,
        product_name,
        category_name,
        department_name,
        product_price,
        ROW_NUMBER() OVER (
            PARTITION BY product_card_id
            ORDER BY order_date_dateorders DESC    -- most recent record wins
        ) AS rn
    FROM staging.stg_orders
    WHERE product_card_id IS NOT NULL
) ranked
WHERE rn = 1;

-- Sanity check
SELECT COUNT(*) AS dim_product_rows FROM warehouse.dim_product;

-- Must return ZERO — no duplicate products allowed
SELECT product_id, COUNT(*) AS occurrences
FROM warehouse.dim_product
GROUP BY product_id
HAVING COUNT(*) > 1;
