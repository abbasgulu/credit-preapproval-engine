-- =====================================================================
-- 01_raw_overview.sql
-- Read-only overview of the raw layer: load log, row counts, disk usage.
-- Run any time:  sqlplus /nolog @sql\99_checks\01_raw_overview.sql
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET VERIFY OFF
@sql\_connect.sql
WHENEVER SQLERROR CONTINUE

SET LINESIZE 150
SET PAGESIZE 100
COLUMN table_name   FORMAT A28
COLUMN segment_name FORMAT A28
COLUMN status       FORMAT A8

PROMPT ===== Load history =====
SELECT load_id, table_name, expected_rows, actual_rows, status, seconds,
       TO_CHAR(started_at, 'YYYY-MM-DD HH24:MI') AS started
FROM   raw_load_log
ORDER  BY load_id;

PROMPT
PROMPT ===== Disk usage by table (MB) =====
SELECT segment_name, ROUND(bytes / 1024 / 1024) AS mb
FROM   user_segments
WHERE  segment_type = 'TABLE'
ORDER  BY bytes DESC;

PROMPT
PROMPT ===== Total (GB) - XE limit is 12 GB =====
SELECT ROUND(SUM(bytes) / 1024 / 1024 / 1024, 2) AS gb FROM user_segments;

EXIT
