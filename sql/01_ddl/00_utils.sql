-- =====================================================================
-- 00_utils.sql
-- Helper objects used by every later script.
--
--   p_drop_if_exists  - drops a table only if it exists (Oracle 18c has no
--                       DROP TABLE IF EXISTS), so every script can be re-run
--   raw_load_log      - one row per table load: expected vs actual rows
--   p_load_start/end  - write to raw_load_log; p_load_end STOPS the run if
--                       the row count does not match (no silent failures)
--
-- Safe to re-run: the log table is created only if it does not exist yet,
-- so the load history is kept.
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE

CREATE OR REPLACE PROCEDURE p_drop_if_exists (p_table IN VARCHAR2) AS
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE ' || DBMS_ASSERT.SIMPLE_SQL_NAME(p_table) || ' PURGE';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -942 THEN   -- -942 = table does not exist -> nothing to do
      RAISE;
    END IF;
END;
/

DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM user_tables WHERE table_name = 'RAW_LOAD_LOG';
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE TABLE raw_load_log (
        load_id       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        table_name    VARCHAR2(30)  NOT NULL,
        expected_rows NUMBER        NOT NULL,
        actual_rows   NUMBER,
        status        VARCHAR2(10)  NOT NULL,
        started_at    TIMESTAMP     NOT NULL,
        finished_at   TIMESTAMP,
        seconds       NUMBER
      )]';
    EXECUTE IMMEDIATE q'[COMMENT ON TABLE raw_load_log IS 'One row per raw table load: expected vs actual row count and duration.']';
  END IF;
END;
/

CREATE OR REPLACE PROCEDURE p_load_start (p_table IN VARCHAR2, p_expected IN NUMBER) AS
BEGIN
  INSERT INTO raw_load_log (table_name, expected_rows, status, started_at)
  VALUES (UPPER(p_table), p_expected, 'RUNNING', SYSTIMESTAMP);
  COMMIT;
END;
/

CREATE OR REPLACE PROCEDURE p_load_end (p_table IN VARCHAR2) AS
  v_actual   NUMBER;
  v_expected NUMBER;
  v_id       NUMBER;
  v_status   VARCHAR2(10);
BEGIN
  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || DBMS_ASSERT.SIMPLE_SQL_NAME(p_table) INTO v_actual;

  SELECT load_id, expected_rows INTO v_id, v_expected
  FROM   raw_load_log
  WHERE  load_id = (SELECT MAX(load_id) FROM raw_load_log WHERE table_name = UPPER(p_table));

  v_status := CASE WHEN v_actual = v_expected THEN 'OK' ELSE 'MISMATCH' END;

  UPDATE raw_load_log
  SET    actual_rows = v_actual,
         status      = v_status,
         finished_at = SYSTIMESTAMP,
         seconds     = ROUND(EXTRACT(DAY    FROM (SYSTIMESTAMP - started_at)) * 86400
                          + EXTRACT(HOUR   FROM (SYSTIMESTAMP - started_at)) * 3600
                          + EXTRACT(MINUTE FROM (SYSTIMESTAMP - started_at)) * 60
                          + EXTRACT(SECOND FROM (SYSTIMESTAMP - started_at)), 1)
  WHERE  load_id = v_id;
  COMMIT;

  IF v_status != 'OK' THEN
    RAISE_APPLICATION_ERROR(-20001,
      p_table || ': expected ' || v_expected || ' rows, loaded ' || v_actual);
  END IF;
END;
/

PROMPT 00_utils: done
