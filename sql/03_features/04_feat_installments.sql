-- =====================================================================
-- 04_feat_installments.sql
-- Repayment discipline on previous credits. One row per client. Aggregated in two steps: payment rows -> instalment -> client (decision 10).
--
-- Every client of v_population gets exactly one row; clients without
-- history get 0 for counts / flags and NULL for amounts and ratios.
-- Checked right after creation (improvement 6).
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
ALTER SESSION SET NLS_NUMERIC_CHARACTERS = '.,';

-- -----------------------------------------------------------------------
-- Step 1 checks (decision 10). One instalment can be paid in several rows:
-- 13,605,401 payment rows belong to 12,951,918 instalments.
-- -----------------------------------------------------------------------
EXEC p_dq('RAW_INSTALLMENTS_PAYMENTS', 'distinct instalments (measured 12,951,918)', 'SELECT COUNT(*) FROM (SELECT DISTINCT sk_id_curr, sk_id_prev, num_instalment_version, num_instalment_number FROM raw_installments_payments)', 12951918)
EXEC p_dq('RAW_INSTALLMENTS_PAYMENTS', 'instalments whose rows disagree on the amount due', 'SELECT COUNT(*) FROM (SELECT 1 FROM raw_installments_payments GROUP BY sk_id_prev, num_instalment_version, num_instalment_number HAVING MIN(amt_instalment) <> MAX(amt_instalment))', 0, 'WARN')
EXEC p_dq('RAW_INSTALLMENTS_PAYMENTS', 'instalments whose rows disagree on the due date', 'SELECT COUNT(*) FROM (SELECT 1 FROM raw_installments_payments GROUP BY sk_id_prev, num_instalment_version, num_instalment_number HAVING MIN(days_instalment) <> MAX(days_instalment))', 0, 'WARN')

PROMPT
PROMPT ===== feat_installments =====
EXEC p_drop_if_exists('FEAT_INSTALLMENTS')
CREATE TABLE feat_installments AS
WITH inst AS (    -- step 1: one row per instalment
    SELECT sk_id_curr, sk_id_prev, num_instalment_version, num_instalment_number,
           MAX(amt_instalment)        AS amt_due,
           MAX(days_instalment)       AS days_due,
           SUM(NVL(amt_payment, 0))   AS amt_paid,
           MAX(days_entry_payment)    AS days_paid_last
    FROM   raw_installments_payments
    GROUP  BY sk_id_curr, sk_id_prev, num_instalment_version, num_instalment_number
  ),
agg AS (
  SELECT            -- step 2: one row per client
    sk_id_curr,
    1                                                                      AS ins_has_history,
    COUNT(*)                                                               AS ins_cnt_all,
    SUM(CASE WHEN days_paid_last > days_due THEN 1 ELSE 0 END) / COUNT(*)  AS ins_late_share_all,
    MAX(GREATEST(days_paid_last - days_due, 0))                            AS ins_days_late_max_all,
    AVG(GREATEST(days_paid_last - days_due, 0))                            AS ins_days_late_avg_all,
    SUM(CASE WHEN amt_paid < amt_due - 0.01 THEN 1 ELSE 0 END) / COUNT(*)  AS ins_underpaid_share_all,
    SUM(CASE WHEN days_paid_last IS NULL THEN 1 ELSE 0 END)                AS ins_unpaid_cnt_all,
    SUM(CASE WHEN days_due >= -365 THEN 1 ELSE 0 END)                      AS ins_cnt_12m,
    SUM(CASE WHEN days_due >= -365 AND days_paid_last > days_due THEN 1 ELSE 0 END)
      / NULLIF(SUM(CASE WHEN days_due >= -365 THEN 1 ELSE 0 END), 0)       AS ins_late_share_12m,
    MAX(CASE WHEN days_due >= -365 THEN GREATEST(days_paid_last - days_due, 0) END) AS ins_days_late_max_12m,
    SUM(CASE WHEN days_due >= -365 AND amt_paid < amt_due - 0.01 THEN 1 ELSE 0 END)
      / NULLIF(SUM(CASE WHEN days_due >= -365 THEN 1 ELSE 0 END), 0)       AS ins_underpaid_share_12m
  FROM   inst
  GROUP  BY sk_id_curr
)
SELECT
  p.sk_id_curr,
  NVL(a.ins_has_history, 0) AS ins_has_history,
  NVL(a.ins_cnt_all, 0) AS ins_cnt_all,
  a.ins_late_share_all,
  a.ins_days_late_max_all,
  a.ins_days_late_avg_all,
  a.ins_underpaid_share_all,
  NVL(a.ins_unpaid_cnt_all, 0) AS ins_unpaid_cnt_all,
  NVL(a.ins_cnt_12m, 0) AS ins_cnt_12m,
  a.ins_late_share_12m,
  a.ins_days_late_max_12m,
  a.ins_underpaid_share_12m
FROM   v_population p
LEFT   JOIN agg a ON a.sk_id_curr = p.sk_id_curr;

-- Column comments (quiet: ~20 lines of 'Comment created.' are not useful)
SET FEEDBACK OFF
SET TIMING OFF
COMMENT ON TABLE feat_installments IS 'Repayment discipline on previous credits. One row per client. Aggregated in two steps: payment rows -> instalment -> client (decision 10).';
COMMENT ON COLUMN feat_installments.sk_id_curr IS 'Client / application ID. Unique in this table.';
COMMENT ON COLUMN feat_installments.ins_has_history IS '1 when the client has instalment history on previous credits.';
COMMENT ON COLUMN feat_installments.ins_cnt_all IS 'Instalments due (after merging partial payments into one instalment, decision 10).';
COMMENT ON COLUMN feat_installments.ins_late_share_all IS 'Share of instalments whose last payment came after the due date.';
COMMENT ON COLUMN feat_installments.ins_days_late_max_all IS 'Maximum days between due date and last payment.';
COMMENT ON COLUMN feat_installments.ins_days_late_avg_all IS 'Average days late (early payment counts as 0).';
COMMENT ON COLUMN feat_installments.ins_underpaid_share_all IS 'Share of instalments where the total paid is below the amount due.';
COMMENT ON COLUMN feat_installments.ins_unpaid_cnt_all IS 'Instalments with no payment recorded.';
COMMENT ON COLUMN feat_installments.ins_cnt_12m IS 'Instalments due in the 365 days before application.';
COMMENT ON COLUMN feat_installments.ins_late_share_12m IS 'Share of instalments paid late, last 365 days.';
COMMENT ON COLUMN feat_installments.ins_days_late_max_12m IS 'Maximum days late, last 365 days.';
COMMENT ON COLUMN feat_installments.ins_underpaid_share_12m IS 'Share of instalments underpaid, last 365 days.';
SET FEEDBACK ON
SET TIMING ON

-- Checks
EXEC p_dq_unique('FEAT_INSTALLMENTS')
EXEC p_dq_rowcount('FEAT_INSTALLMENTS', 356255)
EXEC p_dq_range('FEAT_INSTALLMENTS', 'INS_LATE_SHARE_ALL', 0, 1)
EXEC p_dq_range('FEAT_INSTALLMENTS', 'INS_UNDERPAID_SHARE_ALL', 0, 1)
EXEC p_dq('FEAT_INSTALLMENTS', 'sum of instalments = distinct instalments', 'SELECT SUM(ins_cnt_all) FROM feat_installments', 12951918)

PROMPT feat_installments: done
