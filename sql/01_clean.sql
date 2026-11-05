-- 01_clean.sql
-- Types the raw LendingClub file and defines which loans are safe to measure.

-- The raw file ends with 33 footer lines ("Total amount funded...") that are not loans.
-- Percent signs and text months are converted here, so later queries stay simple.
CREATE OR REPLACE TABLE loans AS
SELECT
    id                                             AS loan_id,
    TRY_CAST(funded_amnt AS DOUBLE)                AS funded,
    trim(term)                                     AS term,
    TRY_CAST(replace(int_rate, '%', '') AS DOUBLE) AS interest_rate,
    grade,
    sub_grade,
    purpose,
    home_ownership,
    verification_status,
    addr_state,
    TRY_CAST(annual_inc AS DOUBLE)                 AS annual_income,
    TRY_CAST(dti AS DOUBLE)                        AS dti,
    TRY_CAST(fico_range_low AS DOUBLE)             AS fico_low,
    TRY_CAST(inq_last_6mths AS DOUBLE)             AS inquiries_6m,
    strptime(issue_d, '%b-%Y')::DATE               AS issue_month,
    year(strptime(issue_d, '%b-%Y'))               AS vintage,
    loan_status,
    TRY_CAST(total_pymnt AS DOUBLE)                AS total_paid,
    TRY_CAST(total_rec_int AS DOUBLE)              AS interest_paid,
    try_strptime(last_pymnt_d, '%b-%Y')::DATE      AS last_payment_month
FROM raw_loans
WHERE issue_d IS NOT NULL;

-- Only loans that have had time to finish can show a true default rate.
-- Data ends in March 2019, so a 36-month loan issued by Dec 2015 has reached its end date.
-- 2012 is the start because earlier years are small. Counting recent vintages as they stand
-- would flatter them: their bad loans have not happened yet.
CREATE OR REPLACE TABLE matured AS
SELECT
    *,
    CASE WHEN loan_status IN ('Charged Off', 'Default') THEN 1 ELSE 0 END AS is_bad,
    total_paid - funded AS net_gain,
    CASE WHEN grade IN ('E', 'F', 'G') THEN 'E-G' ELSE grade END AS grade_group
FROM loans
WHERE term = '36 months'
  AND vintage BETWEEN 2012 AND 2015
  AND loan_status IN ('Fully Paid', 'Charged Off', 'Default');

-- Reconciliation from file to analysis population.
CREATE OR REPLACE TABLE dq_population AS
SELECT 1 AS step, 'Rows in raw file' AS item, COUNT(*) AS loans FROM raw_loans
UNION ALL SELECT 2, 'Less: footer lines', -COUNT(*) FROM raw_loans WHERE issue_d IS NULL
UNION ALL SELECT 3, 'Less: 60-month loans', -COUNT(*) FROM loans WHERE term = '60 months'
UNION ALL SELECT 4, 'Less: 36-month, issued before 2012', -COUNT(*) FROM loans WHERE term = '36 months' AND vintage < 2012
UNION ALL SELECT 5, 'Less: 36-month, issued after 2015 (not finished)', -COUNT(*) FROM loans WHERE term = '36 months' AND vintage > 2015
UNION ALL SELECT 6, 'Less: 2012-2015, still open or late', -COUNT(*) FROM loans
          WHERE term = '36 months' AND vintage BETWEEN 2012 AND 2015
            AND loan_status NOT IN ('Fully Paid', 'Charged Off', 'Default')
UNION ALL SELECT 7, 'Matured loans analysed', COUNT(*) FROM matured;
