"""Stage 3f: the final exam — both models on the holdout clients.

In plain words: 15% of the clients with a known outcome (the holdout) were
kept aside from the very start. Neither model has seen them, and no choice
was made by looking at them. Now both models score them once, and the
winner is picked by the rule written down in advance (decision 16): the
scorecard wins unless LightGBM is better by at least 0.02 Gini.

The holdout can be used only once. This script therefore records the
result, together with a fingerprint of both model files, in
models/holdout_result.json. Run again with the SAME models, it simply
repeats the same calculation; with CHANGED models it refuses, because the
holdout would then no longer be an honest test.

Also measured:
  - a 95% confidence interval for the Gini difference (bootstrap: the
    holdout is re-drawn 500 times with replacement)
  - calibration: predicted vs actual default rate in 10 groups
  - stability (PSI) between the holdout and the test clients, who stand in
    for new applicants

Output:
  models/holdout_result.json    the one-time result
  docs/model_comparison.md      the result in readable form (generated)
  docs/img/3f_deciles.png       default rate in each tenth of clients, by model

Run from the repository root:
    python python\\scripts\\compare_holdout.py
"""
import json
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # makes "import hcr" work

import lightgbm as lgb  # noqa: E402
import matplotlib  # noqa: E402

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402

from hcr.db import read_sql  # noqa: E402
from hcr.metrics import brier, calibration_table, gini, ks, psi  # noqa: E402
from hcr.scoring import fingerprint, lightgbm_raw, scorecard_raw, to_pd  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
MODELS = ROOT / "models"
RESULT = MODELS / "holdout_result.json"
MIN_GAIN = 0.02          # decision 16
BOOTSTRAP = 500

SURFACE, TEXT, TEXT_2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e1e0d9"
COLOURS = {"Scorecard": "#2a78d6", "LightGBM": "#eb6834"}   # categorical slots 1 and 2 (validated pair)


def scorecard_pd(card: dict, data: pd.DataFrame) -> np.ndarray:
    return to_pd(scorecard_raw(card, data))


def lightgbm_pd(booster: lgb.Booster, meta: dict, data: pd.DataFrame) -> np.ndarray:
    return to_pd(lightgbm_raw(booster, meta, data))


