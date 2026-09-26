"""Stage 4e: the three facts behind every risk decline, in plain words.

In plain words: a client declined because the estimated risk is too high
(reason PD_ABOVE_CUTOFF) deserves to know WHY the risk is high. The model
can tell: SHAP values split each client's score into one part per fact,
compared with an average client. The three facts that raised the risk
most are written to Oracle as sentences, e.g.
    "35% of instalments in the last year were paid late"
The sentences come from ref_feature_text (texts as data), never from code.

Safety:
  - only the model named on the decisions (LightGBM, the model of record)
    and only its version on the decisions are accepted
  - reconciliation: for every client, the SHAP parts must add up exactly to
    the raw score stored in model_scores; otherwise the model file is not
    the one that scored the clients, and nothing is written
  - the run date's explanations are replaced in one transaction; checks
    are logged to dq_log like every other check (p_dq)

Output:
  Oracle: decision_risk_factors (view v_decision_explanations)
  docs/risk_factors.md        results in readable form (generated)
  docs/img/4e_risk_facts.png  the facts most often behind a risk decline

Run from the repository root, after sql\\run_decisions.sql:
    python python\\scripts\\explain_decisions.py
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # makes "import hcr" work

import matplotlib  # noqa: E402

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import oracledb  # noqa: E402
import pandas as pd  # noqa: E402

from hcr.db import connect, read_sql  # noqa: E402
from hcr.scoring import lightgbm_contributions, load_lightgbm  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SURFACE, LINE, TEXT, TEXT_2, GRID = "#fcfcfb", "#2a78d6", "#0b0b0b", "#52514e", "#e1e0d9"
TOP_N = 3
BATCH = 50_000
TOLERANCE = 1e-8
# facts about a person's circumstances rather than their credit behaviour (reported, not removed)
PERSONAL = ["app_education", "app_family_status", "app_children_cnt", "app_family_members_cnt",
            "app_income_type", "app_is_not_employed"]
DPD_STATUS = {0: "never late", 1: "up to 30 days late", 2: "31-60 days late", 3: "61-90 days late",
              4: "91-120 days late", 5: "more than 120 days late, or written off"}

LAST = "(SELECT run_date FROM v_decision_last_run)"
RUN_SQL = """SELECT run_id, TO_CHAR(run_date, 'YYYY-MM-DD') AS run_date, model_name, model_version
             FROM v_decision_last_run"""
TEXT_SQL = "SELECT feature_name, unit, short_label, text_value, text_zero, text_missing FROM ref_feature_text"
CLIENTS_SQL = f"""
SELECT m.*, s.raw_score, d.run_id, d.main_reason, d.pd AS decision_pd
FROM   decisions d
JOIN   decision_reasons r ON r.run_date = d.run_date AND r.sk_id_curr = d.sk_id_curr
                         AND r.reason_code = 'PD_ABOVE_CUTOFF'
JOIN   v_model_input m    ON m.sk_id_curr = d.sk_id_curr
JOIN   model_scores s     ON s.sk_id_curr = d.sk_id_curr
                         AND s.model_name = d.model_name AND s.model_version = d.model_version
WHERE  d.run_date = {LAST}
"""
INSERT_SQL = """
INSERT INTO decision_risk_factors (run_date, sk_id_curr, rank_no, run_id, feature_name, feature_value,
                                   contribution, fact_text, model_name, model_version, created_at)
