# Project shortlist

Source: MariaDB Foundation project list, https://mariadb.org/bachelor_hackathon_2026-09/ (list may change during the semester — re-check before finalizing).

Both the starter and the main dish are picked from the professor's approved list (`todo_cp_01.pdf` / `team_guide.pdf`).

Our shortlist reflects two different bets, and we are choosing between them deliberately:
- **Safety of delivery** — a self-contained Tier A/B project (single local server) that two contributors can reliably finish and demo.
- **Real external contribution** — work that produces a merged pull request in a real open-source project, at the cost of a scope we cannot size upfront.

## Starter (pick one) — leaning: **Custom Aggregate Functions**

| Candidate | What it is | Why / why not |
|---|---|---|
| **Custom aggregate functions** ✅ leaning towards this | `CREATE AGGREGATE FUNCTION ... FETCH GROUP NEXT ROW` — write your own SQL-level aggregate (median, mode, geometric mean, weighted percentile, longest streak, etc.). Not available at the SQL level in MySQL, so it's a clean "something only MariaDB has." | Small, contained, easy to demo before/after (aggregate function vs. window function vs. correlated subquery vs. app-side loop), with measurable query length/readability/execution-time differences. Good scope for a starter. |
| SQL features that save code | Demonstrate ≥2 of: `INET4`/`INET6`, `UUID`, `RETURNING`, `CREATE SEQUENCE`, `INTERSECT`/`EXCEPT`, `CREATE OR REPLACE`, `IS JSON`, invisible columns, `ROW` types, instant column changes, global temp tables, `UPDATE`/`DELETE` with CTEs. | Also a solid, low-effort starter — broader surface (many small features) rather than one focused feature. Kept as backup if the aggregate-function angle turns out too thin. |

**Decision**: confirmed with Janhavi — custom aggregate functions is the starter (both contributors' SQL examples in `sql/` implement it: `GEOMETRIC_MEAN` and `WEIGHTED_AVERAGE`).

## Main dish (pick one) — shortlisted

### 1. Ecosystem compatibility (contribute upstream) — Tier C

Pick an open-source project not yet verified against MariaDB (Drupal, Nextcloud, Moodle, Matomo — *not* WordPress, which the project page indicates is already well covered), run its test suite against MariaDB, diagnose every failure, fix the MySQL assumptions, and additionally add a capability using a MariaDB-only feature the project does not currently use. Submit upstream.

**Why we want it**: it is the only option on the list that produces a contribution to a real external project rather than a self-contained demo repository, and it is the most direct fit for this semester's Open Source theme. It also gives MariaDB something they do not already have — evidence of where their database breaks in real applications.

**Where the code lands**: in the chosen project's repository (Drupal, Nextcloud, etc.), **not** in MariaDB's codebase. MariaDB benefits indirectly through wider ecosystem support.

**The structural tension to design around**: the two mandated halves pull against each other. Compatibility fixes are highly mergeable but score nothing on "MariaDB depth." Adding a MariaDB-only capability scores well on depth but is hard to merge into a project that also supports PostgreSQL and SQLite, because maintainers reject changes that fragment their support matrix. Our plan is to split the deliverable: **compatibility fixes go upstream** (the contribution), **the MariaDB-capability work lives in our own repository** as a documented proof-of-concept with measurements (the depth artifact). Neither half is then hostage to the other.

**Known risks**: scope cannot be sized until we clone a candidate and run its test suite (a scouting phase must come first); upstream acceptance is outside our control and review cycles are slow; Tier C means reading a large unfamiliar PHP codebase. Mitigation: the graded deliverable is "test results, diagnosis, patch" — not the merge — so a rigorous writeup scores even if a maintainer sits on the pull request.

### 2. System-versioned tables — Tier A

`WITH SYSTEM VERSIONING`, queried via `FOR SYSTEM_TIME AS OF / BETWEEN / ALL` (SQL:2011, built into the server). Suggested build: a "Wikipedia article time machine" using revision-history data, letting a reader view and compare article versions at chosen timestamps.

**Why**: the safe alternative. Most approachable tier, strong demo narrative, clear before/after story, and a well-defined design decision to document (how historical dates are represented). Produces a portfolio repository rather than an external contribution.

### 3. Storage-engine choice — Tier B

Benchmark one dataset and workload across ≥3 engines (InnoDB, Aria, MyRocks, ...): load time, disk size, point-lookup latency, full scan, concurrent writes, crash recovery.

**Why**: pure measurement and engineering rigor, no exotic setup. A good fallback if we want disciplined benchmarking rather than a single feature.

**Not shortlisted**: *The optimizer* (high depth but needs strong query-plan literacy going in), *Online schema change* (viable, but overlaps heavily with storage-engine benchmarking), *Write a server plugin* (C/C++ toolchain and server headers — steep ramp-up for two contributors, though it is the closest option to real MariaDB engineering).

## Open decision

Options 1 and 2 are genuinely different bets, and we have not committed yet. Two things resolve it:

1. **Ask the MariaDB Foundation** which ecosystem projects they consider unverified and would most want covered — a project they name is far likelier to be accepted upstream than one we pick blindly.
2. **Run a scouting pass** on the named candidate: stand up its test environment, point it at MariaDB 12.3.3, run its suite, and count and categorise the failures. Roughly 30–60 genuine failures suggests a well-sized project; very few means too thin, very many means deep MySQL assumptions and we walk away.

If scouting shows the scope is unmanageable, we fall back to System-versioned tables.
