# Phase 6: Kubernetes Production-Style Deployment

## How This Phase Is Structured

This phase has 12 scenarios. You go through them in order. Each scenario builds on the previous one.

Here is what you will learn in each scenario:

```text
Scenario 1  - Kubernetes Fundamentals with Kind (local cluster)
Scenario 2  - Self-Managed Kubernetes with kubeadm (single control plane)
Scenario 3  - Multi-Node Kubernetes Cluster (add 2 workers to Scenario 2)
Scenario 4  - Deploy LaunchBoard on the kubeadm cluster
Scenario 5  - NGINX Ingress Controller with MetalLB
Scenario 6  - HTTPS with Cert-Manager (free, uses Let's Encrypt)
Scenario 7  - Metrics Server
Scenario 8  - Horizontal Pod Autoscaler
Scenario 11 - ArgoCD GitOps
Scenario 12 - Production Hardening
```

Scenarios 9 and 10 (Prometheus and Grafana) are covered in a later phase.

## Important Notes Before You Start

**About AWS costs:**

Scenario 1 uses Kind on a single t3.small EC2. That is AWS free-tier eligible.

Scenarios 2 through 12 use kubeadm on t3.medium EC2 instances. t3.medium is not free tier. A t3.medium costs roughly $0.04 per hour. Three t3.medium instances running for 8 hours costs around $1.00. Stop or terminate EC2 instances when you are not using them.

**About following the guide:**

Each scenario tells you exactly what to run. Type commands manually. Do not copy-paste blindly without reading the explanation below each command. The explanation tells you why each command exists, which helps you learn.

**About the project folder:**

All work lives inside:

```text
/opt/devops-launchboard/app-source
```

Each scenario adds new files to the project. You do not delete previous scenario files unless the guide says to.

---

# Scenario 1: Kubernetes Fundamentals with Kind

## Files And Folders For This Scenario

Before you start, here is every file you will create in this scenario. Read this section first so you understand what you are building before you build it.

```text
/opt/devops-launchboard/app-source/
+-- .dockerignore                                          (root level, shared across all phases)
+-- deployment/
    +-- phase-6-kubernetes-local/
        +-- kind-config.yaml                               (Kind cluster configuration)
        +-- Dockerfile.backend                             (multi-stage Docker build for FastAPI)
        +-- Dockerfile.frontend                            (multi-stage Docker build for React/Vite)
        +-- nginx-frontend.conf                            (Nginx config for the frontend container)
        +-- k8s/
            +-- namespace.yaml                             (Kubernetes namespace for the app)
            +-- configmap.yaml                             (non-secret app configuration)
            +-- secret.example.yaml                        (example secret file, never committed with real values)
            +-- pvc.yaml                                   (persistent storage claim for PostgreSQL)
            +-- launchboard-postgres-deployment.yaml       (runs the PostgreSQL database Pod)
            +-- launchboard-postgres-service.yaml          (internal DNS name for the database)
            +-- launchboard-migration-job.yaml             (runs Alembic database migrations once)
            +-- launchboard-backend-deployment.yaml        (runs the FastAPI backend Pods)
            +-- launchboard-backend-service.yaml           (internal DNS name for the backend)
            +-- launchboard-frontend-deployment.yaml       (runs the React/Nginx frontend Pods)
            +-- launchboard-frontend-service.yaml          (internal DNS name for the frontend)
            +-- ingress.yaml                               (routes public HTTP traffic into the cluster)
            +-- hpa.yaml                                   (autoscaling rules for the backend)
            +-- kustomization.yaml                         (groups all manifests for one-command apply)
```

What each file does and why it exists:

| File | What It Does | Why You Need It |
| --- | --- | --- |
| `.dockerignore` | Tells Docker which files to exclude from the build context | Keeps secrets, caches, and node_modules out of images |
| `kind-config.yaml` | Configures the Kind cluster with port mappings and node labels | Allows port 80 and 443 traffic to reach the cluster from the EC2 host |
| `Dockerfile.backend` | Multi-stage build for the FastAPI backend | Produces a small, secure, non-root backend image |
| `Dockerfile.frontend` | Multi-stage build for React/Vite frontend | Builds React app and serves it with unprivileged Nginx |
| `nginx-frontend.conf` | Nginx server block for the frontend container | Serves static files and proxies /api calls to the backend |
| `namespace.yaml` | Creates the `devops-launchboard` Kubernetes namespace | Isolates app resources from system and other namespaces |
| `configmap.yaml` | Stores non-secret environment values | Gives Pods configuration without hardcoding values in the image |
| `secret.example.yaml` | Shows the Secret structure with placeholder values | Reference only, real secret is created with kubectl |
| `pvc.yaml` | Requests 5GB persistent disk for PostgreSQL | Without this, database data is lost when the Pod restarts |
| `launchboard-postgres-deployment.yaml` | Runs the PostgreSQL database as a Kubernetes Pod | Manages the database container lifecycle with probes and resource limits |
| `launchboard-postgres-service.yaml` | Creates `launchboard-db` DNS name inside the cluster | Backend and migration Job can reach the database by name |
| `launchboard-migration-job.yaml` | Runs Alembic migrations once when deployed | Creates database tables before the backend starts |
| `launchboard-backend-deployment.yaml` | Runs 2 FastAPI backend replicas | Handles API requests from the frontend |
| `launchboard-backend-service.yaml` | Creates `launchboard-backend` DNS name | Frontend Nginx can proxy /api calls to the backend by name |
| `launchboard-frontend-deployment.yaml` | Runs 2 React/Nginx frontend replicas | Serves the browser UI |
| `launchboard-frontend-service.yaml` | Creates `launchboard-frontend` DNS name | Ingress sends browser traffic to this Service |
| `ingress.yaml` | Defines public HTTP routing rules | Connects EC2 port 80 traffic to the frontend Service |
| `hpa.yaml` | Defines autoscaling rules for the backend | Scales backend Pods up when CPU is high, down when CPU drops |
| `kustomization.yaml` | Lists all manifests to apply together | One command deploys everything in the right order |

## What This Scenario Covers

Kind stands for Kubernetes IN Docker. It creates a Kubernetes cluster by running Kubernetes nodes as Docker containers on your EC2 server. This is a local Kubernetes cluster, meaning everything runs on one machine.

You will use this scenario to learn how Pods, Deployments, Services, ConfigMaps, Secrets, Jobs, PVCs, Ingress, rolling updates, and rollback work before moving to real multi-node Kubernetes in Scenarios 2 and 3.

Architecture:

```text
Browser
  |
  | HTTP port 80 on EC2
  v
Kind control-plane port mapping
  |
  v
Ingress Nginx Controller
  |
  v
launchboard-frontend Service (ClusterIP port 80)
  |
  v
launchboard-frontend Pods (Nginx on port 8080)
  |
  | /api, /health, /ready (proxied by frontend Nginx)
  v
launchboard-backend Service (ClusterIP port 8000)
  |
  v
launchboard-backend Pods (Uvicorn on port 8000)
  |
  v
launchboard-db Service (ClusterIP port 5432)
  |
  v
PostgreSQL Pod + PVC (data on persistent disk)
```

## Recommended AWS Setup

| Item | Value |
| --- | --- |
| EC2 Name | `devops-launchboard-phase-6-s1` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` |
| Storage | 25 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | `devops-launchboard-phase-6-sg` |

Security group inbound rules:

| Type | Port | Source | Why |
| --- | ---: | --- | --- |
| SSH | 22 | Your IP | Terminal access |
| HTTP | 80 | Anywhere | Browser traffic to the app |
| HTTPS | 443 | Anywhere | Reserved for HTTPS testing |

Do not open port 8000, 5432, or 6443 publicly. Those are internal ports.

## Step 1: Create EC2 Server

Run this step from the AWS Console.

Create one EC2 instance using the values from the table above. Make sure Public IP is enabled.

Why this step exists:

Kind runs Kubernetes nodes as Docker containers. EC2 gives you the Linux server that runs Docker, Kind, kubectl, and the application workload.

Reference:

- AWS EC2 docs: https://docs.aws.amazon.com/ec2/
- EC2 security groups: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html

## Step 2: SSH Into EC2

Run from your local machine:

```bash
chmod 400 devops-launchboard-key.pem
ssh -i devops-launchboard-key.pem ubuntu@YOUR_EC2_PUBLIC_IP
```

Command explanation:

- `chmod 400` sets the key file to read-only for your user. SSH refuses to connect if the key file has open permissions.
- `ssh -i` tells SSH which private key file to use for authentication.
- `ubuntu` is the default user on Ubuntu EC2 AMIs. It has sudo access.
- `YOUR_EC2_PUBLIC_IP` is the public IPv4 address shown in the EC2 console.

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

Reference:

- AWS SSH guide: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-linux-inst-ssh.html

## Step 3: Update Server And Install Base Tools

Run:

```bash
cd ~
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl wget vim unzip jq ca-certificates gnupg lsb-release
```

Command explanation:

- `cd ~` moves to the home directory of the ubuntu user (`/home/ubuntu`).
- `sudo apt update` refreshes the list of available packages from Ubuntu's repositories. Run this before installing anything.
- `sudo apt upgrade -y` installs newer versions of already-installed packages. The `-y` flag skips the confirmation prompt.
- `git` is used to clone the project repository from GitHub.
- `curl` downloads files and tests HTTP endpoints from the terminal.
- `wget` is an alternative downloader used in some tool install scripts.
- `vim` is the text editor used to create and edit files throughout this guide.
- `unzip` extracts zip archives if needed.
- `jq` formats JSON output so API responses are readable in the terminal.
- `ca-certificates` installs trusted certificate authority certificates so HTTPS downloads work correctly.
- `gnupg` verifies digital signatures on downloaded packages, used when adding Docker's apt repository.
- `lsb-release` reads the Ubuntu release codename, used in the Docker repository setup command.

Reference:

- Ubuntu package management: https://ubuntu.com/server/docs/package-management

## Step 4: Install Docker Engine

Run:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo ${UBUNTU_CODENAME:-$VERSION_CODENAME}) stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ubuntu
```

Command explanation:

- `sudo install -m 0755 -d /etc/apt/keyrings` creates the `/etc/apt/keyrings` directory with mode 0755, which means the owner has read/write/execute and others have read/execute. This folder holds GPG keys for third-party apt repositories.
- `curl -fsSL https://download.docker.com/linux/ubuntu/gpg` downloads Docker's official GPG signing key. `-f` fails silently on HTTP errors, `-s` hides progress output, `-S` shows errors, `-L` follows redirects.
- `sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg` converts the key from ASCII armor format to binary format that apt understands.
- `sudo chmod a+r /etc/apt/keyrings/docker.gpg` gives all users read access to the key file so apt can verify package signatures.
- `echo "deb [arch=...] ..."` constructs the Docker apt repository line. `arch=$(dpkg --print-architecture)` inserts `amd64` for x86 machines. `$(. /etc/os-release && echo ${UBUNTU_CODENAME:-$VERSION_CODENAME})` reads the Ubuntu release codename (e.g. `noble` for 24.04) from the OS config file.
- `sudo tee /etc/apt/sources.list.d/docker.list` writes the repository line to a file in the apt sources directory. `tee` writes to a file and also prints to stdout.
- `sudo apt update` refreshes package metadata now that the Docker repository has been added.
- `docker-ce` is the Docker Community Edition engine, the main Docker package.
- `docker-ce-cli` is the Docker command-line interface, the `docker` command you type in the terminal.
- `containerd.io` is the container runtime that Docker uses to actually run containers.
- `docker-buildx-plugin` adds the BuildKit-based build system to Docker, which supports multi-stage builds and better caching.
- `sudo systemctl enable docker` tells systemd to start Docker automatically when the server reboots.
- `sudo systemctl start docker` starts Docker immediately without rebooting.
- `sudo usermod -aG docker ubuntu` adds the `ubuntu` user to the `docker` group. This lets the ubuntu user run `docker` commands without `sudo`. The `-a` flag appends to existing groups instead of replacing them. The `-G docker` specifies the group to add.

Log out and SSH back in to apply the group change:

```bash
exit
ssh -i devops-launchboard-key.pem ubuntu@YOUR_EC2_PUBLIC_IP
```

Verify:

```bash
docker --version
docker info
```

Expected: Version number appears and `docker info` shows server details without a permission error.

Why this step exists:

Kind creates Kubernetes nodes as Docker containers. Without Docker, Kind has nothing to run nodes inside.

Reference:

- Docker Engine install on Ubuntu: https://docs.docker.com/engine/install/ubuntu/
- Docker post-install steps: https://docs.docker.com/engine/install/linux-postinstall/

## Step 5: Install kubectl

Run:

```bash
cd ~
curl -LO "https://dl.k8s.io/release/stable.txt"
KUBECTL_VERSION=$(cat stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl
rm stable.txt
```

Command explanation:

- `curl -LO "https://dl.k8s.io/release/stable.txt"` downloads a small text file that contains the latest stable Kubernetes version string, for example `v1.31.0`. `-L` follows redirects, `-O` saves with the original filename.
- `KUBECTL_VERSION=$(cat stable.txt)` reads that version string into a shell variable so the next download uses the exact right version.
- `curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"` downloads the kubectl binary for Linux on x86_64. The URL includes the version variable so you always get the matching version.
- `chmod +x kubectl` marks the downloaded file as executable. Without this, the shell cannot run it as a program.
- `sudo mv kubectl /usr/local/bin/kubectl` moves kubectl into `/usr/local/bin`, which is in the system PATH. This means you can type `kubectl` from any directory.
- `rm stable.txt` removes the temporary version file since it is no longer needed.

Verify:

```bash
kubectl version --client
```

Expected: Prints the kubectl client version. The server version part will show an error until a cluster is running, which is expected.

Why this step exists:

kubectl is the command-line tool you use to create, read, update, and delete every Kubernetes resource. Every step from here uses kubectl.

Reference:

- Install kubectl on Linux: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
- kubectl overview: https://kubernetes.io/docs/reference/kubectl/

## Step 6: Install Kind

Run:

```bash
cd ~
curl -Lo kind https://kind.sigs.k8s.io/dl/v0.29.0/kind-linux-amd64
chmod +x kind
sudo mv kind /usr/local/bin/kind
```

Command explanation:

- `curl -Lo kind https://kind.sigs.k8s.io/dl/v0.29.0/kind-linux-amd64` downloads the Kind binary. `-L` follows redirects, `-o kind` saves the file with the name `kind` instead of the URL filename.
- `chmod +x kind` makes the binary executable.
- `sudo mv kind /usr/local/bin/kind` places Kind in the system PATH so you can type `kind` from anywhere.

Verify:

```bash
kind version
```

Expected: Prints the Kind version, for example `kind v0.29.0`.

Why this step exists:

Kind is the tool that creates a local Kubernetes cluster by running each node as a Docker container. Without Kind, there is no cluster.

Reference:

- Kind quick start: https://kind.sigs.k8s.io/docs/user/quick-start/
- Kind releases: https://github.com/kubernetes-sigs/kind/releases

## Step 7: Create GitHub SSH Key On EC2

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-6-ec2" -f ~/.ssh/devops_launchboard_github_key
cat ~/.ssh/devops_launchboard_github_key.pub
```

Command explanation:

- `mkdir -p ~/.ssh` creates the `.ssh` directory if it does not already exist. `-p` means no error if it exists and creates parent directories as needed.
- `chmod 700 ~/.ssh` sets the directory permissions so only the owner can read, write, and enter it. SSH requires this or it refuses to use keys in that directory.
- `ssh-keygen -t ed25519` generates a new SSH key pair using the Ed25519 algorithm. Ed25519 is modern, fast, and more secure than the older RSA algorithm.
- `-C "devops-launchboard-phase-6-ec2"` adds a comment to the key. This label appears when you list keys in GitHub so you can identify which key belongs to which server.
- `-f ~/.ssh/devops_launchboard_github_key` sets the output file path. This creates two files: the private key at that path and the public key at that path plus `.pub`.
- `cat ~/.ssh/devops_launchboard_github_key.pub` prints the public key to the terminal so you can copy and paste it into GitHub.

Add the public key to GitHub:

```text
GitHub repository > Settings > Deploy keys > Add deploy key
Title: devops-launchboard-phase-6-ec2
Key: paste the public key
Allow write access: unchecked
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
  IdentityFile ~/.ssh/devops_launchboard_github_key
  IdentitiesOnly yes
```

Config file explanation:

- `Host github.com` means this block applies whenever you SSH to github.com.
- `HostName github.com` is the actual hostname to connect to.
- `User git` sets the SSH username. GitHub uses the username `git` for all SSH connections regardless of your GitHub username.
- `IdentityFile` tells SSH which private key file to use for this host.
- `IdentitiesOnly yes` tells SSH to only use the key specified here and not try other keys. This prevents confusion if you have multiple keys.

Secure the files:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/config
chmod 600 ~/.ssh/devops_launchboard_github_key
chmod 644 ~/.ssh/devops_launchboard_github_key.pub
```

Permission explanation:

- `600` means only the owner can read and write. Private keys must have this permission or SSH refuses to use them.
- `644` means the owner can read and write, others can only read. Public keys do not need to be secret.

Test:

```bash
ssh -T git@github.com
```

Expected:

```text
Hi ashraful2430! You've successfully authenticated...
```

Reference:

- GitHub SSH docs: https://docs.github.com/en/authentication/connecting-to-github-with-ssh
- GitHub deploy keys: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys

## Step 8: Clone The Repository

Run:

```bash
sudo mkdir -p /opt/devops-launchboard
sudo chown -R ubuntu:ubuntu /opt/devops-launchboard
cd /opt/devops-launchboard
git clone git@github.com:ashraful2430/N-tier-application.git app-source
cd app-source
git branch --show-current
```

Command explanation:

- `sudo mkdir -p /opt/devops-launchboard` creates the deployment directory under `/opt`. The `/opt` directory is the conventional Linux location for optional third-party software. Using it instead of the home directory keeps the project separate from personal files.
- `sudo chown -R ubuntu:ubuntu /opt/devops-launchboard` changes ownership of the directory recursively (`-R`) to the ubuntu user and ubuntu group. This means the ubuntu user can create, read, and modify files inside without needing sudo.
- `git clone git@github.com:ashraful2430/N-tier-application.git app-source` clones the repository into a subdirectory named `app-source`. Using a clear name like `app-source` instead of the default repository name makes the path more readable.
- `git branch --show-current` prints the currently checked out branch name to confirm you are on `main`.

Expected:

```text
main
```

Reference:

- Git clone documentation: https://git-scm.com/docs/git-clone

## Step 9: Create Phase 6 Working Folders

Run:

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-6-kubernetes-local/k8s
```

Command explanation:

- `mkdir -p deployment/phase-6-kubernetes-local/k8s` creates the full directory path in one command. `-p` creates all intermediate directories and does not error if they already exist. This creates both the scenario folder and the `k8s` subfolder for Kubernetes manifests.

Why this structure exists:

Keeping all phase 6 files inside `deployment/phase-6-kubernetes-local/` means each phase has its own folder. The `k8s/` subfolder separates Kubernetes manifests from Dockerfiles and Nginx configs.

## Step 10: Create Root `.dockerignore`

Run:

```bash
cd /opt/devops-launchboard/app-source
vim .dockerignore
```

Paste:

```dockerignore
.git
.github
.venv
backend/.venv
frontend/node_modules
frontend/dist
node_modules
__pycache__
**/__pycache__
*.pyc
.pytest_cache
.ruff_cache
.env
.env.*
deployment/phase-4-docker-compose/.env
deployment/phase-5-docker-swarm/secrets/*
deployment/phase-6-kubernetes-local/k8s/secret.yaml
```

Line explanation:

- `.git` excludes the entire Git history directory. It is large and has no use inside a Docker image.
- `.github` excludes GitHub Actions workflow files and PR templates.
- `.venv` and `backend/.venv` exclude Python virtual environment directories. These are local development environments and must never go into an image.
- `frontend/node_modules` excludes the Node.js dependency folder. It contains thousands of files and can be hundreds of megabytes. The image installs its own dependencies during build.
- `frontend/dist` excludes any previously built frontend output on your local machine. The image builds its own fresh output.
- `node_modules` catches any root-level node_modules that might exist.
- `__pycache__` and `**/__pycache__` exclude Python bytecode cache directories at any depth.
- `*.pyc` excludes compiled Python bytecode files.
- `.pytest_cache` and `.ruff_cache` exclude test and linter cache directories.
- `.env` and `.env.*` exclude all environment files. These contain secrets and must never go into an image.
- The `deployment/...` lines exclude environment files and secrets from other phases.
- `deployment/phase-6-kubernetes-local/k8s/secret.yaml` excludes the real secret file if a student accidentally creates it with that name.

Why this file exists at the root:

Docker builds use the entire repository root as the build context. Without `.dockerignore`, Docker sends every file including node_modules and secrets to the Docker daemon before building. This is slow and dangerous. The `.dockerignore` file tells Docker what to skip.

Reference:

- Docker build context: https://docs.docker.com/build/concepts/context/
- .dockerignore syntax: https://docs.docker.com/reference/dockerfile/#dockerignore-file

## Step 11: Create Kind Config

Run:

```bash
vim deployment/phase-6-kubernetes-local/kind-config.yaml
```

Paste:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: ingress-ready=true
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
```

Line explanation:

- `kind: Cluster` tells Kind that this YAML file describes a cluster. Kind reads this field to know what type of object to create.
- `apiVersion: kind.x-k8s.io/v1alpha4` specifies which version of the Kind configuration schema this file uses. `v1alpha4` is the current stable schema version for Kind cluster configs.
- `nodes` is a list that defines which Kubernetes nodes Kind should create. Each item in the list becomes one Docker container acting as a Kubernetes node.
- `role: control-plane` creates a node that runs the Kubernetes control plane components: the API server, etcd, scheduler, and controller manager. Kind also allows worker roles, but for this scenario one control-plane node is enough.
- `kubeadmConfigPatches` allows you to pass extra configuration to kubeadm, which Kind uses internally to initialize the cluster.
- `kind: InitConfiguration` is a kubeadm configuration object for the initial cluster setup.
- `nodeRegistration.kubeletExtraArgs` passes extra arguments to the kubelet process that runs on this node.
- `node-labels: ingress-ready=true` adds a label to the node. The official Kind Ingress Nginx manifest uses a `nodeSelector` that looks for this label when deciding which node to schedule the Ingress Controller on. Without this label, the Ingress Controller Pod cannot schedule.
- `extraPortMappings` tells Kind to map ports from the EC2 host into the Kind node container.
- `containerPort: 80` and `hostPort: 80` mean: when traffic arrives at port 80 on the EC2 host, forward it into port 80 of the Kind container. This is how public browser traffic reaches the cluster.
- `containerPort: 443` and `hostPort: 443` reserve port 443 for HTTPS if you test it later.
- `protocol: TCP` specifies the network protocol for the port mapping.

Reference:

