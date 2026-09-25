-- =====================================================================
-- 04_model_scores.sql
-- Stage 3g: one score per client and model version.
--
-- In plain words: Python computes each client's raw score with the saved
-- model and stores it here. The probability of default is NOT stored as a
-- fixed number: the view v_scores turns the raw score into a PD with the
-- calibration numbers of ref_calibration and the one formula
-- f_calibrate_pd. Change the calibration, and every PD follows.
--
-- pd_check is the PD as Python computed it. A data-quality check proves
-- that Oracle's formula gives the same result (reconciliation of the two
-- engines, improvement 10).
--
-- Scores are kept per model version (improvement 5: no truncate, history).
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE

DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM user_tables WHERE table_name = 'MODEL_SCORES';
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE TABLE model_scores (
        model_name     VARCHAR2(30)   NOT NULL,
        model_version  NUMBER         NOT NULL,
        sk_id_curr     NUMBER         NOT NULL,
        split          VARCHAR2(10)   NOT NULL,
        raw_score      BINARY_DOUBLE  NOT NULL,
        pd_check       BINARY_DOUBLE  NOT NULL,
        scored_at      TIMESTAMP      NOT NULL,
        CONSTRAINT pk_model_scores PRIMARY KEY (model_name, model_version, sk_id_curr)
      )]';
    EXECUTE IMMEDIATE q'[COMMENT ON TABLE model_scores IS 'Raw score of every client per model version, written by python/scripts/calibrate_and_score.py. Read PDs from v_scores.']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN model_scores.raw_score IS 'Model output on the log-odds scale; higher = riskier.']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN model_scores.pd_check IS 'Calibrated PD as computed in Python; must equal v_scores.pd (reconciliation check).']';
  END IF;
END;
/

CREATE OR REPLACE VIEW v_scores AS
SELECT s.model_name,
       s.model_version,
       s.sk_id_curr,
       s.split,
       s.raw_score,
       f_calibrate_pd(s.raw_score, c.coef_a, c.coef_b) AS pd,
       s.pd_check,
       s.scored_at
FROM   model_scores s
JOIN   ref_calibration c
       ON  c.model_name    = s.model_name
       AND c.model_version = s.model_version;

COMMENT ON TABLE v_scores IS 'Calibrated probability of default (pd) per client and model version: raw_score + ref_calibration + f_calibrate_pd.';

PROMPT 04_model_scores: done
