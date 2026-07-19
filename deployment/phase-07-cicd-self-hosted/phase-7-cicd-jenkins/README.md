# Phase 7: CI/CD Automation — Jenkins From Scratch (Amazon EKS)

## Fresh Start Assumption

This phase starts from a clean Ubuntu EC2 server, a clean AWS account, and a GitHub repository.

You do not need to complete any previous phase before using this guide. This guide does not reuse the main Phase 7 (GitHub Actions) server, cluster, or files, and it does not reuse the sibling `phase-7-cicd-EKS` guide's cluster either — it builds its own Jenkins server, its own EKS cluster, its own ECR repositories, and its own copies of every file, end to end.

This guide assumes:

- You have an AWS account with permissions to create EKS, EC2, IAM, VPC, ALB, EBS, ECR, and NAT Gateway resources.
- You have a fresh AWS EC2 server for Jenkins.
- Docker, AWS CLI, kubectl, eksctl, Helm, and Jenkins are not installed yet.
- No EKS cluster or ECR repository exists yet.
- The repository is not cloned yet.
- You will create files with `vim`.
- You will type commands manually.
- You will not use shell scripts.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What You Will Build

This phase builds a self-hosted CI/CD pipeline using Jenkins that deploys to a real Amazon EKS cluster instead of a local Kind cluster:

- Installs Jenkins directly on an EC2 server (the most common way teams run a self-hosted CI server).
- Creates an Amazon EKS cluster and ECR repositories once, ahead of time, the same way a real platform team provisions infrastructure before wiring up a pipeline to it.
- Creates a Jenkins Pipeline job that checks out the repository, lints and smoke-tests the backend, lints and builds the frontend, builds Docker images tagged with the Git commit SHA, pushes them to Amazon ECR, and deploys to the EKS cluster with `kubectl`.
- Tags every build with the Git commit SHA so rollback is real, not cosmetic — the same lesson taught in the main Phase 7 guide, now reproduced with Jenkins and EKS instead of GitHub Actions and Kind.
- Automatically discovers the AWS Application Load Balancer's DNS name after every deploy and updates the backend's CORS setting to match it, so the app works in a browser without a second manual step.
- Adds a second Jenkins Pipeline job for one-click rollback.
- Polls GitHub for new commits on a schedule, so pushing code triggers a new build automatically without exposing the server to the internet.

## CI/CD Architecture

```text
Developer pushes to GitHub main
  |
  v
Jenkins polls GitHub on a schedule (no inbound traffic needed)
  |
  v
Jenkins server (runs directly on your EC2 instance)
  |
  | 1. Checkout
  | 2. Backend lint + smoke test
  | 3. Frontend lint + build
  | 4. Update EKS kubeconfig (IAM credentials, no static kubeconfig file)
  | 5. Docker login to ECR
  | 6. Docker build (commit SHA tag)
  | 7. Docker push to ECR
  | 8. Apply Kubernetes manifests to EKS
  | 9. Wait for rollout
  | 10. Discover ALB DNS name, fix CORS, restart backend
  | 11. Verify with curl against the ALB
  |
  v
Amazon EKS cluster (separate AWS-managed infrastructure, not this EC2)
  |
  v
DevOps LaunchBoard app, reachable through its own AWS Application Load Balancer
```

The Jenkins EC2 instance is purely a CI controller in this version of the lab. Unlike the Kind-based guide, the live application never runs on the Jenkins box itself and is never reached through the Jenkins box's own IP address — it runs on EKS worker nodes and is reached through an AWS Application Load Balancer that EKS provisions on its own.

## When To Use This Architecture

Jenkins is where a large share of real-world CI still happens — knowing it is a direct employment filter for a specific set of companies:

- **Regulated and security-conscious enterprises.** Banks, insurers, telcos, healthcare, defense: code and build artifacts often may not leave company infrastructure, ruling out hosted CI. Self-hosted Jenkins (or GitLab CE) on their own machines is the standard answer, and those industries hire continuously.
- **The installed base.** Jenkins has been the default CI for fifteen years; the world is full of business-critical Jenkins servers with hundreds of jobs. "Maintain, harden, and eventually migrate our Jenkins" is a real job description, and it pays well precisely because fewer juniors learn it now.
- **Pipelines that outgrow hosted CI.** Custom build hardware (GPU, mobile device farms), exotic plugins, multi-hour builds, fine-grained credential control — self-hosted CI keeps these feasible.
- **The transferable core.** Declarative pipelines, credential stores, agents, polling vs webhooks, parameterized rollback jobs — the concepts here map one-to-one onto every other CI system. Learn them on Jenkins and GitLab CI/CircleCI/Actions all read like dialects.

Choose something else when: the team is small, on GitHub, with standard build needs — hosted Actions (the parent lab) wins on maintenance cost; nobody should run a CI server they do not need.

## Cost Warning

| Resource                  | Approximate Cost                              |
| ------------------------- | --------------------------------------------- |
| EKS control plane         | ~$0.10/hour (~$73/month)                      |
| 2 × t3.medium workers     | ~$0.08/hour (~$60/month)                      |
| NAT Gateway               | ~$0.045/hour (~$33/month)                     |
| Application Load Balancer | ~$0.02/hour (~$16/month)                      |
| EBS volumes               | ~$0.01/hour                                   |
| Jenkins EC2 (t3.small)    | ~$0.02/hour (~$15/month)                      |
| Amazon ECR storage        | First 500 MB/month free, then ~$0.10/GB-month |

Running this lab for a few hours costs a few dollars. Running everything 24/7 for a month costs roughly $200, dominated by the NAT Gateway and EKS control plane, neither of which existed in the Kind-backed version of this guide. Delete the EKS cluster and Jenkins EC2 after each lab session — see Cleanup at the end of this guide.

Create an AWS Budget before starting: AWS Console > Billing > Budgets > Create budget.

## Recommended AWS Setup

| Item            | Recommended Value                       |
| --------------- | --------------------------------------- |
| EC2 Name        | `devops-launchboard-phase-7-jenkins`    |
| AMI             | Ubuntu Server 24.04 LTS                 |
| Instance Type   | `t3.small`                              |
| Storage         | 30 GB gp3                               |
| Key Pair        | `devops-launchboard-key`                |
| Security Group  | `devops-launchboard-phase-7-jenkins-sg` |
| SSH Port        | `22`, your IP only                      |
| Jenkins UI Port | `8080`, your IP only                    |

Do not open:

```text
80
443
8000
5432
6443
```

No port needs to be open to the public internet on this server at all. The live application is served by EKS through its own AWS Application Load Balancer, not through this EC2 instance, so this box never needs an inbound HTTP/HTTPS rule the way the Kind-backed guide did.

Why `t3.small` instead of the `t3.medium` used in the Kind-backed Jenkins guide: this server no longer runs a local Kubernetes cluster (Kind) or the application's own Pods. It only runs Jenkins itself, plus short-lived `docker build` steps during each pipeline run. That is a meaningfully smaller footprint than Jenkins plus a full local cluster, so `t3.small` (2 GB RAM) is enough — the same size used for the AWS-CLI-driven workstations in Phase 8 and the sibling `phase-7-cicd-EKS` guide.

## Files Included In This Phase

```text
deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/
+-- cluster/
|   +-- eksctl-cluster.yaml               (EKS cluster definition)
+-- ecr/
|   +-- lifecycle-policy.json             (ECR image cleanup rules)
+-- Dockerfile.backend
+-- Dockerfile.frontend
+-- nginx-frontend.conf
+-- Jenkinsfile                          (deploy pipeline)
+-- Jenkinsfile.rollback                 (rollback pipeline)
+-- k8s/
|   +-- namespace.yaml
|   +-- storageclass.yaml
|   +-- configmap.yaml
|   +-- secret.example.yaml
|   +-- pvc.yaml
|   +-- launchboard-postgres-deployment.yaml
|   +-- launchboard-postgres-service.yaml
|   +-- launchboard-migration-job.yaml
|   +-- launchboard-backend-deployment.yaml
|   +-- launchboard-backend-service.yaml
|   +-- launchboard-frontend-deployment.yaml
|   +-- launchboard-frontend-service.yaml
|   +-- ingress.yaml
|   +-- hpa.yaml
|   +-- kustomization.yaml
+-- README.md
```

## Step 1: Prepare AWS IAM User

Use an IAM principal that can create:

```text
EKS clusters
EC2 instances
VPC resources (subnets, route tables, internet gateways, NAT gateways)
IAM roles, policies, and users
ECR repositories
CloudWatch log groups
Elastic Load Balancers
EBS volumes
CloudFormation stacks (eksctl uses CloudFormation internally)
```

If you are using the root account for a student lab, that works but is not recommended for production. For a dedicated IAM user, attach the `AdministratorAccess` policy for the lab, and scope it down later when you understand which permissions are needed.

Why this step exists:

EKS creates many AWS resources across multiple services. Missing IAM permissions are one of the most common reasons EKS setup fails. This same IAM user's access keys are what you configure on the EC2 server in Step 6 to run `eksctl`, `aws ecr`, and `helm` commands by hand. A second, narrower-scoped IAM user is created later in Step 19 specifically for Jenkins' own pipeline runs — that one does not need `AdministratorAccess`.

Reference:

- EKS IAM: https://docs.aws.amazon.com/eks/latest/userguide/security-iam.html

## Step 2: Create EC2 Server

Run this step from AWS Console.

Create one EC2 instance:

| Field         | Value                                |
| ------------- | ------------------------------------ |
| Name          | `devops-launchboard-phase-7-jenkins` |
| AMI           | Ubuntu Server 24.04 LTS              |
| Instance Type | `t3.small`                           |
| Storage       | 30 GB gp3                            |
| Public IP     | Enabled                              |

Security group inbound rules:

| Type                    | Port | Source  |
| ----------------------- | ---: | ------- |
| SSH                     |   22 | Your IP |
| Custom TCP (Jenkins UI) | 8080 | Your IP |

Why this step exists:

This single server runs Docker, AWS CLI, eksctl, kubectl, Helm, and Jenkins itself. Jenkins schedules and executes the pipeline directly on this machine, the same way a small company would run a first self-hosted Jenkins controller before splitting build agents onto separate machines. The application itself does not run here — it runs on EKS worker nodes created in Step 14.

Reference:

- AWS EC2 docs: https://docs.aws.amazon.com/ec2/
- EC2 security groups: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html

## Step 3: SSH Into EC2

Run from your local machine:

```bash
chmod 400 devops-launchboard-key.pem
ssh -i devops-launchboard-key.pem ubuntu@YOUR_EC2_PUBLIC_IP
```

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

## Step 4: Update Server And Install Base Tools

Run:

```bash
cd ~
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl wget vim unzip jq ca-certificates gnupg lsb-release python3-venv python3-pip
```