- Kind cluster configuration: https://kind.sigs.k8s.io/docs/user/configuration/
- Kind ingress setup: https://kind.sigs.k8s.io/docs/user/ingress/

## Step 12: Create Backend Dockerfile

Run:

```bash
vim deployment/phase-6-kubernetes-local/Dockerfile.backend
```

Paste:

```dockerfile
FROM python:3.12-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

WORKDIR /app

RUN python -m venv /opt/venv

COPY backend/pyproject.toml backend/alembic.ini ./
COPY backend/app ./app
COPY backend/alembic ./alembic

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir ".[dev]"

FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="/opt/venv/bin:${PATH}"
ENV APP_ENV=production

RUN groupadd --system app \
    && useradd --system --gid app --home-dir /app --shell /usr/sbin/nologin app

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /app /app

RUN chown -R app:app /app /opt/venv

USER app

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3).read()" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
```

Line explanation:

- `FROM python:3.12-slim AS builder` starts the first stage of a multi-stage build. `python:3.12-slim` is a Debian-based Python image with only the minimum packages needed to run Python. `AS builder` gives this stage a name so the second stage can copy files from it. Using a named stage means the builder stage is not included in the final image.
- `ENV PYTHONDONTWRITEBYTECODE=1` tells Python not to write `.pyc` compiled bytecode files to disk. This keeps the image smaller and avoids stale cache files.
- `ENV PYTHONUNBUFFERED=1` forces Python to write output directly to stdout and stderr without buffering. This means logs appear in real time in `kubectl logs` instead of being delayed.
- `ENV VIRTUAL_ENV=/opt/venv` sets the path where the Python virtual environment will be created. Using a specific path makes it easy to copy just the venv between build stages.
- `ENV PATH="/opt/venv/bin:${PATH}"` adds the virtual environment's bin directory to the front of the PATH. This means when you run `python`, `pip`, `uvicorn`, or `alembic`, the shell finds the venv versions first.
- `WORKDIR /app` sets the working directory inside the container to `/app`. All subsequent `COPY` and `RUN` commands use this as the base path.
- `RUN python -m venv /opt/venv` creates the virtual environment during the build. Using a venv inside the image isolates the app's Python dependencies from the system Python.
- `COPY backend/pyproject.toml backend/alembic.ini ./` copies the dependency definition and Alembic config files into `/app` in the image. Copying these before the source code is a Docker caching trick: if these files have not changed, Docker reuses the cached layer with installed packages and skips reinstallation.
- `COPY backend/app ./app` copies the FastAPI application source code into `/app/app`.
- `COPY backend/alembic ./alembic` copies the Alembic migration files into `/app/alembic`. The migration Job needs these files to apply database schema changes.
- `RUN pip install --no-cache-dir --upgrade pip` upgrades pip to the latest version. `--no-cache-dir` prevents pip from storing downloaded packages in a cache directory, keeping the image smaller.
- `RUN pip install --no-cache-dir ".[dev]"` installs the application and its dependencies. The `.` refers to the current directory where `pyproject.toml` lives. `[dev]` includes extra dependencies defined in the dev extras group, which includes Alembic and other tools needed for migrations.
- `FROM python:3.12-slim AS runtime` starts a completely fresh second stage. This stage becomes the final image. It has no build tools, no pip cache, nothing from the builder stage except what you explicitly copy.
- `RUN groupadd --system app` creates a system group named `app`. System groups have low GIDs and are meant for services, not real users.
- `useradd --system --gid app --home-dir /app --shell /usr/sbin/nologin app` creates a system user named `app` in the `app` group. `--home-dir /app` sets the home directory. `--shell /usr/sbin/nologin` prevents anyone from logging in as this user directly, which is a security measure.
- `COPY --from=builder /opt/venv /opt/venv` copies the entire virtual environment from the builder stage into the runtime image. This is what gives the runtime image all the installed Python packages without needing pip or build tools.
- `COPY --from=builder /app /app` copies the application code from the builder stage.
- `RUN chown -R app:app /app /opt/venv` gives the non-root `app` user ownership of the app directory and virtual environment. Without this, the `app` user cannot read its own files.
- `USER app` switches from root to the `app` user for all subsequent commands. The container runs as non-root from this point forward.
- `EXPOSE 8000` documents that the container listens on port 8000. This does not actually open the port; it is metadata for humans and tools reading the Dockerfile.
- `HEALTHCHECK` defines how Docker checks if the container is healthy. Every 30 seconds it runs a Python command that tries to open `http://127.0.0.1:8000/health`. If this fails 3 times in a row, the container is marked unhealthy.
- `CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]` is the command that runs when the container starts. `uvicorn` is the ASGI server. `app.main:app` means import `app` from the `app/main.py` module. `--host 0.0.0.0` listens on all network interfaces so Kubernetes can reach it. `--proxy-headers` makes Uvicorn trust the X-Forwarded-For headers from the Nginx ingress proxy.

Reference:

- Dockerfile reference: https://docs.docker.com/reference/dockerfile/
- Multi-stage builds: https://docs.docker.com/build/building/multi-stage/
- Python Docker best practices: https://docs.docker.com/language/python/

## Step 13: Create Frontend Dockerfile

Run:

```bash
vim deployment/phase-6-kubernetes-local/Dockerfile.frontend
```

Paste:

```dockerfile
FROM node:22-alpine AS builder

WORKDIR /app

ARG VITE_API_URL=""
ENV VITE_API_URL=${VITE_API_URL}

COPY frontend/package*.json ./
RUN npm ci

COPY frontend/ ./
RUN npm run build

FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime

COPY deployment/phase-6-kubernetes-local/nginx-frontend.conf /etc/nginx/conf.d/default.conf
COPY --from=builder --chown=101:101 /app/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

Line explanation:

- `FROM node:22-alpine AS builder` uses the official Node.js 22 image based on Alpine Linux. Alpine is a minimal Linux distribution that produces very small images. This stage is used only to build the React app and will not appear in the final image.
- `WORKDIR /app` sets the working directory inside the build container.
- `ARG VITE_API_URL=""` declares a build argument with a default empty value. Build arguments are values you pass in at build time using `--build-arg`. Vite reads this during the build to know the API base URL.
- `ENV VITE_API_URL=${VITE_API_URL}` transfers the build argument into an environment variable so Vite can access it during the build process. Vite embeds environment variables starting with `VITE_` into the compiled JavaScript at build time.
- `COPY frontend/package*.json ./` copies both `package.json` and `package-lock.json` into the container. Copying these before the source code lets Docker cache the npm install layer. If these files have not changed, Docker skips the `npm ci` step on the next build.
- `RUN npm ci` installs exact versions of dependencies from `package-lock.json`. `ci` stands for clean install. Unlike `npm install`, `npm ci` deletes `node_modules` and reinstalls from scratch, guaranteeing a reproducible install.
- `COPY frontend/ ./` copies all frontend source code into the container now that dependencies are installed.
- `RUN npm run build` runs the Vite build command, which compiles React components into static HTML, CSS, and JavaScript files. Output goes to `/app/dist`.
- `FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime` starts the final stage using the official unprivileged Nginx image. This image is designed to run Nginx without root privileges, using port 8080 instead of 80. The final image does not include Node.js at all.
- `COPY deployment/phase-6-kubernetes-local/nginx-frontend.conf /etc/nginx/conf.d/default.conf` replaces the default Nginx config with the custom config you create in Step 14. The `/etc/nginx/conf.d/default.conf` path is where Nginx looks for its default site configuration.
- `COPY --from=builder --chown=101:101 /app/dist /usr/share/nginx/html` copies the compiled frontend files from the builder stage into the Nginx web root. `--chown=101:101` sets the owner to UID 101 and GID 101, which is the nginx user in the unprivileged image. Without this, Nginx cannot read the files.
- `EXPOSE 8080` documents the port Nginx listens on. The unprivileged image uses 8080 because non-root users cannot bind to ports below 1024.
- `HEALTHCHECK` runs `wget -qO- http://127.0.0.1:8080/healthz` to check if Nginx is serving. `-q` silences output, `-O-` prints the response to stdout.
- `CMD ["nginx", "-g", "daemon off;"]` starts Nginx in the foreground. `daemon off` is required in containers because Docker needs the main process to stay running. If Nginx runs as a background daemon, Docker thinks the process exited and stops the container.

Reference:

- Vite environment variables: https://vite.dev/guide/env-and-mode
- Nginx unprivileged image: https://hub.docker.com/r/nginxinc/nginx-unprivileged
- Multi-stage builds: https://docs.docker.com/build/building/multi-stage/

## Step 14: Create Frontend Nginx Config

Run:

```bash
vim deployment/phase-6-kubernetes-local/nginx-frontend.conf
```

Paste:

```nginx
server {
    listen 8080;
    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    client_max_body_size 10M;

    location = /healthz {
        access_log off;
        add_header Content-Type text/plain;
        return 200 "ok";
    }

    location /api/ {
        proxy_pass http://launchboard-backend:8000/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location = /health {
        proxy_pass http://launchboard-backend:8000/health;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location = /ready {
        proxy_pass http://launchboard-backend:8000/ready;
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

Line explanation:

- `server { }` is an Nginx server block. It defines one virtual server that handles incoming HTTP requests.
- `listen 8080` tells Nginx to listen on port 8080 inside the container. The unprivileged Nginx image cannot use port 80 because ports below 1024 require root.
- `server_name _` is a catch-all that matches any hostname. Since the frontend does not use virtual hosting, it accepts requests with any hostname.
- `root /usr/share/nginx/html` sets the document root to where the compiled React files are stored.
- `index index.html` tells Nginx that the default file to serve for directory requests is `index.html`.
- `client_max_body_size 10M` allows request bodies up to 10 megabytes. This is needed if the app allows file uploads through the API.
- `location = /healthz` is an exact match location for the `/healthz` path. The `=` modifier means only an exact match works, not `/healthz/anything`.
- `access_log off` disables access logging for health check requests so your logs are not flooded with check entries.
- `add_header Content-Type text/plain` sets the response content type.
- `return 200 "ok"` immediately responds with HTTP 200 and the body `ok`. This is the health check response for the Kubernetes readiness and liveness probes on the frontend.
- `location /api/` matches any request path starting with `/api/`. This is a prefix match.
- `proxy_pass http://launchboard-backend:8000/api/` forwards the request to the backend. `launchboard-backend` is the Kubernetes Service DNS name. Inside a Pod, Kubernetes DNS resolves this name to the backend Service's ClusterIP. The trailing slash on both the `location` path and `proxy_pass` URL is important: it strips the `/api/` prefix correctly.
- `proxy_http_version 1.1` uses HTTP 1.1 for the upstream connection. HTTP 1.1 supports connection keep-alive which is more efficient.
- `proxy_set_header Host $host` passes the original Host header to the backend so it knows which domain the request came from.
- `proxy_set_header X-Real-IP $remote_addr` passes the client's actual IP address to the backend. The backend can use this for logging.
- `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for` adds the client IP to the chain of proxy IPs. If there are multiple proxies, the backend can see the full path.
- `proxy_set_header X-Forwarded-Proto $scheme` tells the backend whether the original request was HTTP or HTTPS.
- `location = /health` and `location = /ready` are exact match locations that proxy health and readiness check requests to the corresponding backend endpoints.
- `location / { try_files $uri $uri/ /index.html; }` handles all other requests. `try_files` first looks for a file at `$uri`, then a directory at `$uri/`, and finally falls back to `/index.html`. This fallback is essential for React Router: when a user navigates to `/dashboard` directly, there is no file called `dashboard`. Nginx falls back to `index.html`, React Router reads the URL, and renders the correct page.

Reference:

- Nginx server block documentation: https://nginx.org/en/docs/http/ngx_http_core_module.html
- Nginx proxy module: https://nginx.org/en/docs/http/ngx_http_proxy_module.html
- Nginx try_files: https://nginx.org/en/docs/http/ngx_http_core_module.html#try_files

## Step 15: Create Kubernetes Manifests

All manifests go inside `deployment/phase-6-kubernetes-local/k8s/`.

Move to the project root first:

```bash
cd /opt/devops-launchboard/app-source
```

### 15.1 namespace.yaml

A Namespace is a logical boundary inside Kubernetes. Resources in one namespace are isolated from resources in other namespaces. All your application resources live inside the `devops-launchboard` namespace.

```bash
vim deployment/phase-6-kubernetes-local/k8s/namespace.yaml
```

Paste:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: devops-launchboard
  labels:
    app.kubernetes.io/name: devops-launchboard
    app.kubernetes.io/part-of: devops-launchboard
```

Line explanation:

- `apiVersion: v1` means this resource uses the core Kubernetes API group. Namespaces, Services, ConfigMaps, Secrets, and PersistentVolumeClaims all use `v1`. Resources from extension API groups like Deployments use `apps/v1`.
- `kind: Namespace` tells Kubernetes what type of object to create. The kind field maps to a specific Kubernetes resource type.
- `metadata` is a section that holds identifying information about the resource.
- `metadata.name: devops-launchboard` is the name of the namespace. Every other resource in this phase sets `namespace: devops-launchboard` to belong to this namespace.
- `labels` are key-value pairs attached to Kubernetes resources. They are used for organizing, selecting, and filtering resources.
- `app.kubernetes.io/name` and `app.kubernetes.io/part-of` are standardized Kubernetes labels defined by the Kubernetes community. Using standard label names makes your resources compatible with tools that look for these labels, such as dashboards and monitoring systems.

Reference:

- Kubernetes Namespaces: https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/
- Kubernetes recommended labels: https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/

### 15.2 configmap.yaml

A ConfigMap stores non-sensitive configuration data as key-value pairs. Pods read these values as environment variables or mounted files. Storing config in a ConfigMap instead of hardcoding it in the image means you can change configuration without rebuilding the image.

```bash
vim deployment/phase-6-kubernetes-local/k8s/configmap.yaml
```

Paste:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: launchboard-config
  namespace: devops-launchboard
data:
  APP_NAME: DevOps LaunchBoard API
  APP_ENV: production
  CORS_ORIGINS: http://YOUR_EC2_PUBLIC_IP
  SEED_DEMO_DATA: "true"
  POSTGRES_DB: launchboard
  POSTGRES_USER: launchboard_user
```

Replace `YOUR_EC2_PUBLIC_IP` with your actual EC2 public IP address.

Line explanation:

- `apiVersion: v1` uses the core Kubernetes API. ConfigMap is a core resource.
- `kind: ConfigMap` creates a ConfigMap object.
- `metadata.name: launchboard-config` names this ConfigMap. Pods reference this name when they read values from it.
- `metadata.namespace: devops-launchboard` places this ConfigMap in the app namespace. A Pod can only read ConfigMaps in its own namespace.
- `data` is the section that contains the actual configuration key-value pairs.
- `APP_NAME: DevOps LaunchBoard API` is the display name of the application, read by the FastAPI backend.
- `APP_ENV: production` tells the backend it is running in a production environment, which affects logging behavior and error responses.
- `CORS_ORIGINS: http://YOUR_EC2_PUBLIC_IP` tells the FastAPI backend which origin the browser is allowed to make API requests from. CORS (Cross-Origin Resource Sharing) is a browser security mechanism. If this value does not match the URL you open in your browser, the browser will block API responses. In Kind, the browser accesses the app through the EC2 public IP on port 80, so the CORS origin must be exactly `http://YOUR_EC2_PUBLIC_IP`.
- `SEED_DEMO_DATA: "true"` tells the backend to insert sample data into the database on first run so the dashboard is not empty.
- `POSTGRES_DB: launchboard` is the name of the PostgreSQL database to create and connect to.
- `POSTGRES_USER: launchboard_user` is the PostgreSQL username the backend uses to connect. The password comes from the Secret, not the ConfigMap.

Reference:

- Kubernetes ConfigMaps: https://kubernetes.io/docs/concepts/configuration/configmap/
- Using ConfigMaps as environment variables: https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/

### 15.3 secret.example.yaml

A Secret stores sensitive data such as passwords and connection strings. Kubernetes Secrets are base64 encoded (not encrypted by default). This file is an example only. You never commit real credentials to Git.

```bash
vim deployment/phase-6-kubernetes-local/k8s/secret.example.yaml
```

Paste:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: launchboard-secret
  namespace: devops-launchboard
type: Opaque
stringData:
  POSTGRES_PASSWORD: CHANGE_ME_STRONG_PASSWORD
  DATABASE_URL: postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@launchboard-db:5432/launchboard
```

Line explanation:

- `apiVersion: v1` uses the core API. Secret is a core Kubernetes resource.
- `kind: Secret` creates a Secret object.
- `metadata.name: launchboard-secret` names this Secret. Pods reference this name to read values from it.
- `metadata.namespace: devops-launchboard` places the Secret in the app namespace.
- `type: Opaque` means this is a generic secret with no special structure. Kubernetes also supports typed secrets like `kubernetes.io/tls` for TLS certificates and `kubernetes.io/dockerconfigjson` for registry credentials. `Opaque` is the right type for application credentials.
- `stringData` allows you to write plain text values. Kubernetes automatically base64 encodes them when storing. This is different from the `data` field which requires you to manually base64 encode values before writing them.
- `POSTGRES_PASSWORD: CHANGE_ME_STRONG_PASSWORD` is the PostgreSQL superuser password. The PostgreSQL Pod reads this to create the database user. The backend Pod reads this to authenticate.
- `DATABASE_URL: postgresql+asyncpg://...` is the full database connection string used by the FastAPI backend. The format is: `driver://user:password@host:port/database`. `postgresql+asyncpg` tells SQLAlchemy to use the async asyncpg driver. `launchboard-db` is the Kubernetes Service DNS name that resolves to the PostgreSQL Pod. The password here must exactly match `POSTGRES_PASSWORD`.

Important: This file has placeholder values. You will create the real Secret using `kubectl create secret` in Step 19. Never replace the placeholders in this file with real credentials and never commit this file with real values.

Reference:

- Kubernetes Secrets: https://kubernetes.io/docs/concepts/configuration/secret/
- Secret best practices: https://kubernetes.io/docs/concepts/security/secrets-good-practices/

### 15.4 pvc.yaml

A PersistentVolumeClaim asks Kubernetes for a piece of persistent storage. Without this, all data inside the PostgreSQL container is lost when the Pod restarts.

```bash
vim deployment/phase-6-kubernetes-local/k8s/pvc.yaml
```

Paste:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: launchboard-postgres-pvc
  namespace: devops-launchboard
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

Line explanation:

- `apiVersion: v1` uses the core API. PersistentVolumeClaim is a core resource.
- `kind: PersistentVolumeClaim` requests persistent storage from Kubernetes. Kubernetes finds available storage (a PersistentVolume) and binds it to this claim.
- `metadata.name: launchboard-postgres-pvc` names the claim. The PostgreSQL Deployment references this name in its `volumes` section.
- `metadata.namespace: devops-launchboard` places the claim in the app namespace.
- `spec` contains the storage requirements.
- `accessModes` defines how the storage can be mounted. A list because some storage types support multiple access modes.
- `ReadWriteOnce` means the volume can be mounted as read-write by one node at a time. This is the correct mode for a database. If you set `ReadWriteMany`, multiple nodes could write simultaneously and corrupt the database. Kind uses local storage which only supports `ReadWriteOnce`.
- `resources.requests.storage: 5Gi` requests 5 gibibytes of storage. For a student lab, 5Gi is more than enough for PostgreSQL data.

Reference:

- Kubernetes Persistent Volumes: https://kubernetes.io/docs/concepts/storage/persistent-volumes/
- PersistentVolumeClaims: https://kubernetes.io/docs/concepts/storage/persistent-volumes/#persistentvolumeclaims

### 15.5 launchboard-postgres-deployment.yaml

A Deployment manages a set of identical Pods. It ensures the desired number of replicas are running, handles restarts if a Pod crashes, and supports rolling updates.

```bash
vim deployment/phase-6-kubernetes-local/k8s/launchboard-postgres-deployment.yaml
```

Paste:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: launchboard-db
  namespace: devops-launchboard
  labels:
    app: launchboard-db
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: launchboard-db
  template:
    metadata:
      labels:
        app: launchboard-db
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          imagePullPolicy: IfNotPresent
          ports:
            - name: postgres
              containerPort: 5432
          env:
            - name: POSTGRES_DB
              valueFrom:
                configMapKeyRef:
                  name: launchboard-config
                  key: POSTGRES_DB
            - name: POSTGRES_USER
              valueFrom:
                configMapKeyRef:
                  name: launchboard-config
                  key: POSTGRES_USER
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: launchboard-secret
                  key: POSTGRES_PASSWORD
          volumeMounts:
            - name: postgres-data
              mountPath: /var/lib/postgresql/data
          readinessProbe:
            exec:
              command:
                - pg_isready
                - -U
                - launchboard_user
                - -d
                - launchboard
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            exec:
              command:
                - pg_isready
                - -U
                - launchboard_user
                - -d
                - launchboard
            initialDelaySeconds: 20
            periodSeconds: 15
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 1000m
              memory: 1Gi
      volumes:
        - name: postgres-data
          persistentVolumeClaim:
            claimName: launchboard-postgres-pvc
