"""Stage 6a: the dashboard's data, as small summary files for Tableau Public.

In plain words: Tableau Public cannot read Oracle, and everything published
there is public. So this script adds up the latest run of the decision
engine into a handful of small CSV files — counts, rates and averages per
group — and Tableau reads only those. No file contains a client ID or any
single client's data (decision 29).

Two safety nets before anything is written:
  - reconciliation: the files must add up to exactly the engine's totals
    (356,255 clients, the approvals of the run) in every direction;
    otherwise nothing is written
  - small groups: in the distribution files, a row describing fewer than
    MIN_CELL clients keeps its count but hides its rates (suppressed = 1),
    so no published number can describe a handful of people

Output (tableau/data/, all from the same run of the engine):
  run_info.csv          which run, model, cut-off and rule set
  kpi_by_split.csv      approval and repayment trouble per group of clients
  outcomes.csv          clients per main reason, with their repayment trouble
  reasons_all.csv       every reason that applied (a client can have several)
  risk_facts.csv        facts most often behind a risk decline (SHAP, Stage 4e)
  pd_distribution.csv   clients per 1-point PD band, approved or not
  grid_cells.csv        the limit grid: clients, approvals and limits per cell
  limit_distribution.csv  approved limits in bands of 100,000
  limit_basis.csv       which cap set the approved limit
  debt_rule.csv         the debt rule at other values (what-if page)

Run from the repository root, after sql\\run_decisions.sql and
python\\scripts\\explain_decisions.py:
    python python\\scripts\\export_tableau.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # makes "import hcr" work

import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402

from hcr.db import read_sql  # noqa: E402
from hcr.decisions import (DEBT_MULTIPLES, DECISIONS_SQL, LAST_RUN, REASONS_SQL, RULES_SQL,  # noqa: E402
                           RUN_SQL, split_stats, with_debt_multiple)

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "tableau" / "data"
MIN_CELL = 10                      # smallest group whose rates are published
SPLITS = ["fit", "valid", "holdout", "test"]
SPLIT_LABEL = {"fit": "Fit (model learned here)", "valid": "Valid (cut-off chosen here)",
               "holdout": "Holdout (final exam, report only)", "test": "Test (new applicants, outcome unknown)"}
PD_BIN = 0.01                      # PD bands of 1 percentage point ...
PD_TOP = 0.40                      # ... up to 40%, then one band "40% and above"
LIMIT_BIN = 100_000
BASIS_LABEL = {"GRID": "Limit grid (income x multiple)", "DEBT": "Debt rule (room left)",
               "MAX_LIMIT": "Maximum limit"}

GRID_SQL = f"""
SELECT g.pd_from, g.pd_to, g.income_from, g.income_to, g.income_multiple,
       COUNT(d.sk_id_curr)                                      AS clients,
       SUM(CASE WHEN d.decision = 'APPROVE' THEN 1 ELSE 0 END)  AS approved,
       AVG(d.offer_limit)                                       AS avg_limit,
       COUNT(p.target)                                          AS known_outcome_clients,
       SUM(p.target)                                            AS defaults
FROM   ref_limit_grid g
LEFT   JOIN decisions d
       ON  d.run_date = {LAST_RUN}
       AND d.pd >= g.pd_from AND (d.pd < g.pd_to OR g.pd_to = 1)
       AND d.income_amt >= g.income_from AND (g.income_to IS NULL OR d.income_amt < g.income_to)
LEFT   JOIN v_population p ON p.sk_id_curr = d.sk_id_curr
WHERE  g.valid_from <= {LAST_RUN} AND (g.valid_to IS NULL OR g.valid_to > {LAST_RUN})
GROUP  BY g.pd_from, g.pd_to, g.income_from, g.income_to, g.income_multiple
ORDER  BY g.pd_from, g.income_from
"""
OUTCOMES_SQL = f"""
SELECT split, decision, outcome, outcome_category, outcome_order, clients, clients_known_outcome,
       defaults, default_rate, avg_pd, total_limit, avg_limit
