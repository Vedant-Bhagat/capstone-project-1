# Pranesh — tests for `HARMONIC_MEAN`

**Deadline: 12 November 2026.** Estimated effort: 2–3 hours.

## Why this task exists

The supervisor's feedback on our submission was 32/40, and this was the single cheapest gain available:

> *"To improve, only three tests in total. Cover `WEIGHTED_AVERAGE` and `HARMONIC_MEAN`, and the NULL,
> negative, tie and text cases. This is the cheapest gain available."*

He is right. `sql/test_aggregates.sql` has three tests and **all three test `GEOMETRIC_MEAN` only**. Your
`HARMONIC_MEAN` currently has no tests at all. Janhavi has the same task for `WEIGHTED_AVERAGE` — see
[`task_janhavi_weighted_average_tests.md`](task_janhavi_weighted_average_tests.md).

## Your job

Add a `HARMONIC_MEAN` section to **`sql/test_aggregates.sql`** covering the seven cases below.

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
    ('cancel',    1,    1, NULL, 'reciprocals that cancel: 1/1 + 1/-1 = 0'),
    ('cancel',   -1,    1, NULL, ''),
    ('zero_val',  0,    1, NULL, 'a zero value: 1/0 is undefined'),
    ('zero_val', 10,    1, NULL, ''),
    ('text',   NULL,    1, '12.5', 'numeric strings and junk, for coercion'),
    ('text',   NULL,    1, '20',   ''),
    ('text',   NULL,    1, 'abc',  '');
```

**If this file already exists on `main`, pull and use it — do not rewrite it.** Janhavi's doc contains the
same block for the same reason. Hers is missing the `cancel` group, which only matters for you; if she
created the file first, add those two rows.

Then add one line to `sql/test_aggregates.sql`'s prerequisites comment noting that `test_fixture.sql` must
run first.

## Step 2 — the seven tests

Copy the shape of "Test 1" that is already in the file: compute into a variable, compare, print `PASS`/`FAIL`.

| # | Case | What to assert | Why it matters |
|---|---|---|---|
| 4 | **Agrees with the closed form** | `HARMONIC_MEAN(km)` equals `COUNT(*)/SUM(1/km)` for every airline in `route_distances` where `km > 0`, within relative tolerance | The main correctness test. Same shape as Test 1. |
| 5 | **HM ≤ GM ≤ AM** | for every airline: `HARMONIC_MEAN(km) <= GEOMETRIC_MEAN(km) * (1+tol)` and `GEOMETRIC_MEAN(km) <= AVG(km) * (1+tol)` | **Write this one first — it is the strongest test in the file.** The inequality holds for any set of positive reals, so it depends on no dataset and catches errors the closed-form test cannot. The file already asserts the GM ≤ AM half; you are completing the chain. |
| 6 | **Identical values** | on `grp='ties'`, result is exactly 7 | The harmonic mean of N copies of x is x. This is the "tie" case the feedback asks for. |
| 7 | **Empty group returns NULL** | result `IS NULL` for an airline code that does not exist | Your function codes for `cnt = 0`. An uncovered `IF` branch. |
| 8 | **A zero value** | on `grp='zero_val'`, record what happens and assert it | `1/0` in MariaDB gives NULL rather than an error, so `inv_sum` goes NULL and the whole result does. This is the `km = 0` gotcha your script's header warns about — assert the behaviour the comment describes. |
| 9 | **Reciprocals that cancel** | on `grp='cancel'` (values 1 and −1), record what happens and assert it | `inv_sum` reaches exactly 0, so the return is `cnt/0`. Your `IF cnt = 0` guard does not catch this one, because the count is fine and the *sum* is the problem. **Run it before deciding the expected value.** Also try `grp='neg'`. |
| 10 | **Text coercion** | on `grp='text'`, `HARMONIC_MEAN(val_text)` — record what MariaDB does with `'12.5'`, `'20'` and `'abc'` | MariaDB coerces numeric strings and turns junk into 0 with a warning, which then hits the `1/0` path. Assert the real behaviour and note it. |

Test 9 is the interesting one. Your script's closing comment says *"x must be non-zero"* but the function
has no guard for a reciprocal sum of zero. Whatever it does, documenting it precisely is a genuine finding.

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
Get-Content pranesh_example.sql   | mariadb -u root
Get-Content vedant_example.sql    | mariadb -u root
Get-Content janhavi_example.sql   | mariadb -u root
Get-Content test_aggregates.sql   | mariadb -u root
echo $LASTEXITCODE     # must be 0
```

Test 5 needs `GEOMETRIC_MEAN` to exist, so `vedant_example.sql` must have been run — that is why the order
above matters.

Then break something on purpose — change a tolerance or an expected value — and confirm the exit code goes
non-zero. **A test suite you have never seen fail is not a test suite.**

## Done when

**Done.** Closed by PR #6 (`pranesh/harmonic-mean-tests`), merged as `2746f08`, and PR #7 (`pranesh/test-10b-modes`), merged as `e6d5093`. Seven tests asked for, eight delivered as Tests 4–11; PR #7 then split Test 10b into separate strict and non-strict legs after review found the strict leg passed only because the statement errored. CI green on 11.4, 12.3 and 13.0.

- [x] `sql/test_fixture.sql` exists (yours or Janhavi's, with the `cancel` rows)
- [x] Seven new tests in `sql/test_aggregates.sql`, all printing `PASS`
- [x] Every new counter included in `@total_failures`
- [x] You have watched the suite fail on purpose, then pass
- [x] CI is green on your PR

## If a test genuinely fails

**Do not quietly change the function to make it pass.** Tell Vedant and Janhavi first. A real bug found by a
new test is a better result than another green tick — it goes in the README as a finding, and that is the
kind of thing the supervisor scored us well on last time. Test 9 has a fair chance of being exactly that.

## Workflow (from `CONTRIBUTING.md`)

1. Branch: `pranesh/harmonic-mean-tests`
2. Small commits, as yourself
3. `git push -u origin pranesh/harmonic-mean-tests`, open a PR into `main`
4. Janhavi or Vedant reviews, then merge and delete the branch
5. Add your line to `AI_USE_LOG.md` **with the change, not afterwards**, if you use AI help
6. Fill your row in the current `self_assessment/` file

## One coordination note

You and Janhavi are both editing `sql/test_aggregates.sql`. To avoid a merge conflict: **append your section
at the end, above the "Fail the run" block, and leave her region alone.** Whoever merges second will have a
small conflict in the `@total_failures` line only — keep both sides of it.
