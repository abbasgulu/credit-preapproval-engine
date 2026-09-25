-- =====================================================================
-- 03_ref_reason_codes.sql
-- Stage 4a: every reason a decision can give, in plain words
-- (improvement 9).
--
-- In plain words: a decline must come with a reason a client or an
-- auditor can read. The engine writes these codes at the moment of the
-- decision; reports only look them up here, they never reconstruct them.
-- priority: when several reasons apply, the lowest number is the main one.
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE

DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM user_tables WHERE table_name = 'REF_REASON_CODES';
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE TABLE ref_reason_codes (
        reason_code  VARCHAR2(30)   NOT NULL,
        category     VARCHAR2(20)   NOT NULL,
        priority     NUMBER         NOT NULL,
        description  VARCHAR2(300)  NOT NULL,
        CONSTRAINT pk_ref_reason_codes PRIMARY KEY (reason_code),
        CONSTRAINT ck_reason_category CHECK (category IN ('EXCLUSION', 'POLICY', 'RISK', 'AFFORDABILITY'))
      )]';
    EXECUTE IMMEDIATE q'[COMMENT ON TABLE ref_reason_codes IS 'Every decline reason with a plain-words description. Lowest priority number = main reason.']';
  END IF;
END;
/

MERGE INTO ref_reason_codes t
USING (
  SELECT 'EXCL_WRITTEN_OFF' AS reason_code, 'EXCLUSION' AS category, 10 AS priority,
         'A credit at another lender was written off or sold to a debt collector.' AS description FROM dual UNION ALL
  SELECT 'AGE_UNDER_MIN',   'POLICY', 20, 'Below the minimum age for credit.' FROM dual UNION ALL
  SELECT 'CURRENT_ARREARS', 'POLICY', 30, 'Currently behind on a payment at another lender.' FROM dual UNION ALL
  SELECT 'AGE_AT_MATURITY', 'POLICY', 40, 'Would be above the maximum age at the end of the offered term.' FROM dual UNION ALL
  SELECT 'PD_ABOVE_CUTOFF', 'RISK',   50, 'Estimated chance of repayment trouble is above the accepted level.' FROM dual UNION ALL
  SELECT 'DEBT_TOO_HIGH',   'AFFORDABILITY', 60, 'Existing debt leaves no room for an offer of the minimum size.' FROM dual
) s
ON (t.reason_code = RTRIM(s.reason_code))
WHEN MATCHED THEN UPDATE SET t.category = RTRIM(s.category), t.priority = s.priority, t.description = RTRIM(s.description)
WHEN NOT MATCHED THEN INSERT (reason_code, category, priority, description)
     VALUES (RTRIM(s.reason_code), RTRIM(s.category), s.priority, RTRIM(s.description));
COMMIT;

PROMPT 03_ref_reason_codes: done
