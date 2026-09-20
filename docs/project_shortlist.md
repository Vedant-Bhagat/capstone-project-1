# Project shortlist

Source: MariaDB Foundation project list, https://mariadb.org/bachelor_hackathon_2026-09/ (list may change during the semester — re-check before finalizing).

Both the starter and the main dish are picked from the 20 areas on that page. Work outside those areas does not count toward the grade.

## What the MariaDB Q&A session settled (17.09.2026)

Three answers from Kaj Arnö and Robert Silén shaped the choice below.

**What counts as a contribution.** The Foundation originally considered asking for MariaDB Server extensions (MDEVs) but dropped that. Kaj: *"now in this hackathon, we're actually asking for contributions on a demo level, on a documentation level… The contribution as such is the project that you are doing and you deliver it in the form of a public repository that shows how the feature works."* Robert added that at the end of the course they will list the projects somewhere central and give them publicity. So "adopted" means listed and publicised, not merged into the server.

**Upstream work is not what the course rewards.** Asked whether the Foundation would advocate for a patch we submit to an external project, Kaj: *"in this course, none of the 20 are yet listed in such a way where that would be necessary… we are on the side of anybody who makes such a contribution, but it's not advocacy as a service."* Robert's advice if we ever do this independently: contact the project early, state intentions before building, and follow their contribution rules.

**How to get help.** Not GitHub — the Foundation uses it only for code and markdown docs. Questions go to their Zulip community chat or Stack Overflow under the MariaDB tag; bugs go to Jira, after searching for duplicates.

**Self-evaluation.** The task page ends with an LLM evaluation prompt we can run ourselves against our own repository using Claude Code. Robert indicated it may later be extended to actually run the submitted solution, so the README's run instructions serve the AI evaluator as well as human readers.

## Starter — decided: **Custom Aggregate Functions**

| Candidate | What it is | Why / why not |
|---|---|---|
| **Custom aggregate functions** ✅ leaning towards this | `CREATE AGGREGATE FUNCTION ... FETCH GROUP NEXT ROW` — write your own SQL-level aggregate (median, mode, geometric mean, weighted percentile, longest streak, etc.). Not available at the SQL level in MySQL, so it's a clean "something only MariaDB has." | Small, contained, easy to demo before/after (aggregate function vs. window function vs. correlated subquery vs. app-side loop), with measurable query length/readability/execution-time differences. Good scope for a starter. |
| SQL features that save code | Demonstrate ≥2 of: `INET4`/`INET6`, `UUID`, `RETURNING`, `CREATE SEQUENCE`, `INTERSECT`/`EXCEPT`, `CREATE OR REPLACE`, `IS JSON`, invisible columns, `ROW` types, instant column changes, global temp tables, `UPDATE`/`DELETE` with CTEs. | Also a solid, low-effort starter — broader surface (many small features) rather than one focused feature. Kept as backup if the aggregate-function angle turns out too thin. |

