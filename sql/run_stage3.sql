-- =====================================================================
-- run_stage3.sql
-- Runs the SQL steps of Stage 3 (the model). Grows step by step:
--   3b  split: v_model_input
--   3g  calibration table + formula (ref_calibration, f_calibrate_pd),
--       score table + view (model_scores, v_scores)
--       -> then run python\scripts\calibrate_and_score.py
--       -> then check:  sqlplus /nolog @sql\99_checks\05_model_scores.sql
--
-- Run from the repository root:
--   sqlplus /nolog @sql\run_stage3.sql
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET VERIFY OFF
SET LINESIZE 150
SET PAGESIZE 100

@sql\_connect.sql

VARIABLE run_start VARCHAR2(30)
EXEC :run_start := TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')

@sql\03_features\08_model_split.sql
@sql\04_reference\01_ref_calibration.sql
@sql\01_ddl\04_model_scores.sql

PROMPT
PROMPT ===== DQ results of this run =====
COLUMN table_name FORMAT A16
COLUMN check_name FORMAT A55
COLUMN severity   FORMAT A5
COLUMN passed     FORMAT A6
SELECT table_name, check_name, severity, expected, actual, passed
FROM   dq_log
WHERE  checked_at >= TO_TIMESTAMP(:run_start, 'YYYY-MM-DD HH24:MI:SS')
ORDER  BY dq_id;

PROMPT
PROMPT ===== STAGE 3 (SQL) COMPLETE =====
EXIT
