# Janhavi — tests for `WEIGHTED_AVERAGE`

**Deadline: 12 November 2026.** Estimated effort: 2–3 hours.

## Why this task exists

The supervisor's feedback on our submission was 32/40, and this was the single cheapest gain available:

> *"To improve, only three tests in total. Cover `WEIGHTED_AVERAGE` and `HARMONIC_MEAN`, and the NULL,
> negative, tie and text cases. This is the cheapest gain available."*

He is right. `sql/test_aggregates.sql` has three tests and **all three test `GEOMETRIC_MEAN` only**. Your
`WEIGHTED_AVERAGE` currently has no tests at all. Pranesh has the same task for `HARMONIC_MEAN` — see
[`task_pranesh_harmonic_mean_tests.md`](task_pranesh_harmonic_mean_tests.md).

## Your job

Add a `WEIGHTED_AVERAGE` section to **`sql/test_aggregates.sql`** covering the seven cases below.

---

## Step 1 — the shared fixture (whoever starts first)

The real dataset has no NULLs, no negative distances and no ties, so the edge cases need their own small
table. Create **`sql/test_fixture.sql`** with exactly this:

```sql
-- Controlled rows for aggregate edge-case tests. The real dataset cannot
-- produce NULLs, negatives or ties, so they are constructed here.
USE flightdb2;

DROP TABLE IF EXISTS agg_edge_cases;
CREATE TABLE agg_edge_cases (
    grp      VARCHAR(16)  NOT NULL,
    val      DOUBLE       NULL,
    weight   DOUBLE       NULL,
    val_text VARCHAR(16)  NULL,
    note     VARCHAR(80)  NOT NULL DEFAULT ''
);

INSERT INTO agg_edge_cases (grp, val, weight, val_text, note) VALUES
    ('plain',    10,    1, NULL, 'three ordinary positive values, equal weights'),
    ('plain',    20,    1, NULL, ''),
    ('plain',    30,    1, NULL, ''),
    ('has_null', 10,    1, NULL, 'one NULL value among valid ones'),
    ('has_null', NULL,  1, NULL, ''),
    ('has_null', 30,    1, NULL, ''),
    ('null_wt',  10,    1, NULL, 'one NULL weight'),
    ('null_wt',  20, NULL, NULL, ''),
    ('zero_wt',  10,    0, NULL, 'every weight is zero'),
    ('zero_wt',  20,    0, NULL, ''),
    ('neg_wt',   10,    2, NULL, 'weights that cancel to zero'),
    ('neg_wt',   20,   -2, NULL, ''),
    ('neg',     -10,    1, NULL, 'a negative value'),
    ('neg',      20,    1, NULL, ''),
    ('ties',      7,    1, NULL, 'three identical values'),
    ('ties',      7,    1, NULL, ''),
    ('ties',      7,    1, NULL, ''),
    ('zero_val',  0,    1, NULL, 'a zero value: 1/0 is undefined'),
    ('zero_val', 10,    1, NULL, ''),
    ('text',   NULL,    1, '12.5', 'numeric strings and junk, for coercion'),
    ('text',   NULL,    1, '20',   ''),
    ('text',   NULL,    1, 'abc',  '');
```

**If this file already exists on `main`, pull and use it — do not rewrite it.** Pranesh's doc contains the
same block for the same reason.

Then add one line to `sql/test_aggregates.sql`'s prerequisites comment noting that `test_fixture.sql` must
run first.

## Step 2 — the seven tests

Copy the shape of "Test 1" that is already in the file: compute into a variable, compare, print `PASS`/`FAIL`.

