-- =====================================================================
-- _connect.sql
-- The ONE place where every script connects to the database as HC.
-- Called at the top of each runner:  @sql\_connect.sql
--
-- Oracle Wallet (Secure External Password Store): the HC password is
-- kept encrypted in a wallet outside this repository, so no password is
-- typed and none is stored in any script.
--
-- One-time setup, and the alternative for machines without a wallet:
-- docs/setup_wallet.md
-- =====================================================================

CONNECT /@hc_xepdb1
