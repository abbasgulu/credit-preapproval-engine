-- =====================================================================
-- 02_feat_bureau.sql
-- Credits at other lenders (credit bureau). One row per client. Source: raw_bureau + raw_bureau_balance, aggregated in two steps (per credit, then per client).
--
-- Every client of v_population gets exactly one row; clients without
-- history get 0 for counts / flags and NULL for amounts and ratios.
-- Checked right after creation (improvement 6).
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
ALTER SESSION SET NLS_NUMERIC_CHARACTERS = '.,';

PROMPT
PROMPT ===== feat_bureau =====
EXEC p_drop_if_exists('FEAT_BUREAU')
CREATE TABLE feat_bureau AS
WITH bb AS (      -- step 1: one row per bureau credit
    SELECT sk_id_bureau,
           MAX(CASE WHEN status IN ('1','2','3','4','5') THEN TO_NUMBER(status)
                    WHEN status = '0' THEN 0 END)                          AS worst_all,
           -- bureau_balance has month 0, so months 0..-11 = the last 12 months
           MAX(CASE WHEN months_balance >= -11 THEN
                 CASE WHEN status IN ('1','2','3','4','5') THEN TO_NUMBER(status)
                      WHEN status = '0' THEN 0 END END)                    AS worst_12m,
           SUM(CASE WHEN months_balance >= -11
                     AND status IN ('1','2','3','4','5') THEN 1 ELSE 0 END) AS dpd_months_12m
    FROM   raw_bureau_balance
    GROUP  BY sk_id_bureau
  ),
agg AS (
  SELECT            -- step 2: one row per client
    b.sk_id_curr,
    1                                                                  AS bur_has_history,
    COUNT(*)                                                           AS bur_credit_cnt,
    SUM(CASE WHEN b.credit_active = 'Active' THEN 1 ELSE 0 END)        AS bur_active_cnt,
    SUM(CASE WHEN b.credit_active = 'Closed' THEN 1 ELSE 0 END)        AS bur_closed_cnt,
    SUM(CASE WHEN b.credit_active IN ('Sold', 'Bad debt') THEN 1 ELSE 0 END) AS bur_bad_status_cnt,
    NVL(SUM(CASE WHEN b.credit_active = 'Active' THEN b.amt_credit_sum END), 0)      AS bur_active_credit_sum,
    NVL(SUM(CASE WHEN b.credit_active = 'Active' THEN b.amt_credit_sum_debt END), 0) AS bur_active_debt_sum,
    NVL(SUM(CASE WHEN b.credit_active = 'Active' THEN b.amt_credit_sum_overdue END), 0) AS bur_active_overdue_sum,
    NVL(MAX(b.credit_day_overdue), 0)                                  AS bur_current_dpd_max,
    MAX(b.amt_credit_max_overdue)                                      AS bur_max_overdue_amt_ever,
    NVL(SUM(b.cnt_credit_prolong), 0)                                  AS bur_prolong_cnt,
    MIN(-b.days_credit)                                                AS bur_last_credit_days_ago,
    SUM(CASE WHEN b.days_credit >= -365 THEN 1 ELSE 0 END)             AS bur_new_credit_cnt_12m,
    NVL(SUM(CASE WHEN b.credit_active = 'Active' AND b.amt_annuity > 0 THEN b.amt_annuity END), 0) AS bur_annuity_known_sum,
    SUM(CASE WHEN b.credit_active = 'Active' AND b.amt_annuity > 0 THEN 1 ELSE 0 END)  AS bur_annuity_known_cnt,
    MAX(CASE WHEN bb.sk_id_bureau IS NOT NULL THEN 1 ELSE 0 END)       AS bb_has_history,
    MAX(bb.worst_all)                                                  AS bb_worst_status_all,
    MAX(bb.worst_12m)                                                  AS bb_worst_status_12m,
    NVL(SUM(bb.dpd_months_12m), 0)                                     AS bb_dpd_months_12m
  FROM   raw_bureau b
  LEFT   JOIN bb ON bb.sk_id_bureau = b.sk_id_bureau
  GROUP  BY b.sk_id_curr
)
SELECT
  p.sk_id_curr,
  NVL(a.bur_has_history, 0) AS bur_has_history,
  NVL(a.bur_credit_cnt, 0) AS bur_credit_cnt,
  NVL(a.bur_active_cnt, 0) AS bur_active_cnt,
  NVL(a.bur_closed_cnt, 0) AS bur_closed_cnt,
  NVL(a.bur_bad_status_cnt, 0) AS bur_bad_status_cnt,
  NVL(a.bur_active_credit_sum, 0) AS bur_active_credit_sum,
  NVL(a.bur_active_debt_sum, 0) AS bur_active_debt_sum,
  NVL(a.bur_active_overdue_sum, 0) AS bur_active_overdue_sum,
  NVL(a.bur_current_dpd_max, 0) AS bur_current_dpd_max,
  a.bur_max_overdue_amt_ever,
  NVL(a.bur_prolong_cnt, 0) AS bur_prolong_cnt,
  a.bur_last_credit_days_ago,
  NVL(a.bur_new_credit_cnt_12m, 0) AS bur_new_credit_cnt_12m,
  NVL(a.bur_annuity_known_sum, 0) AS bur_annuity_known_sum,
  NVL(a.bur_annuity_known_cnt, 0) AS bur_annuity_known_cnt,
  NVL(a.bb_has_history, 0) AS bb_has_history,
  a.bb_worst_status_all,
  a.bb_worst_status_12m,
  NVL(a.bb_dpd_months_12m, 0) AS bb_dpd_months_12m
