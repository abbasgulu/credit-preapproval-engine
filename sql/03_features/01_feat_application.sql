-- =====================================================================
-- 01_feat_application.sql
-- Features of the current application. One row per client. Source: raw_application_train + raw_application_test.
--
-- Every client of v_population gets exactly one row; clients without
-- history get 0 for counts / flags and NULL for amounts and ratios.
-- Checked right after creation (improvement 6).
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
ALTER SESSION SET NLS_NUMERIC_CHARACTERS = '.,';

PROMPT
PROMPT ===== feat_application =====
EXEC p_drop_if_exists('FEAT_APPLICATION')
CREATE TABLE feat_application AS
WITH agg AS (
  SELECT
    sk_id_curr,
    name_contract_type                                   AS app_contract_type,
    name_income_type                                     AS app_income_type,
    name_education_type                                  AS app_education,
    name_family_status                                   AS app_family_status,
    cnt_children                                         AS app_children_cnt,
    cnt_fam_members                                      AS app_family_members_cnt,
    ROUND(-days_birth / 365.25, 2)                       AS app_age_years,
    CASE WHEN days_employed = 365243 THEN NULL
         ELSE ROUND(-days_employed / 365.25, 2) END      AS app_employed_years,
    CASE WHEN days_employed = 365243 THEN 1 ELSE 0 END   AS app_is_not_employed,
    amt_income_total                                     AS app_income_amt,
    amt_credit                                           AS app_credit_amt,
    amt_annuity                                          AS app_annuity_amt,
    amt_goods_price                                      AS app_goods_price_amt,
    amt_credit  / NULLIF(amt_income_total, 0)            AS app_credit_to_income,
    amt_annuity / NULLIF(amt_income_total, 0)            AS app_annuity_to_income,
    amt_credit  / NULLIF(amt_goods_price, 0)             AS app_credit_to_goods,
    amt_credit  / NULLIF(amt_annuity, 0)                 AS app_credit_term,
    ext_source_1                                         AS app_ext_source_1,
    ext_source_2                                         AS app_ext_source_2,
    ext_source_3                                         AS app_ext_source_3,
    (NVL(ext_source_1, 0) + NVL(ext_source_2, 0) + NVL(ext_source_3, 0))
      / NULLIF(NVL2(ext_source_1, 1, 0) + NVL2(ext_source_2, 1, 0) + NVL2(ext_source_3, 1, 0), 0)
                                                         AS app_ext_source_mean,
    region_rating_client                                 AS app_region_rating,
    doc_cnt                                              AS app_documents_cnt,
    amt_req_credit_bureau_year                           AS app_bureau_enquiries_1y
  FROM (
    SELECT sk_id_curr, name_contract_type, name_income_type, name_education_type, name_family_status, cnt_children, cnt_fam_members, amt_income_total, amt_credit, amt_annuity, amt_goods_price, days_birth, days_employed, ext_source_1, ext_source_2, ext_source_3, region_rating_client, amt_req_credit_bureau_year, flag_document_2 + flag_document_3 + flag_document_4 + flag_document_5 + flag_document_6 + flag_document_7 + flag_document_8 + flag_document_9 + flag_document_10 + flag_document_11 + flag_document_12 + flag_document_13 + flag_document_14 + flag_document_15 + flag_document_16 + flag_document_17 + flag_document_18 + flag_document_19 + flag_document_20 + flag_document_21 AS doc_cnt FROM raw_application_train
    UNION ALL
    SELECT sk_id_curr, name_contract_type, name_income_type, name_education_type, name_family_status, cnt_children, cnt_fam_members, amt_income_total, amt_credit, amt_annuity, amt_goods_price, days_birth, days_employed, ext_source_1, ext_source_2, ext_source_3, region_rating_client, amt_req_credit_bureau_year, flag_document_2 + flag_document_3 + flag_document_4 + flag_document_5 + flag_document_6 + flag_document_7 + flag_document_8 + flag_document_9 + flag_document_10 + flag_document_11 + flag_document_12 + flag_document_13 + flag_document_14 + flag_document_15 + flag_document_16 + flag_document_17 + flag_document_18 + flag_document_19 + flag_document_20 + flag_document_21 AS doc_cnt FROM raw_application_test
  )
)
SELECT
  p.sk_id_curr,
  a.app_contract_type,
  a.app_income_type,
  a.app_education,
  a.app_family_status,
  a.app_children_cnt,
  a.app_family_members_cnt,
  a.app_age_years,
  a.app_employed_years,
  a.app_is_not_employed,
  a.app_income_amt,
  a.app_credit_amt,
  a.app_annuity_amt,
  a.app_goods_price_amt,
  a.app_credit_to_income,
  a.app_annuity_to_income,
  a.app_credit_to_goods,
  a.app_credit_term,
  a.app_ext_source_1,
  a.app_ext_source_2,
  a.app_ext_source_3,
  a.app_ext_source_mean,
  a.app_region_rating,
  a.app_documents_cnt,
  a.app_bureau_enquiries_1y