VALUES (TO_DATE(:1, 'YYYY-MM-DD'), :2, :3, :4, :5, :6, :7, :8, :9, :10, SYSTIMESTAMP)"""
CHECKS = [
    ("DECISION_RISK_FACTORS", "every client declined for risk has its facts",
     f"SELECT COUNT(*) FROM decision_reasons r WHERE r.run_date = {LAST} AND r.reason_code = 'PD_ABOVE_CUTOFF' "
     "AND NOT EXISTS (SELECT 1 FROM decision_risk_factors f WHERE f.run_date = r.run_date "
     "AND f.sk_id_curr = r.sk_id_curr AND f.run_id = (SELECT run_id FROM v_decision_last_run))", 0),
    ("DECISION_RISK_FACTORS", "only facts of the latest run remain for this date",
     f"SELECT COUNT(*) FROM decision_risk_factors WHERE run_date = {LAST} "
     "AND run_id <> (SELECT run_id FROM v_decision_last_run)", 0),
    ("DECISION_RISK_FACTORS", "no facts for a client who was not declined for risk",
     f"SELECT COUNT(*) FROM decision_risk_factors f WHERE f.run_date = {LAST} AND NOT EXISTS "
     "(SELECT 1 FROM decision_reasons r WHERE r.run_date = f.run_date AND r.sk_id_curr = f.sk_id_curr "
     "AND r.reason_code = 'PD_ABOVE_CUTOFF')", 0),
    ("V_DECISION_EXPLANATIONS", "one explanation per client declined for risk",
     "SELECT (SELECT COUNT(*) FROM v_decision_explanations WHERE run_id = (SELECT run_id FROM v_decision_last_run)) "
     f"- (SELECT COUNT(*) FROM decision_reasons WHERE run_date = {LAST} AND reason_code = 'PD_ABOVE_CUTOFF') FROM dual", 0),
]


def format_value(value, unit: str) -> str:
    """A client's value written the way the sentence needs it."""
    if unit == "category":
        return str(value)
    v = float(value)
    if unit == "share":
        return f"{100 * v:.1f}%" if abs(v) < 0.1 else f"{100 * v:.0f}%"
    if unit == "amount":
        return f"{v:,.0f}"
    if unit in ("count", "days"):
        return f"{round(v):,.0f}"
    if unit == "decimal1":
        return f"{v:.1f}"
    if unit in ("decimal2", "score"):
        return f"{v:.2f}"
    if unit == "dpd_status":
        return DPD_STATUS.get(int(round(v)), f"level {v:g}")
    raise ValueError(f"unknown unit {unit}")


def fact_sentence(value, t: dict) -> str:
    """The plain-words sentence for one fact of one client (texts from ref_feature_text)."""
    missing = value is None or (not isinstance(value, str) and pd.isna(value))
    if missing:
        return t["text_missing"]
    if t["unit"] == "flag":
        return t["text_value"] if float(value) == 1 else t["text_zero"]
    if t["text_zero"] is not None and t["unit"] != "category" and float(value) == 0:
        return t["text_zero"]
    sentence = t["text_value"].replace("{value}", format_value(value, t["unit"]))
    return re.sub(r"\b1 days\b", "1 day", sentence)


def raw_value(value) -> str | None:
    if value is None or (not isinstance(value, str) and pd.isna(value)):
        return None
    return value if isinstance(value, str) else f"{float(value):.6g}"