# ---------------------------------------------------------------------------
def main() -> None:
    prints = fingerprint()
    if RESULT.exists():
        previous = json.loads(RESULT.read_text(encoding="utf-8"))
        if previous["model_fingerprint"] != prints:
            sys.exit("REFUSED: the holdout was already used with different model files "
                     f"(see {RESULT.relative_to(ROOT)}). Changing the models after the exam "
                     "would make the holdout a dishonest test.")
        print("Same model files as the recorded exam: repeating the same calculation.\n")

    card = json.loads((MODELS / "scorecard.json").read_text(encoding="utf-8"))
    meta = json.loads((MODELS / "lightgbm.json").read_text(encoding="utf-8"))
    booster = lgb.Booster(model_file=str(MODELS / "lightgbm.txt"))

    df = read_sql("SELECT * FROM v_model_input WHERE split IN ('holdout', 'test')")
    holdout, test = df[df.split == "holdout"].reset_index(drop=True), df[df.split == "test"]
    y = holdout.target.to_numpy()
    print(f"holdout {len(holdout):,} clients ({int(y.sum()):,} defaults), test {len(test):,} clients\n")

    pds = {"Scorecard": scorecard_pd(card, holdout), "LightGBM": lightgbm_pd(booster, meta, holdout)}
    pds_test = {"Scorecard": scorecard_pd(card, test), "LightGBM": lightgbm_pd(booster, meta, test)}

    # ---- measures --------------------------------------------------------------
    results = {}
    for name, p in pds.items():
        results[name] = {"gini": gini(y, p), "ks": ks(y, p), "brier": brier(y, p),
                         "mean_pd": float(p.mean()), "psi_holdout_vs_test": psi(p, pds_test[name])}
    actual_rate = float(y.mean())

    # paired bootstrap of the Gini difference
    rng = np.random.default_rng(42)
    diffs = []
    for _ in range(BOOTSTRAP):
        idx = rng.integers(0, len(y), len(y))
        diffs.append(gini(y[idx], pds["LightGBM"][idx]) - gini(y[idx], pds["Scorecard"][idx]))
    gain = results["LightGBM"]["gini"] - results["Scorecard"]["gini"]
    ci = (float(np.percentile(diffs, 2.5)), float(np.percentile(diffs, 97.5)))
    winner = "LightGBM" if gain >= MIN_GAIN else "Scorecard"

    calib = {name: calibration_table(y, p) for name, p in pds.items()}
    deciles = {name: t.actual.to_numpy() for name, t in calib.items()}   # group 1 = lowest PD

    # ---- record ----------------------------------------------------------------
    record = {
        "stage": "3f", "date": date.today().isoformat(), "holdout_clients": int(len(y)),
        "holdout_defaults": int(y.sum()), "model_fingerprint": prints,
        "results": results, "gini_gain_lightgbm": gain, "gini_gain_ci95": ci,
        "rule": f"LightGBM wins if its Gini is higher by at least {MIN_GAIN} (decision 16)",
        "winner": winner,
    }
    RESULT.write_text(json.dumps(record, indent=2), encoding="utf-8")
    draw_deciles(deciles, actual_rate)
    write_markdown(record, calib, actual_rate)

    # ---- console ---------------------------------------------------------------
    print("===== Holdout results =====")
    print(f"{'model':<10} {'Gini':>6} {'KS':>6} {'Brier':>7} {'mean PD':>8} {'PSI vs test':>12}")
    for name, r in results.items():
        print(f"{name:<10} {r['gini']:6.3f} {r['ks']:6.3f} {r['brier']:7.4f} {100 * r['mean_pd']:7.2f}% "
              f"{r['psi_holdout_vs_test']:12.3f}")
    print(f"actual default rate on holdout: {100 * actual_rate:.2f}%")
    print(f"\nGini gain of LightGBM: {gain:+.3f}  (95% interval {ci[0]:+.3f} .. {ci[1]:+.3f})")
    print(f"Rule (decision 16): LightGBM wins if the gain >= {MIN_GAIN}  ->  WINNER: {winner}")
    print("\n===== Default rate by tenth of clients (1 = lowest predicted risk) =====")
    print(f"{'group':>5} " + " ".join(f"{n:>10}" for n in deciles))
    for i in range(10):
        print(f"{i + 1:>5} " + " ".join(f"{100 * deciles[n][i]:9.2f}%" for n in deciles))
    print("\nWritten: models/holdout_result.json, docs/model_comparison.md, docs/img/3f_deciles.png")
    print("\n===== 3f COMPLETE =====")


def draw_deciles(deciles: dict, overall: float) -> None:
    fig, ax = plt.subplots(figsize=(9, 4.8), dpi=150)
    fig.patch.set_facecolor(SURFACE)
    ax.set_facecolor(SURFACE)
    x = np.arange(1, 11)
    width = 0.38
    for i, (name, rates) in enumerate(deciles.items()):
        ax.bar(x + (i - 0.5) * width, 100 * rates, width=width, color=COLOURS[name], label=name,
               edgecolor=SURFACE, linewidth=2, zorder=2)
    ax.axhline(100 * overall, color=TEXT_2, linewidth=1, linestyle=(0, (4, 3)), zorder=1)
    for name, rates in deciles.items():   # label only the two ends: safest and riskiest tenth
        left = name == "Scorecard"        # left bar's label leans left, right bar's leans right
        for xi in (1, 10):
            ax.text(xi + (-0.5 if left else 0.5) * width, 100 * rates[xi - 1] + 0.3,
                    f"{100 * rates[xi - 1]:.1f}%", ha="right" if left else "left", va="bottom",
                    fontsize=8, color=TEXT)
    top = max(r.max() for r in deciles.values())
    ax.set_ylim(0, 100 * top * 1.15)
    ax.set_xticks(x)
    ax.set_xticklabels([f"{i}" for i in x], fontsize=8.5, color=TEXT_2)
    ax.set_xlabel("Tenth of clients, from lowest (1) to highest (10) predicted risk", fontsize=9.5,
                  color=TEXT_2, labelpad=8)
    ax.set_ylabel("Clients with repayment trouble", fontsize=9.5, color=TEXT_2)
    ax.yaxis.set_major_locator(matplotlib.ticker.MaxNLocator(nbins=6, steps=[1, 2, 5, 10], integer=True))
    ax.yaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(decimals=0))
    ax.tick_params(axis="both", length=0, labelsize=8.5, colors=TEXT_2)
    ax.grid(axis="y", color=GRID, linewidth=0.8, zorder=0)
    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    ax.spines["bottom"].set_color(GRID)
    ax.legend(frameon=False, fontsize=9, loc="upper left")
    ax.set_title("How well each model separates safe from risky clients", loc="left", fontsize=12.5,
                 color=TEXT, fontweight="bold", pad=28)
    ax.text(0, 1.035, f"Holdout clients, never seen by either model. Dashed line: all clients ({100 * overall:.1f}%). "
            "Steeper = better.", transform=ax.transAxes, fontsize=8.5, color=TEXT_2, va="bottom")
    fig.tight_layout()
    fig.savefig(ROOT / "docs" / "img" / "3f_deciles.png", facecolor=SURFACE)
    plt.close(fig)