**Decision**: confirmed with Janhavi — custom aggregate functions is the starter (both contributors' SQL examples in `sql/` implement it: `GEOMETRIC_MEAN` and `WEIGHTED_AVERAGE`).

## Main dish — decided: **Vector Search and RAG, Natively**

MariaDB 11.8 LTS added a native `VECTOR` type with HNSW indexing, so semantic search runs inside the database instead of requiring a separate vector service. The build: chunk and embed Wikipedia articles, store the vectors with a `VECTOR INDEX`, query with `VEC_DISTANCE_COSINE`, and combine semantic search with ordinary SQL predicates in a single statement. Then measure retrieval quality honestly against a brute-force baseline.

**Why this one.** Of the 20 areas, this is the one the Foundation engaged with most in the Q&A — four of the submitted questions were about it, and Kaj answered with specifics rather than principles. That gives us a gradeable target before we write any code, which none of the other areas offer. It is also Tier A, so a single local server is enough, and it is the most current skill on the list.

**What Kaj told us "good" looks like:**

- **Corpus size**: at least 1000 Wikipedia articles, which yields several times more chunks (he estimated roughly 10 per article). Small enough to manage, large enough that a table scan is no longer competitive — if the index isn't earning its place, the demo proves nothing.
- **Recall**: 98% or better against an exhaustive comparison. He was blunt that 95% is *"still frequently not considered acceptable"* and half is *"absolutely not acceptable."*
- **Hybrid search** means genuinely combining relational and vector querying, not bolting a `WHERE` clause onto a vector query. His example: a store selling books and clothing, where the category filter is an ordinary predicate and the product description is vector-indexed, so the query narrows on something absolute first and something fluffy second. The other valid shape is combining full-text and vector results into one answer.
- **Explanation quality is what is actually graded.** *"The place where you explain things is the readme… if this is something that you can show to your sibling or your parent that is not into AI and they understood roughly what it's about, then you got it."*

**Three limitations he warned us about**, all of which affect schema design:

1. Only one vector index per table, so we cannot put `WHERE` criteria across several vector indexes on the same table.
2. The indexed column must be `NOT NULL`.
3. The distance function must match the index. An index built for Euclidean distance cannot be queried with cosine distance, or the results are meaningless. Euclidean measures straight-line distance in high-dimensional space; cosine measures the angle between vectors, which is usually the better fit for language. Kaj's analogy: two stars can look adjacent in the night sky (small cosine distance) while being astronomically far apart (large Euclidean distance).

**Known risk**: vector search is roughly a year old, so it is the least mature feature we could have picked. Mitigation is that Kaj named the three sharp edges above, and said that hitting an undocumented limitation is not a problem as long as we document what we hit.

**On RAG specifically**: retrieving the right rows is only half of it. Kaj was clear that the pipeline should end in an actual generated answer, because *"the easiest way to evaluate is for you to run that through an LLM so that you do get the answer to the prompt."* The embedding model and the answering model need not be the same, and the answering model can be any provider or a local one.

## Fallback: System-versioned tables — Tier A

`WITH SYSTEM VERSIONING`, queried via `FOR SYSTEM_TIME AS OF / BETWEEN / ALL`. Build: a Wikipedia article time machine letting a reader view and compare article versions at chosen timestamps.

Kept as the fallback because it is far more mature than vector search — Kaj said its limitations section is unlikely to bite us. The failure mode he named is staying too shallow: turning system versioning on and then only writing ordinary `SELECT`s against the current state, which defeats the point of the feature.

## Considered and rejected

**Ecosystem compatibility** — this was our lead until the Q&A session. We dropped it because the entire reason for choosing it was producing a merged upstream pull request, and the session established that the course does not reward that. Kaj confirmed none of the 20 areas require upstream work, that the Foundation will not act as our advocate, and that the graded contribution is the repository itself. A separate problem stood regardless: compatibility fixes merge easily but score nothing on MariaDB depth, while MariaDB-only features score well but cross-database projects resist them on portability grounds.

Also asked about which applications the Foundation considers unverified. Kaj answered about language connectors rather than applications — C, PHP, Perl, Python and Java are the supported set, plus community connectors — and noted he was unsure whether the TypeScript and JavaScript integrations are optimal. No application was named, so we would have been picking blind.

**Storage-engine choice, the optimizer, online schema change** — all viable, none with a specification as clear as what we now have for vector search.

**Write a server plugin** — closest to real MariaDB engineering, but needs a C/C++ toolchain and server headers, and the Foundation has explicitly stopped asking for server extensions in this hackathon.

## Next steps

1. Fix the embedding model and chunking strategy, and record why we chose them.
2. Load at least 1000 Wikipedia articles and document the fetch so a reader can reproduce it.
3. Build the brute-force baseline first — recall is meaningless without it.
4. Run the Foundation's evaluation prompt against our repository before submission, and act on what it reports.
