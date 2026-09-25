-- =====================================================================
-- 03_grain_profiling.sql
-- Stage 2a: what does ONE ROW mean in each raw table, and is it true?
--
-- Feature tables aggregate many source rows into one row per client
-- (SK_ID_CURR). If a source has duplicates or several rows where one is
-- expected, sums and counts are silently inflated. This script measures
-- that BEFORE any feature is built.
--
--   A. Grain check   - rows vs distinct values of the expected key
--   B. Known traps   - duplicate applications, partial payments
--   C. Coverage      - how many clients have history in each source
--   D. Value lists   - status codes the features will depend on
--   E. Obligations   - is AMT_ANNUITY usable for a monthly debt measure?
--   F. Partitioning  - is the feature available in this Oracle edition?
--
-- Read-only, except section F, which creates and drops one tiny test
-- table (ZZ_PART_TEST).
--
-- Run from the repository root:
--   sqlplus /nolog @sql\99_checks\03_grain_profiling.sql
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET VERIFY OFF
@sql\_connect.sql

SET LINESIZE 160
SET PAGESIZE 200
SET TIMING ON
COLUMN table_name      FORMAT A26
COLUMN expected_key    FORMAT A55
COLUMN source_name     FORMAT A26
COLUMN val             FORMAT A40
COLUMN check_name      FORMAT A55
COLUMN check_result    FORMAT A60

-- ---------------------------------------------------------------------
-- A. Grain: rows = distinct keys means the expected grain holds.
-- ---------------------------------------------------------------------
PROMPT
PROMPT ===== A. Grain check (duplicates = rows - distinct_keys, expected 0) =====
SELECT 'raw_application_train' AS table_name, 'SK_ID_CURR' AS expected_key,
       COUNT(*) AS row_count, COUNT(DISTINCT sk_id_curr) AS distinct_keys,
       COUNT(*) - COUNT(DISTINCT sk_id_curr) AS duplicates
FROM   raw_application_train
UNION ALL
SELECT 'raw_application_test', 'SK_ID_CURR',
       COUNT(*), COUNT(DISTINCT sk_id_curr), COUNT(*) - COUNT(DISTINCT sk_id_curr)
FROM   raw_application_test
UNION ALL
SELECT 'raw_bureau', 'SK_ID_BUREAU',
       COUNT(*), COUNT(DISTINCT sk_id_bureau), COUNT(*) - COUNT(DISTINCT sk_id_bureau)
FROM   raw_bureau
UNION ALL
SELECT 'raw_bureau_balance', 'SK_ID_BUREAU + MONTHS_BALANCE',
       COUNT(*), COUNT(DISTINCT sk_id_bureau || '|' || months_balance),
       COUNT(*) - COUNT(DISTINCT sk_id_bureau || '|' || months_balance)
FROM   raw_bureau_balance
UNION ALL
SELECT 'raw_previous_application', 'SK_ID_PREV',
       COUNT(*), COUNT(DISTINCT sk_id_prev), COUNT(*) - COUNT(DISTINCT sk_id_prev)
FROM   raw_previous_application
UNION ALL
SELECT 'raw_installments_payments', 'SK_ID_PREV + VERSION + INSTALMENT_NUMBER',
       COUNT(*),
       COUNT(DISTINCT sk_id_prev || '|' || num_instalment_version || '|' || num_instalment_number),
       COUNT(*) - COUNT(DISTINCT sk_id_prev || '|' || num_instalment_version || '|' || num_instalment_number)
FROM   raw_installments_payments
UNION ALL
SELECT 'raw_pos_cash_balance', 'SK_ID_PREV + MONTHS_BALANCE',
       COUNT(*), COUNT(DISTINCT sk_id_prev || '|' || months_balance),
       COUNT(*) - COUNT(DISTINCT sk_id_prev || '|' || months_balance)
FROM   raw_pos_cash_balance
UNION ALL
SELECT 'raw_credit_card_balance', 'SK_ID_PREV + MONTHS_BALANCE',
       COUNT(*), COUNT(DISTINCT sk_id_prev || '|' || months_balance),
       COUNT(*) - COUNT(DISTINCT sk_id_prev || '|' || months_balance)
FROM   raw_credit_card_balance;

-- ---------------------------------------------------------------------
-- B. Known traps described in Kaggle's own column descriptions
-- ---------------------------------------------------------------------
PROMPT
PROMPT ===== B1. Train and test must not share clients (expected 0) =====
SELECT COUNT(*) AS clients_in_both
FROM   raw_application_train t
WHERE  EXISTS (SELECT 1 FROM raw_application_test s WHERE s.sk_id_curr = t.sk_id_curr);

PROMPT
PROMPT ===== B2. previous_application: flags for repeated applications =====
SELECT 'FLAG_LAST_APPL_PER_CONTRACT' AS check_name, flag_last_appl_per_contract AS val, COUNT(*) AS row_count
FROM   raw_previous_application
GROUP  BY flag_last_appl_per_contract
UNION ALL
SELECT 'NFLAG_LAST_APPL_IN_DAY', TO_CHAR(nflag_last_appl_in_day), COUNT(*)
FROM   raw_previous_application
GROUP  BY nflag_last_appl_in_day
ORDER  BY 1, 2;

PROMPT
PROMPT ===== B3. installments: one instalment paid in several rows? =====
WITH per_instalment AS (
  SELECT sk_id_prev, num_instalment_version, num_instalment_number,
         COUNT(*) AS payment_rows
  FROM   raw_installments_payments
  GROUP  BY sk_id_prev, num_instalment_version, num_instalment_number
)
SELECT payment_rows, COUNT(*) AS instalments
FROM   per_instalment
GROUP  BY payment_rows
ORDER  BY payment_rows
FETCH FIRST 10 ROWS ONLY;

