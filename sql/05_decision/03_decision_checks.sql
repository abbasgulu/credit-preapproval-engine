-- =====================================================================
-- 03_decision_checks.sql
-- Stage 4c: checks and a first summary of the latest successful run.
--
-- In plain words: the engine's output is checked by SEPARATE queries that
-- read the rules again from the ref_ tables - they do not trust the
-- engine's own arithmetic. Every client must have exactly one decision,
-- every decline a reason, and no approved client may break any rule:
-- not the exclusion list, not a policy rule, not the cut-off, not the
-- limit grid, not the debt cap, not the minimum or maximum limit.
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE

-- run date of the latest successful run, used by every check below:
--   (SELECT run_date FROM v_decision_last_run)

EXEC p_dq('DECISIONS', 'every client has exactly one decision (356,255)', 'SELECT COUNT(*) FROM decisions WHERE run_date = (SELECT run_date FROM v_decision_last_run)', 356255)
EXEC p_dq('DECISIONS', 'a re-run replaced this date: only rows of the latest run remain', 'SELECT COUNT(*) FROM decisions d JOIN v_decision_last_run l ON l.run_date = d.run_date WHERE d.run_id <> l.run_id', 0)
EXEC p_dq('DECISIONS', 'every decline has a main reason; no approval has one', 'SELECT COUNT(*) FROM decisions WHERE run_date = (SELECT run_date FROM v_decision_last_run) AND ((decision = ''DECLINE'' AND (main_reason IS NULL OR reason_count = 0)) OR (decision = ''APPROVE'' AND (main_reason IS NOT NULL OR reason_count <> 0)))', 0)
EXEC p_dq('DECISION_REASONS', 'reason rows = reasons counted on the decisions', 'SELECT (SELECT COUNT(*) FROM decision_reasons WHERE run_date = (SELECT run_date FROM v_decision_last_run)) - (SELECT SUM(reason_count) FROM decisions WHERE run_date = (SELECT run_date FROM v_decision_last_run)) FROM dual', 0)
EXEC p_dq('DECISIONS', 'main reason = the reason with the lowest priority number', 'SELECT COUNT(*) FROM decisions d WHERE d.run_date = (SELECT run_date FROM v_decision_last_run) AND d.decision = ''DECLINE'' AND d.main_reason <> (SELECT MIN(r.reason_code) KEEP (DENSE_RANK FIRST ORDER BY c.priority, r.reason_code) FROM decision_reasons r JOIN ref_reason_codes c ON c.reason_code = r.reason_code WHERE r.run_date = d.run_date AND r.sk_id_curr = d.sk_id_curr)', 0)
EXEC p_dq('DECISIONS', 'no approved client is on the exclusion list', 'SELECT COUNT(*) FROM decisions d WHERE d.run_date = (SELECT run_date FROM v_decision_last_run) AND d.decision = ''APPROVE'' AND EXISTS (SELECT 1 FROM ref_exclusion_list e WHERE e.sk_id_curr = d.sk_id_curr AND e.valid_from <= d.run_date AND (e.valid_to IS NULL OR e.valid_to > d.run_date))', 0)
EXEC p_dq('DECISIONS', 'no approved client breaks a policy rule (age, arrears, age at maturity)', 'SELECT COUNT(*) FROM decisions d JOIN (SELECT run_date, f_rule(''MIN_AGE'', run_date) AS min_age, f_rule(''MAX_AGE_AT_MATURITY'', run_date) AS max_age, f_rule(''OFFER_TERM_MONTHS'', run_date) AS term, f_rule(''MAX_CURRENT_DPD'', run_date) AS max_dpd FROM v_decision_last_run WHERE ROWNUM = 1) r ON r.run_date = d.run_date WHERE d.decision = ''APPROVE'' AND (d.age_years < r.min_age OR d.age_years + r.term / 12 > r.max_age OR d.current_dpd > r.max_dpd)', 0)
EXEC p_dq('DECISIONS', 'no approved client has a PD above the cut-off', 'SELECT COUNT(*) FROM decisions d JOIN (SELECT run_date, f_rule(''PD_CUTOFF'', run_date) AS cutoff FROM v_decision_last_run WHERE ROWNUM = 1) r ON r.run_date = d.run_date WHERE d.decision = ''APPROVE'' AND d.pd > r.cutoff', 0)
EXEC p_dq('DECISIONS', 'limit-grid multiple matches the client''s PD band and income band', 'SELECT COUNT(*) FROM decisions d WHERE d.run_date = (SELECT run_date FROM v_decision_last_run) AND NOT EXISTS (SELECT 1 FROM ref_limit_grid g WHERE g.income_multiple = d.income_multiple AND g.valid_from <= d.run_date AND (g.valid_to IS NULL OR g.valid_to > d.run_date) AND d.pd >= g.pd_from AND (d.pd < g.pd_to OR g.pd_to = 1) AND d.income_amt >= g.income_from AND (g.income_to IS NULL OR d.income_amt < g.income_to))', 0)
EXEC p_dq('DECISIONS', 'no approved limit above grid, debt cap or MAX_LIMIT, or below MIN_LIMIT', 'SELECT COUNT(*) FROM decisions d JOIN (SELECT run_date, f_rule(''MIN_LIMIT'', run_date) AS min_limit, f_rule(''MAX_LIMIT'', run_date) AS max_limit, f_rule(''MAX_TOTAL_DEBT_TO_INCOME'', run_date) AS max_dti FROM v_decision_last_run WHERE ROWNUM = 1) r ON r.run_date = d.run_date WHERE d.decision = ''APPROVE'' AND (d.offer_limit < r.min_limit OR d.offer_limit > r.max_limit OR d.offer_limit > d.income_multiple * d.income_amt OR d.active_debt + d.offer_limit > r.max_dti * d.income_amt)', 0)
EXEC p_dq('V_DECISION_SUMMARY', 'summary adds up to every client (356,255)', 'SELECT SUM(clients) FROM v_decision_summary WHERE run_date = (SELECT run_date FROM v_decision_last_run)', 356255)
EXEC p_dq('DECISIONS', 'valid clients: default rate among approved <= TARGET_BAD_RATE', 'SELECT CASE WHEN AVG(m.target) <= MAX(r.target) THEN 1 ELSE 0 END FROM decisions d JOIN v_model_input m ON m.sk_id_curr = d.sk_id_curr JOIN (SELECT run_date, f_rule(''TARGET_BAD_RATE'', run_date) AS target FROM v_decision_last_run WHERE ROWNUM = 1) r ON r.run_date = d.run_date WHERE d.decision = ''APPROVE'' AND m.split = ''valid''', 1, 'WARN')

