-- =====================================================================
-- run_decisions.sql
-- Stage 4c: runs the decision engine for today, checks the result and
-- prints a summary. This is the script a lender would schedule daily.
--
-- In plain words: every client gets a decision (approve with a limit, or
-- decline with reasons) using the rules in force today. Running it again
-- on the same day replaces today's decisions only; earlier days are kept.
--
-- Needs: sql\run_stage4.sql and python\scripts\choose_cutoff.py first.
-- For another date, in SQL*Plus:  EXEC p_run_decisions(DATE '2026-09-25')
--
-- Run from the repository root:
--   sqlplus /nolog @sql\run_decisions.sql
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET VERIFY OFF
SET LINESIZE 170
SET PAGESIZE 100

@sql\_connect.sql

VARIABLE run_start VARCHAR2(30)
EXEC :run_start := TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')

PROMPT
PROMPT ===== Decision engine: run for today =====
SET SERVEROUTPUT ON SIZE UNLIMITED
EXEC p_run_decisions
SET SERVEROUTPUT OFF

@sql\05_decision\03_decision_checks.sql

PROMPT
PROMPT ===== DQ results of this run =====
COLUMN table_name FORMAT A16
COLUMN check_name FORMAT A75
COLUMN severity   FORMAT A5
COLUMN passed     FORMAT A6
SELECT table_name, check_name, severity, expected, actual, passed
FROM   dq_log
WHERE  checked_at >= TO_TIMESTAMP(:run_start, 'YYYY-MM-DD HH24:MI:SS')
ORDER  BY dq_id;

PROMPT
PROMPT ===== DECISION RUN COMPLETE =====
EXIT
