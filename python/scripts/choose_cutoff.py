"""Stage 4b: choose the PD cut-off from the target default rate.

In plain words: the lower the cut-off, the fewer clients get an offer and
the safer they are; the higher, the more offers and the more of them end in
trouble. The rule agreed in advance (decision 25) is: offer credit to as
many clients as possible, as long as no more than 5% of the approved
clients (TARGET_BAD_RATE in ref_rules) are expected to have repayment
trouble.

How:
  - clients stopped earlier by the exclusion list or a policy rule (age,
    current arrears) are left out, as the engine would stop them first
  - on the `valid` clients, clients are sorted from lowest to highest PD
    and the highest cut-off is taken at which the default rate among the
    approved is still at or below the target
  - the cut-off is written to ref_rules as PD_CUTOFF (the previous one, if
    any, is closed with a valid_to date: history is kept)
  - the result on `holdout` is reported only, never used for the choice

Output:
  Oracle: ref_rules row PD_CUTOFF
  docs/cutoff.md           results in readable form (generated)
  docs/img/4b_tradeoff.png approval rate vs default rate among approved

Run from the repository root:
    python python\\scripts\\choose_cutoff.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # makes "import hcr" work

import matplotlib  # noqa: E402

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402

from hcr.db import connect, read_sql  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
MODEL = "lightgbm"
SURFACE, LINE, TEXT, TEXT_2, GRID, MARK = "#fcfcfb", "#2a78d6", "#0b0b0b", "#52514e", "#e1e0d9", "#eb6834"

# Clients who reach the risk step: not excluded, and passing the policy rules in force today.
POPULATION_SQL = """
WITH r AS (
  SELECT MAX(CASE WHEN rule_code = 'MIN_AGE'             THEN rule_value END) AS min_age,
         MAX(CASE WHEN rule_code = 'MAX_AGE_AT_MATURITY' THEN rule_value END) AS max_age_mat,
         MAX(CASE WHEN rule_code = 'OFFER_TERM_MONTHS'   THEN rule_value END) AS term_months,
         MAX(CASE WHEN rule_code = 'MAX_CURRENT_DPD'     THEN rule_value END) AS max_dpd
  FROM   ref_rules
  WHERE  valid_from <= TRUNC(SYSDATE) AND (valid_to IS NULL OR valid_to > TRUNC(SYSDATE))
)
SELECT m.sk_id_curr, m.split, m.target, s.pd
FROM   v_model_input m
JOIN   v_scores s ON s.sk_id_curr = m.sk_id_curr
CROSS  JOIN r
WHERE  s.model_name = :model
AND    s.model_version = (SELECT MAX(model_version) FROM model_scores WHERE model_name = :model)
AND    m.split IN ('valid', 'holdout')
AND    NOT EXISTS (SELECT 1 FROM ref_exclusion_list e
                   WHERE e.sk_id_curr = m.sk_id_curr
                   AND   e.valid_from <= TRUNC(SYSDATE) AND (e.valid_to IS NULL OR e.valid_to > TRUNC(SYSDATE)))
