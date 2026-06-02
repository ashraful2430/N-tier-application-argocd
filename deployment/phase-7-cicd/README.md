# Phase 7: CI/CD Automation

## Fresh Start Assumption

This phase starts from a clean Ubuntu EC2 server and a GitHub repository.

You do not need to complete any previous phase before using this guide.

This guide assumes:

- You have a fresh AWS EC2 server.
- Docker is not installed yet.
- Kind and kubectl are not installed yet.
- The repository is not cloned yet.
- GitHub Actions workflows are not configured yet.
- You will create files with `vim`.
- You will type commands manually.
- You will not use shell scripts.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What You Will Build

This phase creates a CI/CD pipeline that:

- Runs backend lint and smoke checks.
- Runs frontend lint and build checks.
- Builds backend and frontend Docker images.
- Scans Docker images with Trivy.
- Optionally pushes images to GitHub Container Registry.
- Deploys the app to a local Kind Kubernetes cluster on an EC2 self-hosted GitHub Actions runner.
- Creates Kubernetes ConfigMap and Secret from GitHub Actions variable and secret values.
- Waits for rollout.
- Verifies the app with curl.
- Supports rollback through a manual GitHub Actions workflow.

## CI/CD Architecture

```text
Developer pushes to GitHub main
  |
  v
GitHub Actions hosted runner
  |
  | build-and-test
  | docker build + scan + optional push
  v
GitHub Actions self-hosted runner on EC2
  |
  | Docker
  | Kind
  | kubectl
  v
Local Kubernetes cluster
  |
  v
DevOps LaunchBoard app
```

## When To Use This Architecture

Use this CI/CD architecture when:

- You want students to learn CI/CD before using managed cloud Kubernetes.
- You want automation but still want the deployment target to stay low cost.
- You want to teach GitHub Actions, runners, Docker builds, image scanning, Kubernetes rollout, and rollback.
- You want a bridge between local Kubernetes and EKS.

Do not use this exact architecture when:

- You need a long-term production platform.
- You need managed runner security boundaries.
- You need highly available Kubernetes.
- You need cloud load balancers and managed node groups.

Production note:

A self-hosted runner can access your server directly, so protect it carefully. For serious production, use short-lived runners, GitHub OIDC, least-privilege cloud roles, private networks, and a managed Kubernetes platform.

## Recommended AWS Setup

| Item | Recommended Value |
| --- | --- |
| EC2 Name | `devops-launchboard-phase-7-runner` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` |
| Storage | 30 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | `devops-launchboard-phase-7-sg` |
| SSH Port | `22`, your IP only |
| HTTP Port | `80`, anywhere |
| HTTPS Port | `443`, anywhere if testing HTTPS |

Do not open:

```text
8000
5432
6443
```

The backend, database, and Kubernetes API should not be public.

## Files Included In This Phase

```text
deployment/phase-7-cicd/
+-- .github/
|   +-- workflows/
|       +-- build-and-test.yml
|       +-- docker-build-push.yml
|       +-- deploy-k8s.yml
|       +-- rollback.yml
+-- k8s/
|   +-- namespace.yaml
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
+-- Dockerfile.backend
+-- Dockerfile.frontend
+-- Jenkinsfile
+-- kind-config.yaml
+-- nginx-frontend.conf
+-- README.md
```

## Step 1: Create EC2 Server

Run this step from AWS Console.

Create one EC2 instance:

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-7-runner` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` |
| Storage | 30 GB gp3 |
| Public IP | Enabled |

Security group inbound rules:

| Type | Port | Source |
| --- | ---: | --- |
| SSH | 22 | Your IP |
| HTTP | 80 | Anywhere |
| HTTPS | 443 | Anywhere |

Why this step exists:

The EC2 server will run Docker, Kind, kubectl, and the GitHub Actions self-hosted runner. The deployment workflow runs on this machine and deploys into the local Kind cluster.

Reference:

- AWS EC2 docs: https://docs.aws.amazon.com/ec2/
- EC2 security groups: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html

## Step 2: SSH Into EC2

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

## Step 3: Update Server And Install Base Tools

Run:

```bash
cd ~
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl wget vim unzip jq ca-certificates gnupg lsb-release
```

Why this step exists:

The self-hosted runner needs normal Linux tools for cloning, Docker setup, file editing, and endpoint checks.

## Step 4: Install Docker

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

Log out and SSH back in:

```bash
exit
ssh -i devops-launchboard-key.pem ubuntu@YOUR_EC2_PUBLIC_IP
```

Verify:

```bash
docker --version
docker info
```

Reference:

- Docker Engine Ubuntu install: https://docs.docker.com/engine/install/ubuntu/

## Step 5: Install Kubectl And Kind

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

Install Kind:

```bash
cd ~
curl -Lo kind https://kind.sigs.k8s.io/dl/v0.29.0/kind-linux-amd64
chmod +x kind
sudo mv kind /usr/local/bin/kind
```

Verify:

```bash
kubectl version --client
kind version
```

Why this step exists:

The deploy workflow uses `kind` to create a local Kubernetes cluster and `kubectl` to deploy the app.

Reference:

- Install kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
- Kind quick start: https://kind.sigs.k8s.io/docs/user/quick-start/

## Step 6: Create GitHub SSH Key On EC2

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-7-ec2" -f ~/.ssh/devops_launchboard_github_key
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

## Step 7: Clone The Repository

Run:

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

## Step 8: Create Phase 7 Folders

Run:

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-7-cicd/.github/workflows
mkdir -p deployment/phase-7-cicd/k8s
mkdir -p .github/workflows
```

