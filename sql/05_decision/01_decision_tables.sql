-- =====================================================================
-- 01_decision_tables.sql
-- Stage 4c: where the decision engine writes its results.
--
-- In plain words: every run of the engine leaves three things behind:
--
--   decision_runs     one row per run: date, model, cut-off, the rules in
--                     force (as text and as a short fingerprint), counts,
--                     status. Rows are never deleted.
--   decisions         one row per client per run date: approve or decline,
--                     limit, PD, main reason, all reasons, and the facts
--                     the rules looked at (age, income, debt, ...)
--   decision_reasons  one row per client, run date and reason - the same
--                     reasons as a list, easy to count in reports
--
-- decisions and decision_reasons are PARTITIONED by run date: the table is
-- stored as separate parts, one per date. Re-running a date empties and
-- refills only that date's part; every other date stays exactly as it was
-- (improvement 5: no daily truncate, history is kept). AUTOMATIC means
-- Oracle creates the part for a new date by itself.
--
-- decision_work is the engine's scratch pad: a temporary table whose rows
-- only the running session sees and which empties itself at COMMIT.
--
-- Tables are created only if they do not exist, so history is kept.
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE

DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM user_tables WHERE table_name = 'DECISION_RUNS';
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE TABLE decision_runs (
        run_id            NUMBER GENERATED ALWAYS AS IDENTITY,
        run_date          DATE            NOT NULL,
        model_name        VARCHAR2(30)    NOT NULL,
        model_version     NUMBER,
        coef_a            BINARY_DOUBLE,
        coef_b            BINARY_DOUBLE,
        pd_cutoff         NUMBER,
        rules_in_force    VARCHAR2(4000),
        ruleset_hash      VARCHAR2(16),
        excluded_clients  NUMBER,
        clients           NUMBER,
        approved          NUMBER,
        status            VARCHAR2(10)    NOT NULL,
        message           VARCHAR2(4000),
        started_at        TIMESTAMP       NOT NULL,
        finished_at       TIMESTAMP,
        seconds           NUMBER,
        CONSTRAINT pk_decision_runs PRIMARY KEY (run_id),
        CONSTRAINT ck_decision_runs_status CHECK (status IN ('RUNNING', 'DONE', 'FAILED'))
      )]';
    EXECUTE IMMEDIATE q'[COMMENT ON TABLE decision_runs IS 'One row per run of p_run_decisions: date, model, cut-off, rules in force and their fingerprint, counts, status. Never deleted.']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN decision_runs.rules_in_force IS 'Every rule in force on run_date as CODE=value, so the run can be explained later without looking anything up.']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN decision_runs.ruleset_hash IS 'First 16 characters of the SHA-256 of the rules, limit grid and reason codes in force: two runs with the same hash used the same rule set.']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN decision_runs.status IS 'RUNNING while the engine works, DONE when all decisions are written, FAILED with the error in message.']';
  END IF;

  SELECT COUNT(*) INTO v_count FROM user_tables WHERE table_name = 'DECISIONS';
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE TABLE decisions (
        run_date          DATE            NOT NULL,
        sk_id_curr        NUMBER          NOT NULL,
        run_id            NUMBER          NOT NULL,
        split             VARCHAR2(10)    NOT NULL,
        decision          VARCHAR2(7)     NOT NULL,
        offer_limit       NUMBER,
        main_reason       VARCHAR2(30),
        all_reasons       VARCHAR2(400),
        reason_count      NUMBER          NOT NULL,
        pd                BINARY_DOUBLE   NOT NULL,
        age_years         NUMBER          NOT NULL,
        current_dpd       NUMBER          NOT NULL,
        income_amt        NUMBER          NOT NULL,
        active_debt       NUMBER          NOT NULL,
        income_multiple   NUMBER          NOT NULL,
        grid_limit        NUMBER          NOT NULL,
        debt_room         NUMBER          NOT NULL,
        calc_limit        NUMBER          NOT NULL,
        limit_basis       VARCHAR2(10)    NOT NULL,
        model_name        VARCHAR2(30)    NOT NULL,
        model_version     NUMBER          NOT NULL,
        CONSTRAINT pk_decisions PRIMARY KEY (run_date, sk_id_curr) USING INDEX LOCAL,
        CONSTRAINT fk_decisions_run FOREIGN KEY (run_id) REFERENCES decision_runs (run_id),
        CONSTRAINT fk_decisions_reason FOREIGN KEY (main_reason) REFERENCES ref_reason_codes (reason_code),
        CONSTRAINT ck_decisions_outcome CHECK (
             (decision = 'APPROVE' AND offer_limit IS NOT NULL AND main_reason IS NULL     AND reason_count = 0)
          OR (decision = 'DECLINE' AND offer_limit IS NULL     AND main_reason IS NOT NULL AND reason_count > 0)),
        CONSTRAINT ck_decisions_basis CHECK (limit_basis IN ('GRID', 'DEBT', 'MAX_LIMIT'))
      )
      PARTITION BY LIST (run_date) AUTOMATIC
      (PARTITION p_20260925 VALUES (DATE '2026-09-25'))]';
    EXECUTE IMMEDIATE q'[COMMENT ON TABLE decisions IS 'One pre-approval decision per client and run date, with limit and reasons, written by p_run_decisions. Partitioned by run_date: a re-run replaces only its own date.']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN decisions.decision IS 'APPROVE (with offer_limit) or DECLINE (with main_reason).']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN decisions.offer_limit IS 'Pre-approved limit; NULL when declined.']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN decisions.main_reason IS 'The reason with the lowest priority number in ref_reason_codes; NULL when approved.']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN decisions.all_reasons IS 'Every reason that applied, in priority order, comma-separated. Same content as decision_reasons.']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN decisions.pd IS 'Calibrated probability of default used for the decision.']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN decisions.active_debt IS 'Active debt at other lenders (negative bureau balances counted as 0).']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN decisions.grid_limit IS 'income_multiple x income: the limit the limit grid allows.']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN decisions.debt_room IS 'MAX_TOTAL_DEBT_TO_INCOME x income - active_debt: how much new credit the debt rule allows (can be negative).']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN decisions.calc_limit IS 'Smallest of grid_limit, debt_room and MAX_LIMIT (not below 0), computed for every client, approved or not.']';
    EXECUTE IMMEDIATE q'[COMMENT ON COLUMN decisions.limit_basis IS 'Which of the three set calc_limit: GRID, DEBT or MAX_LIMIT.']';
  END IF;

  SELECT COUNT(*) INTO v_count FROM user_tables WHERE table_name = 'DECISION_REASONS';
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE TABLE decision_reasons (
        run_date     DATE          NOT NULL,
        sk_id_curr   NUMBER        NOT NULL,
        reason_code  VARCHAR2(30)  NOT NULL,
        CONSTRAINT pk_decision_reasons PRIMARY KEY (run_date, sk_id_curr, reason_code) USING INDEX LOCAL,
        CONSTRAINT fk_decision_reasons_code FOREIGN KEY (reason_code) REFERENCES ref_reason_codes (reason_code)
      )
      PARTITION BY LIST (run_date) AUTOMATIC
      (PARTITION p_20260925 VALUES (DATE '2026-09-25'))]';
    EXECUTE IMMEDIATE q'[COMMENT ON TABLE decision_reasons IS 'Every reason that applied to a client on a run date, written at decision time (improvement 9). Partitioned like decisions.']';
  END IF;

  SELECT COUNT(*) INTO v_count FROM user_tables WHERE table_name = 'DECISION_WORK';
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE GLOBAL TEMPORARY TABLE decision_work (
        sk_id_curr        NUMBER,
        split             VARCHAR2(10),
        pd                BINARY_DOUBLE,
        age_years         NUMBER,
        current_dpd       NUMBER,
        income_amt        NUMBER,
        active_debt       NUMBER,
        income_multiple   NUMBER,
        grid_limit        NUMBER,
        debt_room         NUMBER,
        calc_limit        NUMBER,
        limit_basis       VARCHAR2(10),
        rc_min_age        VARCHAR2(30),
        rc_arrears        VARCHAR2(30),
        rc_age_maturity   VARCHAR2(30),
        rc_pd             VARCHAR2(30),
        rc_debt           VARCHAR2(30),
        rc_limit_min      VARCHAR2(30)
      ) ON COMMIT DELETE ROWS]';
    EXECUTE IMMEDIATE q'[COMMENT ON TABLE decision_work IS 'Scratch pad of p_run_decisions: one row per client with inputs, limit and the reason each rule gives. Session-private, emptied at COMMIT.']';
  END IF;
END;
/

CREATE OR REPLACE VIEW v_decision_last_run AS
SELECT run_id, run_date, model_name, model_version, pd_cutoff, ruleset_hash,
       excluded_clients, clients, approved, status, started_at, seconds
FROM   decision_runs
WHERE  run_id = (SELECT MAX(run_id) FROM decision_runs WHERE status = 'DONE');

COMMENT ON TABLE v_decision_last_run IS 'The most recent successful run of the decision engine (one row).';

PROMPT 01_decision_tables: done
