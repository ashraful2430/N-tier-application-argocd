# Phase 2: Bare-Metal EC2 Deployment

## Fresh Start Assumption

You do not need to complete any previous deployment phase before using this guide.

This phase starts from a clean AWS account or clean AWS lab environment and a fresh Ubuntu EC2 server.

This phase deploys the N-tier application manually on one EC2 instance:

- PostgreSQL runs on the EC2 server.
- FastAPI backend runs as a systemd service.
- React/Vite frontend is built into static files.
- Nginx serves the frontend and reverse proxies backend API routes.
- Optional Certbot can add HTTPS when you have a domain.

Students read this README from GitHub in the browser. Do not assume the deployment folder already exists on the EC2 server. Every file that must be created is shown inline immediately after the `vim` command that creates it.

No shell scripts are required in this phase.

## What This Phase Teaches

By completing this phase, students will learn:

- How to create an EC2 server.
- How to configure a safe security group.
- How to SSH into Ubuntu EC2.
- How to create a GitHub SSH key on the server.
- How to clone the project using SSH.
- How to install Python, Node.js, PostgreSQL, and Nginx manually.
- How to create a Linux service user.
- How to create a PostgreSQL app user and database.
- How to create backend and frontend environment files.
- How to install backend dependencies.
- How to run Alembic migrations.
- How to build the frontend for production.
- How to serve the frontend through Nginx.
- How to run FastAPI with systemd.
- How to proxy API traffic through Nginx.
- How to verify frontend, backend, database, logs, rollback, and cleanup.

## Architecture

```text
User Browser
  |
  | HTTP or HTTPS
  v
Nginx on EC2
  |
  +-- serves frontend static files from /var/www/devops-launchboard
  |
  +-- proxies /api, /health, and /ready to FastAPI
        |
        v
      FastAPI backend on 127.0.0.1:8000
        |
        v
      PostgreSQL on 127.0.0.1:5432
```

Service map:

| Service | Runs Where | Port | Public Access | Purpose |
| --- | --- | ---: | --- | --- |
| Nginx | EC2 | `80`, optional `443` | Yes | Public entry point |
| Frontend | Static files | Served by Nginx | Yes | Browser UI |
| Backend | systemd service | `8000` | No | FastAPI API |
| PostgreSQL | EC2 | `5432` | No | Database |

Important idea:

Users should reach the backend through Nginx only. Do not expose backend port `8000` publicly.

## Architecture Decision Guide

Use Phase 2 when:

- You want students to understand Linux deployment deeply.
- You want to learn users, folders, permissions, logs, systemd, Nginx, PostgreSQL, and ports.
- You are deploying a small app on one server.
- You want a manual foundation before Docker and Kubernetes.

Do not use Phase 2 when:

- You need automatic scaling.
- You need high availability.
- You need managed database backups.
- You need zero-downtime deployment.
- You want container orchestration.

Production note:

This is production-style for a single server, but not highly available. Real production should also consider managed PostgreSQL, automated backups, CI/CD, monitoring, TLS renewal, vulnerability scanning, and infrastructure as code.

## Cost Warning

This phase can create AWS charges:

| Resource | Cost Risk | Why |
| --- | --- | --- |
| EC2 instance | Medium | Billed while running |
| EBS volume | Medium | Storage attached to EC2 |
| Elastic IP | Medium | Charged if unused or in some public IPv4 cases |
| Data transfer | Low to medium | Depends on traffic |
| Snapshot | Medium | Charged if created |

Cost-safe practice:

- Use one small EC2 instance.
- Do not create a NAT Gateway.
- Do not create a Load Balancer.
- Do not create RDS for this phase.
- Stop or terminate the server after practice.
- Delete unused EBS volumes and snapshots.
- Create an AWS Budget alert.

Reference:

- AWS Budgets: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html
- AWS EC2 documentation: https://docs.aws.amazon.com/ec2/

## Recommended AWS Setup

| Item | Recommended Value |
| --- | --- |
| AWS Region | `us-east-1` or closest region |
| EC2 Name | `devops-launchboard-phase-2` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.micro` or `t3.small` |
| Storage | 20 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | `devops-launchboard-phase-2-sg` |
| SSH | Port `22`, your IP only |
| HTTP | Port `80`, anywhere |
| HTTPS | Port `443`, anywhere if using SSL |
| Backend | Port `8000`, do not expose publicly |
| PostgreSQL | Port `5432`, do not expose publicly |

Security group inbound rules:

| Type | Port | Source | Purpose |
| --- | ---: | --- | --- |
| SSH | `22` | Your IP only | Server access |
| HTTP | `80` | `0.0.0.0/0` | Public app |
| HTTPS | `443` | `0.0.0.0/0` | Public app with SSL |

Do not open:

```text
8000
5432
5173
```

Why:

- `8000` is private backend traffic.
- `5432` is private database traffic.
- `5173` is a Vite development server port and should not be used in production.

## Deployment Plan

You will follow this flow:

1. Create EC2 server.
2. SSH into EC2.
3. Install base tools.
4. Install Python, Node.js, PostgreSQL, and Nginx.
5. Create Linux service user.
6. Create GitHub SSH key on EC2.
7. Clone the project from `main`.
8. Create PostgreSQL user and database.
9. Create backend environment file.
10. Create frontend production environment file.
11. Install backend dependencies.
12. Run Alembic migrations.
13. Test backend manually.
14. Build frontend.
15. Publish frontend to Nginx web root.
16. Create systemd service files.
17. Start backend through systemd.
18. Create Nginx config.
19. Verify app through public IP.
20. Optional domain and HTTPS.
21. Rollback.
22. Cleanup.

## Step 1: Create EC2 Server

Run this step from: AWS Console

Create an EC2 instance with:

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-2` |
| AMI | Ubuntu Server 24.04 LTS |
| Architecture | 64-bit x86 |
| Instance Type | `t3.micro` or `t3.small` |
| Key Pair | `devops-launchboard-key` |
| Storage | 20 GB gp3 |
| Public IP | Enabled |

Security group inbound rules:

| Type | Port | Source |
| --- | ---: | --- |
| SSH | `22` | Your IP |
| HTTP | `80` | Anywhere |
| HTTPS | `443` | Anywhere |

Expected result:

```text
EC2 instance state: Running
Status checks: 2/2 checks passed
```

Why this step exists:

The application needs a Linux server. Security groups control which traffic can reach that server.

Reference:

- Connect to EC2 Linux instance: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-to-linux-instance.html
- EC2 security groups: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html

## Step 2: SSH Into EC2

Run this command from: your local machine where the `.pem` key exists

Replace:

- `<key-file>` with your key file
- `<public-ip>` with your EC2 public IP

```bash
chmod 400 <key-file>.pem
ssh -i <key-file>.pem ubuntu@<public-ip>
```

Command explanation:

- `chmod 400 <key-file>.pem` sets the key file to read-only for your user. SSH refuses to connect if the key file has loose permissions. This is a security requirement enforced by the SSH client.
- `ssh -i <key-file>.pem ubuntu@<public-ip>` connects to the EC2 server. `-i` tells SSH which key to use. `ubuntu` is the default user on Ubuntu EC2 instances created by AWS.

Verify:

```bash
whoami
hostname
pwd
```

Expected:

```text
ubuntu
ip-...
/home/ubuntu
```

Why this step exists:

SSH gives you terminal access to install tools, clone code, configure services, and inspect logs.

## Step 3: Update Server And Install Base Tools

Run this command from: EC2 server

```bash
cd ~
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl wget vim jq tree unzip ca-certificates gnupg lsb-release rsync software-properties-common
```

Command explanation:

- `cd ~` moves you to your home directory (`/home/ubuntu`) so you start from a known location.
- `sudo apt update` refreshes the list of available packages from Ubuntu's servers. Without this, you may install old or missing versions.
- `sudo apt upgrade -y` upgrades all installed packages to their latest versions. This applies security patches that shipped after the AMI was built.
- `sudo apt install -y git curl wget vim jq tree unzip ca-certificates gnupg lsb-release rsync software-properties-common` installs the tools needed for the rest of this deployment:
  - `git` clones the project from GitHub.
  - `curl` and `wget` download files from the internet, including the Node.js GPG key.
  - `vim` edits config files directly on the server.
  - `jq` formats and reads JSON output from API health checks.
  - `tree` shows folder structures visually, useful for verifying your project layout.
  - `unzip` extracts zip archives.
  - `ca-certificates` and `gnupg` allow apt to verify GPG-signed package sources, which you need for the Node.js repository.
  - `lsb-release` prints the Ubuntu release name, used when adding third-party package sources.
  - `rsync` copies the built frontend files into the Nginx web root efficiently.
  - `software-properties-common` provides the `add-apt-repository` command for adding extra package sources.

Verify:

```bash
git --version
curl --version
jq --version
tree --version
rsync --version
```

Why this step exists:

Fresh servers have old package metadata and may be missing tools needed for deployment.

Reference:

- Ubuntu package management: https://ubuntu.com/server/docs/how-to/software/package-management/index.html

## Step 4: Install Python, PostgreSQL, Nginx, And Node.js 22

Install Python, PostgreSQL, and Nginx:

```bash
sudo apt install -y python3 python3-venv python3-pip postgresql postgresql-contrib nginx
```

Command explanation:

- `python3` is the Python runtime. The FastAPI backend is written in Python, so this is required to run the app.
- `python3-venv` allows you to create isolated Python environments. You install the backend dependencies inside a virtual environment so they do not conflict with system Python packages.
- `python3-pip` is the Python package installer. It is used inside the virtual environment to install FastAPI, Uvicorn, SQLAlchemy, and other backend libraries.
- `postgresql` is the database engine. The app stores all its data in PostgreSQL.
- `postgresql-contrib` installs extra PostgreSQL extensions. Some apps and tools depend on these, so it is good practice to include it.
- `nginx` is the web server. It serves the built frontend files to the browser and proxies API requests to the FastAPI backend.

Install Node.js 22 using the NodeSource apt repository:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
sudo apt update
sudo apt install -y nodejs
```

Command explanation:

- `sudo install -m 0755 -d /etc/apt/keyrings` creates the directory where apt stores trusted GPG keys. The `-m 0755` flag sets correct permissions so the directory is readable by the system.
- `curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg` downloads the NodeSource GPG signing key and saves it in binary format. Apt uses this key to verify that the Node.js packages you download actually came from NodeSource and have not been tampered with.
- `echo "deb [signed-by=...] ..." | sudo tee /etc/apt/sources.list.d/nodesource.list` adds the NodeSource package repository to your system's list of package sources. Ubuntu's default repositories only include older Node.js versions. This line tells apt where to find Node.js 22.
- `sudo apt update` refreshes apt's package list so it includes the packages from the NodeSource repository you just added.
- `sudo apt install -y nodejs` installs Node.js 22 and npm. Node.js is required to install frontend dependencies and build the React/Vite frontend into static files.

Why you cannot just run `sudo apt install nodejs`: Ubuntu 24.04's default repositories include Node.js 18, which is outdated for this project. NodeSource provides Node.js 22, which matches the version this app requires.

Enable services:

```bash
sudo systemctl enable postgresql
sudo systemctl start postgresql
sudo systemctl enable nginx
sudo systemctl start nginx
```

Command explanation:

- `sudo systemctl enable postgresql` tells systemd to start PostgreSQL automatically when the server reboots. Without this, PostgreSQL would be off after every restart.
- `sudo systemctl start postgresql` starts PostgreSQL immediately so you can use it now without rebooting.
- `sudo systemctl enable nginx` and `sudo systemctl start nginx` do the same for Nginx.

Verify:

```bash
python3 --version
node --version
npm --version
psql --version
systemctl status postgresql --no-pager
systemctl status nginx --no-pager
```

Why this step exists:

Python runs the backend. Node builds the frontend. PostgreSQL stores data. Nginx is the public web server and reverse proxy.

Reference:

- NodeSource distributions: https://github.com/nodesource/distributions
- PostgreSQL documentation: https://www.postgresql.org/docs/
- Ubuntu Nginx guide: https://ubuntu.com/tutorials/install-and-configure-nginx

## Step 5: Create Linux Service User And Folders

Run:

```bash
sudo useradd --system --create-home --home-dir /opt/devops-launchboard --shell /bin/bash launchboard || true
sudo mkdir -p /opt/devops-launchboard/app-source
sudo mkdir -p /etc/devops-launchboard
sudo mkdir -p /var/www/devops-launchboard
sudo chmod 755 /opt/devops-launchboard
sudo chown -R ubuntu:ubuntu /opt/devops-launchboard/app-source
sudo chown -R launchboard:launchboard /etc/devops-launchboard
sudo chown -R www-data:www-data /var/www/devops-launchboard
```

Command explanation:

- `sudo useradd --system --create-home --home-dir /opt/devops-launchboard --shell /bin/bash launchboard || true`
  - `useradd` creates a new Linux user account.
  - `--system` marks this as a system user, not a regular login user. System users have lower user IDs and are intended for running services, not for human logins.
  - `--create-home` creates a home directory for the user so the process has a place to store its files.
  - `--home-dir /opt/devops-launchboard` sets that home directory to `/opt/devops-launchboard`. The `/opt` folder is the standard Linux location for optional, self-contained application software.
  - `--shell /bin/bash` gives the user a working shell. This is needed so that systemd can start processes as this user.
  - `launchboard` is the name of the user being created.
  - `|| true` prevents the command from failing if the user already exists. This makes the command safe to run more than once.

- `sudo mkdir -p /opt/devops-launchboard/app-source` creates the folder where the cloned project code will live. The `-p` flag creates any missing parent directories and does not fail if the folder already exists.

- `sudo mkdir -p /etc/devops-launchboard` creates the folder where the backend environment file will be stored. Using `/etc` for configuration files follows standard Linux conventions. Config files in `/etc` are separate from app code, which makes them easier to manage and audit.

- `sudo mkdir -p /var/www/devops-launchboard` creates the folder where the built frontend static files will be served from. Nginx serves files from `/var/www` by convention.

- `sudo chmod 755 /opt/devops-launchboard` allows the `ubuntu` SSH user to enter the parent application folder. This is required because Linux checks parent directory permissions before it checks the child folder. Without this, `ubuntu` may own `/opt/devops-launchboard/app-source` but still get `Permission denied` when running `cd /opt/devops-launchboard`.

- `sudo chown -R ubuntu:ubuntu /opt/devops-launchboard/app-source` gives the `ubuntu` SSH user ownership of the app source folder. This lets you clone the repository and install dependencies without needing `sudo` for every command. The `-R` flag applies the change to all files and subfolders recursively.

- `sudo chown -R launchboard:launchboard /etc/devops-launchboard` gives the `launchboard` service user ownership of the config folder. systemd runs the backend as `launchboard`, so that user needs to read the environment file stored here.

- `sudo chown -R www-data:www-data /var/www/devops-launchboard` gives the `www-data` user ownership of the frontend web root. Nginx runs as `www-data` by default on Ubuntu, so it needs read access to the files it serves.

Verify:

```bash
id launchboard
ls -ld /opt/devops-launchboard /opt/devops-launchboard/app-source /etc/devops-launchboard /var/www/devops-launchboard
```

Command explanation:

- `id launchboard` prints the user ID, group ID, and group memberships for the `launchboard` user. Use this to confirm the user was created successfully.
- `ls -ld ...` lists the ownership and permissions for each folder. The `-l` flag shows detailed info and `-d` shows the directory itself rather than its contents. Check that each folder is owned by the correct user before moving on.

Why this step exists:

The app should not run as root. A dedicated `launchboard` user limits what the backend process can access. If the backend is ever compromised, the attacker only has the permissions of the `launchboard` user, not full root access to the server.

Folder purpose:

| Folder | Purpose |
| --- | --- |
| `/opt/devops-launchboard/app-source` | Application source code |
| `/etc/devops-launchboard` | Runtime environment files |
| `/var/www/devops-launchboard` | Built frontend static files |

## Step 6: Create GitHub SSH Key On EC2

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-2-ec2" -f ~/.ssh/devops_launchboard_github_key
cat ~/.ssh/devops_launchboard_github_key.pub
```