```

Line explanation:

- `apiVersion: apps/v1` uses the `apps` API group where Deployments, StatefulSets, and DaemonSets live.
- `kind: Deployment` creates a Deployment object that manages Pods.
- `metadata.name: launchboard-db` names the Deployment. kubectl commands reference this name.
- `metadata.namespace: devops-launchboard` places the Deployment in the app namespace.
- `metadata.labels.app: launchboard-db` labels the Deployment itself, not the Pods. Used for organizing and filtering.
- `spec.replicas: 1` tells the Deployment to run exactly one PostgreSQL Pod. Running more than one would require a clustered database setup with shared storage, which is beyond this lab.
- `spec.strategy.type: Recreate` means when updating the Deployment, Kubernetes kills the old Pod completely before starting the new one. This is required for PostgreSQL because the PVC uses `ReadWriteOnce` access mode. If two Pods tried to run simultaneously they would both try to mount the same disk, and the second one would fail. `Recreate` prevents that. The tradeoff is brief downtime during updates.
- `spec.selector.matchLabels.app: launchboard-db` tells the Deployment which Pods it manages. The Deployment looks for Pods with the label `app: launchboard-db`. This must match the labels in `template.metadata.labels`.
- `spec.template` is the Pod template. Every Pod created by this Deployment uses this template.
- `spec.template.metadata.labels.app: launchboard-db` labels each Pod. The Deployment selector, Service selector, and NetworkPolicy selectors all use these labels to find the right Pods.
- `spec.template.spec.containers` is the list of containers that run inside each Pod.
- `name: postgres` names the container within the Pod. Used in `kubectl logs`, `kubectl exec`, and events.
- `image: postgres:16-alpine` uses PostgreSQL version 16 on Alpine Linux. Alpine-based images are smaller than Debian-based ones. Version 16 is a stable long-term support release.
- `imagePullPolicy: IfNotPresent` tells Kubernetes to use a locally available image if it exists, and only pull from the registry if the image is not found. This works with `kind load docker-image` for local images.
- `ports[0].name: postgres` gives the port a name. Named ports make manifests more readable and allow Services to reference ports by name instead of number.
- `ports[0].containerPort: 5432` documents that this container listens on port 5432. Like `EXPOSE` in Dockerfile, this is documentation, not a firewall rule.
- `env[0].name: POSTGRES_DB` defines an environment variable named `POSTGRES_DB` inside the container.
- `valueFrom.configMapKeyRef.name: launchboard-config` reads the value from the ConfigMap named `launchboard-config`.
- `valueFrom.configMapKeyRef.key: POSTGRES_DB` reads specifically the `POSTGRES_DB` key from that ConfigMap.
- `env[2].valueFrom.secretKeyRef.name: launchboard-secret` reads from the Secret named `launchboard-secret`.
- `env[2].valueFrom.secretKeyRef.key: POSTGRES_PASSWORD` reads the `POSTGRES_PASSWORD` key from the Secret.
- `volumeMounts[0].name: postgres-data` references the volume named `postgres-data` defined in the `volumes` section below.
- `volumeMounts[0].mountPath: /var/lib/postgresql/data` is where PostgreSQL stores its data files inside the container. Mounting the PVC here means database files persist on the PVC even if the container restarts.
- `readinessProbe` defines how Kubernetes checks if the Pod is ready to receive traffic. A Pod that fails readiness is removed from Service endpoints so no traffic is sent to it.
- `readinessProbe.exec.command` runs `pg_isready -U launchboard_user -d launchboard` inside the container. `pg_isready` is a PostgreSQL utility that checks if the server is accepting connections.
- `initialDelaySeconds: 10` waits 10 seconds after the container starts before running the first probe. PostgreSQL needs time to initialize.
- `periodSeconds: 10` runs the probe every 10 seconds.
- `livenessProbe` defines how Kubernetes checks if the Pod is still alive. A Pod that fails liveness gets restarted.
- `livenessProbe.initialDelaySeconds: 20` waits 20 seconds before the first liveness check. Longer than readiness to give PostgreSQL more startup time before restarting.
- `resources.requests.cpu: 100m` reserves 100 millicores (0.1 CPU cores) for this container. Kubernetes uses requests to decide which node to schedule the Pod on. `m` means millicores. 1000m = 1 full CPU core.
- `resources.requests.memory: 256Mi` reserves 256 mebibytes of RAM.
- `resources.limits.cpu: 1000m` caps the container at 1 full CPU core. If PostgreSQL tries to use more, the kernel throttles it.
- `resources.limits.memory: 1Gi` caps the container at 1 gibibyte of RAM. If PostgreSQL exceeds this, Kubernetes kills the container with an OOMKilled event.
- `volumes[0].name: postgres-data` names a volume that containers in this Pod can mount.
- `volumes[0].persistentVolumeClaim.claimName: launchboard-postgres-pvc` tells Kubernetes to back this volume with the PVC you created in 15.4.

Reference:

- Kubernetes Deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
- Configure liveness and readiness probes: https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/
- Resource management for Pods: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/

### 15.6 launchboard-postgres-service.yaml

A Service gives a set of Pods a stable DNS name and IP address inside the cluster. Pods come and go, but the Service name stays the same. Other Pods use the Service name to find and talk to the database.

```bash
vim deployment/phase-6-kubernetes-local/k8s/launchboard-postgres-service.yaml
```

Paste:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: launchboard-db
  namespace: devops-launchboard
spec:
  type: ClusterIP
  selector:
    app: launchboard-db
  ports:
    - name: postgres
      port: 5432
      targetPort: 5432
```

Line explanation:

- `apiVersion: v1` uses the core API. Services are core resources.
- `kind: Service` creates a Service object.
- `metadata.name: launchboard-db` names the Service. This name becomes a DNS entry inside the cluster. Any Pod in the `devops-launchboard` namespace can connect to the database at `launchboard-db:5432`. The `DATABASE_URL` in the Secret uses this exact name.
- `spec.type: ClusterIP` creates an internal-only Service. Kubernetes assigns a virtual IP address inside the cluster network. Traffic from outside the cluster cannot reach a ClusterIP Service directly. This keeps the database private.
- `spec.selector.app: launchboard-db` tells the Service which Pods to send traffic to. Kubernetes finds all Pods with the label `app: launchboard-db` and adds their IPs to the Service's endpoint list.
- `ports[0].name: postgres` names the port for readability.
- `ports[0].port: 5432` is the port the Service listens on. Other Pods connect to this port.
- `ports[0].targetPort: 5432` is the port on the Pod that the Service forwards traffic to. Here both are 5432 because PostgreSQL listens on 5432 inside the container.

Reference:

- Kubernetes Services: https://kubernetes.io/docs/concepts/services-networking/service/
- Service types: https://kubernetes.io/docs/concepts/services-networking/service/#publishing-services-service-types

### 15.7 launchboard-migration-job.yaml

A Job runs a one-time task to completion. Unlike a Deployment which keeps Pods running forever, a Job runs its Pod, waits for it to complete successfully, and then stops. The migration Job runs Alembic to apply database schema changes before the backend Pods start serving traffic.

```bash
vim deployment/phase-6-kubernetes-local/k8s/launchboard-migration-job.yaml
```

Paste:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: launchboard-migrate
  namespace: devops-launchboard
spec:
  backoffLimit: 3
  template:
    metadata:
      labels:
        app: launchboard-migrate
    spec:
      restartPolicy: OnFailure
      containers:
        - name: migrate
          image: launchboard-backend:phase-6
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
            - |
              until python -c "import socket; s=socket.create_connection(('launchboard-db', 5432), timeout=3); s.close()"; do
                echo "waiting for postgres"
                sleep 2
              done
              alembic upgrade head
          envFrom:
            - configMapRef:
                name: launchboard-config
            - secretRef:
                name: launchboard-secret
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 250m
              memory: 256Mi
```

Line explanation:

- `apiVersion: batch/v1` uses the `batch` API group. Jobs and CronJobs live in the batch group.
- `kind: Job` creates a Job object.
- `metadata.name: launchboard-migrate` names the Job.
- `spec.backoffLimit: 3` sets how many times Kubernetes retries the Job if it fails. If the migration Pod fails 3 times in a row, the Job is marked as failed and stops retrying. This prevents an infinite retry loop if migrations have a permanent error.
- `spec.template` is the Pod template for the Job, just like in a Deployment.
- `spec.template.spec.restartPolicy: OnFailure` tells Kubernetes to restart the Pod container if it exits with a non-zero code (failure). Jobs cannot use `Always` as the restart policy because that would restart even on success. `OnFailure` only restarts on failure, which is what you want for migrations.
- `containers[0].image: launchboard-backend:phase-6` uses the same backend image for migrations because Alembic is installed in that image. There is no need for a separate migration image.
- `containers[0].imagePullPolicy: IfNotPresent` uses the locally loaded Kind image.
- `command` overrides the Dockerfile CMD for this Job. Instead of starting Uvicorn, the Job runs a shell script.
- `/bin/sh -c` runs the following string as a shell script.
- The `until python -c "import socket; ..."` loop tries to open a TCP connection to `launchboard-db` on port 5432 every 2 seconds until it succeeds. This is an init-container pattern implemented in the main container. It prevents Alembic from running before PostgreSQL is ready to accept connections.
- `alembic upgrade head` runs all pending Alembic migrations in the correct order up to the latest version (`head`).
- `envFrom` loads environment variables from multiple sources.
- `configMapRef.name: launchboard-config` loads all keys from the ConfigMap as environment variables.
- `secretRef.name: launchboard-secret` loads all keys from the Secret as environment variables. Alembic reads `DATABASE_URL` from here to know which database to connect to.
- `resources.requests` and `resources.limits` are smaller than the main backend because migrations run briefly and do not need much compute.

Reference:

- Kubernetes Jobs: https://kubernetes.io/docs/concepts/workloads/controllers/job/
- Alembic migrations: https://alembic.sqlalchemy.org/en/latest/

### 15.8 launchboard-backend-deployment.yaml

```bash
vim deployment/phase-6-kubernetes-local/k8s/launchboard-backend-deployment.yaml
```

Paste:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: launchboard-backend
  namespace: devops-launchboard
  labels:
    app: launchboard-backend
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: launchboard-backend
  template:
    metadata:
      labels:
        app: launchboard-backend
    spec:
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: backend
          image: launchboard-backend:phase-6
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
            - |
              until python -c "import socket; s=socket.create_connection(('launchboard-db', 5432), timeout=3); s.close()"; do
                echo "waiting for postgres"
                sleep 2
              done
              exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers
          ports:
            - name: http
              containerPort: 8000
          envFrom:
            - configMapRef:
                name: launchboard-config
            - secretRef:
                name: launchboard-secret
          readinessProbe:
            httpGet:
              path: /ready
              port: 8000
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 20
            periodSeconds: 15
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

Line explanation:

- `spec.replicas: 2` runs two backend Pods simultaneously. Two replicas means if one Pod crashes, the other still handles requests while Kubernetes restarts the failed one.
- `spec.strategy.type: RollingUpdate` updates Pods gradually instead of all at once. When you push a new image, Kubernetes creates a new Pod, waits for it to be ready, then removes an old Pod, repeating until all Pods run the new version.
- `rollingUpdate.maxSurge: 1` allows one extra Pod to exist during the update. With 2 replicas and maxSurge 1, there can be at most 3 Pods during the rollout.
- `rollingUpdate.maxUnavailable: 0` means zero Pods can be unavailable during the update. Kubernetes will not remove an old Pod until the new one is fully ready. This ensures zero downtime during updates.
- `spec.template.spec.securityContext` applies security settings at the Pod level, affecting all containers.
- `runAsNonRoot: true` prevents any container in this Pod from running as root. If an image tries to run as root, Kubernetes rejects it. This is enforced at the Kubernetes level, not just in the Dockerfile.
- `seccompProfile.type: RuntimeDefault` applies the container runtime's default seccomp profile to the Pod. Seccomp filters which system calls a process can make. The default profile blocks dangerous syscalls while allowing everything a normal app needs.
- `command` overrides CMD from the Dockerfile. It waits for PostgreSQL to be available before starting Uvicorn, preventing startup errors.
- `exec uvicorn ...` uses `exec` to replace the shell process with Uvicorn. Without `exec`, Uvicorn runs as a child of the shell. With `exec`, Uvicorn becomes PID 1 in the container and receives signals directly, which means `kubectl rollout` and `kubectl scale` work correctly.
- `readinessProbe.httpGet.path: /ready` makes an HTTP GET request to the backend's `/ready` endpoint. This endpoint typically checks database connectivity. A Pod only receives traffic after this probe succeeds.
- `readinessProbe.httpGet.port: 8000` sends the probe to port 8000 on the container.
- `livenessProbe.httpGet.path: /health` checks the `/health` endpoint. If this returns a non-2xx status or times out, Kubernetes restarts the container.

Reference:

- Kubernetes Deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
- Pod security context: https://kubernetes.io/docs/tasks/configure-pod-container/security-context/
- Rolling updates: https://kubernetes.io/docs/tutorials/kubernetes-basics/update/update-intro/

### 15.9 launchboard-backend-service.yaml

```bash
vim deployment/phase-6-kubernetes-local/k8s/launchboard-backend-service.yaml
```

Paste:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: launchboard-backend
  namespace: devops-launchboard
spec:
  type: ClusterIP
  selector:
    app: launchboard-backend
  ports:
    - name: http
      port: 8000
      targetPort: 8000
```

Line explanation:

- `metadata.name: launchboard-backend` becomes the DNS name. The frontend Nginx config uses `http://launchboard-backend:8000/api/` as the proxy_pass target. Kubernetes DNS resolves `launchboard-backend` to this Service's ClusterIP.
- `spec.type: ClusterIP` keeps the backend internal. The backend is not exposed directly to the internet. All public traffic goes through the frontend Nginx, which proxies API calls to this Service.
- `spec.selector.app: launchboard-backend` routes traffic to Pods with the label `app: launchboard-backend`. If one backend Pod is unhealthy and removed from the Service endpoints, traffic automatically goes only to the healthy replica.
- `ports[0].port: 8000` is the port clients use to connect to the Service.
- `ports[0].targetPort: 8000` is the port on the backend Pod that receives the traffic.

Reference:

- Kubernetes Services: https://kubernetes.io/docs/concepts/services-networking/service/

### 15.10 launchboard-frontend-deployment.yaml

```bash
vim deployment/phase-6-kubernetes-local/k8s/launchboard-frontend-deployment.yaml
```

Paste:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: launchboard-frontend
  namespace: devops-launchboard
  labels:
    app: launchboard-frontend
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: launchboard-frontend
  template:
    metadata:
      labels:
        app: launchboard-frontend
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 101
        runAsGroup: 101
        fsGroup: 101
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: frontend
          image: launchboard-frontend:phase-6
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8080
          readinessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 15
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 250m
              memory: 256Mi
```

Line explanation:

- `spec.replicas: 2` runs two frontend Pods. Same reasoning as the backend: one Pod can handle traffic while the other is being updated or recovered.
- `securityContext.runAsNonRoot: true` prevents root containers.
- `securityContext.runAsUser: 101` sets the UID that the container process runs as. UID 101 is the nginx user inside the `nginxinc/nginx-unprivileged` image. This must match or the Nginx process cannot read its own files.
- `securityContext.runAsGroup: 101` sets the primary GID. Must match the nginx group in the image.
- `securityContext.fsGroup: 101` sets the GID that owns volume mounts. When Kubernetes mounts a volume into the Pod, it sets the group ownership to this GID so the process can read and write the mounted files.
- `containers[0].ports[0].containerPort: 8080` documents that the frontend container listens on 8080, not 80. The unprivileged Nginx image uses 8080 because non-root processes cannot bind to port 80.
- `readinessProbe.httpGet.path: /healthz` probes the `/healthz` endpoint defined in the Nginx config. If Nginx is not serving, this fails and the Pod is removed from Service endpoints.
- `resources.requests.cpu: 50m` and `resources.requests.memory: 64Mi` are low because the frontend serves static files, which is lightweight.
- `resources.limits.cpu: 250m` and `resources.limits.memory: 256Mi` cap the frontend at modest resources.

Reference:

- Kubernetes Deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
- Security context: https://kubernetes.io/docs/tasks/configure-pod-container/security-context/

### 15.11 launchboard-frontend-service.yaml

```bash
vim deployment/phase-6-kubernetes-local/k8s/launchboard-frontend-service.yaml
```

Paste:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: launchboard-frontend
  namespace: devops-launchboard
spec:
  type: ClusterIP
  selector:
    app: launchboard-frontend
  ports:
    - name: http
      port: 80
      targetPort: 8080
```

Line explanation:

- `metadata.name: launchboard-frontend` becomes the DNS name for the frontend inside the cluster.
- `spec.type: ClusterIP` makes the Service internal. The Ingress resource routes external traffic to this Service by name.
- `spec.selector.app: launchboard-frontend` selects Pods with the `app: launchboard-frontend` label.
- `ports[0].port: 80` is the port the Service listens on. The Ingress resource sends traffic to this Service on port 80.
- `ports[0].targetPort: 8080` is the port on the frontend Pod. The Service translates: traffic comes in on port 80, goes out to the Pod on port 8080. This translation lets external consumers use the standard port 80 while the container uses its non-root port 8080.

Reference:

- Kubernetes Services: https://kubernetes.io/docs/concepts/services-networking/service/

### 15.12 ingress.yaml

An Ingress defines rules for routing external HTTP and HTTPS traffic to Services inside the cluster. It requires an Ingress Controller (Nginx Ingress in this scenario) to actually process the rules.

```bash
vim deployment/phase-6-kubernetes-local/k8s/ingress.yaml
```

Paste:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: launchboard-ingress
  namespace: devops-launchboard
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "60"
spec:
  ingressClassName: nginx
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: launchboard-frontend
                port:
                  number: 80
```

Line explanation:

- `apiVersion: networking.k8s.io/v1` uses the networking API group. Ingress is a networking resource.
- `kind: Ingress` creates an Ingress object.
- `metadata.annotations` are key-value pairs that provide extra configuration to the Ingress Controller. Annotations are how you pass controller-specific settings that the Ingress spec itself does not have fields for.
- `nginx.ingress.kubernetes.io/proxy-read-timeout: "60"` sets the timeout for reading a response from the backend to 60 seconds. This prevents the Ingress Controller from closing connections that take longer than the default timeout.
- `nginx.ingress.kubernetes.io/proxy-send-timeout: "60"` sets the timeout for sending a request to the backend to 60 seconds.
- `spec.ingressClassName: nginx` tells Kubernetes which Ingress Controller should handle this Ingress. When you have multiple Ingress Controllers, the class name determines which one picks up the resource. `nginx` refers to the Nginx Ingress Controller you install in Step 17.
- `spec.rules` is the list of routing rules. Each rule matches requests and sends them to a backend Service.
- `rules[0].http` means this rule handles HTTP traffic. You would add a `tls` section for HTTPS.
- `rules[0].http.paths` is the list of path-based routing rules.
- `paths[0].path: /` matches all paths starting with `/`. Since there is no `host` field, this rule matches all hostnames.
- `paths[0].pathType: Prefix` means the path `/` is a prefix match, not an exact match. Requests to `/`, `/api/summary`, `/dashboard`, and anything else all match.
- `backend.service.name: launchboard-frontend` sends matched traffic to the Service named `launchboard-frontend`.
- `backend.service.port.number: 80` sends traffic to port 80 of that Service.

Reference:

- Kubernetes Ingress: https://kubernetes.io/docs/concepts/services-networking/ingress/
- Nginx Ingress Controller annotations: https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/

### 15.13 hpa.yaml

A HorizontalPodAutoscaler watches CPU or memory usage of a Deployment and automatically scales the number of Pods up or down. It requires Metrics Server to be installed.

```bash
vim deployment/phase-6-kubernetes-local/k8s/hpa.yaml
```

Paste:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: launchboard-backend
  namespace: devops-launchboard
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: launchboard-backend
  minReplicas: 2
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

Line explanation:

- `apiVersion: autoscaling/v2` uses the `autoscaling` API group version 2. `v2` supports multiple metric types including CPU, memory, and custom metrics. The older `v1` only supported CPU.
- `kind: HorizontalPodAutoscaler` creates an HPA object.
- `spec.scaleTargetRef` points to the resource the HPA manages.
- `scaleTargetRef.apiVersion: apps/v1` specifies the API group of the target resource.
- `scaleTargetRef.kind: Deployment` says the target is a Deployment.
- `scaleTargetRef.name: launchboard-backend` names the specific Deployment to scale.
- `spec.minReplicas: 2` is the minimum number of Pods the HPA will keep. Even if CPU drops to zero, the HPA never scales below 2.
- `spec.maxReplicas: 5` is the maximum number of Pods the HPA will create. Even if CPU is 100%, the HPA stops at 5 Pods.
- `spec.metrics` defines what to measure when deciding to scale.
- `type: Resource` means you are measuring a standard Kubernetes resource (CPU or memory).
- `resource.name: cpu` measures CPU usage.
- `target.type: Utilization` compares actual usage to the `requests` value defined in the Deployment.
- `target.averageUtilization: 70` means: if the average CPU usage across all backend Pods exceeds 70% of their requested CPU, scale up. If it drops well below 70%, scale down.

This file is created now but not applied in this scenario. You apply it in Scenario 8 after Metrics Server is installed.

Reference:

- Horizontal Pod Autoscaler: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
- HPA walkthrough: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/

### 15.14 kustomization.yaml

Kustomize is built into kubectl. A `kustomization.yaml` file lists multiple Kubernetes manifests so you can apply them all with one command: `kubectl apply -k`. Without Kustomize you would need to run `kubectl apply -f` for every single file.

```bash
vim deployment/phase-6-kubernetes-local/k8s/kustomization.yaml
```

Paste:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - configmap.yaml
  - pvc.yaml
  - launchboard-postgres-deployment.yaml
  - launchboard-postgres-service.yaml
  - launchboard-migration-job.yaml
  - launchboard-backend-deployment.yaml
  - launchboard-backend-service.yaml
  - launchboard-frontend-deployment.yaml
  - launchboard-frontend-service.yaml
  - ingress.yaml
```

Line explanation:

- `apiVersion: kustomize.config.k8s.io/v1beta1` is the Kustomize API version.
- `kind: Kustomization` identifies this as a Kustomize configuration file.
- `resources` is the list of files to include when you run `kubectl apply -k`. Kubernetes applies them in order.
- `secret.example.yaml` is not listed because it contains placeholder credentials. The real Secret is created manually with `kubectl create secret`.
- `hpa.yaml` is not listed because Metrics Server is not installed yet. You add it in Scenario 8.

Reference:

- Kustomize documentation: https://kustomize.io/
- kubectl apply -k: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/

## Step 16: Create Kind Cluster

Run:

```bash
cd /opt/devops-launchboard/app-source/deployment/phase-6-kubernetes-local
kind create cluster --name launchboard-local --config kind-config.yaml
```

Command explanation:

- `kind create cluster` instructs Kind to create a new Kubernetes cluster.
- `--name launchboard-local` gives the cluster a human-readable name. This name appears in kubeconfig and kubectl context references.
- `--config kind-config.yaml` uses the cluster configuration file you created in Step 11, which defines the port mappings and node label.

Verify:

```bash
kubectl get nodes
kubectl get pods -A
```

Expected:

```text
NAME                           STATUS   ROLES           AGE   VERSION
launchboard-local-control-plane   Ready    control-plane   1m    v1.31.x
```

Reference:

- Kind cluster management: https://kind.sigs.k8s.io/docs/user/quick-start/#creating-a-cluster

## Step 17: Install Nginx Ingress Controller

Run:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
```

Wait for the controller to be ready:

```bash
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s
```

Command explanation:

- `kubectl apply -f URL` downloads the manifest from the URL and applies it to the cluster. The Kind-specific Ingress Nginx manifest includes a DaemonSet and a NodeSelector that schedules the controller on nodes with the `ingress-ready=true` label you set in `kind-config.yaml`.
- `kubectl wait` blocks until the specified condition is true or the timeout expires.
- `--namespace ingress-nginx` looks in the `ingress-nginx` namespace where the controller runs.
- `--for=condition=ready pod` waits until the Pod's Ready condition becomes true.
- `--selector=app.kubernetes.io/component=controller` selects only the controller Pod.
- `--timeout=180s` gives the controller up to 3 minutes to start.

Why this step exists:

An Ingress resource is just a set of routing rules written in YAML. Without an Ingress Controller, nobody reads those rules and acts on them. The Nginx Ingress Controller watches for Ingress resources and configures Nginx to implement the routing rules.

Reference:

- Kind Ingress setup: https://kind.sigs.k8s.io/docs/user/ingress/
- Nginx Ingress Controller: https://kubernetes.github.io/ingress-nginx/
- Nginx Ingress deploy docs: https://kubernetes.github.io/ingress-nginx/deploy/

## Step 18: Build And Load Images Into Kind

Run:

```bash
cd /opt/devops-launchboard/app-source
docker build -f deployment/phase-6-kubernetes-local/Dockerfile.backend \
  -t launchboard-backend:phase-6 .
