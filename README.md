# Credit Pre-Approval Engine

An end-to-end credit pre-approval pipeline built on public data: from raw bureau and
transaction history to a calibrated probability of default, a credit limit and a
reason for every decision.

## In plain words

When someone asks for a loan, the lender has to decide quickly and fairly:
yes or no, how much, and why. This project builds that decision step by step
on public, anonymised data from a consumer lender (Home Credit, published on
Kaggle):

1. **Collect** what is known about each applicant: loans at other lenders,
   earlier applications, how past loans were repaid.
2. **Summarise** it into one row per person — 84 facts such as "share of
   payments made late in the last year".
3. **Estimate** the chance that the person will have trouble repaying.
4. **Decide**: pre-approved or not, up to what limit, and the main reason.

Every step is checked automatically and every choice is written down, so
anyone can follow why the result is what it is. Unfamiliar words are
explained in the [glossary](docs/glossary.md).

> **Status:** 🚧 In progress — Stages 1–2 complete: 58.5M raw rows loaded; 87-column feature table (one row per client) built and verified by 35 automated data-quality checks. Next: model.

The project also addresses ten engineering problems that are common in legacy
risk pipelines (hard-coded lists, duplicated formulas, rules scattered through
code, silent row duplication and more). See [docs/before_after.md](docs/before_after.md).

## Links

| Platform | What | Link |
|---|---|---|
| GitHub | Code, SQL, documentation | this repository |
| Tableau Public | Dashboards | _coming soon_ |
| Kaggle | Modelling notebook | _coming soon_ |

## Tech stack

Oracle SQL · Python (pandas, scikit-learn, LightGBM) · Dataiku · Tableau

## Data

[Home Credit Default Risk](https://www.kaggle.com/competitions/home-credit-default-risk) (Kaggle).
The data is not included in this repository — see [data/README.md](data/README.md).

## Repository structure

```
config/      connection settings template (.env.example)
data/        raw Kaggle files and exports (not committed)
sql/         Oracle scripts, numbered in execution order
python/      reusable modules (hcr/) and runnable scripts
notebooks/   EDA, modelling, calibration and limits
dataiku/     flow export and screenshots
tableau/     workbook and screenshots
docs/        glossary, design notes, data profiling, data dictionary, decision log
```

## How to run

_Step-by-step instructions will be added as each stage is completed._

All commands are run from the repository root in Windows `cmd`.

1. Download the data (see [data/README.md](data/README.md)) and check it:
   `python python\scripts\check_data.py`
2. Create the database user (once):
   `sqlplus / as sysdba @sql\00_setup\01_create_user.sql`
3. Verify the user:
   `sqlplus / as sysdba @sql\00_setup\02_grant_and_test.sql`
4. Point Oracle at the data folder (once):
   `sqlplus / as sysdba @sql\00_setup\03_create_directory.sql "%CD%\data\raw"`
5. Store the HC password in an Oracle Wallet (once), so no script asks for
   or contains a password: [docs/setup_wallet.md](docs/setup_wallet.md).
   For Python: `python -m pip install -r requirements.txt`, create `config\.env`
   from `config\.env.example`, and store the password once in Windows
   Credential Manager (same document, section "Python")
6. Stage 1 — external tables, raw tables and load:
   `sqlplus /nolog @sql\run_stage1.sql`
7. Check the raw layer at any time:
   `sqlplus /nolog @sql\99_checks\01_raw_overview.sql`
8. Stage 2 — feature tables with data-quality checks, then the data dictionary:
   `sqlplus /nolog @sql\run_stage2.sql`
   (results of every check are stored in the `dq_log` table)
9. Regenerate only [docs/data_dictionary.md](docs/data_dictionary.md):
   `sqlplus /nolog @sql\run_data_dictionary.sql`
10. Stage 3 — check that Python reaches Oracle:
   `python python\scripts\check_db.py`
11. Stage 3 — SQL steps (so far: the fit / valid / holdout split):
   `sqlplus /nolog @sql\run_stage3.sql`

## Licence

MIT — see [LICENSE](LICENSE).