Command explanation:

- `cd ~` moves you to your home directory before creating SSH files.
- `mkdir -p ~/.ssh` creates the `.ssh` folder if it does not exist. The `-p` flag prevents an error if the folder is already there.
- `chmod 700 ~/.ssh` sets the `.ssh` folder so only your user can read, write, or enter it. SSH refuses to work if this folder has open permissions.
- `ssh-keygen -t ed25519 -C "devops-launchboard-phase-2-ec2" -f ~/.ssh/devops_launchboard_github_key` generates a new SSH key pair:
  - `-t ed25519` selects the Ed25519 algorithm, which is modern, fast, and more secure than the older RSA algorithm.
  - `-C "devops-launchboard-phase-2-ec2"` adds a comment to the key so you can identify it later in GitHub's deploy keys list.
  - `-f ~/.ssh/devops_launchboard_github_key` saves the key to a specific file instead of the default `~/.ssh/id_ed25519`. Using a named file avoids overwriting any existing keys on the server.
- `cat ~/.ssh/devops_launchboard_github_key.pub` prints the public key to your terminal so you can copy it and add it to GitHub.

Add the public key to GitHub:

```text
GitHub repository
Settings
Deploy keys
Add deploy key
```

Use:

| Field | Value |
| --- | --- |
| Title | `devops-launchboard-phase-2-ec2` |
| Key | Paste the public key |
| Allow write access | Unchecked |

Why "Allow write access" stays unchecked: this EC2 server only needs to clone and pull code. It does not need to push changes back to GitHub. Keeping write access off limits what someone can do if this server is ever compromised.

Create SSH config:

```bash
vim ~/.ssh/config
```

Paste:

```text
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/devops_launchboard_github_key
  IdentitiesOnly yes
```

Config explanation:

- `Host github.com` tells SSH this block applies when connecting to `github.com`.
- `IdentityFile ~/.ssh/devops_launchboard_github_key` tells SSH which private key to use for GitHub. Without this, SSH would try your default keys and may not find the right one.
- `IdentitiesOnly yes` forces SSH to use only the key listed above, ignoring any other keys loaded in memory.

