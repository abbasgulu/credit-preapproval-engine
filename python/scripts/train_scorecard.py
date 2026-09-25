"""Stage 3d: the scorecard — a points-based model anyone can read.

In plain words: every fact about a client is cut into groups, each group
gets points, and the points are added up. A higher total means a safer
client. The points are learned from the `fit` clients and checked on the
`valid` clients, which the model has not seen. The `holdout` clients stay
untouched until the final comparison (Stage 3f).

Steps:
  1. Bin every feature and compute its information value (IV)   -> hcr/woe.py
  2. Keep features with IV >= 0.02 (below that they say almost nothing)
  3. Of two strongly related features (|correlation| > 0.7), keep the stronger
  4. Keep at most 20 features, strongest first
  5. Logistic regression on the WoE values; a feature whose weight points the
     wrong way (a side effect of overlapping features), or that moves the score
     by fewer than 3 points, is removed and the model refit
  6. Turn the result into points: 600 points = odds of 50 good clients to 1 bad,
     every 20 points more = the odds double ("points to double the odds", PDO)

Output:
  models/scorecard.json   the complete scorecard (used later to score in SQL)
  docs/scorecard.md       the scorecard in readable form (generated)
  docs/img/3d_points.png  how many points each fact can move

Run from the repository root:
    python python\\scripts\\train_scorecard.py
"""
import json
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # makes "import hcr" work

import matplotlib  # noqa: E402

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402
from sklearn.linear_model import LogisticRegression  # noqa: E402

from hcr.db import read_sql  # noqa: E402
from hcr.metrics import gini, ks  # noqa: E402
from hcr.woe import fit_binning  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
MIN_IV = 0.02
MAX_CORR = 0.7
MAX_FEATURES = 20
MIN_POINTS_RANGE = 3
PDO, BASE_SCORE, BASE_ODDS = 20, 600, 50

NOT_FEATURES = {"sk_id_curr", "split", "dataset", "target"}

# chart colours (reference data-viz palette, light mode)
SURFACE, BAR, TEXT, TEXT_2, GRID = "#fcfcfb", "#2a78d6", "#0b0b0b", "#52514e", "#e1e0d9"


def select_features(binnings: dict, woe_fit: pd.DataFrame) -> tuple[list[str], dict[str, str]]:
    """IV filter -> correlation thinning -> cap. Returns kept features and a reason for every dropped one."""
    reasons, kept = {}, []
    for f in sorted(binnings, key=lambda f: -binnings[f].iv):
        if binnings[f].iv < MIN_IV:
            reasons[f] = f"IV {binnings[f].iv:.3f} < {MIN_IV}"
            continue
        corr = [(k, abs(np.corrcoef(woe_fit[f], woe_fit[k])[0, 1])) for k in kept]
        clash = [(k, c) for k, c in corr if c > MAX_CORR]
        if clash:
            reasons[f] = f"correlated with {clash[0][0]} ({clash[0][1]:.2f})"
            continue
        if len(kept) >= MAX_FEATURES:
            reasons[f] = f"beyond the {MAX_FEATURES} strongest"
            continue
        kept.append(f)
    return kept, reasons


def fit_logistic(woe_fit: pd.DataFrame, y: pd.Series, features: list[str], reasons: dict) -> LogisticRegression:
    """Refit until every weight has the expected sign (negative: higher WoE = safer = lower PD)."""
    while True:
        model = LogisticRegression(C=1.0, max_iter=2000)
        model.fit(woe_fit[features], y)
        coefs = dict(zip(features, model.coef_[0]))
        wrong = [f for f, c in coefs.items() if c >= 0]
        if not wrong:
            return model
        worst = max(wrong, key=lambda f: coefs[f])
        reasons[worst] = f"weight had the wrong sign ({coefs[worst]:+.3f}) next to related features"
        features.remove(worst)


