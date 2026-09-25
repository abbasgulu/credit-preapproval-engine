# Data profiling

Facts measured on the raw layer before design decisions were made.
All numbers can be reproduced with
[`sql/99_checks/02_raw_profiling.sql`](../sql/99_checks/02_raw_profiling.sql) (sections 1–3) and
[`sql/99_checks/03_grain_profiling.sql`](../sql/99_checks/03_grain_profiling.sql) (section 4).

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

## 4. Grain: what one row means

Feature tables aggregate many source rows into one row per client. If a source
has more rows than its key suggests, sums and counts are silently inflated,
so the grain of every source was measured before any feature was built.

### Rows vs distinct keys

| Table | Expected key | Rows | Distinct keys | Extra rows |
|---|---|---:|---:|---:|
| `raw_application_train` | `SK_ID_CURR` | 307,511 | 307,511 | 0 |
| `raw_application_test` | `SK_ID_CURR` | 48,744 | 48,744 | 0 |
| `raw_bureau` | `SK_ID_BUREAU` | 1,716,428 | 1,716,428 | 0 |
| `raw_bureau_balance` | `SK_ID_BUREAU` + `MONTHS_BALANCE` | 27,299,925 | 27,299,925 | 0 |
| `raw_previous_application` | `SK_ID_PREV` | 1,670,214 | 1,670,214 | 0 |
| `raw_installments_payments` | `SK_ID_PREV` + version + instalment number | 13,605,401 | 12,951,918 | **653,483** |
| `raw_pos_cash_balance` | `SK_ID_PREV` + `MONTHS_BALANCE` | 10,001,358 | 10,001,358 | 0 |
| `raw_credit_card_balance` | `SK_ID_PREV` + `MONTHS_BALANCE` | 3,840,312 | 3,840,312 | 0 |

Train and test share no clients (0 overlap).

### Instalments paid in several rows

| Payment rows per instalment | Instalments |
|---:|---:|
| 1 | 12,311,013 |
| 2 | 629,210 |
| 3 | 11,000 |
| 4 | 578 |
| 5–12 | 117 |

2,905 rows have no payment recorded (`AMT_PAYMENT` and `DAYS_ENTRY_PAYMENT`
both empty). → [decision 10](decisions.md): aggregate per instalment first.

### Repeated previous applications

| Flag | Value | Rows |
|---|---|---:|
| `FLAG_LAST_APPL_PER_CONTRACT` | N (not the last application for its contract) | 8,475 |
| `NFLAG_LAST_APPL_IN_DAY` | 0 (not the last application that day) | 5,900 |

→ [decision 11](decisions.md): keep only the last application.

### Coverage of the 356,255 clients

| Source | Clients with history | Share |
|---|---:|---:|
| `installments_payments` | 339,587 | 95.3% |
| `previous_application` | 338,857 | 95.1% |
| `pos_cash_balance` | 337,252 | 94.7% |
| `bureau` | 305,811 | 85.8% |
| `bureau_balance` (via bureau) | 134,542 | 37.8% |
| `credit_card_balance` | 103,558 | 29.1% |

Clients without history still get a row in every feature table, with a
`*_has_history` flag, so "no history" is visible to the model instead of
being mixed up with "history with zero problems".

43,041 `SK_ID_BUREAU` values in `bureau_balance` have no matching credit in
`bureau`; they cannot be linked to a client and are ignored.

### Value lists

| Column | Values (rows) |
|---|---|
| `bureau.CREDIT_ACTIVE` | Closed 1,079,273 · Active 630,607 · Sold 6,527 · Bad debt 21 |
| `bureau_balance.STATUS` | C 13,646,993 · 0 7,499,507 · X 5,810,482 · 1 242,347 · 5 62,406 · 2 23,419 · 3 8,924 · 4 5,847 |
| `previous_application.NAME_CONTRACT_STATUS` | Approved 1,036,781 · Canceled 316,319 · Refused 290,678 · Unused offer 26,436 |

Status codes: C = closed, X = unknown, 0 = no days past due, 1–5 = DPD buckets
(1 = 1–30 days … 5 = over 120 days or written off). Sold and Bad debt are
merged into one count because Bad debt has only 21 rows.

### Month ranges

| Source | Earliest month | Latest month |
|---|---:|---:|
| `bureau_balance` | -96 | **0** |
| `pos_cash_balance` | -96 | -1 |
| `credit_card_balance` | -96 | -1 |

Because `bureau_balance` includes month 0, its "last 12 months" window is
months 0 to -11; for the other two sources it is -1 to -12.

### Bureau annuities

| Active bureau credits | Annuity empty | Annuity zero | Usable |
|---:|---:|---:|---:|
| 630,607 | 431,549 | 59,259 | 22.2% |

→ [decision 12](decisions.md): burden measured as debt / income.

### Partitioning

Available in this Oracle 18c XE installation (tested by creating and
dropping a small partitioned table). Needed for snapshot history (Stage 2f).
