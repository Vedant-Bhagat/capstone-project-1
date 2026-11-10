A project for area 2, "Custom Aggregate Functions in SQL", of the MariaDB student database projects, 2026-09: https://mariadb.org/bachelor_hackathon_2026-09/

# Golden Record — Custom Aggregate Functions in MariaDB

MariaDB lets you write your own aggregate function in SQL:

```sql
CREATE AGGREGATE FUNCTION GEOMETRIC_MEAN(x DOUBLE) RETURNS DOUBLE
BEGIN
    ...
    FETCH GROUP NEXT ROW;
    ...
END
```

MySQL cannot do this at the SQL level at all. There you write a UDF in C and install it into the server, or you give up and do the work in application code. `FETCH GROUP NEXT ROW` is the piece that makes it possible: inside the function body it pulls one row of the current `GROUP BY` group at a time, so an ordinary SQL routine can accumulate across a group and return a single value, exactly like a built-in.

This repository implements three such aggregates against a real dataset, compares each against the alternatives you would otherwise reach for, and measures what the convenience costs.

**Capstone Project I**, Constructor University, in partnership with the MariaDB Foundation.

## Our other project

This is the **starter**. Our **main dish** — area 4, "Vector search and RAG, natively" — is a separate
repository: **https://github.com/Vedant-Bhagat/capstone-project-1-primary**

The two are separate because the project page asks you to pick one area and declare it on the first line of
your README, and whichever area a README declares is the only one assessed. One README cannot truthfully
declare two areas.

## Team

