# Contributing workflow

We use a small, standard branch/PR workflow so the git history itself shows who did what — this is part of how the course is graded.

## Branches

- Never commit directly to `main`.
- One branch per piece of work, named `<yourname>/<short-description>`, e.g. `vedant/aggregate-function-example`, `janhavi/mariadb-setup`.

## Commits

- Small, focused commits with a clear message: what changed and why, e.g. `Add median aggregate function example with benchmark`.
- Commit as yourself — your commits are the evidence of your own contribution (git history is checked by the supervisor).

## Pull requests

1. Push your branch: `git push -u origin <branch-name>`.
2. Open a PR on GitHub into `main`.
3. The other teammate reviews it (even a quick "looks good" comment counts as code review) before merging.
4. Merge via GitHub, then delete the branch.

## Issues

Use GitHub Issues for anything worth tracking across a session: a bug found, a task to pick up later, a question for the MariaDB reviewers.

## Self-assessment and AI-use log

- Every contributor fills their own row in the current week's file under `self_assessment/` before the weekly meeting.
- Every AI-assisted change gets a line in `AI_USE_LOG.md`, added at the same time as the change (not retroactively at the end of the week).
