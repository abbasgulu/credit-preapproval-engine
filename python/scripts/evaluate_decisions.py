"""Stage 4d: how well do the decisions work?

In plain words: the engine has approved or declined every client. For the
clients whose outcome is known we can now check what happened to them:
did the approved clients repay, and were the declined ones really riskier?
For the test clients (outcome unknown, they stand in for new applicants) we
report how much trouble the model expects among those approved.

What is measured, all on the latest successful run of the engine:
  - holdout (known outcome, never used for any choice): approval rate,
    share with repayment trouble among approved and declined, and the share
    of all trouble avoided by declining
  - the same per main reason: is each rule declining riskier clients?
  - test: approval rate and the expected trouble (average PD) of approved
  - the debt rule (MAX_TOTAL_DEBT_TO_INCOME) at other values, on `valid`:
    how many more or fewer clients would be approved and how risky they
    are. This is a decision aid only; nothing is changed in ref_rules.
  - a reconciliation: Python recomputes the engine's decision and limit for
    every client with the rule values in force; they must match exactly

Output:
  docs/decision_engine.md     results in readable form (generated)
  docs/img/4d_outcomes.png    share with trouble per outcome (holdout)
  docs/img/4d_debt_rule.png   the debt rule at other values (valid)

Run from the repository root, after sql\\run_decisions.sql:
    python python\\scripts\\evaluate_decisions.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # makes "import hcr" work

import matplotlib  # noqa: E402

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402

from hcr.db import read_sql  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SURFACE, LINE, TEXT, TEXT_2, GRID, MARK = "#fcfcfb", "#2a78d6", "#0b0b0b", "#52514e", "#e1e0d9", "#eb6834"
DEBT_MULTIPLES = [3, 4, 5, 6, 8, 10, None]      # None = no debt rule at all
TOLERANCE = 1e-6                                # Python floats vs Oracle's exact decimals

LAST_RUN = "(SELECT run_date FROM v_decision_last_run)"
RUN_SQL = """SELECT run_id, TO_CHAR(run_date, 'YYYY-MM-DD') AS run_date, model_name, model_version,
                    pd_cutoff, ruleset_hash, clients, approved
             FROM   v_decision_last_run"""
RULES_SQL = f"""SELECT rule_code, rule_value FROM ref_rules
                WHERE  valid_from <= {LAST_RUN} AND (valid_to IS NULL OR valid_to > {LAST_RUN})"""
REASONS_SQL = "SELECT reason_code, category, priority, description FROM ref_reason_codes ORDER BY priority"
DECISIONS_SQL = f"""
SELECT d.sk_id_curr, d.split, d.decision, d.main_reason, d.pd, d.offer_limit,
       d.income_amt, d.active_debt, d.grid_limit, p.target,
       NVL(o.other_reason, 0) AS other_reason
FROM   decisions d
JOIN   v_population p ON p.sk_id_curr = d.sk_id_curr
LEFT   JOIN (SELECT sk_id_curr,
                    MAX(CASE WHEN reason_code <> 'DEBT_TOO_HIGH' THEN 1 ELSE 0 END) AS other_reason
             FROM   decision_reasons
             WHERE  run_date = {LAST_RUN}
             GROUP  BY sk_id_curr) o ON o.sk_id_curr = d.sk_id_curr
