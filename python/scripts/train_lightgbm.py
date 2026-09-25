"""Stage 3e: LightGBM — a more flexible model, to see how much accuracy the
scorecard leaves on the table.

In plain words: instead of one points table, LightGBM builds hundreds of
small yes/no decision trees, each correcting the mistakes of the ones before.
It can pick up patterns a points table cannot — rare warning signs,
combinations of facts. The price is that it is harder to explain, so we
measure what each fact contributes (SHAP) and compare it fairly with the
scorecard on the same unseen clients.

Rules (decisions 16 and 21):
  - settings are chosen by 5-fold cross-validation INSIDE `fit`: the fit
    clients are cut into 5 parts, the model learns on 4 and is tested on the
    5th, five times over. Only a small, pre-declared grid of 6 settings is
    tried, so the result is not a lucky pick
  - the number of trees comes from the same cross-validation (early stopping)
  - `valid` is used for nothing but measuring the final model, so its Gini is
    a clean estimate, directly comparable with the scorecard's
  - `holdout` stays untouched until the final comparison (Stage 3f)
  - age is not a feature (decision 21), in line with decision 20

Output:
  models/lightgbm.txt          the trained model
  models/lightgbm.json         settings and results
  docs/lightgbm.md             results in readable form (generated)
  docs/img/3e_importance.png   what drives the predictions

Run from the repository root:
    python python\\scripts\\train_lightgbm.py
"""
import json
import sys
import time
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
from hcr.metrics import gini, ks  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
NOT_FEATURES = {"sk_id_curr", "split", "dataset", "target"}
SHAP_SAMPLE = 20_000
TOP = 20

PARAMS = {
    "objective": "binary",
    "metric": "auc",
    "learning_rate": 0.03,        # small steps: slower, but more stable
    "feature_fraction": 0.8,      # each tree sees 80% of the features ...
    "bagging_fraction": 0.8,      # ... and 80% of the clients
    "bagging_freq": 1,
    "lambda_l2": 1.0,             # penalty on extreme leaf values
    "seed": 42,
    "deterministic": True,
    "verbosity": -1,
}
# The only settings searched (declared in advance):
#   num_leaves        - how detailed each tree may be
#   min_child_samples - smallest group of clients a tree may single out
SETTINGS = [{"num_leaves": nl, "min_child_samples": mcs} for nl in (15, 31, 63) for mcs in (100, 400)]
FOLDS, MAX_TREES, EARLY_STOP = 5, 5000, 200
EXCLUDE = {"app_age_years"}     # decision 21

SURFACE, BAR, TEXT, TEXT_2, GRID = "#fcfcfb", "#2a78d6", "#0b0b0b", "#52514e", "#e1e0d9"


