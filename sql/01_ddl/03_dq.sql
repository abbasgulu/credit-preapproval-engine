-- =====================================================================
-- 03_dq.sql
-- Data-quality tools used after every feature table (improvement 6).
--
--   dq_log          - one row per check: expected vs actual, passed Y/N
--   p_dq            - runs a query that returns one number and compares it
--                     with the expected value. severity ERROR stops the run,
--                     WARN only records the result
--   p_dq_unique     - key is unique (duplicates = 0)
--   p_dq_rowcount   - table has the expected number of rows
--   p_dq_range      - no value of a column outside [min, max]
--   v_population    - the 356,255 clients every feature table must cover
--
-- dq_log is created only if it does not exist, so the history is kept.
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE

DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM user_tables WHERE table_name = 'DQ_LOG';
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE TABLE dq_log (
        dq_id       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        table_name  VARCHAR2(30)   NOT NULL,
        check_name  VARCHAR2(200)  NOT NULL,
        severity    VARCHAR2(5)    NOT NULL,
        expected    NUMBER,
        actual      NUMBER,
        passed      CHAR(1)        NOT NULL,
        checked_at  TIMESTAMP      NOT NULL
      )]';
    EXECUTE IMMEDIATE q'[COMMENT ON TABLE dq_log IS 'One row per data-quality check: expected vs actual value. ERROR checks stop the run when they fail.']';
  END IF;
END;
/

CREATE OR REPLACE PROCEDURE p_dq (
  p_table    IN VARCHAR2,
  p_check    IN VARCHAR2,
  p_sql      IN VARCHAR2,
  p_expected IN NUMBER,
  p_severity IN VARCHAR2 DEFAULT 'ERROR'
) AS
  v_actual NUMBER;
  v_passed CHAR(1);
BEGIN
  EXECUTE IMMEDIATE p_sql INTO v_actual;
  v_passed := CASE WHEN v_actual = p_expected THEN 'Y' ELSE 'N' END;

  INSERT INTO dq_log (table_name, check_name, severity, expected, actual, passed, checked_at)
  VALUES (UPPER(p_table), p_check, p_severity, p_expected, v_actual, v_passed, SYSTIMESTAMP);
  COMMIT;

  IF v_passed = 'N' AND p_severity = 'ERROR' THEN
    RAISE_APPLICATION_ERROR(-20010,
      'DQ FAILED ' || p_table || ' / ' || p_check ||
      ': expected ' || p_expected || ', got ' || v_actual);
  END IF;
END;
/

CREATE OR REPLACE PROCEDURE p_dq_unique (p_table IN VARCHAR2, p_key IN VARCHAR2 DEFAULT 'SK_ID_CURR') AS
  v_t VARCHAR2(128) := DBMS_ASSERT.SIMPLE_SQL_NAME(p_table);
  v_k VARCHAR2(128) := DBMS_ASSERT.SIMPLE_SQL_NAME(p_key);
BEGIN
  p_dq(p_table, 'unique ' || v_k,
       'SELECT COUNT(*) - COUNT(DISTINCT ' || v_k || ') FROM ' || v_t, 0);
END;
/

CREATE OR REPLACE PROCEDURE p_dq_rowcount (p_table IN VARCHAR2, p_expected IN NUMBER) AS
  v_t VARCHAR2(128) := DBMS_ASSERT.SIMPLE_SQL_NAME(p_table);
BEGIN
  p_dq(p_table, 'row count', 'SELECT COUNT(*) FROM ' || v_t, p_expected);
END;
/

CREATE OR REPLACE PROCEDURE p_dq_range (
  p_table  IN VARCHAR2,
  p_column IN VARCHAR2,
  p_min    IN NUMBER,
  p_max    IN NUMBER
) AS
  v_t   VARCHAR2(128) := DBMS_ASSERT.SIMPLE_SQL_NAME(p_table);
  v_c   VARCHAR2(128) := DBMS_ASSERT.SIMPLE_SQL_NAME(p_column);
  v_min VARCHAR2(50)  := TO_CHAR(p_min, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,''');
  v_max VARCHAR2(50)  := TO_CHAR(p_max, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,''');
BEGIN
  p_dq(p_table, v_c || ' in [' || v_min || ', ' || v_max || ']',
       'SELECT COUNT(*) FROM ' || v_t || ' WHERE ' || v_c || ' < ' || v_min ||
       ' OR ' || v_c || ' > ' || v_max, 0);
END;
/

CREATE OR REPLACE VIEW v_population AS
SELECT sk_id_curr, 'train' AS dataset, target FROM raw_application_train
UNION ALL
SELECT sk_id_curr, 'test'  AS dataset, CAST(NULL AS NUMBER) AS target FROM raw_application_test;

COMMENT ON TABLE v_population IS 'All 356,255 clients: train (known TARGET) and test (treated as incoming applicants).';

PROMPT 03_dq: done