WHERE  d.run_date = {LAST_RUN}
"""
MODELS_SQL = """
SELECT s.model_name, s.split, AVG(s.pd) AS avg_pd, AVG(p.target) AS actual
FROM   v_scores s
JOIN   v_population p ON p.sk_id_curr = s.sk_id_curr
WHERE  s.split IN ('holdout', 'test')
AND    s.model_version = (SELECT MAX(m.model_version) FROM model_scores m WHERE m.model_name = s.model_name)
GROUP  BY s.model_name, s.split
ORDER  BY s.model_name, s.split
"""


def pct(x: float, d: int = 1) -> str:
    return "–" if pd.isna(x) else f"{100 * x:.{d}f}%"


def with_debt_multiple(g: pd.DataFrame, k, rules: dict) -> tuple[pd.Series, pd.Series]:
    """The engine's steps 4-5 with a different debt multiple k (None = no debt rule).
    Every other reason (exclusion, policy, risk, small grid limit) is kept as the engine found it."""
    room = np.inf if k is None else k * g.income_amt - g.active_debt
    limit = np.minimum(np.minimum(g.grid_limit, room), rules["MAX_LIMIT"]).clip(lower=0)
    approve = (g.other_reason == 0) & (limit >= rules["MIN_LIMIT"] - TOLERANCE)
    return approve, limit


def split_stats(g: pd.DataFrame) -> dict:
    appr = g.decision == "APPROVE"
    known = g.target.notna().all()
    return {
        "clients": len(g),
        "approval_rate": appr.mean(),
        "bad_approved": g.target[appr].mean() if known else np.nan,
        "expected_approved": g.pd[appr].mean(),
        "bad_declined": g.target[~appr].mean() if known else np.nan,
        "bads_avoided": g.target[~appr].sum() / g.target.sum() if known else np.nan,
        "avg_limit": g.offer_limit[appr].mean(),
    }


def main() -> None:
    run = read_sql(RUN_SQL)
    if run.empty:
        sys.exit("No successful run of the decision engine yet: run sql\\run_decisions.sql first.")
    run = run.iloc[0]
    rules = read_sql(RULES_SQL).set_index("rule_code").rule_value.to_dict()
    reasons = read_sql(REASONS_SQL)
    df = read_sql(DECISIONS_SQL)
    models = read_sql(MODELS_SQL)
    print(f"Run {int(run.run_id)} of {run.run_date}: {len(df):,} decisions read\n")

    # ---- reconciliation: Python recomputes the engine's decision and limit ----
    approve, limit = with_debt_multiple(df, rules["MAX_TOTAL_DEBT_TO_INCOME"], rules)
    engine_approve = df.decision == "APPROVE"
    diff_decision = int((approve != engine_approve).sum())
    diff_limit = int((np.abs(limit[engine_approve] - df.offer_limit[engine_approve]) > 0.01).sum())
    print(f"Reconciliation: {diff_decision} decisions and {diff_limit} limits differ between Python and Oracle")
    if diff_decision or diff_limit:
        sys.exit("Python and the engine disagree: nothing written. Investigate before reporting.")

    # ---- results per group of clients ----------------------------------------
    splits = {s: split_stats(df[df.split == s]) for s in ("valid", "holdout", "test")}

    # ---- per main reason, holdout ----------------------------------------------
    hold = df[df.split == "holdout"]
    order = ["APPROVED"] + reasons.reason_code.tolist()
    hold_outcome = hold.main_reason.fillna("APPROVED")
    by_reason = (hold.assign(outcome=hold_outcome)
                 .groupby("outcome")
                 .agg(clients=("sk_id_curr", "size"), bad_rate=("target", "mean"), avg_pd=("pd", "mean"))
                 .reindex([o for o in order if o in set(hold_outcome)]))
    by_reason["share"] = by_reason.clients / len(hold)
    overall_bad = hold.target.mean()
    debt_only = hold[(hold.decision == "DECLINE") & (hold.other_reason == 0)]

    # ---- the debt rule at other values, valid -----------------------------------
    valid = df[df.split == "valid"]
    rows = []
    for k in DEBT_MULTIPLES:
        a, lim = with_debt_multiple(valid, k, rules)
        rows.append({"k": k, "approval_rate": a.mean(), "bad_approved": valid.target[a].mean(),
                     "avg_limit": lim[a].mean(), "debt_declines": int(((valid.other_reason == 0) & ~a).sum())})
    sens = pd.DataFrame(rows)
    current_k = rules["MAX_TOTAL_DEBT_TO_INCOME"]

    ratio = splits["holdout"]["bad_declined"] / splits["holdout"]["bad_approved"]
    outcomes_title = f"Declined clients had {ratio:.1f}× the repayment trouble of approved ones"
    cur, loose = sens[sens.k == current_k].iloc[0], sens[sens.k.isna()].iloc[0]
    debt_title = (f"Without the debt rule: {100 * (loose.approval_rate - cur.approval_rate):+.1f} pp approved, "
                  f"trouble {100 * cur.bad_approved:.1f}% → {100 * loose.bad_approved:.1f}%")
    draw_outcomes(by_reason, overall_bad, outcomes_title)
    draw_debt_rule(sens, current_k, rules["TARGET_BAD_RATE"], debt_title)
    write_markdown(run, rules, splits, by_reason, overall_bad, debt_only, sens, current_k, reasons, models,
                   outcomes_title, debt_title)

    # ---- console summary ----------------------------------------------------
    print("\n===== Decisions by group of clients =====")
    print(f"{'group':<8} {'approved':>9} {'trouble approved':>17} {'expected (PD)':>14} "
          f"{'trouble declined':>17} {'trouble avoided':>16} {'avg limit':>10}")
    for s, r in splits.items():
        print(f"{s:<8} {pct(r['approval_rate']):>9} {pct(r['bad_approved'], 2):>17} {pct(r['expected_approved'], 2):>14} "
              f"{pct(r['bad_declined'], 2):>17} {pct(r['bads_avoided']):>16} {r['avg_limit']:>10,.0f}")
    print("\n===== Holdout: share with repayment trouble per outcome =====")
    for o, r in by_reason.iterrows():
        print(f"{o:<18} {int(r.clients):>7,} clients {pct(r.share):>6}   trouble {pct(r.bad_rate, 2):>7}")
    print(f"{'(overall)':<18} {len(hold):>7,} clients           trouble {pct(overall_bad, 2):>7}")
    print(f"declined ONLY by the debt rule: {len(debt_only):,} clients, trouble {pct(debt_only.target.mean(), 2)}")
    print("\n===== Valid: the debt rule at other values (decision aid, nothing changed) =====")
    for _, r in sens.iterrows():
        label = "no rule" if r.k is None or pd.isna(r.k) else f"{r.k:g} x income"
        mark = "  <- in force" if r.k == current_k else ""
        print(f"{label:<13} approve {pct(r.approval_rate):>6}  trouble among approved {pct(r.bad_approved, 2):>6}  "
              f"avg limit {r.avg_limit:>9,.0f}{mark}")
    print("\nWritten: docs/decision_engine.md, docs/img/4d_outcomes.png, docs/img/4d_debt_rule.png")
    print("\n===== 4d COMPLETE =====")


def _style(ax) -> None:
    ax.set_facecolor(SURFACE)
    ax.tick_params(axis="both", length=0, labelsize=8.5, colors=TEXT_2)
    ax.grid(color=GRID, linewidth=0.8, zorder=0)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(GRID)


def draw_outcomes(by_reason: pd.DataFrame, overall: float, title: str) -> None:
    data = by_reason.iloc[::-1]                      # first outcome on top
    fig, ax = plt.subplots(figsize=(9, 5), dpi=150)
    fig.patch.set_facecolor(SURFACE)
    _style(ax)
    ax.grid(axis="y", visible=False)
    colors = [MARK if o == "APPROVED" else LINE for o in data.index]
    y = np.arange(len(data))
    ax.barh(y, 100 * data.bad_rate, color=colors, height=0.6, zorder=3)
    ax.axvline(100 * overall, color=TEXT_2, linewidth=1, linestyle=(0, (4, 3)), zorder=4)
    for yi, (o, r) in zip(y, data.iterrows()):
        ax.text(100 * r.bad_rate + 0.4, yi, f"{100 * r.bad_rate:.1f}%  ({int(r.clients):,} clients)",
                va="center", fontsize=8.5, color=TEXT, zorder=5,
                bbox={"facecolor": SURFACE, "edgecolor": "none", "pad": 1.5})
    ax.set_yticks(y, [o.replace("_", " ").lower() if o != "APPROVED" else "approved" for o in data.index])
    ax.set_xlim(0, 100 * data.bad_rate.max() * 1.45)
    ax.xaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(decimals=0))
    ax.xaxis.set_major_locator(matplotlib.ticker.MaxNLocator(nbins=6, steps=[1, 2, 5, 10], integer=True))
    ax.set_xlabel("Clients with repayment trouble", fontsize=9.5, color=TEXT_2)
    ax.set_title(title, loc="left",
                 fontsize=12.5, color=TEXT, fontweight="bold", pad=24)
    ax.text(0, 1.015, f"Holdout clients by outcome (main reason). Dashed line: all holdout clients "
            f"({100 * overall:.1f}%).", transform=ax.transAxes, fontsize=8.5, color=TEXT_2, va="bottom")
    fig.tight_layout()
    fig.savefig(ROOT / "docs" / "img" / "4d_outcomes.png", facecolor=SURFACE)
    plt.close(fig)


def draw_debt_rule(sens: pd.DataFrame, current_k: float, target: float, title: str) -> None:
    fig, ax = plt.subplots(figsize=(9, 5), dpi=150)
    fig.patch.set_facecolor(SURFACE)
    _style(ax)
    x, y = 100 * sens.approval_rate, 100 * sens.bad_approved
    ax.plot(x, y, color=LINE, linewidth=2, marker="o", markersize=8, markeredgecolor=SURFACE,
            markeredgewidth=2, zorder=3)
    ax.axhline(100 * target, color=TEXT_2, linewidth=1, linestyle=(0, (4, 3)), zorder=2)
    for i, (xi, yi, k) in enumerate(zip(x, y, sens.k)):
        is_current = k == current_k
        if is_current:
            ax.plot([xi], [yi], marker="o", markersize=10, color=MARK, markeredgecolor=SURFACE,
                    markeredgewidth=2, zorder=4)
        label = "no debt rule" if k is None or pd.isna(k) else f"{k:g} × income"
        above = i % 2 == 0                            # alternate above / below: no overlapping labels
        ax.annotate(label + ("\n(in force)" if is_current else ""), (xi, yi), xytext=(0, 11 if above else -13),
                    textcoords="offset points", ha="center", va="bottom" if above else "top",
                    fontsize=8.5, color=TEXT, zorder=5,
                    bbox={"facecolor": SURFACE, "edgecolor": "none", "pad": 1.5})   # lines pass behind labels
    ax.set_xlim(x.min() - 3, x.max() + 3)
    ax.set_ylim(min(y.min(), 100 * target) - 0.5, max(y.max(), 100 * target) + 0.8)
    ax.xaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(decimals=0))
    ax.yaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(decimals=1))
    for axis in (ax.xaxis, ax.yaxis):
        axis.set_major_locator(matplotlib.ticker.MaxNLocator(nbins=7, steps=[1, 2, 5, 10]))
    ax.set_xlabel("Share of clients approved", fontsize=9.5, color=TEXT_2)
    ax.set_ylabel("Clients with repayment trouble among the approved", fontsize=9.5, color=TEXT_2)
    ax.set_title(title, loc="left",
                 fontsize=12.5, color=TEXT, fontweight="bold", pad=24)
    ax.text(0, 1.015, f"Valid clients. Debt at other lenders + offer may not exceed k × income. "
            f"Dashed line: target ({100 * target:.0f}%).", transform=ax.transAxes, fontsize=8.5,
            color=TEXT_2, va="bottom")
    fig.tight_layout()
    fig.savefig(ROOT / "docs" / "img" / "4d_debt_rule.png", facecolor=SURFACE)
    plt.close(fig)


def write_markdown(run, rules, splits, by_reason, overall_bad, debt_only, sens, current_k, reasons, models,
                   outcomes_title, debt_title) -> None:
    hold = splits["holdout"]
    debt_bad = debt_only.target.mean()
    appr_bad = hold["bad_approved"]
    if debt_bad > 1.25 * appr_bad:
        debt_verdict = "riskier than the approved clients, so the rule also removes risk the model did not see"
    elif debt_bad < 0.8 * appr_bad:
        debt_verdict = "safer than the approved clients, so the rule mainly turns away good clients"
    else:
        debt_verdict = "about as risky as the approved clients, so the rule mainly limits exposure, not risk"
    desc = reasons.set_index("reason_code").description.to_dict()

    lines = [
        "# The decision engine: results (Stage 4d)",
        "",
        "_Generated by `python/scripts/evaluate_decisions.py`. Do not edit by hand._",
        "",
        "## In plain words",
        "",
        "Every client was approved with a limit or declined with reasons by one procedure,",
        "`p_run_decisions`, which reads all its rules from tables ([stage4_design.md](stage4_design.md)).",
        "For clients whose outcome is known we can check whether the decisions were sensible:",
        f"**{pct(appr_bad)}** of the approved holdout clients had repayment trouble, against",
        f"**{pct(hold['bad_declined'])}** of the declined ones. Declining {pct(1 - hold['approval_rate'])} of the clients",
        f"avoided **{pct(hold['bads_avoided'])}** of all repayment trouble.",
        "",
        "## Which run",
        "",
        "| Run | Date | Model | PD cut-off | Rule-set fingerprint | Clients | Approved |",
        "|---|---|---|---:|---|---:|---:|",
        f"| {int(run.run_id)} | {run.run_date} | {run.model_name} v{int(run.model_version)} | {pct(run.pd_cutoff, 2)} | "
        f"`{run.ruleset_hash}` | {int(run.clients):,} | {int(run.approved):,} |",
        "",
        "Python recomputed every decision and limit from the same rules: all of them match the",
        "engine's (reconciliation, [improvement 10](before_after.md)).",
        "",
        "## Results by group of clients",
        "",
        "| Group | Clients | Approved | Trouble among approved | Expected trouble (average PD) | Trouble among declined | Trouble avoided | Average limit |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    names = {"valid": "valid (cut-off chosen here)", "holdout": "holdout (report only)",
             "test": "test (outcome unknown)"}
    for s, r in splits.items():
        lines.append(f"| {names[s]} | {r['clients']:,} | {pct(r['approval_rate'])} | {pct(r['bad_approved'], 2)} | "
                     f"{pct(r['expected_approved'], 2)} | {pct(r['bad_declined'], 2)} | {pct(r['bads_avoided'])} | "
                     f"{r['avg_limit']:,.0f} |")
    lines += [
        "",
        "The cut-off was chosen so that at most "
        f"{pct(rules['TARGET_BAD_RATE'], 0)} of approved `valid` clients have trouble ([cutoff.md](cutoff.md));",
        "the other rules decline some more clients after it. For the test clients the outcome is",
        "unknown, so only the model's expectation can be shown.",
        "",
        "## Is each rule declining riskier clients?",
        "",
        f"![{outcomes_title}](img/4d_outcomes.png)",
        "",
        "| Outcome (main reason) | Meaning | Clients | Share | Trouble | Average PD |",
        "|---|---|---:|---:|---:|---:|",
    ]
    for o, r in by_reason.iterrows():
        meaning = "Pre-approved" if o == "APPROVED" else desc.get(o, "")
        lines.append(f"| `{o}` | {meaning} | {int(r.clients):,} | {pct(r.share)} | {pct(r.bad_rate, 2)} | "
                     f"{pct(r.avg_pd, 2)} |")
    lines += [
        f"| all holdout clients | | {int(by_reason.clients.sum()):,} | 100.0% | {pct(overall_bad, 2)} | |",
        "",
        f"Clients declined **only** by the debt rule: {len(debt_only):,}, of whom {pct(debt_bad, 2)} had trouble —",
        f"{debt_verdict}.",
        "",
        "## The debt rule at other values (decision aid)",
        "",
        f"The rule in force: active debt at other lenders plus the offer may not exceed "
        f"**{current_k:g} × income** (`MAX_TOTAL_DEBT_TO_INCOME`, an illustrative choice).",
        "Below, the same `valid` clients with other values; every other rule is unchanged.",
        "**Nothing is changed in `ref_rules`**: a new value would be a new, dated row, decided by a person.",
        "",
        f"![{debt_title}](img/4d_debt_rule.png)",
        "",
        "| Debt rule | Approved | Trouble among approved | Declined by the debt rule | Average limit |",
        "|---|---:|---:|---:|---:|",
    ]
    for _, r in sens.iterrows():
        label = "no debt rule" if r.k is None or pd.isna(r.k) else f"{r.k:g} × income"
        if r.k == current_k:
            label = f"**{label} (in force)**"
        lines.append(f"| {label} | {pct(r.approval_rate)} | {pct(r.bad_approved, 2)} | {int(r.debt_declines):,} | "
                     f"{r.avg_limit:,.0f} |")
    m = models.set_index(["model_name", "split"])
    lines += [
        "",
        "## Things to watch",
        "",
        "| Model | Average PD, holdout | Actual, holdout | Average PD, test |",
        "|---|---:|---:|---:|",
    ]
    for name in sorted(models.model_name.unique()):
        lines.append(f"| {name} | {pct(m.loc[(name, 'holdout'), 'avg_pd'], 2)} | "
                     f"{pct(m.loc[(name, 'holdout'), 'actual'], 2)} | {pct(m.loc[(name, 'test'), 'avg_pd'], 2)} |")
    hold_gap = max(abs(m.loc[(n, "holdout"), "avg_pd"] - m.loc[(n, "holdout"), "actual"]) for n in models.model_name.unique())
    test_pd = [m.loc[(n, "test"), "avg_pd"] for n in sorted(models.model_name.unique())]
    lines += [
        "",
        f"On the holdout, each model's average PD is within {100 * hold_gap:.2f} percentage points of the actual rate.",
        f"On the test clients the two models' averages differ by {100 * (max(test_pd) - min(test_pd)):.2f} points, and the",
        "outcome is unknown, so nobody can yet say which is closer. In live use this is what monitoring is for:",
        "once outcomes arrive, compare them with the expectation, and recalibrate if they drift apart.",
        "",
    ]
    (ROOT / "docs" / "decision_engine.md").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
