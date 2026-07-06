"""
db_clients.py
Two small database clients:
  - PostgresDBClient   : runs a query, returns a pandas DataFrame
  - ClickHouseDBClient : inserts a DataFrame, reads the last loaded time
Connection settings come from creds.ini in the project root.
"""

import configparser
import datetime
from pathlib import Path

import clickhouse_connect
import pandas as pd
import psycopg2

CREDS_FILE = Path(__file__).resolve().parent.parent / "creds.ini"


def load_creds(section):
    config = configparser.ConfigParser()
    config.read(CREDS_FILE)
    return config[section]


class PostgresDBClient:
    def __init__(self):
        self.config = load_creds("postgres")

    def fetch_data(self, query):
        connection = psycopg2.connect(
            host=self.config["host"],
            port=int(self.config["port"]),
            user=self.config["user"],
            password=self.config["password"],
            database=self.config["database"],
        )
        try:
            cursor = connection.cursor()
            cursor.execute(query)
            rows = cursor.fetchall()
            columns = [desc[0] for desc in cursor.description]
            return pd.DataFrame(rows, columns=columns)
        finally:
            cursor.close()
            connection.close()


class ClickHouseDBClient:
    def __init__(self):
        self.config = load_creds("clickhouse")
        self.client = clickhouse_connect.get_client(
            host=self.config["host"],
            port=int(self.config["port"]),
            username=self.config["user"],
            password=self.config["password"],
            database=self.config["database"],
        )

    def insert_dataframe(self, df, table_name):
        if df.empty:
            print(f"No new rows for {table_name}.")
            return
        self.client.insert_df(table_name, df)
        print(f"Inserted {len(df):,} rows into {table_name}")

    def get_last_changed_on(self, table_name, date_column="updated_at"):
        """Ask the table itself when it was last loaded.
        Empty table -> 1970, which makes the first run a full load."""
        try:
            result = self.client.query(
                f"SELECT MAX({date_column}) FROM {table_name}"
            ).result_rows[0][0]
            if result is None or result.year < 1971:
                return pd.Timestamp("1970-01-01 00:00:00")
            if isinstance(result, datetime.datetime):
                return pd.to_datetime(result.strftime("%Y-%m-%d %H:%M:%S"))
            return pd.to_datetime(result)
        except Exception as e:
            print(f"Could not read watermark from {table_name}: {e}")
            return pd.Timestamp("1970-01-01 00:00:00")