| # | Case | What to assert | Why it matters |
|---|---|---|---|
| 4 | **Agrees with the closed form** | `WEIGHTED_AVERAGE(mean_km, route_count)` equals `SUM(mean_km*route_count)/SUM(route_count)` for every country in `airline_route_stats`, within relative tolerance | The main correctness test. Same shape as Test 1. |
| 5 | **Equal weights reduce to `AVG()`** | on `grp='plain'`, `WEIGHTED_AVERAGE(val,weight)` equals `AVG(val)` = 20 | A property that holds regardless of data. This is the "tie" case the feedback asks for — identical weights. |
| 6 | **The independent real-data check** | for each country, `WEIGHTED_AVERAGE(mean_km, route_count)` equals plain `AVG(d.km)` over all that country's routes | Your own script already claims this in its closing comment. Asserting it turns a claim into a test — free points. |
| 7 | **All-zero weights return NULL** | on `grp='zero_wt'`, result `IS NULL` | Your function explicitly codes for this. An uncovered `IF` branch. |
| 8 | **NULL poisons the group** | on `grp='has_null'` **and** `grp='null_wt'`, result `IS NULL` | Your closing comment documents this as a limit. Assert the documented behaviour — don't "fix" it. |
| 9 | **Weights summing to zero** | on `grp='neg_wt'`, record what actually happens and assert that | `weight_total` reaches 0 by cancellation, so the `IF weight_total = 0` branch fires and you get NULL even though real data was present. **Run it before deciding the expected value.** |
| 10 | **Text coercion** | on `grp='text'`, `WEIGHTED_AVERAGE(val_text, weight)` — record what MariaDB does with `'12.5'`, `'20'` and `'abc'` | MariaDB coerces numeric strings and turns junk into 0 with a warning. Assert the real behaviour and note it. |

## Step 3 — wire it into the failure count

**This is the part that is easy to get wrong.** At the bottom of `sql/test_aggregates.sql`:

```sql
SET @total_failures = @failures + @amgm_violations + IF(@empty_result IS NULL, 0, 1);
```

That line decides whether CI goes red. **Every new counter you add must be added into it**, or your tests
will print `FAIL` and the build will still pass — which is worse than having no test.

---

## How to run

```powershell
cd sql
Get-Content setup_dataset.sql     | mariadb -u root
Get-Content test_fixture.sql      | mariadb -u root
Get-Content janhavi_example.sql   | mariadb -u root
Get-Content vedant_example.sql    | mariadb -u root
Get-Content pranesh_example.sql   | mariadb -u root
Get-Content test_aggregates.sql   | mariadb -u root
echo $LASTEXITCODE     # must be 0
```

Then break something on purpose — change a tolerance or a expected value — and confirm the exit code goes
non-zero. **A test suite you have never seen fail is not a test suite.**

## Done when

**Done.** Closed by PR #8 (`janhavi/weighted-average-tests`), merged as `4b69977`. Seven tests delivered as Tests 12–18, with 18 split into three legs. CI green on 11.4, 12.3 and 13.0. One follow-up landed separately as `c08dea3`: Tests 12 and 14 counted failures with `SUM(cond)`, which is `NULL` rather than 0 when every comparison is `NULL`, and that `NULL` silenced the suite's `SIGNAL`. See the README section *A `SUM()` in a test can switch the test suite off*.

- [x] `sql/test_fixture.sql` exists (yours or Pranesh's)
- [x] Seven new tests in `sql/test_aggregates.sql`, all printing `PASS`
- [x] Every new counter included in `@total_failures`
- [x] You have watched the suite fail on purpose, then pass
- [x] CI is green on your PR

## If a test genuinely fails

**Do not quietly change the function to make it pass.** Tell Vedant and Pranesh first. A real bug found by a
new test is a better result than another green tick — it goes in the README as a finding, and that is the
kind of thing the supervisor scored us well on last time.

## Workflow (from `CONTRIBUTING.md`)

1. Branch: `janhavi/weighted-average-tests`
2. Small commits, as yourself
3. `git push -u origin janhavi/weighted-average-tests`, open a PR into `main`
4. Pranesh or Vedant reviews, then merge and delete the branch
5. Add your line to `AI_USE_LOG.md` **with the change, not afterwards**, if you use AI help
6. Fill your row in the current `self_assessment/` file — yours is still blank in the last one

## One coordination note

You and Pranesh are both editing `sql/test_aggregates.sql`. To avoid a merge conflict: **append your section
at the end, above the "Fail the run" block, and leave his region alone.** Whoever merges second will have a
small conflict in the `@total_failures` line only — keep both sides of it.
