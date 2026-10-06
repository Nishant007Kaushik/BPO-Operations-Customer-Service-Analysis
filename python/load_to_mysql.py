import getpass
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine
from sqlalchemy.engine import URL

ROOT = Path(__file__).resolve().parent.parent
CSV_PATH = ROOT / "data" / "bpo_interactions.csv"

# The password is typed at run time so it never ends up in your code or on GitHub
password = getpass.getpass("MySQL password: ")

url = URL.create(
    "mysql+pymysql",
    username="root",          # change if you use a different MySQL user
    password=password,
    host="localhost",
    port=3306,
    database="bpo_operations",
)
engine = create_engine(url)

df = pd.read_csv(CSV_PATH)
print("Rows to load:", df.shape)       # (60000, 35)

with engine.begin() as conn:
    conn.exec_driver_sql("TRUNCATE TABLE bpo_interactions")   # makes the script safe to re-run

# pandas converts NaN into real SQL NULLs, so invalid dates load as NULL
df.to_sql("bpo_interactions", engine, if_exists="append", index=False, chunksize=5000)
print("Load complete")