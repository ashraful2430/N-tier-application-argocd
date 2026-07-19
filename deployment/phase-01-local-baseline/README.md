# Phase 1: Local Baseline

## Fresh Start Assumption

You do not need to complete any previous deployment phase before using this guide.

This phase starts from a fresh Ubuntu 24.04 machine or fresh local development environment.

This phase runs the full N-tier application locally:

- PostgreSQL database
- FastAPI backend
- React/Vite frontend

Students read this README from GitHub in the browser. Do not assume the deployment folder already exists on the student's machine. Every file that must be created is shown inline immediately after the `vim` command that creates it.

## What This Phase Teaches

By completing this phase, students will learn:

- How to prepare a local machine.
- How to clone the project using GitHub SSH.
- How to create PostgreSQL user and database.
- How to configure backend `.env`.
- How to configure frontend `.env`.
- How to create a Python virtual environment.
- How to install backend dependencies.
- How to run Alembic migrations.
- How to start the backend locally.
- How to install frontend dependencies.
- How to start the frontend locally.
- How to verify frontend, backend, and database.
- How to troubleshoot common local errors.

## Architecture

```text
Browser
  |
  | http://localhost:5173
  v
React/Vite Frontend
  |
  | VITE_API_URL=http://localhost:8000
  v
FastAPI Backend
  |
  | DATABASE_URL=postgresql+asyncpg://...
  v
PostgreSQL
```

Service map:

| Service | Runs Where | Port | Verification |
| --- | --- | ---: | --- |
| Frontend | Local machine | `5173` | `curl -I http://localhost:5173` |
| Backend | Local machine | `8000` | `curl http://localhost:8000/health` |
| PostgreSQL | Local machine | `5432` | `pg_isready` |

## Architecture Decision Guide

Running the app locally is not a toy step — it is a move you will make constantly in real jobs:

- **Reproducing a production bug.** The first question in any incident triage is "does it happen locally?" If you cannot run the stack on your machine, you cannot isolate whether the bug is code or infrastructure.
- **Onboarding to an unfamiliar codebase.** New team, week one: clone it, run it, click through it. Engineers who can bring up any project locally learn codebases in days instead of weeks.
- **Verifying before blaming.** When a deployment misbehaves, running the same commit locally splits the world in half: works locally → look at infra/config; broken locally → look at code. That one split saves hours.
- **Knowing what CI builds.** The commands in this phase are the same ones every later pipeline runs. When a pipeline fails, you debug it by running its steps locally.

What this is never for: serving anyone but yourself. The moment a second person needs the app, you are in Phase 2 territory or beyond.

## Cost Warning

This phase is free if you run it on your local machine.

It does not create AWS resources.

If you run this on EC2, the EC2 instance and EBS volume may cost money.

## Repository

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

Recommended branch:

```text
main
```

## Files Included In This Phase

This phase includes helper examples outside the README so students can inspect the exact values before creating their local files.

```text
deployment/phase-01-local-baseline/
+-- env/
|   +-- backend.env.example
|   +-- frontend.env.example
+-- notes/
|   +-- local-baseline-checklist.md
+-- README.md
```

Important:

The README still shows the full file contents inline when students create `backend/.env` and `frontend/.env` with `vim`. The files in `env/` are examples for review and copy-paste practice.

## Step 1: Install Base Tools

Run this command from: a fresh Ubuntu 24.04 machine

```bash
sudo apt update
sudo apt install -y git curl vim jq tree ca-certificates python3 python3-venv python3-pip postgresql postgresql-contrib
```

Install Node.js 22:

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
```

Verify:

```bash
python3 --version
pip3 --version
node --version
npm --version
psql --version
git --version
```

Expected:

```text
Python 3.12 or newer
Node.js v22.x
npm version shown
PostgreSQL version shown
Git version shown
```

Why this step exists:

The backend needs Python. The frontend needs Node.js and npm. PostgreSQL stores app data. Git clones the repository. curl and jq help test API responses.

Reference:

- Python venv: https://docs.python.org/3/library/venv.html
- NodeSource distributions: https://github.com/nodesource/distributions
- PostgreSQL Ubuntu packages: https://www.postgresql.org/download/linux/ubuntu/

## Step 2: Create GitHub SSH Key

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "ntier-launchboard-phase-1" -f ~/.ssh/ntier_launchboard_github_key
cat ~/.ssh/ntier_launchboard_github_key.pub
```

Add the public key to GitHub:

```text
GitHub
Settings
SSH and GPG keys
New SSH key
```

Create SSH config:

```bash
vim ~/.ssh/config
```

Paste:

```text
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/ntier_launchboard_github_key
  IdentitiesOnly yes
```

Save with:

```text
:wq
```

