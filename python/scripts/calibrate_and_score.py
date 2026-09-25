"""Stage 3g: calibrate both models and write every client's score to Oracle.

In plain words: a model says "this client has a 5% chance of trouble". For
that number to be used in decisions — limits, prices, cut-offs — a group of
clients labelled "5%" must really have about 5% with trouble. Calibration
adjusts the model's output with two numbers (a, b) so that this holds.

  - a and b are learned on the `valid` clients (never on `fit`, where the
    model is over-confident because it learned from them; never on
    `holdout`, which is only reported on, not used for any choice)
  - a and b go to the Oracle table ref_calibration; the formula is the
    Oracle function f_calibrate_pd (improvement 2: written once)
  - every client's raw score goes to model_scores; v_scores turns it into
    a calibrated PD. The PD Python computed is stored alongside, and
    sql/99_checks/05_model_scores.sql proves both engines agree

Before running: sqlplus /nolog @sql\\run_stage3.sql   (creates the tables)
After running:  sqlplus /nolog @sql\\99_checks\\05_model_scores.sql

Output:
  Oracle: ref_calibration (2 rows), model_scores (2 x 356,255 rows)
  docs/calibration.md          results in readable form (generated)
  docs/img/3g_calibration.png  predicted vs actual, before and after

Run from the repository root:
    python python\\scripts\\calibrate_and_score.py
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # makes "import hcr" work

import matplotlib  # noqa: E402

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import oracledb  # noqa: E402
import pandas as pd  # noqa: E402
from sklearn.linear_model import LogisticRegression  # noqa: E402

from hcr.db import connect, read_sql  # noqa: E402
from hcr.metrics import brier, calibration_table, gini  # noqa: E402
from hcr.scoring import (lightgbm_raw, load_lightgbm, load_scorecard,  # noqa: E402
                         scorecard_raw, to_pd)

ROOT = Path(__file__).resolve().parents[2]
BATCH = 50_000
SURFACE, TEXT, TEXT_2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e1e0d9"
BEFORE, AFTER = "#86b6ef", "#1c5cab"     # one hue, light = before, dark = after (sequential steps 250 / 550)


def fit_calibration(raw: np.ndarray, y: np.ndarray) -> tuple[float, float]:
    """Platt scaling: logistic regression of the outcome on the raw score -> (a, b)."""
    lr = LogisticRegression(C=1e9, max_iter=1000).fit(raw.reshape(-1, 1), y)   # huge C = practically no penalty
    return float(lr.intercept_[0]), float(lr.coef_[0, 0])


def write_scores(con, name: str, version: int, df: pd.DataFrame, raw: np.ndarray, pd_cal: np.ndarray) -> None:
    """Replace this model version's rows (a rerun gives the same result) and insert all clients."""
    with con.cursor() as cur:
        cur.execute("DELETE FROM model_scores WHERE model_name = :1 AND model_version = :2", [name, version])
        cur.setinputsizes(None, None, None, None, oracledb.DB_TYPE_BINARY_DOUBLE, oracledb.DB_TYPE_BINARY_DOUBLE)
        rows = list(zip([name] * len(df), [version] * len(df), df.sk_id_curr.astype(int).tolist(),
                        df.split.tolist(), raw.astype(float).tolist(), pd_cal.astype(float).tolist()))
        sql = ("INSERT INTO model_scores (model_name, model_version, sk_id_curr, split, raw_score, pd_check, scored_at) "
               "VALUES (:1, :2, :3, :4, :5, :6, SYSTIMESTAMP)")
        for i in range(0, len(rows), BATCH):
            cur.executemany(sql, rows[i:i + BATCH])
    con.commit()


def write_calibration(con, name: str, version: int, a: float, b: float) -> None:
    with con.cursor() as cur:
        cur.setinputsizes(None, None, oracledb.DB_TYPE_BINARY_DOUBLE, oracledb.DB_TYPE_BINARY_DOUBLE)
        cur.execute("""
            MERGE INTO ref_calibration t
            USING (SELECT :1 AS model_name, :2 AS model_version, :3 AS coef_a, :4 AS coef_b FROM dual) s
            ON (t.model_name = s.model_name AND t.model_version = s.model_version)
            WHEN MATCHED THEN UPDATE SET t.coef_a = s.coef_a, t.coef_b = s.coef_b, t.created_at = SYSTIMESTAMP
            WHEN NOT MATCHED THEN INSERT (model_name, model_version, coef_a, coef_b, fitted_on, valid_from, created_at)
                 VALUES (s.model_name, s.model_version, s.coef_a, s.coef_b,
                         'v_model_input split = valid (46,342 clients)', TRUNC(SYSDATE), SYSTIMESTAMP)""",
                    [name, version, a, b])
    con.commit()


