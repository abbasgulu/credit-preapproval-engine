-- =====================================================================
-- 05_model_scores.sql
-- Stage 3g checks, run after python\scripts\calibrate_and_score.py.
--
-- In plain words: prove that every client has a score from each model,
-- that every PD is a real probability, that Oracle and Python compute the
-- very same PD (one formula, two engines, no drift), and that the average
-- PD matches the actual default rate.
--
-- Run from the repository root:
--   sqlplus /nolog @sql\99_checks\05_model_scores.sql
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET VERIFY OFF
SET LINESIZE 150
SET PAGESIZE 100

@sql\_connect.sql

VARIABLE run_start VARCHAR2(30)
EXEC :run_start := TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')

-- latest version of each model
EXEC p_dq('MODEL_SCORES', 'lightgbm: every client scored (356,255)', 'SELECT COUNT(*) FROM model_scores WHERE model_name = ''lightgbm'' AND model_version = (SELECT MAX(model_version) FROM model_scores WHERE model_name = ''lightgbm'')', 356255)
EXEC p_dq('MODEL_SCORES', 'scorecard: every client scored (356,255)', 'SELECT COUNT(*) FROM model_scores WHERE model_name = ''scorecard'' AND model_version = (SELECT MAX(model_version) FROM model_scores WHERE model_name = ''scorecard'')', 356255)
EXEC p_dq('V_SCORES', 'every score has calibration numbers', 'SELECT (SELECT COUNT(*) FROM model_scores) - (SELECT COUNT(*) FROM v_scores) FROM dual', 0)
EXEC p_dq('V_SCORES', 'PD strictly between 0 and 1', 'SELECT COUNT(*) FROM v_scores WHERE pd <= 0 OR pd >= 1', 0)
EXEC p_dq('V_SCORES', 'Oracle PD = Python PD (difference < 1e-9)', 'SELECT COUNT(*) FROM v_scores WHERE ABS(pd - pd_check) > 1e-9', 0)
EXEC p_dq('V_SCORES', 'mean PD within 0.3 pp of actual rate (train clients, per model)', 'SELECT CASE WHEN MAX(ABS(avg_pd - avg_y)) <= 0.003 THEN 1 ELSE 0 END FROM (SELECT s.model_name, AVG(s.pd) AS avg_pd, AVG(m.target) AS avg_y FROM v_scores s JOIN v_model_input m ON m.sk_id_curr = s.sk_id_curr WHERE m.dataset = ''train'' GROUP BY s.model_name)', 1)

PROMPT
PROMPT ===== Average PD vs actual default rate =====
COLUMN model_name FORMAT A10
COLUMN split      FORMAT A8
SELECT s.model_name, s.split,
       COUNT(*)                          AS clients,
       ROUND(100 * AVG(s.pd), 2)         AS avg_pd_pct,
       ROUND(100 * AVG(m.target), 2)     AS actual_pct
FROM   v_scores s
JOIN   v_model_input m ON m.sk_id_curr = s.sk_id_curr
GROUP  BY s.model_name, s.split
ORDER  BY s.model_name, DECODE(s.split, 'fit', 1, 'valid', 2, 'holdout', 3, 4);

PROMPT
PROMPT ===== Calibration numbers in use =====
COLUMN fitted_on FORMAT A40
SELECT model_name, model_version, ROUND(coef_a, 4) AS coef_a, ROUND(coef_b, 4) AS coef_b,
       fitted_on, valid_from
FROM   ref_calibration
WHERE  valid_to IS NULL
ORDER  BY model_name;

PROMPT
PROMPT ===== DQ results of this run =====
COLUMN table_name FORMAT A14
COLUMN check_name FORMAT A66
COLUMN severity   FORMAT A5
COLUMN passed     FORMAT A6
SELECT table_name, check_name, severity, expected, actual, passed
FROM   dq_log
WHERE  checked_at >= TO_TIMESTAMP(:run_start, 'YYYY-MM-DD HH24:MI:SS')
ORDER  BY dq_id;

PROMPT
PROMPT ===== 3g CHECKS COMPLETE =====
EXIT