Secure permissions:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/config
chmod 600 ~/.ssh/devops_launchboard_github_key
chmod 644 ~/.ssh/devops_launchboard_github_key.pub
```

Command explanation:

- `chmod 600 ~/.ssh/config` makes the SSH config file readable only by your user. SSH will refuse to use the config file if other users can read it.
- `chmod 600 ~/.ssh/devops_launchboard_github_key` locks down the private key. SSH will refuse to use the key if permissions are too open.
- `chmod 644 ~/.ssh/devops_launchboard_github_key.pub` makes the public key readable by other users. Public keys are not secret, so this is safe.

Test:

```bash
ssh -T git@github.com
```

Expected result:

```text
Hi USERNAME! You've successfully authenticated, but GitHub does not provide shell access.
```

This message is successful. GitHub does not open a shell session, but SSH authentication worked.

Why this step exists:

The EC2 server needs GitHub access to clone the app source code. SSH keys are more secure than passwords for automated server access.

Reference:

- GitHub SSH docs: https://docs.github.com/en/authentication/connecting-to-github-with-ssh

## Step 7: Clone The Project

Run:

```bash
cd /opt/devops-launchboard/app-source
git clone git@github.com:ashraful2430/N-tier-application.git .
git branch --show-current
tree -L 2 -a
```

Command explanation:

- `cd /opt/devops-launchboard/app-source` moves you into the folder created for the app source code.
- `git clone git@github.com:ashraful2430/N-tier-application.git .` clones the repository into the current directory. The `.` at the end means "clone here" instead of creating a new subfolder. This uses the SSH key you configured in Step 6.
- `git branch --show-current` prints the active branch name. Confirm it shows `main` before continuing.
- `tree -L 2 -a` shows the folder structure two levels deep, including hidden files. Use this to confirm the project files are present and look correct.

Expected branch:

```text
main
```

Keep source ownership with `ubuntu` for now:

```bash
sudo chown -R ubuntu:ubuntu /opt/devops-launchboard/app-source
sudo chmod -R u+rwX,go+rX /opt/devops-launchboard/app-source
```

Command explanation:

- `sudo chown -R ubuntu:ubuntu /opt/devops-launchboard/app-source` keeps the source code owned by the `ubuntu` SSH user. This is important because the next steps create `.env.production`, install dependencies, build the frontend, and create deployment config files from the `ubuntu` user.
- `sudo chmod -R u+rwX,go+rX /opt/devops-launchboard/app-source` gives the owner read and write access, and gives other users read and enter access where needed. This lets the `launchboard` systemd user read and execute the backend files later, without taking ownership away from `ubuntu`.

Why this step exists:

The app source must stay editable by `ubuntu` while students finish setup. If the whole `/opt/devops-launchboard` folder is changed to `launchboard:launchboard` too early, later commands such as `vim .env.production`, `python3 -m venv .venv`, `npm install`, and `npm run build` can fail with permission errors.

## Step 8: Create PostgreSQL User And Database

Run:

```bash
sudo -u postgres psql
```

Command explanation:

- `sudo -u postgres psql` opens the PostgreSQL interactive shell as the `postgres` system user. PostgreSQL is installed with a default `postgres` superuser. You use this account to create your app's database and user.

Inside `psql`, paste this. Replace `CHANGE_ME_STRONG_PASSWORD` with a strong password and remember it for the backend env file:

```sql
CREATE USER launchboard_user WITH PASSWORD 'CHANGE_ME_STRONG_PASSWORD';
CREATE DATABASE launchboard OWNER launchboard_user;
GRANT ALL PRIVILEGES ON DATABASE launchboard TO launchboard_user;
\q
```

SQL explanation:

- `CREATE USER launchboard_user WITH PASSWORD '...'` creates a dedicated database user for the app. Using a dedicated user means the app never needs the `postgres` superuser credentials.
- `CREATE DATABASE launchboard OWNER launchboard_user` creates the database and immediately assigns ownership to the app user. The owner has full control over the database.
- `GRANT ALL PRIVILEGES ON DATABASE launchboard TO launchboard_user` explicitly grants the app user all permissions on the database. This is required for the app to create tables, read, and write data.
- `\q` exits the `psql` shell.

Verify:

```bash
psql "postgresql://launchboard_user:CHANGE_ME_STRONG_PASSWORD@127.0.0.1:5432/launchboard" -c "select current_database(), current_user;"
```

Command explanation:

- This connects to the database as `launchboard_user` and runs a simple query. If it returns a row showing the database name and username, your database setup is working correctly.

Why this step exists:

The app needs its own database and database user. Using a dedicated user is safer than connecting as `postgres`.

## Step 9: Create Backend Environment File

Run:

```bash
sudo vim /etc/devops-launchboard/backend.env
```

Paste:

```env
APP_NAME="DevOps LaunchBoard API"
APP_ENV=production
DATABASE_URL=postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@127.0.0.1:5432/launchboard
CORS_ORIGINS=http://YOUR_EC2_PUBLIC_IP
SEED_DEMO_DATA=true
```

Replace:

```text
CHANGE_ME_STRONG_PASSWORD
YOUR_EC2_PUBLIC_IP
```

Password note:

For student practice, use a strong password with letters, numbers, and safe symbols only. Avoid `@`, `/`, `:`, `#`, `?`, and `&` unless you know how to URL encode them. These characters can break `DATABASE_URL` because the password is placed inside a database connection URL.

Set permissions:

```bash
sudo chown ubuntu:ubuntu /etc/devops-launchboard/backend.env
sudo chmod 600 /etc/devops-launchboard/backend.env
```

Command explanation:

- `sudo chown ubuntu:ubuntu /etc/devops-launchboard/backend.env` gives the `ubuntu` SSH user ownership of the env file. This lets you edit the file later without using `sudo`. The systemd service also reads this file using the `EnvironmentFile` directive, which runs as root before switching to the `launchboard` user.
- `sudo chmod 600 /etc/devops-launchboard/backend.env` makes the file readable and writable only by the owner. This protects your database password from being read by other users on the server.

Why this file exists:

systemd loads this file before starting the backend. The `ubuntu` SSH user also reads it during manual migration and manual backend testing steps. It keeps production runtime settings outside the Git repository.

Line explanation:

- `APP_NAME` names the FastAPI app. It is wrapped in quotes because the value contains spaces. This prevents `source /etc/devops-launchboard/backend.env` from failing during migration and manual testing steps.
- `APP_ENV=production` labels this as a production-style runtime.
- `DATABASE_URL` tells SQLAlchemy where PostgreSQL is. The `postgresql+asyncpg://` prefix tells SQLAlchemy to use the async PostgreSQL driver.
- `CORS_ORIGINS` allows the browser origin served by Nginx. The browser blocks API requests from origins not listed here.
- `SEED_DEMO_DATA=true` loads demo data on startup if the database is empty.

## Step 10: Create Frontend Production Environment File

Run:

```bash
cd /opt/devops-launchboard/app-source/frontend
vim .env.production
```

Paste:

```env
VITE_API_URL=http://YOUR_EC2_PUBLIC_IP
```

Replace:

```text
YOUR_EC2_PUBLIC_IP
```

Command explanation:

- `.env.production` is a Vite-specific file. Vite reads it automatically when you run `npm run build`. Variables in this file are embedded into the compiled JavaScript bundle at build time. They are not secret and will be visible in the browser.

Why this file exists:

Vite reads `.env.production` during `npm run build`. The browser bundle needs the public backend base URL. Since Nginx proxies backend paths on the same host, this value should be the public app origin.

Line explanation:

- `VITE_API_URL` is the base URL used by frontend browser code before adding paths like `/api/summary`. For example, the frontend will call `http://YOUR_EC2_PUBLIC_IP/api/summary`.

Reference:

- Vite env variables: https://vite.dev/guide/env-and-mode

## Step 11: Install Backend Dependencies

Run:

```bash
cd /opt/devops-launchboard/app-source/backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -e ".[dev]"
```

Command explanation:

- `cd /opt/devops-launchboard/app-source/backend` moves you into the backend directory where the Python project files are.
- `python3 -m venv .venv` creates a Python virtual environment inside a folder called `.venv`. A virtual environment is an isolated Python installation. Dependencies you install here do not affect the system Python or any other project on the server.
- `source .venv/bin/activate` activates the virtual environment. After this command, `python` and `pip` refer to the versions inside `.venv`, not the system-wide ones. You will see `(.venv)` at the start of your terminal prompt when the environment is active.
- `python -m pip install --upgrade pip` upgrades pip itself to the latest version inside the virtual environment. Older pip versions sometimes fail to install packages correctly.
- `pip install -e ".[dev]"` installs the backend package and its dependencies. The `-e` flag installs it in "editable" mode, meaning Python reads the code directly from the source folder instead of copying it. The `[dev]` part installs extra development dependencies defined in the project's `pyproject.toml`.

Verify:

```bash
cd /opt/devops-launchboard/app-source/backend
source .venv/bin/activate
python --version
pip list
```

Why this step exists:

The backend needs a Python virtual environment and dependencies before it can start.

## Step 12: Run Database Migrations

Run:

