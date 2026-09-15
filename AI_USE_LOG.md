# AI-use log

Per the course's AI-use policy: every AI-assisted change is logged here — tool, part touched, and a link to the prompt/session plus what it produced. Kept up to date as the code changes; add a row in the same commit as the change it describes, not retroactively.

Session reference for the entries below: https://claude.ai/code/session_01FcRqx9zst5MMVEWhSRuAaR (Claude Code, Sonnet 5)

| Date | Contributor | Tool | Part touched | Prompt / session link | Output |
|---|---|---|---|---|---|
| 2026-09-15 | Vedant | Claude Code | Repo scaffolding: README, CONTRIBUTING, .gitignore, self-assessment & AI-use-log templates, docs/reading_summary.md, docs/project_shortlist.md | Session link above — prompted to set up the team repo per `todo_cp_01.pdf`/`team_guide.pdf` requirements | commit `dd405c2` |
| 2026-09-15 | Vedant | Claude Code | MariaDB local install/verification and `sql/vedant_example.sql` (custom aggregate function starter demo, GEOMETRIC_MEAN) | Session link above | commit `7c5a0f3` |
| 2026-09-16 | Janhavi | Claude Code (CLI) | Cloned the team repo, installed/verified MariaDB locally, wrote and ran `sql/janhavi_example.sql` (`WEIGHTED_AVERAGE(value, weight)` custom aggregate function per `docs/CONTRIBUTOR_SETUP.md`), added `docs/CONTRIBUTOR_SETUP.md` to the repo, updated `docs/reading_summary.md` and `README.md` (team name), filled in Janhavi's `self_assessment/2026-09-15.md` section, opened this AI-use-log row | Local Claude Code CLI session on 2026-09-16 (not a claude.ai/code web session — no shareable link); prompt: "clone the team repo and complete the to-do 01 deliverables (traceability, commits, AI log) per the team guide and contributor setup walkthrough" | branch `janhavi/setup-and-sql-example`, see commit(s) below |
