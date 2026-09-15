# Project shortlist

Source: MariaDB Foundation project list, https://mariadb.org/bachelor_hackathon_2026-09/ (list may change during the semester — re-check before finalizing).

Both the starter and the main dish are picked from the professor's approved list (`todo_cp_01.pdf` / `team_guide.pdf`). With a 2-person team, we favored **Tier A/B projects** (single local server) over Tier C–E (external systems, multi-server clusters, C/C++ plugin toolchains) — those need more infrastructure and specialist setup than we can reliably support with two contributors.

## Starter (pick one) — leaning: **Custom Aggregate Functions**

| Candidate | What it is | Why / why not |
|---|---|---|
| **Custom aggregate functions** ✅ leaning towards this | `CREATE AGGREGATE FUNCTION ... FETCH GROUP NEXT ROW` — write your own SQL-level aggregate (median, mode, geometric mean, weighted percentile, longest streak, etc.). Not available at the SQL level in MySQL, so it's a clean "something only MariaDB has." | Small, contained, easy to demo before/after (aggregate function vs. window function vs. correlated subquery vs. app-side loop), with measurable query length/readability/execution-time differences. Good scope for a starter. |
| SQL features that save code | Demonstrate ≥2 of: `INET4`/`INET6`, `UUID`, `RETURNING`, `CREATE SEQUENCE`, `INTERSECT`/`EXCEPT`, `CREATE OR REPLACE`, `IS JSON`, invisible columns, `ROW` types, instant column changes, global temp tables, `UPDATE`/`DELETE` with CTEs. | Also a solid, low-effort starter — broader surface (many small features) rather than one focused feature. Kept as backup if the aggregate-function angle turns out too thin. |

**Decision**: confirmed with Janhavi — custom aggregate functions is the starter (both contributors' SQL examples in `sql/` implement it: `GEOMETRIC_MEAN` and `WEIGHTED_AVERAGE`).

## Main dish (pick one) — shortlisted, in order of preference

1. **System-versioned tables** — `WITH SYSTEM VERSIONING`, queried via `FOR SYSTEM_TIME AS OF / BETWEEN / ALL` (SQL:2011, built into the server). Suggested build: a "Wikipedia article time machine" using revision-history data, letting a reader view/compare article versions at chosen timestamps. **Why**: Tier A (single local server, most approachable), strong narrative, clear before/after story, and a well-defined design decision to document (how historical dates are represented) — good fit for a first main dish.
2. **Storage-engine choice** — benchmark one dataset/workload across ≥3 engines (InnoDB, Aria, MyRocks, ...): load time, disk size, point-lookup latency, full scan, concurrent writes, crash recovery. **Why**: Tier B, pure measurement/engineering rigor, no exotic setup — good if we want a project that's more about disciplined benchmarking than a single clever feature.
3. **The optimizer, opened up** — compare `EXPLAIN` vs `ANALYZE SELECT`, show histogram/cost-setting effects, find and explain a case where the optimizer picks badly. **Why**: Tier B, high depth, but needs solid query-plan literacy going in — higher risk if we're not already comfortable reading plans.

**Not shortlisted**: *Online schema change* (viable but overlaps heavily with storage-engine benchmarking work), *Write a server plugin* (requires a C/C++ toolchain and server headers — steep ramp-up for a 2-person team on a tight schedule), *Ecosystem compatibility* (requires deep-diving an external codebase before we even know the scope — harder to size upfront).

**Decision**: bring options 1–3 to the meeting; System-versioned tables is the current lead.