PROMPT
PROMPT ===== B4. installments: rows with no payment recorded =====
SELECT COUNT(*) AS rows_total,
       SUM(CASE WHEN amt_payment IS NULL        THEN 1 ELSE 0 END) AS amt_payment_null,
       SUM(CASE WHEN days_entry_payment IS NULL THEN 1 ELSE 0 END) AS days_entry_payment_null
FROM   raw_installments_payments;

PROMPT
PROMPT ===== B5. bureau_balance rows whose credit is missing from bureau =====
SELECT COUNT(DISTINCT bb.sk_id_bureau) AS orphan_bureau_ids
FROM   raw_bureau_balance bb
WHERE  NOT EXISTS (SELECT 1 FROM raw_bureau b WHERE b.sk_id_bureau = bb.sk_id_bureau);

-- ---------------------------------------------------------------------
-- C. Coverage: share of the 356,255 clients with any history per source
-- ---------------------------------------------------------------------
PROMPT
PROMPT ===== C. Coverage of the client population =====
WITH population AS (
  SELECT sk_id_curr FROM raw_application_train
  UNION ALL
  SELECT sk_id_curr FROM raw_application_test
),
src AS (
  SELECT 'bureau' AS source_name, sk_id_curr FROM raw_bureau
  UNION ALL SELECT 'bureau_balance (via bureau)', b.sk_id_curr
            FROM raw_bureau b
            WHERE EXISTS (SELECT 1 FROM raw_bureau_balance bb WHERE bb.sk_id_bureau = b.sk_id_bureau)
  UNION ALL SELECT 'previous_application', sk_id_curr FROM raw_previous_application
  UNION ALL SELECT 'installments_payments', sk_id_curr FROM raw_installments_payments
  UNION ALL SELECT 'pos_cash_balance', sk_id_curr FROM raw_pos_cash_balance
  UNION ALL SELECT 'credit_card_balance', sk_id_curr FROM raw_credit_card_balance
),
covered AS (
  SELECT source_name, COUNT(DISTINCT s.sk_id_curr) AS clients_with_history
  FROM   src s
  WHERE  s.sk_id_curr IN (SELECT sk_id_curr FROM population)
  GROUP  BY source_name
)
SELECT c.source_name,
       c.clients_with_history,
       (SELECT COUNT(*) FROM population) AS population,
       ROUND(100 * c.clients_with_history / (SELECT COUNT(*) FROM population), 1) AS pct
FROM   covered c
ORDER  BY pct DESC;

-- ---------------------------------------------------------------------
-- D. Value lists the features depend on
-- ---------------------------------------------------------------------
PROMPT
PROMPT ===== D1. bureau.CREDIT_ACTIVE =====
SELECT credit_active AS val, COUNT(*) AS row_count
FROM   raw_bureau GROUP BY credit_active ORDER BY 2 DESC;

PROMPT
PROMPT ===== D2. bureau_balance.STATUS (C closed, X unknown, 0 no DPD, 1..5 DPD buckets) =====
SELECT status AS val, COUNT(*) AS row_count
FROM   raw_bureau_balance GROUP BY status ORDER BY 1;

PROMPT
PROMPT ===== D3. previous_application.NAME_CONTRACT_STATUS =====
SELECT name_contract_status AS val, COUNT(*) AS row_count
FROM   raw_previous_application GROUP BY name_contract_status ORDER BY 2 DESC;

PROMPT
PROMPT ===== D4. MONTHS_BALANCE range (expected: all <= 0) =====
SELECT 'bureau_balance' AS source_name, MIN(months_balance) AS min_month, MAX(months_balance) AS max_month
FROM   raw_bureau_balance
UNION ALL
SELECT 'pos_cash_balance', MIN(months_balance), MAX(months_balance) FROM raw_pos_cash_balance
UNION ALL
SELECT 'credit_card_balance', MIN(months_balance), MAX(months_balance) FROM raw_credit_card_balance;

-- ---------------------------------------------------------------------
-- E. Can we build a monthly debt obligation from bureau annuities?
-- ---------------------------------------------------------------------
PROMPT
PROMPT ===== E. bureau.AMT_ANNUITY availability on ACTIVE credits =====
SELECT COUNT(*) AS active_credits,
       SUM(CASE WHEN amt_annuity IS NULL THEN 1 ELSE 0 END) AS annuity_null,
       SUM(CASE WHEN amt_annuity = 0     THEN 1 ELSE 0 END) AS annuity_zero,
       ROUND(100 * AVG(CASE WHEN amt_annuity > 0 THEN 1 ELSE 0 END), 1) AS pct_usable
FROM   raw_bureau
WHERE  credit_active = 'Active';

-- ---------------------------------------------------------------------
-- F. Partitioning available? (needed for Stage 2f snapshots)
-- ---------------------------------------------------------------------
SET TIMING OFF
PROMPT
PROMPT ===== F. Partitioning test =====
WHENEVER SQLERROR CONTINUE
EXEC p_drop_if_exists('ZZ_PART_TEST')
CREATE TABLE zz_part_test (snapshot_date DATE, n NUMBER)
PARTITION BY LIST (snapshot_date) AUTOMATIC
(PARTITION p_first VALUES (DATE '2000-01-01'));
SELECT CASE WHEN COUNT(*) = 1 THEN 'Partitioning: AVAILABLE'
            ELSE 'Partitioning: NOT available' END AS check_result
FROM   user_part_tables WHERE table_name = 'ZZ_PART_TEST';
EXEC p_drop_if_exists('ZZ_PART_TEST')

PROMPT
PROMPT ===== 03_grain_profiling: done =====
EXIT
