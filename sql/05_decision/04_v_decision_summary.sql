-- =====================================================================
-- 04_v_decision_summary.sql
-- Stage 4d: one small, dashboard-ready summary of the decisions.
--
-- In plain words: the decisions table has one row per client. A dashboard
-- (Tableau, Stage 6) mostly needs totals: how many clients were approved or
-- declined, for which main reason, how many of them later had repayment
-- trouble (where the outcome is known), how much trouble the model expected,
-- and how much credit was offered. This view adds those up per run date,
-- group of clients (split) and outcome. It holds no logic of its own: every
-- number is a count, sum or average of what the engine wrote.
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE

CREATE OR REPLACE VIEW v_decision_summary AS
SELECT d.run_date,
       d.split,
       d.decision,
       NVL(d.main_reason, 'APPROVED')  AS outcome,
       NVL(c.category, 'APPROVED')     AS outcome_category,
       NVL(c.priority, 0)              AS outcome_order,
       COUNT(*)                        AS clients,
       COUNT(p.target)                 AS clients_known_outcome,
       SUM(p.target)                   AS defaults,
       AVG(p.target)                   AS default_rate,
       AVG(d.pd)                       AS avg_pd,
       SUM(d.pd)                       AS expected_defaults,
       SUM(d.offer_limit)              AS total_limit,
       AVG(d.offer_limit)              AS avg_limit
FROM   decisions d
JOIN   v_population p ON p.sk_id_curr = d.sk_id_curr
LEFT   JOIN ref_reason_codes c ON c.reason_code = d.main_reason
GROUP  BY d.run_date, d.split, d.decision, d.main_reason, c.category, c.priority;

SET FEEDBACK OFF
COMMENT ON TABLE v_decision_summary IS 'Decisions added up per run date, split and outcome (APPROVED or the main decline reason): clients, known defaults, expected defaults (sum of PD), offered credit. Feeds the dashboard.';
COMMENT ON COLUMN v_decision_summary.default_rate IS 'Share of clients with repayment trouble; NULL for test clients (outcome unknown).';
COMMENT ON COLUMN v_decision_summary.expected_defaults IS 'Sum of calibrated PDs: how many defaults the model expects in the group.';
SET FEEDBACK ON

PROMPT 04_v_decision_summary: done