```bash
cd /opt/devops-launchboard/app-source/backend
source .venv/bin/activate
set -a
source /etc/devops-launchboard/backend.env
set +a
alembic upgrade head
```

Command explanation:

- `source .venv/bin/activate` activates the virtual environment so the `alembic` command is available.
- `set -a` tells the shell to automatically export all variables it reads next, so they become environment variables available to the `alembic` process.
- `source /etc/devops-launchboard/backend.env` loads your production settings, including the `DATABASE_URL` that Alembic needs to connect to PostgreSQL.
- `set +a` turns off the automatic export so subsequent shell variables are not exported unintentionally.
- `alembic upgrade head` runs all pending database migrations up to the latest version. Alembic reads the `DATABASE_URL` environment variable to know where to connect, then creates or updates the database tables your app needs.

Verify:

```bash
psql "postgresql://launchboard_user:CHANGE_ME_STRONG_PASSWORD@127.0.0.1:5432/launchboard" -c "\dt"
```

Command explanation:

- `\dt` lists all tables in the database. After migrations run successfully, you should see the application tables here.

Why this step exists:

Alembic creates the database tables. Without migrations, API routes that use the database can fail.

Reference:

- Alembic tutorial: https://alembic.sqlalchemy.org/en/latest/tutorial.html

## Step 13: Test Backend Manually

Run:

```bash
cd /opt/devops-launchboard/app-source/backend
source .venv/bin/activate
set -a
source /etc/devops-launchboard/backend.env
set +a
uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Command explanation:

- `uvicorn app.main:app --host 127.0.0.1 --port 8000` starts the FastAPI application directly in your terminal:
  - `app.main:app` tells Uvicorn to look for the `app` object inside `app/main.py`. This is the FastAPI application instance.
  - `--host 127.0.0.1` binds the server to localhost only. The backend is not reachable from the public internet at this stage.
  - `--port 8000` runs the server on port 8000.

Open a second SSH terminal and test:

```bash
curl -s http://127.0.0.1:8000/health | jq
curl -s http://127.0.0.1:8000/ready | jq
curl -s http://127.0.0.1:8000/api/summary | jq
```

Command explanation:

- `curl -s http://127.0.0.1:8000/health` sends an HTTP request to the health endpoint. The `-s` flag silences curl's progress output so only the response body is printed.
- `| jq` formats the JSON response so it is readable. If you see a structured JSON response, the backend is working.

Stop the manual backend:

```text
Press CTRL + C in the first terminal.
```

Why this step exists:

Manual startup shows direct errors before systemd is introduced. This prevents students from blaming systemd for app configuration problems.

Reference:

- Uvicorn deployment: https://www.uvicorn.org/deployment/
- FastAPI deployment: https://fastapi.tiangolo.com/deployment/

## Step 14: Build Frontend

Run:

```bash
cd /opt/devops-launchboard/app-source/frontend
npm install
npm run build
```

Command explanation:

- `cd /opt/devops-launchboard/app-source/frontend` moves you into the frontend directory.
- `npm install` reads the `package.json` file and downloads all the JavaScript dependencies the frontend needs. These go into a `node_modules` folder.
- `npm run build` compiles the React/Vite application into static HTML, CSS, and JavaScript files. Vite reads `.env.production` during this step and embeds the `VITE_API_URL` value into the compiled output. The result is saved to a `dist` folder.

Verify:

```bash
ls -la /opt/devops-launchboard/app-source/frontend/dist
test -f /opt/devops-launchboard/app-source/frontend/dist/index.html && echo "Frontend build exists"
```

Command explanation:

- `ls -la .../dist` lists the contents of the build output folder. You should see `index.html` and asset files here.
- `test -f .../index.html && echo "Frontend build exists"` checks whether `index.html` was created. If the file exists, it prints the confirmation message.

Why this step exists:

Production Nginx serves static files from a build output. It does not run the Vite development server.

## Step 15: Publish Frontend To Nginx Web Root

Run:

```bash
sudo rsync -av --delete /opt/devops-launchboard/app-source/frontend/dist/ /var/www/devops-launchboard/
sudo chown -R www-data:www-data /var/www/devops-launchboard
```

Command explanation:

- `sudo rsync -av --delete .../dist/ /var/www/devops-launchboard/` copies the built frontend files into the Nginx web root:
  - `-a` stands for archive mode. It copies files recursively and preserves file permissions and timestamps.
  - `-v` stands for verbose. It prints each file as it is copied so you can see what changed.
  - `--delete` removes files from the destination that no longer exist in the source. This keeps the web root clean when you rebuild after removing files.
  - The trailing `/` after `dist/` is important. It means "copy the contents of this folder," not the folder itself.
- `sudo chown -R www-data:www-data /var/www/devops-launchboard` gives the `www-data` user ownership of the published files. Nginx runs as `www-data` and needs ownership to read and serve the files.

Verify:

```bash
ls -la /var/www/devops-launchboard
test -f /var/www/devops-launchboard/index.html && echo "Frontend published"
```

Why this step exists:

Nginx serves files from `/var/www/devops-launchboard`. The build must be copied there before users can open the UI.

## Step 16: Create systemd Service Files

Create backend service:

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-02-bare-metal/systemd
vim deployment/phase-02-bare-metal/systemd/launchboard-backend.service
```

Paste:

```ini
[Unit]
Description=DevOps LaunchBoard Backend API
Wants=network-online.target postgresql.service
After=network-online.target postgresql.service

[Service]
Type=simple
User=launchboard
Group=launchboard
WorkingDirectory=/opt/devops-launchboard/app-source/backend
EnvironmentFile=/etc/devops-launchboard/backend.env
ExecStart=/opt/devops-launchboard/app-source/backend/.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000 --proxy-headers --forwarded-allow-ips=127.0.0.1
Restart=always
RestartSec=5
TimeoutStartSec=30
TimeoutStopSec=30
KillSignal=SIGTERM
StandardOutput=journal
StandardError=journal
SyslogIdentifier=launchboard-backend
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=/opt/devops-launchboard/app-source/backend

