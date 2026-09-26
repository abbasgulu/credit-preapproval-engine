-- =====================================================================
-- 06_ref_feature_text.sql
-- Stage 4e: every fact the model uses, in plain words.
--
-- In plain words: when a client is declined because the estimated risk is
-- too high, the engine names the three facts that raised that risk most
-- (python\scripts\explain_decisions.py, SHAP). A column name such as
-- ins_late_share_12m means nothing to a client, so each of the 84 model
-- features has a sentence here, e.g.
--   "{value} of instalments in the last year were paid late"  -> "35% of ..."
--
--   unit          how the value is written: share (35%), amount (1,250,000),
--                 count / days (whole number), decimal1 / decimal2 / score,
--                 category (text as given), flag (yes/no: no value shown),
--                 dpd_status (bureau delay level 0-5 in words)
--   text_value    the sentence, with {value} where the client's value goes
--   text_zero     used instead when the value is 0 (for a flag: when it is 0)
--   text_missing  used when the value is unknown (no history, no data)
--
-- Texts are data, like the rules: a wording is improved by updating a row,
-- never by changing code. Re-running updates the texts to this file.
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE

DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM user_tables WHERE table_name = 'REF_FEATURE_TEXT';
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE TABLE ref_feature_text (
        feature_name  VARCHAR2(40)   NOT NULL,
        unit          VARCHAR2(12)   NOT NULL,
        short_label   VARCHAR2(60)   NOT NULL,
        text_value    VARCHAR2(200)  NOT NULL,
        text_zero     VARCHAR2(200),
        text_missing  VARCHAR2(200)  NOT NULL,
        updated_at    TIMESTAMP      NOT NULL,
        CONSTRAINT pk_ref_feature_text PRIMARY KEY (feature_name),
        CONSTRAINT ck_feature_text_unit CHECK (unit IN ('share', 'amount', 'count', 'days', 'decimal1',
                                                        'decimal2', 'score', 'category', 'flag', 'dpd_status')),
        CONSTRAINT ck_feature_text_value CHECK ((unit = 'flag' AND text_zero IS NOT NULL)
                                             OR (unit <> 'flag' AND INSTR(text_value, '{value}') > 0))
      )]';
    EXECUTE IMMEDIATE q'[COMMENT ON TABLE ref_feature_text IS 'Every model feature in plain words: the sentence used when a fact is named as a reason for a decision.']';
  END IF;
END;
/

