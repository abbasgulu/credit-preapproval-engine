-- =====================================================================
-- 03_create_directory.sql
-- Tells Oracle where the raw CSV files are and lets HC read them.
--
-- Run from the repository root (the path is passed as an argument):
--   sqlplus / as sysdba @sql\00_setup\03_create_directory.sql "%CD%\data\raw"
--
-- READ  = HC can read the CSV files through external tables
-- WRITE = Oracle can write .log / .bad files for each external table
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE
SET VERIFY OFF
SET LINESIZE 200
COLUMN directory_name FORMAT A12
COLUMN directory_path FORMAT A90
COLUMN privilege      FORMAT A10

ALTER SESSION SET CONTAINER = XEPDB1;

CREATE OR REPLACE DIRECTORY hc_raw AS '&1';
GRANT READ, WRITE ON DIRECTORY hc_raw TO hc;

PROMPT
PROMPT ===== Directory =====
SELECT directory_name, directory_path FROM dba_directories WHERE directory_name = 'HC_RAW';

PROMPT
PROMPT ===== HC privileges on it =====
SELECT privilege FROM dba_tab_privs WHERE grantee = 'HC' AND table_name = 'HC_RAW' ORDER BY privilege;

EXIT
