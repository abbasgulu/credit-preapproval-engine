# Stage 6 design — the dashboard (Tableau Public)

Choices made 2026-09-27 (decision 29). The export is the last step of the
pipeline (Stage 5, decision 31).

## In plain words

Everything the project found is in tables and documents. A dashboard shows
the same results as a few interactive pages that anyone can open in a browser:
how many clients are pre-approved, why the others are declined, how risk and
limits relate, and what a looser or stricter debt rule would change.

## 1. Tool and what is published

- **Tableau Public** (free) on the personal computer. It reads files, not
  Oracle, and whatever is published there is visible to everyone.
- So Tableau gets **only summary files**: counts, rates and averages per group,
  written by `python/scripts/export_tableau.py` into `tableau/data/`: CSV
  files to read on GitHub, and the same tables as one Excel file
  (`dashboard_data.xlsx`, a sheet per table) that Tableau opens — Tableau
  misread the CSV separators when labels contained commas. No file holds a
  client ID or a single client's data.
- **Small groups:** in the distribution files, a row about fewer than 10
  clients keeps its count but its rates are hidden (`suppressed = 1`).
- **Reconciliation:** the export adds every file back up to the engine's run
  (356,255 clients and the approvals of that run, per group) and writes nothing
  if any total differs.
- Language: English, like the repository.

## 2. The data files

| File | One row per | Used on page |
|---|---|---|
| `run_info.csv` | the run (date, model, cut-off, rule-set fingerprint) | all (footer) |
| `kpi_by_split.csv` | group of clients | 1 |
| `outcomes.csv` | group × outcome (approved or main reason) | 1, 2 |
| `reasons_all.csv` | group × reason (all reasons) | 2 |
| `risk_facts.csv` | fact named behind a risk decline | 2 |
| `pd_distribution.csv` | group × 1-point PD band | 3 |
| `grid_cells.csv` | cell of the limit grid | 3 |
| `limit_distribution.csv` | group × limit band of 100,000 | 3 |
| `limit_basis.csv` | which cap set the limit | 3 |
| `debt_rule.csv` | group × debt-rule value | 4 |

Column meanings: [tableau/README.md](../tableau/README.md).

## 3. The pages (as built)

A **Group** selector (fit / valid / holdout / test, default **holdout** — the
clients never used for any choice) sits at the top right of every page and
changes every chart that has a group at once. Titles state the finding in a few
words; numbers are written on the bars, so most axes are hidden.

**Page 1 — At a glance**
- Tiles: pre-approved, trouble among approved and among declined, share of
  trouble avoided, average limit
- Bar: pre-approved per group — the same rules give the same result everywhere

**Page 2 — Why clients are declined**
- Main reason per declined client (colour = category)
- Repayment trouble per outcome, with the group average as a dashed line:
  risk declines have about 5× the trouble of approved clients, debt-rule declines
  about the same as approved
- Every reason that applied (a client can have several)
- The 10 facts most often among the top 3 reasons of a risk decline (all groups)

**Page 3 — Risk and limits**
- Pre-approved per 1-point PD band: approvals stop at the cut-off
- Repayment trouble per PD band: trouble rises with the predicted risk
- The limit grid as a heat map: income multiple per PD band × income band,
  darker = more pre-approved (all clients)
- Approved limits in bands of 100,000

**Page 4 — What if the debt rule were different**
- For 3, 4, 5, 6, 8, 10 × income and no rule: pre-approved, trouble among
  approved, clients the rule declines; the rule in force (5 × income) in blue
- Holdout: without the rule approvals rise from 65.6% to 80.2% while trouble
  among approved moves only from 4.72% to 4.78% — the rule protects
  affordability, not risk (decision 27)

Every page ends with the run footer: run date, model, cut-off, rule-set
fingerprint, "public Kaggle data, all rules illustrative".

## 4. Look

- Colours by meaning, the same on every page: approved **#2a78d6** (blue),
  risk **#eb6834** (orange), affordability **#1baf7a** (aqua), policy
  **#eda100** (yellow), exclusion **#e87ba4** (magenta); values are labelled on
  the bars, so colour is never the only clue
- Heat map: one blue from light to dark (more approved = darker)
- One number format per measure: rates as % with one decimal, amounts with a
  thousands separator
- Titles state the finding ("Declined clients had 3× the trouble of approved"),
  subtitles say what is shown

## 5. Order of work

| Step | What |
|---|---|
| 6a | `export_tableau.py`: the summary files, reconciled — done |
| 6b | Install Tableau Public, open the files, check the totals against the run — done |
| 6c | Build pages 1–4 — done 2026-10-02 |
| 6d | Publish to Tableau Public — done 2026-10-02: [Credit Pre-Approval Engine](https://public.tableau.com/views/CreditPre-ApprovalEngine/1-Ataglance); the workbook is in the repository as `tableau/credit_preapproval.twb` |

## 6. Changes made while building

- **One Group selector for all pages** (a Tableau parameter) instead of a
  filter per chart: each data source has a field `In chosen group`, so one
  choice changes every page.
- **Short reason names** (`Debt too high`, `Risk above cut-off`, …) written by
  `export_tableau.py`; the full sentence stays in the files
  (`outcome_description`, `full_description`). New columns are added at the
  end of a table, because Tableau reads Excel columns by position.
- **Fewer words on screen:** one-line titles that state the finding, one
  short subtitle, numbers on the bars instead of axes.
- `limit_basis` (which cap set the limit) stays in the data files but has no
  chart: the limit histogram and grid already tell that story.
- Page 4 shows every debt-rule value side by side (three bar charts) instead of
  a selector with tiles: all values can be compared at a glance.
