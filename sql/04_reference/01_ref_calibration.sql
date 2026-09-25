-- =====================================================================
-- 01_ref_calibration.sql
-- Stage 3g: calibration numbers in a table, the formula in ONE function
-- (improvement 2).
--
-- In plain words: a model's raw score has to be turned into a probability
-- of default (PD) that can be taken at face value. That takes a formula
-- with two numbers, a and b. Legacy pipelines often copy such a formula
-- into many procedures, each with its own hard-coded numbers. Here:
--   - the numbers live in ONE table, ref_calibration, one row per model
--     version, with the dates it is valid for
--   - the formula lives in ONE function, f_calibrate_pd
--   - Python checks that it computes exactly the same PD (Stage 3g check)
--
--   PD = 1 / (1 + EXP(-(a + b * raw_score)))
--
-- ref_calibration is created only if it does not exist, so its history is
-- kept. Rows are written by python/scripts/calibrate_and_score.py.
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE

DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM user_tables WHERE table_name = 'REF_CALIBRATION';
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE TABLE ref_calibration (
        model_name     VARCHAR2(30)   NOT NULL,
        model_version  NUMBER         NOT NULL,
        coef_a         BINARY_DOUBLE  NOT NULL,
        coef_b         BINARY_DOUBLE  NOT NULL,
        fitted_on      VARCHAR2(200)  NOT NULL,
        valid_from     DATE           NOT NULL,
        valid_to       DATE,
        created_at     TIMESTAMP      NOT NULL,
        CONSTRAINT pk_ref_calibration PRIMARY KEY (model_name, model_version)
      )]';
    EXECUTE IMMEDIATE q'[COMMENT ON TABLE ref_calibration IS 'Calibration numbers per model version: PD = 1 / (1 + EXP(-(coef_a + coef_b * raw_score))). The formula itself is f_calibrate_pd.']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN ref_calibration.coef_a IS 'Shift of the raw score (log-odds).']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN ref_calibration.coef_b IS 'Stretch of the raw score; 1 = unchanged.']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN ref_calibration.fitted_on IS 'Which clients the numbers were learned from.']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN ref_calibration.valid_to IS 'NULL = still in use.']';
  END IF;
END;
/

CREATE OR REPLACE FUNCTION f_calibrate_pd (
  p_raw_score IN BINARY_DOUBLE,
  p_coef_a    IN BINARY_DOUBLE,
  p_coef_b    IN BINARY_DOUBLE
) RETURN BINARY_DOUBLE DETERMINISTIC
IS
  PRAGMA UDF;   -- compiled for fast calls from SQL
BEGIN
  RETURN 1 / (1 + EXP(-(p_coef_a + p_coef_b * p_raw_score)));
END;
/

PROMPT 01_ref_calibration: done
