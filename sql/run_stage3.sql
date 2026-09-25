-- =====================================================================
-- run_stage3.sql
-- Runs the SQL steps of Stage 3 (the model). Grows step by step:
--   3b  split: v_model_input
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