FROM   v_population p
LEFT   JOIN agg a ON a.sk_id_curr = p.sk_id_curr;

-- Column comments (quiet: ~20 lines of 'Comment created.' are not useful)
SET FEEDBACK OFF
SET TIMING OFF
COMMENT ON TABLE feat_bureau IS 'Credits at other lenders (credit bureau). One row per client. Source: raw_bureau + raw_bureau_balance, aggregated in two steps (per credit, then per client).';
COMMENT ON COLUMN feat_bureau.sk_id_curr IS 'Client / application ID. Unique in this table.';
COMMENT ON COLUMN feat_bureau.bur_has_history IS '1 when the client has at least one credit in the bureau.';
COMMENT ON COLUMN feat_bureau.bur_credit_cnt IS 'Bureau credits, all statuses.';
COMMENT ON COLUMN feat_bureau.bur_active_cnt IS 'Active bureau credits.';
COMMENT ON COLUMN feat_bureau.bur_closed_cnt IS 'Closed bureau credits.';
COMMENT ON COLUMN feat_bureau.bur_bad_status_cnt IS 'Bureau credits with status Sold or Bad debt (merged: Bad debt has only 21 rows).';
COMMENT ON COLUMN feat_bureau.bur_active_credit_sum IS 'Sum of credit amounts of active bureau credits.';
COMMENT ON COLUMN feat_bureau.bur_active_debt_sum IS 'Sum of current debt on active bureau credits.';
COMMENT ON COLUMN feat_bureau.bur_active_overdue_sum IS 'Sum of amounts currently overdue on active bureau credits.';
COMMENT ON COLUMN feat_bureau.bur_current_dpd_max IS 'Maximum days past due on any bureau credit at application.';
COMMENT ON COLUMN feat_bureau.bur_max_overdue_amt_ever IS 'Largest amount ever overdue on any bureau credit.';
COMMENT ON COLUMN feat_bureau.bur_prolong_cnt IS 'Number of prolongations over all bureau credits.';
COMMENT ON COLUMN feat_bureau.bur_last_credit_days_ago IS 'Days between the most recent bureau credit application and this application.';
COMMENT ON COLUMN feat_bureau.bur_new_credit_cnt_12m IS 'Bureau credits applied for in the 365 days before application.';
COMMENT ON COLUMN feat_bureau.bur_annuity_known_sum IS 'Sum of annuities of active bureau credits where the annuity is reported (> 0). Reported for only 22.2% of active credits (decision 12).';
COMMENT ON COLUMN feat_bureau.bur_annuity_known_cnt IS 'Active bureau credits with a reported annuity.';
COMMENT ON COLUMN feat_bureau.bb_has_history IS '1 when monthly bureau status history exists for at least one credit (37.8% of clients).';
COMMENT ON COLUMN feat_bureau.bb_worst_status_all IS 'Worst monthly bureau status ever: 0 = no DPD, 1 = 1-30, 2 = 31-60, 3 = 61-90, 4 = 91-120, 5 = 120+ or sold / written off.';
COMMENT ON COLUMN feat_bureau.bb_worst_status_12m IS 'Worst monthly bureau status in the last 12 months (MONTHS_BALANCE 0 to -11; bureau data includes month 0). Same scale as bb_worst_status_all.';
COMMENT ON COLUMN feat_bureau.bb_dpd_months_12m IS 'Credit-months with DPD (status 1-5) in the last 12 months (MONTHS_BALANCE 0 to -11), summed over bureau credits.';
SET FEEDBACK ON
SET TIMING ON

-- Checks
EXEC p_dq_unique('FEAT_BUREAU')
EXEC p_dq_rowcount('FEAT_BUREAU', 356255)
EXEC p_dq_range('FEAT_BUREAU', 'BB_WORST_STATUS_ALL', 0, 5)
EXEC p_dq_range('FEAT_BUREAU', 'BUR_CREDIT_CNT', 0, 1000)
EXEC p_dq('FEAT_BUREAU', 'clients with bureau history (measured 305,811)', 'SELECT COUNT(*) FROM feat_bureau WHERE bur_has_history = 1', 305811)
EXEC p_dq('FEAT_BUREAU', 'clients with bureau_balance history (measured 134,542)', 'SELECT COUNT(*) FROM feat_bureau WHERE bb_has_history = 1', 134542)

PROMPT feat_bureau: done
