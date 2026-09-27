# Stage 6 design — the dashboard (Tableau Public)

Choices made 2026-09-27 (decision 29). Stage 5 (Dataiku) waits for Dataiku's
answer on the Free Edition registration; nothing here depends on it.

## In plain words

Everything the project found is in tables and documents. A dashboard shows
the same results as a few interactive pages that anyone can open in a browser:
how many clients are pre-approved, why the others are declined, how risk and
limits relate, and what a looser or stricter debt rule would change.

## 1. Tool and what is published

- **Tableau Public** (free) on the personal computer. It reads files, not
  Oracle, and whatever is published there is visible to everyone.
- So Tableau gets **only summary files**: counts, rates and averages per group,
  written by `python/scripts/export_tableau.py` into `tableau/data/`. No file
  holds a client ID or a single client's data.
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

## 3. The pages

A **group filter** (valid / holdout / test; fit available) sits at the top of
pages 1–3, default **holdout** — the clients never used for any choice.

**Page 1 — At a glance**
- Tiles: approved %, repayment trouble among approved and among declined,
  share of all trouble avoided, average limit (test: expected trouble = average PD)
- Bar: approval rate per group — the same rules give the same result everywhere
- Footer: run date, model, cut-off, rule-set fingerprint; "all numbers are illustrative"

**Page 2 — Why declined**
- Bar: clients per main reason, coloured by category (exclusion, policy, risk, affordability)
- Bar: repayment trouble per outcome, with the group's average as a line
- Bar: every reason that applied (a client can have several)
- Bar: the 10 facts most often behind a risk decline (share of risk declines)

**Page 3 — Risk and limits**
- Histogram: clients per PD band, approved vs declined, cut-off as a line
- Line (separate chart, same PD axis): repayment trouble per PD band
- Heat map: the limit grid — PD band × income band, cell text = income multiple,
  colour = approval rate
- Histogram: approved limits; bar: which cap set the limit

**Page 4 — What if the debt rule were different**
- A selector (parameter) for the debt rule: 3, 4, 5, 6, 8, 10 × income or none
- Tiles for the chosen value next to the rule in force: approved %, trouble
  among approved, average limit, clients declined by the debt rule
- Chart: approved % against trouble among approved for every value, the chosen
  one highlighted, the 5% target as a line
- Note: the rule stays at 5 × income (decision 27) and why

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
| 6a | `export_tableau.py`: the summary files, reconciled |
| 6b | Install Tableau Public, open the files, check the totals against the run |
| 6c | Build pages 1–4 |
| 6d | Publish to Tableau Public; save the workbook (`tableau/credit_preapproval.twbx`) and screenshots in the repository; link from the README |
