-- =====================================================================
-- 06_feat_credit_card.sql
-- Monthly balances of previous credit cards. One row per client. Only 29.1% of clients have card history.
--
-- Every client of v_population gets exactly one row; clients without
-- history get 0 for counts / flags and NULL for amounts and ratios.
-- Checked right after creation (improvement 6).
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
ALTER SESSION SET NLS_NUMERIC_CHARACTERS = '.,';

PROMPT
PROMPT ===== feat_credit_card =====
EXEC p_drop_if_exists('FEAT_CREDIT_CARD')
CREATE TABLE feat_credit_card AS
WITH agg AS (
  SELECT
    sk_id_curr,
    1                                                                         AS cc_has_history,
    COUNT(DISTINCT sk_id_prev)                                                AS cc_card_cnt,
    AVG(CASE WHEN months_balance >= -12
             THEN amt_balance / NULLIF(amt_credit_limit_actual, 0) END)       AS cc_util_avg_12m,
    MAX(CASE WHEN months_balance >= -12
             THEN amt_balance / NULLIF(amt_credit_limit_actual, 0) END)       AS cc_util_max_12m,
    COUNT(DISTINCT CASE WHEN months_balance >= -12 AND amt_drawings_current > 0
                        THEN months_balance END)                              AS cc_active_months_12m,
    AVG(CASE WHEN months_balance >= -12 THEN amt_drawings_current END)        AS cc_drawings_avg_12m,
    AVG(CASE WHEN months_balance >= -12 AND amt_inst_min_regularity > 0
             THEN amt_payment_total_current / amt_inst_min_regularity END)    AS cc_pay_to_min_avg_12m,
    MAX(sk_dpd)                                                               AS cc_dpd_max_all,
    SUM(CASE WHEN months_balance >= -12 AND sk_dpd > 0 THEN 1 ELSE 0 END)     AS cc_dpd_months_12m
  FROM   raw_credit_card_balance
  GROUP  BY sk_id_curr
)
SELECT
  p.sk_id_curr,
  NVL(a.cc_has_history, 0) AS cc_has_history,
  NVL(a.cc_card_cnt, 0) AS cc_card_cnt,
  a.cc_util_avg_12m,
  a.cc_util_max_12m,
  NVL(a.cc_active_months_12m, 0) AS cc_active_months_12m,
  a.cc_drawings_avg_12m,
  a.cc_pay_to_min_avg_12m,
  a.cc_dpd_max_all,
  NVL(a.cc_dpd_months_12m, 0) AS cc_dpd_months_12m
FROM   v_population p
LEFT   JOIN agg a ON a.sk_id_curr = p.sk_id_curr;

-- Column comments (quiet: ~20 lines of 'Comment created.' are not useful)
SET FEEDBACK OFF
SET TIMING OFF
COMMENT ON TABLE feat_credit_card IS 'Monthly balances of previous credit cards. One row per client. Only 29.1% of clients have card history.';
COMMENT ON COLUMN feat_credit_card.sk_id_curr IS 'Client / application ID. Unique in this table.';
COMMENT ON COLUMN feat_credit_card.cc_has_history IS '1 when the client has credit card history.';
COMMENT ON COLUMN feat_credit_card.cc_card_cnt IS 'Previous credit cards.';
COMMENT ON COLUMN feat_credit_card.cc_util_avg_12m IS 'Average balance / limit, last 12 months.';
COMMENT ON COLUMN feat_credit_card.cc_util_max_12m IS 'Maximum balance / limit, last 12 months.';
COMMENT ON COLUMN feat_credit_card.cc_active_months_12m IS 'Months with any card spending in the last 12 months (0-12).';
COMMENT ON COLUMN feat_credit_card.cc_drawings_avg_12m IS 'Average monthly drawings, last 12 months.';
COMMENT ON COLUMN feat_credit_card.cc_pay_to_min_avg_12m IS 'Average total payment / minimum instalment, last 12 months (below 1 = paid less than the minimum).';
COMMENT ON COLUMN feat_credit_card.cc_dpd_max_all IS 'Maximum days past due on any card in any month.';
COMMENT ON COLUMN feat_credit_card.cc_dpd_months_12m IS 'Card-months with DPD > 0, last 12 months.';
SET FEEDBACK ON
SET TIMING ON

-- Checks
EXEC p_dq_unique('FEAT_CREDIT_CARD')
EXEC p_dq_rowcount('FEAT_CREDIT_CARD', 356255)
EXEC p_dq_range('FEAT_CREDIT_CARD', 'CC_ACTIVE_MONTHS_12M', 0, 12)
EXEC p_dq('FEAT_CREDIT_CARD', 'clients with card history (measured 103,558)', 'SELECT COUNT(*) FROM feat_credit_card WHERE cc_has_history = 1', 103558)

PROMPT feat_credit_card: done
