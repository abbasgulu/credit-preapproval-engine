-- =====================================================================
-- 07_feat_customer.sql
-- One row per client with every feature: the input of the model (Stage 3)
-- and of the decision engine (Stage 4).
--
-- Inner joins are safe here: every feature table was checked to contain
-- exactly the 356,255 clients of v_population. The row-count check below
-- proves no client was lost or duplicated by the joins.
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE

PROMPT
PROMPT ===== feat_customer =====
EXEC p_drop_if_exists('FEAT_CUSTOMER')
CREATE TABLE feat_customer AS
SELECT
  p.sk_id_curr,
  p.dataset,
  p.target,
  fa.app_contract_type,
  fa.app_income_type,
  fa.app_education,
  fa.app_family_status,
  fa.app_children_cnt,
  fa.app_family_members_cnt,
  fa.app_age_years,
  fa.app_employed_years,
  fa.app_is_not_employed,
  fa.app_income_amt,
  fa.app_credit_amt,
  fa.app_annuity_amt,
  fa.app_goods_price_amt,
  fa.app_credit_to_income,
  fa.app_annuity_to_income,
  fa.app_credit_to_goods,
  fa.app_ext_source_1,
  fa.app_ext_source_2,
  fa.app_ext_source_3,
  fa.app_ext_source_mean,
  fa.app_region_rating,
  fa.app_documents_cnt,
  fa.app_bureau_enquiries_1y,
  fb.bur_has_history,
  fb.bur_credit_cnt,
  fb.bur_active_cnt,
  fb.bur_closed_cnt,
  fb.bur_bad_status_cnt,
  fb.bur_active_credit_sum,
  fb.bur_active_debt_sum,
  fb.bur_active_overdue_sum,
  fb.bur_current_dpd_max,
  fb.bur_max_overdue_amt_ever,
  fb.bur_prolong_cnt,
  fb.bur_last_credit_days_ago,
  fb.bur_new_credit_cnt_12m,
  fb.bur_annuity_known_sum,
  fb.bur_annuity_known_cnt,
  fb.bb_has_history,
  fb.bb_worst_status_all,
  fb.bb_worst_status_12m,
  fb.bb_dpd_months_12m,
  fp.prv_has_history,
  fp.prv_app_cnt,
  fp.prv_approved_cnt,
  fp.prv_refused_cnt,
  fp.prv_canceled_cnt,
  fp.prv_refused_share,
  fp.prv_app_cnt_2y,
  fp.prv_refused_cnt_2y,
  fp.prv_last_decision_days_ago,
  fp.prv_granted_to_asked_avg,
  fp.prv_approved_credit_sum,
  fi.ins_has_history,
  fi.ins_cnt_all,
  fi.ins_late_share_all,
  fi.ins_days_late_max_all,
  fi.ins_days_late_avg_all,
  fi.ins_underpaid_share_all,
  fi.ins_unpaid_cnt_all,
  fi.ins_cnt_12m,
  fi.ins_late_share_12m,
  fi.ins_days_late_max_12m,
  fi.ins_underpaid_share_12m,
  fc.pos_has_history,
  fc.pos_contract_cnt,
  fc.pos_active_cnt,
  fc.pos_instalments_left_sum,
  fc.pos_dpd_max_all,
  fc.pos_dpd_def_max_all,
  fc.pos_dpd_months_all,
  fc.pos_dpd_max_12m,
  fc.pos_dpd_months_12m,
  fk.cc_has_history,
  fk.cc_card_cnt,
  fk.cc_util_avg_12m,
  fk.cc_util_max_12m,
  fk.cc_active_months_12m,
  fk.cc_drawings_avg_12m,
  fk.cc_pay_to_min_avg_12m,
  fk.cc_dpd_max_all,
  fk.cc_dpd_months_12m,
  fb.bur_active_debt_sum / NULLIF(fa.app_income_amt, 0) AS bur_debt_to_income,
  fb.bur_annuity_known_sum / NULLIF(fa.app_income_amt, 0) AS bur_annuity_to_income
FROM   v_population p
JOIN   feat_application   fa ON fa.sk_id_curr = p.sk_id_curr
JOIN   feat_bureau        fb ON fb.sk_id_curr = p.sk_id_curr
JOIN   feat_previous      fp ON fp.sk_id_curr = p.sk_id_curr
JOIN   feat_installments  fi ON fi.sk_id_curr = p.sk_id_curr
JOIN   feat_pos_cash      fc ON fc.sk_id_curr = p.sk_id_curr
JOIN   feat_credit_card   fk ON fk.sk_id_curr = p.sk_id_curr;

