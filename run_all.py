"""Rebuilds the whole project from the raw LendingClub file.

1. Put accepted_2007_to_2018Q4.csv in data/ (link in the README).
2. pip install duckdb
3. python run_all.py
"""
import pathlib
import duckdb

ROOT = pathlib.Path(__file__).parent
RAW = ROOT / "data" / "accepted_2007_to_2018Q4.csv"
con = duckdb.connect()
con.execute(f"""
    CREATE TABLE raw_loans AS
    SELECT * FROM read_csv('{RAW}', header=true, all_varchar=true,
                           sample_size=-1, strict_mode=false, parallel=false)
""")
for script in sorted((ROOT / "sql").glob("*.sql")):
    print("Running", script.name)
    con.execute(script.read_text(encoding="utf-8"))

(ROOT / "marts").mkdir(exist_ok=True)
for (table,) in con.execute("SHOW TABLES").fetchall():
    if table.startswith("mart_"):
        con.execute(f"COPY {table} TO '{ROOT / 'marts' / table}.csv' (HEADER, DELIMITER ',')")
        print("Wrote", table)
