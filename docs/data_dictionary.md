# Data dictionary

_Generated from Oracle column comments by `sql/99_checks/04_data_dictionary.sql` on 2026-09-25. Do not edit by hand._

## `feat_application`

Features of the current application. One row per client. Source: raw_application_train + raw_application_test.

| # | Column | Type | Description |
|---:|---|---|---|
| 1 | `sk_id_curr` | NUMBER | Client / application ID. Unique in this table. |
| 2 | `app_contract_type` | VARCHAR2 | Product of the current application: Cash loans or Revolving loans. |
| 3 | `app_income_type` | VARCHAR2 | Income type of the client (Working, Pensioner, ...). |
| 4 | `app_education` | VARCHAR2 | Highest education level. |
| 5 | `app_family_status` | VARCHAR2 | Family status. |
| 6 | `app_children_cnt` | NUMBER | Number of children. |
| 7 | `app_family_members_cnt` | NUMBER | Number of family members. |
| 8 | `app_age_years` | NUMBER | Age at application, in years (from DAYS_BIRTH). |
| 9 | `app_employed_years` | NUMBER | Length of current employment in years. NULL when DAYS_EMPLOYED = 365243 (not employed, decision 9). |
| 10 | `app_is_not_employed` | NUMBER | 1 when DAYS_EMPLOYED = 365243: pensioners and unemployed (decision 9). |
| 11 | `app_income_amt` | NUMBER | Income of the client (AMT_INCOME_TOTAL, as given by Kaggle). |
| 12 | `app_credit_amt` | NUMBER | Credit amount of the current application. |
| 13 | `app_annuity_amt` | NUMBER | Annuity of the current application (AMT_ANNUITY). |
| 14 | `app_goods_price_amt` | NUMBER | Price of the goods financed (consumer loans). |
| 15 | `app_credit_to_income` | NUMBER | Credit amount / income. |
| 16 | `app_annuity_to_income` | NUMBER | AMT_ANNUITY / AMT_INCOME_TOTAL as given. Kaggle does not document the period of either amount, so this is a relative burden measure, not a monthly PTI. |
| 17 | `app_credit_to_goods` | NUMBER | Credit amount / goods price. Above 1 = credit larger than the goods price. |
| 18 | `app_ext_source_1` | NUMBER | Normalised external score 1 (Kaggle, source undisclosed). |
| 19 | `app_ext_source_2` | NUMBER | Normalised external score 2 (Kaggle, source undisclosed). |
| 20 | `app_ext_source_3` | NUMBER | Normalised external score 3 (Kaggle, source undisclosed). |
| 21 | `app_ext_source_mean` | NUMBER | Mean of the available external scores; NULL when none is available. |
| 22 | `app_region_rating` | NUMBER | Lender's rating of the client's region (1, 2, 3). |
| 23 | `app_documents_cnt` | NUMBER | Number of documents provided (sum of FLAG_DOCUMENT_2..21). |
| 24 | `app_bureau_enquiries_1y` | NUMBER | Credit bureau enquiries in the year before application. |

## `feat_bureau`

Credits at other lenders (credit bureau). One row per client. Source: raw_bureau + raw_bureau_balance, aggregated in two steps (per credit, then per client).