def main() -> None:
    run = read_sql(RUN_SQL)
    if run.empty:
        sys.exit("No successful run of the decision engine yet: run sql\\run_decisions.sql first.")
    run = run.iloc[0]
    booster, meta = load_lightgbm()
    if run.model_name != meta["model"] or int(run.model_version) != int(meta["version"]):
        sys.exit(f"The decisions used {run.model_name} v{int(run.model_version)}, but models/ holds "
                 f"{meta['model']} v{meta['version']}: explanations would not match. Nothing written.")

    texts = read_sql(TEXT_SQL).set_index("feature_name").astype(object)
    texts = texts.where(texts.notna(), None)          # empty text -> None (pandas would give NaN, which counts as "true")
    missing_text = [f for f in meta["features"] if f not in texts.index]
    if missing_text:
        sys.exit(f"No plain-words text in ref_feature_text for: {missing_text}. Nothing written.")

    df = read_sql(CLIENTS_SQL).reset_index(drop=True)
    print(f"Run {int(run.run_id)} of {run.run_date}: {len(df):,} clients declined for risk\n")

    # ---- SHAP values and the reconciliation with the stored raw scores ----------
    contrib, base = lightgbm_contributions(booster, meta, df)
    gap = float(np.max(np.abs(base + contrib.sum(axis=1) - df.raw_score.to_numpy())))
    print(f"Reconciliation: SHAP parts add up to the stored raw score (largest gap {gap:.1e})")
    if gap > TOLERANCE:
        sys.exit("The model file does not reproduce the stored scores: nothing written.")

    # ---- top 3 risk-raising facts per client -------------------------------------
    features = meta["features"]
    order = np.argsort(-contrib, axis=1, kind="stable")[:, :TOP_N]
    top = np.take_along_axis(contrib, order, axis=1)
    t = texts.to_dict("index")
    rows, records = [], []
    for i in range(len(df)):
        rank = 0
        for j in range(TOP_N):
            if top[i, j] <= 0:                           # only facts that RAISED the risk
                break
            rank += 1
            f = features[order[i, j]]
            value = df.at[i, f]
            sentence = fact_sentence(value, t[f])
            rows.append((run.run_date, int(df.at[i, "sk_id_curr"]), rank, int(run.run_id), f, raw_value(value),
                         float(top[i, j]), sentence, run.model_name, int(run.model_version)))
            records.append({"sk_id_curr": int(df.at[i, "sk_id_curr"]), "rank": rank, "feature": f,
                            "fact": sentence})
    facts = pd.DataFrame(records)

    # ---- write: replace this run date's facts in one transaction -------------------
    with connect() as con, con.cursor() as cur:
        cur.execute("DELETE FROM decision_risk_factors WHERE run_date = TO_DATE(:1, 'YYYY-MM-DD')", [run.run_date])
        # every bind position typed explicitly, in the order of INSERT_SQL
        cur.setinputsizes(oracledb.DB_TYPE_VARCHAR, oracledb.DB_TYPE_NUMBER, oracledb.DB_TYPE_NUMBER,
                          oracledb.DB_TYPE_NUMBER, oracledb.DB_TYPE_VARCHAR, oracledb.DB_TYPE_VARCHAR,
                          oracledb.DB_TYPE_BINARY_DOUBLE, oracledb.DB_TYPE_VARCHAR, oracledb.DB_TYPE_VARCHAR,
                          oracledb.DB_TYPE_NUMBER)
        for k in range(0, len(rows), BATCH):
            cur.executemany(INSERT_SQL, rows[k:k + BATCH])
        con.commit()
        for table, check, sql, expected in CHECKS:
            cur.callproc("p_dq", [table, check, sql, expected])   # stops with an error if a check fails
    print(f"{len(rows):,} facts written for {facts.sk_id_curr.nunique():,} clients; "
          f"{len(CHECKS)} checks passed (see dq_log)\n")

    # ---- summaries -------------------------------------------------------------
    n = facts.sk_id_curr.nunique()
    freq = (facts.groupby("feature")
            .agg(in_top3=("sk_id_curr", "nunique"), first=("rank", lambda r: int((r == 1).sum())))
            .assign(share=lambda x: x.in_top3 / n, share_first=lambda x: x["first"] / n)
            .sort_values("in_top3", ascending=False))
    freq["label"] = [t[f]["short_label"] for f in freq.index]
    personal_any = facts[facts.feature.isin(PERSONAL)].sk_id_curr.nunique() / n
    personal_first = facts[(facts["rank"] == 1) & facts.feature.isin(PERSONAL)].sk_id_curr.nunique() / n

    test = df[df.split == "test"]
    examples = test.sample(3, random_state=7) if len(test) >= 3 else df.head(3)
    ex = []
    for _, r in examples.iterrows():
        fs = facts[facts.sk_id_curr == int(r.sk_id_curr)].sort_values("rank").fact.tolist()
        ex.append({"sk_id_curr": int(r.sk_id_curr), "pd": r.decision_pd, "main_reason": r.main_reason, "facts": fs})

    title = f"{freq.label.iloc[0]}: a top-3 fact in {100 * freq.share.iloc[0]:.0f}% of risk declines"
    draw(freq.head(12), title)
    write_markdown(run, n, len(df), gap, freq, personal_any, personal_first, ex, title)

    print("===== Facts most often behind a risk decline =====")
    for f, r in freq.head(12).iterrows():
        print(f"{r.label:<42} top 3: {100 * r.share:5.1f}%   #1: {100 * r.share_first:5.1f}%")
    print(f"\nA personal-circumstance fact (education, family, children, income type, not employed) "
          f"is in the top 3 for {100 * personal_any:.1f}% and #1 for {100 * personal_first:.1f}%")
    print("\n===== Three examples (test clients) =====")
    for e in ex:
        print(f"client {e['sk_id_curr']}  PD {100 * e['pd']:.1f}%  main reason {e['main_reason']}")
        for k, fct in enumerate(e["facts"], 1):
            print(f"   {k}. {fct}")
    print("\nWritten: decision_risk_factors, docs/risk_factors.md, docs/img/4e_risk_facts.png")
    print("\n===== 4e COMPLETE =====")


