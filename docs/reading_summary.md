# Reading summary

Summary of the sources required for To-do 01. Both of us should still skim the originals — this is meant to save time re-finding things, not replace reading them.

## Pro Git, chapters 1–2 (https://git-scm.com/book)

**Ch.1 — About Version Control**
- Git is a *distributed* VCS: every clone has the full history, not just the latest snapshot, so almost every operation (log, diff, commit) is local and fast.
- Git stores **snapshots**, not diffs. Each commit is a snapshot of the whole project; unchanged files are just referenced, not duplicated.
- Everything is checksummed with SHA-1 before storage, so silent corruption is caught.
- Git generally only *adds* data — most actions are hard to lose permanently, which is why it's safe to experiment on a branch.
- Three states a file can be in: **modified** (changed, not saved to git yet), **staged** (marked to go into the next commit), **committed** (safely stored). These map to the working directory, the staging area (index), and the `.git` directory.

**Ch.2 — Git Basics**
- Start a repo with `git init` (new) or `git clone <url>` (existing).
- Core loop: `git status` → `git add <file>` (stage) → `git commit -m "message"`.
- `git diff` shows unstaged changes; `git diff --staged` shows staged-but-not-committed changes.
- `git log` (and `git log --oneline --graph`) to read history.
- Remotes: `git remote add origin <url>`, `git push -u origin <branch>`, `git pull` to fetch+merge.
- Undo tools: `git restore` (discard working changes), `git reset` (move HEAD/unstage), `git commit --amend` (fix the last commit) — use carefully, these can lose work if misused.

## Open Source Guides — "How to Contribute to Open Source" (https://opensource.guide/how-to-contribute/)

- **Orient yourself first**: read the project's README, `CONTRIBUTING.md`, and code of conduct before writing anything — every project has its own norms.
- **Contribution isn't only code**: triaging issues, improving docs, answering questions, and reporting clear bugs all count and are good low-friction first contributions.
- **Standard flow for a code contribution**: fork/branch → make a focused change → commit with a clear message → open a pull request that explains *what* and *why* → respond to review feedback → maintainer merges.
- **Communication etiquette**: be patient and specific, assume good faith, keep discussion public in the issue/PR so context isn't lost, and don't take review feedback personally — it's about the code.
- **Licensing matters**: check the project's license before reusing code from elsewhere, and understand what license your own contribution is released under.
- This maps directly onto what we're doing with MariaDB: small starter contribution first, then a larger main-dish contribution, going through the same fork → branch → PR → review cycle.

## MariaDB documentation (https://mariadb.com/docs/)

- Central reference for SQL syntax, storage engines (InnoDB, Aria, MyRocks, and others), server configuration, and version-specific features.
- Used as the reference while building the SQL examples in `sql/` and while narrowing the project shortlist — see `docs/project_shortlist.md` for the specific MariaDB-only features each shortlisted project leans on.

## MariaDB examples we got working

See `sql/` for the runnable scripts and their inline explanations. Summarized:
- `sql/vedant_example.sql` — see file header for what it demonstrates and how to run it.
- `sql/janhavi_example.sql` — `WEIGHTED_AVERAGE(value, weight)`, a two-argument custom aggregate function (see file header for how to run it).
- `sql/pranesh_example.sql` — `HARMONIC_MEAN` custom aggregate function, the correct way to average speeds over equal distances; compared against the inline formula (matches exactly) and against plain `AVG()` (gives the wrong, higher answer).