| # | Column | Type | Description |
|---:|---|---|---|
| 1 | `sk_id_curr` | NUMBER | Client / application ID. Unique in this table. |
| 2 | `bur_has_history` | NUMBER | 1 when the client has at least one credit in the bureau. |
| 3 | `bur_credit_cnt` | NUMBER | Bureau credits, all statuses. |
| 4 | `bur_active_cnt` | NUMBER | Active bureau credits. |
| 5 | `bur_closed_cnt` | NUMBER | Closed bureau credits. |
| 6 | `bur_bad_status_cnt` | NUMBER | Bureau credits with status Sold or Bad debt (merged: Bad debt has only 21 rows). |
| 7 | `bur_active_credit_sum` | NUMBER | Sum of credit amounts of active bureau credits. |
| 8 | `bur_active_debt_sum` | NUMBER | Sum of current debt on active bureau credits. |
| 9 | `bur_active_overdue_sum` | NUMBER | Sum of amounts currently overdue on active bureau credits. |
| 10 | `bur_current_dpd_max` | NUMBER | Maximum days past due on any bureau credit at application. |
| 11 | `bur_max_overdue_amt_ever` | NUMBER | Largest amount ever overdue on any bureau credit. |
| 12 | `bur_prolong_cnt` | NUMBER | Number of prolongations over all bureau credits. |
| 13 | `bur_last_credit_days_ago` | NUMBER | Days between the most recent bureau credit application and this application. |
| 14 | `bur_new_credit_cnt_12m` | NUMBER | Bureau credits applied for in the 365 days before application. |
| 15 | `bur_annuity_known_sum` | NUMBER | Sum of annuities of active bureau credits where the annuity is reported (> 0). Reported for only 22.2% of active credits (decision 12). |
| 16 | `bur_annuity_known_cnt` | NUMBER | Active bureau credits with a reported annuity. |
| 17 | `bb_has_history` | NUMBER | 1 when monthly bureau status history exists for at least one credit (37.8% of clients). |
| 18 | `bb_worst_status_all` | NUMBER | Worst monthly bureau status ever: 0 = no DPD, 1 = 1-30, 2 = 31-60, 3 = 61-90, 4 = 91-120, 5 = 120+ or sold / written off. |
| 19 | `bb_worst_status_12m` | NUMBER | Worst monthly bureau status in the last 12 months (MONTHS_BALANCE 0 to -11; bureau data includes month 0). Same scale as bb_worst_status_all. |
| 20 | `bb_dpd_months_12m` | NUMBER | Credit-months with DPD (status 1-5) in the last 12 months (MONTHS_BALANCE 0 to -11), summed over bureau credits. |

## `feat_previous`

Previous applications at the same lender. One row per client. Repeated applications removed with Kaggle's own flags (decision 11).

| # | Column | Type | Description |
|---:|---|---|---|
| 1 | `sk_id_curr` | NUMBER | Client / application ID. Unique in this table. |
| 2 | `prv_has_history` | NUMBER | 1 when the client has at least one previous application. |
| 3 | `prv_app_cnt` | NUMBER | Previous applications (last application per contract and per day only, decision 11). |
| 4 | `prv_approved_cnt` | NUMBER | Previous applications approved. |
| 5 | `prv_refused_cnt` | NUMBER | Previous applications refused. |
| 6 | `prv_canceled_cnt` | NUMBER | Previous applications cancelled. |
| 7 | `prv_refused_share` | NUMBER | Refused / all previous applications; NULL without history. |
| 8 | `prv_app_cnt_2y` | NUMBER | Previous applications decided in the 730 days before application. |
| 9 | `prv_refused_cnt_2y` | NUMBER | Previous applications refused in the 730 days before application. |
| 10 | `prv_last_decision_days_ago` | NUMBER | Days between the most recent previous decision and this application. |
| 11 | `prv_granted_to_asked_avg` | NUMBER | Average of granted / asked amount over approved applications (below 1 = client got less than asked). |
| 12 | `prv_approved_credit_sum` | NUMBER | Sum of credit amounts of approved previous applications. |

## `feat_installments`

Repayment discipline on previous credits. One row per client. Aggregated in two steps: payment rows -> instalment -> client (decision 10).

| # | Column | Type | Description |
|---:|---|---|---|
| 1 | `sk_id_curr` | NUMBER | Client / application ID. Unique in this table. |
| 2 | `ins_has_history` | NUMBER | 1 when the client has instalment history on previous credits. |
| 3 | `ins_cnt_all` | NUMBER | Instalments due (after merging partial payments into one instalment, decision 10). |
| 4 | `ins_late_share_all` | NUMBER | Share of instalments whose last payment came after the due date. |
| 5 | `ins_days_late_max_all` | NUMBER | Maximum days between due date and last payment. |
| 6 | `ins_days_late_avg_all` | NUMBER | Average days late (early payment counts as 0). |
| 7 | `ins_underpaid_share_all` | NUMBER | Share of instalments where the total paid is below the amount due. |
| 8 | `ins_unpaid_cnt_all` | NUMBER | Instalments with no payment recorded. |
| 9 | `ins_cnt_12m` | NUMBER | Instalments due in the 365 days before application. |
| 10 | `ins_late_share_12m` | NUMBER | Share of instalments paid late, last 365 days. |
| 11 | `ins_days_late_max_12m` | NUMBER | Maximum days late, last 365 days. |
| 12 | `ins_underpaid_share_12m` | NUMBER | Share of instalments underpaid, last 365 days. |

