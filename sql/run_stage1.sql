-- =====================================================================
-- run_stage1.sql
-- Runs all of Stage 1 as HC, in order:
--   utils -> external tables -> raw tables -> load
--
-- Run from the repository root:
--   sqlplus /nolog @sql\run_stage1.sql
--
-- The script asks for the HC password and connects itself. (Do not use
-- sqlplus hc@localhost:1521/XEPDB1 - SQL*Plus reads the text after '/'
-- as the password.)
--
-- Before the first run, as SYSDBA: sql\00_setup\03_create_directory.sql
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET VERIFY OFF
SET LINESIZE 150
SET PAGESIZE 100

ACCEPT hc_password CHAR PROMPT 'HC password: ' HIDE
CONNECT hc/"&hc_password"@localhost:1521/XEPDB1
UNDEFINE hc_password

-- Remember when this run started, to check only this run's loads at the end
VARIABLE run_start VARCHAR2(30)
EXEC :run_start := TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')

-- Paths are relative to the repository root (run the script from there)
@sql\01_ddl\00_utils.sql
@sql\01_ddl\01_external_tables.sql
@sql\01_ddl\02_raw_tables.sql
@sql\02_load\01_load_raw.sql

-- -----------------------------------------------------------------------
-- Final gate. SQL*Plus errors (SP2-...), e.g. a script file not found, do
-- NOT stop the run, so we verify the result instead of trusting it:
-- all 9 tables must have an OK load that started during THIS run.
-- If raw_load_log does not even exist, this block fails too.
-- -----------------------------------------------------------------------
DECLARE
  v_ok NUMBER;
BEGIN
  SELECT COUNT(DISTINCT table_name) INTO v_ok
  FROM   raw_load_log
  WHERE  status = 'OK'
  AND    started_at >= TO_TIMESTAMP(:run_start, 'YYYY-MM-DD HH24:MI:SS');

  IF v_ok != 9 THEN
    RAISE_APPLICATION_ERROR(-20002,
      'Stage 1 INCOMPLETE: ' || v_ok || ' of 9 tables loaded OK in this run');
  END IF;
END;
/

PROMPT
PROMPT ===== STAGE 1 COMPLETE: 9 of 9 tables loaded and verified =====
EXIT
