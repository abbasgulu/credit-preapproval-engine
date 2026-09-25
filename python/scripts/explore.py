"""Stage 3c: a first look — how does the default rate change with key facts?

In plain words: before building any model, look at the data the way a
person would. Split clients into simple groups (by age, by late payments,
...) and compare how often each group had repayment trouble. If a fact
makes a big difference between groups, the model will probably use it.

Only the `fit` group (70% of known clients) is used, so the `valid` and
`holdout` groups stay unseen until the model is tested on them.

Output:
  - one chart per fact in docs/img/3c_*.png
  - the numbers behind every chart, printed as tables

Run from the repository root:
    python python\\scripts\\explore.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # makes "import hcr" work

import matplotlib  # noqa: E402

matplotlib.use("Agg")  # draw to files, no window
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402

from hcr.db import read_sql  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
IMG = ROOT / "docs" / "img"

# Colours (reference data-viz palette, light mode)
SURFACE = "#fcfcfb"
BAR = "#2a78d6"        # one series -> one hue
NO_DATA = "#898781"    # neutral: "no history" is not a risk level; always labelled
TEXT = "#0b0b0b"
TEXT_2 = "#52514e"
GRID = "#e1e0d9"

NO_DATA_LABEL = "No history"

COLUMNS = """
    sk_id_curr, target, app_age_years, app_ext_source_mean, app_is_not_employed,
    app_employed_years, app_education, ins_has_history, ins_late_share_12m,
    ins_cnt_12m, prv_has_history, prv_refused_cnt_2y, bb_has_history,
    bb_worst_status_12m, cc_has_history, cc_util_max_12m, bur_has_history,
    bur_debt_to_income