[Install]
WantedBy=multi-user.target
```

Backend service explanation:

- `[Unit]` describes the service and startup ordering.
- `Wants=network-online.target postgresql.service` asks for network and PostgreSQL to be available. `Wants` is a soft dependency: systemd will try to start them but will not fail if they are unavailable.
- `After=network-online.target postgresql.service` ensures the backend starts only after the network and PostgreSQL are ready. Without this, the backend could start before the database is up and immediately crash.
- `User=launchboard` runs the API as the app user, not root. This limits the damage if the process is ever exploited.
- `WorkingDirectory` points to the backend folder so relative imports and file paths inside the app work correctly.
- `EnvironmentFile` loads production env values from the file you created in Step 9. systemd reads this file and passes each variable to the process as an environment variable.
- `ExecStart` starts Uvicorn on private localhost port `8000`. `--proxy-headers` tells Uvicorn to trust the `X-Forwarded-For` and `X-Forwarded-Proto` headers that Nginx sends. `--forwarded-allow-ips=127.0.0.1` limits trusted headers to requests coming from localhost, preventing header spoofing from the public internet.
- `Restart=always` restarts the backend after crashes or after the process exits for any reason. `RestartSec=5` waits 5 seconds before restarting to avoid a crash loop.
- `TimeoutStartSec=30` and `TimeoutStopSec=30` give the process 30 seconds to start or stop before systemd considers it failed or kills it.
- `KillSignal=SIGTERM` sends a graceful shutdown signal so the app can finish in-flight requests before stopping.
- `StandardOutput=journal` and `StandardError=journal` send all logs to systemd's journal, so you can read them with `journalctl`.
- `SyslogIdentifier=launchboard-backend` labels log entries so you can filter them with `journalctl -u launchboard-backend`.
- `NoNewPrivileges=true` prevents the process from gaining elevated privileges, even if it calls `setuid`.
- `PrivateTmp=true` gives the process its own isolated `/tmp` directory so it cannot read other services' temporary files.
- `ProtectSystem=full` makes the system directories read-only for this process. The backend cannot modify system files.
- `ProtectHome=true` hides home directories from the process. The backend cannot read files in `/home` or `/root`.
- `ReadWritePaths=/opt/devops-launchboard/app-source/backend` explicitly allows write access only to the backend directory, overriding the read-only restriction from `ProtectSystem` for just this path.

Create frontend validation service:

```bash
vim deployment/phase-02-bare-metal/systemd/launchboard-frontend.service
```

Paste:

```ini
[Unit]
Description=DevOps LaunchBoard Frontend Static Files
After=nginx.service
Wants=nginx.service

[Service]
Type=oneshot
ExecStart=/usr/bin/test -f /var/www/devops-launchboard/index.html
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

Frontend service explanation:

- Nginx serves the frontend, so the frontend does not need a long-running Node process.
- `Type=oneshot` means this service runs a single command and then exits. It is not a continuously running process.
- `ExecStart=/usr/bin/test -f /var/www/devops-launchboard/index.html` checks whether the built frontend file exists. If the file is missing, the service fails and you get a clear error signal.
- `RemainAfterExit=yes` keeps the service in an active state after the check completes. This lets you see it as "active" in `systemctl status` even though the process already exited.

Verify runtime permissions before installing services:

```bash
sudo chmod 755 /opt/devops-launchboard
sudo chmod -R u+rwX,go+rX /opt/devops-launchboard/app-source
namei -l /opt/devops-launchboard/app-source/backend/.venv/bin/uvicorn
```

Command explanation:

- `sudo chmod 755 /opt/devops-launchboard` confirms that the `launchboard` service user can enter the parent folder.
- `sudo chmod -R u+rwX,go+rX /opt/devops-launchboard/app-source` confirms that the backend files and virtual environment are readable and executable by the `launchboard` service user.
- `namei -l .../uvicorn` shows permissions for every directory in the path to the Uvicorn executable. If any parent folder blocks access, systemd will fail with a permission error.

Install services:

```bash
sudo cp deployment/phase-02-bare-metal/systemd/launchboard-backend.service /etc/systemd/system/launchboard-backend.service
sudo cp deployment/phase-02-bare-metal/systemd/launchboard-frontend.service /etc/systemd/system/launchboard-frontend.service
sudo systemctl daemon-reload
sudo systemctl enable launchboard-backend
sudo systemctl enable launchboard-frontend
sudo systemctl restart launchboard-backend
sudo systemctl restart launchboard-frontend
```

Command explanation:

- `sudo cp .../launchboard-backend.service /etc/systemd/system/` copies the service file to the directory where systemd looks for user-defined service units.
- `sudo systemctl daemon-reload` tells systemd to re-read all service files. You must run this every time you create or modify a service file, otherwise systemd uses the old version.
- `sudo systemctl enable launchboard-backend` makes the backend service start automatically on boot.
- `sudo systemctl restart launchboard-backend` starts the backend service now. If it was already running, it stops and starts it again.

Verify:

```bash
sudo systemctl status launchboard-backend --no-pager
sudo systemctl status launchboard-frontend --no-pager
curl -s http://127.0.0.1:8000/health | jq
```

Reference:

- systemd service units: https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html
- systemctl: https://www.freedesktop.org/software/systemd/man/latest/systemctl.html

## Step 17: Create Nginx Config