Secure permissions and test:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/config
chmod 600 ~/.ssh/ntier_launchboard_github_key
chmod 644 ~/.ssh/ntier_launchboard_github_key.pub
ssh -T git@github.com
```

Why this step exists:

The local machine needs GitHub SSH access to clone the repository securely.

Reference:

- GitHub SSH documentation: https://docs.github.com/en/authentication/connecting-to-github-with-ssh

## Step 3: Clone The Project

Run:

```bash
sudo mkdir -p /opt/ntier-launchboard
sudo chown -R "$USER:$USER" /opt/ntier-launchboard
cd /opt/ntier-launchboard
git clone git@github.com:ashraful2430/N-tier-application.git app-source
cd app-source
git branch --show-current
tree -L 2 -a
```

Expected branch:

```text
main
```

Expected folders:

```text
backend
frontend
deployment
docs
```

Why this step exists:

The app source must exist locally before dependencies, environment files, migrations, and servers can run.

## Step 4: Start PostgreSQL

Run:

```bash
sudo systemctl enable postgresql
sudo systemctl start postgresql
sudo systemctl status postgresql --no-pager
```

Verify:

```bash
pg_isready
```

Expected:

```text
accepting connections
```

Why this step exists:

The backend readiness endpoint depends on PostgreSQL. If PostgreSQL is stopped, `/ready` fails.

## Step 5: Create PostgreSQL User And Database

Run:

```bash
sudo -u postgres psql
```

Inside `psql`, paste:

```sql
CREATE USER launchboard_user WITH PASSWORD 'launchboard_pass';
CREATE DATABASE launchboard OWNER launchboard_user;
GRANT ALL PRIVILEGES ON DATABASE launchboard TO launchboard_user;
\q
```

Verify:

```bash
psql "postgresql://launchboard_user:launchboard_pass@localhost:5432/launchboard" -c "select current_database(), current_user;"
```

Expected:

```text
launchboard
launchboard_user
```

Why this step exists:

The backend should connect using an application database user instead of the default PostgreSQL admin user.

Security note:

`launchboard_pass` is a lab password. Use a stronger password for real production.

Reference:

- PostgreSQL create user: https://www.postgresql.org/docs/current/sql-createuser.html
- PostgreSQL create database: https://www.postgresql.org/docs/current/sql-createdatabase.html

## Step 6: Create Backend Environment File

Run:

```bash
cd /opt/ntier-launchboard/app-source/backend
vim .env
```

Paste:

```env
APP_NAME=DevOps LaunchBoard API
APP_ENV=local
DATABASE_URL=postgresql+asyncpg://launchboard_user:launchboard_pass@localhost:5432/launchboard
CORS_ORIGINS=http://localhost:5173
SEED_DEMO_DATA=true
```

Save with:

```text
:wq
```

Why this file exists:

The backend reads runtime settings from `.env`. This file tells the API which database to use and which frontend origin is allowed through CORS.

What each value means:

- `APP_NAME` appears in the FastAPI app metadata.
- `APP_ENV=local` labels responses as local environment.
- `DATABASE_URL` points SQLAlchemy async engine to PostgreSQL.
- `CORS_ORIGINS` allows the Vite frontend to call the backend in the browser.
- `SEED_DEMO_DATA=true` creates demo rows when the backend starts.

Important:

Do not commit real `.env` files.

Reference:

- Pydantic Settings: https://docs.pydantic.dev/latest/concepts/pydantic_settings/
- FastAPI CORS: https://fastapi.tiangolo.com/tutorial/cors/

## Step 7: Install Backend Dependencies

Run:

```bash
cd /opt/ntier-launchboard/app-source/backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -e ".[dev]"
```

Verify:

```bash
python --version
pip list
```

Why this step exists:

The virtual environment isolates backend Python packages from the system Python. `pip install -e ".[dev]"` installs the backend package and developer tools defined in `pyproject.toml`.

## Step 8: Run Database Migrations

Run:

```bash
cd /opt/ntier-launchboard/app-source/backend
source .venv/bin/activate
alembic upgrade head
```

Verify tables:

```bash
psql "postgresql://launchboard_user:launchboard_pass@localhost:5432/launchboard" -c "\dt"
```

Expected:

```text
Tables are listed.
```

Why this step exists:

Migrations create the database tables required by the app. Without migrations, the backend may start but API routes that query the database will fail.

Reference:

- Alembic tutorial: https://alembic.sqlalchemy.org/en/latest/tutorial.html

## Step 9: Start Backend

Run this command from: `/opt/ntier-launchboard/app-source/backend`

```bash
source .venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Keep this terminal open.

Open a second terminal and test:

```bash
curl -s http://localhost:8000/health | jq
curl -s http://localhost:8000/ready | jq
curl -s http://localhost:8000/api/summary | jq
```

Expected:

```json
{
  "status": "ok",
  "environment": "local"
}
```

Why this step exists:

This confirms the API process runs and can connect to PostgreSQL.