AND    m.app_age_years >= r.min_age
AND    m.app_age_years + r.term_months / 12 <= r.max_age_mat
AND    NVL(m.bur_current_dpd_max, 0) <= r.max_dpd
"""


def curve(pd_values: np.ndarray, y: np.ndarray) -> pd.DataFrame:
    """For every possible cut-off (each client's PD): approval rate and default rate among approved."""
    order = np.argsort(pd_values, kind="stable")
    p, t = pd_values[order], y[order]
    n = np.arange(1, len(p) + 1)
    bad_cum = np.cumsum(t)
    return pd.DataFrame({"cutoff": p, "approval_rate": n / len(p), "bad_rate_approved": bad_cum / n,
                         "bads_caught": 1 - bad_cum / t.sum()})


def at_cutoff(pd_values: np.ndarray, y: np.ndarray, cutoff: float) -> dict:
    approved = pd_values <= cutoff
    return {"clients": int(len(y)), "approval_rate": float(approved.mean()),
            "bad_rate_approved": float(y[approved].mean()) if approved.any() else float("nan"),
            "bad_rate_declined": float(y[~approved].mean()) if (~approved).any() else float("nan"),
            "bads_caught": float(y[~approved].sum() / y.sum())}


def main() -> None:
    rules = read_sql("""SELECT rule_code, rule_value FROM ref_rules
                        WHERE valid_from <= TRUNC(SYSDATE) AND (valid_to IS NULL OR valid_to > TRUNC(SYSDATE))""")
    target = float(rules.set_index("rule_code").rule_value["TARGET_BAD_RATE"])
    df = read_sql(POPULATION_SQL, {"model": MODEL})
    valid, holdout = df[df.split == "valid"], df[df.split == "holdout"]
    print(f"Clients reaching the risk step: valid {len(valid):,}, holdout {len(holdout):,}")
    print(f"Target: at most {100 * target:.1f}% default rate among approved clients\n")

    c = curve(valid.pd.to_numpy(), valid.target.to_numpy())
    ok = c[c.bad_rate_approved <= target]
    if ok.empty:
        sys.exit("No cut-off meets the target; nothing written.")
    cutoff = float(np.floor(ok.cutoff.iloc[-1] * 10_000) / 10_000)   # rounded down to 0.01% for a clean rule

    res_valid = at_cutoff(valid.pd.to_numpy(), valid.target.to_numpy(), cutoff)
    res_hold = at_cutoff(holdout.pd.to_numpy(), holdout.target.to_numpy(), cutoff)

    # ---- write PD_CUTOFF to ref_rules (close the previous one) --------------
    with connect() as con, con.cursor() as cur:
        cur.execute("""UPDATE ref_rules SET valid_to = TRUNC(SYSDATE)
                       WHERE rule_code = 'PD_CUTOFF' AND valid_to IS NULL AND valid_from < TRUNC(SYSDATE)""")
        cur.execute("""
            MERGE INTO ref_rules t
            USING (SELECT :cutoff AS rule_value FROM dual) s
            ON (t.rule_code = 'PD_CUTOFF' AND t.valid_from = TRUNC(SYSDATE))
            WHEN MATCHED THEN UPDATE SET t.rule_value = s.rule_value, t.created_at = SYSTIMESTAMP
            WHEN NOT MATCHED THEN INSERT (rule_code, rule_value, unit, description, set_by, valid_from, created_at)
                 VALUES ('PD_CUTOFF', s.rule_value, 'PD',
                         'Highest calibrated PD that can still be approved.',
                         'choose_cutoff.py: highest cut-off with default rate among approved valid clients <= TARGET_BAD_RATE',
                         TRUNC(SYSDATE), SYSTIMESTAMP)""", {"cutoff": cutoff})
        con.commit()

    # ---- trade-off table at round approval rates ------------------------------
    rows = []
    for share in (0.5, 0.6, 0.7, 0.8, 0.85, 0.9, 0.95, 1.0):
        i = min(int(np.ceil(share * len(c))) - 1, len(c) - 1)
        rows.append({"approval_rate": share, "cutoff": c.cutoff.iloc[i],
                     "bad_rate_approved": c.bad_rate_approved.iloc[i], "bads_caught": c.bads_caught.iloc[i]})
    table = pd.DataFrame(rows)

    draw(c, target, res_valid)
    write_markdown(target, cutoff, res_valid, res_hold, table)

    print("===== Chosen cut-off =====")
    print(f"PD_CUTOFF = {cutoff:.4f} ({100 * cutoff:.2f}%)  -> written to ref_rules\n")
    print(f"{'clients':<9} {'approved':>9} {'bad rate approved':>18} {'bad rate declined':>18} {'bads caught':>12}")
    for name, r in (("valid", res_valid), ("holdout", res_hold)):
        print(f"{name:<9} {100 * r['approval_rate']:8.1f}% {100 * r['bad_rate_approved']:17.2f}% "
              f"{100 * r['bad_rate_declined']:17.2f}% {100 * r['bads_caught']:11.1f}%")
    print("(holdout: reported only)\n")
    print("===== Trade-off on valid: approve more -> more trouble among the approved =====")
    print(f"{'approve':>8} {'cut-off PD':>11} {'bad rate approved':>18} {'bads caught':>12}")
    for _, r in table.iterrows():
        print(f"{100 * r.approval_rate:7.0f}% {100 * r.cutoff:10.2f}% {100 * r.bad_rate_approved:17.2f}% "
              f"{100 * r.bads_caught:11.1f}%")
    print("\nWritten: ref_rules (PD_CUTOFF), docs/cutoff.md, docs/img/4b_tradeoff.png")
    print("\n===== 4b COMPLETE =====")


def draw(c: pd.DataFrame, target: float, chosen: dict) -> None:
    step = max(len(c) // 400, 1)          # ~400 points are enough for a smooth line
    s = c.iloc[::step]
    fig, ax = plt.subplots(figsize=(9, 5), dpi=150)
    fig.patch.set_facecolor(SURFACE)
    ax.set_facecolor(SURFACE)
    ax.plot(100 * s.approval_rate, 100 * s.bad_rate_approved, color=LINE, linewidth=2, zorder=3)
    ax.axhline(100 * target, color=TEXT_2, linewidth=1, linestyle=(0, (4, 3)), zorder=2)
    x, y = 100 * chosen["approval_rate"], 100 * chosen["bad_rate_approved"]
    ax.plot([x], [y], marker="o", markersize=9, color=MARK, markeredgecolor=SURFACE, markeredgewidth=2, zorder=4)
    ax.annotate(f"chosen: approve {x:.0f}%,\n{y:.1f}% of them with trouble", (x, y), xytext=(-12, 14),
                textcoords="offset points", ha="right", fontsize=8.5, color=TEXT)
    ax.set_xlim(0, 100)
    ax.set_ylim(0, 100 * c.bad_rate_approved.max() * 1.15)
    ax.set_xlabel("Share of clients approved (lowest risk first)", fontsize=9.5, color=TEXT_2)
    ax.set_ylabel("Clients with repayment trouble among the approved", fontsize=9.5, color=TEXT_2)
    for axis in (ax.xaxis, ax.yaxis):
        axis.set_major_formatter(matplotlib.ticker.PercentFormatter(decimals=0))
    ax.yaxis.set_major_locator(matplotlib.ticker.MaxNLocator(nbins=6, steps=[1, 2, 5, 10], integer=True))
    ax.tick_params(axis="both", length=0, labelsize=8.5, colors=TEXT_2)
    ax.grid(color=GRID, linewidth=0.8, zorder=0)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(GRID)
    ax.set_title("Approving more clients means more trouble among them", loc="left", fontsize=12.5,
                 color=TEXT, fontweight="bold", pad=24)
    ax.text(0, 1.015, f"Valid clients who pass the exclusion list and policy rules. "
            f"Dashed line: target ({100 * target:.0f}%).", transform=ax.transAxes, fontsize=8.5,
            color=TEXT_2, va="bottom")
    fig.tight_layout()
    fig.savefig(ROOT / "docs" / "img" / "4b_tradeoff.png", facecolor=SURFACE)
    plt.close(fig)


def write_markdown(target, cutoff, res_valid, res_hold, table) -> None:
    lines = [
        "# PD cut-off (Stage 4b)",
        "",
        "_Generated by `python/scripts/choose_cutoff.py`. Do not edit by hand._",
        "",
        "## In plain words",
        "",
        "A lender can approve more clients or fewer. More approvals mean more business,",
        "but also more clients who later have trouble repaying. The rule agreed in",
        f"advance ([decision 25](decisions.md)): approve as many clients as possible while at most",
        f"**{100 * target:.0f}%** of the approved are expected to have repayment trouble.",
        "",
        f"**Chosen cut-off: PD {100 * cutoff:.2f}%** — a client whose calibrated PD is at or below this",
        "passes the risk step. The value is stored in `ref_rules` as `PD_CUTOFF`, not in code.",
        "",
        "![Approving more clients means more trouble among them](img/4b_tradeoff.png)",
        "",
        "## Result",
        "",
        "Among clients who pass the exclusion list and the policy rules:",
        "",
        "| Clients | Approved | Trouble among approved | Trouble among declined | Share of all trouble avoided |",
        "|---|---:|---:|---:|---:|",
    ]
    for name, r in (("valid (choice made here)", res_valid), ("holdout (report only)", res_hold)):
        lines.append(f"| {name} | {100 * r['approval_rate']:.1f}% | {100 * r['bad_rate_approved']:.2f}% | "
                     f"{100 * r['bad_rate_declined']:.2f}% | {100 * r['bads_caught']:.1f}% |")
    lines += [
        "",
        "## The trade-off",
        "",
        "Other choices a lender could make, on the same `valid` clients:",
        "",
        "| Approve | Cut-off PD | Trouble among approved | Share of all trouble avoided |",
        "|---:|---:|---:|---:|",
    ]
    for _, r in table.iterrows():
        lines.append(f"| {100 * r.approval_rate:.0f}% | {100 * r.cutoff:.2f}% | {100 * r.bad_rate_approved:.2f}% | "
                     f"{100 * r.bads_caught:.1f}% |")
    lines.append("")
    (ROOT / "docs" / "cutoff.md").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
