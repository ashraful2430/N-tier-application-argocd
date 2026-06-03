# DevOps LaunchBoard

A simple 3-tier learning project that shows how a React frontend, FastAPI backend, and PostgreSQL database work together.

## Tech Stack

- Frontend: React, TypeScript, Vite, Three.js
- Backend: Python, FastAPI, SQLAlchemy, Alembic
- Database: PostgreSQL

## Deployment Learning Path

This repository includes a full `deployment/` folder with standalone phases for local setup, bare metal EC2, Docker, Docker Compose, Docker Swarm, Kubernetes, CI/CD, EKS, observability, security, advanced releases, disaster recovery, and performance validation.

Students can start from any phase because each phase explains the setup from scratch.

## AWS EC2 Setup

These steps assume an Ubuntu EC2 server.

In your EC2 security group, allow inbound traffic for:

```text
22    SSH
5173  Frontend dev server
8001  Backend API
```

Use your EC2 public IP in the examples below:

```text
EC2_PUBLIC_IP=your-ec2-public-ip
```

## 1. Install Server Tools

SSH into the EC2 server, then run:

```bash
sudo apt update
sudo apt install -y git python3 python3-venv python3-pip postgresql postgresql-contrib
```

Install Node.js 20:

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
```

Check versions:

```bash
python3 --version
node --version
npm --version
psql --version
```

## 2. Create The PostgreSQL Database

Start PostgreSQL:

```bash
sudo systemctl enable postgresql
sudo systemctl start postgresql
```

Create a database user and database:

```bash
sudo -u postgres psql
```

Inside `psql`, run:

```sql
CREATE USER launchboard_user WITH PASSWORD 'launchboard_pass';
CREATE DATABASE launchboard OWNER launchboard_user;
GRANT ALL PRIVILEGES ON DATABASE launchboard TO launchboard_user;
\q
```

The backend database URL will be:

```text
postgresql+asyncpg://launchboard_user:launchboard_pass@localhost:5432/launchboard
```

## 3. Download The Project

```bash
git clone https://github.com/ashraful2430/N-tier-application.git
cd N-tier-application
```

## 4. Configure And Run The Backend

```bash
cd backend
cp .env.example .env
nano .env
```

For EC2, `backend/.env` should look like this. Replace `YOUR_EC2_PUBLIC_IP` with your real EC2 public IP:

```env
APP_NAME=DevOps LaunchBoard API
APP_ENV=ec2
DATABASE_URL=postgresql+asyncpg://launchboard_user:launchboard_pass@localhost:5432/launchboard
CORS_ORIGINS=http://YOUR_EC2_PUBLIC_IP:5173
SEED_DEMO_DATA=true
```

Install and run the backend:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
alembic upgrade head
uvicorn app.main:app --host 0.0.0.0 --port 8001
```

Backend links:

```text
API Health: http://YOUR_EC2_PUBLIC_IP:8001/health
API Docs:   http://YOUR_EC2_PUBLIC_IP:8001/docs
```

Keep this terminal open.

## 5. Configure And Run The Frontend

Open a second SSH terminal, then run:

```bash
cd N-tier-application/frontend
cp .env.example .env
nano .env
```

For EC2, `frontend/.env` should look like this. Replace `YOUR_EC2_PUBLIC_IP` with your real EC2 public IP:

```env
VITE_API_URL=http://YOUR_EC2_PUBLIC_IP:8001
```

Install and run the frontend:

```bash
npm install
npm run dev -- --host 0.0.0.0
```

Open the app in your browser:

```text
http://YOUR_EC2_PUBLIC_IP:5173
```

## Important Notes

- If you change `backend/.env`, stop and restart the backend.
- If you change `frontend/.env`, stop and restart the frontend.
- If the browser says the API failed, check that port `8001` is open in the EC2 security group.
- If the frontend does not open, check that port `5173` is open in the EC2 security group.

## Useful Commands

Backend:

```bash
cd ~/N-tier-application/backend
source .venv/bin/activate
alembic upgrade head
uvicorn app.main:app --host 0.0.0.0 --port 8001
```

Frontend:

```bash
cd ~/N-tier-application/frontend
npm run dev -- --host 0.0.0.0
```

PostgreSQL:

```bash
sudo systemctl status postgresql
sudo -u postgres psql
```

## Deployment Files

Open the deployment guide index here:

```text
deployment/README.md
```

Each phase has its own README and production-style files. The README explains the commands, the file contents, and why each step exists.