Backend URLs:

```text
http://localhost:8000/health
http://localhost:8000/ready
http://localhost:8000/docs
```

## Step 10: Create Frontend Environment File

Open a new terminal.

Run:

```bash
cd /opt/ntier-launchboard/app-source/frontend
vim .env
```

Paste:

```env
VITE_API_URL=http://localhost:8000
```

Save with:

```text
:wq
```

Why this file exists:

The browser code needs to know where the backend API is running. Vite exposes variables that start with `VITE_` to frontend code.

Reference:

- Vite environment variables: https://vite.dev/guide/env-and-mode

## Step 11: Install Frontend Dependencies

Run:

```bash
cd /opt/ntier-launchboard/app-source/frontend
npm install
```

Verify:

```bash
npm run build
```

Why this step exists:

The frontend needs npm packages before it can run or build. `npm run build` confirms TypeScript and Vite can produce a production build.

## Step 12: Start Frontend

Run:

```bash
cd /opt/ntier-launchboard/app-source/frontend
npm run dev -- --host 0.0.0.0
```

Open:

```text
http://localhost:5173
```

Verify from terminal:

```bash
curl -I http://localhost:5173
```

Expected:

```text
HTTP/1.1 200 OK
```

Why this step exists:

This starts the browser UI and confirms it can be served locally.

## Step 13: Verify Full App Flow

In the browser:

1. Open `http://localhost:5173`.
2. Confirm the dashboard loads.
3. Confirm service cards or deployment data appear.
4. Create a deployment if the UI supports it.
5. Refresh the page and confirm data still loads.

In terminal:

```bash
curl -s http://localhost:8000/api/services | jq
curl -s http://localhost:8000/api/deployments | jq
curl -s http://localhost:8000/api/summary | jq
```

Expected:

```text
JSON data returns from backend.
Frontend displays data from backend.
PostgreSQL persists app data.
```

## Logs And Debugging

Backend logs:

```text
Visible in the terminal running uvicorn.
```

Frontend logs:

```text
Visible in the terminal running npm run dev.
```

PostgreSQL status:

```bash
sudo systemctl status postgresql --no-pager
```

Database connection:

```bash
psql "postgresql://launchboard_user:launchboard_pass@localhost:5432/launchboard" -c "select 1;"
```

## Troubleshooting

### Problem 1: Python Version Too Old

Check:

```bash
python3 --version
```

Cause:

```text
The backend requires Python 3.12 or newer.
```

Fix:

```text
Use Ubuntu 24.04 or install Python 3.12+ before continuing.
```

### Problem 2: Backend Cannot Connect To Database

Check:

```bash
sudo systemctl status postgresql --no-pager
pg_isready
cat /opt/ntier-launchboard/app-source/backend/.env
```

Common causes:

```text
PostgreSQL is stopped.
Database user was not created.
Password in DATABASE_URL is wrong.
Database name is wrong.
Migrations were not run.
```

### Problem 3: Frontend Cannot Call Backend

Check:

```bash
cat /opt/ntier-launchboard/app-source/frontend/.env
curl -s http://localhost:8000/health
```

Common causes:

```text
Backend is not running.
VITE_API_URL is wrong.
CORS_ORIGINS does not include http://localhost:5173.
Frontend was not restarted after changing .env.
```

### Problem 4: Port Already In Use

Check:

```bash
sudo ss -tulpn | grep ':8000\|:5173\|:5432'
```

Fix:

```text
Stop the old process or choose another port and update env files.
```

## Cleanup

Stop frontend:

```text
Press CTRL + C in the frontend terminal.
```

Stop backend:

```text
Press CTRL + C in the backend terminal.
```

Optional database cleanup:

```bash
sudo -u postgres psql
```

Inside `psql`:

```sql
DROP DATABASE IF EXISTS launchboard;
DROP USER IF EXISTS launchboard_user;
\q
```

Optional project cleanup:

```bash
sudo rm -rf /opt/ntier-launchboard
```

## Production Checklist

Before moving to the next phase, confirm:

```text
[ ] GitHub SSH clone works
[ ] Project is on main branch
[ ] PostgreSQL is running
[ ] launchboard_user exists
[ ] launchboard database exists
[ ] backend/.env exists
[ ] frontend/.env exists
[ ] Python virtual environment exists
[ ] Backend dependencies installed
[ ] Alembic migrations completed
[ ] Backend /health works
[ ] Backend /ready works
[ ] Frontend dependencies installed
[ ] Frontend build works
[ ] Frontend dev server opens
[ ] Frontend can call backend
[ ] API returns service and deployment data
```

## What To Do Next

Move to:

```text
Phase 2: Bare-Metal EC2 Deployment
```

Why:

Phase 1 proves the app works locally. Phase 2 teaches how to deploy the same app manually on a Linux EC2 server with production-style services.