"""


# ---------------------------------------------------------------------------
# Grouping rules: each returns a Series of ordered group labels
# ---------------------------------------------------------------------------
def by_bins(values: pd.Series, edges, labels, missing_label=None) -> pd.Series:
    groups = pd.cut(values, bins=edges, labels=labels, right=False)
    groups = groups.cat.add_categories([missing_label]) if missing_label else groups
    if missing_label:
        groups = groups.fillna(missing_label)
    return groups


def age(df):
    return by_bins(df.app_age_years, [0, 25, 30, 35, 40, 45, 50, 55, 60, 65, 200],
                   ["<25", "25–29", "30–34", "35–39", "40–44", "45–49",
                    "50–54", "55–59", "60–64", "65+"])


def ext_score(df):
    labels = ["Lowest 20%", "20–40%", "40–60%", "60–80%", "Highest 20%"]
    groups = pd.qcut(df.app_ext_source_mean, 5, labels=labels)
    return groups.cat.add_categories(["No score"]).fillna("No score")


def employment(df):
    groups = by_bins(df.app_employed_years, [0, 1, 3, 5, 10, 200],
                     ["<1 year", "1–2", "3–4", "5–9", "10+ years"])
    groups = groups.cat.add_categories(["Not employed"])
    return groups.where(df.app_is_not_employed == 0, "Not employed")


def late_payments(df):
    share = df.ins_late_share_12m
    labels = ["None late", "Up to 5%", "5–20%", "Over 20%", NO_DATA_LABEL]
    groups = pd.Series(pd.Categorical([None] * len(df), categories=labels), index=df.index)
    groups[share == 0] = "None late"
    groups[(share > 0) & (share <= 0.05)] = "Up to 5%"
    groups[(share > 0.05) & (share <= 0.20)] = "5–20%"
    groups[share > 0.20] = "Over 20%"
    groups[share.isna()] = NO_DATA_LABEL          # no instalment due in the last 12 months
    return groups


def refusals(df):
    groups = by_bins(df.prv_refused_cnt_2y, [0, 1, 2, 3, 1000], ["0", "1", "2", "3+"])
    groups = groups.cat.add_categories([NO_DATA_LABEL])
    return groups.where(df.prv_has_history == 1, NO_DATA_LABEL)


def bureau_status(df):
    labels = ["Never late", "1–30 days late", "31+ days late", NO_DATA_LABEL]
    s = df.bb_worst_status_12m
    groups = pd.Series(pd.Categorical([None] * len(df), categories=labels), index=df.index)
    groups[s == 0] = "Never late"
    groups[s == 1] = "1–30 days late"
    groups[s >= 2] = "31+ days late"
    groups[s.isna()] = NO_DATA_LABEL              # no monthly bureau history in the last 12 months
    return groups


def card_use(df):
    groups = by_bins(df.cc_util_max_12m, [-1e9, 0.3, 0.7, 1.0, 1e9],
                     ["Under 30%", "30–70%", "70–100%", "Over limit"], missing_label=NO_DATA_LABEL)
    return groups


def debt_to_income(df):
    groups = by_bins(df.bur_debt_to_income, [-1e9, 1e-9, 1, 3, 1e9],
                     ["No debt", "Up to 1× income", "1–3×", "Over 3×"])
    groups = groups.cat.add_categories([NO_DATA_LABEL])
    return groups.where(df.bur_has_history == 1, NO_DATA_LABEL)


def education(df):
    order = ["Lower secondary", "Secondary / secondary special", "Incomplete higher",
             "Higher education", "Academic degree"]
    return pd.Series(pd.Categorical(df.app_education, categories=order), index=df.index)


FACTS = [
    # file name,       title,                                                     x-axis label,                          rule
    ("age",            "Default rate by age",                                     "Age at application",                   age),
    ("ext_score",      "Default rate by external credit score",                   "External score, from lowest to highest", ext_score),
    ("employment",     "Default rate by length of employment",                    "Years in current job",                 employment),
    ("late_payments",  "Default rate by late payments in the last 12 months",     "Share of instalments paid late",       late_payments),
    ("refusals",       "Default rate by refused applications in the last 2 years", "Refused applications at this lender",  refusals),
    ("bureau_status",  "Default rate by worst status at other lenders (12 months)", "Worst monthly status at other lenders", bureau_status),
    ("card_use",       "Default rate by highest credit-card use (12 months)",     "Highest balance as a share of the limit", card_use),
    ("debt_to_income", "Default rate by debt at other lenders",                   "Active debt at other lenders / income", debt_to_income),
    ("education",      "Default rate by education",                               "Highest education",                    education),
]


# ---------------------------------------------------------------------------
# Table + chart
# ---------------------------------------------------------------------------
def summarise(df: pd.DataFrame, groups: pd.Series) -> pd.DataFrame:
    table = (df.assign(group=groups)
               .groupby("group", observed=False)
               .agg(clients=("target", "size"), defaults=("target", "sum")))
    table["default_pct"] = 100 * table.defaults / table.clients.replace(0, np.nan)
    table["share_pct"] = 100 * table.clients / table.clients.sum()
    return table


def draw(table: pd.DataFrame, title: str, xlabel: str, overall_pct: float, path: Path) -> None:
    table = table[table.clients > 0]
    labels = [str(g) for g in table.index]
    rates = table.default_pct.to_numpy()
    colours = [NO_DATA if lab in (NO_DATA_LABEL, "No score") else BAR for lab in labels]

    fig, ax = plt.subplots(figsize=(9, 4.8), dpi=150)
    fig.patch.set_facecolor(SURFACE)
    ax.set_facecolor(SURFACE)

    x = np.arange(len(labels))
    ax.bar(x, rates, width=0.62, color=colours, edgecolor=SURFACE, linewidth=2, zorder=2)

    # Reference line: all clients (explained in the subtitle, so it never collides with a bar label)
    ax.axhline(overall_pct, color=TEXT_2, linewidth=1, linestyle=(0, (4, 3)), zorder=1)

    # Value on each bar (static image: no hover, so the numbers are printed)
    for xi, rate in zip(x, rates):
        ax.text(xi, rate + 0.25, f"{rate:.1f}%", ha="center", va="bottom", fontsize=9, color=TEXT,
                bbox=dict(facecolor=SURFACE, edgecolor="none", pad=1.5), zorder=4)

    ax.set_xticks(x)
    ax.set_xticklabels([f"{lab}\nn={n:,}" for lab, n in zip(labels, table.clients)],
                       fontsize=8.5, color=TEXT_2)
    ax.set_xlabel(xlabel, fontsize=9.5, color=TEXT_2, labelpad=8)
    ax.set_ylabel("Clients with repayment trouble", fontsize=9.5, color=TEXT_2)
    # whole-number steps only, so every tick label is exact (no 7.5% shown as "8%")
    ax.yaxis.set_major_locator(matplotlib.ticker.MaxNLocator(nbins=6, steps=[1, 2, 5, 10], integer=True))
    ax.yaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(decimals=0))
    ax.set_ylim(0, max(rates.max() * 1.18, overall_pct * 1.4))
    ax.tick_params(axis="y", labelsize=8.5, colors=TEXT_2, length=0)
    ax.tick_params(axis="x", length=0)
    ax.grid(axis="y", color=GRID, linewidth=0.8, zorder=0)
    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    ax.spines["bottom"].set_color(GRID)

    ax.set_title(title, loc="left", fontsize=12.5, color=TEXT, pad=28, fontweight="bold")
    subtitle = f"Share of clients who had repayment trouble. Dashed line: all clients ({overall_pct:.1f}%)."
    if NO_DATA in colours:
        subtitle += " Grey bar: no history in this source."
    ax.text(0, 1.035, subtitle, transform=ax.transAxes, fontsize=8.5, color=TEXT_2, va="bottom")
    fig.text(0.01, 0.01, "Source: Home Credit Default Risk (Kaggle), fit group (70% of clients with a known outcome).",
             fontsize=7.5, color=TEXT_2)
    fig.tight_layout(rect=(0, 0.03, 1, 1))
    fig.savefig(path, facecolor=SURFACE)
    plt.close(fig)


def main() -> None:
    df = read_sql(f"SELECT {COLUMNS} FROM v_model_input WHERE split = 'fit'")
    overall = 100 * df.target.mean()
    print(f"fit group: {len(df):,} clients, default rate {overall:.2f}%\n")

    IMG.mkdir(parents=True, exist_ok=True)
    pd.set_option("display.width", 120)
    for name, title, xlabel, rule in FACTS:
        table = summarise(df, rule(df))
        path = IMG / f"3c_{name}.png"
        draw(table, title, xlabel, overall, path)

        spread = table.loc[table.clients >= 500, "default_pct"]
        print(f"===== {title} =====")
        print(table.to_string(formatters={"default_pct": "{:.2f}".format, "share_pct": "{:.1f}".format}))
        print(f"lowest {spread.min():.2f}% / highest {spread.max():.2f}% "
              f"(groups with 500+ clients) -> chart {path.relative_to(ROOT)}\n")

    print(f"===== 3c COMPLETE: {len(FACTS)} charts in docs\\img =====")


if __name__ == "__main__":
    main()
