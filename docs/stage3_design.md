# Stage 3 design — the risk model

Approved 2026-09-25. Turns the 85 features of `feat_customer` (Stage 2) into a
**probability of default** for every client — the input of the decision
engine (Stage 4).

## In plain words

A lender wants to know, before saying yes: *how likely is this person to have
trouble repaying?* A model answers with a number between 0% and 100%.

We teach the model with past clients whose outcome is known (did they have
payment difficulties or not?), then check it on clients it has **never seen** —
like a student who is examined on questions that were not in the textbook.

We build two models and compare them:

| | Scorecard | Gradient boosting (LightGBM) |
|---|---|---|
| Idea | Points per answer, added up — like a quiz score | Hundreds of small yes/no decision trees voting together |
| Strength | Every point can be explained to a client or a regulator | Usually more accurate |
| Weakness | Usually a bit less accurate | Harder to explain |

The better one — judged on unseen clients — feeds the decision engine.

## 1. Data flow

```
Oracle: feat_customer (356,255 clients, 85 features)
   │  python-oracledb (password from Windows Credential Manager)
   ▼
Python: train the scorecard and LightGBM, compare, calibrate
   │
   ▼
Oracle: model_scores (one score and PD per client and model)
        ref_calibration + f_calibrate_pd   (improvement 2)
```

Oracle stays the single source of truth: Python reads features from it and
writes scores back to it. No CSV copies in between.

Python connects in *thin mode* (pure Python, no Oracle client needed) and
takes the password from Windows Credential Manager at the moment of
connecting (decision 15). `config/.env` holds only the user name, the
database address and the name of the stored entry — no password.

## 2. Validation

### The split

Only the **train** part of Kaggle's data (307,511 clients) has a known outcome.
It is split into three parts:

| Part | Share | Clients (≈) | Used for |
|---|---:|---:|---|
| `fit` | 70% | 215,000 | Learning |
| `valid` | 15% | 46,000 | Tuning and calibration |
| `holdout` | 15% | 46,000 | Final exam — used **once**, at the end |

Kaggle's **test** part (48,744 clients, no known outcome) is not used for
learning. It plays the role of *new applicants* in Stage 4, and it is used to
check score stability (below).

The split is made **in Oracle**, not in Python, with a hash of the client ID
(`ORA_HASH`): the same client always lands in the same part, on any machine,
with no random seed to remember. It is exposed as a column `split` in the
view `v_model_input` (all features + split), so SQL, Python, Dataiku and
Tableau all use exactly the same split.
A DQ check confirms the sizes and that the default rate is similar in all
three parts.

### Why no time-based test

Banks usually test a model on a *later* period than it learned from. The
Kaggle data has no application dates, so that is not possible here; this is
stated as a limitation in the model report.

### Measures

| Measure | Question it answers | Plain explanation |
|---|---|---|
| **Gini** | Does the model rank risky clients above safe ones? | 0 = coin toss, 1 = perfect. Credit models are typically 0.4–0.7 |
| **KS** | How well does the score separate the two groups? | Largest gap between the score distributions of good and bad clients |
| **Calibration table** | Is a "5%" really about 5%? | Clients are sorted into 10 groups; predicted vs actual default rate per group |
| **Brier score** | How close are the probabilities to reality overall? | Average squared error of the probability; lower is better |
| **PSI** | Do new applicants look like the clients the model learned from? | Population Stability Index; below 0.1 = stable |

## 3. Models

### 3a. Scorecard (logistic regression on WoE)

1. **Binning** — each feature is cut into up to 10 groups (e.g. age 21–25,
   26–30, …); missing values form their own group.
2. **WoE** (*weight of evidence*) — each group gets a number showing whether it
   has more or fewer defaults than average.
3. **IV** (*information value*) — one number per feature: how much it tells us
   about default. Features below 0.02 are dropped as uninformative.
4. Strongly correlated features are thinned out (keep the one with higher IV).
5. **Logistic regression** on the WoE values → points per group.

Result: a points table that can be printed on one page, and that can later be
scored in plain SQL.

### 3b. LightGBM

Uses the features directly (it handles missing values itself), except age
(decision 21). Its two main settings are chosen by 5-fold cross-validation
inside `fit` from 6 combinations declared in advance; the number of trees is
where the cross-validated result stops improving (*early stopping*), so it does
not memorise the training clients. `valid` is only used to measure the result.

**SHAP** values show which features drive each individual prediction, so the
more accurate model can still be explained.

### 3c. Choosing

Compared on `holdout`: Gini, KS, calibration. If the difference in Gini is
small (below about 0.02), the scorecard is preferred because it is easier to
explain and runs in SQL. The choice and its reason go into `decisions.md`.

## 4. Calibration (improvement 2)

A model's raw score is not yet a trustworthy probability. It is calibrated on
the `valid` part with a two-number formula:

```
PD = 1 / (1 + exp(-(a + b × raw_score)))
```

- `a` and `b` are stored in the table `ref_calibration` (one row per model
  version, with validity dates);
- the formula is written **once**, in the SQL function `f_calibrate_pd`;
- Python writes the calibration, SQL reads it — nowhere is the formula copied.

## 5. Fairness

Gender is not a feature (decision 13). **Age** is offered to the models like
any other feature (decision 17). The scorecard excluded it by itself: next to
the external score, employment length and income type, its weight pointed the
wrong way, meaning its information was already there.

A lender may still want an age limit — for example on age at the end of the
loan term. That is a **policy** choice, not a repayment-risk estimate (in this
data, older clients repay better), so it belongs in the decision engine as an
explicit rule with its own reason code (Stage 4, decision 20), never hidden in
the score.

## 6. Outputs

| Output | Where |
|---|---|
| Split (`v_model_input`) | `sql/03_features/08_model_split.sql`, run by `sql/run_stage3.sql` |
| Calibration table + function | `sql/04_reference/01_ref_calibration.sql` |
| Score table | `sql/01_ddl/04_model_scores.sql` |
| Reusable Python | `python/hcr/db.py` (connection), `woe.py`, `metrics.py` |
| One command that trains everything | `python/scripts/train_models.py` |
| The story with charts | `notebooks/03_model.ipynb` (also for Kaggle) |
| Model report (plain words + numbers) | `docs/model_report.md` |

## 7. Order of work

| Step | What | Why in this order |
|---|---|---|
| 3a | Python ↔ Oracle connection through the wallet | Everything else depends on it |
| 3b | Split column + DQ | Must exist before any learning |
| 3c | Quick look: default rate by key features | Sanity check, first charts |
| 3d | Scorecard | Simpler model first — the benchmark |
| 3e | LightGBM | Must beat the benchmark to be worth it |
| 3f | Holdout comparison, choice | The holdout is opened only here |
| 3g | Calibration, `ref_calibration`, `f_calibrate_pd`, scores to Oracle | Needs the chosen model |
| 3h | Model report | Last, from the final numbers |
