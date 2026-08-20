import pandas as pd
from sqlalchemy import create_engine, text

# ============================================================
#  DataCo Supply Chain DWH — Staging Load Script
#  Simple full load — reads CSV and loads into staging
# ============================================================

# ── Database credentials ── change these ──
DB_USER     = "postgres"
DB_PASSWORD = "your_password"
DB_HOST     = "localhost"
DB_PORT     = "5432"
DB_NAME     = "dataco_dwh"

# ── Path to the full CSV file ──
CSV_PATH    = r"C:\Users\EGY10\dataco-dwh\data\DataCoSupplyChainDataset.csv"

# ============================================================

def get_engine():
    return create_engine(
        f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
    )

def create_schemas(engine):
    print("\n[1/7] Creating schemas...")
    with engine.connect() as conn:
        conn.execute(text("CREATE SCHEMA IF NOT EXISTS staging;"))
        conn.execute(text("CREATE SCHEMA IF NOT EXISTS warehouse;"))
        conn.execute(text("CREATE SCHEMA IF NOT EXISTS marts;"))
        conn.commit()
    print("      Done.")

def read_csv(csv_path):
    print(f"\n[2/7] Reading CSV...")
    df = pd.read_csv(csv_path, encoding='latin-1')
    print(f"      Rows    : {len(df):,}")
    print(f"      Columns : {len(df.columns)}")
    return df

def clean_columns(df):
    print("\n[3/7] Cleaning column names...")
    df.columns = (
        df.columns
        .str.strip()
        .str.lower()
        .str.replace(' ', '_',      regex=False)
        .str.replace(r'[()\/]', '', regex=True)
    )
    print("      Done.")
    return df

def parse_dates(df):
    print("\n[4/7] Parsing dates...")
    df['order_date_dateorders'] = pd.to_datetime(
        df['order_date_dateorders'], errors='coerce'
    )
    df['shipping_date_dateorders'] = pd.to_datetime(
        df['shipping_date_dateorders'], errors='coerce'
    )
    print(f"      order_date nulls    : {df['order_date_dateorders'].isna().sum():,}")
    print(f"      shipping_date nulls : {df['shipping_date_dateorders'].isna().sum():,}")
    return df

def drop_useless_columns(df):
    print("\n[5/7] Dropping useless columns...")
    cols_to_drop = ['product_description', 'product_image']
    cols_present = [c for c in cols_to_drop if c in df.columns]
    if cols_present:
        df.drop(columns=cols_present, inplace=True)
        print(f"      Dropped : {cols_present}")
    else:
        print("      Nothing to drop.")
    return df

def deduplicate(df):
    print("\n[6/7] Deduplicating on order_item_id...")
    before = len(df)
    df = df.drop_duplicates(subset=['order_item_id'], keep='last')
    after = len(df)
    print(f"      Before : {before:,}")
    print(f"      After  : {after:,}")
    print(f"      Removed: {before - after:,} duplicates")
    return df

def load_to_staging(df, engine):
    print(f"\n[7/7] Loading {len(df):,} rows into staging.stg_orders...")
    print("      This may take 1-3 minutes...")
    df.to_sql(
        name      = 'stg_orders',
        con       = engine,
        schema    = 'staging',
        if_exists = 'replace',
        index     = False,
        chunksize = 5000,
        method    = 'multi'
    )
    print("      Done.")

def verify(engine):
    with engine.connect() as conn:
        result = conn.execute(text("SELECT COUNT(*) FROM staging.stg_orders"))
        return result.scalar()

def main():
    print("=" * 55)
    print("  DataCo DWH — Full Staging Load")
    print("=" * 55)

    engine = get_engine()
    create_schemas(engine)
    df = read_csv(CSV_PATH)
    df = clean_columns(df)
    df = parse_dates(df)
    df = drop_useless_columns(df)
    df = deduplicate(df)
    load_to_staging(df, engine)

    total = verify(engine)

    print(f"\n{'=' * 55}")
    print(f"  Staging Load Complete")
    print(f"  Total rows in staging : {total:,}")
    print(f"{'=' * 55}")
    print(f"\n  Next steps in pgAdmin:")
    print(f"  1. Run dim_date.sql")
    print(f"  2. Run dim_geography.sql")
    print(f"  3. Run dim_shipping.sql")
    print(f"  4. Run dim_customer.sql")
    print(f"  5. Run dim_product.sql")
    print(f"  6. Run fact_orders.sql")
    print(f"  7. Run marts.sql")
    print()

if __name__ == "__main__":
    main()
