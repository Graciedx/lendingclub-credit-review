-- 02_analysis.sql
-- Each mart_ table answers one question and feeds the Power BI dashboard.
-- Total return = (all money received - amount funded) / amount funded, over the life of the loan.
-- It is not annualised, and it is before LendingClub's servicing fee.

-- Q1. Is the book getting better or worse as it grows?
CREATE OR REPLACE TABLE mart_vintage AS
SELECT
    vintage,
    COUNT(*)                                     AS loans,
    ROUND(SUM(funded) / 1e6, 1)                  AS funded_musd,
    ROUND(AVG(interest_rate), 2)                 AS avg_rate_pct,
    ROUND(100.0 * AVG(is_bad), 1)                AS default_rate_pct,
    ROUND(100.0 * SUM(net_gain) / SUM(funded), 1) AS total_return_pct,
    ROUND(SUM(net_gain) / 1e6, 1)                AS net_gain_musd
FROM matured GROUP BY vintage ORDER BY vintage;

-- Q2. Does a riskier grade still pay more?
CREATE OR REPLACE TABLE mart_grade_vintage AS
SELECT
    grade_group,
    vintage,
    COUNT(*)                                      AS loans,
    ROUND(SUM(funded) / 1e6, 1)                   AS funded_musd,
    ROUND(AVG(interest_rate), 2)                  AS avg_rate_pct,
    ROUND(100.0 * AVG(is_bad), 1)                 AS default_rate_pct,
    ROUND(100.0 * SUM(net_gain) / SUM(funded), 1) AS total_return_pct,
    ROUND(SUM(net_gain) / 1e6, 2)                 AS net_gain_musd
FROM matured GROUP BY grade_group, vintage ORDER BY grade_group, vintage;

-- Q3. Inside a grade, what separates weak loans from strong ones?
-- Only facts known on application day are used. Payment fields would leak the outcome.
CREATE OR REPLACE TABLE mart_drivers AS
WITH labelled AS (
    SELECT *,
        CASE WHEN dti < 10 THEN '0-10' WHEN dti < 20 THEN '10-20' WHEN dti < 30 THEN '20-30' ELSE '30+' END AS dti_band,
        CASE WHEN inquiries_6m = 0 THEN '0' WHEN inquiries_6m = 1 THEN '1'
             WHEN inquiries_6m = 2 THEN '2' ELSE '3+' END AS inquiry_band,
        CASE WHEN fico_low < 680 THEN '660-679' WHEN fico_low < 700 THEN '680-699'
             WHEN fico_low < 720 THEN '700-719' ELSE '720+' END AS fico_band
    FROM matured
), unpivoted AS (
    SELECT 'DTI' AS driver, dti_band AS band, grade_group, is_bad, net_gain, funded, vintage FROM labelled
    UNION ALL SELECT 'Credit inquiries (6m)', inquiry_band, grade_group, is_bad, net_gain, funded, vintage FROM labelled
    UNION ALL SELECT 'FICO', fico_band, grade_group, is_bad, net_gain, funded, vintage FROM labelled
    UNION ALL SELECT 'Purpose', purpose, grade_group, is_bad, net_gain, funded, vintage FROM labelled
    UNION ALL SELECT 'Home ownership', home_ownership, grade_group, is_bad, net_gain, funded, vintage FROM labelled
)
SELECT driver, band, grade_group, vintage,
       COUNT(*) AS loans,
       SUM(funded) AS funded,
       SUM(is_bad) AS bad_loans,
       SUM(net_gain) AS net_gain
FROM unpivoted
GROUP BY driver, band, grade_group, vintage
ORDER BY driver, band, grade_group, vintage;