docker build -f deployment/phase-6-kubernetes-local/Dockerfile.frontend \
  --build-arg VITE_API_URL= \
  -t launchboard-frontend:phase-6 .
kind load docker-image launchboard-backend:phase-6 --name launchboard-local
kind load docker-image launchboard-frontend:phase-6 --name launchboard-local
```

Command explanation:

- `docker build -f deployment/.../Dockerfile.backend` specifies which Dockerfile to use for the build.
- `-t launchboard-backend:phase-6` tags the resulting image. The tag format is `name:version`. Kubernetes manifest files reference this exact tag.
- `.` is the build context. Docker sends the entire current directory to the build daemon. The `.dockerignore` file controls what gets sent.
- `--build-arg VITE_API_URL=` passes an empty string as the API URL. When `VITE_API_URL` is empty, Vite assumes API calls use the same origin as the frontend (same host, same port). This means the browser sends `/api/summary` requests to `http://EC2_IP/api/summary`, which Nginx proxies to the backend. You do not need to hardcode the IP in the JavaScript bundle.
- `kind load docker-image launchboard-backend:phase-6 --name launchboard-local` copies the image from the EC2 host's Docker image cache into the Kind cluster's internal image registry. Kind nodes are Docker containers and they have their own isolated image storage. Images on the EC2 host are not automatically available inside Kind containers.

Verify:

```bash
docker images | grep launchboard
```

Reference:

- kind load docker-image: https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster
- Docker build command: https://docs.docker.com/reference/cli/docker/buildx/build/

## Step 19: Create Namespace And Secret

Apply the namespace first so the Secret has a namespace to live in:

```bash
cd /opt/devops-launchboard/app-source
kubectl apply -f deployment/phase-6-kubernetes-local/k8s/namespace.yaml
```

Create the real Secret using kubectl instead of applying a YAML file:

```bash
kubectl create secret generic launchboard-secret \
  --namespace devops-launchboard \
  --from-literal=POSTGRES_PASSWORD='CHANGE_ME_STRONG_PASSWORD' \
  --from-literal=DATABASE_URL='postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@launchboard-db:5432/launchboard'
```

Replace `CHANGE_ME_STRONG_PASSWORD` with a real strong password. Use the same password in both `--from-literal` values.

Command explanation:

- `kubectl create secret generic` creates a generic (Opaque) Secret.
- `launchboard-secret` is the name of the Secret, which must match what the manifests reference.
- `--namespace devops-launchboard` creates the Secret in the app namespace.
- `--from-literal=KEY=VALUE` creates a Secret key-value pair from a literal string on the command line. The value is never written to a file.
- Using `kubectl create secret` instead of `kubectl apply -f secret.yaml` is safer because the credentials never touch the filesystem.

Verify:

```bash
kubectl -n devops-launchboard get secret launchboard-secret
```

Reference:

- kubectl create secret: https://kubernetes.io/docs/tasks/configmap-secret/managing-secret-using-kubectl/

## Step 20: Apply Kubernetes Manifests

Run:

```bash
cd /opt/devops-launchboard/app-source
kubectl apply -k deployment/phase-6-kubernetes-local/k8s
```

Command explanation:

- `kubectl apply -k` reads the `kustomization.yaml` file in the specified directory and applies all listed resources.
- `-k` is the Kustomize flag. It is different from `-f` which applies a single file.
- Kubernetes applies each resource and prints whether it was created or unchanged.

## Step 21: Verify Kubernetes Resources

```bash
kubectl -n devops-launchboard get all
kubectl -n devops-launchboard get ingress
kubectl -n devops-launchboard get pvc
```

Wait for Deployments:

```bash
kubectl -n devops-launchboard rollout status deployment/launchboard-db
kubectl -n devops-launchboard rollout status deployment/launchboard-backend
kubectl -n devops-launchboard rollout status deployment/launchboard-frontend
```

Check migration Job:

```bash
kubectl -n devops-launchboard get job launchboard-migrate
kubectl -n devops-launchboard logs job/launchboard-migrate
```

Expected:

```text
PostgreSQL Pod: Running
Migration Job: Completed
Backend Pods: 2/2 Running
Frontend Pods: 2/2 Running
Ingress: ADDRESS shows 127.0.0.1
PVC: Bound
```

## Step 22: Verify The App

```bash
curl -I http://127.0.0.1
curl -s http://127.0.0.1/health | jq
curl -s http://127.0.0.1/ready | jq
curl -s http://127.0.0.1/api/summary | jq
```

Open in browser:

```text
http://YOUR_EC2_PUBLIC_IP
```

Expected:

```text
Frontend loads.
Dashboard data appears.
API works through /api.
No CORS errors in the browser console.
```

## Step 23: Test Rollout And Rollback

Build and load a new backend image:

```bash
cd /opt/devops-launchboard/app-source
docker build -f deployment/phase-6-kubernetes-local/Dockerfile.backend \
  -t launchboard-backend:phase-6-v2 .
kind load docker-image launchboard-backend:phase-6-v2 --name launchboard-local
```

Update backend image:

```bash
kubectl -n devops-launchboard set image deployment/launchboard-backend \
  backend=launchboard-backend:phase-6-v2
kubectl -n devops-launchboard rollout status deployment/launchboard-backend
```

Check rollout history:

```bash
kubectl -n devops-launchboard rollout history deployment/launchboard-backend
```

Rollback:

```bash
kubectl -n devops-launchboard rollout undo deployment/launchboard-backend
kubectl -n devops-launchboard rollout status deployment/launchboard-backend
```

Command explanation:

- `kubectl set image deployment/NAME CONTAINER=IMAGE` changes the image of a specific container in the Deployment. Kubernetes starts a rolling update immediately.
- `rollout status` watches the update and returns when all Pods are running the new image.
- `rollout history` lists all previous revisions of the Deployment. Each `kubectl apply` or `set image` creates a new revision.
- `rollout undo` reverts to the previous revision. You can also specify a revision number with `--to-revision=N`.

Reference:

- Rolling updates: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-update-deployment
- Rollback: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment

## Troubleshooting

### Pod Shows ImagePullBackOff

```bash
kubectl -n devops-launchboard describe pod POD_NAME
```

Fix:

```bash
kind load docker-image launchboard-backend:phase-6 --name launchboard-local
kind load docker-image launchboard-frontend:phase-6 --name launchboard-local
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
kubectl -n devops-launchboard rollout restart deployment/launchboard-frontend
```

### Backend Cannot Connect To Database

```bash
kubectl -n devops-launchboard logs deployment/launchboard-backend
kubectl -n devops-launchboard get secret launchboard-secret
kubectl -n devops-launchboard get pods -l app=launchboard-db
```

Common causes: Secret not created, `DATABASE_URL` password does not match `POSTGRES_PASSWORD`, PostgreSQL Pod not yet ready.

### Migration Job Failed

```bash
kubectl -n devops-launchboard describe job launchboard-migrate
kubectl -n devops-launchboard logs job/launchboard-migrate
```

Fix after correcting the issue:

```bash
kubectl -n devops-launchboard delete job launchboard-migrate
kubectl apply -f deployment/phase-6-kubernetes-local/k8s/launchboard-migration-job.yaml
```

### Ingress Does Not Work

```bash
kubectl get pods -n ingress-nginx
kubectl -n devops-launchboard get ingress
curl -v http://127.0.0.1
```

Common causes: Ingress Controller not ready, Kind cluster created without port mappings, AWS security group blocking port 80.

## Cleanup For Scenario 1

```bash
kubectl delete namespace devops-launchboard
kind delete cluster --name launchboard-local
docker rmi launchboard-backend:phase-6 launchboard-backend:phase-6-v2 launchboard-frontend:phase-6 || true
docker system prune -f
```

Terminate the EC2 instance from the AWS Console when you are done.

---

# Scenario 2: Self-Managed Kubernetes with kubeadm (Single Control Plane)

## Files And Folders For This Scenario

In this scenario you do not create Kubernetes manifests yet. You are setting up the cluster itself. The files and configuration changes happen on the EC2 server directly.

```text
EC2: devops-launchboard-k8s-control
+-- /etc/modules-load.d/k8s.conf          (kernel modules to load on boot)
+-- /etc/sysctl.d/k8s.conf               (kernel networking parameters)
+-- /etc/containerd/config.toml          (containerd runtime configuration)
+-- /etc/apt/keyrings/kubernetes-apt-keyring.gpg  (Kubernetes apt signing key)
+-- /etc/apt/sources.list.d/kubernetes.list       (Kubernetes apt repository)
+-- $HOME/.kube/config                   (kubectl authentication config, auto-created by kubeadm)
```

What each file does:

| File | What It Does | Why You Need It |
| --- | --- | --- |
| `k8s.conf` (modules) | Tells the kernel to load `overlay` and `br_netfilter` on every boot | Kubernetes networking and container layered filesystems require these kernel modules |
| `k8s.conf` (sysctl) | Sets `ip_forward` and `bridge-nf-call-iptables` kernel parameters | Allows Pods on different nodes to communicate and lets iptables see bridged traffic |
| `config.toml` | Configures containerd to use the systemd cgroup driver | kubelet and containerd must use the same cgroup driver or kubelet refuses to start |
| `kubernetes-apt-keyring.gpg` | GPG key for verifying Kubernetes apt packages | Prevents installing tampered packages |
| `kubernetes.list` | Points apt to the official Kubernetes package repository | Required to install kubeadm, kubelet, kubectl |
| `$HOME/.kube/config` | kubeconfig file with cluster address and credentials | kubectl reads this to know which cluster to talk to and how to authenticate |

## What This Scenario Covers

In Scenario 1 you used Kind, which runs Kubernetes inside Docker containers on one machine. That is great for learning but it is not how real clusters work.

In a real environment, each Kubernetes node is a separate server. The control plane node runs the Kubernetes brain: the API server, scheduler, etcd database, and controller manager. Worker nodes run your application Pods.

kubeadm is the official tool for setting up a real Kubernetes cluster on bare Linux servers. In this scenario you will create a single-node cluster where the control plane node also runs Pods temporarily. In Scenario 3 you add 2 dedicated worker nodes.

## AWS Cost Warning

kubeadm requires t3.medium (2 vCPU, 4GB RAM) as the minimum. t3.small does not have enough memory. t3.medium costs approximately $0.04 per hour and is not AWS free tier. Stop or terminate this instance when you are not actively using it.

## Recommended AWS Setup For Control Plane

| Item | Value |
| --- | --- |
| EC2 Name | `devops-launchboard-k8s-control` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.medium` |
| Storage | 20 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | `devops-launchboard-k8s-sg` |

Security group inbound rules:

| Type | Port | Source | Why |
| --- | ---: | --- | --- |
| SSH | 22 | Your IP | Terminal access |
| Custom TCP | 6443 | Your IP | Kubernetes API server |
| Custom TCP | 2379-2380 | Control plane private IP | etcd peer communication |
| Custom TCP | 10250 | Control plane private IP | kubelet API |
| Custom TCP | 10259 | Control plane private IP | kube-scheduler |
| Custom TCP | 10257 | Control plane private IP | kube-controller-manager |

You will add worker node IPs to this security group in Scenario 3 after creating worker EC2 instances.

## Step 1: Create EC2 For Control Plane

Create one EC2 instance with the values from the table above. Enable public IP. After creating, note both the public IP and private IP. The private IP is on the EC2 details page under Private IPv4 addresses. It usually starts with `172.31.`.

```text
Control plane public IP:  YOUR_CONTROL_PLANE_PUBLIC_IP
Control plane private IP: YOUR_CONTROL_PLANE_PRIVATE_IP
```

Why you need both IPs:

kubectl and worker nodes connect to the API server. Worker nodes connect via the private IP because they are in the same VPC. You connect via the public IP from your laptop. The kubeadm init command uses the private IP so the API server advertises the right address to worker nodes.

Reference:

- AWS EC2 launch guide: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EC2_GetStarted.html

## Step 2: SSH Into Control Plane

```bash
ssh -i devops-launchboard-key.pem ubuntu@YOUR_CONTROL_PLANE_PUBLIC_IP
```

## Step 3: Update Server And Install Base Tools

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl wget vim unzip jq ca-certificates gnupg lsb-release apt-transport-https
```

Command explanation:

- All packages are the same as Scenario 1 except `apt-transport-https`, which allows apt to download packages over HTTPS. This is needed for the Kubernetes apt repository.

Reference:

- Ubuntu package management: https://ubuntu.com/server/docs/package-management

## Step 4: Disable Swap

Kubernetes requires swap to be completely disabled.

Check if swap is on:

```bash
free -h
```

If the Swap line shows any value other than 0B, disable it:

```bash
sudo swapoff -a
```

Make the change permanent across reboots:

```bash
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

Verify swap is off:

```bash
free -h
```

Expected: Swap row shows `0B 0B 0B`.

Command explanation:

- `swapoff -a` disables all swap partitions and swap files immediately.
- `sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab` edits the `/etc/fstab` file in place. It finds any line containing the word `swap` and comments it out by adding a `#` at the beginning. `/etc/fstab` is the file Linux reads at boot to know what to mount. Commenting the swap line prevents swap from being re-enabled after a reboot.

Why swap must be off:

Kubernetes needs predictable memory behavior. Swap allows the Linux kernel to move RAM contents to disk when memory is full. This introduces unpredictable latency and breaks the memory management assumptions Kubernetes makes. If a Pod needs more memory than the node has, Kubernetes expects the Pod to be killed (OOMKilled) so it can be rescheduled elsewhere. With swap enabled, the kernel might keep the Pod alive by using slow disk storage instead. kubelet detects swap and refuses to start when it is on.

Reference:

- kubeadm prerequisites: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#before-you-begin

## Step 5: Load Required Kernel Modules

Kubernetes networking needs two kernel modules loaded.

```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

Command explanation:

- `cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf` is a here-document that writes multiple lines to a file. Everything between `<<EOF` and `EOF` is the file content. `tee` writes to the file while also printing to stdout.
- `/etc/modules-load.d/k8s.conf` is a systemd configuration file. systemd reads all files in this directory on boot and loads the listed kernel modules automatically.
- `overlay` is the kernel module that enables OverlayFS, the layered filesystem used by containerd to layer Docker images on top of each other efficiently.
- `br_netfilter` is the kernel module that enables iptables to process packets crossing Linux bridges. Kubernetes creates virtual network bridges for Pod networking. Without this module, Kubernetes network rules do not apply to Pod traffic.
- `sudo modprobe overlay` loads the `overlay` module immediately without waiting for a reboot.
- `sudo modprobe br_netfilter` loads the `br_netfilter` module immediately.

Verify both modules are loaded:

```bash
lsmod | grep overlay
lsmod | grep br_netfilter
```

Both commands should produce output. Empty output means the module is not loaded.

Reference:

- kubeadm networking prerequisites: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#letting-iptables-see-bridged-traffic

## Step 6: Set Kernel Networking Parameters

```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

Command explanation:

- `/etc/sysctl.d/k8s.conf` is a kernel parameter configuration file. sysctl parameters control kernel behavior at runtime. Files in `/etc/sysctl.d/` are loaded automatically on boot.
- `net.bridge.bridge-nf-call-iptables = 1` tells the kernel to pass bridged IPv4 traffic through iptables. Kubernetes uses iptables to implement Service routing and NetworkPolicy rules. Without this, traffic between Pods on the same node bypasses iptables rules and Services do not work.
- `net.bridge.bridge-nf-call-ip6tables = 1` does the same for IPv6 traffic.
- `net.ipv4.ip_forward = 1` enables IP forwarding. IP forwarding allows the Linux kernel to forward packets from one network interface to another. Without this, a node cannot route traffic between its network interface (connected to the VPC) and the virtual network interfaces used by Pods.
- `sudo sysctl --system` applies all sysctl configuration files from all the standard directories immediately without rebooting.

Verify:

```bash
sysctl net.bridge.bridge-nf-call-iptables net.ipv4.ip_forward
```

Expected:

```text
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
```

Reference:

- Linux sysctl: https://www.kernel.org/doc/html/latest/admin-guide/sysctl/net.html
- kubeadm sysctl setup: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#letting-iptables-see-bridged-traffic

## Step 7: Install containerd

containerd is the container runtime that Kubernetes uses to run containers. Unlike Scenario 1 where Docker is needed for Kind, here you install containerd directly because Kubernetes talks to containerd through the CRI (Container Runtime Interface), not Docker.

```bash
sudo apt install -y containerd
```

Create the default containerd configuration:

```bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
```

Enable the systemd cgroup driver:

```bash
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
```

Verify the change:

```bash
grep SystemdCgroup /etc/containerd/config.toml
```

Expected:

```text
SystemdCgroup = true
```

Restart and enable containerd:

```bash
sudo systemctl restart containerd
sudo systemctl enable containerd
sudo systemctl status containerd
```

Expected: `Active: active (running)`.

Command explanation:

- `containerd config default` prints the full default configuration for containerd to stdout.
- `sudo tee /etc/containerd/config.toml` writes that output to the config file. Without a config file, containerd uses built-in defaults which may not have the correct cgroup driver.
- `sed -i 's/SystemdCgroup = false/SystemdCgroup = true/'` edits the config file in place, changing the cgroup driver from `cgroupfs` to `systemd`.
- `SystemdCgroup = true` is the critical setting. It tells containerd to use systemd as the cgroup driver. kubelet also uses the systemd cgroup driver by default on modern systems. If they use different drivers, kubelet cannot manage container resources correctly and refuses to start.
- `systemctl enable containerd` creates a systemd service link so containerd starts automatically when the server boots.
- `systemctl restart containerd` applies the new configuration immediately.

Why containerd and not Docker:

Kubernetes communicates with the container runtime through the CRI (Container Runtime Interface), a standard API. containerd implements CRI directly. Docker Engine also uses containerd internally but adds extra layers that Kubernetes does not use. Installing containerd directly is lighter, simpler, and is the standard approach for Kubernetes nodes.

Reference:

- containerd getting started: https://containerd.io/docs/getting-started/
- CRI overview: https://kubernetes.io/docs/concepts/architecture/cri/
- containerd for Kubernetes: https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd

## Step 8: Install kubeadm, kubelet, kubectl

These three tools are required on every Kubernetes node.

What each one does:

- `kubelet` is the agent that runs on every node. It watches for Pod assignments from the API server and starts, stops, and monitors containers accordingly.
- `kubeadm` is the cluster initialization tool. You use it once to set up the cluster and again on worker nodes to join them. After the cluster is running, you rarely use kubeadm day-to-day.
- `kubectl` is the command-line client. You use it to manage every Kubernetes resource from the terminal.

Add the Kubernetes apt repository:

```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list
```

Install:

```bash
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

Enable kubelet:

```bash
sudo systemctl enable kubelet
```

Command explanation:

- `curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key` downloads the Kubernetes package signing key from the official Kubernetes apt repository for version 1.31.
- `sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg` converts the key from ASCII armor format to binary GPG format that apt can use to verify package signatures.
- `echo 'deb [signed-by=...] ...'` constructs the apt source line that points to the Kubernetes 1.31 stable package repository.
- `sudo tee /etc/apt/sources.list.d/kubernetes.list` writes the source line to a file. apt reads all files in `/etc/apt/sources.list.d/` when you run `apt update`.
- `sudo apt update` refreshes package metadata now that the Kubernetes repository is added.
- `sudo apt install -y kubelet kubeadm kubectl` installs all three tools.
- `sudo apt-mark hold kubelet kubeadm kubectl` prevents apt from automatically upgrading these packages. Kubernetes version upgrades must be done deliberately and carefully following the official upgrade procedure. An unexpected automatic upgrade can break the cluster.
- `sudo systemctl enable kubelet` enables the kubelet service so it starts on boot. kubelet does not start successfully until the cluster is initialized, but enabling it now means it will start correctly after `kubeadm init`.

Verify:

```bash
kubeadm version
kubectl version --client
kubelet --version
```

Reference:

- kubeadm install guide: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
- kubelet reference: https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/
- kubectl install: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/

## Step 9: Initialize The Kubernetes Cluster

This is the most important step in this scenario. `kubeadm init` creates the entire Kubernetes control plane from scratch.

```bash
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=YOUR_CONTROL_PLANE_PRIVATE_IP
```

Replace `YOUR_CONTROL_PLANE_PRIVATE_IP` with the actual private IP of this EC2 instance.

This command takes 2 to 4 minutes. At the end you will see output similar to:

```text
Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Then you can join any number of worker nodes by running the following on each:

kubeadm join 172.31.X.X:6443 --token XXXX.XXXXXXXXXXXXXXXXXX \
    --discovery-token-ca-cert-hash sha256:XXXXXXXX...
```

Copy the `kubeadm join` command from your output and save it. You will use it in Scenario 3.

Command explanation:

- `sudo kubeadm init` runs the cluster initialization as root. It creates all control plane components: etcd, kube-apiserver, kube-controller-manager, and kube-scheduler as static Pods managed by kubelet.
- `--pod-network-cidr=10.244.0.0/16` sets the IP address range assigned to Pods. This exact CIDR (`10.244.0.0/16`) is required by Flannel, the CNI networking plugin you install next. Flannel expects this range. If you change it, Flannel will not work correctly.
- `--apiserver-advertise-address=YOUR_CONTROL_PLANE_PRIVATE_IP` tells the API server which IP address to advertise to worker nodes and kubectl clients. Using the private IP is correct because worker nodes in the same VPC communicate over private IPs. The public IP is not stable (it changes when the EC2 instance stops and starts).

Reference:

- kubeadm init reference: https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/
- kubeadm cluster creation: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/

## Step 10: Configure kubectl Access

Run these as the ubuntu user (not root):

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Command explanation:

- `mkdir -p $HOME/.kube` creates the kubectl configuration directory. `$HOME` is `/home/ubuntu` for the ubuntu user.
- `sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config` copies the kubeconfig file that kubeadm created. `/etc/kubernetes/admin.conf` contains the API server address, the cluster's CA certificate, and an admin client certificate that grants full cluster access. `-i` prompts before overwriting an existing file.
- `sudo chown $(id -u):$(id -g) $HOME/.kube/config` changes ownership of the copied file to the current user. `$(id -u)` outputs your UID and `$(id -g)` outputs your GID. kubectl requires the kubeconfig file to be owned by the user running it.

Verify:

```bash
kubectl get nodes
```

Expected:

```text
NAME       STATUS     ROLES           AGE   VERSION
ip-...     NotReady   control-plane   1m    v1.31.x
```

The `NotReady` status is expected at this point. The node is not ready because there is no Pod networking plugin installed yet. You fix that in the next step.

Reference:

- kubectl kubeconfig: https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/

## Step 11: Generate A Long-Lived Join Token

The default join token from `kubeadm init` expires in 24 hours. Since you are working at your own pace, generate a token that never expires before you continue.

```bash
kubeadm token create --ttl 0 --print-join-command
```

Command explanation:

- `kubeadm token create` creates a new bootstrap token. Bootstrap tokens are used by worker nodes to authenticate with the API server during the join process.
- `--ttl 0` sets the token time-to-live to zero, which means it never expires. A TTL of `24h` would be the default. Setting it to `0` is appropriate for a student lab where you may work across multiple days.
- `--print-join-command` prints the complete `kubeadm join` command with the token and discovery hash already included, so you can copy and paste it directly onto worker nodes.

Save the full output. It looks like:

```text
kubeadm join 172.31.X.X:6443 --token XXXX.XXXXXXXXXXXXXXXXXX \
  --discovery-token-ca-cert-hash sha256:XXXX...
