-- =====================================================================
-- 05_feat_pos_cash.sql
-- Monthly balances of previous POS and cash loans. One row per client.
--
-- Every client of v_population gets exactly one row; clients without
-- history get 0 for counts / flags and NULL for amounts and ratios.
-- Checked right after creation (improvement 6).
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
ALTER SESSION SET NLS_NUMERIC_CHARACTERS = '.,';

PROMPT
PROMPT ===== feat_pos_cash =====
EXEC p_drop_if_exists('FEAT_POS_CASH')
CREATE TABLE feat_pos_cash AS
WITH latest AS (  -- latest month of each contract
    SELECT sk_id_curr, sk_id_prev, name_contract_status, cnt_instalment_future,
           ROW_NUMBER() OVER (PARTITION BY sk_id_prev ORDER BY months_balance DESC) AS rn
    FROM   raw_pos_cash_balance
  ),
  latest_agg AS (
    SELECT sk_id_curr,
           SUM(CASE WHEN name_contract_status = 'Active' THEN 1 ELSE 0 END)                      AS active_cnt,
           NVL(SUM(CASE WHEN name_contract_status = 'Active' THEN cnt_instalment_future END), 0) AS left_sum
    FROM   latest
    WHERE  rn = 1
    GROUP  BY sk_id_curr
  ),
  monthly AS (
    SELECT sk_id_curr,
           COUNT(DISTINCT sk_id_prev)                                          AS contract_cnt,
           MAX(sk_dpd)                                                         AS dpd_max_all,
           MAX(sk_dpd_def)                                                     AS dpd_def_max_all,
           SUM(CASE WHEN sk_dpd > 0 THEN 1 ELSE 0 END)                         AS dpd_months_all,
           MAX(CASE WHEN months_balance >= -12 THEN sk_dpd END)                AS dpd_max_12m,
           SUM(CASE WHEN months_balance >= -12 AND sk_dpd > 0 THEN 1 ELSE 0 END) AS dpd_months_12m
    FROM   raw_pos_cash_balance
    GROUP  BY sk_id_curr
  ),
agg AS (
  SELECT m.sk_id_curr,
         1                  AS pos_has_history,
         m.contract_cnt     AS pos_contract_cnt,
         l.active_cnt       AS pos_active_cnt,
         l.left_sum         AS pos_instalments_left_sum,
         m.dpd_max_all      AS pos_dpd_max_all,
         m.dpd_def_max_all  AS pos_dpd_def_max_all,
         m.dpd_months_all   AS pos_dpd_months_all,
         m.dpd_max_12m      AS pos_dpd_max_12m,
         m.dpd_months_12m   AS pos_dpd_months_12m
  FROM   monthly m
  JOIN   latest_agg l ON l.sk_id_curr = m.sk_id_curr
)
SELECT
  p.sk_id_curr,
  NVL(a.pos_has_history, 0) AS pos_has_history,
  NVL(a.pos_contract_cnt, 0) AS pos_contract_cnt,
  NVL(a.pos_active_cnt, 0) AS pos_active_cnt,
  NVL(a.pos_instalments_left_sum, 0) AS pos_instalments_left_sum,
  a.pos_dpd_max_all,
  a.pos_dpd_def_max_all,
  NVL(a.pos_dpd_months_all, 0) AS pos_dpd_months_all,
  a.pos_dpd_max_12m,
  NVL(a.pos_dpd_months_12m, 0) AS pos_dpd_months_12m
FROM   v_population p
LEFT   JOIN agg a ON a.sk_id_curr = p.sk_id_curr;

-- Column comments (quiet: ~20 lines of 'Comment created.' are not useful)
SET FEEDBACK OFF
SET TIMING OFF
COMMENT ON TABLE feat_pos_cash IS 'Monthly balances of previous POS and cash loans. One row per client.';
COMMENT ON COLUMN feat_pos_cash.sk_id_curr IS 'Client / application ID. Unique in this table.';
COMMENT ON COLUMN feat_pos_cash.pos_has_history IS '1 when the client has POS or cash loan balance history.';
COMMENT ON COLUMN feat_pos_cash.pos_contract_cnt IS 'Previous POS / cash contracts.';
COMMENT ON COLUMN feat_pos_cash.pos_active_cnt IS 'Contracts whose latest monthly status is Active.';
COMMENT ON COLUMN feat_pos_cash.pos_instalments_left_sum IS 'Instalments left to pay on active contracts (latest month).';
COMMENT ON COLUMN feat_pos_cash.pos_dpd_max_all IS 'Maximum days past due in any month.';
COMMENT ON COLUMN feat_pos_cash.pos_dpd_def_max_all IS 'Maximum days past due with tolerance (small debts ignored), any month.';
COMMENT ON COLUMN feat_pos_cash.pos_dpd_months_all IS 'Contract-months with DPD > 0.';
COMMENT ON COLUMN feat_pos_cash.pos_dpd_max_12m IS 'Maximum days past due, last 12 months (MONTHS_BALANCE -1 to -12; the latest month in this source is -1).';
COMMENT ON COLUMN feat_pos_cash.pos_dpd_months_12m IS 'Contract-months with DPD > 0, last 12 months.';
SET FEEDBACK ON
SET TIMING ON

-- Checks
EXEC p_dq_unique('FEAT_POS_CASH')
EXEC p_dq_rowcount('FEAT_POS_CASH', 356255)
EXEC p_dq_range('FEAT_POS_CASH', 'POS_DPD_MAX_ALL', 0, 100000)

PROMPT feat_pos_cash: done
