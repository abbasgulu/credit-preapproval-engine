"""Stage 3a: check that Python can reach Oracle.

In plain words: before any model is trained, make sure Python can read the
feature table from Oracle — with the password taken from Windows Credential
Manager, never typed or stored in a file — and see how long a full read takes.

Run from the repository root:
    python python\\scripts\\check_db.py
"""
import platform
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # makes "import hcr" work

import oracledb  # noqa: E402

from hcr.db import connect, keyring_backend, read_sql  # noqa: E402


def main() -> None:
    print("===== 1. Python =====")
    print(f"Python        : {platform.python_version()} ({platform.architecture()[0]})")
    print(f"python-oracledb: {oracledb.__version__}")
    if platform.architecture()[0] != "64bit":
        print("WARNING: 64-bit Python is needed to load the 64-bit Oracle client.")

    print("\n===== 2. Connection (password from Windows Credential Manager) =====")
    print(f"Password store: {keyring_backend()}")
    print("                (keyring.backends.Windows.WinVaultKeyring = Windows Credential Manager)")
    with connect() as con, con.cursor() as cur:
        cur.execute("SELECT USER, SYS_CONTEXT('USERENV', 'CON_NAME') FROM dual")
        user, container = cur.fetchone()
        print(f"Connected as  : {user} (database {container})")
        print(f"Mode          : {'thin' if con.thin else 'thick'}, server {con.version}")

        print("\n===== 3. feat_customer in Oracle =====")
        cur.execute("""
            SELECT dataset, COUNT(*), SUM(target), ROUND(100 * AVG(target), 2)
            FROM   feat_customer
            GROUP  BY dataset
            ORDER  BY dataset DESC""")
        print(f"{'dataset':<8} {'clients':>9} {'defaults':>9} {'default %':>10}")
        for dataset, n, bad, rate in cur:
            print(f"{dataset:<8} {n:>9,} {bad if bad is not None else '-':>9} {rate if rate is not None else '-':>10}")

    print("\n===== 4. Full read into Python =====")
    start = time.perf_counter()
    df = read_sql("SELECT * FROM feat_customer")
    seconds = time.perf_counter() - start
    memory_mb = df.memory_usage(deep=True).sum() / 1024**2
    print(f"Rows x columns: {df.shape[0]:,} x {df.shape[1]}")
    print(f"Read time     : {seconds:.1f} s")
    print(f"Memory        : {memory_mb:,.0f} MB")

    expected = (356_255, 88)   # 88 columns: sk_id_curr, dataset, target + 85 features
    ok = df.shape == expected and df["sk_id_curr"].is_unique
    print(f"\nCheck         : shape {df.shape} = {expected} and sk_id_curr unique -> {'OK' if ok else 'FAILED'}")
    print("\n===== 3a " + ("COMPLETE" if ok else "FAILED") + " =====")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
