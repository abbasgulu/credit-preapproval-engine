# Stage 5 — the whole pipeline with one command

Built 2026-10-02 (decision 31). This stage was first planned in Dataiku; see
"Why not Dataiku" below.

## In plain words

The project is a chain of steps: load the data, build the features, score
every client, run the decision engine, explain the declines, write the
dashboard files. Each step already checks itself and stops on a problem.
`python/scripts/run_pipeline.py` runs the steps in the right order, stops at
the first one that fails, and keeps everything every step printed in one log
file — so a run can be repeated by anyone and inspected afterwards.

## How to run

From the repository root:

```bat
python python\scripts\run_pipeline.py                 :: daily run
python python\scripts\run_pipeline.py --mode full     :: everything from the raw files
python python\scripts\run_pipeline.py --list          :: show the steps, run nothing
python python\scripts\run_pipeline.py --from explain  :: resume after a failed step
```

The log of every run is written to `logs\pipeline_<date>_<time>.log` (not
committed). No password is involved: SQL*Plus connects through the Oracle
Wallet and Python through Windows Credential Manager, exactly as when each
step is run by hand.

## The steps

| Step | What it does | Runner | Mode |
|---|---|---|---|
| `check_data` | raw Kaggle files are complete | `check_data.py` | full |
| `load` | Stage 1: raw tables loaded from the files | `run_stage1.sql` | full |
| `features` | Stage 2: feature table and its data-quality checks | `run_stage2.sql` | full |
| `split` | Stage 3: fit / valid / holdout split, score tables | `run_stage3.sql` | full |
| `scores` | calibrated scores for every client | `calibrate_and_score.py` | full |
| `scores_check` | Oracle and Python compute the same PD | `05_model_scores.sql` | full |
| `reference` | rules, reasons, limit grid, engine code | `run_stage4.sql` | full |
| `decisions` | decision engine for today and its 12 checks | `run_decisions.sql` | daily, full |
| `evaluate` | evaluation; Python recomputes every decision | `evaluate_decisions.py` | daily, full |
| `explain` | the three facts behind each risk decline | `explain_decisions.py` | daily, full |
| `export` | dashboard files, reconciled with the run | `export_tableau.py` | daily, full |

**Never run by the pipeline, on purpose:** training the models, the one-time
holdout exam and choosing the PD cut-off. Each is a decision with a date and
a reason, made once by a person (decisions 16, 23, 25) — not something a
schedule should repeat.

**Before anything starts** the pipeline checks that every script exists,
that `sqlplus` is installed, that `config\.env` and the model file are in
place. **After a successful run** it reads back from Oracle what the run
produced: the decision run and every data-quality check it logged.

## First run (2026-10-02, daily mode)

| Step | Result | Time |
|---|---|---|
| decisions | 356,255 decisions, 12 of 12 checks passed | 35 s |
| evaluate | 0 differences between Python and the engine | 7 s |
| explain | three facts for every risk decline, SHAP adds up exactly | 36 s |
| export | 11 of 11 reconciliation checks passed | 8 s |

All 4 steps passed in 1.4 minutes. Run 21 approved 233,377 clients (65.5%) —
exactly as many as the run of 2026-09-26 with the same rules and model: the
result is reproducible.

## Why not Dataiku

Dataiku DSS Free Edition was installed, but its registration server refused
the licence request (HTTP 403). A Dataiku Community member explained that free
registrations are blocked from some countries, without a published list.
Working around that block (for example through a VPN) would break Dataiku's
terms, so the orchestration was built in Python instead. The design goals of
the Dataiku plan are kept: every step is one named script, run in a fixed
order, logic stays in Oracle, and every step proves its own result.
