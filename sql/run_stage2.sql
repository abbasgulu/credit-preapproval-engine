-- =====================================================================
-- run_stage2.sql
-- Runs all of Stage 2 as HC: DQ tools -> 6 feature tables -> feat_customer
-- -> generated data dictionary.
--
-- Run from the repository root:
--   sqlplus /nolog @sql\run_stage2.sql
--
-- Every feature table is checked right after it is built; a failed ERROR
-- check stops the run. The final gate verifies the result of THIS run.
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET VERIFY OFF
SET LINESIZE 150
SET PAGESIZE 100

@sql\_connect.sql

VARIABLE run_start VARCHAR2(30)
EXEC :run_start := TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')

SET TIMING ON
@sql\01_ddl\03_dq.sql
@sql\03_features\01_feat_application.sql
@sql\03_features\02_feat_bureau.sql
@sql\03_features\03_feat_previous.sql
@sql\03_features\04_feat_installments.sql
@sql\03_features\05_feat_pos_cash.sql
@sql\03_features\06_feat_credit_card.sql
@sql\03_features\07_feat_customer.sql
SET TIMING OFF

-- -----------------------------------------------------------------------
-- Final gate: in THIS run, all 7 feature tables passed their unique and
-- row-count checks, and no ERROR check failed.
-- -----------------------------------------------------------------------
DECLARE
  v_tables NUMBER;
  v_failed NUMBER;
BEGIN
  SELECT COUNT(DISTINCT table_name) INTO v_tables
  FROM   dq_log
  WHERE  check_name = 'row count' AND passed = 'Y'
  AND    table_name LIKE 'FEAT\_%' ESCAPE '\'
  AND    checked_at >= TO_TIMESTAMP(:run_start, 'YYYY-MM-DD HH24:MI:SS');

  SELECT COUNT(*) INTO v_failed
  FROM   dq_log
  WHERE  severity = 'ERROR' AND passed = 'N'
  AND    checked_at >= TO_TIMESTAMP(:run_start, 'YYYY-MM-DD HH24:MI:SS');

  IF v_tables != 7 OR v_failed != 0 THEN
    RAISE_APPLICATION_ERROR(-20002,
      'Stage 2 INCOMPLETE: ' || v_tables || ' of 7 feature tables verified, '
      || v_failed || ' failed checks');
  END IF;
END;
/

PROMPT
PROMPT ===== DQ results of this run =====
COLUMN table_name FORMAT A26
COLUMN check_name FORMAT A62
COLUMN severity   FORMAT A5
COLUMN passed     FORMAT A6
SELECT table_name, check_name, severity, expected, actual, passed
FROM   dq_log
WHERE  checked_at >= TO_TIMESTAMP(:run_start, 'YYYY-MM-DD HH24:MI:SS')
ORDER  BY dq_id;

@sql\99_checks\04_data_dictionary.sql

PROMPT
PROMPT ===== STAGE 2 COMPLETE: 7 of 7 feature tables built and verified =====
EXIT
