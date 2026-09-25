# Credit Pre-Approval Engine

An end-to-end credit pre-approval pipeline built on public data: from raw bureau and
transaction history to a calibrated probability of default, a credit limit and a
reason for every decision.

> **Status:** 🚧 In progress — setup complete, data loading next.

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
docs/        architecture, data dictionary, decision log
```

## How to run

_Step-by-step instructions will be added as each stage is completed._

1. Download the data (see [data/README.md](data/README.md)).
2. Create the database user: `sqlplus / as sysdba @sql/00_setup/01_create_user.sql`
3. Verify it: `sqlplus / as sysdba @sql/00_setup/02_grant_and_test.sql`

## Licence

MIT — see [LICENSE](LICENSE).
