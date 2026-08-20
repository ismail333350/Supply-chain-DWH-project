# DataCo Supply Chain — Data Warehouse

A production-pattern Data Warehouse built on **PostgreSQL** using the DataCo Supply Chain dataset (180,518 order records). The project implements a full three-layer architecture — staging, warehouse, and analytical marts — connected to **Power BI** for business reporting.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Dataset](#dataset)
- [Architecture](#architecture)
- [Star Schema Design](#star-schema-design)
- [Project Structure](#project-structure)
- [How to Run](#how-to-run)
- [Data Quality Issues Discovered and Fixed](#data-quality-issues-discovered-and-fixed)
- [Data Marts and Business Questions](#data-marts-and-business-questions)
- [Design Decisions](#design-decisions)
- [Key Findings](#key-findings)
- [Tech Stack](#tech-stack)

---

## Project Overview

Raw supply chain data arrives as a flat CSV with 180,518 rows and 53 columns where every attribute about every order — customers, products, shipping, geography, and financials — is crammed into a single flat row. This makes analytics slow, unreliable, and structurally incorrect.

This project transforms that flat file into a purpose-built Data Warehouse that separates business events (facts) from business context (dimensions), pre-aggregates common analytical queries into data marts, and connects directly to Power BI for business reporting.

---

## Dataset

| Property | Value |
|---|---|
| Source | DataCo Supply Chain Dataset |
| Original rows | 180,519 |
| Rows after deduplication | 180,518 |
| Columns | 53 (51 after dropping useless columns) |
| Date range | January 2015 — January 2018 |
| Markets | LATAM, Europe, Pacific Asia, USCA, Africa |
| Business domains | Orders, Customers, Products, Shipping, Geography |

### Known Data Quality Issues

| Issue | Discovery Method | Resolution |
|---|---|---|
| `product_description` 100% NULL | EDA at ingestion | Dropped at staging load |
| `product_image` contains only URLs | EDA at ingestion | Dropped at staging load |
| 1 duplicate `order_item_id` | Deduplication check in Python | Removed before staging load |
| Latitude/longitude float variation caused 689x fan trap in dim_geography | Diagnosis query on fact joins | GROUP BY join key columns only, AVG coordinates |
| `order_customer_id` is a redundant copy of `customer_id` | Data dictionary analysis | Used `customer_id` only |

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│  SOURCE                                         │
│  DataCoSupplyChainDataset.csv  (180,519 rows)   │
└────────────────────┬────────────────────────────┘
                     │
                     │  Python — load_staging.py
                     │  • Normalize column names
                     │  • Parse date columns
                     │  • Drop useless columns
                     │  • Deduplicate on order_item_id
                     │  • Full replace every run
                     ▼
┌─────────────────────────────────────────────────┐
│  STAGING  |  staging.stg_orders                 │
│  180,518 rows · 51 columns · raw data           │
└────────────────────┬────────────────────────────┘
                     │
                     │  SQL — pgAdmin
                     │  • Dimension extraction
                     │  • ROW_NUMBER() deduplication
                     │  • GROUP BY join key only for geography
                     │  • Surrogate key generation
                     │  • Diagnosis check before fact load
                     ▼
┌─────────────────────────────────────────────────┐
│  WAREHOUSE  |  warehouse schema  |  Star Schema  │
│                                                 │
│  dim_customer   dim_product   dim_date          │
│  dim_geography  dim_shipping                    │
│                                                 │
│           ▼  fact_orders  ▼                     │
│           180,518 rows                          │
└────────────────────┬────────────────────────────┘
                     │
                     │  Materialized Views
                     ▼
┌─────────────────────────────────────────────────┐
│  MARTS  |  marts schema                         │
│                                                 │
│  mart_delivery_performance                      │
│  mart_product_profitability                     │
│  mart_monthly_revenue                           │
└────────────────────┬────────────────────────────┘
                     │
                     │  DirectQuery / Import
                     ▼
┌─────────────────────────────────────────────────┐
│  POWER BI                                       │
│  Delivery · Profitability · Revenue Reports     │
└─────────────────────────────────────────────────┘
```

---

## Star Schema Design

### Fact Table — `warehouse.fact_orders`

**Grain:** One row per order line item (`order_item_id`)

| Column | Type | Description |
|---|---|---|
| order_item_id | INT PK | Grain — one row per order line item |
| order_id | INT | Parent order containing this line item |
| customer_sk | INT FK | → dim_customer surrogate key |
| product_sk | INT FK | → dim_product surrogate key |
| date_id | INT FK | → dim_date (YYYYMMDD format) |
| geography_id | INT FK | → dim_geography |
| shipping_id | INT FK | → dim_shipping |
| quantity | INT | Units ordered |
| unit_price | NUMERIC | Price before discount |
| discount_amount | NUMERIC | Discount in dollars |
| discount_rate | NUMERIC | Discount as a ratio 0–1 |
| line_total | NUMERIC | Total after discount |
| sales | NUMERIC | Actual revenue |
| benefit | NUMERIC | Gross earnings |
| profit | NUMERIC | Net profit |
| profit_ratio | NUMERIC | Profit divided by sales |
| late_delivery_risk | INT | 1 = at risk, 0 = on time |
| order_status | VARCHAR | COMPLETE, CANCELED, SUSPECTED_FRAUD etc |
| payment_type | VARCHAR | DEBIT, TRANSFER, CASH, PAYMENT |

### Dimension Tables

| Dimension | Type | Grain | Key Attributes |
|---|---|---|---|
| dim_customer | SCD1 | One row per customer | customer_id, name, segment, city, state, country |
| dim_product | SCD1 | One row per product | product_id, name, category, department, price |
| dim_date | Static | One row per date | date_id, full_date, year, month, quarter, day_name |
| dim_geography | SCD1 | One row per city/country/region | order_city, order_country, order_region, market, lat, lon |
| dim_shipping | SCD1 | One row per shipping combination | shipping_mode, delivery_status, delay_days |

### Why No SCD Type 2

This version of the project uses SCD Type 1 (latest value wins) for all dimensions. This makes the warehouse simpler, faster to build, and easier to connect to Power BI without complex temporal join logic. SCD Type 2 will be added in a future iteration for `dim_customer` and `dim_product` to enable historical segment and price analysis.

---

## Project Structure

```
dataco-dwh/
├── data/
│   └── DataCoSupplyChainDataset.csv        ← source file (not committed to git)
├── python/
│   └── load_staging.py                     ← ingestion script
├── sql/
│   ├── 02_dimensions/
│   │   ├── dim_date.sql
│   │   ├── dim_geography.sql
│   │   ├── dim_shipping.sql
│   │   ├── dim_customer.sql
│   │   └── dim_product.sql
│   ├── 03_facts/
│   │   └── fact_orders.sql
│   └── 04_marts/
│       └── marts.sql
└── README.md
```

---

## How to Run

### Prerequisites

| Tool | Purpose |
|---|---|
| PostgreSQL 14+ | Database engine |
| Python 3.9+ | Ingestion script |
| pgAdmin | Running SQL scripts |
| pandas, sqlalchemy, psycopg2-binary | Python libraries |

### Step 1 — Create the database

```sql
CREATE DATABASE dataco_dwh;
```

### Step 2 — Set up Python environment

```bat
cd C:\Users\EGY10\dataco-dwh
python -m venv venv
venv\Scripts\activate
pip install pandas sqlalchemy psycopg2-binary
```

### Step 3 — Configure load_staging.py

Open `python\load_staging.py` and update:

```python
DB_PASSWORD = "your_password"
CSV_PATH    = r"C:\path\to\DataCoSupplyChainDataset.csv"
```

### Step 4 — Run the staging load

```bat
python python\load_staging.py
```

Expected output:
```
[6/7] Deduplicating on order_item_id...
      Before : 180,519
      After  : 180,518
      Removed: 1 duplicate

  Total rows in staging : 180,518
```

### Step 5 — Run SQL scripts in pgAdmin (in this exact order)

```
1.  dim_date.sql
2.  dim_geography.sql        ← uses GROUP BY join key only
3.  dim_shipping.sql
4.  dim_customer.sql         ← uses ROW_NUMBER() to guarantee one row per customer
5.  dim_product.sql          ← uses ROW_NUMBER() to guarantee one row per product
6.  Diagnosis check          ← must return ZERO rows before proceeding
7.  fact_orders.sql
8.  marts.sql
```

### Step 6 — Diagnosis check (mandatory before fact load)

```sql
SELECT o.order_item_id, COUNT(*) AS match_count
FROM staging.stg_orders o
JOIN warehouse.dim_customer c ON c.customer_id = o.customer_id
JOIN warehouse.dim_product  p ON p.product_id  = o.product_card_id
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
HAVING COUNT(*) > 1;
-- Must return ZERO rows
```

### Step 7 — Sanity check

```sql
SELECT 'staging.stg_orders'       AS table_name, COUNT(*) AS rows FROM staging.stg_orders
UNION ALL SELECT 'warehouse.dim_customer',  COUNT(*) FROM warehouse.dim_customer
UNION ALL SELECT 'warehouse.dim_product',   COUNT(*) FROM warehouse.dim_product
UNION ALL SELECT 'warehouse.dim_date',      COUNT(*) FROM warehouse.dim_date
UNION ALL SELECT 'warehouse.dim_geography', COUNT(*) FROM warehouse.dim_geography
UNION ALL SELECT 'warehouse.dim_shipping',  COUNT(*) FROM warehouse.dim_shipping
UNION ALL SELECT 'warehouse.fact_orders',   COUNT(*) FROM warehouse.fact_orders
ORDER BY table_name;

-- Must return 0
SELECT COUNT(*) AS orphaned FROM warehouse.fact_orders
WHERE customer_sk IS NULL OR product_sk IS NULL;
```

Expected results:

| Table | Rows |
|---|---|
| staging.stg_orders | 180,518 |
| warehouse.dim_customer | ~12,000 |
| warehouse.dim_product | ~100 |
| warehouse.dim_date | ~1,400 |
| warehouse.dim_geography | ~3,000 |
| warehouse.dim_shipping | ~20 |
| warehouse.fact_orders | ~180,518 |
| Orphaned rows | 0 |

---

## Data Quality Issues Discovered and Fixed

### Issue 1 — Duplicate order_item_id in source

**Discovered:** Python deduplication step showed 180,519 rows reduced to 180,518.
**Root cause:** One order item ID appeared twice in the source CSV.
**Fix:** `drop_duplicates(subset=['order_item_id'], keep='last')` in Python before staging load.

### Issue 2 — Float precision causing 689x fan trap in dim_geography

**Discovered:** Diagnosis query showed single order items matching up to 689 rows in the join — causing duplicate primary key violations in the fact table.
**Root cause:** `latitude` and `longitude` columns had tiny floating point variations (e.g. `40.7128` vs `40.7127`) for the same city. Including them in the `DISTINCT` clause created hundreds of geography rows for what should be one location.
**Fix:** `GROUP BY` only on the three join key columns (`order_city`, `order_country`, `order_region`) and use `AVG(latitude)`, `AVG(longitude)` for coordinates.

```sql
-- Wrong — includes float columns in deduplication
SELECT DISTINCT order_city, order_country, order_region, latitude, longitude ...

-- Correct — group by join key only, average the floats
SELECT order_city, order_country, order_region,
       AVG(latitude), AVG(longitude)
FROM staging.stg_orders
GROUP BY order_city, order_country, order_region
```

### Issue 3 — Residual duplicates after geography fix

**Discovered:** Diagnosis query still returned 3 matches per order item after the first geography fix.
**Root cause:** `order_state` and `market` were still included in the GROUP BY, creating multiple rows for the same city/country/region combination where state or market had slight variations.
**Fix:** Remove `order_state` and `market` from GROUP BY entirely. Use `MIN(order_state)` and `MIN(market)` as aggregates instead.

---

## Data Marts and Business Questions

### mart_delivery_performance

**Business question:** Which markets and shipping modes have the highest late delivery rates and longest delays?

```sql
SELECT market, shipping_mode, late_rate_pct, avg_delay_days
FROM marts.mart_delivery_performance
ORDER BY late_rate_pct DESC;
```

### mart_product_profitability

**Business question:** Which product categories and departments generate the most profit and the best margin?

```sql
SELECT category_name, total_profit, avg_margin_pct
FROM marts.mart_product_profitability
ORDER BY total_profit DESC;
```

### mart_monthly_revenue

**Business question:** What is the month-over-month revenue and profit trend for each market?

```sql
SELECT year, month, market, total_revenue, total_profit
FROM marts.mart_monthly_revenue
ORDER BY year, month, total_revenue DESC;
```

Refresh all marts after each pipeline run:

```sql
REFRESH MATERIALIZED VIEW marts.mart_delivery_performance;
REFRESH MATERIALIZED VIEW marts.mart_product_profitability;
REFRESH MATERIALIZED VIEW marts.mart_monthly_revenue;
```

---

## Design Decisions

**Why GROUP BY join key columns only for dim_geography**
The fact table joins to dim_geography on three columns: `order_city`, `order_country`, and `order_region`. Including any additional columns in the deduplication key — especially float columns like latitude and longitude — creates multiple geography rows for the same logical location, causing a fan trap that multiplies fact rows. Deduplicating on the join key alone guarantees exactly one geography row per fact row.

**Why ROW_NUMBER() instead of DISTINCT for dim_customer and dim_product**
`DISTINCT` deduplicates on the full row combination of all columns. Since `customer_zipcode` is 86% NULL in this dataset, the same customer can appear with a zipcode on some orders and NULL on others — producing two DISTINCT rows for the same customer. `ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date DESC)` guarantees exactly one row per customer regardless of attribute variation, always using the most recent record.

**Why ON CONFLICT DO NOTHING on the fact table**
Even after the diagnosis check passes, `ON CONFLICT DO NOTHING` acts as a permanent safety net ensuring the fact load never fails on a duplicate key. It is a standard practice in production pipelines.

**Why INNER JOIN for customer and product but LEFT JOIN for geography and shipping**
Customer and product are business-critical dimensions — an order must have a customer and a product to be meaningful. INNER JOIN enforces this and surfaces data quality issues. Geography and shipping are enrichment dimensions — an order can still be analyzed for revenue and profit even if the geography or shipping row is not found. LEFT JOIN preserves all orders and sets those FK columns to NULL rather than silently dropping rows.

**Why materialized views for marts**
Materialized views store pre-computed aggregation results on disk. Analytical queries against the marts run in milliseconds instead of scanning 180,518 fact rows every time. The trade-off is that they must be refreshed after each pipeline run — a deliberate and acceptable choice for this use case.

---

## Key Findings

From the EDA on the full dataset:

- **54.9%** of orders carry a late delivery risk — the single biggest operational concern
- **Second Class** shipping averages **+2.07 days** late despite being a paid upgrade over Standard Class
- **Standard Class** is the most reliable shipping mode, averaging nearly on-time delivery
- **Fishing** is the most profitable product category by total profit
- **LATAM and Europe** are the top two markets, virtually tied at approximately $575K in revenue each
- **2.1%** of orders are flagged as `SUSPECTED_FRAUD` with above-average profit per order — a pattern worth investigating
- **Cardio Equipment** leads in average profit per order despite not having the highest total revenue

---

## Tech Stack

| Layer | Tool |
|---|---|
| Database | PostgreSQL 16 |
| Ingestion | Python 3 — pandas, sqlalchemy, psycopg2-binary |
| Transformation | SQL — pgAdmin Query Tool |
| Serving | PostgreSQL Materialized Views |
| Visualization | Power BI |
| OS | Windows 11 |

---

## Future Enhancements

- Add **SCD Type 2** to `dim_customer` and `dim_product` to track historical segment and price changes
- Add **incremental loading** with a watermark table to process only new records on each run
- Add **dbt** for tested, documented, version-controlled transformations
- Deploy to **AWS RDS** for cloud-hosted PostgreSQL
- Add **data quality assertions** that run automatically after each pipeline step
- Add **Airflow** or **cron** scheduling for automated daily pipeline runs

---

*DataCo Supply Chain Data Warehouse — Built with PostgreSQL and Python*
