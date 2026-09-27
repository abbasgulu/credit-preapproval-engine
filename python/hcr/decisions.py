"""Reading the decision engine's results — written once, used by every report.

In plain words: the evaluation (Stage 4d) and the dashboard export (Stage 6)
both need the latest run of the engine, the rules it used, every client's
decision, and the "what if the debt rule were different" calculation. They
take all of it from here, so the two can never disagree.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

DEBT_MULTIPLES = [3, 4, 5, 6, 8, 10, None]      # None = no debt rule at all
TOLERANCE = 1e-6                                # Python floats vs Oracle's exact decimals

LAST_RUN = "(SELECT run_date FROM v_decision_last_run)"

RUN_SQL = """SELECT run_id, TO_CHAR(run_date, 'YYYY-MM-DD') AS run_date, model_name, model_version,
                    pd_cutoff, ruleset_hash, clients, approved
             FROM   v_decision_last_run"""

RULES_SQL = f"""SELECT rule_code, rule_value FROM ref_rules
                WHERE  valid_from <= {LAST_RUN} AND (valid_to IS NULL OR valid_to > {LAST_RUN})"""

REASONS_SQL = "SELECT reason_code, category, priority, description FROM ref_reason_codes ORDER BY priority"

# one row per client of the latest run; other_reason = 1 when any reason other than the debt rule applies
DECISIONS_SQL = f"""
SELECT d.sk_id_curr, d.split, d.decision, d.main_reason, d.pd, d.offer_limit,
       d.income_amt, d.active_debt, d.grid_limit, d.limit_basis, p.target,
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


def with_debt_multiple(g: pd.DataFrame, k, rules: dict) -> tuple[pd.Series, pd.Series]:
    """The engine's steps 4-5 with a different debt multiple k (None = no debt rule).
    Every other reason (exclusion, policy, risk, small grid limit) is kept as the engine found it."""
    room = np.inf if k is None else k * g.income_amt - g.active_debt
    limit = np.minimum(np.minimum(g.grid_limit, room), rules["MAX_LIMIT"]).clip(lower=0)
    approve = (g.other_reason == 0) & (limit >= rules["MIN_LIMIT"] - TOLERANCE)
    return approve, limit


def split_stats(g: pd.DataFrame) -> dict:
    """Approval and repayment trouble for one group of clients (trouble only where the outcome is known)."""
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