Install Node.js 22 using the NodeSource apt repository:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
sudo apt update
sudo apt install -y nodejs
```

Verify:

```bash
node --version
npm --version
```

Why this step exists:

Most of the first package list is the same baseline Linux tools every other phase installs: cloning the repository, editing files, downloading binaries, and reading JSON output. `python3-venv` and `python3-pip` are needed because the Jenkinsfile's "Backend Checks" stage runs `python3 -m venv .venv` directly on this EC2 instance (not inside a container) — Ubuntu ships a `python3` binary without the `venv` module by default, and `python3 -m venv` fails with `ensurepip is not available` if this package is missing.

Node.js and npm are needed for the same reason, one stage later: the Jenkinsfile's "Frontend Checks" stage runs `npm ci`, `npm run lint`, and `npm run build` directly on this host. Ubuntu's own default repositories only carry Node.js 18, which is too old for this project's frontend tooling, so the NodeSource repository is added the same way Phase 2 (bare metal) does it, to get Node.js 22 and the matching `npm` binary instead.

Reference:

- NodeSource distributions: https://github.com/nodesource/distributions

## Step 5: Install Docker

Run:

```bash
cd ~
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

Log out and SSH back in so the docker group membership takes effect:

```bash
exit
ssh -i devops-launchboard-key.pem ubuntu@YOUR_EC2_PUBLIC_IP
```

Verify:

```bash
docker --version
docker info
```

Why this step exists:

Docker builds the backend and frontend images that get pushed to ECR. Both the `ubuntu` user (for manual commands) and, later, the `jenkins` user (for pipeline runs) need to run Docker commands.

Reference:

- Docker Engine Ubuntu install: https://docs.docker.com/engine/install/ubuntu/

## Step 6: Configure AWS CLI

Install the AWS CLI:

```bash
cd ~
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip
sudo ./aws/install
rm -rf awscliv2.zip awscli
```

Configure it with the IAM user's access key from Step 1:

```bash
aws configure
```

Enter your Access Key ID, Secret Access Key, region (e.g. `us-east-1`), and `json` for output format.

Set shell variables you will reuse throughout the rest of this guide:

```bash
export AWS_REGION=YOUR_AWS_REGION
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export CLUSTER_NAME=devops-launchboard-phase-7-jenkins
echo "Account: $ACCOUNT_ID  Region: $AWS_REGION  Cluster: $CLUSTER_NAME"
```

Replace `YOUR_AWS_REGION` with your region (e.g. `us-east-1`).

Verify:

```bash
aws --version
aws sts get-caller-identity
```

Why this step exists:

Every AWS operation in the rest of this guide — creating the EKS cluster, creating ECR repositories, mapping IAM identities into the cluster's RBAC, installing the Load Balancer Controller — goes through this AWS CLI configuration, run as the `ubuntu` user. The `export` lines are shell variables, not persistent configuration: if you disconnect and reconnect over SSH, you must re-run them in the new session.

Reference:

- AWS CLI install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

## Step 7: Install kubectl, eksctl, And Helm

Install kubectl:

```bash
cd ~
curl -LO "https://dl.k8s.io/release/stable.txt"
KUBECTL_VERSION=$(cat stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl
rm stable.txt
```

Install eksctl:

```bash
cd ~
curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz
sudo mv eksctl /usr/local/bin/eksctl
```

Install Helm:

```bash
cd ~
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Verify:

```bash
kubectl version --client
eksctl version
helm version
```

Why this step exists:

`eksctl` creates and manages the EKS cluster, `kubectl` is how both you and Jenkins talk to that cluster once it exists, and `helm` installs the AWS Load Balancer Controller in Step 17. Installing all three to `/usr/local/bin` puts them on the PATH for every user on this machine, including the `jenkins` system user created in Step 9.

Reference:

- Install kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
- eksctl: https://eksctl.io/

## Step 8: Create GitHub SSH Key And Clone The Repository

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-7-jenkins" -f ~/.ssh/devops_launchboard_github_key
cat ~/.ssh/devops_launchboard_github_key.pub
```

Add the public key to GitHub:

```text
GitHub repository
Settings
Deploy keys
Add deploy key
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

Secure permissions:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/config
chmod 600 ~/.ssh/devops_launchboard_github_key
chmod 644 ~/.ssh/devops_launchboard_github_key.pub
```

Test:

```bash
ssh -T git@github.com
```

Clone:

```bash
sudo mkdir -p /opt/devops-launchboard
sudo chown -R ubuntu:ubuntu /opt/devops-launchboard
cd /opt/devops-launchboard
git clone git@github.com:ashraful2430/N-tier-application.git app-source
cd app-source
git branch --show-current
```

Expected:

```text
main
```

Why this step exists:

You need a local copy of the application source to create the Phase 7 Jenkins files and to build images. This key is only used by your own `ubuntu` user for this initial clone and manual edits; Jenkins gets its own separate deploy key in Step 23, which is a better security practice than sharing one key between a human user and an automated service.

Reference:

- GitHub deploy keys: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys

## Step 9: Install Java And Jenkins

Jenkins is a Java application. Install a current LTS Java runtime first, then add Jenkins' own apt repository.

```bash
cd ~
sudo apt update
sudo apt install -y fontconfig openjdk-21-jre
java -version
```

Add the Jenkins repository and install:

```bash
sudo mkdir -p /etc/apt/keyrings
sudo curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key \
  -o /etc/apt/keyrings/jenkins-keyring.asc

echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

sudo apt update
sudo apt install -y jenkins
```

Jenkins periodically rotates its package signing key, and the key filename is versioned by year (`jenkins.io-2026.key` at the time of writing). If `sudo apt update` reports `NO_PUBKEY` with a key ID that does not match what you just downloaded, the key has rotated again since this guide was written — check the current filename in the official install command at the Reference link below and substitute it here.

Start and enable Jenkins:

```bash
sudo systemctl enable jenkins
sudo systemctl start jenkins
sudo systemctl status jenkins --no-pager
```

Expected: `active (running)`.

Why this step exists:

Jenkins is not a container or a managed service in this guide — it installs as a system service (`jenkins.service`) running under its own dedicated Linux user, also named `jenkins`. That user, not `ubuntu`, is who actually executes every pipeline stage, which is why later steps configure permissions and credentials specifically for the `jenkins` user.

Reference:

- Jenkins Debian/Ubuntu install: https://www.jenkins.io/doc/book/installing/linux/#debianubuntu

## Step 10: Open Jenkins And Finish The Setup Wizard

Get the initial administrator password:

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Open in your browser:

```text
http://YOUR_EC2_PUBLIC_IP:8080
```

Paste the password from the command above into the "Unlock Jenkins" screen.

On the next screen, choose **Install suggested plugins**. This installs the Git plugin, Pipeline plugin, and other commonly needed plugins automatically; nothing further needs to be installed manually for this guide.

Create your first admin user when prompted (this replaces the temporary password going forward).

Confirm the Jenkins URL on the final screen matches `http://YOUR_EC2_PUBLIC_IP:8080/` and click **Start using Jenkins**.

Why this step exists:

The initial admin password file proves that whoever is unlocking Jenkins already has root access to the server it runs on — Jenkins will not let you create an account over the network without it. The suggested plugin set already includes everything this guide's Jenkinsfiles need (`git`, `workflow-aggregator` for Pipeline, `credentials-binding`); no extra plugin installation step is required, including for the AWS credential used in Step 19, which only needs Jenkins' built-in "Username with password" credential type.

## Step 11: Allow The Jenkins User To Run Docker

The `jenkins` system user (not `ubuntu`) executes every pipeline stage, so it needs the same Docker access that you set up for `ubuntu` in Step 5.

Add `jenkins` to the `docker` group:

```bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

Why `systemctl restart` is required: group membership is only read when a process starts. Jenkins was already running before this command, so its existing process is still in the old group list; restarting Jenkins starts it fresh with `docker` included.

Verify the `jenkins` user can reach Docker:

```bash
sudo -u jenkins docker ps
```

Expected: an empty container list (`CONTAINER ID   IMAGE   COMMAND ...` with no rows), not a permission error.

Why no AWS credential file step is needed here: unlike the Docker group, AWS access does not need a system-user-specific setup step. The Jenkinsfile in Step 20 reads AWS credentials from a Jenkins credential (created in Step 19) and exports them as `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` shell environment variables for the duration of each pipeline run. The `jenkins` Linux user never needs its own `~/.aws/credentials` file, and the EKS kubeconfig that `aws eks update-kubeconfig` writes to `/var/lib/jenkins/.kube/config` is created automatically the first time the pipeline runs that command — there is nothing to copy or chown manually.

## Step 12: Create Phase Folders And Root `.dockerignore`

Run:

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/cluster
mkdir -p deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/ecr
mkdir -p deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s
```

Create the root `.dockerignore` (shared by every Docker build in this repository, not specific to this phase):

```bash
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
deployment/phase-04-docker-compose/.env
```

Why this step exists:

Docker only reads `.dockerignore` from the build context root, and the build context in this phase is the repository root (every `docker build` command ends with a final `.`). Skipping this file would let Docker copy local virtual environments, `node_modules`, and cache folders into the build context, slowing builds and bloating images.

## Step 13: Create Dockerfiles And Nginx Config

### Dockerfile.backend

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/Dockerfile.backend
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
    && pip install --no-cache-dir .

FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="/opt/venv/bin:${PATH}"
ENV APP_ENV=production

RUN groupadd --system --gid 10001 app \
    && useradd --system \
       --uid 10001 \
       --gid 10001 \
       --home-dir /app \
       --shell /usr/sbin/nologin app

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

- `FROM python:3.12-slim AS builder` starts the first stage of a multi-stage build; the builder stage is not included in the final image.
- `ENV PYTHONDONTWRITEBYTECODE=1` and `ENV PYTHONUNBUFFERED=1` keep the image clean of `.pyc` files and make logs appear immediately.
- `ENV VIRTUAL_ENV=/opt/venv` and `ENV PATH="/opt/venv/bin:${PATH}"` create and prioritize a virtual environment at a known path so it can be copied between stages.
- `COPY backend/pyproject.toml backend/alembic.ini ./` copies dependency definitions before source code, a Docker layer-caching trick: unchanged dependencies mean a cached, faster rebuild.
- `RUN pip install --no-cache-dir .` installs the application and its base dependencies. Alembic is a base dependency (not a dev-only extra), so this single install is enough for the migration Job too.
- `groupadd --system --gid 10001 app` / `useradd --system --uid 10001 --gid 10001 ...` create a non-login service user with an explicit, pinned numeric UID/GID rather than letting the system auto-assign one. A name-only `USER app` produces a non-numeric user that Kubernetes cannot verify against `runAsNonRoot`; pinning a fixed UID/GID keeps the Dockerfile and the Kubernetes `securityContext` (in Step 18) deterministic and in sync.
- `COPY --from=builder /opt/venv /opt/venv` and `COPY --from=builder /app /app` bring only the installed dependencies and app code into the clean runtime stage — no build tools, no pip cache.
- `RUN chown -R app:app /app /opt/venv` gives the non-root user ownership of its own files.
- `USER app` switches to the non-root user for the rest of the image.
- `HEALTHCHECK` polls `/health` every 30 seconds so Docker itself can report container health.
- `CMD [...]` starts Uvicorn listening on all interfaces. `--proxy-headers` makes FastAPI trust the `X-Forwarded-*` headers added by the AWS Application Load Balancer in front of it.

