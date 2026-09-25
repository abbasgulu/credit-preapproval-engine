-- =====================================================================
-- 03_feat_previous.sql
-- Previous applications at the same lender. One row per client. Repeated applications removed with Kaggle's own flags (decision 11).
--
-- Every client of v_population gets exactly one row; clients without
-- history get 0 for counts / flags and NULL for amounts and ratios.
-- Checked right after creation (improvement 6).
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
ALTER SESSION SET NLS_NUMERIC_CHARACTERS = '.,';

PROMPT
PROMPT ===== feat_previous =====
EXEC p_drop_if_exists('FEAT_PREVIOUS')
CREATE TABLE feat_previous AS
WITH agg AS (
  SELECT
    sk_id_curr,
    1                                                                       AS prv_has_history,
    COUNT(*)                                                                AS prv_app_cnt,
    SUM(CASE WHEN name_contract_status = 'Approved' THEN 1 ELSE 0 END)      AS prv_approved_cnt,
    SUM(CASE WHEN name_contract_status = 'Refused'  THEN 1 ELSE 0 END)      AS prv_refused_cnt,
    SUM(CASE WHEN name_contract_status = 'Canceled' THEN 1 ELSE 0 END)      AS prv_canceled_cnt,
    SUM(CASE WHEN name_contract_status = 'Refused'  THEN 1 ELSE 0 END) / COUNT(*) AS prv_refused_share,
    SUM(CASE WHEN days_decision >= -730 THEN 1 ELSE 0 END)                  AS prv_app_cnt_2y,
    SUM(CASE WHEN days_decision >= -730
              AND name_contract_status = 'Refused' THEN 1 ELSE 0 END)       AS prv_refused_cnt_2y,
    MIN(-days_decision)                                                     AS prv_last_decision_days_ago,
    AVG(CASE WHEN name_contract_status = 'Approved'
             THEN amt_credit / NULLIF(amt_application, 0) END)              AS prv_granted_to_asked_avg,
    NVL(SUM(CASE WHEN name_contract_status = 'Approved' THEN amt_credit END), 0) AS prv_approved_credit_sum
  FROM   raw_previous_application
  WHERE  flag_last_appl_per_contract = 'Y'
  AND    nflag_last_appl_in_day = 1
  GROUP  BY sk_id_curr
)
SELECT
  p.sk_id_curr,
  NVL(a.prv_has_history, 0) AS prv_has_history,
  NVL(a.prv_app_cnt, 0) AS prv_app_cnt,
  NVL(a.prv_approved_cnt, 0) AS prv_approved_cnt,
  NVL(a.prv_refused_cnt, 0) AS prv_refused_cnt,
  NVL(a.prv_canceled_cnt, 0) AS prv_canceled_cnt,
  a.prv_refused_share,
  NVL(a.prv_app_cnt_2y, 0) AS prv_app_cnt_2y,
  NVL(a.prv_refused_cnt_2y, 0) AS prv_refused_cnt_2y,
  a.prv_last_decision_days_ago,
  a.prv_granted_to_asked_avg,
  NVL(a.prv_approved_credit_sum, 0) AS prv_approved_credit_sum
FROM   v_population p
LEFT   JOIN agg a ON a.sk_id_curr = p.sk_id_curr;

-- Column comments (quiet: ~20 lines of 'Comment created.' are not useful)
SET FEEDBACK OFF
SET TIMING OFF
COMMENT ON TABLE feat_previous IS 'Previous applications at the same lender. One row per client. Repeated applications removed with Kaggle''s own flags (decision 11).';
COMMENT ON COLUMN feat_previous.sk_id_curr IS 'Client / application ID. Unique in this table.';
COMMENT ON COLUMN feat_previous.prv_has_history IS '1 when the client has at least one previous application.';
COMMENT ON COLUMN feat_previous.prv_app_cnt IS 'Previous applications (last application per contract and per day only, decision 11).';
COMMENT ON COLUMN feat_previous.prv_approved_cnt IS 'Previous applications approved.';
COMMENT ON COLUMN feat_previous.prv_refused_cnt IS 'Previous applications refused.';
COMMENT ON COLUMN feat_previous.prv_canceled_cnt IS 'Previous applications cancelled.';
COMMENT ON COLUMN feat_previous.prv_refused_share IS 'Refused / all previous applications; NULL without history.';
COMMENT ON COLUMN feat_previous.prv_app_cnt_2y IS 'Previous applications decided in the 730 days before application.';
COMMENT ON COLUMN feat_previous.prv_refused_cnt_2y IS 'Previous applications refused in the 730 days before application.';
COMMENT ON COLUMN feat_previous.prv_last_decision_days_ago IS 'Days between the most recent previous decision and this application.';
COMMENT ON COLUMN feat_previous.prv_granted_to_asked_avg IS 'Average of granted / asked amount over approved applications (below 1 = client got less than asked).';
COMMENT ON COLUMN feat_previous.prv_approved_credit_sum IS 'Sum of credit amounts of approved previous applications.';
SET FEEDBACK ON
SET TIMING ON

-- Checks
EXEC p_dq_unique('FEAT_PREVIOUS')
EXEC p_dq_rowcount('FEAT_PREVIOUS', 356255)
EXEC p_dq_range('FEAT_PREVIOUS', 'PRV_REFUSED_SHARE', 0, 1)

PROMPT feat_previous: done
