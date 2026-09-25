-- =====================================================================
-- 04_ref_limit_grid.sql
-- Stage 4a: the limit matrix as a table, checked for gaps and overlaps
-- (improvement 3).
--
-- In plain words: the offer is a multiple of the client's income, higher
-- for lower risk and for higher income. Legacy code often writes such a
-- matrix as a long CASE statement, where a boundary typed twice or not at
-- all silently gives some clients no limit or two. Here the matrix is rows
-- in a table, and two checks prove that every combination of PD and income
-- falls into exactly one cell.
--
-- Cell: pd_from <= PD < pd_to  (the last band includes PD = 1)
--       income_from <= income < income_to  (income_to NULL = no upper bound)
-- Values are ILLUSTRATIVE (decision 25).
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE

DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM user_tables WHERE table_name = 'REF_LIMIT_GRID';
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE TABLE ref_limit_grid (
        pd_from          NUMBER  NOT NULL,
        pd_to            NUMBER  NOT NULL,
        income_from      NUMBER  NOT NULL,
        income_to        NUMBER,
        income_multiple  NUMBER  NOT NULL,
        valid_from       DATE    NOT NULL,
        valid_to         DATE,
        CONSTRAINT pk_ref_limit_grid PRIMARY KEY (valid_from, pd_from, income_from),
        CONSTRAINT ck_grid_pd CHECK (pd_from >= 0 AND pd_to <= 1 AND pd_from < pd_to),
        CONSTRAINT ck_grid_income CHECK (income_from >= 0 AND (income_to IS NULL OR income_from < income_to))
      )]';
    EXECUTE IMMEDIATE q'[COMMENT ON TABLE ref_limit_grid IS 'Limit = income_multiple x income, per PD band and income band. Checked for gaps and overlaps by the grid DQ checks.']';
  END IF;
END;
/

-- 5 PD bands x 3 income bands; lower PD and higher income -> higher multiple
MERGE INTO ref_limit_grid t
USING (
  WITH pd_band AS (
    SELECT 1 AS b, 0.00 AS pd_from, 0.02 AS pd_to FROM dual UNION ALL
    SELECT 2, 0.02, 0.04 FROM dual UNION ALL
    SELECT 3, 0.04, 0.07 FROM dual UNION ALL
    SELECT 4, 0.07, 0.12 FROM dual UNION ALL
    SELECT 5, 0.12, 1.00 FROM dual
  ),
  inc_band AS (
    SELECT 1 AS i, 0 AS income_from, 100000 AS income_to FROM dual UNION ALL
    SELECT 2, 100000, 250000 FROM dual UNION ALL
    SELECT 3, 250000, NULL FROM dual
  ),
  mult AS (   -- rows = PD band, columns = income band
    SELECT 1 AS b, 2.0 AS m1, 3.0 AS m2, 4.0 AS m3 FROM dual UNION ALL
    SELECT 2, 1.5, 2.5, 3.5 FROM dual UNION ALL
    SELECT 3, 1.0, 2.0, 3.0 FROM dual UNION ALL
    SELECT 4, 0.75, 1.5, 2.0 FROM dual UNION ALL
    SELECT 5, 0.5, 1.0, 1.0 FROM dual
  )
  SELECT p.pd_from, p.pd_to, i.income_from, i.income_to,
         CASE i.i WHEN 1 THEN m.m1 WHEN 2 THEN m.m2 ELSE m.m3 END AS income_multiple
  FROM   pd_band p CROSS JOIN inc_band i JOIN mult m ON m.b = p.b
) s
ON (t.valid_from = DATE '2026-09-25' AND t.pd_from = s.pd_from AND t.income_from = s.income_from)
WHEN NOT MATCHED THEN INSERT (pd_from, pd_to, income_from, income_to, income_multiple, valid_from)
     VALUES (s.pd_from, s.pd_to, s.income_from, s.income_to, s.income_multiple, DATE '2026-09-25');
COMMIT;

-- ---------------------------------------------------------------------
-- The grid checks: every PD in [0, 1] and every income >= 0 must fall in
-- exactly one cell of the grid in force. A gap or an overlap stops the run.
-- ---------------------------------------------------------------------
EXEC p_dq('REF_LIMIT_GRID', 'PD bands: no gap, no overlap, cover 0..1 (per income band)', 'SELECT COUNT(*) FROM (SELECT pd_from, pd_to, LAG(pd_to) OVER (PARTITION BY income_from ORDER BY pd_from) AS prev_to, ROW_NUMBER() OVER (PARTITION BY income_from ORDER BY pd_from) AS rn, COUNT(*) OVER (PARTITION BY income_from) AS cnt FROM ref_limit_grid WHERE valid_to IS NULL) WHERE (rn = 1 AND pd_from <> 0) OR (rn > 1 AND pd_from <> prev_to) OR (rn = cnt AND pd_to <> 1)', 0)
EXEC p_dq('REF_LIMIT_GRID', 'income bands: no gap, no overlap, open-ended top (per PD band)', 'SELECT COUNT(*) FROM (SELECT income_from, income_to, LAG(income_to) OVER (PARTITION BY pd_from ORDER BY income_from) AS prev_to, ROW_NUMBER() OVER (PARTITION BY pd_from ORDER BY income_from) AS rn, COUNT(*) OVER (PARTITION BY pd_from) AS cnt FROM ref_limit_grid WHERE valid_to IS NULL) WHERE (rn = 1 AND income_from <> 0) OR (rn > 1 AND (prev_to IS NULL OR income_from <> prev_to)) OR (rn = cnt AND income_to IS NOT NULL) OR (rn < cnt AND income_to IS NULL)', 0)
EXEC p_dq('REF_LIMIT_GRID', 'lower PD never gets a lower multiple (same income band)', 'SELECT COUNT(*) FROM (SELECT income_multiple, LAG(income_multiple) OVER (PARTITION BY income_from ORDER BY pd_from) AS prev_m FROM ref_limit_grid WHERE valid_to IS NULL) WHERE income_multiple > prev_m', 0)

PROMPT 04_ref_limit_grid: done
