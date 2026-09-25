-- =====================================================================
-- 04_data_dictionary.sql
-- Generates docs/data_dictionary.md from Oracle's column comments
-- (improvement 8): the documentation cannot drift from the database.
--
-- Called by run_stage2.sql. To regenerate only the dictionary:
--   sqlplus /nolog @sql\run_data_dictionary.sql
-- =====================================================================

SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 2000
SET TRIMSPOOL ON
SET TIMING OFF
SET VERIFY OFF
-- RECSEP OFF: no blank line after multi-line values, which would break the markdown tables
SET RECSEP OFF

SPOOL docs\data_dictionary.md

SELECT '# Data dictionary' FROM dual;
SELECT '' FROM dual;
SELECT '_Generated from Oracle column comments by `sql/99_checks/04_data_dictionary.sql` on '
       || TO_CHAR(SYSDATE, 'YYYY-MM-DD') || '. Do not edit by hand._' FROM dual;

SELECT txt FROM (
  SELECT t.table_name, 0 AS part, 0 AS col_id,
         CHR(10) || '## `' || LOWER(t.table_name) || '`' || CHR(10) || CHR(10)
         || NVL(tc.comments, '') || CHR(10) || CHR(10)
         || '| # | Column | Type | Description |' || CHR(10)
         || '|---:|---|---|---|' AS txt
  FROM   user_tables t
  LEFT   JOIN user_tab_comments tc ON tc.table_name = t.table_name
  WHERE  t.table_name LIKE 'FEAT\_%' ESCAPE '\'
  UNION ALL
  SELECT c.table_name, 1, c.column_id,
         '| ' || c.column_id || ' | `' || LOWER(c.column_name) || '` | '
         || c.data_type || ' | ' || REPLACE(NVL(cc.comments, '**missing**'), '|', '/') || ' |'
  FROM   user_tab_columns c
  LEFT   JOIN user_col_comments cc
         ON cc.table_name = c.table_name AND cc.column_name = c.column_name
  WHERE  c.table_name LIKE 'FEAT\_%' ESCAPE '\'
)
ORDER BY CASE table_name
           WHEN 'FEAT_APPLICATION'  THEN 1 WHEN 'FEAT_BUREAU'      THEN 2
           WHEN 'FEAT_PREVIOUS'     THEN 3 WHEN 'FEAT_INSTALLMENTS' THEN 4
           WHEN 'FEAT_POS_CASH'     THEN 5 WHEN 'FEAT_CREDIT_CARD'  THEN 6
           ELSE 7 END,
         part, col_id;

SPOOL OFF

SET HEADING ON
SET FEEDBACK ON
SET PAGESIZE 100
SET RECSEP WRAPPED

PROMPT
PROMPT ===== Columns without a comment (expected 0) =====
SELECT COUNT(*) AS missing_comments
FROM   user_tab_columns c
LEFT   JOIN user_col_comments cc
       ON cc.table_name = c.table_name AND cc.column_name = c.column_name
WHERE  c.table_name LIKE 'FEAT\_%' ESCAPE '\'
AND    cc.comments IS NULL;

PROMPT 04_data_dictionary: written to docs\data_dictionary.md
