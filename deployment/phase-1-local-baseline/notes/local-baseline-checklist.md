# Phase 1 Local Baseline Checklist

## Machine

| Check | Result |
| --- | --- |
| Ubuntu version checked | |
| Python version is 3.12 or newer | |
| Node.js version is installed | |
| npm version is installed | |
| PostgreSQL is installed | |
| GitHub SSH test passed | |

## Repository

| Check | Result |
| --- | --- |
| Repository cloned with SSH | |
| Branch is `main` | |
| `backend` folder exists | |
| `frontend` folder exists | |

## Database

| Check | Result |
| --- | --- |
| PostgreSQL service is running | |
| `launchboard_user` exists | |
| `launchboard` database exists | |
| Database login works | |
| Alembic migrations completed | |

## Backend

| Check | Result |
| --- | --- |
| `backend/.env` created | |
| Python virtual environment created | |
| Backend dependencies installed | |
| `/health` returns ok | |
| `/ready` returns ready | |
| `/api/summary` returns JSON | |

## Frontend

| Check | Result |
| --- | --- |
| `frontend/.env` created | |
| npm dependencies installed | |
| `npm run build` succeeds | |
| Vite dev server starts | |
| Browser opens `http://localhost:5173` | |
| Frontend can call backend | |

## Notes

Write any errors, fixes, or commands that were different on your machine.
