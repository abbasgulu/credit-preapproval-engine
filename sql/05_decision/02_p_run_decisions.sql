-- =====================================================================
-- 02_p_run_decisions.sql
-- Stage 4c: the decision engine.
--
-- In plain words: one procedure takes every client, looks up the rules
-- that are in force on the run date, and writes one decision per client:
-- approve with a limit, or decline with the reasons. It contains no
-- threshold, no list of clients and no limit table of its own - it reads
-- them all from the ref_ tables (improvements 1, 3, 4). Reasons are
-- written at the moment of the decision (improvement 9).
--
-- The steps, the same for every client:
--   1. exclusion list      ref_exclusion_list           -> e.g. EXCL_WRITTEN_OFF
--   2. policy rules        MIN_AGE, MAX_CURRENT_DPD,
--                          MAX_AGE_AT_MATURITY          -> AGE_UNDER_MIN,
--                                                          CURRENT_ARREARS,
--                                                          AGE_AT_MATURITY
--   3. risk                PD > PD_CUTOFF               -> PD_ABOVE_CUTOFF
--   4. limit               grid multiple x income, capped by
--                          MAX_TOTAL_DEBT_TO_INCOME x income - active debt
--                          and by MAX_LIMIT
--   5. affordability       limit below MIN_LIMIT        -> DEBT_TOO_HIGH if
--                          the debt cap is the problem, LIMIT_BELOW_MIN if
--                          the grid limit itself is too small (both can apply)
-- Every step runs for every client, so ALL reasons are recorded; the main
-- reason is the one with the lowest priority number in ref_reason_codes.
-- A client with no reason is approved with the limit from step 4.
--
-- Usage (SQL*Plus):  EXEC p_run_decisions                      -- today, lightgbm
--                    EXEC p_run_decisions(DATE '2026-09-25')   -- a given date
--
-- Safety: the run is logged in decision_runs first (RUNNING); inputs are
-- checked before anything is written; the date's partitions are emptied
-- and all rows are written in ONE transaction; any error rolls it back,
-- marks the run FAILED with the message and stops. A failed re-run leaves
-- that date empty (never half-filled) until the next successful run.
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE

CREATE OR REPLACE PROCEDURE p_run_decisions (
  p_run_date   IN DATE     DEFAULT TRUNC(SYSDATE),
  p_model_name IN VARCHAR2 DEFAULT 'lightgbm'
) AS
  v_date         CONSTANT DATE := TRUNC(p_run_date);
  v_day          CONSTANT VARCHAR2(10) := TO_CHAR(TRUNC(p_run_date), 'YYYY-MM-DD');
  v_run_id       decision_runs.run_id%TYPE;
  v_started      TIMESTAMP := SYSTIMESTAMP;
  v_msg          VARCHAR2(4000);

  -- rules in force on the run date (f_rule stops if one is missing or doubled)
  v_min_age      NUMBER;
  v_max_age_mat  NUMBER;
  v_term_months  NUMBER;
  v_max_dpd      NUMBER;
  v_cutoff       NUMBER;
  v_max_dti      NUMBER;
  v_min_limit    NUMBER;
  v_max_limit    NUMBER;

  -- model and calibration valid on the run date
  v_version      NUMBER;
  v_coef_a       BINARY_DOUBLE;
  v_coef_b       BINARY_DOUBLE;

  -- rule-set fingerprint and counts
  v_rules_txt    VARCHAR2(4000);
  v_grid_txt     VARCHAR2(4000);
  v_codes_txt    VARCHAR2(4000);
  v_hash         VARCHAR2(16);
  v_population   NUMBER;
  v_scored       NUMBER;
  v_excluded     NUMBER;
  v_work_rows    NUMBER;
  v_incomplete   NUMBER;
  v_approved     NUMBER;
  v_has_rows     NUMBER;

  PROCEDURE say (p_text IN VARCHAR2) IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE(TO_CHAR(SYSTIMESTAMP, 'HH24:MI:SS') || '  ' || p_text);
  END;

  PROCEDURE fail (p_text IN VARCHAR2) IS
  BEGIN
    RAISE_APPLICATION_ERROR(-20030, 'p_run_decisions ' || v_day || ': ' || p_text);
  END;