Why this step exists:

The deployment folder stores teaching copies of the files. The root `.github/workflows` folder is where GitHub Actions actually reads workflows.

## Step 9: Add GitHub Actions Secrets And Variables

In GitHub, go to:

```text
Repository
Settings
Secrets and variables
Actions
```

Create this variable:

| Type | Name | Value |
| --- | --- | --- |
| Variable | `PHASE7_PUBLIC_APP_URL` | `http://YOUR_EC2_PUBLIC_IP` |

Create this secret:

| Type | Name | Value |
| --- | --- | --- |
| Secret | `PHASE7_DB_PASSWORD` | Strong PostgreSQL password |

Why this step exists:

The deploy workflow creates the Kubernetes ConfigMap and Secret from GitHub values. The password should not be committed into YAML.

Reference:

- GitHub Actions secrets: https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions
- GitHub Actions variables: https://docs.github.com/en/actions/learn-github-actions/variables

## Step 10: Install GitHub Actions Self-Hosted Runner

In GitHub, go to:

```text
Repository
Settings
Actions
Runners
New self-hosted runner
Linux
x64
```

GitHub will show commands for your repository. Run those commands on the EC2 server.

After configuration, start the runner:

```bash
cd ~/actions-runner
./run.sh
```

For a student lab, keep this terminal open while testing.

Why this step exists:

The deploy workflow must run on the EC2 server because that server owns the local Kind cluster.

Security note:

Self-hosted runners can execute workflow commands on your server. Only use them with repositories and workflows you trust.

Reference:

- Self-hosted runners: https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners

