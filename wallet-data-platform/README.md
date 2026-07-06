# Digital Wallet — Data Engineer Assessment

This project has two parts:

1. **Operational database (PostgreSQL)** — holds the raw wallet data with all the rules enforced (Task 1).
2. **Data warehouse (ClickHouse)** — a copy of the data reshaped for fast analytics, kept up to date by a small Python ETL (Task 2).

Both databases run in Docker, so one command starts everything.

## Products used

- **PostgreSQL 16** — operational database. Strong constraints (primary keys, foreign keys, checks) keep financial data correct.
- **ClickHouse 24.8** — warehouse. Very fast at scanning and aggregating large tables.
- **Python** (pandas, psycopg2, clickhouse-connect) — the ETL.

## Project layout

```
docker-compose.yml       starts both databases
creds.ini                database connection settings
requirements.txt         Python packages
oltp/
  01_create_database.sql creates the database (Docker already does this)
  02_create_tables.sql   creates the 7 tables from the ERD
  03_load_data.py        loads the CSV files
  04_validate_load.sql   checks the load was correct
dwh/
  10_create_warehouse.sql  creates the warehouse tables
  20_sample_analytics.sql  example analytics queries
etl/
  db_clients.py          two small classes: Postgres + ClickHouse
  etl_main.py            the ETL — run this to move / refresh data
data/                    put the extracted CSV files here
```

## How to run (Windows, PowerShell)

You need Docker Desktop and Python installed.

```powershell
# 1. start the databases
docker compose up -d

# 2. install the Python packages
pip install -r requirements.txt

# 3. put the 7 CSV files from data_tables.zip into the data folder

# 4. create the operational tables and load the data
Get-Content oltp/02_create_tables.sql | docker exec -i wallet_postgres psql -U wallet -d wallet_oltp
python oltp/03_load_data.py --data-dir data
Get-Content oltp/04_validate_load.sql | docker exec -i wallet_postgres psql -U wallet -d wallet_oltp

# 5. create the warehouse tables and run the ETL
Get-Content dwh/10_create_warehouse.sql | docker exec -i wallet_clickhouse clickhouse-client --user wallet --password wallet_pass --multiquery
python etl/etl_main.py

# 6. try the analytics queries
Get-Content dwh/20_sample_analytics.sql | docker exec -i wallet_clickhouse clickhouse-client --user wallet --password wallet_pass --multiquery
```

## How the warehouse stays up to date

There are no modes or flags. `etl_main.py` works like this:

1. It asks each warehouse table: *"what is the newest `updated_at` you have?"*
2. It fetches from PostgreSQL only the rows **newer than that**.
3. It inserts them into ClickHouse.

On the first run the tables are empty, so the answer is 1970 and everything loads. On every later run, only new or changed rows load. The tables use ClickHouse's `ReplacingMergeTree` engine, which means a re-inserted row with a newer `updated_at` **replaces** the old version — so updates in PostgreSQL become updates in the warehouse, and running the ETL twice never creates duplicates.

Quick test:

```powershell
docker exec -it wallet_postgres psql -U wallet -d wallet_oltp -c "UPDATE transactions SET status='REVERSED', updated_at=now() WHERE transaction_id=(SELECT transaction_id FROM transactions LIMIT 1) RETURNING transaction_id;"
python etl/etl_main.py     # loads just that one row
```

## Warehouse design

One wide **fact table** (`fact_transactions`) with one row per transaction. In the source, purchases, cash-outs and transfers keep their details in three separate tables — the ETL joins them onto the transaction row, so analysts never need to stitch tables together. Two small **dimensions** (`dim_customer` with an age band, `dim_account`) answer "who" questions. The fact table is partitioned by month, which matches how the data is queried.

## Assumptions

1. `transactions.reference_number` is unique (checked — all 225,000 are). It is declared UNIQUE so the purchase / cashout / transfers tables can point to it with real foreign keys.
2. The detail tables (purchase, cashout, transfers) have no timestamp of their own, so I assume their rows never change without the parent transaction's `updated_at` changing too. The ETL is driven by the transaction timestamp.
3. For transfers, the transaction's `account_id` is the **sender** (checked — it matches `source_account_id` on all 75,000 rows).
4. The allowed values in CHECK constraints (statuses, channels, methods) come from what appears in the data.
5. Card numbers and CVV hashes are sensitive, so they are **not copied** into the warehouse at all.
6. Dimensions keep only the latest version of each row (no history) — enough for this scope.

## Data observations

The data is clean overall (it matches the provided `validation_summary.csv`), but a full check found:

1. **51 cash-outs where the fee is bigger than the withdrawn amount** — e.g. a 4,700 IQD fee on a 1,100 IQD withdrawal. Loaded as-is, but the ETL prints the count on every run and query 3 in the analytics file shows them per channel.
2. **No top-up or deposit transactions exist**, even though the business description mentions wallet top-ups. Only PURCHASE, CASHOUT and TRANSFER appear (75,000 each).
3. `card_id` is empty exactly where it should be: all transfers, and the cash-outs made through non-card channels (agent, branch).
4. Everything is a single currency (IQD) and all merchants are in Iraq.
5. About 16% of cards are expired today — their historical transactions are still valid.
6. The CSV files start with an invisible BOM character and use Windows line endings — the loader handles both.
7. Referential integrity in the files is perfect: no orphan foreign keys, no duplicate keys, and every transaction matches exactly one detail row of the right type.