## `feat_pos_cash`

Monthly balances of previous POS and cash loans. One row per client.

| # | Column | Type | Description |
|---:|---|---|---|
| 1 | `sk_id_curr` | NUMBER | Client / application ID. Unique in this table. |
| 2 | `pos_has_history` | NUMBER | 1 when the client has POS or cash loan balance history. |
| 3 | `pos_contract_cnt` | NUMBER | Previous POS / cash contracts. |
| 4 | `pos_active_cnt` | NUMBER | Contracts whose latest monthly status is Active. |
| 5 | `pos_instalments_left_sum` | NUMBER | Instalments left to pay on active contracts (latest month). |
| 6 | `pos_dpd_max_all` | NUMBER | Maximum days past due in any month. |
| 7 | `pos_dpd_def_max_all` | NUMBER | Maximum days past due with tolerance (small debts ignored), any month. |
| 8 | `pos_dpd_months_all` | NUMBER | Contract-months with DPD > 0. |
| 9 | `pos_dpd_max_12m` | NUMBER | Maximum days past due, last 12 months (MONTHS_BALANCE -1 to -12; the latest month in this source is -1). |
| 10 | `pos_dpd_months_12m` | NUMBER | Contract-months with DPD > 0, last 12 months. |

## `feat_credit_card`

Monthly balances of previous credit cards. One row per client. Only 29.1% of clients have card history.

| # | Column | Type | Description |
|---:|---|---|---|
| 1 | `sk_id_curr` | NUMBER | Client / application ID. Unique in this table. |
| 2 | `cc_has_history` | NUMBER | 1 when the client has credit card history. |
| 3 | `cc_card_cnt` | NUMBER | Previous credit cards. |
| 4 | `cc_util_avg_12m` | NUMBER | Average balance / limit, last 12 months. |
| 5 | `cc_util_max_12m` | NUMBER | Maximum balance / limit, last 12 months. |
| 6 | `cc_active_months_12m` | NUMBER | Months with any card spending in the last 12 months (0-12). |
| 7 | `cc_drawings_avg_12m` | NUMBER | Average monthly drawings, last 12 months. |
| 8 | `cc_pay_to_min_avg_12m` | NUMBER | Average total payment / minimum instalment, last 12 months (below 1 = paid less than the minimum). |
| 9 | `cc_dpd_max_all` | NUMBER | Maximum days past due on any card in any month. |
| 10 | `cc_dpd_months_12m` | NUMBER | Card-months with DPD > 0, last 12 months. |

## `feat_customer`

All features, one row per client. Input of the model and the decision engine.

