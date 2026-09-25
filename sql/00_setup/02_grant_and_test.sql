-- =====================================================================
-- 02_grant_and_test.sql
-- 1) (Re)grants the project privileges to HC — re-granting is harmless
-- 2) Connects as HC and proves it can log in, create, write and drop
--
-- Run from the repository root:
--   sqlplus / as sysdba @sql\00_setup\02_grant_and_test.sql
--
-- Asks for the HC password (the one set in 01_create_user.sql).
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET VERIFY OFF
SET FEEDBACK ON
SET LINESIZE 120
SET PAGESIZE 50
COLUMN username           FORMAT A10
COLUMN account_status     FORMAT A10
COLUMN default_tablespace FORMAT A12
COLUMN privilege          FORMAT A30
COLUMN tablespace_name    FORMAT A12
COLUMN quota              FORMAT A12
COLUMN note               FORMAT A20

ALTER SESSION SET CONTAINER = XEPDB1;

PROMPT
PROMPT ===== 1. Current container =====
SHOW CON_NAME

PROMPT
PROMPT ===== 2. Granting privileges =====
GRANT CREATE SESSION           TO hc;
GRANT CREATE TABLE             TO hc;
GRANT CREATE VIEW              TO hc;
GRANT CREATE PROCEDURE         TO hc;
GRANT CREATE SEQUENCE          TO hc;
GRANT CREATE MATERIALIZED VIEW TO hc;
GRANT CREATE SYNONYM           TO hc;
GRANT CREATE TYPE              TO hc;
ALTER USER hc QUOTA UNLIMITED ON users;

PROMPT
PROMPT ===== 3. As admin: HC privileges =====
SELECT privilege FROM dba_sys_privs WHERE grantee = 'HC' ORDER BY privilege;

PROMPT
PROMPT ===== 4. As admin: HC quota =====
SELECT tablespace_name,
       CASE max_bytes WHEN -1 THEN 'UNLIMITED' ELSE TO_CHAR(max_bytes) END AS quota
FROM   dba_ts_quotas
WHERE  username = 'HC';

-- ---------------------------------------------------------------------
-- Connect as HC. Without CREATE SESSION this fails with ORA-01045.
-- ---------------------------------------------------------------------
PROMPT
PROMPT ===== 5. Connecting as HC =====
ACCEPT hc_password CHAR PROMPT 'HC password: ' HIDE
CONNECT hc/"&hc_password"@localhost:1521/XEPDB1

PROMPT
PROMPT ===== 6. As HC: active privileges =====
SELECT privilege FROM session_privs ORDER BY privilege;

PROMPT
PROMPT ===== 7. Write test: create -> insert -> select -> drop =====
CREATE TABLE zz_test (id NUMBER, note VARCHAR2(20));
INSERT INTO zz_test VALUES (1, 'works');
COMMIT;
SELECT * FROM zz_test;
DROP TABLE zz_test PURGE;

PROMPT
PROMPT ===== DONE: HC is ready =====
EXIT
