# Data

The data is **not** stored in this repository (file size limits and Kaggle licence).

## How to get it

1. Open the competition page: <https://www.kaggle.com/competitions/home-credit-default-risk/data>
2. Accept the competition rules (required before download).
3. Click **Download All** and unzip the archive into `data/raw/`.

## Expected contents of `data/raw/`

| File | Rows | Columns |
|---|---:|---:|
| `application_train.csv` | 307,511 | 122 |
| `application_test.csv` | 48,744 | 121 |
| `bureau.csv` | 1,716,428 | 17 |
| `bureau_balance.csv` | 27,299,925 | 3 |
| `previous_application.csv` | 1,670,214 | 37 |
| `installments_payments.csv` | 13,605,401 | 8 |
| `POS_CASH_balance.csv` | 10,001,358 | 8 |
| `credit_card_balance.csv` | 3,840,312 | 23 |
| `HomeCredit_columns_description.csv` | 219 | 5 |

Verify your download with:

```
python python/scripts/check_data.py
```

## Folders

- `data/raw/` — original Kaggle CSV files, never modified
- `data/export/` — files exported from Oracle for Tableau
