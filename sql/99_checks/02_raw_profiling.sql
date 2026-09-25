-- =====================================================================
-- 02_raw_profiling.sql
-- Facts about the raw data that later design decisions depend on.
--
--   A. Line endings of the two files too large to inspect outside Oracle
--      (credit_card_balance, installments_payments): do any rows still
--      contain a carriage return (CHR(13)) in their last field?
--   B. The 365243 placeholder in DAYS_* columns: where it occurs, how
--      often, and for which income types.
--
-- Read-only. Run from the repository root:
--   sqlplus /nolog @sql\99_checks\02_raw_profiling.sql
--
-- Part A scans two CSV files (~1.1 GB) through the external tables and
-- takes about a minute.
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET VERIFY OFF
ACCEPT hc_password CHAR PROMPT 'HC password: ' HIDE
CONNECT hc/"&hc_password"@localhost:1521/XEPDB1
UNDEFINE hc_password

SET LINESIZE 150
SET PAGESIZE 100
SET TIMING ON
COLUMN file_name        FORMAT A28
COLUMN column_name      FORMAT A28
COLUMN name_income_type FORMAT A22

-- ---------------------------------------------------------------------
-- A. Line endings
-- 0 rows with CHR(13) = the file uses LF, as assumed in 01_external_tables
-- ---------------------------------------------------------------------
PROMPT
PROMPT ===== A. Rows whose last field still contains CR (expected 0) =====
SELECT 'credit_card_balance.csv' AS file_name,
       COUNT(*)                                        AS rows_read,
       SUM(CASE WHEN INSTR(sk_dpd_def, CHR(13)) > 0 THEN 1 ELSE 0 END) AS rows_with_cr
FROM   ext_credit_card_balance
UNION ALL
SELECT 'installments_payments.csv',
       COUNT(*),
       SUM(CASE WHEN INSTR(amt_payment, CHR(13)) > 0 THEN 1 ELSE 0 END)
FROM   ext_installments_payments;

-- ---------------------------------------------------------------------
-- B1. How often does 365243 appear in each DAYS_* column?
-- ---------------------------------------------------------------------
PROMPT
PROMPT ===== B1. 365243 per DAYS_* column =====
SELECT 'application_train' AS file_name, 'DAYS_EMPLOYED' AS column_name,
       COUNT(*) AS total_rows,
       SUM(CASE WHEN days_employed = 365243 THEN 1 ELSE 0 END) AS rows_365243,
       ROUND(100 * AVG(CASE WHEN days_employed = 365243 THEN 1 ELSE 0 END), 2) AS pct
FROM   raw_application_train
UNION ALL
SELECT 'application_test', 'DAYS_EMPLOYED', COUNT(*),
       SUM(CASE WHEN days_employed = 365243 THEN 1 ELSE 0 END),
       ROUND(100 * AVG(CASE WHEN days_employed = 365243 THEN 1 ELSE 0 END), 2)
FROM   raw_application_test
UNION ALL
SELECT 'previous_application', 'DAYS_FIRST_DRAWING', COUNT(*),
       SUM(CASE WHEN days_first_drawing = 365243 THEN 1 ELSE 0 END),
       ROUND(100 * AVG(CASE WHEN days_first_drawing = 365243 THEN 1 ELSE 0 END), 2)
FROM   raw_previous_application
UNION ALL
SELECT 'previous_application', 'DAYS_FIRST_DUE', COUNT(*),
       SUM(CASE WHEN days_first_due = 365243 THEN 1 ELSE 0 END),
       ROUND(100 * AVG(CASE WHEN days_first_due = 365243 THEN 1 ELSE 0 END), 2)
FROM   raw_previous_application
UNION ALL
SELECT 'previous_application', 'DAYS_LAST_DUE_1ST_VERSION', COUNT(*),
       SUM(CASE WHEN days_last_due_1st_version = 365243 THEN 1 ELSE 0 END),
       ROUND(100 * AVG(CASE WHEN days_last_due_1st_version = 365243 THEN 1 ELSE 0 END), 2)
FROM   raw_previous_application
UNION ALL
SELECT 'previous_application', 'DAYS_LAST_DUE', COUNT(*),
       SUM(CASE WHEN days_last_due = 365243 THEN 1 ELSE 0 END),
       ROUND(100 * AVG(CASE WHEN days_last_due = 365243 THEN 1 ELSE 0 END), 2)
FROM   raw_previous_application
UNION ALL
SELECT 'previous_application', 'DAYS_TERMINATION', COUNT(*),
       SUM(CASE WHEN days_termination = 365243 THEN 1 ELSE 0 END),
       ROUND(100 * AVG(CASE WHEN days_termination = 365243 THEN 1 ELSE 0 END), 2)
FROM   raw_previous_application;

-- ---------------------------------------------------------------------
-- B2. Who has DAYS_EMPLOYED = 365243? (by income type)
-- ---------------------------------------------------------------------
PROMPT
PROMPT ===== B2. DAYS_EMPLOYED = 365243 by income type (application_train) =====
SELECT name_income_type,
       COUNT(*)                                                 AS clients,
       SUM(CASE WHEN days_employed = 365243 THEN 1 ELSE 0 END)  AS with_365243
FROM   raw_application_train
GROUP  BY name_income_type
ORDER  BY clients DESC;

-- ---------------------------------------------------------------------
-- B3. Does the placeholder carry risk information? Default rate with
--     and without it. If the rates differ, the flag is worth keeping.
-- ---------------------------------------------------------------------
PROMPT
PROMPT ===== B3. Default rate (TARGET = 1) with / without 365243 =====
SELECT CASE WHEN days_employed = 365243 THEN 'DAYS_EMPLOYED = 365243'
            ELSE 'real value' END                   AS group_name,
       COUNT(*)                                     AS clients,
       ROUND(100 * AVG(target), 2)                  AS default_rate_pct
FROM   raw_application_train
GROUP  BY CASE WHEN days_employed = 365243 THEN 'DAYS_EMPLOYED = 365243'
               ELSE 'real value' END;

SET TIMING OFF
EXIT