-- Q4. Test a tighter lending rule. The rule was picked by looking at vintages up to 2014.
-- 2015 is the out-of-sample test.
CREATE OR REPLACE TABLE mart_rule_backtest AS
WITH flagged AS (
    SELECT *,
        CASE WHEN grade_group = 'E-G' AND (dti >= 20 OR inquiries_6m >= 2) THEN 1 ELSE 0 END AS rule_hit
    FROM matured
)
SELECT
    vintage,
    COUNT(*)                                                      AS all_loans,
    SUM(rule_hit)                                                 AS loans_hit,
    ROUND(100.0 * SUM(rule_hit) / COUNT(*), 1)                    AS pct_loans_hit,
    ROUND(SUM(funded) FILTER (WHERE rule_hit = 1) / 1e6, 1)       AS funded_hit_musd,
    ROUND(100.0 * SUM(is_bad) FILTER (WHERE rule_hit = 1) / SUM(is_bad), 1) AS pct_of_bad_loans_caught,
    ROUND(100.0 * AVG(is_bad) FILTER (WHERE rule_hit = 1), 1)     AS default_rate_hit_pct,
    ROUND(100.0 * SUM(net_gain) FILTER (WHERE rule_hit = 1) / SUM(funded) FILTER (WHERE rule_hit = 1), 1) AS return_hit_pct,
    ROUND(100.0 * AVG(is_bad), 1)                                 AS default_rate_all_pct,
    ROUND(100.0 * AVG(is_bad) FILTER (WHERE rule_hit = 0), 1)     AS default_rate_after_rule_pct,
    ROUND(100.0 * SUM(net_gain) / SUM(funded), 2)                 AS return_all_pct,
    ROUND(100.0 * SUM(net_gain) FILTER (WHERE rule_hit = 0) / SUM(funded) FILTER (WHERE rule_hit = 0), 2) AS return_after_rule_pct
FROM flagged GROUP BY vintage ORDER BY vintage;

-- Q5. How much would rates need to rise for E-G to match grade A on 2015 loans?
-- Pass-through = interest actually collected per 1 point of rate per dollar funded.
-- This holds defaults fixed, so the answer is a minimum, not a forecast.
CREATE OR REPLACE TABLE mart_repricing AS
WITH g AS (
    SELECT grade_group,
           SUM(net_gain) / SUM(funded)                       AS total_return,
           SUM(interest_paid) / SUM(funded * interest_rate / 100) AS pass_through,
           AVG(interest_rate)                                AS avg_rate
    FROM matured WHERE vintage = 2015 GROUP BY grade_group
), a AS (SELECT total_return AS grade_a_return FROM g WHERE grade_group = 'A')
SELECT
    g.grade_group,
    ROUND(g.avg_rate, 2)                         AS avg_rate_2015_pct,
    ROUND(100 * g.total_return, 1)               AS total_return_2015_pct,
    ROUND(g.pass_through, 2)                     AS pass_through,
    ROUND(100 * GREATEST(a.grade_a_return - g.total_return, 0) / g.pass_through, 1) AS rate_rise_needed_pts,
    ROUND(g.avg_rate + 100 * GREATEST(a.grade_a_return - g.total_return, 0) / g.pass_through, 2) AS rate_needed_pct
FROM g CROSS JOIN a ORDER BY g.grade_group;

-- Q6. Could the 2015 problem have been seen early?
-- Charge-off date is not in the file, so the last payment month stands in for it.
CREATE OR REPLACE TABLE mart_vintage_curve AS
WITH bad AS (
    SELECT grade_group, vintage,
           date_diff('month', issue_month, last_payment_month) AS months_on_book,
           COUNT(*) AS bad_loans
    FROM matured
    WHERE is_bad = 1 AND last_payment_month IS NOT NULL
    GROUP BY 1, 2, 3
), base AS (
    SELECT grade_group, vintage, COUNT(*) AS loans FROM matured GROUP BY 1, 2
), axis AS (SELECT UNNEST(range(0, 37)) AS months_on_book)
SELECT
    b.grade_group, b.vintage, x.months_on_book,
    ROUND(100.0 * SUM(COALESCE(d.bad_loans, 0)) OVER (
        PARTITION BY b.grade_group, b.vintage ORDER BY x.months_on_book) / b.loans, 2) AS cumulative_default_pct
FROM base b
CROSS JOIN axis x
LEFT JOIN bad d ON d.grade_group = b.grade_group AND d.vintage = b.vintage AND d.months_on_book = x.months_on_book
ORDER BY 1, 2, 3;

-- Early read on 2016: not finished, so these default rates can only rise.
CREATE OR REPLACE TABLE mart_2016_early AS
SELECT
    CASE WHEN grade IN ('E', 'F', 'G') THEN 'E-G' ELSE grade END AS grade_group,
    COUNT(*) AS loans,
    ROUND(AVG(interest_rate), 2) AS avg_rate_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE loan_status IN ('Charged Off', 'Default')) / COUNT(*), 1) AS default_rate_to_date_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE loan_status NOT IN ('Fully Paid', 'Charged Off', 'Default')) / COUNT(*), 1) AS pct_still_open
FROM loans
WHERE term = '36 months' AND vintage = 2016
GROUP BY 1 ORDER BY 1;

CREATE OR REPLACE TABLE mart_dq_population AS SELECT * FROM dq_population ORDER BY step;
