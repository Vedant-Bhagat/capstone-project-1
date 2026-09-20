# AI-use log

Per the course's AI-use policy: every AI-assisted change is logged here — tool, part touched, and a link to the prompt/session plus what it produced. Kept up to date as the code changes; a row is added in the same commit as the change it describes wherever possible.

Sessions referenced below:
- **S1** — Claude Code (Sonnet 5), Vedant, 2026-09-15: https://claude.ai/code/session_01FcRqx9zst5MMVEWhSRuAaR
- **S2** — Claude Code (CLI), Janhavi, 2026-09-16: local CLI session, no shareable web link.
- **S3** — Claude Code (Opus 5), Vedant, 2026-09-16: https://claude.ai/code/session_01SKpAmxHBFJND6pTkajp9pT
- **S4** — Claude Code (Opus 5), Vedant, 2026-09-19: https://claude.ai/code/session_01FcRqx9zst5MMVEWhSRuAaR

| Date | Contributor | Tool | Part touched | Prompt / session | Output |
|---|---|---|---|---|---|
| 2026-09-15 | Vedant | Claude Code (Sonnet 5) | Repo scaffolding: `README.md`, `CONTRIBUTING.md`, `.gitignore`, `self_assessment/` templates, `docs/reading_summary.md`, `docs/project_shortlist.md` | S1 — "set up the team repo per the `todo_cp_01.pdf` / `team_guide.pdf` requirements" | commit `7c3f446` |
| 2026-09-15 | Vedant | Claude Code (Sonnet 5) | Local MariaDB 12.3.3 install and verification; `sql/vedant_example.sql` (`GEOMETRIC_MEAN` custom aggregate, run against the local server before committing) | S1 | commit `4c859e6` |
| 2026-09-15 | Vedant | Claude Code (Sonnet 5) | Created this AI-use log; confirmed MariaDB version in `README.md` | S1 | commit `1f319ac` |
| 2026-09-16 | Janhavi | Claude Code (CLI) | Cloned the repo, installed and verified MariaDB locally, wrote and ran `sql/janhavi_example.sql` (`WEIGHTED_AVERAGE(value, weight)` custom aggregate); updated `docs/reading_summary.md`, `docs/project_shortlist.md` and the team table in `README.md` | S2 — "clone the team repo and complete the to-do 01 deliverables (traceability, commits, AI log) per the team guide and contributor setup walkthrough" | commits `addc21e`, `c1ac55a`, `6f4df01` — PR [#1](https://github.com/Vedant-Bhagat/capstone-project-1/pull/1) |
| 2026-09-16 | Janhavi | Claude Code (CLI) | Filled in Janhavi's section of `self_assessment/2026-09-15.md`; set the team name to "Golden Record" in `README.md` | S2 | commits `d38a576`, `1d389ae` — PR [#2](https://github.com/Vedant-Bhagat/capstone-project-1/pull/2) |
| 2026-09-16 | Vedant | Claude Code (Opus 5) | `README.md` setup instructions, dataset detail and starter-area description (to-do 02 item 2); corrected stale commit references and an inaccurate entry in this log; corrected the team name in `self_assessment/2026-09-15.md` | S3 — "fix the README setup instructions, clean up the AI-use log, and push" | commit `422e1da` |
| 2026-09-16 | Vedant | Claude Code (Opus 5) | `docs/project_shortlist.md` — added Ecosystem compatibility as a main-dish candidate, restructured the shortlist around the delivery-safety vs. external-contribution trade-off, and recorded the open decision and scouting plan | S3 — discussion of which main dish best supports a real open-source contribution; asked to add the ecosystem option to the shortlist | commit `5551c6d` |
| 2026-09-19 | Vedant | Claude Code (Opus 5) | `self_assessment/TEMPLATE.md` — added a section for Pranesh, the third team member, in the same format as the existing contributors | S4 — "add his section in the self assessment template with the same format" | commit `1439837` |
| 2026-09-21 | Vedant | Claude Code (Opus 5) | `docs/project_shortlist.md` — recorded what the 17.09 MariaDB Q&A settled, decided Vector Search and RAG as the main dish, kept System-versioned tables as fallback, and documented why Ecosystem compatibility was rejected | S4 — analysis of the meeting transcript against our open questions, then asked to decide and update the shortlist | this commit |