def main() -> None:
    df = read_sql("SELECT * FROM v_model_input WHERE split IN ('fit', 'valid')")
    fit, valid = df[df.split == "fit"], df[df.split == "valid"]
    features_all = [c for c in df.columns if c not in NOT_FEATURES]
    print(f"fit {len(fit):,} / valid {len(valid):,} clients, {len(features_all)} candidate features\n")

    # 1. binning + IV on fit only
    binnings = {f: fit_binning(fit[f], fit.target, f) for f in features_all}
    woe_fit = pd.DataFrame({f: b.transform(fit[f]) for f, b in binnings.items()}, index=fit.index)
    woe_valid = pd.DataFrame({f: b.transform(valid[f]) for f, b in binnings.items()}, index=valid.index)

    # 2-4. selection
    features, reasons = select_features(binnings, woe_fit)

    # 5. logistic regression; a feature that moves the score by fewer than
    #    MIN_POINTS_RANGE points adds nothing a reader would notice: drop it and refit
    factor = PDO / np.log(2)
    while True:
        model = fit_logistic(woe_fit, fit.target, features, reasons)
        coefs = dict(zip(features, model.coef_[0]))
        swing = {f: abs(coefs[f]) * (max(binnings[f].woe.values()) - min(binnings[f].woe.values())) * factor
                 for f in features}
        weakest = min(swing, key=swing.get)
        if swing[weakest] >= MIN_POINTS_RANGE:
            break
        reasons[weakest] = f"moves the score by only {swing[weakest]:.1f} points"
        features.remove(weakest)
    intercept = float(model.intercept_[0])

    # 6. points
    offset = BASE_SCORE - factor * np.log(BASE_ODDS)
    k = len(features)
    points = {f: {g: int(round(-(coefs[f] * w + intercept / k) * factor + offset / k))
                  for g, w in binnings[f].woe.items()} for f in features}
    # a group never seen in training (e.g. "Missing" when fit had no missing values) is neutral: WoE 0
    neutral = int(round(-(intercept / k) * factor + offset / k))

    def score(data: pd.DataFrame) -> pd.Series:
        total = pd.Series(0, index=data.index)
        for f in features:
            total += binnings[f].labels(data[f]).map(points[f]).fillna(neutral).astype(int)
        return total

    s_fit, s_valid = score(fit), score(valid)
    p_fit = model.predict_proba(woe_fit[features])[:, 1]
    p_valid = model.predict_proba(woe_valid[features])[:, 1]
    perf = {
        "fit":   {"clients": len(fit),   "gini": gini(fit.target, p_fit),     "ks": ks(fit.target, p_fit),
                  "gini_points": gini(fit.target, -s_fit)},
        "valid": {"clients": len(valid), "gini": gini(valid.target, p_valid), "ks": ks(valid.target, p_valid),
                  "gini_points": gini(valid.target, -s_valid)},
    }

    # ---- save the scorecard --------------------------------------------------
    (ROOT / "models").mkdir(exist_ok=True)
    card = {
        "model": "scorecard", "version": 1, "created": date.today().isoformat(),
        "trained_on": "v_model_input, split = fit", "target": "TARGET = 1 (repayment trouble)",
        "scaling": {"pdo": PDO, "base_score": BASE_SCORE, "base_odds": BASE_ODDS,
                    "factor": factor, "offset": offset},
        "intercept": intercept,
        "points_unseen_group": neutral,
        "features": [{**binnings[f].to_dict(), "coefficient": coefs[f], "points": points[f]} for f in features],
        "performance": perf,
    }
    (ROOT / "models" / "scorecard.json").write_text(json.dumps(card, indent=2), encoding="utf-8")

    # ---- chart: points range per feature ------------------------------------
    swing = pd.Series({f: max(points[f].values()) - min(points[f].values()) for f in features}).sort_values()
    fig, ax = plt.subplots(figsize=(9, 0.38 * len(swing) + 1.6), dpi=150)
    fig.patch.set_facecolor(SURFACE)
    ax.set_facecolor(SURFACE)
    ax.barh(swing.index, swing.values, height=0.62, color=BAR, edgecolor=SURFACE, linewidth=2, zorder=2)
    for yi, v in enumerate(swing.values):
        ax.text(v + 0.8, yi, f"{v}", va="center", fontsize=8.5, color=TEXT)
    ax.set_xlabel("Points between the worst and the best group of the fact", fontsize=9.5, color=TEXT_2)
    ax.tick_params(axis="y", labelsize=8.5, colors=TEXT, length=0)
    ax.tick_params(axis="x", labelsize=8.5, colors=TEXT_2, length=0)
    ax.grid(axis="x", color=GRID, linewidth=0.8, zorder=0)
    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    ax.spines["bottom"].set_color(GRID)
    ax.set_title("Which facts move the score the most", loc="left", fontsize=12.5, color=TEXT,
                 fontweight="bold", pad=24)
    ax.text(0, 1.01, "Scorecard points: a longer bar means the fact can change a client's score by more.",
            transform=ax.transAxes, fontsize=8.5, color=TEXT_2, va="bottom")
    fig.tight_layout()
    fig.savefig(ROOT / "docs" / "img" / "3d_points.png", facecolor=SURFACE)
    plt.close(fig)

    # ---- readable scorecard ---------------------------------------------------
    write_markdown(binnings, features, coefs, points, reasons, perf, fit)

    # ---- console summary ------------------------------------------------------
    print("===== Feature selection =====")
    print(f"IV >= {MIN_IV}: {sum(b.iv >= MIN_IV for b in binnings.values())} of {len(binnings)}; "
          f"in the scorecard: {len(features)}\n")
    print(f"{'feature':<28} {'IV':>6} {'weight':>8} {'points range':>13}")
    for f in sorted(features, key=lambda f: -binnings[f].iv):
        pts = points[f].values()
        print(f"{f:<28} {binnings[f].iv:6.3f} {coefs[f]:8.3f} {min(pts):>6} .. {max(pts):<4}")
    print("\n===== Points by age (fairness check, decisions 17 and 20) =====")
    if "app_age_years" in features:
        for g, p in points["app_age_years"].items():
            print(f"  age {g:<22} {p:>4} points")
    else:
        print("  app_age_years is not in the scorecard")
    print("\n===== Performance =====")
    for part, m in perf.items():
        print(f"{part:<6} clients {m['clients']:>7,}  Gini {m['gini']:.3f}  KS {m['ks']:.3f}  "
              f"(Gini of rounded points {m['gini_points']:.3f})")
    print(f"\nScore range on fit: {s_fit.min()} .. {s_fit.max()}, median {int(s_fit.median())}")
    print("\nWritten: models/scorecard.json, docs/scorecard.md, docs/img/3d_points.png")
    print("\n===== 3d COMPLETE =====")


