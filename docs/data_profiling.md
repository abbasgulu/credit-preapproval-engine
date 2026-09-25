# Data profiling

Facts measured on the raw layer before design decisions were made.
All numbers can be reproduced with
[`sql/99_checks/02_raw_profiling.sql`](../sql/99_checks/02_raw_profiling.sql).

Measured on 2026-09-25.

## 1. Raw load

All nine files were loaded with an exact row-count match
(`sql/run_stage1.sql`, gate: 9 of 9 tables OK).

| Table | Rows | Load time (s) |
|---|---:|---:|
| `raw_column_description` | 219 | 0.6 |
| `raw_application_train` | 307,511 | 16.5 |
| `raw_application_test` | 48,744 | 2.9 |
| `raw_bureau` | 1,716,428 | 12.1 |
| `raw_previous_application` | 1,670,214 | 26.1 |
| `raw_credit_card_balance` | 3,840,312 | 35.3 |
| `raw_pos_cash_balance` | 10,001,358 | 33.4 |
| `raw_installments_payments` | 13,605,401 | 52.8 |
| `raw_bureau_balance` | 27,299,925 | 37.1 |
| **Total** | **58,490,112** | **216.8** |

Oracle 18c XE on a laptop, external tables → direct-path insert.

## 2. Line endings

Oracle 18c has no automatic line-ending detection, so the record delimiter
of every external table is set explicitly. Every file was measured:

| File | Line ending | How it was measured |
|---|---|---|
| `HomeCredit_columns_description.csv` | CRLF | byte count of the file |
| `application_train.csv`, `application_test.csv`, `bureau.csv`, `bureau_balance.csv`, `previous_application.csv`, `POS_CASH_balance.csv` | LF | byte count of the file |
| `credit_card_balance.csv`, `installments_payments.csv` | LF | in Oracle: 0 rows with CR in the last field |

## 3. The `365243` placeholder

`DAYS_*` columns count days relative to the application date (negative = in
the past). The value **365243** (≈ 1,000 years) is not a real duration: it is a
placeholder for "no date" in the source system.

### Where it occurs

| Table | Column | Rows with 365243 | Share |
|---|---|---:|---:|
| `application_train` | `DAYS_EMPLOYED` | 55,374 | 18.01% |
| `application_test` | `DAYS_EMPLOYED` | 9,274 | 19.03% |
| `previous_application` | `DAYS_FIRST_DRAWING` | 934,444 | 55.95% |
| `previous_application` | `DAYS_FIRST_DUE` | 40,645 | 2.43% |
| `previous_application` | `DAYS_LAST_DUE_1ST_VERSION` | 93,864 | 5.62% |
| `previous_application` | `DAYS_LAST_DUE` | 211,221 | 12.65% |
| `previous_application` | `DAYS_TERMINATION` | 225,913 | 13.53% |

### Who has `DAYS_EMPLOYED = 365243` (application_train)

| Income type | Clients | With 365243 |
|---|---:|---:|
| Working | 158,774 | 0 |
| Commercial associate | 71,617 | 0 |
| Pensioner | 55,362 | 55,352 |
| State servant | 21,703 | 0 |
| Unemployed | 22 | 22 |
| Student | 18 | 0 |
| Businessman | 10 | 0 |
| Maternity leave | 5 | 0 |

Every one of the 55,374 clients with the placeholder is a pensioner or
unemployed: in `DAYS_EMPLOYED`, 365243 means **"not employed"**.

### Does it carry risk information?

| Group | Clients | Default rate |
|---|---:|---:|
| `DAYS_EMPLOYED = 365243` | 55,374 | 5.40% |
| Real employment length | 252,137 | 8.66% |

Clients with the placeholder default 38% less often (5.40 / 8.66 = 0.62). The information
must be kept, not discarded.

### Decision

See [decisions.md](decisions.md), decision 9: in the feature layer
`365243 → NULL`, plus an explicit flag (`is_not_employed`). The raw layer is
left unchanged.