def main() -> None:
    start = time.perf_counter()
    card = load_scorecard()
    booster, meta = load_lightgbm()
    df = read_sql("SELECT * FROM v_model_input").reset_index(drop=True)
    print(f"{len(df):,} clients read ({time.perf_counter() - start:.0f} s)\n")

    raws = {"lightgbm": lightgbm_raw(booster, meta, df), "scorecard": scorecard_raw(card, df)}
    versions = {"lightgbm": meta["version"], "scorecard": card["version"]}
    valid, holdout = (df.split == "valid").to_numpy(), (df.split == "holdout").to_numpy()
    y = df.target.to_numpy()

    report = {}
    with connect() as con:
        for name, raw in raws.items():
            a, b = fit_calibration(raw[valid], y[valid])
            pd_raw, pd_cal = to_pd(raw), to_pd(raw, a, b)
            write_calibration(con, name, versions[name], a, b)
            write_scores(con, name, versions[name], df, raw, pd_cal)
            report[name] = {
                "a": a, "b": b,
                "valid": {"actual": y[valid].mean(), "raw": pd_raw[valid].mean(), "cal": pd_cal[valid].mean(),
                          "brier_raw": brier(y[valid], pd_raw[valid]), "brier_cal": brier(y[valid], pd_cal[valid])},
                "holdout": {"actual": y[holdout].mean(), "raw": pd_raw[holdout].mean(), "cal": pd_cal[holdout].mean(),
                            "brier_raw": brier(y[holdout], pd_raw[holdout]),
                            "brier_cal": brier(y[holdout], pd_cal[holdout]),
                            "gini": gini(y[holdout], pd_cal[holdout])},
                "table_raw": calibration_table(y[holdout], pd_raw[holdout]),
                "table_cal": calibration_table(y[holdout], pd_cal[holdout]),
            }
            print(f"{name:<10} a = {a:+.4f}, b = {b:.4f}  ->  {len(df):,} scores written to Oracle "
                  f"({time.perf_counter() - start:.0f} s)")

    draw(report["lightgbm"])
    write_markdown(report)

    print("\n===== Calibration (holdout: reported only, not used for any choice) =====")
    print(f"{'model':<10} {'part':<8} {'actual':>7} {'PD before':>10} {'PD after':>9} {'Brier before':>13} {'Brier after':>12}")
    for name, r in report.items():
        for part in ("valid", "holdout"):
            m = r[part]
            print(f"{name:<10} {part:<8} {100 * m['actual']:6.2f}% {100 * m['raw']:9.2f}% {100 * m['cal']:8.2f}% "
                  f"{m['brier_raw']:13.5f} {m['brier_cal']:12.5f}")
    print(f"\nRanking is unchanged by calibration: LightGBM holdout Gini {report['lightgbm']['holdout']['gini']:.3f}")
    print("\nNext: sqlplus /nolog @sql\\99_checks\\05_model_scores.sql")
    print("\n===== 3g COMPLETE =====")


