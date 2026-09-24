A project for area 2, "Custom Aggregate Functions in SQL" for the MariaDB student database projects, 2026-09

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
mariadb -u root < test_aggregates.sql   # tests
mariadb -u root < bench.sql             # timings
```

Every script is idempotent — re-running one drops and recreates what it owns, so you can run them in any order, repeatedly.

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

### What the feature will not do

- **A custom aggregate cannot be used as a window function.** There is no `GEOMETRIC_MEAN(km) OVER (PARTITION BY airline)`. This is why Option C in each example has to spell the formula out rather than reuse the function, and it is the sharpest limit we hit.
- **`FETCH GROUP NEXT ROW` is single-pass.** The loop sees each row once and cannot rewind, so a median — which needs to know the values before it can pick the middle one — has to buffer the group itself.
- **Non-positive values fail silently.** `LN(0)` returns `NULL` rather than raising, and `AVG()` skips `NULL`s. The dataset contains exactly one zero-length route, and it does not produce an error anywhere. What it does produce is a wrong count: `COUNT(*)` still counts the row that contributed nothing, so an unguarded query reports a mean over 23 routes that was computed from 22. Every query here filters `WHERE km > 0` for that reason, and `sql/vedant_example.sql` demonstrates it.

## Repository layout

```
sql/setup_dataset.sql      the route_distances view every example builds on
sql/vedant_example.sql     GEOMETRIC_MEAN, plus the limits investigation
sql/janhavi_example.sql    WEIGHTED_AVERAGE, a two-argument aggregate
sql/pranesh_example.sql    HARMONIC_MEAN
sql/test_aggregates.sql    tests; exits non-zero on failure, gating CI
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
