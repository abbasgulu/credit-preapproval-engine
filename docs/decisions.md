# Decision log

One line per decision: what was decided and why. Newest at the bottom.

| # | Date | Decision | Reason |
|---|---|---|---|
| 1 | 2026-09-25 | Use the Kaggle *Home Credit Default Risk* dataset | Public, realistic credit data with application, bureau, payment and card history — close to a real pre-approval setting |
| 2 | 2026-09-25 | Database: Oracle 18c XE, pluggable database `XEPDB1` | Data belongs in the PDB, not the container root |
| 3 | 2026-09-25 | Dedicated schema `HC` instead of working as `SYSTEM` | Keeps project objects separate from system objects; the whole project can be removed with one command |
| 4 | 2026-09-25 | GitHub is the single source of truth | Tableau Public, Kaggle and LinkedIn receive copies from the repo and link back to it |
| 5 | 2026-09-25 | Raw data is not committed | GitHub file size limit and Kaggle licence; `data/README.md` explains how to download it |
| 6 | 2026-09-25 | Repository language: English | Readable by international reviewers and the Kaggle/GitHub community |
| 7 | 2026-09-25 | Load CSVs through Oracle external tables (`ext_*` → `raw_*`) | Pure SQL, no extra tools; the CSV can be queried before loading; type conversion is explicit and fails loudly |
| 8 | 2026-09-25 | External tables use an explicit record delimiter per file (`0x'0A'` or `0x'0D0A'`) | Oracle 18c has no `DETECTED NEWLINE`; line endings were measured: the Kaggle data files use LF, the column description file uses CRLF |
| 9 | 2026-09-25 | `365243` in `DAYS_*` columns → `NULL` + explicit flag (e.g. `is_not_employed`), in the feature layer only | Measured: in `DAYS_EMPLOYED` it marks all pensioners and unemployed clients, whose default rate is 5.40% vs 8.66% — the information is kept as a flag, while `NULL` keeps averages and linear models correct. The raw layer stays unchanged. See [data_profiling.md](data_profiling.md) |
| 10 | 2026-09-25 | `installments_payments` is aggregated in two steps: payment rows → one row per instalment → one row per client | Measured: 13,605,401 rows describe 12,951,918 instalments — 629,210 instalments were paid in 2 rows, some in up to 12. Counting rows directly would inflate instalment counts by 653,483 and mark a split payment as "underpaid". A DQ check proves the client table sums back to 12,951,918 instalments |
| 11 | 2026-09-25 | `previous_application` keeps only rows with `FLAG_LAST_APPL_PER_CONTRACT = 'Y'` and `NFLAG_LAST_APPL_IN_DAY = 1` | Kaggle documents that one contract can have several applications and that some applications are repeated within a day. Measured: 8,475 and 5,900 such rows. Without the filter, application and refusal counts are inflated |
| 12 | 2026-09-25 | Bureau burden is measured as active debt / income (`bur_debt_to_income`); the bureau annuity sum is kept but documented as understated | Measured: `AMT_ANNUITY` is reported for only 22.2% of active bureau credits (431,549 NULL, 59,259 zero of 630,607), so a monthly obligation built from it would look lower than it is. Debt (`AMT_CREDIT_SUM_DEBT`) is reported far more consistently |
| 13 | 2026-09-25 | Gender (`CODE_GENDER`) is not used as a feature | Fair lending: many jurisdictions prohibit using sex in credit decisions, and a model that sees it can give two otherwise identical applicants different outcomes. The column stays in the raw layer only |
| 14 | 2026-09-25 | Scripts connect through an Oracle Wallet (`CONNECT /@hc_xepdb1`), from one shared file `sql/_connect.sql` | No password is typed or stored in any script; the encrypted wallet lives outside the repository. Connection logic is in one place instead of being repeated in every runner. See [setup_wallet.md](setup_wallet.md) |
