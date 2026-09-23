# Golden Record — Custom Aggregate Functions in MariaDB

Capstone Project I at Constructor University, partnered with the **MariaDB Foundation**. Semester theme: Open Source.

**Chosen starter area: Custom Aggregate Functions.** MariaDB lets you define your own SQL-level aggregate with `CREATE AGGREGATE FUNCTION ... FETCH GROUP NEXT ROW` — something MySQL cannot do at the SQL level. This repository implements custom aggregates, runs them against sample data, and compares them side by side with the workarounds people reach for instead (inline formulas repeated at every call site, or aggregation done in application code).

## Team

| Name | GitHub |
|---|---|
| Vedant | `vedant.work543` account |
| Janhavi | `janhavi8112` |
| Pranesh | `Pranesh-Navneeth`   |
## MariaDB version

**12.3.3-MariaDB** (Windows x64 build). Every script in `sql/` was written and verified against this version.

## Setup

### 1. Install MariaDB

**Windows** (PowerShell):
```powershell
winget install --id MariaDB.Server --source winget --accept-source-agreements --accept-package-agreements
```
Installs to `C:\Program Files\MariaDB 12.3\`, and initializes the data directory at `C:\Program Files\MariaDB 12.3\data`.

**macOS** (Homebrew):
```bash
brew install mariadb
brew services start mariadb
```

**Debian/Ubuntu**:
```bash
sudo apt install mariadb-server
sudo systemctl start mariadb
```

### 2. Start the server (Windows)

With administrator rights, install and start it as a Windows service so it survives reboots:
```powershell
& "C:\Program Files\MariaDB 12.3\bin\mariadbd.exe" --install MariaDB --defaults-file="C:\Program Files\MariaDB 12.3\data\my.ini"
Start-Service MariaDB
```

Without administrator rights, run the server directly instead (it stops when you log out):
```powershell
Start-Process -FilePath "C:\Program Files\MariaDB 12.3\bin\mariadbd.exe" `
  -ArgumentList '--defaults-file="C:\Program Files\MariaDB 12.3\data\my.ini"' -WindowStyle Hidden
```

### 3. Verify the server is reachable

```powershell
& "C:\Program Files\MariaDB 12.3\bin\mariadb-admin.exe" -u root ping   # -> "mysqld is alive"
& "C:\Program Files\MariaDB 12.3\bin\mariadb.exe" -u root -e "SELECT VERSION();"
```
On macOS/Linux the client is just `mariadb`, so the same checks are `mariadb-admin -u root ping` and `mariadb -u root -e "SELECT VERSION();"`.

### 4. Clone and run the examples

```bash
git clone https://github.com/Vedant-Bhagat/capstone-project-1.git
cd capstone-project-1/sql
mariadb -u root < vedant_example.sql
mariadb -u root < janhavi_example.sql
```
On Windows, substitute the full client path for `mariadb`:
`"C:\Program Files\MariaDB 12.3\bin\mariadb.exe" -u root < vedant_example.sql`

Each script is self-contained: it creates its own database, loads its own sample data, defines the aggregate function, and prints the comparison results. Re-running a script drops and recreates its database, so it is safe to run repeatedly.

## Dataset

No external dataset download is required. Each script under [`sql/`](sql/) defines and loads its own small sample dataset inline:

- `sql/vedant_example.sql` — `exam_scores`, 10 rows of per-class exam results, used to demonstrate `GEOMETRIC_MEAN`.
- `sql/janhavi_example.sql` — `product_reviews`, 6 rows of weighted product ratings, used to demonstrate `WEIGHTED_AVERAGE(value, weight)`.

Sample data is generated inline rather than fetched so that the examples are reproducible on any machine with no network access and no import step.

## Repository layout

```
docs/                    reading summary, project shortlist
self_assessment/         weekly self-assessment (one file per week)
sql/                     MariaDB example scripts, one per contributor
AI_USE_LOG.md            traceable record of AI tool use
CONTRIBUTING.md          branching, commits, PR/code review workflow
```

## Project shortlist

See [`docs/project_shortlist.md`](docs/project_shortlist.md) for the starter and main-dish candidates and why we picked them.

## Reading summary

See [`docs/reading_summary.md`](docs/reading_summary.md) for our summary of Pro Git ch.1-2, the Open Source Guide, and MariaDB docs.

## AI use

We use AI tools in a traceable way, per the course's AI-use policy. Every use is logged in [`AI_USE_LOG.md`](AI_USE_LOG.md): which tool, which part of the work, and a link/description of the prompt and what it produced. This log is kept up to date as the code changes.
