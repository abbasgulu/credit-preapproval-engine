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
@sql\_connect.sql

@sql\99_checks\04_data_dictionary.sql
EXIT