```

Reference:

- kubeadm token: https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-token/

## Step 12: Install Flannel Pod Network

Pods on different nodes need a way to communicate with each other. Kubernetes does not include networking itself. You install a CNI (Container Network Interface) plugin to provide it. Flannel is a simple, widely used CNI plugin that works well with kubeadm.

```bash
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

Wait for Flannel Pods to start:

```bash
kubectl wait --namespace kube-flannel \
  --for=condition=ready pod \
  --selector=app=flannel \
  --timeout=120s
```

Verify the node is now Ready:

```bash
kubectl get nodes
```

Expected:

```text
NAME       STATUS   ROLES           AGE   VERSION
ip-...     Ready    control-plane   5m    v1.31.x
```

Command explanation:

- `kubectl apply -f URL` downloads the Flannel DaemonSet manifest and applies it. Flannel runs as a DaemonSet, meaning one Flannel Pod runs on every node automatically.
- Flannel creates a virtual overlay network. Each node gets a subnet from the `10.244.0.0/16` range. When a Pod on node A sends a packet to a Pod on node B, Flannel wraps the packet in a VXLAN tunnel and forwards it through the underlying network. This is why the `--pod-network-cidr=10.244.0.0/16` value in the kubeadm init command must match what Flannel expects.

Reference:

- Flannel: https://github.com/flannel-io/flannel
- Kubernetes CNI: https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/
- kubeadm CNI setup: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#pod-network

## Step 13: Verify Control Plane Components

```bash
kubectl get pods -n kube-system
```

Expected Pods in `kube-system`:

```text
coredns-...                    Running
etcd-...                       Running
kube-apiserver-...             Running
kube-controller-manager-...    Running
kube-proxy-...                 Running
kube-scheduler-...             Running
```

What each component does:

- `etcd` is the distributed key-value database where Kubernetes stores all cluster state: every resource definition, every Pod status, every Secret. If etcd is lost, the cluster state is lost.
- `kube-apiserver` is the front door to the cluster. Every kubectl command, every controller, and every kubelet talks to the API server. It validates and persists changes to etcd.
- `kube-controller-manager` runs a collection of controllers that watch the cluster state and work to make the actual state match the desired state. For example the Deployment controller notices when a Pod is missing and creates a new one.
- `kube-scheduler` watches for new Pods with no assigned node and picks the best node to run them based on available resources, node selectors, affinity rules, and taints.
- `coredns` provides DNS resolution inside the cluster. When a Pod does a DNS lookup for `launchboard-backend`, CoreDNS resolves it to the ClusterIP of the Service.
- `kube-proxy` runs on every node and maintains iptables rules that implement Service load balancing and routing.

Reference:

- Kubernetes components: https://kubernetes.io/docs/concepts/overview/components/

## Step 14: Allow Scheduling On Control Plane

By default, Kubernetes marks the control plane node with a taint that prevents application Pods from scheduling there. In a production cluster this is correct because the control plane should only run Kubernetes components. In this single-node scenario you have no worker nodes yet, so you must remove the taint to allow application Pods to schedule.

Check existing taints:

```bash
kubectl describe node | grep Taint
```

Remove the control-plane taint:

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

The trailing `-` at the end of the taint name is the syntax for removing a taint.

Expected:

```text
node/ip-... untainted
```

Verify:

```bash
kubectl describe node | grep Taint
```

Expected:

```text
Taints: <none>
```

Important: You will re-apply this taint in Scenario 3 after adding worker nodes.

Reference:

- Kubernetes taints and tolerations: https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/

## Step 15: Verify The Cluster Is Ready

```bash
kubectl get nodes
kubectl get pods -A
```

Expected:

```text
All system Pods: Running or Completed
Node status: Ready
```

Your single-node kubeadm cluster is running. Move to Scenario 3 to add worker nodes.

---

# Scenario 3: Multi-Node Kubernetes Cluster (1 Control Plane + 2 Workers)

## Files And Folders For This Scenario

Like Scenario 2, this scenario involves configuring EC2 servers. No new project files are created. The changes happen on two new EC2 instances (the worker nodes).

```text
EC2: devops-launchboard-k8s-worker-1
EC2: devops-launchboard-k8s-worker-2
Each worker gets the same files as the control plane in Scenario 2:
+-- /etc/modules-load.d/k8s.conf
+-- /etc/sysctl.d/k8s.conf
+-- /etc/containerd/config.toml
+-- /etc/apt/keyrings/kubernetes-apt-keyring.gpg
+-- /etc/apt/sources.list.d/kubernetes.list
```

Workers do not get a `.kube/config` file because you do not run kubectl from worker nodes. kubectl runs only from the control plane.

## What This Scenario Covers

Right now the control plane node runs both Kubernetes components and application Pods. In a real production cluster those jobs are separated. Control plane nodes manage the cluster. Worker nodes run your applications.

In this scenario you create 2 worker EC2 instances, prepare them, and join them to the existing control plane from Scenario 2. After this scenario you will have a proper 3-node cluster.

## AWS Setup For Worker Nodes

Create 2 EC2 instances with these settings:

| Item | Value |
| --- | --- |
| EC2 Names | `devops-launchboard-k8s-worker-1` and `devops-launchboard-k8s-worker-2` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.medium` |
| Storage | 20 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | `devops-launchboard-k8s-worker-sg` (create new) |

Security group inbound rules for worker nodes:

| Type | Port | Source | Why |
| --- | ---: | --- | --- |
| SSH | 22 | Your IP | Terminal access |
| Custom TCP | 10250 | Control plane private IP | kubelet API called by control plane |
| Custom TCP | 30000-32767 | Anywhere | NodePort Services |

After creating both workers, note their private IPs:

```text
Worker 1 private IP: YOUR_WORKER_1_PRIVATE_IP
Worker 2 private IP: YOUR_WORKER_2_PRIVATE_IP
```

## Update Control Plane Security Group

Go to the `devops-launchboard-k8s-sg` security group (for the control plane) and add these inbound rules so worker nodes can reach the API server:

| Type | Port | Source |
| --- | ---: | --- |
| Custom TCP | 6443 | Worker 1 private IP/32 |
| Custom TCP | 6443 | Worker 2 private IP/32 |
| Custom TCP | 10250 | Worker 1 private IP/32 |
| Custom TCP | 10250 | Worker 2 private IP/32 |

The `/32` suffix means that specific IP only, not a range.

## Steps Below Run On BOTH Worker Nodes

SSH into worker 1 and run Steps 1 through 7. Then SSH into worker 2 and repeat the same steps.

```bash
ssh -i devops-launchboard-key.pem ubuntu@YOUR_WORKER_1_PUBLIC_IP
```

### Step 1: Update Server

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl wget vim unzip jq ca-certificates gnupg lsb-release apt-transport-https
```

Reference:

- Ubuntu package management: https://ubuntu.com/server/docs/package-management

### Step 2: Disable Swap

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

Verify:

```bash
free -h
```

Expected: Swap row shows `0B 0B 0B`.

Reference:

- kubeadm prerequisites: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#before-you-begin

### Step 3: Load Kernel Modules

```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

Verify:

```bash
lsmod | grep overlay
lsmod | grep br_netfilter
```

Reference:

- Kernel modules for Kubernetes: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#letting-iptables-see-bridged-traffic

### Step 4: Set Kernel Networking Parameters

```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

Verify:

```bash
sysctl net.bridge.bridge-nf-call-iptables net.ipv4.ip_forward
```

Reference:

- sysctl for Kubernetes: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#letting-iptables-see-bridged-traffic

### Step 5: Install containerd

```bash
sudo apt install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd
```

Verify:

```bash
grep SystemdCgroup /etc/containerd/config.toml
sudo systemctl status containerd
```

Expected: `SystemdCgroup = true` and status `active (running)`.

Reference:

- containerd for Kubernetes: https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd

### Step 6: Install kubeadm, kubelet, kubectl

```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet
```

Verify:

```bash
kubeadm version
kubelet --version
```

Reference:

- kubeadm install: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/

### Step 7: Join The Cluster

Use the join command you saved from Scenario 2 Step 11. Run it with `sudo`:

```bash
sudo kubeadm join 172.31.X.X:6443 \
  --token XXXX.XXXXXXXXXXXXXXXXXX \
  --discovery-token-ca-cert-hash sha256:XXXX...
```

Command explanation:

- `kubeadm join` registers this node with the Kubernetes cluster.
- `172.31.X.X:6443` is the control plane private IP and API server port.
- `--token` is the bootstrap token. The worker node uses this to prove it is allowed to join.
- `--discovery-token-ca-cert-hash` is a hash of the cluster's CA certificate. The worker uses this to verify it is connecting to the correct cluster and not a man-in-the-middle. This prevents a rogue API server from tricking a worker into joining the wrong cluster.

If you lost the join command, SSH to the control plane and regenerate it:

```bash
kubeadm token create --ttl 0 --print-join-command
```

After joining you will see:

```text
This node has joined the cluster:
* Certificate signing request was sent to apiserver and a response was received.
* The kubelet was notified of the new secure configuration.
```

Repeat Steps 1 through 7 on worker 2.

Reference:

- kubeadm join: https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-join/

## Verify From The Control Plane

SSH into the control plane:

```bash
ssh -i devops-launchboard-key.pem ubuntu@YOUR_CONTROL_PLANE_PUBLIC_IP
```

Check nodes:

```bash
kubectl get nodes
```

Wait 1 to 2 minutes for workers to show Ready:

```text
NAME                    STATUS   ROLES           AGE   VERSION
ip-172-31-X-X (control) Ready    control-plane   20m   v1.31.x
ip-172-31-X-X (worker1) Ready    <none>          2m    v1.31.x
ip-172-31-X-X (worker2) Ready    <none>          1m    v1.31.x
```

Check full node details:

```bash
kubectl get nodes -o wide
```

This shows the private IP, OS image, and container runtime of each node.

## Re-Apply Control Plane Taint

In Scenario 2 you removed the control plane taint so Pods could run on the single node. Now that worker nodes exist, re-apply the taint so the control plane is dedicated to Kubernetes components only.

```bash
kubectl taint nodes \
  $(kubectl get nodes --selector=node-role.kubernetes.io/control-plane \
    -o jsonpath='{.items[0].metadata.name}') \
  node-role.kubernetes.io/control-plane:NoSchedule
```

Command explanation:

- `kubectl get nodes --selector=node-role.kubernetes.io/control-plane` selects only the control plane node.
- `-o jsonpath='{.items[0].metadata.name}'` extracts just the node name from the output.
- `$( )` runs that inner command and inserts the result into the outer command.
- `node-role.kubernetes.io/control-plane:NoSchedule` is the taint to apply. `NoSchedule` means Pods without a matching toleration will not be scheduled on this node.

Verify:

```bash
kubectl describe node \
  $(kubectl get nodes --selector=node-role.kubernetes.io/control-plane \
    -o jsonpath='{.items[0].metadata.name}') | grep Taint
```

Expected:

```text
Taints: node-role.kubernetes.io/control-plane:NoSchedule
```

## Label Worker Nodes

Labels help organize and identify nodes. Adding a `worker` role label makes node output more readable.

```bash
kubectl label node \
  $(kubectl get nodes --selector='!node-role.kubernetes.io/control-plane' \
    -o jsonpath='{.items[0].metadata.name}') \
  node-role.kubernetes.io/worker=worker

kubectl label node \
  $(kubectl get nodes --selector='!node-role.kubernetes.io/control-plane' \
    -o jsonpath='{.items[1].metadata.name}') \
  node-role.kubernetes.io/worker=worker
```

Verify:

```bash
kubectl get nodes
```

Expected:

```text
NAME          STATUS   ROLES           AGE   VERSION
ip-...        Ready    control-plane   25m   v1.31.x
ip-...        Ready    worker          5m    v1.31.x
ip-...        Ready    worker          4m    v1.31.x
```

Reference:

- Node labels: https://kubernetes.io/docs/tasks/configure-pod-container/assign-pods-nodes/
- Taints and tolerations: https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/

Your 3-node cluster is ready. Move to Scenario 4 to deploy the LaunchBoard application.

---

# Scenario 4: Deploy LaunchBoard on Self-Managed Kubernetes

## Files And Folders For This Scenario

```text
/opt/devops-launchboard/app-source/
+-- deployment/
    +-- phase-6-kubeadm/
        +-- k8s/
            +-- namespace.yaml                             (Kubernetes namespace)
            +-- configmap.yaml                             (non-secret app configuration)
            +-- secret.example.yaml                        (example secret, never commit real values)
            +-- pvc.yaml                                   (persistent storage for PostgreSQL)
            +-- launchboard-postgres-deployment.yaml       (PostgreSQL database Pod)
            +-- launchboard-postgres-service.yaml          (database internal DNS)
            +-- launchboard-migration-job.yaml             (Alembic migration runner)
            +-- launchboard-backend-deployment.yaml        (FastAPI backend Pods)
            +-- launchboard-backend-service.yaml           (backend internal DNS)
            +-- launchboard-frontend-deployment.yaml       (React frontend Pods)
            +-- launchboard-frontend-service.yaml          (frontend internal DNS)
            +-- frontend-nodeport-service.yaml             (temporary public access, removed in Scenario 5)
            +-- kustomization.yaml                         (groups manifests for one-command apply)
```

What each file does and why it exists:

| File | What It Does | Why You Need It |
| --- | --- | --- |
| `namespace.yaml` | Creates the `devops-launchboard` namespace | Isolates app resources |
| `configmap.yaml` | Stores non-secret config values | Configures app without hardcoding values in images |
| `secret.example.yaml` | Example Secret structure | Reference only, real secret is created with kubectl |
| `pvc.yaml` | Requests persistent disk for PostgreSQL | Data survives Pod restarts |
| `launchboard-postgres-deployment.yaml` | Runs PostgreSQL | Database for the app |
| `launchboard-postgres-service.yaml` | Creates `launchboard-db` DNS name | Backend finds the database by name |
| `launchboard-migration-job.yaml` | Runs Alembic migrations | Creates database tables before backend starts |
| `launchboard-backend-deployment.yaml` | Runs 2 FastAPI backend Pods | API layer |
| `launchboard-backend-service.yaml` | Creates `launchboard-backend` DNS name | Frontend proxies API calls by name |
| `launchboard-frontend-deployment.yaml` | Runs 2 React frontend Pods | Browser UI |
| `launchboard-frontend-service.yaml` | Creates `launchboard-frontend` DNS name | Ingress routes to this |
| `frontend-nodeport-service.yaml` | Exposes frontend on port 30080 on every node | Temporary access before MetalLB is installed in Scenario 5 |
| `kustomization.yaml` | Groups all manifests | One command to deploy everything |

## What This Scenario Covers

You now have a real 3-node Kubernetes cluster. In this scenario you deploy the LaunchBoard N-tier application onto it.

The manifests are very similar to Scenario 1. The key differences are:

- Images are pulled from Docker Hub, not from a local Kind image cache.
- There is no Kind port mapping, so a NodePort Service provides temporary public access.
- Pods spread automatically across the 2 worker nodes.

## Step 1: Prepare The Working Folder On Control Plane

SSH into the control plane:

```bash
ssh -i devops-launchboard-key.pem ubuntu@YOUR_CONTROL_PLANE_PUBLIC_IP
```

Set up the project:

```bash
sudo mkdir -p /opt/devops-launchboard
sudo chown -R ubuntu:ubuntu /opt/devops-launchboard
cd /opt/devops-launchboard
git clone git@github.com:ashraful2430/N-tier-application.git app-source
cd app-source
```

If the repository is already cloned, pull latest changes:

```bash
cd /opt/devops-launchboard/app-source
git pull
```

Create the scenario folder:

```bash
mkdir -p deployment/phase-6-kubeadm/k8s
```

## Step 2: Create Kubernetes Manifests

```bash
cd /opt/devops-launchboard/app-source
```

### namespace.yaml

```bash
vim deployment/phase-6-kubeadm/k8s/namespace.yaml
```

Paste:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: devops-launchboard
  labels:
    app.kubernetes.io/name: devops-launchboard
    app.kubernetes.io/part-of: devops-launchboard
```

Line explanation:

- `apiVersion: v1` uses the core Kubernetes API.
- `kind: Namespace` creates a namespace object.
- `metadata.name: devops-launchboard` is the namespace name all other resources reference.
- `labels` are standard Kubernetes labels that identify which application this namespace belongs to.

Reference:

- Kubernetes Namespaces: https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/

### configmap.yaml

```bash
vim deployment/phase-6-kubeadm/k8s/configmap.yaml
```

Paste:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: launchboard-config
  namespace: devops-launchboard
data:
  APP_NAME: DevOps LaunchBoard API
  APP_ENV: production
  CORS_ORIGINS: http://YOUR_WORKER_1_PUBLIC_IP:30080
  SEED_DEMO_DATA: "true"
  POSTGRES_DB: launchboard
  POSTGRES_USER: launchboard_user
```

Replace `YOUR_WORKER_1_PUBLIC_IP` with the actual public IP of worker 1.

Line explanation:

- `CORS_ORIGINS: http://YOUR_WORKER_1_PUBLIC_IP:30080` must match the URL you use to access the app in the browser. For now the app is accessible via NodePort 30080. After installing MetalLB in Scenario 5, you update this to use port 80.
- All other fields have the same meaning as in Scenario 1.

Reference:

- Kubernetes ConfigMaps: https://kubernetes.io/docs/concepts/configuration/configmap/

### secret.example.yaml

```bash
vim deployment/phase-6-kubeadm/k8s/secret.example.yaml
```

Paste:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: launchboard-secret
  namespace: devops-launchboard
type: Opaque
stringData:
  POSTGRES_PASSWORD: CHANGE_ME_STRONG_PASSWORD
  DATABASE_URL: postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@launchboard-db:5432/launchboard
```

This is an example only. Do not commit real credentials to Git.

Reference:

- Kubernetes Secrets: https://kubernetes.io/docs/concepts/configuration/secret/

### pvc.yaml

```bash
vim deployment/phase-6-kubeadm/k8s/pvc.yaml
```

Paste:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: launchboard-postgres-pvc
  namespace: devops-launchboard
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

Line explanation:

- `accessModes: ReadWriteOnce` means one node at a time can mount this volume for reading and writing. This is correct for PostgreSQL which requires exclusive write access.
- `storage: 5Gi` requests 5 gibibytes of persistent storage from the local node disk.

Reference:

- PersistentVolumeClaims: https://kubernetes.io/docs/concepts/storage/persistent-volumes/#persistentvolumeclaims

### launchboard-postgres-deployment.yaml

```bash
vim deployment/phase-6-kubeadm/k8s/launchboard-postgres-deployment.yaml
```

Paste:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: launchboard-db
  namespace: devops-launchboard
  labels:
    app: launchboard-db
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: launchboard-db
  template:
    metadata:
      labels:
        app: launchboard-db
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          imagePullPolicy: IfNotPresent
          ports:
            - name: postgres
              containerPort: 5432
          env:
            - name: POSTGRES_DB
              valueFrom:
                configMapKeyRef:
                  name: launchboard-config
                  key: POSTGRES_DB
            - name: POSTGRES_USER
              valueFrom:
                configMapKeyRef:
                  name: launchboard-config
                  key: POSTGRES_USER
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: launchboard-secret
                  key: POSTGRES_PASSWORD
          volumeMounts:
            - name: postgres-data
              mountPath: /var/lib/postgresql/data
          readinessProbe:
            exec:
              command:
                - pg_isready
                - -U
                - launchboard_user
                - -d
                - launchboard
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            exec:
              command:
                - pg_isready
                - -U
                - launchboard_user
                - -d
                - launchboard
            initialDelaySeconds: 20
            periodSeconds: 15
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 1000m
              memory: 1Gi
      volumes:
        - name: postgres-data
          persistentVolumeClaim:
            claimName: launchboard-postgres-pvc
```

Line explanation:

- `strategy.type: Recreate` kills the old Pod before starting a new one during updates. Required because the PVC uses `ReadWriteOnce` which only allows one Pod to mount it at a time.
- `env` reads database name and user from the ConfigMap and password from the Secret. This keeps credentials out of the image and out of this manifest.
- `volumeMounts.mountPath: /var/lib/postgresql/data` is where PostgreSQL writes its data files. Mounting the PVC here means data persists across Pod restarts.
- `readinessProbe` and `livenessProbe` both run `pg_isready` to check if PostgreSQL is accepting connections.
- `resources.requests` reserves CPU and memory for scheduling. `resources.limits` prevents the Pod from using too much.

Reference:

- Kubernetes Deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
- Configure probes: https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/

### launchboard-postgres-service.yaml

```bash
vim deployment/phase-6-kubeadm/k8s/launchboard-postgres-service.yaml
```

Paste:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: launchboard-db
  namespace: devops-launchboard
spec:
  type: ClusterIP
  selector:
    app: launchboard-db
  ports:
    - name: postgres
      port: 5432
      targetPort: 5432
```

Line explanation:

- `metadata.name: launchboard-db` becomes the DNS name for the database inside the cluster. The `DATABASE_URL` in the Secret uses `launchboard-db` as the hostname. Any Pod in the namespace can reach the database at `launchboard-db:5432`.
- `type: ClusterIP` keeps the database private. Only Pods inside the cluster can reach it.
- `selector.app: launchboard-db` routes traffic to Pods with this label.

Reference:

- Kubernetes Services: https://kubernetes.io/docs/concepts/services-networking/service/

### launchboard-migration-job.yaml

```bash
vim deployment/phase-6-kubeadm/k8s/launchboard-migration-job.yaml
```

Paste:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: launchboard-migrate
  namespace: devops-launchboard
spec:
  backoffLimit: 3
  template:
    metadata:
      labels:
        app: launchboard-migrate
    spec:
      restartPolicy: OnFailure
      containers:
        - name: migrate
          image: ashik6251/launchboard-backend-k8s:v1
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
            - |
              until python -c "import socket; s=socket.create_connection(('launchboard-db', 5432), timeout=3); s.close()"; do
                echo "waiting for postgres"
                sleep 2
              done
              alembic upgrade head
          envFrom:
            - configMapRef:
                name: launchboard-config
            - secretRef:
                name: launchboard-secret
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 250m
              memory: 256Mi
```

Line explanation:

