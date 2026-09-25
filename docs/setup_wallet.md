# Connecting without typing a password

## In plain words

The database password is never written in a script or a file. SQL scripts
take it from an **Oracle Wallet** (an encrypted file), Python takes it from
**Windows Credential Manager** (the password store built into Windows). You
set each up once; after that nothing asks for the password.

## SQL scripts (Oracle Wallet)

Every script connects through one file, [`sql/_connect.sql`](../sql/_connect.sql):

```sql
CONNECT /@hc_xepdb1
```

No user name and no password appear in the command. Oracle finds the alias
`hc_xepdb1` in its wallet — an encrypted file that holds the `HC` password —
and connects with it. This is Oracle's *Secure External Password Store*, the
usual way scheduled jobs connect to a database without passwords in scripts.

The wallet lives **outside the repository**, so it can never be committed.
`.gitignore` also blocks wallet files as a second safeguard.

### One-time setup (Windows, Oracle 18c XE)

`ORACLE_HOME` below is the Oracle installation folder, for example
`C:\app\<user>\product\18.0.0\dbhomeXE`. Find it with `where mkstore`
(the tool is in `ORACLE_HOME\bin`).

#### 1. Back up the network configuration

```bat
cd /d %ORACLE_HOME%\network\admin
copy sqlnet.ora sqlnet.ora.bak
copy tnsnames.ora tnsnames.ora.bak
```

#### 2. Create the wallet

```bat
mkdir %USERPROFILE%\oracle_wallet
mkstore -wrl %USERPROFILE%\oracle_wallet -create
```

It asks twice for a new **wallet password** (at least 8 characters, letters
combined with numbers). The wallet password is needed only to change the
wallet, never to connect. The folder then contains `ewallet.p12` (the
wallet) and `cwallet.sso` (its auto-login copy, used when connecting).

#### 3. Store the HC credential

```bat
mkstore -wrl %USERPROFILE%\oracle_wallet -createCredential hc_xepdb1 hc
```

It asks twice for the **HC password**, then once for the wallet password.
The password is not typed on the command line, so it stays out of the
command history. Check:

```bat
mkstore -wrl %USERPROFILE%\oracle_wallet -listCredential
```

Expected: `1: hc_xepdb1 hc`.

#### 4. Add the alias to `tnsnames.ora`

Append to `%ORACLE_HOME%\network\admin\tnsnames.ora` (the first line starts
in column 1):

```
HC_XEPDB1 =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = localhost)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = XEPDB1)
    )
  )
```

#### 5. Tell Oracle where the wallet is

Append to `%ORACLE_HOME%\network\admin\sqlnet.ora` (replace the folder with
your own full path — `%USERPROFILE%` is not expanded in this file):

```
WALLET_LOCATION =
  (SOURCE =
    (METHOD = FILE)
    (METHOD_DATA =
      (DIRECTORY = C:\Users\<user>\oracle_wallet)
    )
  )
SQLNET.WALLET_OVERRIDE = TRUE
```

`SQLNET.WALLET_OVERRIDE = TRUE` means: when no user name and password are
given, take them from the wallet. `sqlplus / as sysdba` is not affected.

#### 6. Test

```bat
sqlplus /@hc_xepdb1
SQL> SELECT USER FROM dual;
```

Expected: connected without a password prompt, `USER` = `HC`.

## Python (Windows Credential Manager)

Python uses `python-oracledb` in *thin mode* (pure Python, no Oracle client
needed). Thin mode cannot read the Oracle Wallet, and the Oracle client that
ships with Oracle 18c XE is too old for the driver's *thick mode*, so Python
keeps its own copy of the password in **Windows Credential Manager** — the
encrypted password store built into Windows, tied to your Windows account.

```bat
copy config\.env.example config\.env
python -m keyring set credit-preapproval-engine hc
```

The second command asks for the HC password at a hidden prompt. The
password is never typed on the command line, never written to a file, and
`config/.env` contains only the user name, the database address and the
name of the stored entry.

`python/hcr/db.py` reads the password only at the moment of connecting,
never prints or logs it, and refuses to run if the password store is not an
operating-system-protected one (for example a plain-text file store).

To see the entry: *Control Panel → Credential Manager → Windows Credentials →*
`credit-preapproval-engine`.

## Maintenance

| Task | Command |
|---|---|
| HC password changed | Update **both** stores: `mkstore -wrl %USERPROFILE%\oracle_wallet -modifyCredential hc_xepdb1 hc` and `python -m keyring set credit-preapproval-engine hc` |
| Remove the Python entry | `python -m keyring del credit-preapproval-engine hc` |
| Remove the credential | `mkstore -wrl %USERPROFILE%\oracle_wallet -deleteCredential hc_xepdb1` |
| Undo the whole setup | restore `sqlnet.ora.bak` and `tnsnames.ora.bak`, delete the wallet folder |

## Without a wallet

Replace the `CONNECT` line in `sql/_connect.sql` with the three lines below;
every script will then ask for the password instead:

```sql
ACCEPT hc_password CHAR PROMPT 'HC password: ' HIDE
CONNECT hc/"&hc_password"@localhost:1521/XEPDB1
UNDEFINE hc_password
```
