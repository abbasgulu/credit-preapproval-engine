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