FROM   v_population p
LEFT   JOIN agg a ON a.sk_id_curr = p.sk_id_curr;

-- Column comments (quiet: ~20 lines of 'Comment created.' are not useful)
SET FEEDBACK OFF
SET TIMING OFF
COMMENT ON TABLE feat_application IS 'Features of the current application. One row per client. Source: raw_application_train + raw_application_test.';
COMMENT ON COLUMN feat_application.sk_id_curr IS 'Client / application ID. Unique in this table.';
COMMENT ON COLUMN feat_application.app_contract_type IS 'Product of the current application: Cash loans or Revolving loans.';
COMMENT ON COLUMN feat_application.app_income_type IS 'Income type of the client (Working, Pensioner, ...).';
COMMENT ON COLUMN feat_application.app_education IS 'Highest education level.';
COMMENT ON COLUMN feat_application.app_family_status IS 'Family status.';
COMMENT ON COLUMN feat_application.app_children_cnt IS 'Number of children.';
COMMENT ON COLUMN feat_application.app_family_members_cnt IS 'Number of family members.';
COMMENT ON COLUMN feat_application.app_age_years IS 'Age at application, in years (from DAYS_BIRTH).';
COMMENT ON COLUMN feat_application.app_employed_years IS 'Length of current employment in years. NULL when DAYS_EMPLOYED = 365243 (not employed, decision 9).';
COMMENT ON COLUMN feat_application.app_is_not_employed IS '1 when DAYS_EMPLOYED = 365243: pensioners and unemployed (decision 9).';
COMMENT ON COLUMN feat_application.app_income_amt IS 'Income of the client (AMT_INCOME_TOTAL, as given by Kaggle).';
COMMENT ON COLUMN feat_application.app_credit_amt IS 'Credit amount of the current application.';
COMMENT ON COLUMN feat_application.app_annuity_amt IS 'Annuity of the current application (AMT_ANNUITY).';
COMMENT ON COLUMN feat_application.app_goods_price_amt IS 'Price of the goods financed (consumer loans).';
COMMENT ON COLUMN feat_application.app_credit_to_income IS 'Credit amount / income.';
COMMENT ON COLUMN feat_application.app_annuity_to_income IS 'AMT_ANNUITY / AMT_INCOME_TOTAL as given. Kaggle does not document the period of either amount, so this is a relative burden measure, not a monthly PTI.';
COMMENT ON COLUMN feat_application.app_credit_to_goods IS 'Credit amount / goods price. Above 1 = credit larger than the goods price.';
COMMENT ON COLUMN feat_application.app_credit_term IS 'Credit amount / annuity: how many annuity payments repay the credit, i.e. the loan''s effective term (decision 22). Kaggle does not state the payment period.';
COMMENT ON COLUMN feat_application.app_ext_source_1 IS 'Normalised external score 1 (Kaggle, source undisclosed).';
COMMENT ON COLUMN feat_application.app_ext_source_2 IS 'Normalised external score 2 (Kaggle, source undisclosed).';
COMMENT ON COLUMN feat_application.app_ext_source_3 IS 'Normalised external score 3 (Kaggle, source undisclosed).';
COMMENT ON COLUMN feat_application.app_ext_source_mean IS 'Mean of the available external scores; NULL when none is available.';
COMMENT ON COLUMN feat_application.app_region_rating IS 'Lender''s rating of the client''s region (1, 2, 3).';
COMMENT ON COLUMN feat_application.app_documents_cnt IS 'Number of documents provided (sum of FLAG_DOCUMENT_2..21).';
COMMENT ON COLUMN feat_application.app_bureau_enquiries_1y IS 'Credit bureau enquiries in the year before application.';
SET FEEDBACK ON
SET TIMING ON

-- Checks
EXEC p_dq_unique('FEAT_APPLICATION')
EXEC p_dq_rowcount('FEAT_APPLICATION', 356255)
EXEC p_dq_range('FEAT_APPLICATION', 'APP_AGE_YEARS', 18, 100)
EXEC p_dq_range('FEAT_APPLICATION', 'APP_IS_NOT_EMPLOYED', 0, 1)
EXEC p_dq_range('FEAT_APPLICATION', 'APP_EXT_SOURCE_MEAN', 0, 1)
EXEC p_dq_range('FEAT_APPLICATION', 'APP_CREDIT_TERM', 1, 1000)
EXEC p_dq('FEAT_APPLICATION', 'not-employed flag = 365243 count (train+test)', 'SELECT COUNT(*) FROM feat_application WHERE app_is_not_employed = 1', 64648)

PROMPT feat_application: done