FROM   v_decision_summary
WHERE  run_date = {LAST_RUN}
"""
REASONS_ALL_SQL = f"""
SELECT d.split, r.reason_code, COUNT(*) AS clients
FROM   decision_reasons r
JOIN   decisions d ON d.run_date = r.run_date AND d.sk_id_curr = r.sk_id_curr
WHERE  r.run_date = {LAST_RUN}
GROUP  BY d.split, r.reason_code
"""
FACTS_SQL = f"""
SELECT f.feature_name, t.short_label, f.rank_no, COUNT(*) AS clients
FROM   decision_risk_factors f
JOIN   ref_feature_text t ON t.feature_name = f.feature_name
WHERE  f.run_date = {LAST_RUN} AND f.run_id = (SELECT run_id FROM v_decision_last_run)
GROUP  BY f.feature_name, t.short_label, f.rank_no
"""
EXPLAINED_SQL = f"""
SELECT COUNT(DISTINCT sk_id_curr) AS clients FROM decision_risk_factors
WHERE  run_date = {LAST_RUN} AND run_id = (SELECT run_id FROM v_decision_last_run)
"""


def band_label(lo: float, hi: float | None, pct: bool) -> str:
    if pct:
        return f"{100 * lo:g}% and above" if hi is None else f"{100 * lo:g}-{100 * hi:g}%"
    return f"{lo:,.0f} and above" if hi is None else f"{lo:,.0f}-{hi:,.0f}"


def suppress(df: pd.DataFrame, rate_cols: list[str]) -> pd.DataFrame:
    """Keep counts, hide rates of rows that describe fewer than MIN_CELL clients."""
    df = df.copy()
    small = (df.clients > 0) & (df.clients < MIN_CELL)
    df["suppressed"] = small.astype(int)
    df.loc[small, rate_cols] = np.nan
    return df


def check(name: str, ok: bool, detail: str, problems: list) -> None:
    print(f"  {'OK  ' if ok else 'FAIL'} {name}{'' if ok else ': ' + detail}")
    if not ok:
        problems.append(name)


def main() -> None:
    run = read_sql(RUN_SQL)
    if run.empty:
        sys.exit("No successful run of the decision engine yet: run sql\\run_decisions.sql first.")
    run = run.iloc[0]
    rules = read_sql(RULES_SQL).set_index("rule_code").rule_value.to_dict()
    reasons = read_sql(REASONS_SQL).set_index("reason_code")
    df = read_sql(DECISIONS_SQL)
    print(f"Run {int(run.run_id)} of {run.run_date}: {len(df):,} decisions read\n")
    files: dict[str, pd.DataFrame] = {}

    # ---- run_info -------------------------------------------------------------
    files["run_info"] = pd.DataFrame([{
        "run_id": int(run.run_id), "run_date": run.run_date, "model": run.model_name,
        "model_version": int(run.model_version), "pd_cutoff": run.pd_cutoff,
        "target_bad_rate": rules["TARGET_BAD_RATE"], "debt_rule_multiple": rules["MAX_TOTAL_DEBT_TO_INCOME"],
        "min_limit": rules["MIN_LIMIT"], "max_limit": rules["MAX_LIMIT"],
        "ruleset_hash": run.ruleset_hash, "clients": int(run.clients), "approved": int(run.approved)}])

    # ---- kpi_by_split ---------------------------------------------------------
    rows = []
    for s in SPLITS:
        g = df[df.split == s]
        st = split_stats(g)
        appr = g.decision == "APPROVE"
        rows.append({"split": s, "split_label": SPLIT_LABEL[s], "split_order": SPLITS.index(s) + 1,
                     "clients": st["clients"], "approved": int(appr.sum()), "declined": int((~appr).sum()),
                     "approval_rate": st["approval_rate"], "bad_rate_approved": st["bad_approved"],
                     "bad_rate_declined": st["bad_declined"], "expected_bad_rate_approved": st["expected_approved"],
                     "trouble_avoided": st["bads_avoided"], "avg_limit": st["avg_limit"],
                     "total_limit": g.offer_limit[appr].sum()})
    kpi = pd.DataFrame(rows)
    files["kpi_by_split"] = kpi

    # ---- outcomes (straight from the reconciled view v_decision_summary) ------
    out = read_sql(OUTCOMES_SQL)
    out["outcome_label"] = [("Pre-approved" if o == "APPROVED" else reasons.description.get(o, o))
                            for o in out.outcome]
    out["split_order"] = out.split.map({s: i + 1 for i, s in enumerate(SPLITS)})
    out["share_of_split"] = out.clients / out.split.map(kpi.set_index("split").clients)
    files["outcomes"] = out.sort_values(["split_order", "outcome_order"])

    # ---- reasons_all ------------------------------------------------------------
    ra = read_sql(REASONS_ALL_SQL)
    ra["description"] = ra.reason_code.map(reasons.description)
    ra["category"] = ra.reason_code.map(reasons.category)
    ra["reason_order"] = ra.reason_code.map(reasons.priority)
    ra["share_of_split"] = ra.clients / ra.split.map(kpi.set_index("split").clients)
    files["reasons_all"] = ra.sort_values(["split", "reason_order"])

    # ---- risk_facts ---------------------------------------------------------------
    fa = read_sql(FACTS_SQL)
    explained = int(read_sql(EXPLAINED_SQL).clients.iloc[0])
    facts = (fa.groupby(["feature_name", "short_label"])
             .apply(lambda x: pd.Series({"clients_in_top3": int(x.clients.sum()),
                                         "clients_first": int(x.clients[x.rank_no == 1].sum())}),
                    include_groups=False)
             .reset_index())
    facts["share_in_top3"] = facts.clients_in_top3 / explained
    facts["share_first"] = facts.clients_first / explained
    facts["explained_clients"] = explained
    files["risk_facts"] = facts.sort_values("clients_in_top3", ascending=False)

    # ---- pd_distribution ------------------------------------------------------------
    edges = np.round(np.arange(0, PD_TOP + PD_BIN / 2, PD_BIN), 4)
    b = np.minimum(np.floor(df.pd / PD_BIN + 1e-9).astype(int), len(edges) - 1)
    d2 = df.assign(bin=b, approved=(df.decision == "APPROVE").astype(int))
    pdd = (d2.groupby(["split", "bin"])
           .agg(clients=("sk_id_curr", "size"), approved=("approved", "sum"),
                known_outcome_clients=("target", "count"), defaults=("target", "sum"), avg_pd=("pd", "mean"))
           .reset_index())
    pdd["pd_from"] = edges[pdd.bin]
    pdd["pd_band"] = [band_label(edges[i], None if i == len(edges) - 1 else edges[i] + PD_BIN, True) for i in pdd.bin]
    pdd["approval_rate"] = pdd.approved / pdd.clients
    pdd["default_rate"] = np.where(pdd.known_outcome_clients > 0, pdd.defaults / pdd.known_outcome_clients.clip(lower=1), np.nan)
    pdd.loc[pdd.known_outcome_clients == 0, "defaults"] = np.nan
    pdd["split_order"] = pdd.split.map({s: i + 1 for i, s in enumerate(SPLITS)})
    files["pd_distribution"] = suppress(pdd.drop(columns="bin").sort_values(["split_order", "pd_from"]),
                                        ["approval_rate", "default_rate", "avg_pd"])

    # ---- grid_cells ---------------------------------------------------------------------
    gc = read_sql(GRID_SQL)
    gc["pd_band"] = [band_label(a, b, True) for a, b in zip(gc.pd_from, gc.pd_to)]
    gc["income_band"] = [band_label(a, None if pd.isna(b) else b, False) for a, b in zip(gc.income_from, gc.income_to)]
    gc["approval_rate"] = gc.approved / gc.clients.where(gc.clients > 0)
    gc["default_rate"] = gc.defaults / gc.known_outcome_clients.where(gc.known_outcome_clients > 0)
    files["grid_cells"] = suppress(gc, ["approval_rate", "default_rate", "avg_limit"])

    # ---- limit_distribution and limit_basis (approved clients) ---------------------------
    ap = df[df.decision == "APPROVE"]
    lb = np.minimum((ap.offer_limit // LIMIT_BIN).astype(int), int(rules["MAX_LIMIT"] // LIMIT_BIN) - 1)
    ld = ap.assign(bin=lb).groupby(["split", "bin"]).size().rename("clients").reset_index()
    ld["limit_from"] = ld.bin * LIMIT_BIN
    ld["limit_band"] = [band_label(a, a + LIMIT_BIN, False) for a in ld.limit_from]
    ld["split_order"] = ld.split.map({s: i + 1 for i, s in enumerate(SPLITS)})
    files["limit_distribution"] = suppress(ld.drop(columns="bin").sort_values(["split_order", "limit_from"]), [])
    lbs = (ap.groupby("limit_basis").offer_limit.agg(clients="size", avg_limit="mean", min_limit="min", max_limit="max")
           .reset_index())
    lbs["limit_basis_label"] = lbs.limit_basis.map(BASIS_LABEL)
    files["limit_basis"] = lbs

    # ---- debt_rule (what-if) ----------------------------------------------------------------
    rows = []
    for s in ["valid", "holdout", "test"]:
        g = df[df.split == s]
        known = g.target.notna().all()
        for k in DEBT_MULTIPLES:
            a, lim = with_debt_multiple(g, k, rules)
            rows.append({"split": s, "split_label": SPLIT_LABEL[s],
                         "debt_multiple": 99 if k is None else k,
                         "debt_rule": "No debt rule" if k is None else f"{k:g} x income",
                         "in_force": int(k == rules["MAX_TOTAL_DEBT_TO_INCOME"]),
                         "clients": len(g), "approved": int(a.sum()), "approval_rate": a.mean(),
                         "bad_rate_approved": g.target[a].mean() if known else np.nan,
                         "expected_bad_rate_approved": g.pd[a].mean(), "avg_limit": lim[a].mean(),
                         "declined_by_debt_rule": int(((g.other_reason == 0) & ~a).sum())})
    dr = pd.DataFrame(rows)
    files["debt_rule"] = dr

    # ---- reconciliation: every file adds up to the engine's totals --------------------------
    print("Reconciliation with the engine's run")
    problems: list[str] = []
    total, approved = int(run.clients), int(run.approved)
    check("clients per group add up to the run", kpi.clients.sum() == total, f"{kpi.clients.sum()} vs {total}", problems)
    check("approvals per group add up to the run", kpi.approved.sum() == approved, f"{kpi.approved.sum()} vs {approved}", problems)
    oc = out.groupby("split").clients.sum().reindex(SPLITS)
    check("outcomes = clients, per group", (oc.values == kpi.clients.values).all(), str(oc.to_dict()), problems)
    oa = out[out.outcome == "APPROVED"].groupby("split").clients.sum().reindex(SPLITS)
    check("outcome APPROVED = approvals, per group", (oa.values == kpi.approved.values).all(), str(oa.to_dict()), problems)
    pc = pdd.groupby("split").clients.sum().reindex(SPLITS)
    check("PD bands = clients, per group", (pc.values == kpi.clients.values).all(), str(pc.to_dict()), problems)
    check("limit grid cells = all clients", int(gc.clients.sum()) == total, f"{int(gc.clients.sum())} vs {total}", problems)
    lc = ld.groupby("split").clients.sum().reindex(SPLITS)
    check("limit bands = approvals, per group", (lc.values == kpi.approved.values).all(), str(lc.to_dict()), problems)
    check("limit basis = all approvals", int(lbs.clients.sum()) == approved, f"{int(lbs.clients.sum())} vs {approved}", problems)
    dk = dr[dr.in_force == 1].set_index("split").approved
    ka = kpi.set_index("split").approved.reindex(dk.index)
    check("debt rule in force = the engine's approvals", (dk.values == ka.values).all(), f"{dk.to_dict()} vs {ka.to_dict()}", problems)
    check("risk facts cover every explained client", int(facts.clients_first.sum()) == explained,
          f"{int(facts.clients_first.sum())} vs {explained}", problems)
    check("no client ID in any file", all("sk_id_curr" not in f.columns for f in files.values()), "sk_id_curr found", problems)
    if problems:
        sys.exit(f"\n{len(problems)} reconciliation check(s) failed: nothing written.")

    # ---- write ---------------------------------------------------------------------------------
    OUT.mkdir(parents=True, exist_ok=True)
    for name, f in files.items():
        f = f.copy()
        for col in f.select_dtypes("float").columns:     # rates to 6 decimals, amounts to 2, counts as whole numbers
            is_rate = any(w in col for w in ("rate", "share", "pd", "avoided"))
            values = f[col].dropna()
            if not is_rate and len(values) and (values == values.round()).all():
                f[col] = f[col].round().astype("Int64")
            else:
                f[col] = f[col].round(6 if is_rate else 2)
        f.to_csv(OUT / f"{name}.csv", index=False, encoding="utf-8")
    hidden = sum(int(f["suppressed"].sum()) for f in files.values() if "suppressed" in f.columns)
    print(f"\n{len(files)} files written to tableau/data/ "
          f"({hidden} small rows with rates hidden, fewer than {MIN_CELL} clients)")
    for name, f in files.items():
        print(f"  {name + '.csv':<24} {len(f):>4} rows")

    print("\n===== Key numbers (holdout) =====")
    h = kpi.set_index("split").loc["holdout"]
    print(f"approved {100 * h.approval_rate:.1f}%  trouble among approved {100 * h.bad_rate_approved:.2f}%  "
          f"among declined {100 * h.bad_rate_declined:.2f}%  trouble avoided {100 * h.trouble_avoided:.1f}%")
    print("\n===== 6a COMPLETE =====")


if __name__ == "__main__":
    main()