### Dockerfile.frontend

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/Dockerfile.frontend
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

COPY deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/nginx-frontend.conf /etc/nginx/conf.d/default.conf
COPY --from=builder --chown=101:101 /app/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

Line explanation:

- `FROM node:22-alpine AS builder` uses a minimal Node.js image only to compile the React app; Node.js does not appear in the final image.
- `ARG VITE_API_URL=""` with `ENV VITE_API_URL=${VITE_API_URL}` lets the build embed an API base URL at build time. Left empty, the frontend uses relative `/api` paths, which is what you want here because Nginx proxies those paths.
- `COPY frontend/package*.json ./` followed by `RUN npm ci` is the same layer-caching pattern as the backend, with `npm ci` installing exact versions from `package-lock.json` for reproducible builds.
- `FROM nginxinc/nginx-unprivileged:1.27-alpine` is the official Nginx image designed to run as a non-root user on port 8080.
- `COPY deployment/.../nginx-frontend.conf ...` installs the custom config from this phase's own folder.
- `COPY --from=builder --chown=101:101 /app/dist /usr/share/nginx/html` copies the compiled app into the web root, owned by UID/GID 101, the nginx user baked into the unprivileged image.
- `CMD ["nginx", "-g", "daemon off;"]` keeps Nginx in the foreground so the container stays alive.

### nginx-frontend.conf

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/nginx-frontend.conf
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

- `listen 8080` matches the unprivileged image's non-root port.
- `location = /healthz` returns a plain `200 ok` without hitting the backend — this is what the Kubernetes probes and the ALB's own health check (Step 18) check.
- `location /api/`, `location = /health`, and `location = /ready` proxy those paths to `http://launchboard-backend:8000/...`, the backend's Kubernetes Service DNS name.
- `location / { try_files $uri $uri/ /index.html; }` falls back to `index.html` for any unmatched path, which is required for React Router to handle direct navigation to client-side routes.

Reference:

- Dockerfile reference: https://docs.docker.com/reference/dockerfile/
- Nginx unprivileged image: https://hub.docker.com/r/nginxinc/nginx-unprivileged

## Step 14: Create The EKS Cluster

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/cluster/eksctl-cluster.yaml
```

Paste:

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: devops-launchboard-phase-7-jenkins
  region: YOUR_AWS_REGION
  version: "1.34"

availabilityZones:
  - YOUR_AWS_REGIONa
  - YOUR_AWS_REGIONb

iam:
  withOIDC: true

vpc:
  clusterEndpoints:
    publicAccess: true
    privateAccess: true
  nat:
    gateway: Single

managedNodeGroups:
  - name: launchboard-workers
    instanceType: t3.medium
    desiredCapacity: 2
    minSize: 2
    maxSize: 4
    privateNetworking: true
    volumeSize: 30
    volumeType: gp3
    amiFamily: AmazonLinux2023
    labels:
      workload: launchboard
    tags:
      Project: devops-launchboard
      Environment: phase-7-jenkins
      Owner: student

cloudWatch:
  clusterLogging:
    enableTypes:
      - api
      - audit
      - authenticator
      - controllerManager
      - scheduler

addons:
  - name: aws-ebs-csi-driver
    wellKnownPolicies:
      ebsCSIController: true
```

Replace `YOUR_AWS_REGION` in three places. For example, `us-east-1`, `us-east-1a`, `us-east-1b`.

Line explanation:

- `metadata.name` is the cluster name. Using `devops-launchboard-phase-7-jenkins` instead of Phase 8's `devops-launchboard-phase-8` or the sibling `phase-7-cicd-EKS` guide's `devops-launchboard-phase-7` lets all three coexist in the same AWS account without colliding.
- `iam.withOIDC: true` creates an OpenID Connect (OIDC) provider for the cluster. This is the foundation of IAM Roles for Service Accounts (IRSA): it lets Kubernetes service accounts assume IAM roles without storing AWS credentials in the cluster. The EBS CSI driver and the Load Balancer Controller (Step 17) both need this to authenticate with AWS APIs.
- `vpc.nat.gateway: Single` creates one NAT Gateway instead of one per availability zone, trading some redundancy for a meaningfully lower hourly cost in a lab.
- `managedNodeGroups` defines the EC2 worker nodes that actually run your Pods. `desiredCapacity: 2` with `minSize: 2`/`maxSize: 4` gives the backend's HPA (Step 18) room to schedule extra Pods under load.
- `cloudWatch.clusterLogging.enableTypes` turns on control plane log streams (API server, audit, authenticator, controller manager, scheduler) so you can debug cluster-level problems in CloudWatch Logs.
- `addons.aws-ebs-csi-driver` with `wellKnownPolicies.ebsCSIController: true` tells eksctl to create an IAM role with the `AmazonEBSCSIDriverPolicy` and attach it to the EBS CSI driver's service account via IRSA. PostgreSQL's PVC (Step 18) needs this driver to provision a real EBS volume.

Create the cluster (20 to 40 minutes):

```bash
eksctl create cluster -f deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/cluster/eksctl-cluster.yaml
kubectl get nodes
```

Expected: 2 nodes `Ready`.

Why this step exists:

Unlike the Kind-backed Jenkins guide, where the pipeline itself created the local cluster on its very first run, an EKS cluster takes 20 to 40 minutes to provision and is not something you want a CI pipeline creating on every build. This is a one-time, manual infrastructure step, the same way Phase 8 treats EKS cluster creation as separate from application deployment.

Reference:

- eksctl: https://eksctl.io/
- Amazon EKS: https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html

## Step 15: Create ECR Repositories

ECR stores the Docker images Jenkins builds and pushes. Create the lifecycle policy first, then the repositories.

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/ecr/lifecycle-policy.json
```

Paste:

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep the latest 10 tagged images",
      "selection": {
        "tagStatus": "tagged",
        "tagPatternList": ["*"],
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": {
        "type": "expire"
      }
    },
    {
      "rulePriority": 2,
      "description": "Expire untagged images after 7 days",
      "selection": {
        "tagStatus": "untagged",
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": 7
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
```

Line explanation:

- `rulePriority: 1` is evaluated first. ECR evaluates rules in priority order and applies the first matching rule to each image.
- `tagStatus: "tagged"` with `tagPatternList: ["*"]` selects every tagged image, regardless of what the tag looks like. Every image Jenkins pushes here is already scoped to this one repository, so there is no need to filter by a tag prefix the way phases that share a repository across builds do.
- `countType: "imageCountMoreThan"` with `countNumber: 10` means: if there are more than 10 images matching this rule, expire the oldest ones until only 10 remain. This keeps your last 10 builds available for rollback.
- `rulePriority: 2` catches images that have no tag (failed or interrupted pushes). `sinceImagePushed` with `countNumber: 7` expires them after 7 days.
- `action.type: "expire"` deletes the matching images.

Create the repositories and attach the policy:

```bash
aws ecr create-repository --repository-name launchboard-backend \
  --region "$AWS_REGION" --image-scanning-configuration scanOnPush=true
aws ecr create-repository --repository-name launchboard-frontend \
  --region "$AWS_REGION" --image-scanning-configuration scanOnPush=true

aws ecr put-lifecycle-policy --repository-name launchboard-backend \
  --region "$AWS_REGION" \
  --lifecycle-policy-text file://deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/ecr/lifecycle-policy.json
aws ecr put-lifecycle-policy --repository-name launchboard-frontend \
  --region "$AWS_REGION" \
  --lifecycle-policy-text file://deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/ecr/lifecycle-policy.json
```

Command explanation:

- `aws ecr create-repository --image-scanning-configuration scanOnPush=true` creates each repository and turns on automatic vulnerability scanning every time an image is pushed.
- `aws ecr put-lifecycle-policy --lifecycle-policy-text file://...` attaches the JSON policy you just wrote to each repository.

Verify:

```bash
aws ecr describe-repositories --region "$AWS_REGION" \
  --query "repositories[].repositoryName"
```

Expected:

```text
[
    "launchboard-backend",
    "launchboard-frontend"
]
```

Reference:

- ECR lifecycle policies: https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html
- ECR image scanning: https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning.html

## Step 16: Map The Jenkins IAM User Into The Cluster's RBAC

IAM authentication and Kubernetes RBAC authorization are two separate systems. The IAM user that ran `eksctl create cluster` in Step 14 (your own `ubuntu`-session credentials from Step 6) automatically receives `system:masters` access to the new cluster. No other IAM principal can run `kubectl` against this cluster until you explicitly grant it access — including the dedicated Jenkins IAM user you are about to create in Step 19.

Create the Jenkins-specific IAM user now, before mapping it, so you have its ARN:

```bash
aws iam create-user --user-name devops-launchboard-jenkins
aws iam attach-user-policy --user-name devops-launchboard-jenkins \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
```

Create a minimal custom policy for the one EKS permission this user needs (just enough to resolve cluster connection details, not to act inside the cluster — that comes from the RBAC mapping below):

```bash
cat > /tmp/eks-describe-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["eks:DescribeCluster", "eks:ListClusters"],
      "Resource": "*"
    }
  ]
}
EOF

aws iam create-policy --policy-name devops-launchboard-jenkins-eks-describe \
  --policy-document file:///tmp/eks-describe-policy.json

aws iam attach-user-policy --user-name devops-launchboard-jenkins \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/devops-launchboard-jenkins-eks-describe"

aws iam create-access-key --user-name devops-launchboard-jenkins
```

Copy the `AccessKeyId` and `SecretAccessKey` from the output — you paste them into a Jenkins credential in Step 19. They are shown only once.

Now map this user's IAM identity into the cluster's Kubernetes RBAC:

```bash
eksctl create iamidentitymapping \
  --cluster "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --arn "arn:aws:iam::${ACCOUNT_ID}:user/devops-launchboard-jenkins" \
  --group system:masters \
  --username jenkins
```

Command explanation:

- `aws iam create-user` creates a dedicated identity for Jenkins, separate from the broad `AdministratorAccess` user you configured for yourself in Step 1 and Step 6. This is the same reasoning as the dedicated GitHub deploy key in Step 23: never give an automated service your own personal credentials.
- `AmazonEC2ContainerRegistryPowerUser` is an AWS-managed policy that grants push and pull access to ECR, which is all Jenkins needs there.
- The custom `devops-launchboard-jenkins-eks-describe` policy grants only `eks:DescribeCluster`/`eks:ListClusters` — the IAM-level permission `aws eks update-kubeconfig` needs to write a working kubeconfig file. It does **not** grant any permission to run `kubectl` commands inside the cluster; that authorization comes entirely from Kubernetes RBAC, which is a separate layer.
- `eksctl create iamidentitymapping --group system:masters` adds an entry to the cluster's `aws-auth` ConfigMap that says: "whoever authenticates as this IAM ARN should be treated as a member of the `system:masters` Kubernetes group," which can do anything in the cluster. `system:masters` is a lab simplification — production setups map CI identities to a narrower custom Role scoped to one namespace.

