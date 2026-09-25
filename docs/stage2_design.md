# Stage 2 design — feature tables

Approved 2026-09-25. Turns the raw layer (Stage 1) into one row per client,
ready for the model (Stage 3) and the decision engine (Stage 4).

## 1. Grain

Every feature table has exactly **one row per client** (`SK_ID_CURR`).

Sources have different grains, so some are aggregated in two steps:

```
raw_bureau_balance   one bureau credit × one month
        │  step 1: aggregate per credit
        ▼
raw_bureau           one bureau credit
        │  step 2: aggregate per client
        ▼
feat_bureau          one client
```

Joining a finer-grained table directly to a coarser one multiplies rows and
silently inflates sums and counts. The grain of every source is measured
before any feature is built: [`sql/99_checks/03_grain_profiling.sql`](../sql/99_checks/03_grain_profiling.sql).

Two traps are documented by Kaggle itself:

- `previous_application` — "there could be more applications for one single
  contract" and "one application is in the database twice".
- `installments_payments` — one instalment can be paid in several rows.

## 2. Population

`application_train` (307,511) + `application_test` (48,744) = **356,255 clients**.

- **train** — known outcome (`TARGET`), used to fit and evaluate the model
- **test** — treated as incoming applicants; the decision engine is applied to them

Clients without history in a source still get a row (counts `0`, amounts `NULL`).

## 3. Feature tables

Naming: `<source prefix>_<what>_<aggregate>_<window>`,
e.g. `ins_late_share_12m` = instalments, share paid late, last 12 months.

| Table | Source | Measures | Main features |
|---|---|---|---|
| `feat_application` | application | the application itself | age, employment length + `is_not_employed` (decision 9), income, credit-to-income, annuity-to-income (relative burden — Kaggle does not state the period of the amounts), external scores |
| `feat_bureau` | bureau + bureau_balance | credits at **other lenders** | active credits, active debt, current overdue, worst status in the last 12 months and ever, bad-debt count |
| `feat_previous` | previous_application | **previous applications** at this lender | applications, approved, refused, refusal rate, applications in last 2 years |
| `feat_installments` | installments_payments | **repayment discipline** | instalments, share paid late, max days late, share underpaid |
| `feat_pos_cash` | POS_CASH_balance | POS and cash loan balances | max DPD, months with DPD, instalments left |
| `feat_credit_card` | credit_card_balance | **card behaviour** | utilisation, active months, payment-to-minimum ratio, max DPD |
| **`feat_customer`** | all of the above | model and decision input | all features + `target` + `dataset` (train / test) |

All thresholds are derived from this dataset; none are taken from any
organisation's internal rules.

## 4. Time windows

All time columns are relative to the application date. Two windows to start:

- `_12m` — last 12 months (current behaviour); for monthly sources, the 12 most
  recent months (`bureau_balance` 0 to -11, POS and card -1 to -12, see
  [data_profiling.md](data_profiling.md) section 4)
- `_all` — full history

More windows are added only if the model shows they help (Stage 3).

## 5. Engineering improvements applied in this stage

| # | Improvement | How |
|---|---|---|
| 6 | Row duplication cannot pass silently | After each feature table, `p_dq` and its helpers test uniqueness of `SK_ID_CURR`, row count = 356,255, value ranges and counts measured in profiling; results go to `dq_log`; a failed ERROR check stops the run |
| 8 | No misleading column names | Naming convention above + `COMMENT ON COLUMN` for every feature; `docs/data_dictionary.md` is generated from Oracle's column comments |
| 5 | History instead of truncate | `feat_customer` is kept per `snapshot_date` (partitioned if available — checked in section F of the grain profiling) |

## 6. Order of work

| Step | What | Why in this order |
|---|---|---|
| 2a | Grain profiling (read-only) | Design rests on measured facts |
| 2b | DQ tools: `dq_log`, `p_dq` | Every feature table is checked as soon as it is built |
| 2c | Six feature tables, DQ after each | Independent of each other |
| 2d | `feat_customer` + final DQ | Needs all six |
| 2e | Column comments → generated data dictionary | Once columns are stable |
| 2f | Snapshot history | Last, once `feat_customer` is correct |