def main() -> None:
    df = read_sql("SELECT * FROM v_model_input WHERE split IN ('fit', 'valid')")
    features = [c for c in df.columns if c not in NOT_FEATURES | EXCLUDE]
    categorical = [c for c in features if not pd.api.types.is_numeric_dtype(df[c])]   # text columns
    for c in categorical:   # same category list for fit and valid
        df[c] = pd.Categorical(df[c], categories=sorted(df.loc[df.split == "fit", c].dropna().unique()))
    fit, valid = df[df.split == "fit"], df[df.split == "valid"]
    print(f"fit {len(fit):,} / valid {len(valid):,} clients, {len(features)} features "
          f"({len(categorical)} text; excluded: {', '.join(sorted(EXCLUDE))})\n")

    # ---- 1. choose settings by cross-validation inside fit -------------------------
    start = time.perf_counter()
    train_set = lgb.Dataset(fit[features], fit.target, categorical_feature=categorical, free_raw_data=False)
    grid_results = []
    print(f"===== Cross-validation: {len(SETTINGS)} settings x {FOLDS} folds =====")
    for i, setting in enumerate(SETTINGS, 1):
        res = lgb.cv({**PARAMS, **setting}, train_set, num_boost_round=MAX_TREES, nfold=FOLDS,
                     stratified=True, seed=42, callbacks=[lgb.early_stopping(EARLY_STOP, verbose=False)])
        key = next(k for k in res if k.endswith("auc-mean"))
        auc, sd = res[key][-1], res[key.replace("mean", "stdv")][-1]
        grid_results.append({**setting, "trees": len(res[key]), "cv_gini": 2 * auc - 1, "cv_gini_sd": 2 * sd})
        print(f"  {i}/{len(SETTINGS)} num_leaves {setting['num_leaves']:>2}, min_child_samples "
              f"{setting['min_child_samples']:>3}: {len(res[key]):>4} trees, CV Gini {2 * auc - 1:.3f} "
              f"(+/- {2 * sd:.3f})  [{time.perf_counter() - start:.0f} s]")
    best = max(grid_results, key=lambda r: r["cv_gini"])
    params = {**PARAMS, "num_leaves": best["num_leaves"], "min_child_samples": best["min_child_samples"]}
    trees = best["trees"]

    # ---- 2. final model on all of fit, with the chosen settings --------------------
    booster = lgb.train(params, train_set, num_boost_round=trees)
    seconds = time.perf_counter() - start

    p_fit = booster.predict(fit[features], num_iteration=trees)
    p_valid = booster.predict(valid[features], num_iteration=trees)
    perf = {
        "fit":   {"clients": len(fit),   "gini": gini(fit.target, p_fit),     "ks": ks(fit.target, p_fit)},
        "valid": {"clients": len(valid), "gini": gini(valid.target, p_valid), "ks": ks(valid.target, p_valid)},
    }
    card = json.loads((ROOT / "models" / "scorecard.json").read_text(encoding="utf-8"))
    sc_valid = card["performance"]["valid"]["gini"]
    sc_fit = card["performance"]["fit"]["gini"]

    # ---- what drives the predictions (SHAP, computed by LightGBM itself) --------
    sample = valid.sample(min(SHAP_SAMPLE, len(valid)), random_state=42)
    contrib = booster.predict(sample[features], num_iteration=trees, pred_contrib=True)[:, :-1]
    importance = pd.Series(np.abs(contrib).mean(axis=0), index=features).sort_values(ascending=False)
    shap_share = importance / importance.sum()

    age_effect = None
    if "app_age_years" in features:
        age_col = features.index("app_age_years")
        groups = pd.cut(sample.app_age_years, [0, 30, 40, 50, 60, 200],
                        labels=["under 30", "30-39", "40-49", "50-59", "60+"], right=False)
        age_effect = pd.Series(contrib[:, age_col], index=sample.index).groupby(groups, observed=True).mean()

    # ---- save --------------------------------------------------------------------
    (ROOT / "models").mkdir(exist_ok=True)
    booster.save_model(str(ROOT / "models" / "lightgbm.txt"), num_iteration=trees)
    summary = {
        "model": "lightgbm", "version": 1, "created": date.today().isoformat(),
        "trained_on": "v_model_input, split = fit; settings and tree count by 5-fold CV inside fit",
        "params": params, "trees": trees, "training_seconds": round(seconds, 1),
        "excluded_features": sorted(EXCLUDE), "grid": grid_results,
        "features": features, "categorical": categorical,
        "performance": perf, "scorecard_valid_gini": sc_valid,
        "shap_share_top": {k: round(float(v), 4) for k, v in shap_share.head(TOP).items()},
    }
    (ROOT / "models" / "lightgbm.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")

    draw_importance(shap_share.head(TOP))
    write_markdown(perf, sc_fit, sc_valid, trees, seconds, shap_share, age_effect, grid_results, best)

    # ---- console summary ---------------------------------------------------------
    print(f"\n===== Chosen =====\nnum_leaves {best['num_leaves']}, min_child_samples {best['min_child_samples']}, "
          f"{trees} trees (CV Gini {best['cv_gini']:.3f}); total time {seconds:.0f} s\n")
    print("===== Performance =====")
    for part, m in perf.items():
        print(f"{part:<6} clients {m['clients']:>7,}  Gini {m['gini']:.3f}  KS {m['ks']:.3f}")
    gain = perf["valid"]["gini"] - sc_valid
    print(f"\nScorecard on valid: Gini {sc_valid:.3f}  ->  LightGBM gain {gain:+.3f} "
          f"({'at least' if gain >= 0.02 else 'below'} the 0.02 needed to prefer it, decision 16; "
          "final check on holdout in 3f)")
    print(f"CV Gini {best['cv_gini']:.3f} vs valid Gini {perf['valid']['gini']:.3f}: "
          "close values mean the result is not a lucky split")
    print(f"\n===== Top {TOP} drivers (share of all SHAP contributions) =====")
    for f, v in shap_share.head(TOP).items():
        print(f"  {f:<28} {100 * v:5.1f}%")
    if age_effect is not None:
        print("\n===== Age: average effect on the prediction (SHAP, log-odds; negative = safer) =====")
        for g, v in age_effect.items():
            print(f"  {g:<9} {v:+.3f}")
    print("\nWritten: models/lightgbm.txt, models/lightgbm.json, docs/lightgbm.md, docs/img/3e_importance.png")
    print("\n===== 3e COMPLETE =====")


