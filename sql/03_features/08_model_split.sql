-- =====================================================================
-- 08_model_split.sql
-- Stage 3b: which clients the model learns from, and which it is tested on.
--
-- In plain words: the 307,511 clients with a known outcome are divided
-- into three groups - 70% to learn from (fit), 15% to tune (valid) and 15%
-- kept aside as a final exam (holdout). The 48,744 clients without a known
-- outcome (test) play the role of new applicants.
--
-- The group is computed from a hash of the client ID (ORA_HASH): the same
-- client always lands in the same group, on any machine, with no random
-- seed to remember (decision 17). Every tool reads the same view, so SQL,
-- Python, Dataiku and Tableau all use exactly the same split.
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE

PROMPT
PROMPT ===== v_model_input =====
CREATE OR REPLACE VIEW v_model_input AS
SELECT CASE
         WHEN f.dataset = 'test'               THEN 'test'
         WHEN ORA_HASH(f.sk_id_curr, 99) < 70  THEN 'fit'       -- buckets 0-69
         WHEN ORA_HASH(f.sk_id_curr, 99) < 85  THEN 'valid'     -- buckets 70-84
         ELSE                                       'holdout'   -- buckets 85-99
       END AS split,
       f.*
FROM   feat_customer f;

SET FEEDBACK OFF
COMMENT ON TABLE v_model_input IS 'feat_customer + split: the single input of the model (Stage 3). One row per client.';
COMMENT ON COLUMN v_model_input.split IS 'fit 70% / valid 15% / holdout 15% of train clients (ORA_HASH of SK_ID_CURR); test = clients without a known outcome.';
SET FEEDBACK ON

-- ---------------------------------------------------------------------
-- Checks: sizes and default rates must be close to what was intended.
-- Tolerance for the default rate: 0.5 percentage points (about 4 standard
-- errors for a group of 46,000 clients with an 8% default rate).
-- ---------------------------------------------------------------------
EXEC p_dq_rowcount('V_MODEL_INPUT', 356255)
EXEC p_dq('V_MODEL_INPUT', 'test rows = 48,744', 'SELECT COUNT(*) FROM v_model_input WHERE split = ''test''', 48744)
EXEC p_dq('V_MODEL_INPUT', 'fit share of train in [69%, 71%]', 'SELECT CASE WHEN AVG(CASE WHEN split = ''fit'' THEN 1 ELSE 0 END) BETWEEN 0.69 AND 0.71 THEN 1 ELSE 0 END FROM v_model_input WHERE dataset = ''train''', 1)
EXEC p_dq('V_MODEL_INPUT', 'valid share of train in [14%, 16%]', 'SELECT CASE WHEN AVG(CASE WHEN split = ''valid'' THEN 1 ELSE 0 END) BETWEEN 0.14 AND 0.16 THEN 1 ELSE 0 END FROM v_model_input WHERE dataset = ''train''', 1)
EXEC p_dq('V_MODEL_INPUT', 'holdout share of train in [14%, 16%]', 'SELECT CASE WHEN AVG(CASE WHEN split = ''holdout'' THEN 1 ELSE 0 END) BETWEEN 0.14 AND 0.16 THEN 1 ELSE 0 END FROM v_model_input WHERE dataset = ''train''', 1)
EXEC p_dq('V_MODEL_INPUT', 'default rate of every split within 0.5 pp of train', 'SELECT CASE WHEN MAX(ABS(s.rate - t.rate)) <= 0.005 THEN 1 ELSE 0 END FROM (SELECT AVG(target) AS rate FROM v_model_input WHERE dataset = ''train'' GROUP BY split) s CROSS JOIN (SELECT AVG(target) AS rate FROM v_model_input WHERE dataset = ''train'') t', 1)

PROMPT
PROMPT ===== The split =====
COLUMN split FORMAT A8
SELECT split,
       COUNT(*)                                          AS clients,
       ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 1) AS pct_of_all,
       SUM(target)                                       AS defaults,
       ROUND(100 * AVG(target), 2)                       AS default_pct
FROM   v_model_input
GROUP  BY split
ORDER  BY DECODE(split, 'fit', 1, 'valid', 2, 'holdout', 3, 4);

PROMPT 08_model_split: done
