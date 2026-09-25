# Credit Pre-Approval Engine

An end-to-end credit pre-approval pipeline built on public data: from raw bureau and
transaction history to a calibrated probability of default, a credit limit and a
reason for every decision.

> **Status:** 🚧 In progress — Stage 1 complete (58.5M rows loaded and verified). Next: feature tables.

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
docs/        architecture, data profiling, data dictionary, decision log
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
5. Stage 1 — external tables, raw tables and load:
   `sqlplus /nolog @sql\run_stage1.sql` (asks for the HC password)
6. Check the raw layer at any time:
   `sqlplus /nolog @sql\99_checks\01_raw_overview.sql`

## Licence

MIT — see [LICENSE](LICENSE).
