"""Connection to the Oracle database.

In plain words: this module lets Python read tables from Oracle and write
results back. The password is never written in code or in a file: it is
kept in Windows Credential Manager (the encrypted password store built into
Windows) and read only at the moment of connecting.

Technically: python-oracledb in *thin mode* (pure Python, no Oracle client
needed) + the `keyring` library. Thin mode cannot read the Oracle Wallet
used by SQL*Plus, hence a separate, OS-protected store (decision 15).

One-time setup (the password is typed at a hidden prompt, not on the
command line):
    python -m keyring set credit-preapproval-engine hc

Usage:
    from hcr.db import connect, read_sql
    df = read_sql("SELECT * FROM feat_customer")
"""
from __future__ import annotations

import os
from pathlib import Path

import keyring
import oracledb
import pandas as pd
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]
ENV_FILE = ROOT / "config" / ".env"

# Keyring back-ends that keep secrets encrypted by the operating system.
# Anything else (e.g. a plain-text file back-end) is refused.
# Full names, because short class names are ambiguous (the "no keyring" back-end
# is also called Keyring).
_SAFE_BACKENDS = {
    "keyring.backends.Windows.WinVaultKeyring",   # Windows Credential Manager
    "keyring.backends.macOS.Keyring",             # macOS Keychain
    "keyring.backends.SecretService.Keyring",     # Linux Secret Service
}


def _settings() -> tuple[str, str, str]:
    """Read user, DSN and keyring service name from config/.env (no secrets there)."""
    if not ENV_FILE.exists():
        raise RuntimeError(
            f"{ENV_FILE} not found. Create it with:  copy config\\.env.example config\\.env"
        )
    load_dotenv(ENV_FILE)
    user = os.getenv("ORACLE_USER", "hc").strip()
    dsn = os.getenv("ORACLE_DSN", "localhost:1521/XEPDB1").strip()
    service = os.getenv("KEYRING_SERVICE", "credit-preapproval-engine").strip()
    return user, dsn, service


def _backend_names() -> list[str]:
    """Names of the keyring back-ends that would be consulted (a 'chainer' asks several)."""
    kr = keyring.get_keyring()
    backends = kr.backends if type(kr).__name__ == "ChainerBackend" else [kr]
    return [f"{type(b).__module__}.{type(b).__name__}" for b in backends]


def keyring_backend() -> str:
    """Name(s) of the keyring back-end in use (WinVaultKeyring = Windows Credential Manager)."""
    return ", ".join(_backend_names())


def _password(service: str, user: str) -> str:
    unsafe = [name for name in _backend_names() if name not in _SAFE_BACKENDS]
    if unsafe:
        raise RuntimeError(
            f"Keyring back-end(s) {unsafe} are not OS-protected stores; refusing to use them."
        )
    secret = keyring.get_password(service, user)
    if not secret:
        raise RuntimeError(
            f"No password stored for '{user}' under '{service}'. Store it once with:\n"
            f"    python -m keyring set {service} {user}"
        )
    return secret


def connect() -> oracledb.Connection:
    """Open a thin-mode connection as HC. The password never leaves this function."""
    user, dsn, service = _settings()
    return oracledb.connect(user=user, password=_password(service, user), dsn=dsn)


def read_sql(sql: str, params: dict | None = None, arraysize: int = 10_000) -> pd.DataFrame:
    """Run a query and return the result as a DataFrame with lower-case column names."""
    with connect() as con, con.cursor() as cur:
        cur.arraysize = arraysize      # rows fetched per round trip: bigger = faster for large tables
        cur.prefetchrows = arraysize + 1
        cur.execute(sql, params or {})
        columns = [d[0].lower() for d in cur.description]
        rows = cur.fetchall()
    return pd.DataFrame(rows, columns=columns)