## Step 11: Create Root `.dockerignore`

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
```

Why this file exists:

Docker should not copy secrets, local virtual environments, dependency folders, caches, or build output into images.

## Step 12: Create CI/CD Docker And Kubernetes Files

Create these files in `deployment/phase-7-cicd/` using `vim`.

The Dockerfiles, Nginx config, Kind config, and Kubernetes manifests in this phase are the production deployment target used by the workflow:

```text
Dockerfile.backend
Dockerfile.frontend
nginx-frontend.conf
kind-config.yaml
k8s/*.yaml
```

Important values to update before committing:

```text
deployment/phase-7-cicd/k8s/configmap.yaml
```

Replace:

```text
YOUR_EC2_PUBLIC_IP
```

Why this step exists:

The CI/CD workflow uses these files to build images and deploy Kubernetes resources. Keeping them in the repository makes deployment repeatable.

## Step 13: Create `build-and-test.yml`

Create the teaching copy:

```bash
vim deployment/phase-7-cicd/.github/workflows/build-and-test.yml
```

Create the real GitHub Actions workflow:

```bash
vim .github/workflows/build-and-test.yml
```

Paste:

```yaml
name: phase-7-build-and-test

on:
  workflow_dispatch:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

permissions:
  contents: read

jobs:
  backend:
    name: Backend checks
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: pip

      - name: Install backend dependencies
        working-directory: backend
        run: |
          python -m pip install --upgrade pip
          pip install -e ".[dev]"

      - name: Run backend lint
        working-directory: backend
        run: ruff check .

      - name: Run backend smoke test
        working-directory: backend
        run: python -c "from app.main import app; print(app.title)"

      - name: Run backend tests when present
        working-directory: backend
        run: |
          if [ -d tests ]; then
            pytest
          else
            echo "No backend tests directory yet."
          fi

  frontend:
    name: Frontend checks
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: npm
          cache-dependency-path: frontend/package-lock.json

      - name: Install frontend dependencies
        working-directory: frontend
        run: npm ci

      - name: Run frontend lint
        working-directory: frontend
        run: npm run lint

      - name: Build frontend
        working-directory: frontend
        run: npm run build
```

Explanation:

This workflow protects the code before deployment. It checks backend Python quality, verifies the FastAPI app imports, runs tests if a test folder exists, lints frontend code, and builds the frontend.

## Step 14: Create `docker-build-push.yml`

Create both copies:

```bash
vim deployment/phase-7-cicd/.github/workflows/docker-build-push.yml
vim .github/workflows/docker-build-push.yml
```

Use the file content from:

```text
deployment/phase-7-cicd/.github/workflows/docker-build-push.yml
```

Why this file exists:

This workflow builds backend and frontend images, scans them with Trivy, and optionally pushes them to GitHub Container Registry.

Student note:

The file is included in this phase folder so students can inspect and copy it. The workflow must also exist at root `.github/workflows/docker-build-push.yml` for GitHub Actions to run it.

## Step 15: Create `deploy-k8s.yml`

Create both copies:

```bash
vim deployment/phase-7-cicd/.github/workflows/deploy-k8s.yml
vim .github/workflows/deploy-k8s.yml
```

Use the file content from:

```text
deployment/phase-7-cicd/.github/workflows/deploy-k8s.yml
```

Why this file exists:

This workflow runs on the self-hosted EC2 runner. It creates or reuses a Kind cluster, installs Nginx Ingress, builds images, loads images into Kind, creates ConfigMap and Secret, applies Kubernetes manifests, waits for rollout, and verifies the app.

## Step 16: Create `rollback.yml`

Create both copies:

```bash
vim deployment/phase-7-cicd/.github/workflows/rollback.yml
vim .github/workflows/rollback.yml
```

Use the file content from:

```text
deployment/phase-7-cicd/.github/workflows/rollback.yml
```

Why this file exists:

Rollback lets students manually undo the backend or frontend Deployment from GitHub Actions.

## Step 17: Commit And Push

Run from your local development machine or from the EC2 clone if you are practicing directly there:

```bash
git status
git add .dockerignore .github/workflows deployment/phase-7-cicd
git commit -m "Add phase 7 CI/CD deployment"
git push origin main
```

Why this step exists:

GitHub Actions reads workflows only after they are committed and pushed.

## Step 18: Run The Workflows

In GitHub, go to:

```text
Actions
phase-7-build-and-test
Run workflow
```

Then run:

```text
phase-7-docker-build-scan-push
```

Then run:

```text
phase-7-deploy-kind
```

Expected:

```text
Backend checks pass.
Frontend checks pass.
Docker images build.
Trivy scan passes.
Self-hosted runner deploys to Kind.
Kubernetes rollout completes.
```

## Step 19: Verify From EC2

Run:

```bash
kubectl -n devops-launchboard get all
kubectl -n devops-launchboard get ingress
curl -I http://127.0.0.1
curl -s http://127.0.0.1/health | jq
curl -s http://127.0.0.1/ready | jq
curl -s http://127.0.0.1/api/summary | jq
```

Open:

```text
http://YOUR_EC2_PUBLIC_IP
```

## Step 20: Rollback From GitHub Actions

In GitHub, run:

```text
Actions
phase-7-rollback-kind
Run workflow
```

Choose:

```text
launchboard-backend
```

or:

```text
launchboard-frontend
```

Why this step exists:

Rollback is a required production habit. If a deployment breaks the app, you need a repeatable way to return to the previous version.

## Logs And Debugging

GitHub Actions:

```text
Actions
Open failed workflow
Open failed job
Read the failed step logs
```

EC2 Kubernetes checks:

```bash
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard describe pod POD_NAME
kubectl -n devops-launchboard logs deployment/launchboard-backend
kubectl -n devops-launchboard logs deployment/launchboard-frontend
kubectl -n devops-launchboard get events --sort-by=.metadata.creationTimestamp
```

Runner checks:

```bash
cd ~/actions-runner
./run.sh
```

Docker checks:

```bash
docker images | grep launchboard
kind get clusters
kubectl get nodes
```

## Troubleshooting

### Problem 1: Workflow Does Not Start

Common causes:

```text
Workflow file is not in root .github/workflows.
Workflow was not pushed to GitHub.
GitHub Actions is disabled for the repository.
```

### Problem 2: Deploy Job Waits For Runner

Common causes:

```text
Self-hosted runner is not running.
Runner was registered to another repository.
Runner labels do not match self-hosted.
```

Fix:

```bash
cd ~/actions-runner
./run.sh
```

### Problem 3: Deploy Fails Because Secret Is Missing

Check GitHub:

```text
Settings
Secrets and variables
Actions
```

Required:

```text
PHASE7_DB_PASSWORD
PHASE7_PUBLIC_APP_URL
```

### Problem 4: ImagePullBackOff In Kubernetes

Fix on EC2:

```bash
kind load docker-image launchboard-backend:phase-7 --name launchboard-cicd
kind load docker-image launchboard-frontend:phase-7 --name launchboard-cicd
```

## Cleanup

Delete Kubernetes app:

```bash
kubectl delete namespace devops-launchboard
```

Delete Kind cluster:

```bash
kind delete cluster --name launchboard-cicd
```

Stop runner:

```text
Press CTRL + C in the runner terminal.
```

Remove runner from GitHub:

```text
Repository
Settings
Actions
Runners
Remove runner
```

AWS cleanup:

- Terminate EC2 instance.
- Delete unused EBS volumes.
- Release unused Elastic IPs.
- Check AWS Billing.

## Production Checklist

```text
[ ] EC2 runner created
[ ] Docker installed
[ ] kubectl installed
[ ] Kind installed
[ ] GitHub SSH key created and tested
[ ] Repository cloned
[ ] Self-hosted runner registered
[ ] PHASE7_PUBLIC_APP_URL variable created
[ ] PHASE7_DB_PASSWORD secret created
[ ] Root .github/workflows files created
[ ] Phase 7 Dockerfiles created
[ ] Phase 7 Kubernetes manifests created
[ ] Build and test workflow passes
[ ] Docker build and scan workflow passes
[ ] Deploy workflow runs on self-hosted runner
[ ] Kind cluster created
[ ] Ingress Controller installed
[ ] Images loaded into Kind
[ ] Kubernetes rollout succeeds
[ ] Public app URL works
[ ] Rollback workflow tested
[ ] Cleanup plan understood
```

## Reference Documentation

| Topic | Link |
| --- | --- |
| GitHub Actions | https://docs.github.com/en/actions |
| Workflow syntax | https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions |
| Self-hosted runners | https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners |
| GitHub Actions secrets | https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions |
| Docker Buildx action | https://github.com/docker/setup-buildx-action |
| Docker build-push action | https://github.com/docker/build-push-action |
| Trivy action | https://github.com/aquasecurity/trivy-action |
| Kubernetes deployments | https://kubernetes.io/docs/concepts/workloads/controllers/deployment/ |
| Kind quick start | https://kind.sigs.k8s.io/docs/user/quick-start/ |

## What To Do Next

Move to:

```text
Phase 8: EKS
```

Why:

Phase 7 teaches CI/CD against a local Kubernetes cluster. Phase 8 moves the Kubernetes platform to AWS EKS so students can learn managed Kubernetes, cloud networking, and cloud-native deployment.