Production note:

Granting `system:masters` to a CI credential is broad. For production, create a Kubernetes `Role`/`ClusterRole` limited to the verbs and resources the deploy pipeline actually uses (`get`, `list`, `create`, `update`, `patch`, `delete` on Deployments, Services, Jobs, ConfigMaps, and Secrets in one namespace) and bind the IAM identity mapping to that Role instead of to `system:masters`.

Reference:

- Managing IAM identities for your cluster: https://docs.aws.amazon.com/eks/latest/userguide/grant-k8s-access.html
- IAM and Kubernetes RBAC: https://docs.aws.amazon.com/eks/latest/userguide/cluster-auth.html

## Step 17: Install AWS Load Balancer Controller

```bash
cd ~
curl -o aws-load-balancer-controller-policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicyPhase7Jenkins \
  --policy-document file://aws-load-balancer-controller-policy.json

eksctl create iamserviceaccount \
  --cluster "$CLUSTER_NAME" \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicyPhase7Jenkins" \
  --approve \
  --region "$AWS_REGION"

helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

kubectl -n kube-system rollout status deployment/aws-load-balancer-controller
```

Command explanation:

- `curl -o aws-load-balancer-controller-policy.json ...` downloads the AWS-maintained IAM policy document listing every permission the controller needs to create and manage Application Load Balancers and Target Groups on your behalf.
- `aws iam create-policy` registers that policy in your account under a phase-specific name, so it does not collide with the same policy created by Phase 8 or the sibling `phase-7-cicd-EKS` guide.
- `eksctl create iamserviceaccount` creates three things: an IAM role with the specified policy, a Kubernetes ServiceAccount in `kube-system`, and a trust relationship between them via the cluster's OIDC provider (created by `iam.withOIDC: true` in Step 14). This is IRSA: the controller Pod gets temporary AWS credentials through this ServiceAccount, with no access keys stored in the cluster.
- `helm install aws-load-balancer-controller` deploys the controller. `--set serviceAccount.create=false` tells Helm not to create its own ServiceAccount because `eksctl` already created one with the IAM role attached.
- `kubectl rollout status` waits until the controller Deployment is ready before you move on — the Ingress resource you apply in Step 18 will not get an ALB provisioned until this controller is running and watching for Ingress objects with `ingressClassName: alb`.

Why this step exists:

Kubernetes does not know how to create an AWS Application Load Balancer on its own. This controller watches for Ingress resources cluster-wide and translates them into real ALBs, Target Groups, and listener rules through the AWS API. It replaces the role the Nginx Ingress Controller played in the Kind-backed version of this guide.

Reference:

- AWS Load Balancer Controller: https://kubernetes-sigs.github.io/aws-load-balancer-controller/
- IAM roles for service accounts: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html

## Step 18: Create The Kubernetes Manifests

All manifests go inside `deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/`.

### namespace.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/namespace.yaml
```

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: devops-launchboard
  labels:
    app.kubernetes.io/name: devops-launchboard
    app.kubernetes.io/part-of: devops-launchboard
```

A Namespace is a logical boundary inside Kubernetes; every other resource below sets `namespace: devops-launchboard` to belong to it.

### storageclass.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/storageclass.yaml
```

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  type: gp3
  encrypted: "true"
```

- `provisioner: ebs.csi.aws.com` is the EBS CSI driver installed as a cluster addon in Step 14. Unlike Kind's built-in `local-path` provisioner, EKS has no default StorageClass, so this one must be created explicitly before the PostgreSQL PVC below can be satisfied.
- `volumeBindingMode: WaitForFirstConsumer` delays creating the actual EBS volume until a Pod that uses the PVC is scheduled, so the volume is created in the same availability zone as that Pod — EBS volumes cannot be attached across availability zones.
- `parameters.encrypted: "true"` encrypts the volume at rest using the AWS-managed EBS key, a baseline security practice with no extra setup cost.

### configmap.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/configmap.yaml
```

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: launchboard-config
  namespace: devops-launchboard
data:
  APP_NAME: DevOps LaunchBoard API
  APP_ENV: production
  CORS_ORIGINS: http://YOUR_ALB_DNS_NAME
  SEED_DEMO_DATA: "true"
  POSTGRES_DB: launchboard
  POSTGRES_USER: launchboard_user
```

This file is for reference only — the Jenkins pipeline actually creates this ConfigMap itself, first with a placeholder `CORS_ORIGINS` value and then again with the real ALB DNS name once the load balancer exists (Step 20 explains both stages). `CORS_ORIGINS` tells the FastAPI backend which browser origin may call the API; if it does not match the URL in your browser's address bar, the browser blocks the API responses.

### secret.example.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/secret.example.yaml
```

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

Example only, same reasoning as `configmap.yaml` — the Jenkins pipeline creates the real Secret from the `DB_PASSWORD` build parameter. Never commit real credentials into this file.

### pvc.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/pvc.yaml
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: launchboard-postgres-pvc
  namespace: devops-launchboard
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 5Gi
```

`storageClassName: gp3` points at the StorageClass created above, so the EBS CSI driver provisions a real, encrypted EBS volume for PostgreSQL. Unlike the Kind-backed version of this guide, this data survives deleting and recreating Pods — it is only lost if you delete the PVC itself or the whole EKS cluster.

### launchboard-postgres-deployment.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-postgres-deployment.yaml
```

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
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
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
              cpu: 500m
              memory: 512Mi
      volumes:
        - name: postgres-data
          persistentVolumeClaim:
            claimName: launchboard-postgres-pvc
```

- `strategy.type: Recreate` terminates the existing Pod before creating a new one, required for a single-writer database that holds an exclusive lock on its EBS volume — a `RollingUpdate` would try to attach the same `ReadWriteOnce` volume to two Pods at once and fail.
- `image: postgres:16-alpine` is the official upstream image — Jenkins never builds this one, only the backend and frontend images.
- `env` reads `POSTGRES_DB`/`POSTGRES_USER` from the ConfigMap and `POSTGRES_PASSWORD` from the Secret, exactly what the official Postgres image's entrypoint needs to create the database on first start.
- `PGDATA: /var/lib/postgresql/data/pgdata` points Postgres at a subdirectory of the mounted volume instead of the mount point itself. A freshly created EBS volume's filesystem always contains a `lost+found` directory at its root, and `initdb` refuses to initialize a data directory it considers "not empty" — it has no way to know `lost+found` is harmless filesystem bookkeeping rather than leftover database files. Pointing `PGDATA` at an empty subdirectory avoids the conflict entirely. This was never an issue in the Kind-backed version of this guide, because Kind's `local-path` provisioner bind-mounts an ordinary empty host folder with no `lost+found` in it.
- `readinessProbe`/`livenessProbe` run `pg_isready` inside the container rather than an HTTP check, since PostgreSQL is not an HTTP service.

### launchboard-postgres-service.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-postgres-service.yaml
```

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

`launchboard-db` becomes the DNS name other Pods use to reach PostgreSQL; the `DATABASE_URL` in the Secret depends on this exact name. `ClusterIP` keeps the database unreachable from outside the cluster — there is no path to it through the ALB at all.

### launchboard-migration-job.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-migration-job.yaml
```

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
          image: ECR_REGISTRY_PLACEHOLDER/launchboard-backend:IMAGE_TAG_PLACEHOLDER
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

- `image: ECR_REGISTRY_PLACEHOLDER/launchboard-backend:IMAGE_TAG_PLACEHOLDER` has two literal placeholder strings, not a real image reference. The Jenkins pipeline's "Stamp Image Tag Into Manifests" stage replaces `ECR_REGISTRY_PLACEHOLDER` with the real `ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com` registry hostname and `IMAGE_TAG_PLACEHOLDER` with the real Git commit SHA before applying this file — explained fully in Step 20. The Kind-backed version of this guide only needed to stamp the tag, because images stayed on the local machine; the EKS version also needs the full registry path, because EKS worker nodes pull images over the network from ECR.
- A Job runs its Pod once to completion and stops, unlike a Deployment. `restartPolicy: OnFailure` retries only on failure, not after success.
- The `until python -c "import socket; ..."` loop blocks until PostgreSQL accepts TCP connections, preventing `alembic upgrade head` from running before the database is ready.

### launchboard-backend-deployment.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-backend-deployment.yaml
```

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
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: backend
          image: ECR_REGISTRY_PLACEHOLDER/launchboard-backend:IMAGE_TAG_PLACEHOLDER
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
              cpu: 400m
              memory: 384Mi
```

- `image: ECR_REGISTRY_PLACEHOLDER/launchboard-backend:IMAGE_TAG_PLACEHOLDER` gets both placeholders stamped with the real registry and commit SHA by Jenkins, exactly like the migration Job above. This is the rollback mechanism in disguise: every build produces a uniquely tagged image pushed to ECR, so each deployment creates a new ReplicaSet referencing a specific version. `kubectl rollout undo` then has a real previous version to go back to — if the tag never changed, rollback would point at the same image bytes and do nothing.
- `runAsUser: 10001` and `runAsGroup: 10001` must match the `--uid 10001 --gid 10001` pinned in the Dockerfile, or the Pod fails with `CreateContainerConfigError` because the kubelet cannot verify a name-based `USER app` against `runAsNonRoot`.
- `rollingUpdate.maxSurge: 1` / `maxUnavailable: 0` updates Pods with zero downtime: Kubernetes never removes an old Pod until its replacement passes its readiness probe.
- `command` waits for PostgreSQL, then `exec`s into Uvicorn so it becomes PID 1 and receives termination signals directly, which is what makes rollouts and graceful shutdowns work correctly.

### launchboard-backend-service.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-backend-service.yaml
```

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

`launchboard-backend` becomes the DNS name the frontend's Nginx config proxies `/api`, `/health`, and `/ready` to.

### launchboard-frontend-deployment.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-frontend-deployment.yaml
```

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
          image: ECR_REGISTRY_PLACEHOLDER/launchboard-frontend:IMAGE_TAG_PLACEHOLDER
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
              cpu: 200m
              memory: 128Mi
```

`runAsUser: 101` matches the nginx user baked into the `nginxinc/nginx-unprivileged` image, the same pattern as the backend's pinned UID 10001 but for a different base image with a different built-in user. Like the backend Deployment, both placeholders in `image:` are stamped by Jenkins before this file is applied.

### launchboard-frontend-service.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-frontend-service.yaml
```

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

Port 80 is what the Ingress targets; port 8080 is the Pod's actual non-root port. The Service translates between the two.

