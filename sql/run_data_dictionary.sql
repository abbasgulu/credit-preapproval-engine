-- =====================================================================
-- run_data_dictionary.sql
-- Regenerates docs/data_dictionary.md from Oracle column comments,
-- without rebuilding any table.
--
-- Run from the repository root:
--   sqlplus /nolog @sql\run_data_dictionary.sql
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET VERIFY OFF
ACCEPT hc_password CHAR PROMPT 'HC password: ' HIDE
CONNECT hc/"&hc_password"@localhost:1521/XEPDB1
UNDEFINE hc_password

@sql\99_checks\04_data_dictionary.sql
EXIT