- `image: ashik6251/launchboard-backend-k8s:v1` pulls from Docker Hub. Update this to your published image name if you have pushed your own images.
- `imagePullPolicy: IfNotPresent` uses a cached image if it exists and only pulls if missing.
- The `until` loop waits until a TCP connection to `launchboard-db:5432` succeeds, ensuring PostgreSQL is ready before running migrations.
- `alembic upgrade head` applies all pending database migrations up to the latest version.
- `envFrom` loads all ConfigMap and Secret values as environment variables. Alembic reads `DATABASE_URL` from the Secret.

Reference:

- Kubernetes Jobs: https://kubernetes.io/docs/concepts/workloads/controllers/job/

### launchboard-backend-deployment.yaml

```bash
vim deployment/phase-6-kubeadm/k8s/launchboard-backend-deployment.yaml
```

Paste:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: launchboard-backend
  namespace: devops-launchboard
  labels:
    app: launchboard-backend
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: launchboard-backend
  template:
    metadata:
      labels:
        app: launchboard-backend
    spec:
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: backend
          image: ashik6251/launchboard-backend-k8s:v1
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
            - |
              until python -c "import socket; s=socket.create_connection(('launchboard-db', 5432), timeout=3); s.close()"; do
                echo "waiting for postgres"
                sleep 2
              done
              exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers
          ports:
            - name: http
              containerPort: 8000
          envFrom:
            - configMapRef:
                name: launchboard-config
            - secretRef:
                name: launchboard-secret
          readinessProbe:
            httpGet:
              path: /ready
              port: 8000
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 20
            periodSeconds: 15
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

Line explanation:

- `replicas: 2` runs two backend Pods. Kubernetes schedules them across both worker nodes automatically. If one worker goes down, the other worker still runs a backend Pod.
- `strategy.type: RollingUpdate` with `maxUnavailable: 0` ensures zero downtime during image updates.
- `securityContext.runAsNonRoot: true` prevents the container from running as root at the Kubernetes level, in addition to the Dockerfile USER instruction.
- `exec uvicorn ...` uses `exec` to replace the shell with Uvicorn so Uvicorn receives signals directly. This makes `kubectl rollout restart` and graceful shutdown work correctly.

Reference:

- Kubernetes Deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/

### launchboard-backend-service.yaml

```bash
vim deployment/phase-6-kubeadm/k8s/launchboard-backend-service.yaml
```

Paste:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: launchboard-backend
  namespace: devops-launchboard
spec:
  type: ClusterIP
  selector:
    app: launchboard-backend
  ports:
    - name: http
      port: 8000
      targetPort: 8000
```

Line explanation:

- `metadata.name: launchboard-backend` is the DNS name the frontend Nginx config uses in its `proxy_pass` directive.
- `type: ClusterIP` keeps the backend internal. Public traffic must go through the frontend, which proxies API calls.

Reference:

- Kubernetes Services: https://kubernetes.io/docs/concepts/services-networking/service/

### launchboard-frontend-deployment.yaml

```bash
vim deployment/phase-6-kubeadm/k8s/launchboard-frontend-deployment.yaml
```

Paste:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: launchboard-frontend
  namespace: devops-launchboard
  labels:
    app: launchboard-frontend
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: launchboard-frontend
  template:
    metadata:
      labels:
        app: launchboard-frontend
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 101
        runAsGroup: 101
        fsGroup: 101
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: frontend
          image: ashik6251/launchboard-frontend-k8s:v1
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8080
          readinessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 15
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 250m
              memory: 256Mi
```

Line explanation:

- `runAsUser: 101` and `runAsGroup: 101` match the nginx user UID and GID in the unprivileged Nginx image. If these do not match, Nginx cannot read its own static files.
- `fsGroup: 101` sets the group ownership of any mounted volumes to 101, so the Nginx process can read them.

Reference:

- Kubernetes Deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
- Security context: https://kubernetes.io/docs/tasks/configure-pod-container/security-context/

### launchboard-frontend-service.yaml

```bash
vim deployment/phase-6-kubeadm/k8s/launchboard-frontend-service.yaml
```

Paste:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: launchboard-frontend
  namespace: devops-launchboard
spec:
  type: ClusterIP
  selector:
    app: launchboard-frontend
  ports:
    - name: http
      port: 80
      targetPort: 8080
```

Line explanation:

- `port: 80` is the Service port that the NodePort Service and later the Ingress will target.
- `targetPort: 8080` is the actual port on the frontend Pod where Nginx listens.

Reference:

- Kubernetes Services: https://kubernetes.io/docs/concepts/services-networking/service/

### frontend-nodeport-service.yaml

This is a temporary Service that exposes the frontend on port 30080 on every node's public IP. You will remove it after installing MetalLB in Scenario 5.

```bash
vim deployment/phase-6-kubeadm/k8s/frontend-nodeport-service.yaml
```

Paste:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: launchboard-frontend-nodeport
  namespace: devops-launchboard
spec:
  type: NodePort
  selector:
    app: launchboard-frontend
  ports:
    - name: http
      port: 80
      targetPort: 8080
      nodePort: 30080
```

Line explanation:

- `type: NodePort` is a Service type that opens a port on every node's IP address. This is how you expose a Service publicly without a cloud load balancer or MetalLB.
- `nodePort: 30080` is the port that opens on every node. NodePort values must be in the range 30000-32767. Traffic to `ANY_NODE_IP:30080` is forwarded to a frontend Pod.
- `port: 80` is the internal Service port.
- `targetPort: 8080` is the Pod port.
- Why NodePort and not just updating the ClusterIP Service to NodePort: keeping them separate means you can delete the NodePort Service cleanly in Scenario 5 without touching the ClusterIP Service that the Ingress will use.

Reference:

- NodePort Services: https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport

### kustomization.yaml

```bash
vim deployment/phase-6-kubeadm/k8s/kustomization.yaml
```

Paste:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - configmap.yaml
  - pvc.yaml
  - launchboard-postgres-deployment.yaml
  - launchboard-postgres-service.yaml
  - launchboard-migration-job.yaml
  - launchboard-backend-deployment.yaml
  - launchboard-backend-service.yaml
  - launchboard-frontend-deployment.yaml
  - launchboard-frontend-service.yaml
  - frontend-nodeport-service.yaml
```

Line explanation:

- `secret.example.yaml` is not listed. The real Secret is created with `kubectl create secret`.
- `frontend-nodeport-service.yaml` is listed for now. You remove it from this list in Scenario 5 when you switch to MetalLB and Ingress.

Reference:

- Kustomize: https://kustomize.io/
- kubectl apply -k: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/

## Step 3: Create Namespace And Secret

```bash
cd /opt/devops-launchboard/app-source
kubectl apply -f deployment/phase-6-kubeadm/k8s/namespace.yaml

kubectl create secret generic launchboard-secret \
  --namespace devops-launchboard \
  --from-literal=POSTGRES_PASSWORD='CHANGE_ME_STRONG_PASSWORD' \
  --from-literal=DATABASE_URL='postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@launchboard-db:5432/launchboard'
```

Use the same password in both values.

Reference:

- kubectl create secret: https://kubernetes.io/docs/tasks/configmap-secret/managing-secret-using-kubectl/

## Step 4: Apply Manifests

```bash
kubectl apply -k deployment/phase-6-kubeadm/k8s
```

## Step 5: Verify Deployment

```bash
kubectl -n devops-launchboard get all
kubectl -n devops-launchboard get pvc
```

Wait for rollouts:

```bash
kubectl -n devops-launchboard rollout status deployment/launchboard-db
kubectl -n devops-launchboard rollout status deployment/launchboard-backend
kubectl -n devops-launchboard rollout status deployment/launchboard-frontend
```

Verify Pods spread across workers:

```bash
kubectl -n devops-launchboard get pods -o wide
```

You should see Pods running on both worker node IPs.

Check migration:

```bash
kubectl -n devops-launchboard logs job/launchboard-migrate
```

Expected: Alembic migration output ending with successful completion.

## Step 6: Allow NodePort In Worker Security Group

Go to the `devops-launchboard-k8s-worker-sg` security group and add:

| Type | Port | Source |
| --- | ---: | --- |
| Custom TCP | 30080 | Anywhere |

## Step 7: Verify The App

Open in browser:

```text
http://YOUR_WORKER_1_PUBLIC_IP:30080
```

Or worker 2 (both work because NodePort opens on every node):

```text
http://YOUR_WORKER_2_PUBLIC_IP:30080
```

From the control plane terminal:

```bash
curl -s http://YOUR_WORKER_1_PUBLIC_IP:30080/health | jq
curl -s http://YOUR_WORKER_1_PUBLIC_IP:30080/api/summary | jq
```

Expected: Frontend loads, API returns data, no CORS errors.

---

# Scenario 5: NGINX Ingress Controller with MetalLB

## Files And Folders For This Scenario

```text
/opt/devops-launchboard/app-source/
+-- deployment/
    +-- phase-6-kubeadm/
        +-- k8s/
            +-- ingress.yaml               (NEW: routes public traffic through Ingress Controller)
            +-- kustomization.yaml         (UPDATED: adds ingress.yaml, removes frontend-nodeport-service.yaml)
            +-- configmap.yaml             (UPDATED: CORS_ORIGINS changes from port 30080 to port 80)

Temporary files created on the server (not committed to Git):
+-- /tmp/metallb-config.yaml              (MetalLB IP address pool and L2 advertisement)
```

What each new or changed file does:

| File | What It Does | Why You Need It |
| --- | --- | --- |
| `ingress.yaml` | Defines HTTP routing rules for the Nginx Ingress Controller | Replaces NodePort with proper Ingress-based routing on port 80 |
| `kustomization.yaml` | Updated to include ingress.yaml and exclude the NodePort Service | Keeps deployment in sync with the new architecture |
| `configmap.yaml` | Updated CORS_ORIGINS from `:30080` to port 80 | Browser accesses app on port 80 now |
| `/tmp/metallb-config.yaml` | Tells MetalLB which IP addresses to assign | Without an IP pool MetalLB cannot assign IPs to LoadBalancer Services |

## What This Scenario Covers

Right now the app is accessible at `http://WORKER_IP:30080`. That works but it is not how production traffic reaches a cluster. In production you want port 80, a single stable entry point, and a routing layer that forwards requests based on path or hostname.

In a cloud environment like EKS, creating a Service with `type: LoadBalancer` automatically provisions a cloud load balancer. On a self-managed kubeadm cluster on EC2, there is no cloud integration. MetalLB fills that gap.

MetalLB is a software load balancer for bare-metal Kubernetes. It watches for Services with `type: LoadBalancer` and assigns them a real IP from a pool you define. The NGINX Ingress Controller is exposed as a LoadBalancer Service and MetalLB assigns it an IP. Traffic to that IP on port 80 enters the Ingress Controller, which applies your routing rules.

Traffic flow after this scenario:

```text
Browser
  |
  | HTTP port 80
  v
Worker node public IP
  |
  v
MetalLB (assigns private IP to Ingress Controller Service)
  |
  v
NGINX Ingress Controller Pod
  |
  | Reads Ingress rules, routes to launchboard-frontend Service
  v
launchboard-frontend ClusterIP Service
  |
  v
Frontend Pods (Nginx on port 8080)
  |
  | Proxies /api calls
  v
launchboard-backend ClusterIP Service
  |
  v
Backend Pods (Uvicorn on port 8000)
  |
  v
PostgreSQL Pod
```

## Step 1: Install MetalLB

Run on the control plane:

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
```

Wait for MetalLB Pods to be ready:

```bash
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=120s
```

Verify:

```bash
kubectl get pods -n metallb-system
```

Expected:

```text
metallb-system   controller-...   Running
metallb-system   speaker-...      Running   (one speaker Pod per node)
```

What MetalLB runs:

- `controller` is the MetalLB control plane. It watches for LoadBalancer Services and assigns IPs from the pool.
- `speaker` runs on every node. It announces assigned IPs to the network using ARP (Layer 2 mode). This is how the network learns that traffic for a particular IP should go to a particular node.

Reference:

- MetalLB installation: https://metallb.universe.tf/installation/
- MetalLB concepts: https://metallb.universe.tf/concepts/

## Step 2: Configure MetalLB IP Address Pool

Find the private IP of worker 1:

```bash
kubectl get nodes -o wide
```

Note the `INTERNAL-IP` column value for one of your worker nodes. You will use this as the MetalLB IP pool.

Create the configuration file:

```bash
vim /tmp/metallb-config.yaml
```

Paste the content below. Replace `WORKER_1_PRIVATE_IP` with the actual private IP from the output above:

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: launchboard-pool
  namespace: metallb-system
spec:
  addresses:
    - WORKER_1_PRIVATE_IP/32
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: launchboard-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - launchboard-pool
```

Apply:

```bash
kubectl apply -f /tmp/metallb-config.yaml
```

Line explanation:

- `kind: IPAddressPool` defines a pool of IP addresses that MetalLB is allowed to assign to LoadBalancer Services.
- `metadata.name: launchboard-pool` names this pool. The `L2Advertisement` object references this name.
- `spec.addresses` is the list of IP ranges MetalLB can use. Each entry can be a single IP, a range, or a CIDR block.
- `WORKER_1_PRIVATE_IP/32` is a single IP address. The `/32` prefix means exactly one IP, not a range. You use the worker's private IP because that IP is already routable within the VPC. MetalLB will assign this IP to the Ingress Controller Service.
- `kind: L2Advertisement` tells MetalLB to advertise assigned IPs using the Layer 2 ARP protocol. In Layer 2 mode, MetalLB's speaker on the node that holds the IP responds to ARP requests for that IP on the local network. This works within an AWS VPC because nodes are on the same subnet.
- `spec.ipAddressPools: [launchboard-pool]` links this advertisement to the pool defined above.

Note: Using worker 1's own private IP as the pool is a practical workaround for AWS, but it pins all ingress traffic to worker 1. If worker 1 goes down, the app becomes unreachable even though Pods still run on worker 2. In a real bare-metal environment you would give MetalLB a range of unused IPs on the subnet instead.

Reference:

- MetalLB Layer 2 mode: https://metallb.universe.tf/concepts/layer2/
- MetalLB IP address pools: https://metallb.universe.tf/configuration/#defining-the-ips-to-assign-to-the-load-balancer-services

## Step 3: Install NGINX Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/baremetal/deploy.yaml
```

Wait for the controller:

```bash
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s
```

Reference:

- Nginx Ingress baremetal installation: https://kubernetes.github.io/ingress-nginx/deploy/#bare-metal-clusters
- Nginx Ingress Controller: https://kubernetes.github.io/ingress-nginx/

## Step 4: Patch Ingress Controller Service To Use LoadBalancer

The baremetal Nginx Ingress install uses NodePort by default. Patch it to use LoadBalancer so MetalLB assigns it an IP from the pool:

```bash
kubectl patch svc ingress-nginx-controller \
  -n ingress-nginx \
  -p '{"spec": {"type": "LoadBalancer"}}'
```

Wait and check the external IP assignment:

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

Expected output after 30 to 60 seconds:

```text
NAME                       TYPE           CLUSTER-IP    EXTERNAL-IP              PORT(S)
ingress-nginx-controller   LoadBalancer   10.96.X.X     WORKER_1_PRIVATE_IP      80:.../TCP,443:.../TCP
```

The `EXTERNAL-IP` column should show the private IP of worker 1. This confirms MetalLB has assigned that IP to the Ingress Controller. Traffic arriving at worker 1's public IP on port 80 is forwarded to this private IP by AWS VPC routing, and then MetalLB forwards it to the Ingress Controller Pod.

Command explanation:

- `kubectl patch svc` modifies an existing Service resource.
- `-p '{"spec": {"type": "LoadBalancer"}}'` is a JSON patch that changes only the `spec.type` field without affecting other fields.

Reference:

- kubectl patch: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/update-api-object-kubectl-patch/

## Step 5: Create Ingress Resource

```bash
vim deployment/phase-6-kubeadm/k8s/ingress.yaml
```

Paste:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: launchboard-ingress
  namespace: devops-launchboard
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "60"
spec:
  ingressClassName: nginx
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: launchboard-frontend
                port:
                  number: 80
```

Line explanation:

- `annotations` pass extra configuration to the Nginx Ingress Controller.
- `nginx.ingress.kubernetes.io/proxy-read-timeout: "60"` sets the upstream read timeout to 60 seconds. This prevents the Ingress Controller from prematurely closing connections to backend services that are slow to respond.
- `nginx.ingress.kubernetes.io/proxy-send-timeout: "60"` sets the upstream send timeout to 60 seconds.
- `spec.ingressClassName: nginx` tells Kubernetes that the Nginx Ingress Controller should handle this Ingress resource. Without this field, no controller picks up the Ingress.
- `rules[0].http.paths[0].path: /` with `pathType: Prefix` matches all incoming requests regardless of path.
- `backend.service.name: launchboard-frontend` and `backend.service.port.number: 80` forward all matched traffic to the frontend ClusterIP Service on port 80.

Apply:

```bash
kubectl apply -f deployment/phase-6-kubeadm/k8s/ingress.yaml
```

Reference:

- Kubernetes Ingress: https://kubernetes.io/docs/concepts/services-networking/ingress/
- Nginx Ingress annotations: https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/

## Step 6: Update kustomization.yaml

```bash
vim deployment/phase-6-kubeadm/k8s/kustomization.yaml
```

Replace with:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - configmap.yaml
  - pvc.yaml
  - launchboard-postgres-deployment.yaml
  - launchboard-postgres-service.yaml
  - launchboard-migration-job.yaml
  - launchboard-backend-deployment.yaml
  - launchboard-backend-service.yaml
  - launchboard-frontend-deployment.yaml
  - launchboard-frontend-service.yaml
  - ingress.yaml
```

`frontend-nodeport-service.yaml` is removed. `ingress.yaml` is added.

## Step 7: Delete NodePort Service And Update ConfigMap

Delete the NodePort Service:

```bash
kubectl -n devops-launchboard delete service launchboard-frontend-nodeport
```

Update `CORS_ORIGINS` in the ConfigMap to use port 80:

```bash
vim deployment/phase-6-kubeadm/k8s/configmap.yaml
```

Change `CORS_ORIGINS` to:

```yaml
  CORS_ORIGINS: http://YOUR_WORKER_1_PUBLIC_IP
```

Remove the `:30080`. Port 80 is the default HTTP port so no port number is needed in the URL.

Apply all changes:

```bash
kubectl apply -k deployment/phase-6-kubeadm/k8s
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
kubectl -n devops-launchboard rollout restart deployment/launchboard-frontend
```

## Step 8: Update AWS Security Group

Add HTTP and HTTPS rules to the worker security group:

Go to `devops-launchboard-k8s-worker-sg` and add:

| Type | Port | Source |
| --- | ---: | --- |
| HTTP | 80 | Anywhere |
| HTTPS | 443 | Anywhere |

You can remove the port 30080 rule.

## Step 9: Verify

```bash
kubectl -n devops-launchboard get ingress
kubectl get svc -n ingress-nginx
```

Test:

```bash
curl -I http://YOUR_WORKER_1_PUBLIC_IP
curl -s http://YOUR_WORKER_1_PUBLIC_IP/health | jq
curl -s http://YOUR_WORKER_1_PUBLIC_IP/api/summary | jq
```

Open in browser:

```text
http://YOUR_WORKER_1_PUBLIC_IP
```

Expected: Frontend loads on port 80 with no port number in the URL. API works. No CORS errors.

---

# Scenario 6: HTTPS with Cert-Manager (Optional, Free with Let's Encrypt)

## Files And Folders For This Scenario

```text
/opt/devops-launchboard/app-source/
+-- deployment/
    +-- phase-6-kubeadm/
        +-- k8s/
            +-- ingress.yaml         (UPDATED: adds TLS section and cert-manager annotation)
            +-- configmap.yaml       (UPDATED: CORS_ORIGINS changes from http to https)