### ingress.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/ingress.yaml
```

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: launchboard-ingress
  namespace: devops-launchboard
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
    alb.ingress.kubernetes.io/load-balancer-name: launchboard-phase-7-jenkins
spec:
  ingressClassName: alb
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

- `ingressClassName: alb` tells Kubernetes the AWS Load Balancer Controller installed in Step 17 — not an in-cluster Nginx Ingress Controller — should handle this resource.
- `alb.ingress.kubernetes.io/scheme: internet-facing` provisions a public ALB with a public DNS name, since this lab has no VPN or private network back to your laptop.
- `alb.ingress.kubernetes.io/target-type: ip` routes ALB traffic directly to Pod IP addresses rather than to EC2 instance ports, which works correctly with the AWS VPC CNI used by EKS.
- `alb.ingress.kubernetes.io/healthcheck-path: /healthz` points the ALB's own health check at the frontend's lightweight `/healthz` endpoint, the same one Kubernetes' own readiness probe uses.
- `alb.ingress.kubernetes.io/load-balancer-name` gives the ALB a predictable name in the EC2 Console instead of an autogenerated one, and keeps it distinct from the ALB created by the sibling `phase-7-cicd-EKS` guide or by Phase 8.
- All traffic routes to the frontend Service; the frontend's own Nginx then proxies API paths to the backend, exactly as it did behind the Nginx Ingress Controller in the Kind-backed version.

### hpa.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/hpa.yaml
```

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

- `scaleTargetRef` points the HPA at the `launchboard-backend` Deployment.
- `minReplicas: 2`/`maxReplicas: 5` lets the backend scale up under load and back down when idle, something a single-node Kind cluster could not meaningfully demonstrate but a multi-node EKS cluster can.
- `averageUtilization: 70` triggers scale-up once average CPU usage across backend Pods crosses 70% of the `resources.requests.cpu` value set on the Deployment.

This is new in the EKS-backed version of this guide — the Kind-backed version did not include an HPA, since a single-node local cluster has little room to demonstrate autoscaling.

### kustomization.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/kustomization.yaml
```

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - storageclass.yaml
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

Lists every manifest so a single `kubectl apply -k` applies them all in order. `secret.example.yaml` is deliberately not listed — the Jenkins pipeline creates the real Secret separately with `kubectl create secret`, the same reasoning every other phase in this repository follows for credentials. `configmap.yaml` is listed even though Jenkins also creates it directly with `kubectl create configmap`, because `kubectl apply -k` running against an already-existing, identically-named ConfigMap is a safe no-op — Kubernetes simply reconciles the two definitions instead of erroring out.

Reference:

- Kustomize documentation: https://kustomize.io/
- AWS Load Balancer Controller Ingress annotations: https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/annotations/

## Step 19: Add The AWS Credential To Jenkins

In Jenkins, add the access key from Step 16 as a credential:

```text
Jenkins
Manage Jenkins
Credentials
System
Global credentials (unrestricted)
Add Credentials
Kind: Username with password
Scope: Global
Username: paste the AccessKeyId from Step 16
Password: paste the SecretAccessKey from Step 16
ID: aws-jenkins-credentials
```

Click **Create**.

Why this step exists:

The Jenkinsfile in Step 20 references this credential by its ID (`aws-jenkins-credentials`) to populate `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` as shell environment variables for the duration of each pipeline run. Jenkins masks both values in the UI and in console logs, the same protection a GitHub Actions Secret gives you, and "Username with password" is a built-in Jenkins credential type — no extra plugin is required beyond what the suggested plugin set from Step 10 already installed.

Reference:

- Jenkins credentials: https://www.jenkins.io/doc/book/using/using-credentials/

## Step 20: Create The Jenkins Deploy Pipeline File

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/Jenkinsfile
```

Paste:

```groovy
pipeline {
  agent any

  parameters {
    password(name: 'DB_PASSWORD', defaultValue: 'CHANGE_ME_STRONG_PASSWORD', description: 'PostgreSQL password for this lab')
  }

  environment {
    AWS_CREDS = credentials('aws-jenkins-credentials')
    AWS_ACCESS_KEY_ID = "${AWS_CREDS_USR}"
    AWS_SECRET_ACCESS_KEY = "${AWS_CREDS_PSW}"
    AWS_REGION = 'YOUR_AWS_REGION'
    CLUSTER_NAME = 'devops-launchboard-phase-7-jenkins'
    NAMESPACE = 'devops-launchboard'
    DB_PASSWORD = "${params.DB_PASSWORD}"
  }

  stages {
    stage('Backend Checks') {
      steps {
        dir('backend') {
          sh 'python3 -m venv .venv'
          sh '. .venv/bin/activate && python -m pip install --upgrade pip'
          sh '. .venv/bin/activate && pip install -e ".[dev]"'
          sh '. .venv/bin/activate && ruff check .'
          sh '. .venv/bin/activate && python -c "from app.main import app; print(app.title)"'
        }
      }
    }

    stage('Frontend Checks') {
      steps {
        dir('frontend') {
          sh 'npm ci'
          sh 'npm run lint'
          sh 'npm run build'
        }
      }
    }

    stage('Set Image Tag') {
      steps {
        script {
          env.IMAGE_TAG = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
          env.ACCOUNT_ID = sh(script: 'aws sts get-caller-identity --query Account --output text', returnStdout: true).trim()
          env.ECR_REGISTRY = "${env.ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
        }
        echo "Image tag for this build: ${env.IMAGE_TAG}"
        echo "ECR registry: ${env.ECR_REGISTRY}"
      }
    }

    stage('Update Kubeconfig') {
      steps {
        sh '''
          aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"
          kubectl get nodes
        '''
      }
    }

    stage('Log In To ECR') {
      steps {
        sh '''
          aws ecr get-login-password --region "${AWS_REGION}" \
            | docker login --username AWS --password-stdin "${ECR_REGISTRY}"
        '''
      }
    }

    stage('Build Images') {
      steps {
        sh '''
          docker build -f deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/Dockerfile.backend \
            -t "${ECR_REGISTRY}/launchboard-backend:${IMAGE_TAG}" .
          docker build -f deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/Dockerfile.frontend \
            --build-arg VITE_API_URL= \
            -t "${ECR_REGISTRY}/launchboard-frontend:${IMAGE_TAG}" .
        '''
      }
    }

    stage('Push Images To ECR') {
      steps {
        sh '''
          docker push "${ECR_REGISTRY}/launchboard-backend:${IMAGE_TAG}"
          docker push "${ECR_REGISTRY}/launchboard-frontend:${IMAGE_TAG}"
        '''
      }
    }

    stage('Stamp Image Tag Into Manifests') {
      steps {
        sh '''
          sed -i "s|ECR_REGISTRY_PLACEHOLDER|${ECR_REGISTRY}|g; s|IMAGE_TAG_PLACEHOLDER|${IMAGE_TAG}|g" \
            deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-backend-deployment.yaml \
            deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-frontend-deployment.yaml \
            deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-migration-job.yaml
        '''
      }
    }

    stage('Deploy To EKS') {
      steps {
        sh 'kubectl apply -f deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/namespace.yaml'
        sh 'kubectl apply -f deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/storageclass.yaml'
        sh '''
          kubectl create configmap launchboard-config \
            --namespace "${NAMESPACE}" \
            --from-literal=APP_NAME="DevOps LaunchBoard API" \
            --from-literal=APP_ENV=production \
            --from-literal=CORS_ORIGINS="http://placeholder.invalid" \
            --from-literal=SEED_DEMO_DATA=true \
            --from-literal=POSTGRES_DB=launchboard \
            --from-literal=POSTGRES_USER=launchboard_user \
            --dry-run=client -o yaml | kubectl apply -f -
        '''
        sh '''
          kubectl create secret generic launchboard-secret \
            --namespace "${NAMESPACE}" \
            --from-literal=POSTGRES_PASSWORD="${DB_PASSWORD}" \
            --from-literal=DATABASE_URL="postgresql+asyncpg://launchboard_user:${DB_PASSWORD}@launchboard-db:5432/launchboard" \
            --dry-run=client -o yaml | kubectl apply -f -
        '''
        sh 'kubectl -n "${NAMESPACE}" delete job launchboard-migrate --ignore-not-found'
        sh 'kubectl apply -k deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s'
        sh 'kubectl -n "${NAMESPACE}" rollout status deployment/launchboard-db --timeout=180s'
        sh 'kubectl -n "${NAMESPACE}" wait --for=condition=complete job/launchboard-migrate --timeout=180s'
        sh 'kubectl -n "${NAMESPACE}" rollout status deployment/launchboard-backend --timeout=180s'
        sh 'kubectl -n "${NAMESPACE}" rollout status deployment/launchboard-frontend --timeout=180s'
      }
    }

    stage('Wait For ALB And Fix CORS') {
      steps {
        script {
          def albDns = ''
          for (int i = 0; i < 30; i++) {
            albDns = sh(
              script: "kubectl -n ${env.NAMESPACE} get ingress launchboard-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true",
              returnStdout: true
            ).trim()
            if (albDns) {
              break
            }
            echo "Waiting for ALB hostname... (${i + 1}/30)"
            sleep(10)
          }
          if (!albDns) {
            error 'ALB hostname did not appear within 5 minutes. Check the aws-load-balancer-controller logs.'
          }
          env.ALB_DNS = albDns
        }
        sh '''
          kubectl create configmap launchboard-config \
            --namespace "${NAMESPACE}" \
            --from-literal=APP_NAME="DevOps LaunchBoard API" \
            --from-literal=APP_ENV=production \
            --from-literal=CORS_ORIGINS="http://${ALB_DNS}" \
            --from-literal=SEED_DEMO_DATA=true \
            --from-literal=POSTGRES_DB=launchboard \
            --from-literal=POSTGRES_USER=launchboard_user \
            --dry-run=client -o yaml | kubectl apply -f -
          kubectl -n "${NAMESPACE}" rollout restart deployment/launchboard-backend
          kubectl -n "${NAMESPACE}" rollout status deployment/launchboard-backend --timeout=180s
        '''
      }
    }

    stage('Verify Application') {
      steps {
        sh '''
          curl -fsS "http://${ALB_DNS}/healthz"
          curl -fsS "http://${ALB_DNS}/health"
          curl -fsS "http://${ALB_DNS}/ready"
          curl -fsS "http://${ALB_DNS}/api/summary" | head -c 400
          echo ""
          echo "Deployment of ${IMAGE_TAG} verified at http://${ALB_DNS}"
        '''
      }
    }
  }

  post {
    always {
      sh '''
        git checkout -- deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-backend-deployment.yaml \
          deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-frontend-deployment.yaml \
          deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-migration-job.yaml || true
      '''
    }
  }
}
```

Replace `YOUR_AWS_REGION` on the `AWS_REGION` line with your real region before committing this file in Step 22.

Line explanation:

