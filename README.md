# LendingClub: Credit Portfolio Review (SQL and Power BI)

**The question:** as lending grew about seven times between 2012 and 2015, did the book stay worth the risk?

**The answer:** no. Total return fell from 10.2% to 6.6%, and by 2015 the riskiest grades paid less than the safest. The warning was visible in the first 12 months on book.

Built with SQL (DuckDB) and Power BI on 2.26m LendingClub loans, analysing the 589,488 36-month loans ($7.45bn) that had reached their end date.


## What I found

| Finding | Evidence |
|---|---|
| Return fell as the book grew | Funded $508m in 2012 and $3.62bn in 2015. Total return 10.2% to 6.6% |
| Risky grades stopped paying | E-G default rate rose from 21.4% to 34.3%, while the average rate fell from 21.2% to 19.8%. Return fell from 16.0% to 1.6% |
| The risk premium disappeared | In 2015, E-G returned 1.6% and D returned 4.9%, against 6.9% for grade A |
| The problem was not only E-G | Grade C fell from 11.3% to 6.5%, and grade D from 13.0% to 4.9% |
| The warning came early | By month 12, 2015 E-G loans were at 16.3% cumulative default, against 10.6% for 2013 |
| Pricing moved late and may still be short | The 2016 E-G rate rose to 23.2%, yet those loans had already reached 34.8% default with 19% still open |

## What I recommend

1. **Stop E-G loans with DTI of 20 or more, or 2 or more inquiries in six months.** In the 2015 test these 7,626 loans ($94.7m) returned -0.2% and held 6.6% of bad loans. This is a clean-up, not the fix: book return only moves from 6.55% to 6.73%.
2. **Reprice D and E-G, which is the bigger lever.** To match the grade A return on 2015 loans, E-G needed about 24.5% against 19.8% charged, and D about 18.3% against 16.6%. These are minimums, because they hold defaults fixed and higher rates can attract weaker borrowers.
3. **Add a 12-month vintage trigger.** Review pricing for a grade when its cumulative default at month 12 runs well above the last finished vintage. For E-G, 2015 ran about 54% above 2013.

## Testing the rule

The rule was picked by looking at vintages up to 2014, then tested on 2015.

| Vintage | Loans hit | Return on hit loans | Bad loans caught | Book return | After rule |
|---|---:|---:|---:|---:|---:|
| 2013 | 2,526 | 10.7% | 5.1% | 11.05% | 11.06% |
| 2014 | 5,950 | 6.9% | 8.0% | 9.00% | 9.06% |
| 2015 (test) | 7,626 | -0.2% | 6.6% | 6.55% | 6.73% |

These loans still earned money up to 2014, so the rule would have looked weak at the time. It became loss-making only in 2015. This is another reason pricing and monitoring matter more than a fixed cut-off.

## Avoiding the usual traps

- **Unfinished loans.** Recent years look safe because their bad loans have not happened yet. Only 36-month loans issued up to 2015 are measured, as the data runs to March 2019.
- **Leakage.** Drivers use only facts known on application day. Payment fields are used for outcomes only.
- **Reconciliation.** The path from 2,260,701 raw rows to 589,488 analysed loans is in `marts/mart_dq_population.csv`.

## Limits

- Total return is over the life of the loan. It is not annualised, is not an IRR, and is before LendingClub's servicing fee.
- Repaying early shortens a loan, so returns between grades are not a perfect comparison.
- The file has no charge-off date, so early-warning curves use the last payment month as a stand-in.
- Only approved loans are in the data, so nothing here says how declined applicants would have performed.
- 60-month loans are out of scope.
- The rule test covers one year, so it is evidence, not proof.

## Repository

```text
sql/01_clean.sql      Types the raw file and defines the finished-loan population
sql/02_analysis.sql   One mart table per business question
marts/                Query outputs used by Power BI
dashboard/            Power BI project, open the .pbip in Power BI Desktop
run_all.py            Rebuilds everything from the raw file
```

## Run it

1. Download `accepted_2007_to_2018Q4.csv` into `data/`. It is on [Kaggle](https://www.kaggle.com/datasets/wordsforthewise/lending-club) and [Hugging Face](https://huggingface.co/datasets/codesignal/lending-club-loan-accepted).
2. Run `pip install duckdb`.
3. Run `python run_all.py`.

To refresh the dashboard, set the `DataFolder` parameter in Power BI to your `marts` folder.
