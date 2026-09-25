-- =====================================================================
-- run_stage4.sql
-- Runs the SQL steps of Stage 4 (the decision engine). Grows step by step:
--   4a  reference tables: rules, reason codes, limit grid, exclusion list
--
-- Run from the repository root:
--   sqlplus /nolog @sql\run_stage4.sql
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET VERIFY OFF
SET LINESIZE 160
SET PAGESIZE 100

@sql\_connect.sql

VARIABLE run_start VARCHAR2(30)
EXEC :run_start := TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')

@sql\04_reference\02_ref_rules.sql
@sql\04_reference\03_ref_reason_codes.sql
@sql\04_reference\04_ref_limit_grid.sql
@sql\04_reference\05_ref_exclusion_list.sql

PROMPT
PROMPT ===== Rules in force =====
COLUMN rule_code   FORMAT A26
COLUMN unit        FORMAT A10
COLUMN set_by      FORMAT A40
SELECT rule_code, rule_value, unit, set_by, valid_from
FROM   ref_rules WHERE valid_to IS NULL ORDER BY rule_code;

PROMPT
PROMPT ===== Limit grid in force (income multiple) =====
SELECT pd_from, pd_to,
       MAX(CASE WHEN income_from = 0      THEN income_multiple END) AS "INCOME<100K",
       MAX(CASE WHEN income_from = 100000 THEN income_multiple END) AS "100K-250K",
       MAX(CASE WHEN income_from = 250000 THEN income_multiple END) AS "250K+"
FROM   ref_limit_grid WHERE valid_to IS NULL
GROUP  BY pd_from, pd_to ORDER BY pd_from;

PROMPT
PROMPT ===== Exclusion list =====
SELECT reason_code, COUNT(*) AS clients FROM ref_exclusion_list WHERE valid_to IS NULL GROUP BY reason_code;

PROMPT
PROMPT ===== DQ results of this run =====
COLUMN table_name FORMAT A18
COLUMN check_name FORMAT A70
COLUMN severity   FORMAT A5
COLUMN passed     FORMAT A6
SELECT table_name, check_name, severity, expected, actual, passed
FROM   dq_log
WHERE  checked_at >= TO_TIMESTAMP(:run_start, 'YYYY-MM-DD HH24:MI:SS')
ORDER  BY dq_id;

PROMPT
PROMPT ===== STAGE 4 (SQL) COMPLETE =====
EXIT