Temporary files created on the server (not committed to Git):
+-- /tmp/letsencrypt-issuer.yaml     (ClusterIssuer that tells cert-manager to use Let's Encrypt)
```

What each changed file does:

| File | What Changes | Why |
| --- | --- | --- |
| `ingress.yaml` | Adds TLS config and cert-manager annotation | Triggers certificate request and enables HTTPS |
| `configmap.yaml` | Changes CORS_ORIGINS to https:// | Backend must allow the HTTPS origin |
| `/tmp/letsencrypt-issuer.yaml` | Configures how cert-manager requests certificates | Cert-manager needs to know which CA to use and how to prove domain ownership |

## What You Need For This Scenario

- A domain name or subdomain pointing to `YOUR_WORKER_1_PUBLIC_IP`.
- Port 80 and 443 open on worker 1 (done in Scenario 5).

If you do not have a domain name, you have two options:

**Option A: Buy a cheap domain.** Domains are available from $1 to $3 per year:

- Namecheap: https://www.namecheap.com (look for `.xyz`, `.site`, or `.online` domains)
- Cloudflare Registrar: https://www.cloudflare.com/products/registrar/ (sells at cost with no markup)
- Name.com: https://www.name.com

After buying, create an A record:

```text
Type: A
Name: launchboard (or @ for root domain)
Value: YOUR_WORKER_1_PUBLIC_IP
TTL: 300
```

This creates `launchboard.yourdomain.com` pointing to your worker IP.

**Option B: Skip this scenario.** The application works correctly on HTTP for learning purposes. HTTPS is important in production but optional here. Move directly to Scenario 7.

## Step 1: Install Cert-Manager

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
```

Wait for Cert-Manager Pods:

```bash
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=cert-manager \
  --timeout=120s
```

Verify:

```bash
kubectl get pods -n cert-manager
```

Expected:

```text
cert-manager-...            Running
cert-manager-cainjector-... Running
cert-manager-webhook-...    Running
```

What each component does:

- `cert-manager` is the main controller. It watches for Certificate resources and requests certificates from the configured issuer.
- `cert-manager-cainjector` injects CA data into webhook configurations so Kubernetes can validate cert-manager's own webhooks.
- `cert-manager-webhook` is a Kubernetes admission webhook that validates Certificate and Issuer resources when they are created.

Reference:

- Cert-Manager installation: https://cert-manager.io/docs/installation/
- Cert-Manager overview: https://cert-manager.io/docs/

## Step 2: Create Let's Encrypt ClusterIssuer

A ClusterIssuer tells cert-manager where to get certificates and how to prove domain ownership. Let's Encrypt uses the HTTP-01 challenge: it asks cert-manager to place a specific file at `http://YOUR_DOMAIN/.well-known/acme-challenge/TOKEN`. Let's Encrypt then fetches that file to verify you control the domain. This is why port 80 must be publicly accessible.

```bash
vim /tmp/letsencrypt-issuer.yaml
```

Paste:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: YOUR_EMAIL_ADDRESS
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx
```

Replace `YOUR_EMAIL_ADDRESS` with your real email address.

Line explanation:

- `kind: ClusterIssuer` is a cluster-wide resource. Unlike a regular `Issuer` which is namespace-scoped, a `ClusterIssuer` can issue certificates for all namespaces.
- `spec.acme.server` is the URL of the ACME (Automated Certificate Management Environment) directory for Let's Encrypt production. ACME is the protocol that cert-manager uses to request and renew certificates automatically.
- `spec.acme.email` is your email address. Let's Encrypt sends certificate expiry warning emails to this address if automatic renewal fails.
- `spec.acme.privateKeySecretRef.name: letsencrypt-prod-key` names the Secret where cert-manager stores the private key for your Let's Encrypt account. Cert-manager creates this Secret automatically.
- `solvers[0].http01` configures the HTTP-01 challenge type. Cert-manager creates a temporary Ingress resource and a Pod that serves the challenge file. Let's Encrypt fetches the file to verify domain ownership.
- `ingress.ingressClassName: nginx` tells cert-manager to use the Nginx Ingress Controller to serve the challenge.

Apply:

```bash
kubectl apply -f /tmp/letsencrypt-issuer.yaml
```

Verify:

```bash
kubectl get clusterissuer letsencrypt-prod
```

Expected:

```text
NAME               READY   AGE
letsencrypt-prod   True    1m
```

Reference:

- Cert-Manager ClusterIssuer: https://cert-manager.io/docs/configuration/acme/
- Let's Encrypt HTTP-01 challenge: https://cert-manager.io/docs/configuration/acme/http01/
- Let's Encrypt how it works: https://letsencrypt.org/how-it-works/

## Step 3: Update Ingress For HTTPS

```bash
vim deployment/phase-6-kubeadm/k8s/ingress.yaml
```

Replace the content with:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: launchboard-ingress
  namespace: devops-launchboard
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "60"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - YOUR_DOMAIN
      secretName: launchboard-tls
  rules:
    - host: YOUR_DOMAIN
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: launchboard-frontend
                port:
                  number: 80
```

Replace `YOUR_DOMAIN` with your actual domain (for example `launchboard.yourdomain.com`).

Line explanation:

- `cert-manager.io/cluster-issuer: "letsencrypt-prod"` is the annotation that triggers cert-manager. When cert-manager sees this annotation on an Ingress, it automatically creates a Certificate resource and requests a certificate from the named ClusterIssuer.
- `nginx.ingress.kubernetes.io/ssl-redirect: "true"` tells the Nginx Ingress Controller to redirect all HTTP requests to HTTPS automatically. A visitor going to `http://YOUR_DOMAIN` is redirected to `https://YOUR_DOMAIN`.
- `spec.tls` is the TLS configuration section.
- `tls[0].hosts: [YOUR_DOMAIN]` lists the hostnames the certificate should cover.
- `tls[0].secretName: launchboard-tls` is the name of the Secret where cert-manager stores the issued TLS certificate and private key. The Nginx Ingress Controller reads this Secret to serve HTTPS.
- `rules[0].host: YOUR_DOMAIN` adds a host-based routing rule. The Ingress now only matches requests for this specific domain.

Apply:

```bash
kubectl apply -f deployment/phase-6-kubeadm/k8s/ingress.yaml
```

Reference:

- Cert-Manager securing Ingress: https://cert-manager.io/docs/usage/ingress/
- Nginx Ingress TLS: https://kubernetes.github.io/ingress-nginx/user-guide/tls/

## Step 4: Update ConfigMap For HTTPS

```bash
vim deployment/phase-6-kubeadm/k8s/configmap.yaml
```

Change `CORS_ORIGINS` to:

```yaml
  CORS_ORIGINS: https://YOUR_DOMAIN
```

Apply and restart:

```bash
kubectl apply -k deployment/phase-6-kubeadm/k8s
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
kubectl -n devops-launchboard rollout restart deployment/launchboard-frontend
```

## Step 5: Monitor Certificate Issuance

```bash
kubectl -n devops-launchboard get certificate
```

It takes 1 to 3 minutes. Watch the status:

```bash
kubectl -n devops-launchboard describe certificate launchboard-tls
```

When issued:

```text
NAME             READY   SECRET           AGE
launchboard-tls  True    launchboard-tls  2m
```

## Step 6: Verify HTTPS

Open in browser:

```text
https://YOUR_DOMAIN
```

Expected: Padlock icon appears, certificate is valid, frontend loads over HTTPS, HTTP redirects to HTTPS automatically.

---

# Scenario 7: Metrics Server

## Files And Folders For This Scenario

No new project files are created in this scenario. Metrics Server is installed via a manifest applied directly from the internet. The only change is a patch command you run to make Metrics Server work with self-signed kubelet certificates.

## What This Scenario Covers

Kubernetes has a `kubectl top` command that shows CPU and memory usage for nodes and Pods. By default it does not work because there is no component collecting resource usage data. Metrics Server is the official lightweight component that collects this data.

Metrics Server is also required for HPA to work. HPA reads CPU and memory metrics from Metrics Server to decide when to scale Pods up or down.

## Step 1: Install Metrics Server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

For a kubeadm cluster on EC2, the kubelets use self-signed TLS certificates. Metrics Server tries to verify these certificates and fails by default. Add `--kubelet-insecure-tls` to skip certificate verification:

```bash
kubectl patch deployment metrics-server \
  -n kube-system \
  --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
```

Command explanation:

- `kubectl patch deployment metrics-server -n kube-system` modifies the Metrics Server Deployment.
- `--type='json'` uses JSON Patch format, which lets you add, remove, or replace specific fields.
- `"op": "add"` means add a new item.
- `"path": "/spec/template/spec/containers/0/args/-"` targets the args array of the first container. The `-` at the end means append to the array.
- `"value": "--kubelet-insecure-tls"` is the value to append. This flag tells Metrics Server not to verify the kubelet's TLS certificate.

Wait for Metrics Server:

```bash
kubectl wait --namespace kube-system \
  --for=condition=ready pod \
  --selector=k8s-app=metrics-server \
  --timeout=120s
```

Reference:

- Metrics Server: https://github.com/kubernetes-sigs/metrics-server
- Metrics Server installation: https://kubernetes-sigs.github.io/metrics-server/

## Step 2: Verify Metrics Server

```bash
kubectl top nodes
```

Expected:

```text
NAME      CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
ip-...    45m          2%     1200Mi          30%
ip-...    38m          1%     980Mi           24%
ip-...    42m          2%     1050Mi          26%
```

```bash
kubectl top pods -n devops-launchboard
```

Expected:

```text
NAME                          CPU(cores)   MEMORY(bytes)
launchboard-backend-...       5m           80Mi
launchboard-backend-...       4m           78Mi
launchboard-db-...            8m           120Mi
launchboard-frontend-...      2m           30Mi
launchboard-frontend-...      2m           28Mi
```

## Step 3: Compare Actual Usage To Defined Resources

```bash
kubectl -n devops-launchboard get pods \
  -o custom-columns=\
"NAME:.metadata.name,\
CPU_REQ:.spec.containers[0].resources.requests.cpu,\
CPU_LIM:.spec.containers[0].resources.limits.cpu,\
MEM_REQ:.spec.containers[0].resources.requests.memory,\
MEM_LIM:.spec.containers[0].resources.limits.memory"
```

Compare this output to `kubectl top pods`. If actual usage is much lower than your limits, you can reduce them. If actual usage approaches your limits, increase them. Setting accurate resource values improves scheduling and prevents OOMKilled events.

Reference:

- Resource management: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
- kubectl top: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_top/

---

# Scenario 8: Horizontal Pod Autoscaler

## Files And Folders For This Scenario

```text
/opt/devops-launchboard/app-source/
+-- deployment/
    +-- phase-6-kubeadm/
        +-- k8s/
            +-- hpa.yaml               (NEW: autoscaling rules for the backend Deployment)
            +-- kustomization.yaml     (UPDATED: adds hpa.yaml to the resources list)
```

What each file does:

| File | What It Does | Why You Need It |
| --- | --- | --- |
| `hpa.yaml` | Defines min/max replicas and CPU target for the backend | Scales backend Pods automatically based on real load |
| `kustomization.yaml` | Updated to include hpa.yaml | Ensures HPA is applied with the rest of the manifests |

## What This Scenario Covers

HPA (Horizontal Pod Autoscaler) watches CPU or memory usage of a Deployment and automatically changes the replica count to match the load. When CPU goes high, it adds Pods. When load drops, it removes them.

This is how production clusters handle variable traffic without wasting resources. You define the minimum and maximum replica count and a target utilization. Kubernetes does the rest.

HPA requires Metrics Server to be running, which you installed in Scenario 7.

## Step 1: Create HPA Manifest

```bash
vim deployment/phase-6-kubeadm/k8s/hpa.yaml
```

Paste:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: launchboard-backend-hpa
  namespace: devops-launchboard
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: launchboard-backend
  minReplicas: 2
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

Line explanation:

- `apiVersion: autoscaling/v2` uses version 2 of the autoscaling API which supports multiple metric types. Version 1 only supported CPU.
- `kind: HorizontalPodAutoscaler` creates an HPA object.
- `spec.scaleTargetRef` identifies which resource to scale.
- `scaleTargetRef.apiVersion: apps/v1` is the API group of the target resource.
- `scaleTargetRef.kind: Deployment` means the target is a Deployment.
- `scaleTargetRef.name: launchboard-backend` names the specific Deployment. The HPA reads that Deployment's `resources.requests.cpu` to calculate what 70% means in absolute millicores.
- `spec.minReplicas: 2` is the floor. HPA never scales below 2 Pods. Even with zero traffic, 2 backend Pods are always running for redundancy.
- `spec.maxReplicas: 5` is the ceiling. HPA never creates more than 5 Pods regardless of load.
- `spec.metrics[0].type: Resource` specifies that you are measuring a standard compute resource.
- `resource.name: cpu` measures CPU usage.
- `target.type: Utilization` compares actual CPU to the Pod's `requests.cpu` value.
- `target.averageUtilization: 70` sets the target. If the average CPU across all backend Pods exceeds 70% of their requested CPU, the HPA adds more Pods. If it drops significantly below 70%, the HPA removes Pods (after a cooldown period).

Apply:

```bash
kubectl apply -f deployment/phase-6-kubeadm/k8s/hpa.yaml
```

Reference:

- HPA documentation: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
- HPA algorithm: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#algorithm-details

## Step 2: Update kustomization.yaml

```bash
vim deployment/phase-6-kubeadm/k8s/kustomization.yaml
```

Replace with:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - configmap.yaml
  - pvc.yaml
  - launchboard-postgres-deployment.yaml
  - launchboard-postgres-service.yaml
  - launchboard-migration-job.yaml
  - launchboard-backend-deployment.yaml
  - launchboard-backend-service.yaml
  - launchboard-frontend-deployment.yaml
  - launchboard-frontend-service.yaml
  - ingress.yaml
  - hpa.yaml
```

## Step 3: Verify HPA

```bash
kubectl -n devops-launchboard get hpa
```

Expected:

```text
NAME                      REFERENCE                       TARGETS   MINPODS   MAXPODS   REPLICAS
launchboard-backend-hpa   Deployment/launchboard-backend  3%/70%    2         5         2
```

`TARGETS` shows current CPU percentage versus the 70% target. `3%/70%` means the backend is using 3% of its requested CPU, well below the scale-up threshold.

## Step 4: Test Autoscaling With A Load Generator

Run a Pod that continuously sends requests to the backend:

```bash
kubectl run load-generator \
  --image=busybox:1.28 \
  --restart=Never \
  -n devops-launchboard \
  -- /bin/sh -c "while true; do wget -q -O- http://launchboard-backend:8000/health > /dev/null; done"
```

Watch HPA respond in real time:

```bash
kubectl -n devops-launchboard get hpa -w
```

Within 1 to 2 minutes you should see `REPLICAS` increase as CPU rises above 70%.

Watch Pods being created:

```bash
kubectl -n devops-launchboard get pods -w
```

Stop the load generator:

```bash
kubectl delete pod load-generator -n devops-launchboard
```

Watch Pods scale back down. HPA waits approximately 5 minutes of sustained low usage before scaling down. This cooldown period prevents rapid scale-up and scale-down cycles (thrashing).

Reference:

- HPA walkthrough: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/

---

# Scenario 11: ArgoCD GitOps

## Files And Folders For This Scenario

No new manifest files are added to the project for ArgoCD itself. ArgoCD is installed into the cluster. You create one ArgoCD Application resource that points to your existing manifests.

```text
Temporary files created on the server (not committed to Git):
+-- /tmp/argocd-app.yaml    (optional: if you prefer applying the Application as YAML instead of CLI)

Tools installed on the control plane:
+-- /usr/local/bin/argocd   (ArgoCD CLI)
```

## What This Scenario Covers

Until now you deployed the application by running `kubectl apply` manually from the terminal. In production, manual deployments cause problems:

- Someone might apply a manifest from their local machine that is out of date with Git.
- There is no audit trail of who deployed what and when.
- If the cluster is accidentally modified, there is nothing to detect or fix the drift.

GitOps solves all of this. The principle is simple: Git is the source of truth. The cluster state must always match what is in Git. ArgoCD watches your Git repository and automatically applies changes when it detects a diff between Git and the cluster.

```text
You push a change to Git
  |
  v
ArgoCD detects the change (polls every 3 minutes by default)
  |
  v
ArgoCD compares the Git manifests to the live cluster state
  |
  v
ArgoCD applies the diff to make the cluster match Git
  |
  v
Cluster state matches Git again (Synced)
```

## Step 1: Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Wait for ArgoCD to be ready:

```bash
kubectl wait --namespace argocd \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=argocd-server \
  --timeout=300s
```

Verify:

```bash
kubectl get pods -n argocd
```

Expected:

```text
argocd-application-controller-...   Running
argocd-dex-server-...               Running
argocd-redis-...                    Running
argocd-repo-server-...              Running
argocd-server-...                   Running
```

What each component does:

- `argocd-server` is the API server and web UI. You interact with it through the browser or the CLI.
- `argocd-application-controller` is the main controller. It watches Application resources, compares Git to cluster state, and applies changes.
- `argocd-repo-server` clones and caches Git repositories. It generates the final manifests from Kustomize, Helm, or plain YAML.
- `argocd-redis` is used by ArgoCD for internal caching to reduce repeated Git and API calls.
- `argocd-dex-server` handles SSO (Single Sign-On) authentication. In a basic setup it is not heavily used.

Reference:

- ArgoCD installation: https://argo-cd.readthedocs.io/en/stable/getting_started/
- ArgoCD architecture: https://argo-cd.readthedocs.io/en/stable/operator-manual/architecture/

## Step 2: Expose ArgoCD UI With NodePort

ArgoCD has a web UI. Expose it using NodePort so you can access it from your browser without needing a domain.

```bash
kubectl patch svc argocd-server \
  -n argocd \
  -p '{"spec": {"type": "NodePort"}}'
```

Find the assigned NodePort:

```bash
kubectl get svc argocd-server -n argocd
```

Expected:

```text
NAME           TYPE       CLUSTER-IP   EXTERNAL-IP   PORT(S)
argocd-server  NodePort   10.96.X.X    <none>         80:3XXXX/TCP,443:3XXXX/TCP
```

Note the port mapped to 443. It will be something like `32443`. This is your ArgoCD UI port.

Add this port to the worker security group. Go to `devops-launchboard-k8s-worker-sg` and add:

| Type | Port | Source |
| --- | ---: | --- |
| Custom TCP | YOUR_ARGOCD_NODEPORT | Your IP |

Open in browser:

```text
https://YOUR_WORKER_1_PUBLIC_IP:YOUR_ARGOCD_NODEPORT
```

Your browser will show a certificate warning because ArgoCD uses a self-signed certificate by default. Click Advanced and proceed. This is expected in a lab without a real TLS certificate for ArgoCD.

Reference:

- ArgoCD getting started: https://argo-cd.readthedocs.io/en/stable/getting_started/#3-access-the-argo-cd-api-server

## Step 3: Get ArgoCD Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Command explanation:

- `kubectl get secret argocd-initial-admin-secret` reads the Secret that ArgoCD creates automatically with the initial admin password.
- `-o jsonpath="{.data.password}"` extracts just the password field from the Secret.
- `base64 -d` decodes the base64-encoded value. Kubernetes Secret values are always base64 encoded.
- `&& echo` adds a newline after the password so it is readable in the terminal.

Log in to the ArgoCD UI:

```text
Username: admin
Password: output from the command above
```

Reference:

- ArgoCD initial login: https://argo-cd.readthedocs.io/en/stable/getting_started/#4-login-using-the-cli

## Step 4: Install ArgoCD CLI

```bash
cd ~
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/argocd
```

Command explanation:

- `curl -sSL -o argocd` downloads the ArgoCD CLI binary for Linux AMD64. `-s` hides progress, `-S` shows errors, `-L` follows redirects, `-o argocd` saves with the name `argocd`.
- `chmod +x argocd` makes it executable.
- `sudo mv argocd /usr/local/bin/argocd` places it in the system PATH.

Log in using the CLI:

```bash
ARGOCD_PORT=$(kubectl get svc argocd-server -n argocd \
  -o jsonpath='{.spec.ports[?(@.port==443)].nodePort}')

argocd login YOUR_WORKER_1_PUBLIC_IP:${ARGOCD_PORT} \
  --username admin \
  --password $(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d) \
  --insecure
```

Command explanation:

- The first command reads the NodePort mapped to port 443 from the argocd-server Service and stores it in `ARGOCD_PORT`.
- `argocd login` authenticates the CLI with the ArgoCD server.
- `--insecure` skips TLS certificate verification because ArgoCD uses a self-signed certificate.

Reference:

- ArgoCD CLI: https://argo-cd.readthedocs.io/en/stable/user-guide/commands/argocd/

## Step 5: Create ArgoCD Application

This tells ArgoCD to watch your Git repository and keep the cluster in sync with the manifests in `deployment/phase-6-kubeadm/k8s`.

```bash
argocd app create launchboard \
  --repo https://github.com/ashraful2430/N-tier-application.git \
  --path deployment/phase-6-kubeadm/k8s \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace devops-launchboard \
  --sync-policy automated \
  --auto-prune \
  --self-heal
```

Command explanation:

- `argocd app create launchboard` creates an ArgoCD Application named `launchboard`.
- `--repo` is the Git repository URL. HTTPS is used here so ArgoCD can read a public repository without an SSH key. If your repository is private, you need to add credentials to ArgoCD first.
- `--path deployment/phase-6-kubeadm/k8s` is the folder inside the repository containing the Kubernetes manifests. ArgoCD reads the `kustomization.yaml` in this folder and renders all listed resources.
- `--dest-server https://kubernetes.default.svc` tells ArgoCD to deploy to the cluster it is running inside. `kubernetes.default.svc` is the DNS name of the Kubernetes API server as seen from inside the cluster.
- `--dest-namespace devops-launchboard` is the namespace where resources are deployed.
- `--sync-policy automated` makes ArgoCD apply changes automatically when it detects a difference between Git and the cluster. Without this, you would need to click Sync manually in the UI.
- `--auto-prune` means if you delete a resource from Git, ArgoCD deletes it from the cluster too. Without this, deleted Git resources remain in the cluster.
- `--self-heal` means if someone manually changes a resource in the cluster (bypassing Git), ArgoCD automatically reverts the change to match Git. This enforces GitOps discipline.

Reference:

- ArgoCD Application: https://argo-cd.readthedocs.io/en/stable/user-guide/application-specification/
- ArgoCD sync policies: https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/

## Step 6: Verify ArgoCD Sync

```bash
argocd app get launchboard
```

Expected:

```text
Health Status: Healthy
Sync Status:   Synced
```

In the ArgoCD UI you can see a visual graph of all Kubernetes resources, their health, and sync status.

Note: The migration Job is part of the kustomization. Kubernetes Jobs are immutable after creation, so the Application may show OutOfSync on the Job resource after its first run. This is expected. If it bothers you, you can move the Job out of the kustomization, or add the ArgoCD annotation `argocd.argoproj.io/hook: Sync` to the Job so ArgoCD re-creates it on each sync instead of diffing it.

## Step 7: Test GitOps In Action

Make a change in Git and watch ArgoCD apply it automatically.

Edit the backend Deployment to increase replicas:

```bash
vim deployment/phase-6-kubeadm/k8s/launchboard-backend-deployment.yaml
```

Change `replicas: 2` to `replicas: 3`.

Commit and push:

```bash
git add deployment/phase-6-kubeadm/k8s/launchboard-backend-deployment.yaml
git commit -m "scale backend to 3 replicas for test"
git push origin main
```

Watch ArgoCD detect the change (within 3 minutes):

```bash
argocd app get launchboard
```

The status changes from `Synced` to `OutOfSync`, then ArgoCD applies the change and returns to `Synced`.

Verify the replica count:

```bash
kubectl -n devops-launchboard get pods -l app=launchboard-backend
```

Expected: 3 backend Pods running.

Revert: Change `replicas: 3` back to `replicas: 2`, commit, and push. ArgoCD scales back down automatically.

## Step 8: Change ArgoCD Admin Password

```bash
argocd account update-password \
  --account admin \
  --current-password $(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d) \
  --new-password YOUR_NEW_STRONG_PASSWORD
```

Reference:

- ArgoCD user management: https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/

---

# Scenario 12: Production Hardening

## Files And Folders For This Scenario

```text
/opt/devops-launchboard/app-source/
+-- deployment/
    +-- phase-6-kubeadm/
        +-- hardening/
            +-- networkpolicy.yaml      (NEW: restricts Pod-to-Pod communication)
            +-- resourcequota.yaml      (NEW: limits total namespace resource usage)
            +-- rbac.yaml               (NEW: read-only developer role)
            +-- pdb.yaml                (NEW: prevents all replicas going down at once)
```

What each file does:

| File | What It Does | Why You Need It |
| --- | --- | --- |
| `networkpolicy.yaml` | Defines which Pods can talk to which, denies everything else | Prevents a compromised frontend from directly reaching the database |
| `resourcequota.yaml` | Caps total CPU, memory, and Pod count in the namespace | Prevents one app from consuming all cluster resources |
| `rbac.yaml` | Creates a read-only role for developers | Enforces least-privilege access: developers can view but not modify |
| `pdb.yaml` | Ensures at least 1 Pod of each Deployment stays up during node maintenance | Prevents total downtime during cluster upgrades or node drains |

## Step 1: Create The Hardening Folder

```bash
mkdir -p /opt/devops-launchboard/app-source/deployment/phase-6-kubeadm/hardening
cd /opt/devops-launchboard/app-source
```

## Step 2: Pod Security Standards

Pod Security Standards are built into Kubernetes since version 1.23. They are enforced by applying labels to namespaces. There are three levels:

- `privileged`: no restrictions
- `baseline`: blocks the most dangerous configurations (running as root, hostPID, privileged containers)
- `restricted`: most secure, requires non-root, drops all Linux capabilities, enforces seccomp

Your application already runs as non-root with seccomp profiles. The `restricted` level applies.

Apply security labels to the namespace:

```bash
kubectl label namespace devops-launchboard \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/warn-version=latest \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/audit-version=latest
```

Label explanation:

- `pod-security.kubernetes.io/enforce=restricted` rejects Pods that violate the restricted policy. They cannot be created.
- `pod-security.kubernetes.io/warn=restricted` shows a warning when a Pod would violate the policy, but still allows it. Useful during migration.
- `pod-security.kubernetes.io/audit=restricted` logs violations to the API server audit log without blocking anything.
- `enforce-version=latest` and `warn-version=latest` use the latest version of the policy definitions.
- Setting all three to `restricted` means violations are blocked, warned about, and logged.

Verify the labels:

```bash
kubectl get namespace devops-launchboard --show-labels
```

Test that a privileged Pod is rejected:

```bash
kubectl run test-privileged \
  --image=nginx \
  -n devops-launchboard \
  --overrides='{"spec":{"containers":[{"name":"test","image":"nginx","securityContext":{"privileged":true}}]}}' \
  --restart=Never
```

Expected:

```text
Error from server (Forbidden): ... violates PodSecurity "restricted:latest"
```

Clean up:

```bash
kubectl delete pod test-privileged -n devops-launchboard --ignore-not-found
```

Reference:

- Pod Security Standards: https://kubernetes.io/docs/concepts/security/pod-security-standards/
- Pod Security Admission: https://kubernetes.io/docs/concepts/security/pod-security-admission/

## Step 3: NetworkPolicy

By default, every Pod in a Kubernetes cluster can reach every other Pod in every namespace. This is called a flat network model. It is convenient but dangerous: if an attacker gets into the frontend Pod, nothing stops them from connecting directly to the PostgreSQL Pod.

NetworkPolicy restricts which Pods can send traffic to which other Pods and on which ports. You write rules like: "the backend is only allowed to receive traffic from the frontend" and "the database only accepts traffic from the backend and the migration Job."

```bash
vim deployment/phase-6-kubeadm/hardening/networkpolicy.yaml
```

Paste:

```yaml
# Deny all ingress and egress by default in this namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: devops-launchboard
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
# Allow the Nginx Ingress Controller to reach the frontend
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-to-frontend
  namespace: devops-launchboard
spec:
  podSelector:
    matchLabels:
      app: launchboard-frontend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
---
# Allow frontend Pods to reach backend Pods on port 8000
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: devops-launchboard
spec:
  podSelector:
    matchLabels:
      app: launchboard-backend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: launchboard-frontend
      ports:
        - protocol: TCP
          port: 8000
---
# Allow backend and migration Pods to reach the database on port 5432
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-backend-to-db
  namespace: devops-launchboard
spec:
  podSelector:
    matchLabels:
      app: launchboard-db
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: launchboard-backend
        - podSelector:
            matchLabels:
              app: launchboard-migrate
      ports:
        - protocol: TCP
          port: 5432
---
# Allow all Pods to make DNS queries to CoreDNS in kube-system
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: devops-launchboard
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
---
# Allow frontend Pods to make outbound calls to the backend
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-egress
  namespace: devops-launchboard
spec:
  podSelector:
    matchLabels:
      app: launchboard-frontend
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: launchboard-backend
      ports:
        - protocol: TCP
          port: 8000
---
# Allow backend Pods to make outbound calls to the database
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-backend-egress
  namespace: devops-launchboard
spec:
  podSelector:
    matchLabels:
      app: launchboard-backend
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: launchboard-db
      ports:
        - protocol: TCP
          port: 5432
```

Line explanation for key sections:

- `podSelector: {}` in `default-deny-all` means this policy applies to all Pods in the namespace. An empty selector selects everything.
- `policyTypes: [Ingress, Egress]` means both incoming and outgoing traffic are denied by default.
- `namespaceSelector.matchLabels.kubernetes.io/metadata.name: ingress-nginx` selects the `ingress-nginx` namespace. Kubernetes automatically adds this label to every namespace with the namespace's own name. This is how you allow traffic from the Ingress Controller namespace without knowing the exact Pod IPs.
- Each subsequent policy opens only specific traffic paths. The combination of all policies results in the minimum necessary communication: browser-to-frontend, frontend-to-backend, backend-to-database, and all Pods to DNS.

Apply:

```bash
kubectl apply -f deployment/phase-6-kubeadm/hardening/networkpolicy.yaml
```

Verify the app still works:

```bash
curl -s http://YOUR_WORKER_1_PUBLIC_IP/health | jq
curl -s http://YOUR_WORKER_1_PUBLIC_IP/api/summary | jq
```

Enable NetworkPolicy enforcement with Flannel:

Flannel does not enforce NetworkPolicy by default. Install kube-router alongside Flannel to add enforcement.

> **Caution:** The `kubeadm-kuberouter-all-features.yaml` manifest runs kube-router with its own CNI, routing, and service proxy enabled, which conflicts with the Flannel CNI and kube-proxy already running in this cluster. When running kube-router alongside Flannel, deploy it in firewall-only mode (`--run-firewall=true --run-router=false --run-service-proxy=false`). The cleanest alternative is to replace Flannel with a CNI that enforces NetworkPolicy natively, such as Calico. See the kube-router docs linked below before applying.

```bash
kubectl apply -f https://raw.githubusercontent.com/cloudnativelabs/kube-router/master/daemonset/kubeadm-kuberouter-all-features.yaml
```

Wait:

```bash
kubectl wait --namespace kube-system \
  --for=condition=ready pod \
  --selector=k8s-app=kube-router \
  --timeout=120s
```

Reference:

- Kubernetes NetworkPolicy: https://kubernetes.io/docs/concepts/services-networking/network-policies/
- NetworkPolicy tutorial: https://kubernetes.io/docs/tasks/administer-cluster/declare-network-policy/
- kube-router: https://www.kube-router.io/

## Step 4: ResourceQuota

A ResourceQuota limits the total amount of CPU, memory, and other resources that all Pods in a namespace can consume combined. Without quotas, a single misbehaving application can consume all resources on the cluster and starve other workloads.

```bash
vim deployment/phase-6-kubeadm/hardening/resourcequota.yaml
```

Paste:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: launchboard-quota
  namespace: devops-launchboard
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 2Gi
    limits.cpu: "4"
    limits.memory: 4Gi
    pods: "20"
    persistentvolumeclaims: "5"
```

Line explanation:

- `apiVersion: v1` uses the core API. ResourceQuota is a core resource.
- `kind: ResourceQuota` creates a quota object that Kubernetes enforces on every new Pod creation.
- `spec.hard` defines the absolute maximums that cannot be exceeded.
- `requests.cpu: "2"` means the sum of all `resources.requests.cpu` values across all Pods in this namespace cannot exceed 2 CPU cores.
- `requests.memory: 2Gi` caps total memory requests at 2 gibibytes.
- `limits.cpu: "4"` caps total CPU limits at 4 CPU cores.
- `limits.memory: 4Gi` caps total memory limits at 4 gibibytes.
- `pods: "20"` means no more than 20 Pods can exist in this namespace at once. This includes Pods created by HPA scale-up.
- `persistentvolumeclaims: "5"` limits the number of PVCs to 5.

Apply:

```bash
kubectl apply -f deployment/phase-6-kubeadm/hardening/resourcequota.yaml
```

View current usage against the quota:

```bash
kubectl -n devops-launchboard describe resourcequota launchboard-quota
```

Expected output shows used versus hard limit for each resource.

Reference:

- Kubernetes ResourceQuota: https://kubernetes.io/docs/concepts/policy/resource-quotas/
- Configuring quotas: https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/quota-memory-cpu-namespace/

## Step 5: RBAC

RBAC (Role-Based Access Control) defines who can do what in Kubernetes. Instead of giving every team member full cluster admin access, you create specific roles with specific permissions and bind them to users or service accounts.

The principle is least privilege: a user gets only the permissions they need for their job, nothing more.

For this lab, create a read-only role for a developer who needs to see Pod status and logs but must not be able to modify anything.

```bash
vim deployment/phase-6-kubeadm/hardening/rbac.yaml
```

Paste:

```yaml
# Role: read-only access to key resources in the devops-launchboard namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: launchboard-developer-readonly
  namespace: devops-launchboard
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "services", "configmaps", "events"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "watch"]
---
# RoleBinding: grant the role to a user named "developer"
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: launchboard-developer-readonly-binding
  namespace: devops-launchboard
