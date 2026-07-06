"""
etl_main.py -- moves data from PostgreSQL into ClickHouse.

Run:  python etl/etl_main.py

How it stays up to date (no flags, no modes):
  Every warehouse table is asked "what is the newest updated_at you have?"
  Then only rows NEWER than that are fetched from PostgreSQL.
  - First run: the tables are empty, the answer is 1970 -> everything loads.
  - Later runs: only new or changed rows load.
  The ClickHouse tables use ReplacingMergeTree(updated_at), so a re-sent
  row with a newer updated_at simply replaces the old version.
"""

import sys
from datetime import date
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from etl.db_clients import PostgresDBClient, ClickHouseDBClient


def age_band(dob, today=None):
    today = today or date.today()
    age = today.year - dob.year - ((today.month, today.day) < (dob.month, dob.day))
    if age < 25: return "18-24"
    if age < 35: return "25-34"
    if age < 45: return "35-44"
    if age < 55: return "45-54"
    if age < 65: return "55-64"
    return "65+"


pg = PostgresDBClient()
ch = ClickHouseDBClient()

# ------------------------------------------------------------------
# 1) dim_customer
# ------------------------------------------------------------------
last = ch.get_last_changed_on("dim_customer")
customers = pg.fetch_data(f"""
    SELECT customer_id, first_name, last_name, email, phone_number,
           date_of_birth, created_at, updated_at
    FROM customers
    WHERE updated_at > '{last}'
""")
if not customers.empty:
    customers["full_name"] = customers["first_name"].str.strip() + " " + customers["last_name"].str.strip()
    customers["email"] = customers["email"].fillna("")
    customers["age_band"] = customers["date_of_birth"].apply(age_band)
    customers = customers[["customer_id", "full_name", "email", "phone_number",
                           "date_of_birth", "age_band", "created_at", "updated_at"]]
ch.insert_dataframe(customers, "dim_customer")

# ------------------------------------------------------------------
# 2) dim_account
# ------------------------------------------------------------------
last = ch.get_last_changed_on("dim_account")
accounts = pg.fetch_data(f"""
    SELECT account_id, customer_id, account_number, account_type,
           currency_code, balance, status, opened_at, updated_at
    FROM accounts
    WHERE updated_at > '{last}'
""")
if not accounts.empty:
    accounts["balance"] = accounts["balance"].astype(float)
ch.insert_dataframe(accounts, "dim_account")

# ------------------------------------------------------------------
# 3) fact_transactions
#    One row per transaction. The JOINs pull the purchase / cashout /
#    transfer details onto the same row (LEFT JOIN: only one matches).
# ------------------------------------------------------------------
last = ch.get_last_changed_on("fact_transactions")
fact = pg.fetch_data(f"""
    SELECT
        t.transaction_id,
        t.transaction_date,
        t.account_id,
        a.customer_id,
        t.card_id,
        t.reference_number,
        t.transaction_type,
        t.status,
        t.amount,
        t.currency_code,
        t.description,
        p.merchant_name,
        p.merchant_category,
        p.merchant_country,
        c.cashout_channel,
        c.fee_amount,
        c.location AS cashout_location,
        tr.transfer_method,
        tr.destination_account_id,
        tr.settled_at,
        t.updated_at
    FROM transactions t
    JOIN accounts a        ON a.account_id  = t.account_id
    LEFT JOIN purchase p   ON p.purchase_id = t.reference_number
    LEFT JOIN cashout c    ON c.cashout_id  = t.reference_number
    LEFT JOIN transfers tr ON tr.transfer_id = t.reference_number
    WHERE t.updated_at > '{last}'
""")
if not fact.empty:
    # numbers
    fact["amount"] = fact["amount"].astype(float)
    fact["fee_amount"] = fact["fee_amount"].fillna(0).astype(float)
    # text columns: empty string instead of NULL (ClickHouse-friendly)
    for col in ["card_id", "description", "merchant_name", "merchant_category",
                "merchant_country", "cashout_channel", "cashout_location",
                "transfer_method", "destination_account_id"]:
        fact[col] = fact[col].fillna("")
    # settled_at stays nullable (only transfers have it)
    fact["settled_at"] = fact["settled_at"].astype(object).where(fact["settled_at"].notna(), None)
    # simple in-flight quality check, printed every run
    cash = fact[fact["transaction_type"] == "CASHOUT"]
    print(f"quality check -> rows: {len(fact):,}, "
          f"fee > amount: {(cash['fee_amount'] > cash['amount']).sum()}")
ch.insert_dataframe(fact, "fact_transactions")

print("ETL finished.")
