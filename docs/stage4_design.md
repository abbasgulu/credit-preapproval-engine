# Stage 4 design — the decision engine

Approved 2026-09-25 (decision 25). Turns every client's calibrated PD (Stage 3) into a
pre-approval decision: **yes or no, up to what limit, and why**.

## In plain words

The model says how risky a client is. A lender still has to decide what to
do with that: who gets an offer, how large, and — just as important — the
reason, so that a declined client, an auditor or a colleague can see why.

In many legacy pipelines these rules are buried in code: lists of excluded
clients typed into procedures, thresholds scattered over many scripts, limit
tables written as long `CASE` statements, and reasons reconstructed later in
reports. Here every rule is **data in a table**, the engine only reads the
tables, and every decision is stored **with its reason at the moment it is
made**.

All numbers in this stage are illustrative choices for a public dataset and
are documented as such. None is taken from any lender's internal policy.

## 1. How a decision is made

Each client passes the same steps, in this order. The first step that stops
a client gives the main reason; later steps still run so that *all* reasons
are recorded.

| Step | Question | Source | Example reason code |
|---|---|---|---|
| 1. Exclusions | Is the client on an exclusion list? | `ref_exclusion_list` | `EXCL_WRITTEN_OFF` |
| 2. Policy rules | Does the client meet the eligibility rules? | `ref_rules` | `AGE_AT_MATURITY`, `CURRENT_ARREARS` |
| 3. Risk | Is the PD below the cut-off? | `v_scores` + `ref_rules` | `PD_ABOVE_CUTOFF` |
| 4. Affordability | Would the payment fit the income? | `ref_rules` | `PAYMENT_TOO_HIGH` |
| 5. Limit | How much can be offered? | `ref_limit_grid` | — |

Result per client: `APPROVE` with a limit, or `DECLINE` with a main reason
and the full list of reasons.

## 2. Reference tables (the rules as data)

| Table | Holds | Improvement |
|---|---|---|
| `ref_exclusion_list` | Clients excluded, with reason code and validity dates | **1** — lists as data, not code |
| `ref_rules` | Named parameters (cut-off, age limit, maximum payment share...) with validity dates | **4** — thresholds in one place |
| `ref_limit_grid` | Limit by PD band × income band, as lower/upper bounds | **3** — plus a check query that finds gaps and overlaps |
| `ref_reason_codes` | Every reason code with a plain-words description | **9** |

Changing a rule = updating a row (with a new validity date), never editing
code. Old rows stay, so any past decision can be explained with the rules
that were valid on that day.

### Exclusion list: from the data, not invented

The Kaggle data has no fraud or blacklist. Instead of inventing one, the
list is built from facts in the data, each with its own reason code:

- a credit at another lender was **written off or sold** (`bur_bad_status_cnt > 0`)
- the client is **currently overdue** at another lender (`bur_current_dpd_max > 0`)

These are standard hard stops; they show how a list is kept and maintained
as data.

## 3. Choosing the PD cut-off

The cut-off decides how many clients get an offer and how many of them will
later have trouble. It is chosen on the `valid` clients (the holdout is only
reported on), and written to `ref_rules`, just like the calibration numbers.

**Rule chosen:** the highest cut-off at which the default rate among approved
`valid` clients stays at or below `TARGET_BAD_RATE` (5%).

A trade-off table and chart are produced either way: for every possible
cut-off, the approval rate and the expected default rate among approved
clients.

## 4. Limits and affordability

- **Affordability:** the annuity of the offered credit may take at most a set
  share of income (`MAX_PAYMENT_SHARE` in `ref_rules`). Kaggle does not state
  the period of the amounts, so this is a relative measure, as in Stage 2.
- **Limit:** `ref_limit_grid` gives a maximum credit as a multiple of income
  per PD band — lower risk, higher multiple — capped by affordability.
- The grid check query must return zero gaps and zero overlaps, or the run
  stops (a DQ check).

## 5. Age (decision 20)

Age is not in the risk score. If an age limit is used, it is a rule in
`ref_rules` on **age at the end of the offered term**, with its own reason
code `AGE_AT_MATURITY`, so it is visible, configurable and reported
separately from risk.

## 6. The engine and its output

- One PL/SQL procedure `p_run_decisions(p_run_date)` reads the reference
  tables valid on `p_run_date` and writes all 356,255 decisions.
- `decisions` table, **partitioned by run date**: each run is kept, nothing
  is truncated (improvement **5**). Re-running a date replaces only that
  date's partition.
- Per client: decision, limit, PD, main reason, all reasons, rule-set
  version, run date.
- DQ checks: every client decided once per run; every decline has a reason;
  no approval above the limit grid; approvals only below the cut-off.

## 7. Evaluation

On the `holdout` clients (known outcome, report only):

- approval rate and actual default rate among approved vs declined
- declines by main reason
- the same for the `test` clients (outcome unknown): expected default rate
  from the calibrated PD

A dashboard-ready view `v_decision_summary` feeds Tableau (Stage 6).

## 8. Choices made (decision 25)

1. **Cut-off rule:** default rate among approved clients at most 5% (the
   trade-off table also shows fixed approval rates and other targets).
2. **Age rule:** age at the end of a 24-month offer at most 70 (illustrative).
3. **Reasons for risk declines:** `PD_ABOVE_CUTOFF` plus the 3 facts that
   raised the client's risk most (SHAP), in plain words.

## 9. Order of work

| Step | What |
|---|---|
| 4a | Reference tables, seed rows, grid check |
| 4b | Cut-off analysis on `valid` → `ref_rules` |
| 4c | `p_run_decisions`, partitioned `decisions` table, DQ checks |
| 4d | Evaluation on `holdout` and `test`, `v_decision_summary` |
| 4e | SHAP reasons per client (top 3 risk-raising facts) |
