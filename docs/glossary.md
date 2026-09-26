# Glossary

## In plain words

Every technical term used in this project, explained without jargon and with
an example. If a document uses a word you do not know, it should be here.

## Lending

| Term | Meaning | Example |
|---|---|---|
| **Pre-approval** | Deciding in advance that a person can get a loan, and up to what amount, before they formally apply | "You are pre-approved for up to 5,000" |
| **Default** | The borrower has serious trouble repaying | In this data: `TARGET = 1` — the client had payment difficulties |
| **PD** (probability of default) | The chance, from 0% to 100%, that a borrower will default | PD = 4% means about 4 out of 100 such borrowers default |
| **Instalment** | One scheduled repayment of a loan | A 12-month loan has 12 instalments |
| **Annuity** | The regular payment amount of a loan | 250 per month |
| **DPD** (days past due) | How many days a payment is late | Due on the 1st, paid on the 11th → 10 DPD |
| **Credit bureau** | A shared register where lenders report their clients' loans | Shows a client's loans at *other* lenders |
| **Utilisation** | How much of a credit-card limit is used | Balance 800, limit 1,000 → 80% |
| **Limit** | The maximum amount a client may borrow | |
| **Reject reason** | The main reason an application was declined, recorded at decision time | "Too many late payments in the last 12 months" |

## Data

| Term | Meaning | Example |
|---|---|---|
| **Raw layer** | Tables that hold the source files exactly as delivered, unchanged | `raw_bureau` = `bureau.csv` |
| **Feature** | One fact about a client that the model can use | Age, number of active loans, share of late payments |
| **Feature table** | A table with one row per client and one column per feature | `feat_customer` |
| **Grain** | What one row of a table represents | `raw_bureau`: one row = one loan; `feat_customer`: one row = one client |
| **Aggregation** | Turning many rows into one by counting, summing or averaging | 30 monthly rows of a loan → "worst month" |
| **Placeholder (365243)** | A fake value the source system uses for "no date" | `DAYS_EMPLOYED = 365243` means "not employed" |
| **NULL** | "Unknown" or "does not apply" in a database — not the same as zero | A client with no credit card has `NULL` utilisation, not 0% |
| **DQ check** (data quality) | An automatic test that stops the run if the data is wrong | "Every client appears exactly once" |
| **Data dictionary** | A list of all columns with their meaning | [data_dictionary.md](data_dictionary.md), generated from the database |
| **Snapshot** | A copy of a table as it was on a given date, kept for history | |

## Database

| Term | Meaning | Example |
|---|---|---|
| **Oracle** | The database system used to store and prepare the data | Oracle 18c Express Edition (free) |
| **Schema** | A named area in the database that owns a set of tables | All project tables belong to the schema `HC` |
| **SQL** | The language used to query and change data in a database | `SELECT COUNT(*) FROM feat_customer` |
| **External table** | A table that reads a CSV file directly, without importing it first | `ext_bureau` reads `bureau.csv` |
| **Oracle Wallet** | An encrypted file that holds the database password, so scripts connect without one | [setup_wallet.md](setup_wallet.md) |
| **Windows Credential Manager** | The password store built into Windows; Python reads the database password from it | [setup_wallet.md](setup_wallet.md) |
| **Partitioning** | Splitting a large table into parts, e.g. one part per date; one part can be emptied or refilled without touching the others | `decisions` has one part per run date |
| **Stored procedure** | A program saved inside the database and run there, next to the data | `p_run_decisions` makes all decisions |
| **Temporary table** | A table whose rows only the current session sees and which empties itself at the end of the transaction — a scratch pad | `decision_work` |
| **Transaction** | A group of changes that is saved all together or not at all | The engine writes all 356,255 decisions in one transaction: never half a run |
| **Fingerprint (hash)** | A short code computed from a text or file; any change to the content gives a different code | Two runs with the same rule-set fingerprint used exactly the same rules |

## Decisions

| Term | Meaning | Example |
|---|---|---|
| **Decision engine** | The program that turns each client's facts and PD into a decision, a limit and reasons, using only rules stored as data | [stage4_design.md](stage4_design.md) |
| **Exclusion list** | Clients who get no offer whatever their score, each with a reason code | A credit at another lender was written off |
| **Policy rule** | An eligibility rule that is a lender's choice, not a risk estimate | Age at the end of the offer at most 70 |
| **Cut-off** | The highest PD that can still be approved | PD cut-off 14.5%: a client with PD 15% is declined |
| **Limit grid** | A table of income multiples by risk band and income band; lower risk and higher income give a higher multiple | PD under 2%, income 100k–250k → 3 × income |
| **Reason code** | A short code for why a client was declined, with a plain-words description and a priority | `PD_ABOVE_CUTOFF`: estimated chance of repayment trouble is above the accepted level |
| **Main reason** | Of all reasons that applied, the one with the highest priority (lowest number) | Excluded and too risky → main reason is the exclusion |

## Model

| Term | Meaning | Example |
|---|---|---|
| **Model** | A formula learned from past data that estimates something for new cases | Estimates a client's PD |
| **Training** | Letting the model learn from clients whose outcome is known | |
| **Holdout** | Clients kept aside and shown to the model only at the very end, as a final exam | 15% of the known clients |
| **Overfitting** | Memorising the training clients instead of learning general patterns — the model then fails on new clients | Like memorising answers instead of understanding the subject |
| **Scorecard** | A model that gives points for each answer and adds them up | Age 21–25: 10 points; age 46–55: 35 points |
| **Logistic regression** | The classic formula behind a scorecard; turns a sum of points into a probability | |
| **WoE** (weight of evidence) | A number for each group of a feature: positive = fewer defaults than average, negative = more | |
| **IV** (information value) | How much a feature tells us about default, as one number | Below 0.02 = useless, above 0.3 = strong |
| **LightGBM** | A model made of hundreds of small decision trees that vote together; usually very accurate | |
| **Early stopping** | Stop adding trees when the model stops improving on data it did not learn from | Prevents overfitting |
| **SHAP** | A method that shows how much each feature pushed one prediction up or down | "Late payments added +3% to this client's PD" |
| **Gini** | How well the model ranks risky clients above safe ones: 0 = coin toss, 1 = perfect | Credit models are typically 0.4–0.7 |
| **AUC** | Another scale for the same idea as Gini: Gini = 2 × AUC − 1 | AUC 0.75 = Gini 0.50 |
| **KS** | The largest gap between the score distributions of good and bad clients | |
| **Raw score** | A model's output before it is turned into a probability, on the "log-odds" scale: 0 = 50%, higher = riskier | Raw score -2.4 ≈ 8% |
| **Platt scaling** | The calibration method used here: two numbers (a, b) adjust the raw score, PD = 1 / (1 + exp(-(a + b × raw score))) | [calibration.md](calibration.md) |
| **Calibration** | Adjusting the model so its probabilities match reality | A group given 5% should default about 5% of the time |
| **Brier score** | The average squared error of the predicted probabilities; lower is better | |
| **PSI** (population stability index) | Whether new applicants look like the clients the model learned from | Below 0.1 = stable, above 0.25 = the model needs review |
| **Fairness** | Making sure a model does not treat people differently for reasons that are unfair or illegal | Gender is not used ([decision 13](decisions.md)) |
