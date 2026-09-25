-- =====================================================================
-- 01_create_user.sql
-- Creates the project schema HC in the pluggable database XEPDB1.
--
-- Run from the repository root:
--   sqlplus / as sysdba @sql\00_setup\01_create_user.sql
--
-- The script asks for a password; it is not echoed and not stored.
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
COLUMN autoext            FORMAT A7

-- 1) Switch to the pluggable database that holds user data
ALTER SESSION SET CONTAINER = XEPDB1;

-- 2) Ask for the password (HIDE = not shown while typing)
ACCEPT hc_password CHAR PROMPT 'Password for HC: ' HIDE

-- 3) Create the user
CREATE USER hc IDENTIFIED BY "&hc_password"
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;

-- 4) Privileges needed by the project
GRANT CREATE SESSION           TO hc;   -- connect
GRANT CREATE TABLE             TO hc;   -- tables
GRANT CREATE VIEW              TO hc;   -- views
GRANT CREATE PROCEDURE         TO hc;   -- procedures and functions
GRANT CREATE SEQUENCE          TO hc;   -- sequences
GRANT CREATE MATERIALIZED VIEW TO hc;   -- materialized views
GRANT CREATE SYNONYM           TO hc;   -- synonyms
GRANT CREATE TYPE              TO hc;   -- object types

-- 5) Checks
PROMPT
PROMPT ===== HC user =====
SELECT username, account_status, default_tablespace, created
FROM   dba_users
WHERE  username = 'HC';

PROMPT
PROMPT ===== HC privileges =====
SELECT privilege
FROM   dba_sys_privs
WHERE  grantee = 'HC'
ORDER  BY privilege;

PROMPT
PROMPT ===== Tablespaces =====
SELECT tablespace_name,
       ROUND(SUM(bytes)    / 1024 / 1024) AS current_mb,
       ROUND(SUM(maxbytes) / 1024 / 1024) AS max_mb,
       MAX(autoextensible)                AS autoext
FROM   dba_data_files
GROUP  BY tablespace_name
ORDER  BY tablespace_name;

EXIT