def draw(freq: pd.DataFrame, title: str) -> None:
    data = freq.iloc[::-1]
    fig, ax = plt.subplots(figsize=(9, 5.5), dpi=150)
    fig.patch.set_facecolor(SURFACE)
    ax.set_facecolor(SURFACE)
    y = np.arange(len(data))
    ax.barh(y, 100 * data.share, color=LINE, height=0.6, zorder=3)
    for yi, s in zip(y, data.share):
        ax.text(100 * s + 0.6, yi, f"{100 * s:.0f}%", va="center", fontsize=8.5, color=TEXT)
    ax.set_yticks(y, data.label)
    ax.set_xlim(0, 100 * data.share.max() * 1.15)
    ax.xaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(decimals=0))
    ax.xaxis.set_major_locator(matplotlib.ticker.MaxNLocator(nbins=6, steps=[1, 2, 5, 10], integer=True))
    ax.set_xlabel("Share of risk declines where the fact is among the top 3", fontsize=9.5, color=TEXT_2)
    ax.tick_params(axis="both", length=0, labelsize=8.5, colors=TEXT_2)
    ax.grid(axis="x", color=GRID, linewidth=0.8, zorder=0)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(GRID)
    fig.tight_layout(rect=(0, 0, 1, 0.9))
    fig.text(0.015, 0.965, title, fontsize=12, color=TEXT, fontweight="bold", va="top")
    fig.text(0.015, 0.915, "Clients declined because the estimated risk is above the cut-off; "
             "the 12 facts named most often.", fontsize=8.5, color=TEXT_2, va="top")
    fig.savefig(ROOT / "docs" / "img" / "4e_risk_facts.png", facecolor=SURFACE)
    plt.close(fig)


def write_markdown(run, n, clients, gap, freq, personal_any, personal_first, examples, title) -> None:
    lines = [
        "# Why the risk is high: three facts per client (Stage 4e)",
        "",
        "_Generated by `python/scripts/explain_decisions.py`. Do not edit by hand._",
        "",
        "## In plain words",
        "",
        "\"Your estimated risk is above our limit\" is a reason, but not an explanation. For every",
        "client declined for risk, the model is asked which of the client's facts raised the",
        "estimated risk most **compared with an average client** (SHAP values). The top three are",
        "stored with the decision as sentences a client can read, for example:",
        "",
    ]
    for e in examples[:1]:
        lines += [f"> {k}. {fct}" + ("  " if k < len(e["facts"]) else "") for k, fct in enumerate(e["facts"], 1)]
    lines += [
        "",
        "The sentences come from the table `ref_feature_text` (one per model feature), so a wording",
        "is improved by editing a row, not code. Only facts that *raised* the risk are named.",
        "",
        "## Which run",
        "",
        "| Run | Date | Model | Clients declined for risk | Explained | Largest SHAP reconciliation gap |",
        "|---|---|---|---:|---:|---:|",
        f"| {int(run.run_id)} | {run.run_date} | {run.model_name} v{int(run.model_version)} | {clients:,} | {n:,} | {gap:.1e} |",
        "",
        "For every client the SHAP parts add up to the raw score stored in `model_scores`: the",
        "explanation comes from exactly the model that made the decision.",
        "",
        "## The facts named most often",
        "",
        f"![{title}](img/4e_risk_facts.png)",
        "",
        "| Fact | Among the top 3 | Named first |",
        "|---|---:|---:|",
    ]
    for _, r in freq.head(15).iterrows():
        lines.append(f"| {r.label} | {100 * r.share:.1f}% | {100 * r.share_first:.1f}% |")
    lines += [
        "",
        "## Three examples (test clients, chosen at random)",
        "",
    ]
    for e in examples:
        lines.append(f"**Client {e['sk_id_curr']}** — PD {100 * e['pd']:.1f}%, main reason `{e['main_reason']}`")
        lines.append("")
        lines += [f"{k}. {fct}" for k, fct in enumerate(e["facts"], 1)]
        lines.append("")
    lines += [
        "## To review: facts about personal circumstances",
        "",
        "Some facts describe a person's circumstances rather than how they handled credit:",
        "education, family status, children, family size, income type, not being employed.",
        f"One of them is among the top 3 for **{100 * personal_any:.1f}%** of risk declines and named first for",
        f"**{100 * personal_first:.1f}%**. The model uses them like any other fact (only gender is excluded,",
        "[decision 13](decisions.md)). Whether a lender may use them, and name them to a client, is a",
        "question for its compliance team; these numbers show how much the answer would matter.",
        "",
    ]
    (ROOT / "docs" / "risk_factors.md").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