| # | Column | Type | Description |
|---:|---|---|---|
| 1 | `sk_id_curr` | NUMBER | Client / application ID. Unique in this table. |
| 2 | `dataset` | VARCHAR2 | train = known outcome, used for the model; test = treated as incoming applicants. |
| 3 | `target` | NUMBER | 1 = client had payment difficulties on the current loan (Kaggle definition); NULL for test. |
| 4 | `app_contract_type` | VARCHAR2 | Product of the current application: Cash loans or Revolving loans. |
| 5 | `app_income_type` | VARCHAR2 | Income type of the client (Working, Pensioner, ...). |
| 6 | `app_education` | VARCHAR2 | Highest education level. |
| 7 | `app_family_status` | VARCHAR2 | Family status. |
| 8 | `app_children_cnt` | NUMBER | Number of children. |
| 9 | `app_family_members_cnt` | NUMBER | Number of family members. |
| 10 | `app_age_years` | NUMBER | Age at application, in years (from DAYS_BIRTH). |
| 11 | `app_employed_years` | NUMBER | Length of current employment in years. NULL when DAYS_EMPLOYED = 365243 (not employed, decision 9). |
| 12 | `app_is_not_employed` | NUMBER | 1 when DAYS_EMPLOYED = 365243: pensioners and unemployed (decision 9). |
| 13 | `app_income_amt` | NUMBER | Income of the client (AMT_INCOME_TOTAL, as given by Kaggle). |
| 14 | `app_credit_amt` | NUMBER | Credit amount of the current application. |
| 15 | `app_annuity_amt` | NUMBER | Annuity of the current application (AMT_ANNUITY). |
| 16 | `app_goods_price_amt` | NUMBER | Price of the goods financed (consumer loans). |
| 17 | `app_credit_to_income` | NUMBER | Credit amount / income. |
| 18 | `app_annuity_to_income` | NUMBER | AMT_ANNUITY / AMT_INCOME_TOTAL as given. Kaggle does not document the period of either amount, so this is a relative burden measure, not a monthly PTI. |
| 19 | `app_credit_to_goods` | NUMBER | Credit amount / goods price. Above 1 = credit larger than the goods price. |
| 20 | `app_ext_source_1` | NUMBER | Normalised external score 1 (Kaggle, source undisclosed). |
| 21 | `app_ext_source_2` | NUMBER | Normalised external score 2 (Kaggle, source undisclosed). |
| 22 | `app_ext_source_3` | NUMBER | Normalised external score 3 (Kaggle, source undisclosed). |
| 23 | `app_ext_source_mean` | NUMBER | Mean of the available external scores; NULL when none is available. |
| 24 | `app_region_rating` | NUMBER | Lender's rating of the client's region (1, 2, 3). |
| 25 | `app_documents_cnt` | NUMBER | Number of documents provided (sum of FLAG_DOCUMENT_2..21). |
| 26 | `app_bureau_enquiries_1y` | NUMBER | Credit bureau enquiries in the year before application. |
| 27 | `bur_has_history` | NUMBER | 1 when the client has at least one credit in the bureau. |
| 28 | `bur_credit_cnt` | NUMBER | Bureau credits, all statuses. |
| 29 | `bur_active_cnt` | NUMBER | Active bureau credits. |
| 30 | `bur_closed_cnt` | NUMBER | Closed bureau credits. |
| 31 | `bur_bad_status_cnt` | NUMBER | Bureau credits with status Sold or Bad debt (merged: Bad debt has only 21 rows). |
| 32 | `bur_active_credit_sum` | NUMBER | Sum of credit amounts of active bureau credits. |
| 33 | `bur_active_debt_sum` | NUMBER | Sum of current debt on active bureau credits. |
| 34 | `bur_active_overdue_sum` | NUMBER | Sum of amounts currently overdue on active bureau credits. |
| 35 | `bur_current_dpd_max` | NUMBER | Maximum days past due on any bureau credit at application. |
| 36 | `bur_max_overdue_amt_ever` | NUMBER | Largest amount ever overdue on any bureau credit. |
| 37 | `bur_prolong_cnt` | NUMBER | Number of prolongations over all bureau credits. |
| 38 | `bur_last_credit_days_ago` | NUMBER | Days between the most recent bureau credit application and this application. |
| 39 | `bur_new_credit_cnt_12m` | NUMBER | Bureau credits applied for in the 365 days before application. |
| 40 | `bur_annuity_known_sum` | NUMBER | Sum of annuities of active bureau credits where the annuity is reported (> 0). Reported for only 22.2% of active credits (decision 12). |
| 41 | `bur_annuity_known_cnt` | NUMBER | Active bureau credits with a reported annuity. |
| 42 | `bb_has_history` | NUMBER | 1 when monthly bureau status history exists for at least one credit (37.8% of clients). |
| 43 | `bb_worst_status_all` | NUMBER | Worst monthly bureau status ever: 0 = no DPD, 1 = 1-30, 2 = 31-60, 3 = 61-90, 4 = 91-120, 5 = 120+ or sold / written off. |
| 44 | `bb_worst_status_12m` | NUMBER | Worst monthly bureau status in the last 12 months (MONTHS_BALANCE 0 to -11; bureau data includes month 0). Same scale as bb_worst_status_all. |
| 45 | `bb_dpd_months_12m` | NUMBER | Credit-months with DPD (status 1-5) in the last 12 months (MONTHS_BALANCE 0 to -11), summed over bureau credits. |
| 46 | `prv_has_history` | NUMBER | 1 when the client has at least one previous application. |
| 47 | `prv_app_cnt` | NUMBER | Previous applications (last application per contract and per day only, decision 11). |
| 48 | `prv_approved_cnt` | NUMBER | Previous applications approved. |
| 49 | `prv_refused_cnt` | NUMBER | Previous applications refused. |
| 50 | `prv_canceled_cnt` | NUMBER | Previous applications cancelled. |
| 51 | `prv_refused_share` | NUMBER | Refused / all previous applications; NULL without history. |
| 52 | `prv_app_cnt_2y` | NUMBER | Previous applications decided in the 730 days before application. |
| 53 | `prv_refused_cnt_2y` | NUMBER | Previous applications refused in the 730 days before application. |
| 54 | `prv_last_decision_days_ago` | NUMBER | Days between the most recent previous decision and this application. |
| 55 | `prv_granted_to_asked_avg` | NUMBER | Average of granted / asked amount over approved applications (below 1 = client got less than asked). |
| 56 | `prv_approved_credit_sum` | NUMBER | Sum of credit amounts of approved previous applications. |
| 57 | `ins_has_history` | NUMBER | 1 when the client has instalment history on previous credits. |
| 58 | `ins_cnt_all` | NUMBER | Instalments due (after merging partial payments into one instalment, decision 10). |
| 59 | `ins_late_share_all` | NUMBER | Share of instalments whose last payment came after the due date. |
| 60 | `ins_days_late_max_all` | NUMBER | Maximum days between due date and last payment. |
| 61 | `ins_days_late_avg_all` | NUMBER | Average days late (early payment counts as 0). |
| 62 | `ins_underpaid_share_all` | NUMBER | Share of instalments where the total paid is below the amount due. |
| 63 | `ins_unpaid_cnt_all` | NUMBER | Instalments with no payment recorded. |
| 64 | `ins_cnt_12m` | NUMBER | Instalments due in the 365 days before application. |
| 65 | `ins_late_share_12m` | NUMBER | Share of instalments paid late, last 365 days. |
| 66 | `ins_days_late_max_12m` | NUMBER | Maximum days late, last 365 days. |
| 67 | `ins_underpaid_share_12m` | NUMBER | Share of instalments underpaid, last 365 days. |
| 68 | `pos_has_history` | NUMBER | 1 when the client has POS or cash loan balance history. |
| 69 | `pos_contract_cnt` | NUMBER | Previous POS / cash contracts. |
| 70 | `pos_active_cnt` | NUMBER | Contracts whose latest monthly status is Active. |
| 71 | `pos_instalments_left_sum` | NUMBER | Instalments left to pay on active contracts (latest month). |
| 72 | `pos_dpd_max_all` | NUMBER | Maximum days past due in any month. |
| 73 | `pos_dpd_def_max_all` | NUMBER | Maximum days past due with tolerance (small debts ignored), any month. |
| 74 | `pos_dpd_months_all` | NUMBER | Contract-months with DPD > 0. |
| 75 | `pos_dpd_max_12m` | NUMBER | Maximum days past due, last 12 months (MONTHS_BALANCE -1 to -12; the latest month in this source is -1). |
| 76 | `pos_dpd_months_12m` | NUMBER | Contract-months with DPD > 0, last 12 months. |
| 77 | `cc_has_history` | NUMBER | 1 when the client has credit card history. |
| 78 | `cc_card_cnt` | NUMBER | Previous credit cards. |
| 79 | `cc_util_avg_12m` | NUMBER | Average balance / limit, last 12 months. |
| 80 | `cc_util_max_12m` | NUMBER | Maximum balance / limit, last 12 months. |
| 81 | `cc_active_months_12m` | NUMBER | Months with any card spending in the last 12 months (0-12). |
| 82 | `cc_drawings_avg_12m` | NUMBER | Average monthly drawings, last 12 months. |
| 83 | `cc_pay_to_min_avg_12m` | NUMBER | Average total payment / minimum instalment, last 12 months (below 1 = paid less than the minimum). |
| 84 | `cc_dpd_max_all` | NUMBER | Maximum days past due on any card in any month. |
| 85 | `cc_dpd_months_12m` | NUMBER | Card-months with DPD > 0, last 12 months. |
| 86 | `bur_debt_to_income` | NUMBER | Active bureau debt / income (decision 12: reliable because debt is reported, unlike bureau annuities). |
| 87 | `bur_annuity_to_income` | NUMBER | Reported bureau annuities / income. Understates the burden: annuity is reported for only 22.2% of active credits. |