def write_markdown(binnings, features, coefs, points, reasons, perf, fit) -> None:
    lines = [
        "# Scorecard (Stage 3d)",
        "",
        "_Generated by `python/scripts/train_scorecard.py`. Do not edit by hand._",
        "",
        "## In plain words",
        "",
        "Each fact about a client falls into one group, and each group is worth a",
        "number of points. Add up the points: **the higher the total, the safer the",
        "client**. Every 20 extra points halve the odds of repayment trouble.",
        "",
        "The points were learned from 70% of the clients with a known outcome and",
        "checked on another 15% the model had never seen.",
        "",
        "![Which facts move the score the most](img/3d_points.png)",
        "",
        "## How well it works",
        "",
        "| Clients | Number | Gini | KS |",
        "|---|---:|---:|---:|",
    ]
    for part, m in perf.items():
        lines.append(f"| {part} | {m['clients']:,} | {m['gini']:.3f} | {m['ks']:.3f} |")
    lines += [
        "",
        "Gini: 0 = no better than a coin toss, 1 = perfect ranking. A similar value on",
        "`fit` and `valid` means the scorecard learned general patterns rather than",
        "memorising the training clients. See the [glossary](glossary.md).",
        "",
        "## The points",
        "",
        "Column names are explained in the [data dictionary](data_dictionary.md).",
        "",
    ]
    for f in sorted(features, key=lambda f: -binnings[f].iv):
        t = binnings[f].table
        lines += [f"### `{f}` (IV {binnings[f].iv:.3f})", "",
                  "| Group | Clients | Share | Default rate | Points |", "|---|---:|---:|---:|---:|"]
        for g, r in t.iterrows():
            lines.append(f"| {g} | {int(r.clients):,} | {100 * r.share:.1f}% | {100 * r.bad_rate:.2f}% | "
                         f"{points[f].get(str(g), 0)} |")
        lines.append("")
    lines += [
        "## Facts not in the scorecard",
        "",
        "| Feature | IV | Why not |",
        "|---|---:|---|",
    ]
    for f in sorted(reasons, key=lambda f: -binnings[f].iv):
        lines.append(f"| `{f}` | {binnings[f].iv:.3f} | {reasons[f]} |")
    lines.append("")
    (ROOT / "docs" / "scorecard.md").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