BEGIN
  -- ---- 0. log the run -------------------------------------------------------
  INSERT INTO decision_runs (run_date, model_name, status, started_at)
  VALUES (v_date, p_model_name, 'RUNNING', v_started)
  RETURNING run_id INTO v_run_id;
  COMMIT;
  say('run ' || v_run_id || ' for ' || v_day || ', model ' || p_model_name);

  -- ---- 1. inputs valid on the run date --------------------------------------
  v_min_age     := f_rule('MIN_AGE', v_date);
  v_max_age_mat := f_rule('MAX_AGE_AT_MATURITY', v_date);
  v_term_months := f_rule('OFFER_TERM_MONTHS', v_date);
  v_max_dpd     := f_rule('MAX_CURRENT_DPD', v_date);
  v_cutoff      := f_rule('PD_CUTOFF', v_date);
  v_max_dti     := f_rule('MAX_TOTAL_DEBT_TO_INCOME', v_date);
  v_min_limit   := f_rule('MIN_LIMIT', v_date);
  v_max_limit   := f_rule('MAX_LIMIT', v_date);
  IF v_max_limit < v_min_limit THEN
    fail('MAX_LIMIT (' || v_max_limit || ') is below MIN_LIMIT (' || v_min_limit || ')');
  END IF;

  SELECT MAX(model_version) INTO v_version
  FROM   ref_calibration
  WHERE  model_name = p_model_name
  AND    valid_from <= v_date AND (valid_to IS NULL OR valid_to > v_date);
  IF v_version IS NULL THEN
    fail('no calibration of model ' || p_model_name || ' in force');
  END IF;
  SELECT coef_a, coef_b INTO v_coef_a, v_coef_b
  FROM   ref_calibration
  WHERE  model_name = p_model_name AND model_version = v_version;

  SELECT COUNT(*) INTO v_population FROM v_model_input;
  SELECT COUNT(*) INTO v_scored
  FROM   model_scores
  WHERE  model_name = p_model_name AND model_version = v_version;
  IF v_scored <> v_population THEN
    fail(p_model_name || ' version ' || v_version || ' scored ' || v_scored ||
         ' clients, but there are ' || v_population);
  END IF;

  SELECT COUNT(DISTINCT sk_id_curr) INTO v_excluded
  FROM   ref_exclusion_list
  WHERE  valid_from <= v_date AND (valid_to IS NULL OR valid_to > v_date);

  -- the rule set as text, and its fingerprint (numbers written with a dot,
  -- whatever the language settings of the computer)
  SELECT LISTAGG(rule_code || '=' || TO_CHAR(rule_value, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,'''), '; ')
           WITHIN GROUP (ORDER BY rule_code)
  INTO   v_rules_txt
  FROM   ref_rules
  WHERE  valid_from <= v_date AND (valid_to IS NULL OR valid_to > v_date);

  SELECT LISTAGG(TO_CHAR(pd_from, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,''') || '-' ||
                 TO_CHAR(pd_to, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,''') || '/' ||
                 TO_CHAR(income_from, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,''') || '-' ||
                 NVL(TO_CHAR(income_to, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,'''), 'up') || ':' ||
                 TO_CHAR(income_multiple, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,'''), '; ')
           WITHIN GROUP (ORDER BY pd_from, income_from)
  INTO   v_grid_txt
  FROM   ref_limit_grid
  WHERE  valid_from <= v_date AND (valid_to IS NULL OR valid_to > v_date);
  IF v_grid_txt IS NULL THEN
    fail('no limit grid in force');
  END IF;

  SELECT LISTAGG(reason_code || ':' || priority, '; ') WITHIN GROUP (ORDER BY priority, reason_code)
  INTO   v_codes_txt
  FROM   ref_reason_codes;

  SELECT SUBSTR(RAWTOHEX(STANDARD_HASH(v_rules_txt || '|' || v_grid_txt || '|' || v_codes_txt, 'SHA256')), 1, 16)
  INTO   v_hash
  FROM   dual;

  UPDATE decision_runs
  SET    model_version = v_version, coef_a = v_coef_a, coef_b = v_coef_b,
         pd_cutoff = v_cutoff, rules_in_force = v_rules_txt, ruleset_hash = v_hash,
         excluded_clients = v_excluded
  WHERE  run_id = v_run_id;
  COMMIT;
  say('inputs checked: ' || v_population || ' clients, model version ' || v_version ||
      ', PD cut-off ' || TO_CHAR(v_cutoff, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,''') ||
      ', rule set ' || v_hash);

  -- ---- 2. empty this date's partitions (other dates are not touched) ---------
  SELECT COUNT(*) INTO v_has_rows FROM decisions WHERE run_date = v_date AND ROWNUM = 1;
  IF v_has_rows > 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE decisions TRUNCATE PARTITION FOR (DATE ''' || v_day || ''')';
    say('earlier decisions of ' || v_day || ' removed (re-run)');
  END IF;
  SELECT COUNT(*) INTO v_has_rows FROM decision_reasons WHERE run_date = v_date AND ROWNUM = 1;
  IF v_has_rows > 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE decision_reasons TRUNCATE PARTITION FOR (DATE ''' || v_day || ''')';
  END IF;

  -- ---- 3. every client: PD, limit, and the reason each rule gives -------------
  -- From here on everything is one transaction.
  INSERT INTO decision_work (
    sk_id_curr, split, pd, age_years, current_dpd, income_amt, active_debt,
    income_multiple, grid_limit, debt_room, calc_limit, limit_basis,
    rc_min_age, rc_arrears, rc_age_maturity, rc_pd, rc_debt, rc_limit_min)
  WITH base AS (
    SELECT m.sk_id_curr,
           m.split,
           f_calibrate_pd(s.raw_score, v_coef_a, v_coef_b) AS pd,
           m.app_age_years                                 AS age_years,
           NVL(m.bur_current_dpd_max, 0)                   AS current_dpd,
           m.app_income_amt                                AS income_amt,
           GREATEST(NVL(m.bur_active_debt_sum, 0), 0)      AS active_debt
    FROM   v_model_input m
    JOIN   model_scores s
           ON  s.sk_id_curr    = m.sk_id_curr
           AND s.model_name    = p_model_name
           AND s.model_version = v_version
  ),
  grid AS (
    SELECT pd_from, pd_to, income_from, income_to, income_multiple
    FROM   ref_limit_grid
    WHERE  valid_from <= v_date AND (valid_to IS NULL OR valid_to > v_date)
  ),
  lim AS (
    SELECT b.sk_id_curr, b.split, b.pd, b.age_years, b.current_dpd, b.income_amt, b.active_debt,
           g.income_multiple,
           g.income_multiple * b.income_amt             AS grid_limit,
           v_max_dti * b.income_amt - b.active_debt      AS debt_room
    FROM   base b
    LEFT   JOIN grid g
           ON  b.pd >= g.pd_from
           AND (b.pd < g.pd_to OR g.pd_to = 1)                    -- last band includes PD = 1
           AND b.income_amt >= g.income_from
           AND (g.income_to IS NULL OR b.income_amt < g.income_to)
  ),
  cap AS (
    SELECT l.*,
           GREATEST(LEAST(l.grid_limit, l.debt_room, v_max_limit), 0) AS calc_limit
    FROM   lim l
  )
  SELECT c.sk_id_curr, c.split, c.pd, c.age_years, c.current_dpd, c.income_amt, c.active_debt,
         c.income_multiple, c.grid_limit, c.debt_room, c.calc_limit,
         CASE WHEN c.calc_limit = c.grid_limit             THEN 'GRID'
              WHEN c.calc_limit = GREATEST(c.debt_room, 0) THEN 'DEBT'
              ELSE                                               'MAX_LIMIT' END,
         -- step 2: policy rules
         CASE WHEN c.age_years < v_min_age                          THEN 'AGE_UNDER_MIN'   END,
         CASE WHEN c.current_dpd > v_max_dpd                        THEN 'CURRENT_ARREARS' END,
         CASE WHEN c.age_years + v_term_months / 12 > v_max_age_mat THEN 'AGE_AT_MATURITY' END,
         -- step 3: risk
         CASE WHEN c.pd > v_cutoff                                  THEN 'PD_ABOVE_CUTOFF' END,
         -- step 5: affordability
         CASE WHEN c.debt_room  < v_min_limit                       THEN 'DEBT_TOO_HIGH'   END,
         CASE WHEN c.grid_limit < v_min_limit                       THEN 'LIMIT_BELOW_MIN' END
  FROM   cap c;

  SELECT COUNT(*),
         COUNT(CASE WHEN pd IS NULL OR age_years IS NULL OR income_amt IS NULL
                      OR income_multiple IS NULL THEN 1 END)
  INTO   v_work_rows, v_incomplete
  FROM   decision_work;
  IF v_work_rows <> v_population THEN
    fail(v_work_rows || ' clients prepared, expected ' || v_population);
  END IF;
  IF v_incomplete > 0 THEN
    fail(v_incomplete || ' clients without PD, age, income or a limit-grid cell');
  END IF;
  say('step 1-5 computed for ' || v_work_rows || ' clients');

  -- ---- 4. all reasons: the exclusion list + every rule that fired -------------
  INSERT INTO decision_reasons (run_date, sk_id_curr, reason_code)
  SELECT v_date, e.sk_id_curr, e.reason_code
  FROM   ref_exclusion_list e
  WHERE  e.valid_from <= v_date AND (e.valid_to IS NULL OR e.valid_to > v_date)
  AND    EXISTS (SELECT 1 FROM decision_work w WHERE w.sk_id_curr = e.sk_id_curr)
  UNION                                                   -- UNION: one row per reason
  SELECT v_date, sk_id_curr, reason_code
  FROM   (SELECT sk_id_curr, rc_min_age, rc_arrears, rc_age_maturity, rc_pd, rc_debt, rc_limit_min
          FROM   decision_work)
  UNPIVOT (reason_code FOR rule_step IN (rc_min_age, rc_arrears, rc_age_maturity,
                                         rc_pd, rc_debt, rc_limit_min));   -- empty cells are skipped
  say(SQL%ROWCOUNT || ' reasons written');

  -- ---- 5. one decision per client ---------------------------------------------
  INSERT INTO decisions (
    run_date, sk_id_curr, run_id, split, decision, offer_limit,
    main_reason, all_reasons, reason_count, pd, age_years, current_dpd,
    income_amt, active_debt, income_multiple, grid_limit, debt_room,
    calc_limit, limit_basis, model_name, model_version)
  SELECT v_date, w.sk_id_curr, v_run_id, w.split,
         CASE WHEN r.reason_count IS NULL THEN 'APPROVE' ELSE 'DECLINE' END,
         CASE WHEN r.reason_count IS NULL THEN w.calc_limit END,
         r.main_reason, r.all_reasons, NVL(r.reason_count, 0),
         w.pd, w.age_years, w.current_dpd, w.income_amt, w.active_debt,
         w.income_multiple, w.grid_limit, w.debt_room, w.calc_limit, w.limit_basis,
         p_model_name, v_version
  FROM   decision_work w
  LEFT   JOIN (
           SELECT dr.sk_id_curr,
                  MIN(dr.reason_code) KEEP (DENSE_RANK FIRST ORDER BY c.priority, dr.reason_code) AS main_reason,
                  LISTAGG(dr.reason_code, ', ') WITHIN GROUP (ORDER BY c.priority, dr.reason_code) AS all_reasons,
                  COUNT(*) AS reason_count
           FROM   decision_reasons dr
           JOIN   ref_reason_codes c ON c.reason_code = dr.reason_code
           WHERE  dr.run_date = v_date
           GROUP  BY dr.sk_id_curr
         ) r ON r.sk_id_curr = w.sk_id_curr;

  SELECT COUNT(*) INTO v_approved FROM decisions WHERE run_date = v_date AND decision = 'APPROVE';

  UPDATE decision_runs
  SET    clients = v_population, approved = v_approved, status = 'DONE',
         finished_at = SYSTIMESTAMP,
         seconds = ROUND((CAST(SYSTIMESTAMP AS DATE) - CAST(v_started AS DATE)) * 86400)
  WHERE  run_id = v_run_id;
  COMMIT;                                                 -- also empties decision_work
  say(v_population || ' decisions written: ' || v_approved || ' approved, ' ||
      (v_population - v_approved) || ' declined');

EXCEPTION
  WHEN OTHERS THEN
    v_msg := SUBSTR(SQLERRM, 1, 4000);
    ROLLBACK;
    IF v_run_id IS NOT NULL THEN
      UPDATE decision_runs
      SET    status = 'FAILED', message = v_msg, finished_at = SYSTIMESTAMP,
             seconds = ROUND((CAST(SYSTIMESTAMP AS DATE) - CAST(v_started AS DATE)) * 86400)
      WHERE  run_id = v_run_id;
      COMMIT;
    END IF;
    RAISE;
END p_run_decisions;
/

-- A procedure with errors is still "created" in SQL*Plus; stop here instead.
SHOW ERRORS PROCEDURE p_run_decisions
DECLARE
  v_errors NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_errors FROM user_errors WHERE name = 'P_RUN_DECISIONS';
  IF v_errors > 0 THEN
    RAISE_APPLICATION_ERROR(-20031, 'p_run_decisions has compilation errors (listed above)');
  END IF;
END;
/

PROMPT 02_p_run_decisions: done
