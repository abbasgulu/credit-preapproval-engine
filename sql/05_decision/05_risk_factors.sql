-- =====================================================================
-- 05_risk_factors.sql
-- Stage 4e: the three facts behind each risk decline.
--
-- In plain words: "your estimated risk is above our limit" is a reason, but
-- not an explanation. For every client whose PD is above the cut-off,
-- python\scripts\explain_decisions.py asks the model which of the client's
-- facts raised the estimated risk most, compared with an average client
-- (SHAP values), and writes the top three here as sentences from
-- ref_feature_text, e.g. "35% of instalments in the last year were paid late".
--
--   decision_risk_factors    one row per client, run date and rank (1-3);
--                            partitioned by run date like decisions
--   v_decision_explanations  one row per explained client: decision, main
--                            reason and the three facts side by side
--
-- Each row carries the run_id of the decisions it explains. After a re-run
-- of the engine the old explanations no longer match the new run_id and
-- are hidden by the view until the script is run again.
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE

DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM user_tables WHERE table_name = 'DECISION_RISK_FACTORS';
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE TABLE decision_risk_factors (
        run_date       DATE            NOT NULL,
        sk_id_curr     NUMBER          NOT NULL,
        rank_no        NUMBER(1)       NOT NULL,
        run_id         NUMBER          NOT NULL,
        feature_name   VARCHAR2(40)    NOT NULL,
        feature_value  VARCHAR2(100),
        contribution   BINARY_DOUBLE   NOT NULL,
        fact_text      VARCHAR2(400)   NOT NULL,
        model_name     VARCHAR2(30)    NOT NULL,
        model_version  NUMBER          NOT NULL,
        created_at     TIMESTAMP       NOT NULL,
        CONSTRAINT pk_decision_risk_factors PRIMARY KEY (run_date, sk_id_curr, rank_no) USING INDEX LOCAL,
        CONSTRAINT fk_risk_factors_run FOREIGN KEY (run_id) REFERENCES decision_runs (run_id),
        CONSTRAINT fk_risk_factors_feature FOREIGN KEY (feature_name) REFERENCES ref_feature_text (feature_name),
        CONSTRAINT ck_risk_factors_rank CHECK (rank_no BETWEEN 1 AND 3),
        CONSTRAINT ck_risk_factors_up CHECK (contribution > 0)
      )
      PARTITION BY LIST (run_date) AUTOMATIC
      (PARTITION p_20260925 VALUES (DATE '2026-09-25'))]';
    EXECUTE IMMEDIATE q'[COMMENT ON TABLE decision_risk_factors IS 'Top 3 facts that raised the estimated risk of each client declined for risk (SHAP), in plain words. Written by python/scripts/explain_decisions.py.']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN decision_risk_factors.contribution IS 'SHAP value: how much the fact raised the raw score (log-odds) compared with an average client. Always > 0 here.']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN decision_risk_factors.fact_text IS 'The fact as a sentence, from ref_feature_text with the client''s value filled in.']';
  END IF;
END;
/

CREATE OR REPLACE VIEW v_decision_explanations AS
SELECT d.run_date,
       d.run_id,
       d.sk_id_curr,
       d.split,
       d.decision,
       d.main_reason,
       d.all_reasons,
       d.pd,
       MAX(CASE WHEN f.rank_no = 1 THEN f.fact_text END) AS risk_fact_1,
       MAX(CASE WHEN f.rank_no = 2 THEN f.fact_text END) AS risk_fact_2,
       MAX(CASE WHEN f.rank_no = 3 THEN f.fact_text END) AS risk_fact_3
FROM   decisions d
JOIN   decision_risk_factors f
       ON  f.run_date   = d.run_date
       AND f.sk_id_curr = d.sk_id_curr
       AND f.run_id     = d.run_id
GROUP  BY d.run_date, d.run_id, d.sk_id_curr, d.split, d.decision, d.main_reason, d.all_reasons, d.pd;

SET FEEDBACK OFF
COMMENT ON TABLE v_decision_explanations IS 'One row per client declined for risk: decision, reasons and the three facts that raised the estimated risk most.';
SET FEEDBACK ON

PROMPT 05_risk_factors: done