PROMPT
PROMPT ===== The run =====
COLUMN run_date     FORMAT A10
COLUMN model_name   FORMAT A10
COLUMN ruleset_hash FORMAT A16
SELECT run_id, TO_CHAR(run_date, 'YYYY-MM-DD') AS run_date, model_name, model_version,
       pd_cutoff, ruleset_hash, excluded_clients, clients, approved, seconds
FROM   v_decision_last_run;

PROMPT
PROMPT ===== Decisions by group of clients =====
COLUMN split FORMAT A8
SELECT d.split,
       COUNT(*)                                                         AS clients,
       SUM(CASE WHEN d.decision = 'APPROVE' THEN 1 ELSE 0 END)          AS approved,
       ROUND(100 * AVG(CASE WHEN d.decision = 'APPROVE' THEN 1 ELSE 0 END), 1) AS approved_pct,
       ROUND(AVG(d.offer_limit))                                        AS avg_limit,
       ROUND(MEDIAN(d.offer_limit))                                     AS median_limit
FROM   decisions d
WHERE  d.run_date = (SELECT run_date FROM v_decision_last_run)
GROUP  BY d.split
ORDER  BY DECODE(d.split, 'fit', 1, 'valid', 2, 'holdout', 3, 4);

PROMPT
PROMPT ===== Main reason (one per client) =====
COLUMN outcome  FORMAT A18
COLUMN category FORMAT A13
SELECT NVL(d.main_reason, '(approved)')            AS outcome,
       NVL(c.category, '-')                        AS category,
       COUNT(*)                                    AS clients,
       ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 1) AS pct
FROM   decisions d
LEFT   JOIN ref_reason_codes c ON c.reason_code = d.main_reason
WHERE  d.run_date = (SELECT run_date FROM v_decision_last_run)
GROUP  BY d.main_reason, c.category, c.priority
ORDER  BY NVL(c.priority, 0);

PROMPT
PROMPT ===== Every reason that applied (a client can have several) =====
COLUMN reason_code FORMAT A18
SELECT r.reason_code, c.category, COUNT(*) AS clients
FROM   decision_reasons r
JOIN   ref_reason_codes c ON c.reason_code = r.reason_code
WHERE  r.run_date = (SELECT run_date FROM v_decision_last_run)
GROUP  BY r.reason_code, c.category, c.priority
ORDER  BY c.priority;

PROMPT
PROMPT ===== Approved limits: which cap set the limit =====
COLUMN limit_basis FORMAT A10
SELECT limit_basis,
       COUNT(*)                AS clients,
       ROUND(MIN(offer_limit)) AS min_limit,
       ROUND(AVG(offer_limit)) AS avg_limit,
       ROUND(MAX(offer_limit)) AS max_limit
FROM   decisions
WHERE  run_date = (SELECT run_date FROM v_decision_last_run)
AND    decision = 'APPROVE'
GROUP  BY limit_basis
ORDER  BY limit_basis;

PROMPT
PROMPT ===== All runs so far (history is kept) =====
COLUMN status FORMAT A7
COLUMN message FORMAT A40 TRUNCATED
SELECT run_id, TO_CHAR(run_date, 'YYYY-MM-DD') AS run_date, status, ruleset_hash,
       clients, approved, seconds, message
FROM   decision_runs
ORDER  BY run_id;

PROMPT 03_decision_checks: done