- `pipeline { agent any }` is a declarative Jenkins Pipeline. `agent any` runs every stage directly on the Jenkins controller itself — appropriate here because Docker, AWS CLI, eksctl, and kubectl are all installed on this one EC2 instance and there are no separate build agents.
- `parameters { password(...) }` makes this a parameterized build: the Jenkins UI shows a form with this field before each run. `password(...)` masks the value in the UI and in logs. There is no `PUBLIC_APP_URL` parameter in this version — the "Wait For ALB And Fix CORS" stage discovers the correct URL automatically on every run, removing a manual step the Kind-backed version needed.
- `AWS_CREDS = credentials('aws-jenkins-credentials')` binds the Jenkins credential created in Step 19. Jenkins automatically exposes it as two additional variables, `AWS_CREDS_USR` and `AWS_CREDS_PSW`, which the next two lines re-map to the exact environment variable names (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) that the AWS CLI looks for automatically.
- `CLUSTER_NAME` must match the `metadata.name` in `cluster/eksctl-cluster.yaml` from Step 14.
- `stage('Backend Checks')` and `stage('Frontend Checks')` mirror the `build-and-test.yml` GitHub Actions workflow from the main Phase 7 guide: install dependencies, lint, smoke-test the backend's FastAPI app import, lint and build the frontend.
- `stage('Set Image Tag')` runs `git rev-parse --short=7 HEAD` to get the short commit SHA Jenkins just checked out, and `aws sts get-caller-identity` to get the AWS account ID, then builds the full ECR registry hostname (`ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com`) from both. The commit SHA tagging is the exact same uniqueness mechanism the main Phase 7 GitHub Actions workflow uses (`${GITHUB_SHA::7}`).
- `stage('Update Kubeconfig')` runs `aws eks update-kubeconfig`, which uses the `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` environment variables set above to call the EKS API and write a working kubeconfig to `/var/lib/jenkins/.kube/config` (since pipeline stages run as the `jenkins` Linux user). Every `kubectl` command in later stages uses this file implicitly.
- `stage('Log In To ECR')` exchanges the same AWS credentials for a short-lived Docker registry password via `aws ecr get-login-password`, valid for 12 hours, then feeds it to `docker login` over stdin so the password never appears in a process listing or log line.
- `stage('Build Images')` builds both images tagged with the full ECR registry path and commit SHA in one step, instead of a separate "tag" step — `docker build -t` accepts the final destination tag directly.
- `stage('Push Images To ECR')` pushes both images. This replaces the Kind-backed version's "Load Images Into Kind" stage: EKS worker nodes pull images over the network from a registry, they do not share the Jenkins box's local Docker image cache the way a Kind node does.
- `stage('Stamp Image Tag Into Manifests')` replaces both literal placeholder strings, `ECR_REGISTRY_PLACEHOLDER` and `IMAGE_TAG_PLACEHOLDER`, in three YAML files with the real registry hostname and commit SHA using a single `sed -i` with two substitution expressions, directly in the Jenkins workspace's checked-out copy of those files, immediately before applying them.
- `stage('Deploy To EKS')` creates the namespace and StorageClass, creates or updates the ConfigMap (with a throwaway placeholder `CORS_ORIGINS` value, corrected two stages later) and Secret from the build parameters (`--dry-run=client -o yaml | kubectl apply -f -` is the standard "create or update" idiom in kubectl, since plain `kubectl create` fails if the resource already exists), deletes any previous migration Job (Kubernetes Jobs are immutable, so a stale one must be deleted before applying a new one), applies the full kustomization, and waits for every rollout in dependency order.
- `stage('Wait For ALB And Fix CORS')` is new in this version. It polls `kubectl get ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'` every 10 seconds for up to 5 minutes, since the AWS Load Balancer Controller takes a couple of minutes to provision a real ALB and is not instant the way Kind's port-mapped Nginx Ingress was. Once a hostname appears, it recreates the ConfigMap with the real `CORS_ORIGINS` value and restarts the backend Deployment so the running Pods pick up the corrected environment variable — ConfigMap changes never propagate to already-running Pods on their own.
- `stage('Verify Application')` curls the health, readiness, and summary endpoints through the ALB's own DNS name, the same verification the main Phase 7 guide performs against its own public IP.
- `post { always { ... } }` runs after every build, success or failure. It restores the three manifest files back to their committed placeholder state with `git checkout --`, undoing the `sed -i` from the stamp stage. Without this, the placeholders would be permanently replaced with a stale value in the Jenkins workspace, and the _next_ pipeline run's `sed` command would silently do nothing because the placeholder strings would no longer exist.

Reference:

- Jenkins Pipeline syntax: https://www.jenkins.io/doc/book/pipeline/syntax/
- Jenkins declarative pipeline parameters: https://www.jenkins.io/doc/book/pipeline/syntax/#parameters
- AWS CLI environment variables: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html

## Step 21: Create The Jenkins Rollback Pipeline File

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/Jenkinsfile.rollback
```

Paste:

```groovy
pipeline {
  agent any

  parameters {
    choice(name: 'DEPLOYMENT', choices: ['launchboard-backend', 'launchboard-frontend'], description: 'Which Deployment to roll back')
  }

  environment {
    AWS_CREDS = credentials('aws-jenkins-credentials')
    AWS_ACCESS_KEY_ID = "${AWS_CREDS_USR}"
    AWS_SECRET_ACCESS_KEY = "${AWS_CREDS_PSW}"
    AWS_REGION = 'YOUR_AWS_REGION'
    CLUSTER_NAME = 'devops-launchboard-phase-7-jenkins'
    NAMESPACE = 'devops-launchboard'
  }

  stages {
    stage('Update Kubeconfig') {
      steps {
        sh '''
          aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"
        '''
      }
    }

    stage('Show Rollout History') {
      steps {
        sh 'kubectl -n "${NAMESPACE}" rollout history deployment/${DEPLOYMENT}'
      }
    }

    stage('Roll Back To Previous Revision') {
      steps {
        sh 'kubectl -n "${NAMESPACE}" rollout undo deployment/${DEPLOYMENT}'
      }
    }

    stage('Wait For Rollback') {
      steps {
        sh 'kubectl -n "${NAMESPACE}" rollout status deployment/${DEPLOYMENT} --timeout=180s'
      }
    }

    stage('Show Running Image') {
      steps {
        sh '''
          kubectl -n "${NAMESPACE}" get deployment ${DEPLOYMENT} \
            -o jsonpath='{.spec.template.spec.containers[0].image}'
          echo ""
        '''
      }
    }

    stage('Verify Application') {
      steps {
        script {
          env.ALB_DNS = sh(
            script: "kubectl -n ${env.NAMESPACE} get ingress launchboard-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'",
            returnStdout: true
          ).trim()
        }
        sh '''
          curl -fsS "http://${ALB_DNS}/healthz"
          curl -fsS "http://${ALB_DNS}/health"
          curl -fsS "http://${ALB_DNS}/ready"
          echo "Rollback of ${DEPLOYMENT} verified at http://${ALB_DNS}"
        '''
      }
    }
  }
}
```

Replace `YOUR_AWS_REGION` on the `AWS_REGION` line with your real region before committing this file in Step 22.

Line explanation:

- `parameters { choice(...) }` renders a dropdown in the Jenkins UI with exactly two valid values, preventing a typo'd Deployment name from being passed to `kubectl`.
- The `environment` block reuses the exact same `aws-jenkins-credentials` Jenkins credential and the same kubeconfig pattern as the deploy pipeline, since this is a separate Jenkins job with its own fresh workspace and its own need to authenticate to the cluster.
- `stage('Update Kubeconfig')` runs first because this pipeline can be triggered on its own, at any time, independent of a deploy run — it cannot assume a kubeconfig already exists in this workspace.
- `kubectl rollout undo` switches the Deployment back to its previous ReplicaSet. Because every build in the deploy pipeline tags images with a unique commit SHA pushed to ECR, the previous ReplicaSet still references a real, different image — so this rollback actually changes what is running, not just touching the same bytes again.
- `stage('Verify Application')` looks up the ALB's current DNS name with the same `kubectl get ingress -o jsonpath` lookup the deploy pipeline uses, rather than assuming a fixed URL, since the ALB's hostname does not change between deploys but this job has no other record of it.

Note: this file is a separate Pipeline job from the deploy pipeline (Step 27 covers creating that second job), so that rollback can run on demand without rebuilding or redeploying anything.

## Step 22: Commit And Push

```bash
cd /opt/devops-launchboard/app-source
git add .dockerignore deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins
git commit -m "Convert Phase 7 Jenkins CI/CD from Kind to Amazon EKS"
git push origin main
```

Why this step exists:

The Jenkins jobs you create in the next step check out this exact path from your GitHub repository, so the Jenkinsfiles and supporting manifests must exist on `main` before Jenkins can run them.

## Step 23: Create A Jenkins-Specific GitHub Deploy Key

Jenkins needs its own way to clone the repository — reusing your personal SSH key from Step 8 would mix a human credential with an automated one, which is bad practice even in a lab.

```bash
cd ~
ssh-keygen -t ed25519 -C "jenkins-devops-launchboard" -f ~/jenkins_deploy_key -N ""
cat ~/jenkins_deploy_key.pub
```

Add the public key to GitHub:

```text
GitHub repository
Settings
Deploy keys
Add deploy key
Title: jenkins-devops-launchboard
Allow write access: unchecked
```

Read-only is enough: Jenkins only needs to check out code, never push to this repository.

In Jenkins, add the private key as a credential:

```text
Jenkins
Manage Jenkins
Credentials
System
Global credentials (unrestricted)
Add Credentials
Kind: SSH Username with private key
ID: github-jenkins-deploy-key
Username: git
Private Key: Enter directly -> paste the contents of ~/jenkins_deploy_key
```

Get the private key contents to paste:

```bash
cat ~/jenkins_deploy_key
```

Why this step exists:

When you configure the Pipeline job in the next step to check out from `git@github.com:ashraful2430/N-tier-application.git`, Jenkins needs a credential with permission to do that over SSH. This credential is scoped only to Jenkins and only allows reading this one repository — a separate concern entirely from the `aws-jenkins-credentials` credential from Step 19, which only allows talking to AWS.

Reference:

- Jenkins credentials: https://www.jenkins.io/doc/book/using/using-credentials/

## Step 24: Create The Jenkins Deploy Pipeline Job

In Jenkins:

```text
Dashboard
New Item
Name: launchboard-jenkins-deploy
Type: Pipeline
OK
```

Configure the job:

```text
Build Triggers:
  [x] Poll SCM
  Schedule: H/5 * * * *

Pipeline:
  Definition: Pipeline script from SCM
  SCM: Git
  Repository URL: git@github.com:ashraful2430/N-tier-application.git
  Credentials: github-jenkins-deploy-key
  Branch Specifier: */main
  Script Path: deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/Jenkinsfile