def draw(r: dict) -> None:
    raw_t, cal_t = r["table_raw"], r["table_cal"]
    fig, ax = plt.subplots(figsize=(7.5, 6.2), dpi=150)
    fig.patch.set_facecolor(SURFACE)
    ax.set_facecolor(SURFACE)
    top = 100 * max(raw_t.predicted.max(), raw_t.actual.max(), cal_t.predicted.max()) * 1.08
    ax.plot([0, top], [0, top], color=TEXT_2, linewidth=1, linestyle=(0, (4, 3)), zorder=1)
    for t, colour, label in ((raw_t, BEFORE, "Before calibration"), (cal_t, AFTER, "After calibration")):
        ax.plot(100 * t.predicted, 100 * t.actual, color=colour, linewidth=2, marker="o", markersize=7,
                markeredgecolor=SURFACE, markeredgewidth=2, label=label, zorder=3)
    ax.set_xlim(0, top)
    ax.set_ylim(0, top)
    ax.set_xlabel("Predicted PD (average of each tenth of clients)", fontsize=9.5, color=TEXT_2)
    ax.set_ylabel("Actual share with repayment trouble", fontsize=9.5, color=TEXT_2)
    for axis in (ax.xaxis, ax.yaxis):
        axis.set_major_locator(matplotlib.ticker.MaxNLocator(nbins=6, steps=[1, 2, 5, 10], integer=True))
        axis.set_major_formatter(matplotlib.ticker.PercentFormatter(decimals=0))
    ax.tick_params(axis="both", length=0, labelsize=8.5, colors=TEXT_2)
    ax.grid(color=GRID, linewidth=0.8, zorder=0)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(GRID)
    ax.legend(frameon=False, fontsize=9, loc="upper left")
    ax.set_title("Does a predicted 10% mean 10%? (LightGBM)", loc="left", fontsize=12.5, color=TEXT,
                 fontweight="bold", pad=24)
    ax.text(0, 1.015, "Holdout clients in ten groups by predicted PD. Points on the dashed line = honest probabilities.",
            transform=ax.transAxes, fontsize=8, color=TEXT_2, va="bottom")
    fig.tight_layout()
    fig.savefig(ROOT / "docs" / "img" / "3g_calibration.png", facecolor=SURFACE)
    plt.close(fig)


def write_markdown(report: dict) -> None:
    lines = [
        "# Calibration (Stage 3g)",
        "",
        "_Generated by `python/scripts/calibrate_and_score.py`. Do not edit by hand._",
        "",
        "## In plain words",
        "",
        "A probability is only useful if it is honest: among clients labelled \"10%\",",
        "about 10 in 100 should really have repayment trouble. Calibration adjusts each",
        "model's output with two numbers so that this holds. It does not change *who* is",
        "riskier than whom — only how the risk is expressed as a percentage.",
        "",
        "![Does a predicted 10% mean 10%?](img/3g_calibration.png)",
        "",
        "## How it is organised (improvement 2)",
        "",
        "| What | Where | Why |",
        "|---|---|---|",
        "| The two numbers (a, b) per model version | Oracle table `ref_calibration` | Changing them is a data change, not a code change |",
        "| The formula `1 / (1 + exp(-(a + b × raw score)))` | Oracle function `f_calibrate_pd` — once | No copies that can drift apart |",
        "| Every client's raw score | Oracle table `model_scores` | The PD always follows the current numbers |",
        "| Calibrated PD | Oracle view `v_scores` | One place to read it from |",
        "",
        "The numbers are learned on the `valid` clients. `sql/99_checks/05_model_scores.sql`",
        "proves that Oracle's formula and Python give the same PD for every client.",
        "",
        "## Results",
        "",
        "| Model | a | b | Clients | Actual rate | PD before | PD after | Brier before | Brier after |",
        "|---|---:|---:|---|---:|---:|---:|---:|---:|",
    ]
    for name, r in report.items():
        for part in ("valid", "holdout"):
            m = r[part]
            lines.append(f"| {name} | {r['a']:+.4f} | {r['b']:.4f} | {part} | {100 * m['actual']:.2f}% | "
                         f"{100 * m['raw']:.2f}% | {100 * m['cal']:.2f}% | {m['brier_raw']:.5f} | {m['brier_cal']:.5f} |")
    lines += [
        "",
        "`holdout` is reported only; no number was chosen by looking at it.",
        "Brier score: average squared error of the probabilities, lower is better.",
        "",
        "## LightGBM, holdout, in ten groups",
        "",
        "| Group | Predicted before | Predicted after | Actual |",
        "|---:|---:|---:|---:|",
    ]
    raw_t, cal_t = report["lightgbm"]["table_raw"], report["lightgbm"]["table_cal"]
    for i in range(len(cal_t)):
        lines.append(f"| {i + 1} | {100 * raw_t.predicted.iloc[i]:.2f}% | {100 * cal_t.predicted.iloc[i]:.2f}% | "
                     f"{100 * cal_t.actual.iloc[i]:.2f}% |")
    lines.append("")
    (ROOT / "docs" / "calibration.md").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