SET FEEDBACK OFF
SET TIMING OFF
COMMENT ON TABLE feat_customer IS 'All features, one row per client. Input of the model and the decision engine.';
COMMENT ON COLUMN feat_customer.sk_id_curr IS 'Client / application ID. Unique in this table.';
COMMENT ON COLUMN feat_customer.dataset IS 'train = known outcome, used for the model; test = treated as incoming applicants.';
COMMENT ON COLUMN feat_customer.target IS '1 = client had payment difficulties on the current loan (Kaggle definition); NULL for test.';
COMMENT ON COLUMN feat_customer.app_contract_type IS 'Product of the current application: Cash loans or Revolving loans.';
COMMENT ON COLUMN feat_customer.app_income_type IS 'Income type of the client (Working, Pensioner, ...).';
COMMENT ON COLUMN feat_customer.app_education IS 'Highest education level.';
COMMENT ON COLUMN feat_customer.app_family_status IS 'Family status.';
COMMENT ON COLUMN feat_customer.app_children_cnt IS 'Number of children.';
COMMENT ON COLUMN feat_customer.app_family_members_cnt IS 'Number of family members.';
COMMENT ON COLUMN feat_customer.app_age_years IS 'Age at application, in years (from DAYS_BIRTH).';
COMMENT ON COLUMN feat_customer.app_employed_years IS 'Length of current employment in years. NULL when DAYS_EMPLOYED = 365243 (not employed, decision 9).';
COMMENT ON COLUMN feat_customer.app_is_not_employed IS '1 when DAYS_EMPLOYED = 365243: pensioners and unemployed (decision 9).';
COMMENT ON COLUMN feat_customer.app_income_amt IS 'Income of the client (AMT_INCOME_TOTAL, as given by Kaggle).';
COMMENT ON COLUMN feat_customer.app_credit_amt IS 'Credit amount of the current application.';
COMMENT ON COLUMN feat_customer.app_annuity_amt IS 'Annuity of the current application (AMT_ANNUITY).';
COMMENT ON COLUMN feat_customer.app_goods_price_amt IS 'Price of the goods financed (consumer loans).';
COMMENT ON COLUMN feat_customer.app_credit_to_income IS 'Credit amount / income.';
COMMENT ON COLUMN feat_customer.app_annuity_to_income IS 'AMT_ANNUITY / AMT_INCOME_TOTAL as given. Kaggle does not document the period of either amount, so this is a relative burden measure, not a monthly PTI.';
COMMENT ON COLUMN feat_customer.app_credit_to_goods IS 'Credit amount / goods price. Above 1 = credit larger than the goods price.';
COMMENT ON COLUMN feat_customer.app_ext_source_1 IS 'Normalised external score 1 (Kaggle, source undisclosed).';
COMMENT ON COLUMN feat_customer.app_ext_source_2 IS 'Normalised external score 2 (Kaggle, source undisclosed).';
COMMENT ON COLUMN feat_customer.app_ext_source_3 IS 'Normalised external score 3 (Kaggle, source undisclosed).';
COMMENT ON COLUMN feat_customer.app_ext_source_mean IS 'Mean of the available external scores; NULL when none is available.';
COMMENT ON COLUMN feat_customer.app_region_rating IS 'Lender''s rating of the client''s region (1, 2, 3).';
COMMENT ON COLUMN feat_customer.app_documents_cnt IS 'Number of documents provided (sum of FLAG_DOCUMENT_2..21).';
COMMENT ON COLUMN feat_customer.app_bureau_enquiries_1y IS 'Credit bureau enquiries in the year before application.';
COMMENT ON COLUMN feat_customer.bur_has_history IS '1 when the client has at least one credit in the bureau.';
COMMENT ON COLUMN feat_customer.bur_credit_cnt IS 'Bureau credits, all statuses.';
COMMENT ON COLUMN feat_customer.bur_active_cnt IS 'Active bureau credits.';
COMMENT ON COLUMN feat_customer.bur_closed_cnt IS 'Closed bureau credits.';
COMMENT ON COLUMN feat_customer.bur_bad_status_cnt IS 'Bureau credits with status Sold or Bad debt (merged: Bad debt has only 21 rows).';
COMMENT ON COLUMN feat_customer.bur_active_credit_sum IS 'Sum of credit amounts of active bureau credits.';
COMMENT ON COLUMN feat_customer.bur_active_debt_sum IS 'Sum of current debt on active bureau credits.';
COMMENT ON COLUMN feat_customer.bur_active_overdue_sum IS 'Sum of amounts currently overdue on active bureau credits.';
COMMENT ON COLUMN feat_customer.bur_current_dpd_max IS 'Maximum days past due on any bureau credit at application.';
COMMENT ON COLUMN feat_customer.bur_max_overdue_amt_ever IS 'Largest amount ever overdue on any bureau credit.';
COMMENT ON COLUMN feat_customer.bur_prolong_cnt IS 'Number of prolongations over all bureau credits.';
COMMENT ON COLUMN feat_customer.bur_last_credit_days_ago IS 'Days between the most recent bureau credit application and this application.';
COMMENT ON COLUMN feat_customer.bur_new_credit_cnt_12m IS 'Bureau credits applied for in the 365 days before application.';
COMMENT ON COLUMN feat_customer.bur_annuity_known_sum IS 'Sum of annuities of active bureau credits where the annuity is reported (> 0). Reported for only 22.2% of active credits (decision 12).';
COMMENT ON COLUMN feat_customer.bur_annuity_known_cnt IS 'Active bureau credits with a reported annuity.';
COMMENT ON COLUMN feat_customer.bb_has_history IS '1 when monthly bureau status history exists for at least one credit (37.8% of clients).';
COMMENT ON COLUMN feat_customer.bb_worst_status_all IS 'Worst monthly bureau status ever: 0 = no DPD, 1 = 1-30, 2 = 31-60, 3 = 61-90, 4 = 91-120, 5 = 120+ or sold / written off.';
COMMENT ON COLUMN feat_customer.bb_worst_status_12m IS 'Worst monthly bureau status in the last 12 months (MONTHS_BALANCE 0 to -11; bureau data includes month 0). Same scale as bb_worst_status_all.';
COMMENT ON COLUMN feat_customer.bb_dpd_months_12m IS 'Credit-months with DPD (status 1-5) in the last 12 months (MONTHS_BALANCE 0 to -11), summed over bureau credits.';
COMMENT ON COLUMN feat_customer.prv_has_history IS '1 when the client has at least one previous application.';
COMMENT ON COLUMN feat_customer.prv_app_cnt IS 'Previous applications (last application per contract and per day only, decision 11).';
COMMENT ON COLUMN feat_customer.prv_approved_cnt IS 'Previous applications approved.';
COMMENT ON COLUMN feat_customer.prv_refused_cnt IS 'Previous applications refused.';
COMMENT ON COLUMN feat_customer.prv_canceled_cnt IS 'Previous applications cancelled.';
COMMENT ON COLUMN feat_customer.prv_refused_share IS 'Refused / all previous applications; NULL without history.';
COMMENT ON COLUMN feat_customer.prv_app_cnt_2y IS 'Previous applications decided in the 730 days before application.';
COMMENT ON COLUMN feat_customer.prv_refused_cnt_2y IS 'Previous applications refused in the 730 days before application.';
COMMENT ON COLUMN feat_customer.prv_last_decision_days_ago IS 'Days between the most recent previous decision and this application.';
COMMENT ON COLUMN feat_customer.prv_granted_to_asked_avg IS 'Average of granted / asked amount over approved applications (below 1 = client got less than asked).';
COMMENT ON COLUMN feat_customer.prv_approved_credit_sum IS 'Sum of credit amounts of approved previous applications.';
COMMENT ON COLUMN feat_customer.ins_has_history IS '1 when the client has instalment history on previous credits.';
COMMENT ON COLUMN feat_customer.ins_cnt_all IS 'Instalments due (after merging partial payments into one instalment, decision 10).';
COMMENT ON COLUMN feat_customer.ins_late_share_all IS 'Share of instalments whose last payment came after the due date.';
COMMENT ON COLUMN feat_customer.ins_days_late_max_all IS 'Maximum days between due date and last payment.';
COMMENT ON COLUMN feat_customer.ins_days_late_avg_all IS 'Average days late (early payment counts as 0).';
COMMENT ON COLUMN feat_customer.ins_underpaid_share_all IS 'Share of instalments where the total paid is below the amount due.';
COMMENT ON COLUMN feat_customer.ins_unpaid_cnt_all IS 'Instalments with no payment recorded.';
COMMENT ON COLUMN feat_customer.ins_cnt_12m IS 'Instalments due in the 365 days before application.';
COMMENT ON COLUMN feat_customer.ins_late_share_12m IS 'Share of instalments paid late, last 365 days.';
COMMENT ON COLUMN feat_customer.ins_days_late_max_12m IS 'Maximum days late, last 365 days.';
COMMENT ON COLUMN feat_customer.ins_underpaid_share_12m IS 'Share of instalments underpaid, last 365 days.';
COMMENT ON COLUMN feat_customer.pos_has_history IS '1 when the client has POS or cash loan balance history.';
COMMENT ON COLUMN feat_customer.pos_contract_cnt IS 'Previous POS / cash contracts.';
COMMENT ON COLUMN feat_customer.pos_active_cnt IS 'Contracts whose latest monthly status is Active.';
COMMENT ON COLUMN feat_customer.pos_instalments_left_sum IS 'Instalments left to pay on active contracts (latest month).';
COMMENT ON COLUMN feat_customer.pos_dpd_max_all IS 'Maximum days past due in any month.';
COMMENT ON COLUMN feat_customer.pos_dpd_def_max_all IS 'Maximum days past due with tolerance (small debts ignored), any month.';
COMMENT ON COLUMN feat_customer.pos_dpd_months_all IS 'Contract-months with DPD > 0.';
COMMENT ON COLUMN feat_customer.pos_dpd_max_12m IS 'Maximum days past due, last 12 months (MONTHS_BALANCE -1 to -12; the latest month in this source is -1).';
COMMENT ON COLUMN feat_customer.pos_dpd_months_12m IS 'Contract-months with DPD > 0, last 12 months.';
COMMENT ON COLUMN feat_customer.cc_has_history IS '1 when the client has credit card history.';
COMMENT ON COLUMN feat_customer.cc_card_cnt IS 'Previous credit cards.';
COMMENT ON COLUMN feat_customer.cc_util_avg_12m IS 'Average balance / limit, last 12 months.';
COMMENT ON COLUMN feat_customer.cc_util_max_12m IS 'Maximum balance / limit, last 12 months.';
COMMENT ON COLUMN feat_customer.cc_active_months_12m IS 'Months with any card spending in the last 12 months (0-12).';
COMMENT ON COLUMN feat_customer.cc_drawings_avg_12m IS 'Average monthly drawings, last 12 months.';
COMMENT ON COLUMN feat_customer.cc_pay_to_min_avg_12m IS 'Average total payment / minimum instalment, last 12 months (below 1 = paid less than the minimum).';
COMMENT ON COLUMN feat_customer.cc_dpd_max_all IS 'Maximum days past due on any card in any month.';
COMMENT ON COLUMN feat_customer.cc_dpd_months_12m IS 'Card-months with DPD > 0, last 12 months.';
COMMENT ON COLUMN feat_customer.bur_debt_to_income IS 'Active bureau debt / income (decision 12: reliable because debt is reported, unlike bureau annuities).';
COMMENT ON COLUMN feat_customer.bur_annuity_to_income IS 'Reported bureau annuities / income. Understates the burden: annuity is reported for only 22.2% of active credits.';
SET FEEDBACK ON
SET TIMING ON

-- Checks
EXEC p_dq_unique('FEAT_CUSTOMER')
EXEC p_dq_rowcount('FEAT_CUSTOMER', 356255)
EXEC p_dq('FEAT_CUSTOMER', 'train rows (307,511)', 'SELECT COUNT(*) FROM feat_customer WHERE dataset = ''train''', 307511)
EXEC p_dq('FEAT_CUSTOMER', 'train rows without target', 'SELECT COUNT(*) FROM feat_customer WHERE dataset = ''train'' AND target IS NULL', 0)
EXEC p_dq('FEAT_CUSTOMER', 'test rows with target', 'SELECT COUNT(*) FROM feat_customer WHERE dataset = ''test'' AND target IS NOT NULL', 0)

PROMPT feat_customer: done