Run:

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-02-bare-metal/nginx
vim deployment/phase-02-bare-metal/nginx/default.conf
```

Paste:

```nginx
server {
    listen 80;
    server_name _;

    root /var/www/devops-launchboard;
    index index.html;

    client_max_body_size 10M;

    location = /healthz {
        access_log off;
        add_header Content-Type text/plain;
        return 200 "ok";
    }

    location /api/ {
        proxy_pass http://127.0.0.1:8000/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location = /health {
        proxy_pass http://127.0.0.1:8000/health;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location = /ready {
        proxy_pass http://127.0.0.1:8000/ready;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

Nginx config explanation:

- `listen 80` accepts public HTTP traffic on port 80.
- `server_name _` is a catch-all. It matches any hostname or IP address used to reach this server. You use this before a domain name is configured.
- `root /var/www/devops-launchboard` tells Nginx where to find the frontend static files you copied in Step 15.
- `index index.html` specifies which file to serve when a request comes in for a directory path.
- `client_max_body_size 10M` allows request bodies up to 10 MB. The default is 1 MB, which may be too small for some API payloads.
- `location = /healthz` is a simple health endpoint answered by Nginx itself. It does not touch the backend. Load balancers or monitoring tools can call this to check if Nginx is alive. `access_log off` keeps this frequent health check request out of the access log.
- `location /api/` proxies all requests starting with `/api/` to the FastAPI backend on `127.0.0.1:8000`. The request path is preserved, so `/api/summary` arrives at FastAPI as `/api/summary`.
- `location = /health` and `location = /ready` proxy the backend health check endpoints. The `=` means an exact match, so only these specific paths are proxied.
- `proxy_http_version 1.1` uses HTTP/1.1 for the connection between Nginx and the backend. This is more efficient than the default HTTP/1.0.
- `proxy_set_header Host $host` forwards the original `Host` header so the backend knows which domain was requested.
- `proxy_set_header X-Real-IP $remote_addr` tells the backend the real client IP address. Without this, the backend would see all requests as coming from `127.0.0.1`.
- `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for` appends the client IP to the forwarding chain header, which logs and security tools use.
- `proxy_set_header X-Forwarded-Proto $scheme` tells the backend whether the original request used HTTP or HTTPS.
- `location / { try_files $uri $uri/ /index.html; }` serves frontend static files. If a file matching the URL path exists, Nginx serves it. If not, Nginx serves `index.html`. This is required for React single-page applications, where the browser handles routing. Without this, refreshing the page on any route other than `/` would return a 404.

Install config:

```bash
sudo cp deployment/phase-02-bare-metal/nginx/default.conf /etc/nginx/sites-available/devops-launchboard
sudo ln -sf /etc/nginx/sites-available/devops-launchboard /etc/nginx/sites-enabled/devops-launchboard
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

Command explanation:

- `sudo cp .../default.conf /etc/nginx/sites-available/devops-launchboard` copies your config file into `sites-available`, which is where Nginx stores all possible site configurations.
- `sudo ln -sf /etc/nginx/sites-available/devops-launchboard /etc/nginx/sites-enabled/devops-launchboard` creates a symbolic link in `sites-enabled`. Nginx only loads configs from `sites-enabled`. The `-s` flag creates a symlink and `-f` overwrites an existing symlink if one already exists. This pattern lets you enable or disable sites without deleting config files.
- `sudo rm -f /etc/nginx/sites-enabled/default` removes Nginx's default site, which would otherwise respond on port 80 and conflict with your app.
- `sudo nginx -t` tests your Nginx config for syntax errors. Always run this before reloading. If there is an error, Nginx prints the line number and problem.
- `sudo systemctl reload nginx` applies the new config without restarting Nginx. Reload is safer than restart because active connections are not dropped.

Verify:

```bash
curl -I http://127.0.0.1
curl -s http://127.0.0.1/health | jq
curl -s http://127.0.0.1/ready | jq
curl -s http://127.0.0.1/api/summary | jq
```

Reference:

- Nginx beginner guide: https://nginx.org/en/docs/beginners_guide.html
- Nginx proxy module: https://nginx.org/en/docs/http/ngx_http_proxy_module.html
- FastAPI behind proxy: https://fastapi.tiangolo.com/advanced/behind-a-proxy/

## Step 18: Verify Public App

From your local machine:

```bash
curl -I http://YOUR_EC2_PUBLIC_IP
curl -s http://YOUR_EC2_PUBLIC_IP/health
curl -s http://YOUR_EC2_PUBLIC_IP/ready
```

Open in browser:

```text
http://YOUR_EC2_PUBLIC_IP
```

Expected:

```text
Frontend loads.
Backend health returns ok.
Backend readiness returns ready.
API data appears in the frontend.
```

## Step 19: Optional Domain Setup

If you own a domain, create this DNS record:

| Type | Name | Value |
| --- | --- | --- |
| A | `launchboard` | `YOUR_EC2_PUBLIC_IP` |

Example:

```text
launchboard.example.com -> YOUR_EC2_PUBLIC_IP
```

Update backend env:

```bash
sudo vim /etc/devops-launchboard/backend.env
```

Set:

```env
CORS_ORIGINS=http://launchboard.example.com
```

Update frontend env:

```bash
cd /opt/devops-launchboard/app-source/frontend
vim .env.production
```

Set:

```env
VITE_API_URL=http://launchboard.example.com
```

Rebuild and publish:

```bash
cd /opt/devops-launchboard/app-source/frontend
npm run build
sudo rsync -av --delete /opt/devops-launchboard/app-source/frontend/dist/ /var/www/devops-launchboard/
sudo chown -R www-data:www-data /var/www/devops-launchboard
sudo systemctl restart launchboard-backend
sudo systemctl reload nginx
```

Why this step exists:

Domains are easier for users than IP addresses and are required for trusted HTTPS certificates.

## Step 20: Optional HTTPS With Certbot

Only run this after DNS points to the EC2 public IP.

Replace:

- `launchboard.example.com`
- `you@example.com`

```bash
sudo apt update
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d launchboard.example.com --non-interactive --agree-tos -m you@example.com --redirect
sudo nginx -t
sudo systemctl reload nginx
```

Command explanation:

- `certbot python3-certbot-nginx` installs Certbot and its Nginx plugin. The plugin modifies your Nginx config automatically to enable HTTPS.
- `sudo certbot --nginx -d launchboard.example.com` requests a free TLS certificate from Let's Encrypt for your domain and configures Nginx to use it:
  - `--non-interactive` runs without prompting for input, suitable for scripted setups.
  - `--agree-tos` accepts Let's Encrypt's terms of service.
  - `-m you@example.com` provides an email address for certificate expiry notices.
  - `--redirect` automatically adds a redirect rule so HTTP traffic is sent to HTTPS.

After HTTPS, update env values:

```bash
sudo vim /etc/devops-launchboard/backend.env
```

Set:

```env
CORS_ORIGINS=https://launchboard.example.com
```

Update frontend:

```bash
cd /opt/devops-launchboard/app-source/frontend
vim .env.production
```

Set:

```env
VITE_API_URL=https://launchboard.example.com
```

Rebuild and restart:

```bash
cd /opt/devops-launchboard/app-source/frontend
npm run build
sudo rsync -av --delete /opt/devops-launchboard/app-source/frontend/dist/ /var/www/devops-launchboard/
sudo chown -R www-data:www-data /var/www/devops-launchboard
sudo systemctl restart launchboard-backend
sudo systemctl reload nginx
```

Verify:

```bash
curl -I https://launchboard.example.com
curl -s https://launchboard.example.com/health
```

Reference:

- Certbot documentation: https://eff-certbot.readthedocs.io/en/stable/
- Let's Encrypt documentation: https://letsencrypt.org/docs/

## Logs And Debugging

Backend status:

```bash
sudo systemctl status launchboard-backend --no-pager
sudo journalctl -u launchboard-backend -n 100 --no-pager
sudo journalctl -u launchboard-backend -f
```

Command explanation:

- `systemctl status launchboard-backend` shows whether the service is running, when it last started, and the most recent log lines.
- `journalctl -u launchboard-backend -n 100 --no-pager` prints the last 100 log lines from the backend service. Use this when the service fails to start.
- `journalctl -u launchboard-backend -f` follows the log output in real time. Press `CTRL + C` to stop.

Nginx logs:

```bash
sudo tail -n 100 /var/log/nginx/error.log
sudo tail -n 100 /var/log/nginx/access.log
```

Command explanation:

- `tail -n 100 /var/log/nginx/error.log` shows the last 100 lines of Nginx's error log. Check this when you see a 502 or 504 error in the browser.
- `tail -n 100 /var/log/nginx/access.log` shows recent HTTP requests received by Nginx. Use this to verify that requests are reaching the server.

PostgreSQL:

```bash
sudo systemctl status postgresql --no-pager
sudo -u postgres psql -c "\l"
```

Command explanation:

- `systemctl status postgresql` confirms whether the database is running.
- `sudo -u postgres psql -c "\l"` lists all databases. Use this to confirm the `launchboard` database exists.

Ports:

```bash
sudo ss -tulpn | grep ':80\|:8000\|:5432'
```

Command explanation:

- `ss -tulpn` lists all open TCP and UDP ports on the server with the process name attached. The flags mean: `-t` TCP, `-u` UDP, `-l` listening sockets only, `-p` show process, `-n` show port numbers instead of service names.
- `grep ':80\|:8000\|:5432'` filters the output to show only the three ports you care about. You should see Nginx on port 80, Uvicorn on port 8000, and PostgreSQL on port 5432, all bound to their correct addresses.

## Rollback Plan

Use this when the app is broken and you need to stop public serving quickly.

```bash
sudo systemctl stop launchboard-backend || true
sudo systemctl disable launchboard-backend || true
sudo rm -f /etc/nginx/sites-enabled/devops-launchboard

if [ -f /etc/nginx/sites-available/default ]; then
  sudo ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
fi

sudo nginx -t
sudo systemctl reload nginx
```

Restore a previous Git version:

```bash
cd /opt/devops-launchboard/app-source
git log --oneline -5
git checkout PREVIOUS_COMMIT
sudo chown -R ubuntu:ubuntu /opt/devops-launchboard/app-source

cd /opt/devops-launchboard/app-source/backend
source .venv/bin/activate
pip install -e ".[dev]"
set -a
source /etc/devops-launchboard/backend.env
set +a
alembic upgrade head

cd /opt/devops-launchboard/app-source/frontend
npm install
npm run build

sudo rsync -av --delete /opt/devops-launchboard/app-source/frontend/dist/ /var/www/devops-launchboard/
sudo chown -R www-data:www-data /var/www/devops-launchboard
sudo systemctl restart launchboard-backend
sudo systemctl reload nginx
```

Why rollback exists:

Every production deployment needs a recovery path. Rollback prevents a broken deployment from staying public.

## Troubleshooting

### Problem 1: Cannot SSH

Check:

```bash
ssh -i key.pem ubuntu@YOUR_EC2_PUBLIC_IP
```

Common causes:

```text
Wrong key.
Bad key permissions.
Security group does not allow port 22 from your IP.
EC2 public IP changed.
```

### Problem 2: Backend Service Fails

Check:

```bash
sudo journalctl -u launchboard-backend -n 100 --no-pager
cat /etc/devops-launchboard/backend.env
sudo systemctl status postgresql --no-pager
```

Common causes:

```text
Wrong DATABASE_URL.
PostgreSQL is stopped.
Migrations were not run.
Virtual environment is missing dependencies.
```

### Problem 3: Frontend Loads But API Fails

Check:

```bash
cat /opt/devops-launchboard/app-source/frontend/.env.production
curl -s http://127.0.0.1:8000/health
curl -s http://127.0.0.1:8000/api/summary
curl -s http://127.0.0.1/api/summary
```

Common causes:

```text
Frontend was built with wrong VITE_API_URL.
Backend service is down.
Nginx proxy config is wrong.
CORS_ORIGINS does not match browser origin.
```

### Problem 4: Nginx 502 Bad Gateway

Check:

```bash
sudo systemctl status launchboard-backend --no-pager
sudo ss -tulpn | grep :8000
sudo nginx -t
```

Common causes:

```text
Backend is not running.
Backend listens on the wrong port.
Nginx proxy points to the wrong port.
```

### Problem 5: Readiness Fails

Check:

```bash
curl -s http://127.0.0.1:8000/ready | jq
sudo systemctl status postgresql --no-pager
psql "postgresql://launchboard_user:CHANGE_ME_STRONG_PASSWORD@127.0.0.1:5432/launchboard" -c "select 1;"
```

Common causes:

```text
Database user missing.
Database missing.
Wrong password.
PostgreSQL stopped.
```

## Cleanup

Stop services:

```bash
sudo systemctl stop launchboard-backend || true
sudo systemctl stop launchboard-frontend || true
sudo systemctl stop nginx || true
```

Remove app files:

```bash
sudo rm -rf /opt/devops-launchboard
sudo rm -rf /var/www/devops-launchboard
sudo rm -rf /etc/devops-launchboard
sudo rm -f /etc/systemd/system/launchboard-backend.service
sudo rm -f /etc/systemd/system/launchboard-frontend.service
sudo rm -f /etc/nginx/sites-enabled/devops-launchboard
sudo rm -f /etc/nginx/sites-available/devops-launchboard
sudo systemctl daemon-reload
```

Remove database:

```bash
sudo -u postgres psql
```

Inside `psql`:

```sql
DROP DATABASE IF EXISTS launchboard;
DROP USER IF EXISTS launchboard_user;
\q
```

Delete AWS resources:

```text
Terminate EC2 instance.
Delete unused EBS volumes.
Release unused Elastic IPs.
Delete snapshots.
Remove unused security groups.
Check AWS Billing dashboard.
Remove GitHub deploy key.
```

## Production Checklist

Before calling Phase 2 complete:

```text
[ ] EC2 security group exposes only 22, 80, and optional 443
[ ] SSH is restricted to your IP
[ ] Backend port 8000 is not public
[ ] PostgreSQL port 5432 is not public
[ ] GitHub SSH clone works
[ ] Project cloned from main branch
[ ] launchboard Linux user exists
[ ] PostgreSQL app user and database created
[ ] /etc/devops-launchboard/backend.env created
[ ] frontend/.env.production created
[ ] Backend dependencies installed
[ ] Alembic migrations completed
[ ] Backend works manually
[ ] Frontend build completed
[ ] Frontend copied to /var/www/devops-launchboard
[ ] systemd backend service active
[ ] frontend validation service active
[ ] Nginx config test passes
[ ] Public frontend opens
[ ] /health works through Nginx
[ ] /ready works through Nginx
[ ] /api/summary works through Nginx
[ ] Logs checked
[ ] Rollback plan reviewed
[ ] Cleanup plan reviewed
```

## Required Files Created In This Phase

```text
deployment/phase-02-bare-metal/
+-- env/
|   +-- backend.env.example
|   +-- frontend.env.example
+-- nginx/
|   +-- default.conf
+-- systemd/
    +-- launchboard-backend.service
    +-- launchboard-frontend.service
```

## Reference Documentation

| Topic | Official Link |
| --- | --- |
| AWS EC2 | https://docs.aws.amazon.com/ec2/ |
| Connect to Linux EC2 | https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-to-linux-instance.html |
| Ubuntu package management | https://ubuntu.com/server/docs/how-to/software/package-management/index.html |
| NodeSource Node.js packages | https://github.com/nodesource/distributions |
| PostgreSQL docs | https://www.postgresql.org/docs/ |
| FastAPI deployment | https://fastapi.tiangolo.com/deployment/ |
| FastAPI behind proxy | https://fastapi.tiangolo.com/advanced/behind-a-proxy/ |
| Uvicorn deployment | https://www.uvicorn.org/deployment/ |
| systemd service docs | https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html |
| Nginx docs | https://nginx.org/en/docs/ |
| Vite env variables | https://vite.dev/guide/env-and-mode |
| Certbot docs | https://eff-certbot.readthedocs.io/en/stable/ |

## What To Do Next

Move to:

```text
Phase 3: Docker Images
```

Why:

Phase 2 teaches raw Linux deployment. Phase 3 packages the same app into production Docker images so runtime dependencies become repeatable.