def draw_importance(share: pd.Series) -> None:
    share = share.sort_values()
    fig, ax = plt.subplots(figsize=(9, 0.36 * len(share) + 1.6), dpi=150)
    fig.patch.set_facecolor(SURFACE)
    ax.set_facecolor(SURFACE)
    ax.barh(share.index, 100 * share.values, height=0.62, color=BAR, edgecolor=SURFACE, linewidth=2, zorder=2)
    for yi, v in enumerate(share.values):
        ax.text(100 * v + 0.2, yi, f"{100 * v:.1f}%", va="center", fontsize=8.5, color=TEXT)
    ax.set_xlabel("Share of everything the model uses to decide (average |SHAP|)", fontsize=9.5, color=TEXT_2)
    ax.tick_params(axis="y", labelsize=8.5, colors=TEXT, length=0)
    ax.tick_params(axis="x", labelsize=8.5, colors=TEXT_2, length=0)
    ax.xaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(decimals=0))
    ax.xaxis.set_major_locator(matplotlib.ticker.MaxNLocator(nbins=6, steps=[1, 2, 5, 10], integer=True))
    ax.grid(axis="x", color=GRID, linewidth=0.8, zorder=0)
    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    ax.spines["bottom"].set_color(GRID)
    ax.set_title(f"What drives LightGBM's predictions (top {len(share)})", loc="left", fontsize=12.5,
                 color=TEXT, fontweight="bold", pad=24)
    ax.text(0, 1.01, "A longer bar means the fact moves predictions more, in either direction.",
            transform=ax.transAxes, fontsize=8.5, color=TEXT_2, va="bottom")
    fig.tight_layout()
    fig.savefig(ROOT / "docs" / "img" / "3e_importance.png", facecolor=SURFACE)
    plt.close(fig)


def write_markdown(perf, sc_fit, sc_valid, trees, seconds, shap_share, age_effect, grid_results, best) -> None:
    gain = perf["valid"]["gini"] - sc_valid
    lines = [
        "# LightGBM (Stage 3e)",
        "",
        "_Generated by `python/scripts/train_lightgbm.py`. Do not edit by hand._",
        "",
        "## In plain words",
        "",
        "LightGBM builds many small yes/no decision trees, each fixing the mistakes of",
        "the previous ones. It can find patterns a points table cannot, but it is",
        "harder to explain — so we measure what each fact contributes and compare it",
        "with the [scorecard](scorecard.md) on the same clients neither model learned from.",
        "",
        "## How well it works",
        "",
        "| Model | Gini on `fit` | Gini on `valid` |",
        "|---|---:|---:|",
        f"| Scorecard | {sc_fit:.3f} | {sc_valid:.3f} |",
        f"| LightGBM ({trees} trees) | {perf['fit']['gini']:.3f} | {perf['valid']['gini']:.3f} |",
        "",
        f"Gain on `valid`: **{gain:+.3f}**. The scorecard is preferred unless LightGBM gains",
        "at least 0.02 ([decision 16](decisions.md)); the final comparison uses the",
        "untouched `holdout` clients (Stage 3f).",
        "",
        "A higher Gini on `fit` than on `valid` is expected: `fit` are the clients the",
        "model learned from. What matters is `valid`, which played no part in training.",
        "",
        "## How the settings were chosen",
        "",
        "Five-fold cross-validation inside `fit`: learn on 4/5 of the fit clients, test on",
        "the remaining 1/5, five times over. Only these 6 settings were tried, declared in",
        "advance; the number of trees is where the cross-validated result stopped improving.",
        "",
        "| num_leaves | min_child_samples | Trees | CV Gini |",
        "|---:|---:|---:|---:|",
    ]
    lines += [f"| {r['num_leaves']} | {r['min_child_samples']} | {r['trees']} | {r['cv_gini']:.3f} "
              f"(± {r['cv_gini_sd']:.3f}){' ← chosen' if r is best else ''} |" for r in grid_results]
    lines += [
        "",
        f"Chosen: {trees} trees, {seconds:.0f} seconds in total. Other settings are fixed and",
        "listed in `models/lightgbm.json`. Age is not a feature ([decision 21](decisions.md)).",
        "",
        "## What drives the predictions",
        "",
        "![What drives LightGBM's predictions](img/3e_importance.png)",
        "",
        "Measured with SHAP on 20,000 `valid` clients: for every client, how much each",
        "fact pushed the prediction up or down; the chart shows each fact's share of the total.",
        "",
        "| Fact | Share |",
        "|---|---:|",
    ]
    lines += [f"| `{f}` | {100 * v:.1f}% |" for f, v in shap_share.head(TOP).items()]
    if age_effect is not None:
        lines += [
            "",
            "## Age (decisions 17 and 20)",
            "",
            "Average effect of age on the prediction, in log-odds (negative = safer):",
            "",
            "| Age | Effect |",
            "|---|---:|",
        ]
        lines += [f"| {g} | {v:+.3f} |" for g, v in age_effect.items()]
    lines.append("")
    (ROOT / "docs" / "lightgbm.md").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
