# Dashboard data (Tableau Public)

## In plain words

The dashboard reads only the small summary files in `data/`. They are written
by `python/scripts/export_tableau.py` from the latest run of the decision
engine, and they add up exactly to that run (the script checks this before it
writes anything). No file contains a client ID or any single client's data;
where a row describes fewer than 10 clients, its count is kept but its rates
are hidden (`suppressed = 1`).

Tableau opens **`data/dashboard_data.xlsx`**: the same ten tables, one sheet
each. The CSV files hold identical content and are there to be read on GitHub.

Rebuild the files (from the repository root):

```bat
python python\scripts\export_tableau.py
```

Design of the pages: [docs/stage6_design.md](../docs/stage6_design.md).

## The workbook

Live version: [Credit Pre-Approval Engine on Tableau Public](https://public.tableau.com/views/CreditPre-ApprovalEngine/1-Ataglance).

`credit_preapproval.twb` holds the four dashboard pages and reads
`data/dashboard_data.xlsx`. Open it in Tableau Public (free). The workbook
remembers where the Excel file was on the computer it was built on; on another
computer Tableau asks for the file once — point it to `tableau/data/dashboard_data.xlsx`.
After a new run of the engine: run the export, open the workbook and choose
**Data → (each data source) → Refresh**.

## Words used in the columns

| Word | Meaning |
|---|---|
| `split` | Group of clients: `fit` (model learned here), `valid` (cut-off chosen here), `holdout` (final exam, never used for a choice), `test` (outcome unknown, treated as new applicants) |
| `approval_rate` | Share of clients pre-approved |
| `bad_rate_approved` / `default_rate` | Share of clients who later had repayment trouble (known outcome only; empty for `test`) |
| `expected_bad_rate_approved` / `avg_pd` | Trouble the model expects: the average calibrated PD |
| `trouble_avoided` | Share of all repayment trouble that fell on declined clients |
| `suppressed` | 1 = fewer than 10 clients: rates hidden, count kept |

## The files

| File | One row per | Main columns |
|---|---|---|
| `run_info.csv` | the run | `run_id`, `run_date`, `model`, `pd_cutoff`, `target_bad_rate`, `debt_rule_multiple`, `min_limit`, `max_limit`, `ruleset_hash`, `clients`, `approved` |
| `kpi_by_split.csv` | group | `clients`, `approved`, `declined`, `approval_rate`, `bad_rate_approved`, `bad_rate_declined`, `expected_bad_rate_approved`, `trouble_avoided`, `avg_limit`, `total_limit` |
| `outcomes.csv` | group × outcome | `outcome` (`APPROVED` or the main reason code), `outcome_label` (short name), `outcome_description` (full sentence), `outcome_category`, `outcome_order`, `clients`, `share_of_split`, `default_rate`, `avg_pd`, `avg_limit` — from the Oracle view `v_decision_summary` |
| `reasons_all.csv` | group × reason | `reason_code`, `description` (short name), `full_description` (full sentence), `category`, `clients` (a client can have several reasons), `share_of_split` |
| `risk_facts.csv` | fact | `short_label`, `clients_in_top3`, `clients_first`, `share_in_top3`, `share_first`, `explained_clients` |
| `pd_distribution.csv` | group × PD band of 1 point (40% and above in one band) | `pd_from`, `pd_band`, `clients`, `approved`, `approval_rate`, `default_rate`, `avg_pd` |
| `grid_cells.csv` | cell of the limit grid | `pd_band`, `income_band`, `income_multiple`, `clients`, `approved`, `approval_rate`, `avg_limit`, `default_rate` |
| `limit_distribution.csv` | group × band of 100,000 (approved clients) | `limit_from`, `limit_band`, `clients` |
| `limit_basis.csv` | cap that set the limit | `limit_basis_label`, `clients`, `avg_limit`, `min_limit`, `max_limit` |
| `debt_rule.csv` | group × debt-rule value | `debt_rule` (3–10 × income or none; `debt_multiple` 99 = none), `in_force`, `approval_rate`, `bad_rate_approved`, `expected_bad_rate_approved`, `avg_limit`, `declined_by_debt_rule` |

All numbers come from a public dataset and illustrative rules; none is taken
from any lender's policy.
