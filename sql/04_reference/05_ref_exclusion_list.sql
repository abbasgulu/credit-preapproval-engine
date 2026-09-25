-- =====================================================================
-- 05_ref_exclusion_list.sql
-- Stage 4a: the exclusion list as data (improvement 1).
--
-- In plain words: some clients are not offered credit whatever their
-- score. Legacy procedures often keep such lists as IDs typed into the
-- code, so changing the list means changing and redeploying code. Here the
-- list is a table: each entry has a reason code and dates, and the engine
-- only reads it.
--
-- The Kaggle data has no fraud list, and none is invented. Entries are
-- derived from facts in the data: a credit at another lender that was
-- written off or sold to a collector (feat_bureau.bur_bad_status_cnt > 0).
-- Re-running adds new entries only; existing ones keep their dates.
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE

DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM user_tables WHERE table_name = 'REF_EXCLUSION_LIST';
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE TABLE ref_exclusion_list (
        sk_id_curr   NUMBER         NOT NULL,
        reason_code  VARCHAR2(30)   NOT NULL,
        source       VARCHAR2(200)  NOT NULL,
        valid_from   DATE           NOT NULL,
        valid_to     DATE,
        added_at     TIMESTAMP      NOT NULL,
        CONSTRAINT pk_ref_exclusion_list PRIMARY KEY (sk_id_curr, reason_code, valid_from),
        CONSTRAINT fk_exclusion_reason FOREIGN KEY (reason_code) REFERENCES ref_reason_codes (reason_code)
      )]';
    EXECUTE IMMEDIATE q'[COMMENT ON TABLE ref_exclusion_list IS 'Clients not offered credit whatever their score, with reason and validity dates. Maintained as data, never in code.']';
  END IF;
END;
/

MERGE INTO ref_exclusion_list t
USING (
  SELECT sk_id_curr FROM feat_bureau WHERE bur_bad_status_cnt > 0
) s
ON (t.sk_id_curr = s.sk_id_curr AND t.reason_code = 'EXCL_WRITTEN_OFF')
WHEN NOT MATCHED THEN INSERT (sk_id_curr, reason_code, source, valid_from, added_at)
     VALUES (s.sk_id_curr, 'EXCL_WRITTEN_OFF', 'feat_bureau.bur_bad_status_cnt > 0',
             DATE '2026-09-25', SYSTIMESTAMP);
COMMIT;

EXEC p_dq('REF_EXCLUSION_LIST', 'every client with a written-off credit is listed', 'SELECT COUNT(*) FROM feat_bureau f WHERE f.bur_bad_status_cnt > 0 AND NOT EXISTS (SELECT 1 FROM ref_exclusion_list e WHERE e.sk_id_curr = f.sk_id_curr AND e.reason_code = ''EXCL_WRITTEN_OFF'')', 0)

PROMPT 05_ref_exclusion_list: done