MERGE INTO ref_feature_text t
USING (
  SELECT 'app_contract_type' AS feature_name, 'category' AS unit, 'Product applied for' AS short_label, 'Product applied for: {value}' AS text_value, CAST(NULL AS VARCHAR2(200)) AS text_zero, 'Product type not given' AS text_missing FROM dual UNION ALL
  SELECT 'app_income_type', 'category', 'Income type', 'Income type: {value}', CAST(NULL AS VARCHAR2(200)), 'Income type not given' FROM dual UNION ALL
  SELECT 'app_education', 'category', 'Education', 'Education: {value}', CAST(NULL AS VARCHAR2(200)), 'Education not given' FROM dual UNION ALL
  SELECT 'app_family_status', 'category', 'Family status', 'Family status: {value}', CAST(NULL AS VARCHAR2(200)), 'Family status not given' FROM dual UNION ALL
  SELECT 'app_children_cnt', 'count', 'Children', 'Number of children: {value}', 'No children', 'Number of children not given' FROM dual UNION ALL
  SELECT 'app_family_members_cnt', 'count', 'Family members', 'Family members: {value}', CAST(NULL AS VARCHAR2(200)), 'Number of family members not given' FROM dual UNION ALL
  SELECT 'app_employed_years', 'decimal1', 'Years in current job', 'In the current job for {value} years', CAST(NULL AS VARCHAR2(200)), 'Not currently employed (pensioner or unemployed)' FROM dual UNION ALL
  SELECT 'app_is_not_employed', 'flag', 'Not employed', 'Not currently employed (pensioner or unemployed)', 'Currently employed', 'Employment not given' FROM dual UNION ALL
  SELECT 'app_income_amt', 'amount', 'Income', 'Income: {value}', CAST(NULL AS VARCHAR2(200)), 'Income not given' FROM dual UNION ALL
  SELECT 'app_credit_amt', 'amount', 'Credit amount asked', 'Credit amount of this application: {value}', CAST(NULL AS VARCHAR2(200)), 'Credit amount not given' FROM dual UNION ALL
  SELECT 'app_annuity_amt', 'amount', 'Regular payment', 'Regular payment of this application: {value}', CAST(NULL AS VARCHAR2(200)), 'Regular payment not given' FROM dual UNION ALL
  SELECT 'app_goods_price_amt', 'amount', 'Price of goods', 'Price of the goods to be financed: {value}', CAST(NULL AS VARCHAR2(200)), 'No price of goods given' FROM dual UNION ALL
  SELECT 'app_credit_to_income', 'decimal2', 'Credit to income', 'Credit amount is {value} times the income', CAST(NULL AS VARCHAR2(200)), 'Credit to income not available' FROM dual UNION ALL
  SELECT 'app_annuity_to_income', 'share', 'Payment to income', 'Regular payment is {value} of the income', CAST(NULL AS VARCHAR2(200)), 'Payment to income not available' FROM dual UNION ALL
  SELECT 'app_credit_to_goods', 'decimal2', 'Credit to price of goods', 'Credit amount is {value} times the price of the goods', CAST(NULL AS VARCHAR2(200)), 'No price of goods given' FROM dual UNION ALL
  SELECT 'app_credit_term', 'count', 'Number of payments', 'The loan runs for about {value} regular payments', CAST(NULL AS VARCHAR2(200)), 'Loan term not available' FROM dual UNION ALL
  SELECT 'app_ext_source_1', 'score', 'External score 1', 'External credit score 1: {value} (0 = worst, 1 = best)', CAST(NULL AS VARCHAR2(200)), 'External credit score 1 not available' FROM dual UNION ALL
  SELECT 'app_ext_source_2', 'score', 'External score 2', 'External credit score 2: {value} (0 = worst, 1 = best)', CAST(NULL AS VARCHAR2(200)), 'External credit score 2 not available' FROM dual UNION ALL
  SELECT 'app_ext_source_3', 'score', 'External score 3', 'External credit score 3: {value} (0 = worst, 1 = best)', CAST(NULL AS VARCHAR2(200)), 'External credit score 3 not available' FROM dual UNION ALL
  SELECT 'app_ext_source_mean', 'score', 'Average external score', 'Average external credit score: {value} (0 = worst, 1 = best)', CAST(NULL AS VARCHAR2(200)), 'No external credit score available' FROM dual UNION ALL
  SELECT 'app_region_rating', 'count', 'Region rating', 'Region rating: {value} (1 = best, 3 = worst)', CAST(NULL AS VARCHAR2(200)), 'Region rating not available' FROM dual UNION ALL
  SELECT 'app_documents_cnt', 'count', 'Documents provided', 'Documents provided: {value}', 'No documents provided', 'Documents not recorded' FROM dual UNION ALL
  SELECT 'app_bureau_enquiries_1y', 'count', 'Credit enquiries, last year', 'Credit enquiries at the credit bureau in the last year: {value}', 'No credit enquiries in the last year', 'No credit enquiry data' FROM dual UNION ALL
  SELECT 'bur_has_history', 'flag', 'Credit history elsewhere', 'Has credit history at other lenders', 'No credit history at other lenders', 'No credit history at other lenders' FROM dual UNION ALL
  SELECT 'bur_credit_cnt', 'count', 'Credits elsewhere', 'Credits at other lenders, all time: {value}', 'No credit history at other lenders', 'No credit history at other lenders' FROM dual UNION ALL
  SELECT 'bur_active_cnt', 'count', 'Active credits elsewhere', 'Active credits at other lenders: {value}', 'No active credits at other lenders', 'No credit history at other lenders' FROM dual UNION ALL
  SELECT 'bur_closed_cnt', 'count', 'Repaid credits elsewhere', 'Fully repaid credits at other lenders: {value}', 'No fully repaid credits at other lenders', 'No credit history at other lenders' FROM dual UNION ALL
  SELECT 'bur_bad_status_cnt', 'count', 'Written-off credits elsewhere', 'Credits written off or sold at other lenders: {value}', 'No written-off credits at other lenders', 'No credit history at other lenders' FROM dual UNION ALL
  SELECT 'bur_active_credit_sum', 'amount', 'Active credit elsewhere', 'Total of active credits at other lenders: {value}', 'No active credit at other lenders', 'No credit history at other lenders' FROM dual UNION ALL
  SELECT 'bur_active_debt_sum', 'amount', 'Debt elsewhere', 'Current debt at other lenders: {value}', 'No current debt at other lenders', 'No credit history at other lenders' FROM dual UNION ALL
  SELECT 'bur_active_overdue_sum', 'amount', 'Overdue amount elsewhere', 'Amount currently overdue at other lenders: {value}', 'Nothing currently overdue at other lenders', 'No credit history at other lenders' FROM dual UNION ALL
  SELECT 'bur_current_dpd_max', 'days', 'Current delay elsewhere', 'Currently {value} days late on a payment at another lender', 'Not currently late at other lenders', 'No credit history at other lenders' FROM dual UNION ALL
  SELECT 'bur_max_overdue_amt_ever', 'amount', 'Largest overdue elsewhere', 'Largest amount ever overdue at other lenders: {value}', 'Never had an overdue amount at other lenders', 'No overdue history reported by other lenders' FROM dual UNION ALL
  SELECT 'bur_prolong_cnt', 'count', 'Extended credits elsewhere', 'Credits extended (prolonged) at other lenders: {value}', 'No credit extensions at other lenders', 'No credit history at other lenders' FROM dual UNION ALL
  SELECT 'bur_last_credit_days_ago', 'days', 'Days since last credit elsewhere', 'Last applied for credit at another lender {value} days ago', CAST(NULL AS VARCHAR2(200)), 'No credit history at other lenders' FROM dual UNION ALL
  SELECT 'bur_new_credit_cnt_12m', 'count', 'New credits elsewhere, last year', 'New credits at other lenders in the last year: {value}', 'No new credits at other lenders in the last year', 'No credit history at other lenders' FROM dual UNION ALL
  SELECT 'bur_annuity_known_sum', 'amount', 'Payments reported elsewhere', 'Regular payments reported by other lenders: {value}', 'No regular payments reported by other lenders', 'No credit history at other lenders' FROM dual UNION ALL
  SELECT 'bur_annuity_known_cnt', 'count', 'Credits with a reported payment', 'Active credits at other lenders with a reported payment: {value}', 'No active credit at other lenders reports a payment', 'No credit history at other lenders' FROM dual UNION ALL
  SELECT 'bb_has_history', 'flag', 'Monthly history elsewhere', 'Monthly payment history at other lenders is available', 'No monthly payment history at other lenders', 'No monthly payment history at other lenders' FROM dual UNION ALL
  SELECT 'bb_worst_status_all', 'dpd_status', 'Worst delay elsewhere, ever', 'Worst payment delay ever at other lenders: {value}', CAST(NULL AS VARCHAR2(200)), 'No monthly payment history at other lenders' FROM dual UNION ALL
  SELECT 'bb_worst_status_12m', 'dpd_status', 'Worst delay elsewhere, last year', 'Worst payment delay at other lenders in the last year: {value}', CAST(NULL AS VARCHAR2(200)), 'No monthly payment history at other lenders in the last year' FROM dual UNION ALL
  SELECT 'bb_dpd_months_12m', 'count', 'Late months elsewhere, last year', 'Months with a late payment at other lenders in the last year: {value}', 'No late months at other lenders in the last year', 'No monthly payment history at other lenders' FROM dual UNION ALL
  SELECT 'prv_has_history', 'flag', 'Has applied here before', 'Has applied here before', 'No earlier applications here', 'No earlier applications here' FROM dual UNION ALL
  SELECT 'prv_app_cnt', 'count', 'Number of earlier applications', 'Earlier applications here: {value}', 'No earlier applications here', 'No earlier applications here' FROM dual UNION ALL
  SELECT 'prv_approved_cnt', 'count', 'Earlier approvals', 'Earlier applications approved: {value}', 'No earlier application was approved', 'No earlier applications here' FROM dual UNION ALL
  SELECT 'prv_refused_cnt', 'count', 'Earlier refusals', 'Earlier applications refused: {value}', 'No earlier application was refused', 'No earlier applications here' FROM dual UNION ALL
  SELECT 'prv_canceled_cnt', 'count', 'Earlier cancellations', 'Earlier applications cancelled: {value}', 'No earlier application was cancelled', 'No earlier applications here' FROM dual UNION ALL
  SELECT 'prv_refused_share', 'share', 'Share of earlier applications refused', '{value} of earlier applications were refused', 'No earlier application was refused', 'No earlier applications here' FROM dual UNION ALL
  SELECT 'prv_app_cnt_2y', 'count', 'Applications, last two years', 'Applications here in the last two years: {value}', 'No applications here in the last two years', 'No earlier applications here' FROM dual UNION ALL
  SELECT 'prv_refused_cnt_2y', 'count', 'Refusals, last two years', 'Applications refused in the last two years: {value}', 'No refusals in the last two years', 'No earlier applications here' FROM dual UNION ALL
  SELECT 'prv_last_decision_days_ago', 'days', 'Days since last application', 'The last earlier application was decided {value} days ago', CAST(NULL AS VARCHAR2(200)), 'No earlier applications here' FROM dual UNION ALL
  SELECT 'prv_granted_to_asked_avg', 'share', 'Granted versus asked', 'On earlier approvals, received on average {value} of the amount asked', CAST(NULL AS VARCHAR2(200)), 'No earlier approved application' FROM dual UNION ALL
  SELECT 'prv_approved_credit_sum', 'amount', 'Earlier approved credit', 'Total of earlier approved credits: {value}', 'No earlier approved credit', 'No earlier applications here' FROM dual UNION ALL
  SELECT 'ins_has_history', 'flag', 'Repayment history', 'Has repayment history on earlier loans', 'No repayment history on earlier loans', 'No repayment history on earlier loans' FROM dual UNION ALL
  SELECT 'ins_cnt_all', 'count', 'Earlier instalments', 'Instalments due on earlier loans: {value}', 'No repayment history on earlier loans', 'No repayment history on earlier loans' FROM dual UNION ALL
  SELECT 'ins_late_share_all', 'share', 'Instalments paid late', '{value} of instalments on earlier loans were paid late', 'No instalment on earlier loans was paid late', 'No repayment history on earlier loans' FROM dual UNION ALL
  SELECT 'ins_days_late_max_all', 'days', 'Longest instalment delay', 'Longest delay on an earlier instalment: {value} days', 'Never paid an earlier instalment late', 'No repayment history on earlier loans' FROM dual UNION ALL
  SELECT 'ins_days_late_avg_all', 'decimal1', 'Average instalment delay', 'Average delay on earlier instalments: {value} days', 'Never paid an earlier instalment late', 'No repayment history on earlier loans' FROM dual UNION ALL
  SELECT 'ins_underpaid_share_all', 'share', 'Instalments underpaid', '{value} of instalments on earlier loans were paid less than due', 'No earlier instalment was paid less than due', 'No repayment history on earlier loans' FROM dual UNION ALL
  SELECT 'ins_unpaid_cnt_all', 'count', 'Unpaid instalments', 'Instalments on earlier loans with no payment: {value}', 'No unpaid instalments on earlier loans', 'No repayment history on earlier loans' FROM dual UNION ALL
  SELECT 'ins_cnt_12m', 'count', 'Instalments, last year', 'Instalments due in the last year: {value}', 'No instalments due in the last year', 'No instalments due in the last year' FROM dual UNION ALL
  SELECT 'ins_late_share_12m', 'share', 'Paid late, last year', '{value} of instalments in the last year were paid late', 'No instalment was paid late in the last year', 'No instalments due in the last year' FROM dual UNION ALL
  SELECT 'ins_days_late_max_12m', 'days', 'Longest delay, last year', 'Longest delay on an instalment in the last year: {value} days', 'No instalment was paid late in the last year', 'No instalments due in the last year' FROM dual UNION ALL
  SELECT 'ins_underpaid_share_12m', 'share', 'Underpaid, last year', '{value} of instalments in the last year were paid less than due', 'No instalment was paid less than due in the last year', 'No instalments due in the last year' FROM dual UNION ALL
  SELECT 'pos_has_history', 'flag', 'Has earlier consumer loans', 'Has earlier consumer or cash loans here', 'No earlier consumer or cash loans here', 'No earlier consumer or cash loans here' FROM dual UNION ALL
  SELECT 'pos_contract_cnt', 'count', 'Number of earlier consumer loans', 'Earlier consumer or cash loans here: {value}', 'No earlier consumer or cash loans here', 'No earlier consumer or cash loans here' FROM dual UNION ALL
  SELECT 'pos_active_cnt', 'count', 'Active consumer loans', 'Consumer or cash loans still active: {value}', 'No consumer or cash loans still active', 'No earlier consumer or cash loans here' FROM dual UNION ALL
  SELECT 'pos_instalments_left_sum', 'count', 'Instalments still to pay', 'Instalments still to pay on active loans: {value}', 'No instalments left to pay on active loans', 'No earlier consumer or cash loans here' FROM dual UNION ALL
  SELECT 'pos_dpd_max_all', 'days', 'Longest delay, consumer loans', 'Longest delay on earlier consumer or cash loans: {value} days', 'Never late on earlier consumer or cash loans', 'No earlier consumer or cash loans here' FROM dual UNION ALL
  SELECT 'pos_dpd_def_max_all', 'days', 'Longest delay on a real amount', 'Longest delay on a non-trivial amount, consumer or cash loans: {value} days', 'Never late on a non-trivial amount', 'No earlier consumer or cash loans here' FROM dual UNION ALL
  SELECT 'pos_dpd_months_all', 'count', 'Late months, consumer loans', 'Months late on earlier consumer or cash loans: {value}', 'No late months on earlier consumer or cash loans', 'No earlier consumer or cash loans here' FROM dual UNION ALL
  SELECT 'pos_dpd_max_12m', 'days', 'Longest delay, consumer loans, last year', 'Longest delay on consumer or cash loans in the last year: {value} days', 'Not late on consumer or cash loans in the last year', 'No consumer or cash loan activity in the last year' FROM dual UNION ALL
  SELECT 'pos_dpd_months_12m', 'count', 'Late months, consumer loans, last year', 'Months late on consumer or cash loans in the last year: {value}', 'No late months on consumer or cash loans in the last year', 'No consumer or cash loan activity in the last year' FROM dual UNION ALL
  SELECT 'cc_has_history', 'flag', 'Credit card history', 'Has had a credit card here', 'No credit card history here', 'No credit card history here' FROM dual UNION ALL
  SELECT 'cc_card_cnt', 'count', 'Credit cards', 'Credit cards held here: {value}', 'No credit card history here', 'No credit card history here' FROM dual UNION ALL
  SELECT 'cc_util_avg_12m', 'share', 'Card use, average', 'Credit card balance in the last year: on average {value} of the limit', 'Credit card not used in the last year', 'No credit card activity in the last year' FROM dual UNION ALL
  SELECT 'cc_util_max_12m', 'share', 'Card use, highest', 'Highest credit card balance in the last year: {value} of the limit', 'Credit card not used in the last year', 'No credit card activity in the last year' FROM dual UNION ALL
  SELECT 'cc_active_months_12m', 'count', 'Months with card spending', 'Months with credit card spending in the last year: {value}', 'No credit card spending in the last year', 'No credit card activity in the last year' FROM dual UNION ALL
  SELECT 'cc_drawings_avg_12m', 'amount', 'Card spending', 'Average monthly credit card spending in the last year: {value}', 'No credit card spending in the last year', 'No credit card activity in the last year' FROM dual UNION ALL
  SELECT 'cc_pay_to_min_avg_12m', 'decimal2', 'Card payments versus minimum', 'Credit card payments were on average {value} times the minimum due', 'No credit card payments made against a minimum due', 'No credit card payments due in the last year' FROM dual UNION ALL
  SELECT 'cc_dpd_max_all', 'days', 'Longest card delay', 'Longest delay on a credit card payment: {value} days', 'Never late on a credit card', 'No credit card history here' FROM dual UNION ALL
  SELECT 'cc_dpd_months_12m', 'count', 'Late card months, last year', 'Months late on a credit card in the last year: {value}', 'No late months on a credit card in the last year', 'No credit card activity in the last year' FROM dual UNION ALL
  SELECT 'bur_debt_to_income', 'decimal2', 'Debt elsewhere to income', 'Debt at other lenders is {value} times the income', 'No debt at other lenders', 'No credit history at other lenders' FROM dual UNION ALL
  SELECT 'bur_annuity_to_income', 'share', 'Payments elsewhere to income', 'Payments reported by other lenders are {value} of the income', 'No payments reported by other lenders', 'No credit history at other lenders' FROM dual
) s
ON (t.feature_name = RTRIM(s.feature_name))
WHEN MATCHED THEN UPDATE SET t.unit = RTRIM(s.unit), t.short_label = RTRIM(s.short_label),
     t.text_value = RTRIM(s.text_value), t.text_zero = RTRIM(s.text_zero),
     t.text_missing = RTRIM(s.text_missing), t.updated_at = SYSTIMESTAMP
WHEN NOT MATCHED THEN INSERT (feature_name, unit, short_label, text_value, text_zero, text_missing, updated_at)
     VALUES (RTRIM(s.feature_name), RTRIM(s.unit), RTRIM(s.short_label), RTRIM(s.text_value),
             RTRIM(s.text_zero), RTRIM(s.text_missing), SYSTIMESTAMP);
COMMIT;

EXEC p_dq('REF_FEATURE_TEXT', 'every text belongs to a real column of feat_customer', 'SELECT COUNT(*) FROM ref_feature_text t WHERE NOT EXISTS (SELECT 1 FROM user_tab_columns c WHERE c.table_name = ''FEAT_CUSTOMER'' AND c.column_name = UPPER(t.feature_name))', 0)
EXEC p_dq('REF_FEATURE_TEXT', 'texts for all 84 model features', 'SELECT COUNT(*) FROM ref_feature_text', 84)

PROMPT 06_ref_feature_text: done
