-- ============================================================
--  dim_customer — Customer Dimension
--  SCD Type: SCD1 (latest value wins — no history tracking)
--  Grain   : One row per unique customer
--  Source  : staging.stg_orders
--
--  DESIGN DECISION:
--  I Used ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY
--  order_date_dateorders DESC) instead of DISTINCT to guarantee
--  exactly one row per customer_id.
--
--  DISTINCT does not work here because customer_zipcode is 86%
--  NULL — the same customer appears with a zipcode on some orders
--  and NULL on others, producing multiple DISTINCT rows for the
--  same customer. ROW_NUMBER picks the most recent record only.
-- ============================================================

DROP TABLE IF EXISTS warehouse.dim_customer;

CREATE TABLE warehouse.dim_customer (
    customer_sk     SERIAL PRIMARY KEY,
    customer_id     INT          NOT NULL UNIQUE,
    customer_name   VARCHAR(200),
    segment         VARCHAR(100),
    city            VARCHAR(100),
    state           VARCHAR(100),
    country         VARCHAR(100),
    zipcode         VARCHAR(20)
);

CREATE INDEX idx_dim_customer_id ON warehouse.dim_customer(customer_id);

INSERT INTO warehouse.dim_customer (
    customer_id, customer_name, segment,
    city, state, country, zipcode
)
SELECT
    customer_id,
    customer_name,
    segment,
    city,
    state,
    country,
    zipcode
FROM (
    SELECT
        customer_id,
        customer_fname || ' ' || customer_lname   AS customer_name,
        customer_segment                           AS segment,
        customer_city                              AS city,
        customer_state                             AS state,
        customer_country                           AS country,
        customer_zipcode::text                     AS zipcode,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY order_date_dateorders DESC    -- most recent record wins
        ) AS rn
    FROM staging.stg_orders
    WHERE customer_id IS NOT NULL
) ranked
WHERE rn = 1;

-- Sanity check
SELECT COUNT(*) AS dim_customer_rows FROM warehouse.dim_customer;

-- Must return ZERO — no duplicate customers allowed
SELECT customer_id, COUNT(*) AS occurrences
FROM warehouse.dim_customer
GROUP BY customer_id
HAVING COUNT(*) > 1;
