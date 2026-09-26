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
| 2. Policy rules | Does the client meet the eligibility rules? | `ref_rules` | `AGE_UNDER_MIN`, `CURRENT_ARREARS`, `AGE_AT_MATURITY` |
| 3. Risk | Is the PD at or below the cut-off? | `model_scores` + `ref_calibration` + `ref_rules` | `PD_ABOVE_CUTOFF` |
| 4. Limit | How much can be offered? | `ref_limit_grid` + `ref_rules` | — |
| 5. Affordability | Is that limit at least the minimum offer? | `ref_rules` | `DEBT_TOO_HIGH`, `LIMIT_BELOW_MIN` |

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

This is a standard hard stop; it shows how a list is kept and maintained as
data. Being **currently overdue** at another lender is handled as a policy
rule instead (`MAX_CURRENT_DPD`, reason `CURRENT_ARREARS`): it is a
threshold on today's state, not a permanent entry on a list (section 10).

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

- **Limit:** `ref_limit_grid` gives a maximum credit as a multiple of income
  per PD band and income band — lower risk and higher income, higher
  multiple.
- **Debt cap:** active debt at other lenders plus the new limit may not
  exceed `MAX_TOTAL_DEBT_TO_INCOME` × income. Debt is used rather than
  payments because bureau payments are mostly missing (decision 12).
  Negative bureau balances are counted as 0.
- **Offer** = the smallest of the grid limit, the room left by the debt cap
  and `MAX_LIMIT`. If it is below `MIN_LIMIT`, the client is declined:
  `DEBT_TOO_HIGH` when the debt cap is the problem, `LIMIT_BELOW_MIN` when the
  grid limit itself is too small (both are recorded if both apply).
- The grid check query must return zero gaps and zero overlaps, or the run
  stops (a DQ check).

## 5. Age (decision 20)

Age is not in the risk score. If an age limit is used, it is a rule in
`ref_rules` on **age at the end of the offered term**, with its own reason
code `AGE_AT_MATURITY`, so it is visible, configurable and reported
separately from risk.

## 6. The engine and its output

- One PL/SQL procedure `p_run_decisions(p_run_date)` reads the reference
  tables valid on `p_run_date` and writes all 356,255 decisions. It checks
  its inputs first (every rule present once, a calibration in force, every
  client scored) and writes everything in one transaction.
- `decisions` table, **partitioned by run date**: each run is kept, nothing
  is truncated (improvement **5**). Re-running a date replaces only that
  date's partition.
- Per client: decision, limit, PD, main reason, all reasons, and the facts
  the rules used (age, arrears, income, debt, grid multiple, which cap set
  the limit). `decision_reasons` holds the same reasons one per row.
- `decision_runs`: one row per run with the model version, the cut-off, all
  rules in force as text and a **rule-set fingerprint** (SHA-256 of rules,
  grid and reason codes), counts and status.
- DQ checks, written as separate queries that re-read the rules: every
  client decided once per run; every decline has a reason and the main
  reason is the highest-priority one; no approved client is excluded,
  breaks a policy rule, is above the cut-off, or has a limit above the grid,
  the debt cap or `MAX_LIMIT` or below `MIN_LIMIT`.

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

## 10. Changes made while building

| Step | Change | Why |
|---|---|---|
| 4a | Current arrears became a policy rule (`MAX_CURRENT_DPD`) instead of an exclusion-list entry | It is a threshold on today's state that can change at the next run, not a permanent entry on a list |
| 4a | Affordability measured as total debt to income (`MAX_TOTAL_DEBT_TO_INCOME`) instead of a payment share | Bureau payments are reported for only 22% of active credits, debt far more consistently (decision 12) |
| 4c | New reason code `LIMIT_BELOW_MIN` next to `DEBT_TOO_HIGH` | A client with no debt but a small income can also end below the minimum offer; "debt too high" would then be a wrong reason (decision 26) |