subjects:
  - kind: User
    name: developer
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: launchboard-developer-readonly
  apiGroup: rbac.authorization.k8s.io
```

Line explanation:

- `kind: Role` creates a namespaced role. A Role only applies within its namespace. A ClusterRole applies cluster-wide.
- `metadata.name: launchboard-developer-readonly` names the role.
- `rules` is the list of permissions.
- `apiGroups: [""]` refers to the core API group (the group that contains Pods, Services, ConfigMaps, etc.). An empty string means core API.
- `resources: ["pods", "pods/log", ...]` lists which resource types this rule applies to. `pods/log` is a sub-resource that allows reading Pod logs.
- `verbs: ["get", "list", "watch"]` are the allowed actions. `get` reads one resource, `list` reads many, `watch` streams changes. No `create`, `update`, `patch`, or `delete`.
- `apiGroups: ["apps"]` refers to the apps API group where Deployments live.
- `kind: RoleBinding` binds a Role to subjects (users, groups, or service accounts).
- `subjects[0].kind: User` means this binding applies to a Kubernetes user.
- `subjects[0].name: developer` is the username. When someone authenticates with a kubeconfig that identifies them as `developer`, they get this Role's permissions.
- `roleRef` points to the Role being granted.

Apply:

```bash
kubectl apply -f deployment/phase-6-kubeadm/hardening/rbac.yaml
```

Test permissions using kubectl impersonation:

```bash
kubectl auth can-i get pods -n devops-launchboard --as=developer
kubectl auth can-i delete pods -n devops-launchboard --as=developer
kubectl auth can-i create deployments -n devops-launchboard --as=developer
kubectl auth can-i get secrets -n devops-launchboard --as=developer
```

Expected:

```text
get pods:           yes
delete pods:        no
create deployments: no
get secrets:        no
```

Reference:

- Kubernetes RBAC: https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- Using RBAC authorization: https://kubernetes.io/docs/reference/access-authn-authz/rbac/#role-and-clusterrole

## Step 6: Pod Disruption Budgets

A PodDisruptionBudget (PDB) tells Kubernetes: "when you drain a node or perform voluntary disruptions, make sure at least N Pods of this Deployment are always available."

Without a PDB, Kubernetes might drain a node and take down all replicas of a Deployment simultaneously if they all happened to be on that node. With a PDB, Kubernetes waits until a new Pod is ready on another node before removing the old one.

```bash
vim deployment/phase-6-kubeadm/hardening/pdb.yaml
```

Paste:

```yaml
# Backend: always keep at least 1 Pod running during voluntary disruptions
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: launchboard-backend-pdb
  namespace: devops-launchboard
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: launchboard-backend
---
# Frontend: always keep at least 1 Pod running during voluntary disruptions
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: launchboard-frontend-pdb
  namespace: devops-launchboard
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: launchboard-frontend
```

Line explanation:

- `apiVersion: policy/v1` uses the policy API group. PodDisruptionBudget moved to `policy/v1` in Kubernetes 1.21.
- `kind: PodDisruptionBudget` creates a PDB object.
- `spec.minAvailable: 1` means at least 1 Pod matching the selector must be available at all times during voluntary disruptions. Voluntary disruptions include node drains, cluster upgrades, and cloud provider maintenance. Involuntary disruptions like hardware failures are not restricted by PDBs.
- `spec.selector.matchLabels` selects which Pods this PDB protects. The backend PDB protects backend Pods, the frontend PDB protects frontend Pods.
- With `minAvailable: 1` and `replicas: 2`, Kubernetes can take down at most 1 Pod at a time. If both worker nodes need maintenance, Kubernetes drains one, waits for the replacement Pod to start on another node, then drains the second.

Apply:

```bash
kubectl apply -f deployment/phase-6-kubeadm/hardening/pdb.yaml
```

Verify:

```bash
kubectl -n devops-launchboard get pdb
```

Expected:

```text
NAME                       MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS
launchboard-backend-pdb    1               N/A               1
launchboard-frontend-pdb   1               N/A               1
```

`ALLOWED DISRUPTIONS: 1` means exactly 1 Pod can be disrupted right now while 1 stays running.

Reference:

- Pod Disruption Budgets: https://kubernetes.io/docs/concepts/workloads/pods/disruptions/
- Configuring PDBs: https://kubernetes.io/docs/tasks/run-application/configure-pdb/

## Step 7: Verify The Full Production Setup

```bash
# All nodes ready
kubectl get nodes

# All Pods healthy
kubectl -n devops-launchboard get pods -o wide

# Resource usage within quota
kubectl -n devops-launchboard describe resourcequota launchboard-quota

# Network policies active
kubectl -n devops-launchboard get networkpolicy

# PDBs protecting deployments
kubectl -n devops-launchboard get pdb

# HPA watching backend
kubectl -n devops-launchboard get hpa

# ArgoCD keeping cluster in sync
argocd app get launchboard

# App is reachable
curl -s http://YOUR_WORKER_1_PUBLIC_IP/health | jq
curl -s http://YOUR_WORKER_1_PUBLIC_IP/api/summary | jq
```

## Production Hardening Summary

What you now have in place:

```text
[x] Pod Security Standards    - Pods cannot run as root or use dangerous capabilities
[x] NetworkPolicy             - Pods can only communicate with who they need to
[x] ResourceQuota             - Namespace cannot consume unlimited cluster resources
[x] RBAC                      - Users get only the permissions they need
[x] Pod Disruption Budgets    - Node maintenance cannot take all replicas offline at once
[x] Resource requests/limits  - Every Pod has CPU and memory boundaries
[x] Non-root containers       - All containers run as non-root
[x] Readiness/liveness probes - Unhealthy Pods stop receiving traffic and are restarted
[x] Rolling updates           - New versions deploy without downtime
[x] ArgoCD GitOps             - All changes go through Git
[x] Metrics Server            - Resource usage is visible
[x] HPA                       - Backend scales automatically under load
```

---

# Full Production Checklist

```text
Scenario 1 - Kind
[ ] EC2 t3.small created with correct security group
[ ] Docker installed and ubuntu user added to docker group
[ ] kubectl installed
[ ] Kind installed
[ ] GitHub SSH key created and tested
[ ] Repository cloned
[ ] .dockerignore created at repo root
[ ] kind-config.yaml created
[ ] Dockerfile.backend created
[ ] Dockerfile.frontend created
[ ] nginx-frontend.conf created
[ ] All k8s manifests created
[ ] CORS_ORIGINS updated in configmap.yaml
[ ] Kind cluster created
[ ] Ingress Nginx Controller installed
[ ] Images built and loaded into Kind
[ ] Namespace created
[ ] Secret created with kubectl
[ ] Manifests applied with kubectl apply -k
[ ] PostgreSQL rollout successful
[ ] Migration Job completed
[ ] Backend rollout successful
[ ] Frontend rollout successful
[ ] App accessible on port 80
[ ] API returns data
[ ] Rollout and rollback tested

Scenario 2 - kubeadm Control Plane
[ ] EC2 t3.medium created
[ ] Swap disabled permanently
[ ] overlay and br_netfilter kernel modules loaded
[ ] Sysctl networking parameters set
[ ] containerd installed with SystemdCgroup=true
[ ] kubeadm, kubelet, kubectl installed and held
[ ] kubeadm init completed
[ ] kubeconfig configured for ubuntu user
[ ] Never-expiring join token generated and saved
[ ] Flannel CNI installed
[ ] Node shows Ready
[ ] kube-system Pods all Running
[ ] Control plane taint removed for single-node testing

Scenario 3 - Worker Nodes
[ ] 2 x EC2 t3.medium created for workers
[ ] Worker security group created
[ ] Control plane security group updated with worker IPs
[ ] Both workers: swap disabled, modules loaded, sysctl set
[ ] Both workers: containerd installed with SystemdCgroup=true
[ ] Both workers: kubeadm, kubelet, kubectl installed
[ ] Both workers joined with kubeadm join
[ ] All 3 nodes show Ready
[ ] Control plane taint re-applied
[ ] Worker nodes labeled

Scenario 4 - App on kubeadm
[ ] Project cloned on control plane
[ ] deployment/phase-6-kubeadm/k8s folder created
[ ] All manifests created with correct image names
[ ] CORS_ORIGINS set to worker IP and port 30080
[ ] Namespace created
[ ] Secret created
[ ] Manifests applied
[ ] Pods spread across both worker nodes
[ ] NodePort port 30080 allowed in worker security group
[ ] App accessible at http://WORKER_IP:30080

Scenario 5 - MetalLB and Ingress
[ ] MetalLB installed
[ ] IPAddressPool and L2Advertisement configured with worker private IP
[ ] Nginx Ingress Controller installed
[ ] Ingress Controller Service patched to LoadBalancer
[ ] MetalLB assigned external IP to Ingress Controller
[ ] ingress.yaml created and applied
[ ] kustomization.yaml updated
[ ] NodePort Service deleted
[ ] CORS_ORIGINS updated to port 80
[ ] Worker security group allows port 80
[ ] App accessible at http://WORKER_IP on port 80

Scenario 6 - HTTPS (Optional)
[ ] Domain pointing to worker IP
[ ] Cert-Manager installed
[ ] ClusterIssuer created for Let's Encrypt
[ ] ingress.yaml updated with TLS and cert-manager annotation
[ ] CORS_ORIGINS updated to https://
[ ] Certificate issued (READY=True)
[ ] App accessible at https://YOUR_DOMAIN
[ ] HTTP redirects to HTTPS

Scenario 7 - Metrics Server
[ ] Metrics Server installed
[ ] --kubelet-insecure-tls patch applied
[ ] kubectl top nodes works
[ ] kubectl top pods -n devops-launchboard works

Scenario 8 - HPA
[ ] hpa.yaml created
[ ] kustomization.yaml updated to include hpa.yaml
[ ] HPA applied and showing correct TARGETS
[ ] Load generator test run
[ ] Pods scaled up under load
[ ] Pods scaled down after load

Scenario 11 - ArgoCD
[ ] ArgoCD namespace and installation applied
[ ] ArgoCD server patched to NodePort
[ ] ArgoCD NodePort added to worker security group
[ ] ArgoCD CLI installed
[ ] ArgoCD app create command run
[ ] Application shows Synced and Healthy
[ ] GitOps test: replica count change pushed to Git
[ ] ArgoCD detected and applied change automatically
[ ] Admin password changed

Scenario 12 - Production Hardening
[ ] Hardening folder created
[ ] Pod Security Standards labels applied to namespace
[ ] Privileged Pod rejected by policy
[ ] NetworkPolicy manifests created and applied
[ ] kube-router installed for Flannel NetworkPolicy enforcement
[ ] App still works after NetworkPolicy
[ ] ResourceQuota created and applied
[ ] RBAC role and binding created
[ ] developer user permissions tested with kubectl auth can-i
[ ] PodDisruptionBudgets created and applied
[ ] All verification commands pass
```

---

# Cleanup

## Delete Application Resources

```bash
kubectl delete namespace devops-launchboard
```

## Delete ArgoCD

```bash
kubectl delete namespace argocd
```

## Delete Metrics Server

```bash
kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

## Delete Ingress Nginx

```bash
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/baremetal/deploy.yaml
```

## Delete MetalLB

```bash
kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
```

## Terminate EC2 Instances

From the AWS Console, terminate:

```text
devops-launchboard-phase-6-s1   (Kind scenario)
devops-launchboard-k8s-control  (kubeadm control plane)
devops-launchboard-k8s-worker-1
devops-launchboard-k8s-worker-2
```

Also:

- Delete unused EBS volumes.
- Release unused Elastic IPs.
- Check AWS Billing to confirm no unexpected charges.

---

# Reference Documentation

| Topic | Link |
| --- | --- |
| Kubernetes overview | https://kubernetes.io/docs/concepts/overview/ |
| Kubernetes components | https://kubernetes.io/docs/concepts/overview/components/ |
| kubeadm install | https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/ |
| kubeadm init | https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/ |
| kubectl install | https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/ |
| kubectl reference | https://kubernetes.io/docs/reference/kubectl/ |
| Kind quick start | https://kind.sigs.k8s.io/docs/user/quick-start/ |
| Kind ingress | https://kind.sigs.k8s.io/docs/user/ingress/ |
| Flannel | https://github.com/flannel-io/flannel |
| containerd | https://containerd.io/docs/getting-started/ |
| MetalLB | https://metallb.universe.tf/ |
| Nginx Ingress | https://kubernetes.github.io/ingress-nginx/ |
| Cert-Manager | https://cert-manager.io/docs/ |
| Let's Encrypt | https://letsencrypt.org/how-it-works/ |
| Metrics Server | https://github.com/kubernetes-sigs/metrics-server |
| ArgoCD | https://argo-cd.readthedocs.io/en/stable/ |
| Namespaces | https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/ |
| ConfigMaps | https://kubernetes.io/docs/concepts/configuration/configmap/ |
| Secrets | https://kubernetes.io/docs/concepts/configuration/secret/ |
| Deployments | https://kubernetes.io/docs/concepts/workloads/controllers/deployment/ |
| Services | https://kubernetes.io/docs/concepts/services-networking/service/ |
| Jobs | https://kubernetes.io/docs/concepts/workloads/controllers/job/ |
| Persistent Volumes | https://kubernetes.io/docs/concepts/storage/persistent-volumes/ |
| Ingress | https://kubernetes.io/docs/concepts/services-networking/ingress/ |
| HPA | https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/ |
| NetworkPolicy | https://kubernetes.io/docs/concepts/services-networking/network-policies/ |
| Pod Security Standards | https://kubernetes.io/docs/concepts/security/pod-security-standards/ |
| RBAC | https://kubernetes.io/docs/reference/access-authn-authz/rbac/ |
| PodDisruptionBudget | https://kubernetes.io/docs/tasks/run-application/configure-pdb/ |
| ResourceQuota | https://kubernetes.io/docs/concepts/policy/resource-quotas/ |
| Kustomize | https://kustomize.io/ |
| Probes | https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/ |
| Security context | https://kubernetes.io/docs/tasks/configure-pod-container/security-context/ |
| Resource management | https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/ |
| Taints and tolerations | https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/ |
| Docker Engine install | https://docs.docker.com/engine/install/ubuntu/ |
| Dockerfile reference | https://docs.docker.com/reference/dockerfile/ |
| Multi-stage builds | https://docs.docker.com/build/building/multi-stage/ |

---

# What To Do Next

Move to:

```text
Phase 7: CI/CD
```

Phase 6 covered Kubernetes from the ground up: local clusters with Kind, real clusters with kubeadm, multi-node setups, traffic routing with MetalLB and Ingress, HTTPS with cert-manager, resource visibility with Metrics Server, autoscaling with HPA, GitOps with ArgoCD, and production-level security hardening. Phase 7 covers how to automate the image build and deployment pipeline so changes in code flow all the way to the cluster without manual steps.