def write_markdown(record: dict, calib: dict, actual_rate: float) -> None:
    r, gain, ci = record["results"], record["gini_gain_lightgbm"], record["gini_gain_ci95"]
    sc, lg = calib["Scorecard"], calib["LightGBM"]
    lines = [
        "# Final comparison on the holdout (Stage 3f)",
        "",
        "_Generated by `python/scripts/compare_holdout.py`. Do not edit by hand._",
        "",
        "## In plain words",
        "",
        f"{record['holdout_clients']:,} clients were kept aside from the start and never shown to",
        "either model. Both models were tested on them once, and the winner was picked by",
        "a rule written down before the test ([decision 16](decisions.md)).",
        "",
        f"**Winner: {record['winner']}.**",
        "",
        "![How well each model separates safe from risky clients](img/3f_deciles.png)",
        "",
        f"Among the 10% of clients LightGBM rates safest, {100 * lg.actual.iloc[0]:.1f}% had repayment",
        f"trouble; among the 10% it rates riskiest, {100 * lg.actual.iloc[-1]:.1f}% did "
        f"(all clients: {100 * actual_rate:.1f}%).",
        "",
        "## Results",
        "",
        "| Model | Gini | KS | Brier | Average predicted PD | Stability vs new applicants (PSI) |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for name, m in r.items():
        lines.append(f"| {name} | {m['gini']:.3f} | {m['ks']:.3f} | {m['brier']:.4f} | "
                     f"{100 * m['mean_pd']:.2f}% | {m['psi_holdout_vs_test']:.3f} |")
    lines += [
        "",
        f"Actual default rate on the holdout: {100 * actual_rate:.2f}%.",
        "",
        f"**Gini gain of LightGBM: {gain:+.3f}** (95% interval {ci[0]:+.3f} to {ci[1]:+.3f}, from 500",
        "bootstrap re-draws of the holdout). The rule needs at least +0.020.",
        "",
        "PSI below 0.1 means the new applicants (Kaggle's test clients) look like the",
        "clients the models were tested on, so the results should carry over.",
        "",
        "## Calibration: predicted vs actual",
        "",
        "Clients sorted by predicted PD into ten equal groups. Close numbers mean the",
        "probabilities can be taken at face value; any gap is corrected in Stage 3g.",
        "",
        "| Group | Scorecard predicted | Scorecard actual | LightGBM predicted | LightGBM actual |",
        "|---:|---:|---:|---:|---:|",
    ]
    for i in range(len(sc)):
        lines.append(f"| {i + 1} | {100 * sc.predicted.iloc[i]:.2f}% | {100 * sc.actual.iloc[i]:.2f}% | "
                     f"{100 * lg.predicted.iloc[i]:.2f}% | {100 * lg.actual.iloc[i]:.2f}% |")
    lines += [
        "",
        "## Integrity",
        "",
        "The exam is recorded in `models/holdout_result.json` together with a SHA-256",
        "fingerprint of both model files. The script refuses to re-run the holdout on",
        "changed models.",
        "",
    ]
    (ROOT / "docs" / "model_comparison.md").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