| Name | GitHub |
|---|---|
| Vedant | [`Vedant-Bhagat`](https://github.com/Vedant-Bhagat) |
| Janhavi | [`janhavi8112`](https://github.com/janhavi8112) |
| Pranesh | [`Pranesh-Navneeth`](https://github.com/Pranesh-Navneeth) |

## MariaDB version

Developed against **12.3.3**. Requires **10.3 or later** — `CREATE AGGREGATE FUNCTION` was introduced in 10.3, and `ST_Distance_Sphere`, used to derive the dataset, in 10.2.38.

Continuous integration runs every script against **11.4, 12.3 and 13.0** on each push, so the examples are known to work across all three.

## The dataset

We use **[MariaDB's OpenFlights dataset](https://github.com/mariadb/openflights)** — airports, airlines and routes — which MariaDB packages with load instructions for local, Docker and cloud setups.

The examples work on a derived quantity rather than a stored column: **the great-circle distance of every airline route**, obtained by joining each route to the coordinates of its origin and destination airport and passing them through `ST_Distance_Sphere`.

That gives **66,771 routes** spanning **0 to 16,082 km**. The spread matters. Route lengths cover three orders of magnitude, and it is precisely on data like that where the choice of *which mean* stops being pedantry and starts changing the answer.

The data is not committed here. It is fetched by the documented step below, which takes about a minute.

## Setup

### 1. Install MariaDB

**Windows** (PowerShell):
```powershell
winget install --id MariaDB.Server --source winget --accept-source-agreements --accept-package-agreements
```

**macOS**:
```bash
brew install mariadb && brew services start mariadb
```

**Debian/Ubuntu**:
```bash
sudo apt install mariadb-server && sudo systemctl start mariadb
```

Confirm the server is up:
```bash
mariadb -u root -e "SELECT VERSION();"
```

On Windows the client may not be on your `PATH`; use the full path instead, adjusting the version number to match your install:
```powershell
& "C:\Program Files\MariaDB 12.3\bin\mariadb.exe" -u root -e "SELECT VERSION();"
```

If you already run MySQL, it is probably holding port 3306 and MariaDB will not start on it. Run MariaDB on another port and pass it to every command below:
```bash
mariadb -u root -P 3307 --protocol=tcp -e "SELECT VERSION();"
```

### 2. Load the OpenFlights data

```bash
git clone https://github.com/mariadb/openflights
cd openflights
mariadb -u root < sql/create.sql
mariadb -u root --local-infile=1 < sql/load-data.sql
```

**In PowerShell, `<` is a reserved operator and will not redirect a file.** Use `Get-Content` instead:
```powershell
Get-Content sql/create.sql | mariadb -u root
Get-Content sql/load-data.sql | mariadb -u root --local-infile=1
```

Two things that will otherwise cost you twenty minutes: `--local-infile=1` is required or the import silently loads nothing, and the load script uses relative paths, so it must be run from inside the `openflights` directory.

### 3. Run the examples

From this repository's `sql/` directory:

```bash
mariadb -u root < setup_dataset.sql     # creates the route_distances view
mariadb -u root < vedant_example.sql    # GEOMETRIC_MEAN
mariadb -u root < janhavi_example.sql   # WEIGHTED_AVERAGE
mariadb -u root < pranesh_example.sql   # HARMONIC_MEAN
mariadb -u root < median_buffered.sql   # MEDIAN_AGG, the buffering one
mariadb -u root < test_fixture.sql      # controlled rows for the edge cases
mariadb -u root < test_aggregates.sql   # tests
mariadb -u root < test_median.sql       # tests for MEDIAN_AGG
mariadb -u root < bench.sql             # timings
```

Every script is idempotent — re-running one drops and recreates what it owns, so you can run them in any order, repeatedly. The two test scripts are the exception to "any order": `test_median.sql` needs `median_buffered.sql` and `test_fixture.sql` to have run first.

## What we found

### The three means disagree, and by a lot

Each aggregate answers "how long is a typical route for this airline?" in a different way. On identical data they land far apart:

| Airline | Routes | Arithmetic | Geometric | Harmonic |
|---|---|---|---|---|
| Ryanair (FR) | 2,484 | 1,489.7 km | 1,320.1 km | 1,130.7 km |
| American (AA) | 2,352 | 2,310.3 km | 1,396.5 km | 849.5 km |
| United (UA) | 2,178 | 2,352.2 km | 1,362.2 km | 741.5 km |
| Delta (DL) | 1,981 | 2,350.5 km | 1,451.5 km | 933.6 km |
| British Airways (BA) | 547 | 3,310.0 km | 1,940.8 km | 1,062.7 km |

American Airlines is the clearest case: the arithmetic mean says 2,310 km, the geometric mean says 1,397 km. Same 2,352 routes. The arithmetic mean is being dragged upward by a handful of intercontinental flights; the geometric mean describes what a typical American route actually looks like. Ryanair, flying a dense short-haul European network with no long tail, shows the three means clustered much closer together — the shape of the distribution is visible in how far apart they sit.

### Weighting changes the answer more than the choice of mean does

`WEIGHTED_AVERAGE(value, weight)` takes two arguments, which no built-in aggregate can express. It answers: how long is a typical route for a country's airlines, weighted by how many routes each airline actually flies?

| Country | Airlines | Routes | Weighted | Unweighted |
|---|---|---|---|---|
| United States | 51 | 12,831 | 1,977.7 km | 957.4 km |
| Germany | 11 | 2,920 | 2,236.8 km | 1,490.4 km |
| Ireland | 4 | 2,760 | 1,484.4 km | 1,013.6 km |
| China | 16 | 7,194 | 1,424.2 km | 1,142.5 km |
| France | 15 | 2,013 | 2,217.4 km | 2,082.6 km |

The United States more than doubles. Fifty-one US airlines are counted, and most are small regional carriers flying short hops; unweighted, each counts as much as Delta. France barely moves, because its carriers are more uniform in size. The gap between the two columns is a measure of how lopsided a country's airline industry is — which is not a question you set out to ask, and is the sort of thing a weighted aggregate makes cheap to notice.

### Real data does not join the way the schema suggests

`routes.airline` holds a two-letter IATA code, and joining it to `airlines.iata` looks like the obvious way to attribute a route to a carrier. It is wrong. IATA codes are not unique in that table — code `1I` alone belongs to seven airlines — so the join inflates 66,770 routes into **76,277 rows**, silently double-counting some airlines and attributing their routes to several countries at once.

The numeric `airlines.alid` is the real key. Joining on it gives 66,315 rows; the remaining 455 routes carry no airline id and drop out, which we state rather than hide. Nothing about this is visible in the row counts unless you check, and no error is ever raised.

### The custom aggregate is slower than writing the formula out

Ten runs each over all 66,770 routes, measured by `sql/bench.sql`:

| Approach | Mean | Min | Max | Std dev |
|---|---|---|---|---|
| A: custom aggregate | 310.9 ms | 300.1 ms | 319.6 ms | 6.6 ms |
| B: inline formula | 131.4 ms | 120.4 ms | 150.0 ms | 9.0 ms |
| C: window function | 170.3 ms | 153.1 ms | 192.1 ms | 12.2 ms |

*AMD Ryzen 7 6800H (8C/16T), 15 GB RAM, NVMe SSD, Windows 11, MariaDB 12.3.3, default configuration.*

**The custom aggregate costs about 2.4× the inline formula.** That is the honest result and it is not a small overhead. `FETCH GROUP NEXT ROW` steps through the stored-routine interpreter once per row, and at 66,770 rows that per-row cost dominates. `EXP(AVG(LN(x)))` runs entirely inside the server's own aggregation machinery and never pays it.

So the case for a custom aggregate is not performance. It is that `GEOMETRIC_MEAN(km)` is one call site that cannot be got wrong, versus a formula every caller has to know, repeat correctly, and guard against a zero. On a 66,000-row analytical query taking a third of a second, we would take the readability. On a hot path, we would not — and you should measure before assuming.

### A median is where the feature runs out

The three aggregates above are *streaming*: each row is folded into a running total and forgotten. A median cannot work that way — you cannot know which value is in the middle until you have seen them all — so the function has to keep the group somewhere. [`sql/median_buffered.sql`](sql/median_buffered.sql) does exactly that, in a `TEMPORARY` table created inside the function body, and it is the most interesting thing in this repository for four reasons.

**It works, and it agrees with the built-in.** `MEDIAN_AGG(km)` matches MariaDB's own `MEDIAN()` on all 566 airlines to within floating-point tolerance, and on every hand-checked edge case. Asserted in [`sql/test_median.sql`](sql/test_median.sql).

**It is the wrong choice anyway.** Same data, same server, best of three runs:

| Approach | Time |
|---|---|
| Custom aggregate `MEDIAN_AGG(km)` | 1,460 ms |
| Built-in `MEDIAN(km) OVER (PARTITION BY airline)` | 250 ms |
| `PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY km)` | 265 ms |
| `ROW_NUMBER()`, pick the middle row(s) by hand | 295 ms |

About 5x slower than all three alternatives, one of which is a built-in. Varying the group count over the same 66,771 rows — 1 group 1,365 ms, 566 groups 1,460 ms, 5,000 groups 2,140 ms — puts the cost at roughly 0.02 ms per row buffered against 0.16 ms per group, so it is the one `INSERT` per row that dominates, not the per-group setup. We had assumed the opposite before measuring.

**The obvious implementation is quietly broken.** A fixed-name temporary table passes every test that calls the function once, and fails the moment you call it twice in one statement:

```
SELECT grp, MEDIAN_AGG(v), MEDIAN_AGG(v * 10) FROM t GROUP BY grp;
ERROR 1146 (42S02): Table 'flightdb2.median_buf' doesn't exist
```

The two invocations interleave and the second one's `DROP` takes the first one's buffer away mid-fill. The natural fix — a unique table name per invocation — is not available, because that needs `PREPARE` and prepared statements are not allowed inside a stored function. So the buffer has to be shared and every row tagged with an invocation counter instead. Test 7 in `test_median.sql` is the regression test for it.

**The server does not promise to finish an invocation.** This is the finding we would not have reached without buffering. In this shape:

```sql
SELECT COUNT(*) FROM (SELECT airline, MEDIAN_AGG(km) AS med,
                             MIN(km) AS lo, MAX(km) AS hi
                      FROM route_distances WHERE km > 0 GROUP BY airline) t
 WHERE med < lo OR med > hi;
```

the derived table is merged and the outer condition pushed down into the grouping — and afterwards the buffer holds exactly one row per group, 566 of them. The medians are still correct. What happens is that a second invocation per group is started, fed a single row, and abandoned before the body reaches its cleanup, so the function's own `DELETE` never runs. Adding a `LIMIT` to the derived table blocks the merge and the leak disappears.

A streaming aggregate could never show this, because it holds no state outside its own variables. Nothing in the documentation says an aggregate body runs to completion, and it turns out not to. `test_median.sql` prints the number rather than asserting it, so the CI log shows it per server version instead of a test breaking when a version behaves differently.

Two smaller restrictions found along the way: a stored aggregate cannot appear in `HAVING` (`HAVING AVG(km) > 0` is fine, `HAVING MEDIAN_AGG(km) > 0` is `ERROR 1054: Unknown column 'km'`), and the built-in `MEDIAN()` will not accept a named `WINDOW w AS (...)` clause although `AVG()` in the same statement will — the percentile family wants its window spelled out inline.
### `HARMONIC_MEAN` failed differently depending on how it was created

The new edge-case tests in `sql/test_aggregates.sql` turned up a real defect. On a group containing a zero, or one whose reciprocals cancel to exactly zero (values 1 and −1), the function divided by zero, and what happened next depended on the `sql_mode` MariaDB stores with the function at `CREATE` time. Under the default `ERROR_FOR_DIVISION_BY_ZERO` the call raised error 1365. Without it, the same call quietly returned `NULL`. The existing `IF cnt = 0` guard cannot catch the cancelling case, because the count is fine and the *sum* is the problem. Vedant's task doc predicted that case before the test was written.

The fix is two explicit guards that return `NULL` unconditionally. `NULL` was not a fresh choice: it is what the unguarded function already returned in non-strict mode, so the existing behaviour became unconditional rather than new behaviour being invented.

The other awkward inputs are left alone, documented, and each pinned by a test:

- **A `NULL` value makes the whole group `NULL`** (Test 11). Built-in `AVG()` behaves differently: it skips `NULL`s.
- **Negative inputs pass through as the plain formula result** (Test 9): 2 / (1/−10 + 1/20) = −40. The harmonic mean is only defined for positive values, and the function does not police that.
- **Junk text never produces a number** (Test 10). Two different `sql_mode`s are involved here, and they are not the same one. Converting the text to the function's `DOUBLE` argument follows the *caller's session* mode: in a strict session `'abc'` raises error 1366 before the function body runs, and in a non-strict session it becomes 0, which the zero guard turns into `NULL`. Division by zero *inside* the function follows the mode stored at `CREATE` time, as above. Test 10b sets the session mode itself and asserts each case separately. Observed on MariaDB 13.0.2; CI runs the same test on 11.4 and 12.3. Numeric strings such as `'12.5'` convert correctly.

One limit remains: the guard catches a reciprocal sum of *exactly* zero, and floating point rarely lands there. The values 2, 3 and −1.2 cancel mathematically (1/2 + 1/3 − 1/1.2 = 0), but in `DOUBLE` the sum comes out as −1.1 × 10⁻¹⁶, so `HARMONIC_MEAN` returns **−2.7 × 10¹⁶**, with no error and no warning. Fed the same three values in a different order, it returns −5.4 × 10¹⁶, so the answer depends on the order rows reach the function, which SQL does not guarantee. Positive inputs cannot get here, because their reciprocals never cancel. The problem only affects negative inputs, which the function already does not support.

### What the feature will not do

- **A custom aggregate cannot be used as a window function.** There is no `GEOMETRIC_MEAN(km) OVER (PARTITION BY airline)`. This is why Option C in each example has to spell the formula out rather than reuse the function, and it is the sharpest limit we hit.
- **`FETCH GROUP NEXT ROW` is single-pass.** The loop sees each row once and cannot rewind, so a median — which needs to know the values before it can pick the middle one — has to buffer the group itself. We did that in [`sql/median_buffered.sql`](sql/median_buffered.sql); see *A median is where the feature runs out* above for what buffering costs and what it exposes.
- **A stored aggregate cannot be used in `HAVING`.** The column name does not resolve there, so filtering on the result needs a derived table or a subquery.
- **An aggregate body is not guaranteed to run to completion.** The optimizer can start an invocation and abandon it, which is invisible for a streaming aggregate and leaks state for a buffering one.
- **Non-positive values fail silently.** `LN(0)` returns `NULL` rather than raising, and `AVG()` skips `NULL`s. The dataset contains exactly one zero-length route, and it does not produce an error anywhere. What it does produce is a wrong count: `COUNT(*)` still counts the row that contributed nothing, so an unguarded query reports a mean over 23 routes that was computed from 22. Every query here filters `WHERE km > 0` for that reason, and `sql/vedant_example.sql` demonstrates it.

## Repository layout

```
sql/setup_dataset.sql      the route_distances view every example builds on
sql/vedant_example.sql     GEOMETRIC_MEAN, plus the limits investigation
sql/janhavi_example.sql    WEIGHTED_AVERAGE, a two-argument aggregate
sql/pranesh_example.sql    HARMONIC_MEAN
sql/median_buffered.sql    MEDIAN_AGG: buffers the group, and what that costs
sql/test_fixture.sql       controlled NULL/negative/tie rows the real data lacks
sql/test_aggregates.sql    tests; exits non-zero on failure, gating CI
sql/test_median.sql        tests for MEDIAN_AGG, same gate
sql/bench.sql              timing harness, 10 runs per variant with variance
.github/workflows/ci.yml   loads the dataset and runs all of the above
docs/                      reading summary, project shortlist
self_assessment/           weekly self-assessment
AI_USE_LOG.md              record of AI tool use
CONTRIBUTING.md            branching, commits, PR and review workflow
```

## Documentation

- [`docs/project_shortlist.md`](docs/project_shortlist.md) — how we chose this area, and the main dish
- [`docs/reading_summary.md`](docs/reading_summary.md) — Pro Git, the Open Source Guide, MariaDB docs
- MariaDB reference: [`CREATE AGGREGATE FUNCTION`](https://mariadb.com/docs/server/reference/sql-statements/data-definition/create/create-function-udf)

## AI use

We use AI tools in a traceable way, per the course's policy. Every use is logged in [`AI_USE_LOG.md`](AI_USE_LOG.md): the tool, the part of the work it touched, the prompt, and the commit it produced. AI-assisted commits also carry `Co-Authored-By` trailers, so the record is visible in git history as well as in the log.
