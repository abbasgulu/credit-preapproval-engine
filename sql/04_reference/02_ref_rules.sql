-- =====================================================================
-- 02_ref_rules.sql
-- Stage 4a: every threshold of the decision engine in ONE table
-- (improvement 4).
--
-- In plain words: instead of numbers such as "minimum age 18" or "cut-off
-- 10%" being typed into many scripts, each rule is one row here, with the
-- date it starts to apply. The engine reads the rows valid on its run date.
-- Changing a rule = closing the old row (valid_to) and adding a new one;
-- past decisions stay explainable with the rules of their day.
--
-- All values are ILLUSTRATIVE choices for a public dataset (decision 25).
-- PD_CUTOFF is not seeded here: it is derived from TARGET_BAD_RATE by
-- python\scripts\choose_cutoff.py (Stage 4b).
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE

DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM user_tables WHERE table_name = 'REF_RULES';
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE TABLE ref_rules (
        rule_code    VARCHAR2(40)   NOT NULL,
        rule_value   NUMBER         NOT NULL,
        unit         VARCHAR2(30)   NOT NULL,
        description  VARCHAR2(400)  NOT NULL,
        set_by       VARCHAR2(200)  NOT NULL,
        valid_from   DATE           NOT NULL,
        valid_to     DATE,
        created_at   TIMESTAMP      NOT NULL,
        CONSTRAINT pk_ref_rules PRIMARY KEY (rule_code, valid_from)
      )]';
    EXECUTE IMMEDIATE q'[COMMENT ON TABLE ref_rules IS 'Every threshold of the decision engine, one row per rule and validity period. The engine reads rows valid on its run date.']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN ref_rules.set_by IS 'Who or what set the value: an illustrative choice, or the analysis that derived it.']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN ref_rules.valid_to IS 'NULL = in force.']';
  END IF;
END;
/

MERGE INTO ref_rules t
USING (
  SELECT 'MIN_AGE' AS rule_code, 18 AS rule_value, 'years' AS unit,
         'Minimum age at application.' AS description FROM dual UNION ALL
  SELECT 'MAX_AGE_AT_MATURITY', 70, 'years',
         'Maximum age at the end of the offered term (policy rule, not a risk estimate: decision 20).' FROM dual UNION ALL
  SELECT 'OFFER_TERM_MONTHS', 24, 'months',
         'Term of the pre-approved offer, used for the age-at-maturity rule.' FROM dual UNION ALL
  SELECT 'MAX_CURRENT_DPD', 0, 'days',
         'Maximum days past due today on any credit at other lenders.' FROM dual UNION ALL
  SELECT 'TARGET_BAD_RATE', 0.05, 'share',
         'Highest accepted default rate among approved clients; the PD cut-off is derived from it (Stage 4b).' FROM dual UNION ALL
  SELECT 'MAX_TOTAL_DEBT_TO_INCOME', 5, 'x income',
         'Active debt at other lenders plus the offered limit may not exceed this multiple of income.' FROM dual UNION ALL
  SELECT 'MIN_LIMIT', 50000, 'amount',
         'Smallest offer worth making; below it the client is declined for affordability.' FROM dual UNION ALL
  SELECT 'MAX_LIMIT', 1500000, 'amount',
         'Largest pre-approved offer.' FROM dual
) s
ON (t.rule_code = RTRIM(s.rule_code) AND t.valid_from = DATE '2026-09-25')
WHEN NOT MATCHED THEN INSERT (rule_code, rule_value, unit, description, set_by, valid_from, created_at)
     VALUES (RTRIM(s.rule_code), s.rule_value, RTRIM(s.unit), RTRIM(s.description),
             'illustrative choice (decision 25)', DATE '2026-09-25', SYSTIMESTAMP);
COMMIT;

PROMPT 02_ref_rules: done