```

Click **Save**.

Why **Poll SCM** instead of a webhook: a GitHub webhook needs GitHub to reach Jenkins over the internet, which means opening port 8080 to the public — a real security tradeoff for a lab server. Poll SCM has Jenkins check GitHub for new commits on a schedule instead, which needs no inbound access at all. `H/5 * * * *` means "once every 5 minutes, at a random offset" (the `H` spreads load if many jobs share this schedule); Jenkins only actually starts a build if it finds a new commit since the last check.

Why this step exists:

This is the Jenkins equivalent of the main Phase 7 guide's `deploy-k8s.yml` GitHub Actions workflow: a build of this job runs every stage in the Jenkinsfile from Step 20, end to end, against the EKS cluster created in Step 14.

Reference:

- Jenkins Pipeline from SCM: https://www.jenkins.io/doc/book/pipeline/getting-started/#defining-a-pipeline-in-scm
- Jenkins Poll SCM cron syntax: https://www.jenkins.io/doc/book/pipeline/syntax/#cron-syntax

## Step 25: Run The Pipeline For The First Time

```text
Dashboard
launchboard-jenkins-deploy
Build with Parameters
DB_PASSWORD: choose a strong password
Build
```

Click the running build number, then **Console Output** to watch every stage execute live.

Expected: the build ends with `Finished: SUCCESS`. The whole run typically takes 4 to 7 minutes — most of that is the "Wait For ALB And Fix CORS" stage polling for the new Application Load Balancer to finish provisioning. Unlike the Kind-backed version of this guide, this run does not create the cluster itself (it was already created in Step 14), so there is no 5-to-10-minute first-run penalty for cluster bootstrap.

If the build fails, see Troubleshooting below before continuing.

## Step 26: Verify The App

Get the ALB DNS name from the EC2 terminal:

```bash
kubectl -n devops-launchboard get ingress launchboard-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
echo ""
```

Curl it directly:

```bash
ALB_DNS=$(kubectl -n devops-launchboard get ingress launchboard-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -I "http://${ALB_DNS}"
curl -s "http://${ALB_DNS}/health" | jq
curl -s "http://${ALB_DNS}/ready" | jq
curl -s "http://${ALB_DNS}/api/summary" | jq
```

Open in a browser:

```text
http://YOUR_ALB_DNS_NAME
```

Expected:

```text
Frontend loads.
Dashboard data appears.
No CORS errors in the browser console.
```

Unlike the Kind-backed version, do not expect the app at the Jenkins EC2's own public IP — there is no application traffic on this box at all. The URL you open is always the ALB's own DNS name.

## Step 27: Create The Jenkins Rollback Pipeline Job

```text
Dashboard
New Item
Name: launchboard-jenkins-rollback
Type: Pipeline
OK
```

Configure the job:

```text
Pipeline:
  Definition: Pipeline script from SCM
  SCM: Git
  Repository URL: git@github.com:ashraful2430/N-tier-application.git
  Credentials: github-jenkins-deploy-key
  Branch Specifier: */main
  Script Path: deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/Jenkinsfile.rollback
```

Click **Save**, then click **Build Now** once with the default parameter. Jenkins needs one initial run to discover the `choice` parameter declared in the Jenkinsfile before showing it as a "Build with Parameters" form on later runs — this is normal Jenkins behavior for any Pipeline-from-SCM job, not specific to this lab.

## Step 28: Test The Full CI/CD Loop

Make a visible change:

```bash
cd /opt/devops-launchboard/app-source
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/configmap.yaml
```

Change `APP_NAME`:

```yaml
APP_NAME: DevOps LaunchBoard API via Jenkins on EKS v2
```

Commit and push:

```bash
git add deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/configmap.yaml
git commit -m "test Jenkins CI/CD loop on EKS"
git push origin main
```

Within 5 minutes (the Poll SCM schedule from Step 24), Jenkins detects the new commit and starts a build automatically. Watch it under:

```text
Dashboard
launchboard-jenkins-deploy
```

No SSH session, no manual `kubectl` command, no manual "Build Now" click was needed for this deployment.

## Step 29: Test Rollback

```text
Dashboard
launchboard-jenkins-rollback
Build with Parameters
DEPLOYMENT: launchboard-backend
Build
```

Watch the console output: it updates the kubeconfig, shows the rollout history, rolls back, waits, and verifies against the ALB. Repeat with `launchboard-frontend` if you want to test that Deployment too.

## Logs And Debugging

Jenkins itself:

```bash
sudo journalctl -u jenkins -n 100 --no-pager
sudo tail -n 100 /var/log/jenkins/jenkins.log
```

Pipeline build logs: Jenkins UI > job name > build number > Console Output.

Kubernetes checks:

```bash
kubectl -n devops-launchboard get all
kubectl -n devops-launchboard describe pod POD_NAME
kubectl -n devops-launchboard logs deployment/launchboard-backend
kubectl -n devops-launchboard logs deployment/launchboard-frontend
kubectl -n devops-launchboard get events --sort-by=.metadata.creationTimestamp
```

EKS and AWS checks:

```bash
kubectl get nodes
eksctl get cluster --region "$AWS_REGION"
aws ecr describe-images --repository-name launchboard-backend --region "$AWS_REGION"
kubectl -n kube-system get pods | grep aws-load-balancer-controller
kubectl -n kube-system logs deployment/aws-load-balancer-controller --tail=50
```

## Troubleshooting

### Problem 1: `sudo apt install jenkins` Fails With "NO_PUBKEY" Or "Package jenkins is not available"

```text
W: GPG error: https://pkg.jenkins.io/debian-stable binary/ Release: The following signatures couldn't
be verified because the public key is not available: NO_PUBKEY 7198F4B714ABFC68
E: The repository 'https://pkg.jenkins.io/debian-stable binary/ Release' is not signed.
...
E: Package 'jenkins' has no installation candidate
```

Jenkins rotated its package signing key again since Step 9 was written, so the downloaded `jenkins.io-2026.key` file no longer matches the key ID the repository's `Release` file is actually signed with. `apt` correctly refuses to install from an unsigned repository — this is not a connectivity problem, it is a stale key.

Fix it by re-running Step 9's commands with the current key filename from the official install page:

```bash
sudo rm -f /etc/apt/keyrings/jenkins-keyring.asc /etc/apt/sources.list.d/jenkins.list
```

Then open https://www.jenkins.io/doc/book/installing/linux/#debianubuntu, copy the exact `jenkins.io-YYYY.key` filename it currently shows, and re-run:

```bash
sudo mkdir -p /etc/apt/keyrings
sudo curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-CURRENT_YEAR.key \
  -o /etc/apt/keyrings/jenkins-keyring.asc
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update
sudo apt install -y jenkins
```

### Problem 2: Jenkins UI Is Unreachable On Port 8080

Common causes:

```text
Security group does not allow inbound 8080 from your IP.
Jenkins service is not running: sudo systemctl status jenkins
Your IP address changed since the security group rule was created.
```

### Problem 3: Pipeline Fails With "permission denied" On Docker Commands

The `jenkins` user is not in the `docker` group, or Jenkins was not restarted after Step 11.

```bash
groups jenkins
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

### Problem 4: "Backend Checks" Stage Fails With "ensurepip is not available"

```text
The virtual environment was not created successfully because ensurepip is not
available. On Debian/Ubuntu systems, you need to install the python3-venv
package using the following command.

    apt install python3.12-venv
```

This means Step 4 was run before `python3-venv` was added to its package list, or you created this EC2 instance before that step was last updated. Install the missing package directly and re-run the build — no Jenkinsfile or workspace changes are needed, this is a one-time fix for the host:

```bash
sudo apt update
sudo apt install -y python3-venv python3-pip
```

Why this happens: Ubuntu's `python3` package does not bundle the `venv` module by default. `python3 -m venv .venv` needs `ensurepip`, which only becomes available once `python3-venv` is installed. Since the Jenkinsfile runs this command directly on the EC2 instance (not inside a container with its own Python image), the host itself must have this package, the same reasoning Phase 2 (bare metal) installs it for.

### Problem 5: "Backend Checks" Stage Fails With `ruff check .` Reporting F401 On `alembic/env.py`

```text
F401 [*] `app.models.deployment.Deployment` imported but unused
  --> alembic/env.py:9:35
F401 [*] `app.models.deployment.Service` imported but unused
  --> alembic/env.py:9:47
```

This is not a Jenkins or EKS problem — it is a pre-existing lint finding in the application's own `backend/alembic/env.py`, and it will fail the same way in the main Phase 7 (GitHub Actions) guide and the sibling `phase-7-cicd-EKS` guide too, since all three run the same `ruff check .` command against the same backend source.

`alembic/env.py` imports the `Deployment` and `Service` models purely so SQLAlchemy's `Base.metadata` picks up their table definitions — Alembic needs that metadata object populated to autogenerate migrations, even though nothing in this file calls `Deployment` or `Service` by name afterward. Ruff has no way to know an import exists for that side effect rather than direct use, so it flags it as unused.

Fix it once, in your own repository, by adding a `noqa` suppression comment to that import line:

```bash
cd /opt/devops-launchboard/app-source
vim backend/alembic/env.py
```

Change:

```python
from app.models.deployment import Deployment, Service
```

to:

```python
from app.models.deployment import Deployment, Service  # noqa: F401
```

Commit and push:

```bash
git add backend/alembic/env.py
git commit -m "fix: suppress ruff F401 for alembic model imports"
git push origin main
```

The next pipeline run (automatic within 5 minutes via Poll SCM, or triggered manually) will pick up the fix and the "Backend Checks" stage will pass.

### Problem 6: "Frontend Checks" Stage Fails With "npm: not found"

```text
/var/lib/jenkins/workspace/launchboard-jenkins-deploy/frontend@tmp/.../script.sh.copy: 1: npm: not found
ERROR: script returned exit code 127
```

Node.js and npm were never installed on this EC2 instance, the same root cause as Problem 4 but for the frontend toolchain instead of the Python one. Install them now and re-run the build — no Jenkinsfile or workspace changes are needed:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
sudo apt update
sudo apt install -y nodejs
node --version
npm --version
```

Why this happens: the Jenkinsfile's "Frontend Checks" stage runs `npm ci`, `npm run lint`, and `npm run build` directly on this host, the same way "Backend Checks" runs Python directly on the host. Installing Jenkins itself does not install Node.js — that is a separate toolchain Step 4 must provision explicitly.

### Problem 7: Pipeline Fails At Checkout With "Permission denied (publickey)"

The Jenkins credential from Step 23 does not match the deploy key added to GitHub, or the deploy key was added to the wrong repository.

```bash
sudo -u jenkins ssh -T git@github.com -i /var/lib/jenkins/.ssh/known_hosts 2>&1 || true
```

Re-check that the public key pasted into GitHub matches `cat ~/jenkins_deploy_key.pub`, and that the private key pasted into the Jenkins credential matches `cat ~/jenkins_deploy_key`.

### Problem 8: Pipeline Fails At "Update Kubeconfig" With "ResourceNotFoundException" Or A Region Error

The `CLUSTER_NAME` or `AWS_REGION` value hardcoded in the Jenkinsfile does not match the cluster's actual name or region from Step 14.

```bash
eksctl get cluster --region "$AWS_REGION"
```

A specific variant of this is the AWS CLI printing the placeholder string back literally:

```text
aws: [ERROR]: Provided region_name 'YOUR_AWS_REGION' doesn't match a supported format.
```

This means `AWS_REGION = 'YOUR_AWS_REGION'` was never replaced with a real region. **`Jenkinsfile` (Step 20) and `Jenkinsfile.rollback` (Step 21) each carry their own independent copy of this placeholder** — fixing it in one file does not fix it in the other, so if you replaced it in `Jenkinsfile` and the deploy pipeline started working, that tells you nothing about whether `Jenkinsfile.rollback` was also fixed. Check both files explicitly:

```bash
grep -n "AWS_REGION = 'YOUR_AWS_REGION'" deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/Jenkinsfile deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/Jenkinsfile.rollback
```

Fix whichever file `grep` still finds the placeholder in, commit, and push.

### Problem 9: kubectl Commands Fail With "error: You must be logged in to the server (Unauthorized)"

The IAM identity mapping from Step 16 is missing, or maps the wrong ARN. The IAM user behind the `aws-jenkins-credentials` Jenkins credential (Step 19) must exactly match the ARN mapped into the cluster's RBAC.

```bash
eksctl get iamidentitymapping --cluster "$CLUSTER_NAME" --region "$AWS_REGION"
```

If the entry is missing or wrong, re-run the `eksctl create iamidentitymapping` command from Step 16 with the correct ARN.

### Problem 10: docker push To ECR Fails With "no basic auth credentials"

The ECR login token from `aws ecr get-login-password` is only valid for 12 hours and is re-fetched on every pipeline run by the "Log In To ECR" stage, so this almost always means that stage did not run, or ran against the wrong region.

```bash
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"
```

### Problem 11: "Deploy To EKS" Stage Fails At `rollout status deployment/launchboard-db` With "exceeded its progress deadline"

```text
error: deployment "launchboard-db" exceeded its progress deadline
```

Check the Pod's actual crash reason — the rollout timeout itself is generic and never tells you why:

```bash
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard logs deployment/launchboard-db --previous --tail=40
```

If the log shows:

```text
initdb: error: directory "/var/lib/postgresql/data" exists but is not empty
initdb: detail: It contains a lost+found directory, perhaps due to it being a mount point.
```

this is a known PostgreSQL-on-EBS issue, not an EKS or Jenkins problem. A freshly formatted EBS volume's filesystem always contains a `lost+found` directory at its root, and PostgreSQL's `initdb` refuses to initialize a data directory it considers non-empty. The fix is to set `PGDATA` to a subdirectory of the mount in `k8s/launchboard-postgres-deployment.yaml` (already done in this guide's manifest from Step 18 — if you are hitting this, your checked-out copy predates that fix):

```yaml
- name: PGDATA
  value: /var/lib/postgresql/data/pgdata
```

After adding it, commit, push, and re-run the deploy pipeline. The backend Pods crashing with `ConnectionRefusedError` in their own logs around the same time are not a separate bug — the backend's startup script waits on a TCP connection to Postgres before doing anything else, so it crash-loops for as long as Postgres itself never comes up.

### Problem 12: Pods Show ImagePullBackOff

The image was pushed to the wrong account, region, or repository name, the ECR repositories from Step 15 were never created, or a manifest still has a literal placeholder string. Check:

```bash
kubectl -n devops-launchboard describe pod POD_NAME | tail -10
grep -rE "ECR_REGISTRY_PLACEHOLDER|IMAGE_TAG_PLACEHOLDER" deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/
aws ecr describe-repositories --region "$AWS_REGION" --query "repositories[].repositoryName"
```

If `grep` finds either placeholder still present after a build ran, the "Stamp Image Tag Into Manifests" stage did not run before "Deploy To EKS" — check the build's Console Output for the order stages actually executed in.

### Problem 13: "Wait For ALB And Fix CORS" Stage Times Out

The AWS Load Balancer Controller from Step 17 is not running, crashed, or lacks IRSA permissions.

```bash
kubectl -n kube-system get pods | grep aws-load-balancer-controller
kubectl -n kube-system logs deployment/aws-load-balancer-controller --tail=50
kubectl -n devops-launchboard describe ingress launchboard-ingress
```

`kubectl describe ingress` shows Kubernetes Events at the bottom, which usually name the exact AWS API error (commonly a missing IAM permission on the controller's IRSA role).

### Problem 14: Second Build's "Stamp Image Tag" Stage Silently Does Nothing

The `post { always { git checkout -- ... } }` block from Step 20 did not run on a previous failed build (for example, the build was manually aborted), so the placeholders are already gone from the workspace. Manually restore them:

```bash
cd /opt/devops-launchboard/app-source
git checkout -- deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-backend-deployment.yaml \
  deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-frontend-deployment.yaml \
  deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-migration-job.yaml
```

### Problem 15: CORS Errors In Browser

Should be rare in this version, since "Wait For ALB And Fix CORS" recomputes `CORS_ORIGINS` from the live ALB hostname on every run. If it still happens:

```bash
kubectl -n devops-launchboard get configmap launchboard-config -o jsonpath='{.data.CORS_ORIGINS}'
```

Compare this against the exact URL in the browser address bar. If they differ, re-run the deploy pipeline — the backend Pods may not have picked up a recent ConfigMap change if the rollout restart step itself failed partway through.

## Cleanup

Delete the Kubernetes app and load balancer (wait 2-3 minutes for ALB deletion to finish):

```bash
kubectl delete namespace devops-launchboard
```

Delete the AWS Load Balancer Controller:

```bash
helm uninstall aws-load-balancer-controller --namespace kube-system
```

Delete the EKS cluster (10 to 20 minutes):

```bash
eksctl delete cluster --name devops-launchboard-phase-7-jenkins --region "$AWS_REGION"
```

Delete the ECR repositories:

```bash
aws ecr delete-repository --repository-name launchboard-backend --region "$AWS_REGION" --force
aws ecr delete-repository --repository-name launchboard-frontend --region "$AWS_REGION" --force
```

Delete the Load Balancer Controller IAM policy:

```bash
aws iam delete-policy \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicyPhase7Jenkins"
```

Delete the Jenkins-specific IAM user from Step 16:

```bash
aws iam list-access-keys --user-name devops-launchboard-jenkins
aws iam delete-access-key --user-name devops-launchboard-jenkins --access-key-id THE_ACCESS_KEY_ID
aws iam detach-user-policy --user-name devops-launchboard-jenkins \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
aws iam detach-user-policy --user-name devops-launchboard-jenkins \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/devops-launchboard-jenkins-eks-describe"
aws iam delete-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/devops-launchboard-jenkins-eks-describe"
aws iam delete-user --user-name devops-launchboard-jenkins
```

Remove the two Jenkins jobs and the AWS credential:

```text
Dashboard > launchboard-jenkins-deploy > Delete Pipeline
Dashboard > launchboard-jenkins-rollback > Delete Pipeline
Manage Jenkins > Credentials > aws-jenkins-credentials > Delete
```

Remove the GitHub deploy key:

```text
GitHub repository > Settings > Deploy keys > delete "jenkins-devops-launchboard"
```

Stop and uninstall Jenkins (if you are done with this server entirely):

```bash
sudo systemctl stop jenkins
sudo systemctl disable jenkins
sudo apt remove -y jenkins
```

Terminate the EC2 instance from the AWS Console.

Check the AWS Console for leftover resources before you stop paying attention to this account:

```text
EC2 > Load Balancers, Target Groups, Volumes
VPC > NAT Gateways, Elastic IPs
CloudWatch > Log Groups
```

## Production Checklist

```text
[ ] IAM user with AdministratorAccess created for lab setup
[ ] EC2 server created with port 8080 restricted to your IP, no ports 80/443 open
[ ] Docker installed and verified
[ ] AWS CLI configured and verified
[ ] kubectl, eksctl, and Helm installed
[ ] GitHub SSH key created and tested (for your own manual clone)
[ ] Repository cloned
[ ] Java and Jenkins installed
[ ] Jenkins unlocked, suggested plugins installed, admin user created
[ ] jenkins system user added to docker group and Jenkins restarted
[ ] jenkins system user verified to run docker ps successfully
[ ] Phase folders and root .dockerignore created
[ ] Dockerfile.backend, Dockerfile.frontend, nginx-frontend.conf created
[ ] EKS cluster created and 2 nodes Ready
[ ] ECR repositories created with lifecycle policy
[ ] Jenkins-specific IAM user created and mapped into cluster RBAC
[ ] AWS Load Balancer Controller installed and rolled out
[ ] All Kubernetes manifests created in k8s/
[ ] AWS credential added to Jenkins
[ ] Jenkinsfile and Jenkinsfile.rollback created with correct region/cluster name
[ ] Changes committed and pushed to main
[ ] Separate Jenkins-only GitHub deploy key created and added as a Jenkins credential
[ ] launchboard-jenkins-deploy Pipeline job created with Poll SCM
[ ] First pipeline run succeeded end to end
[ ] App verified in browser via the ALB DNS name with no CORS errors
[ ] launchboard-jenkins-rollback Pipeline job created
[ ] Full CI/CD loop tested with a real code push
[ ] Rollback tested from the Jenkins UI
[ ] Cleanup plan understood, AWS Budget reviewed
```

## Reference Documentation

| Topic                                    | Link                                                                                 |
| ---------------------------------------- | ------------------------------------------------------------------------------------ |
| Jenkins installation (Debian/Ubuntu)     | https://www.jenkins.io/doc/book/installing/linux/#debianubuntu                       |
| Jenkins Pipeline syntax                  | https://www.jenkins.io/doc/book/pipeline/syntax/                                     |
| Jenkins Pipeline from SCM                | https://www.jenkins.io/doc/book/pipeline/getting-started/#defining-a-pipeline-in-scm |
| Jenkins credentials                      | https://www.jenkins.io/doc/book/using/using-credentials/                             |
| Jenkins Poll SCM cron syntax             | https://www.jenkins.io/doc/book/pipeline/syntax/#cron-syntax                         |
| Jenkins built-in steps reference         | https://www.jenkins.io/doc/pipeline/steps/                                           |
| Docker Engine Ubuntu install             | https://docs.docker.com/engine/install/ubuntu/                                       |
| Amazon EKS                               | https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html                    |
| eksctl                                   | https://eksctl.io/                                                                   |
| ECR lifecycle policies                   | https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html        |
| Managing IAM identities for your cluster | https://docs.aws.amazon.com/eks/latest/userguide/grant-k8s-access.html               |
| AWS Load Balancer Controller             | https://kubernetes-sigs.github.io/aws-load-balancer-controller/                      |
| Kustomize documentation                  | https://kustomize.io/                                                                |
| Kubernetes Deployments                   | https://kubernetes.io/docs/concepts/workloads/controllers/deployment/                |
| kubectl rollout                          | https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/              |
| Horizontal Pod Autoscaling               | https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/           |

## What To Do Next

Move to:

```text
Phase 8: EKS
```

Why:

This phase taught CI/CD with a self-hosted Jenkins server against a real Amazon EKS cluster, the Jenkins-flavored equivalent of the main Phase 7 guide's GitHub Actions pipeline and the sibling `phase-7-cicd-EKS` guide's Docker-Hub-and-EKS pipeline. Phase 8 goes deeper into EKS-specific topics on their own — ECR as a private registry, OIDC authentication, EBS CSI driver details, and production EKS operations — independent of which CI tool triggers the deployment.
