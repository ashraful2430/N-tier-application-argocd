# Phase 10: Security Hardening

## Fresh Start Assumption

This phase starts from a clean AWS environment and a clean Ubuntu EC2 workstation.

You do not need to complete any previous phase before using this guide.

This guide assumes:

- You have an AWS account with permissions to create EKS, EC2, IAM, ECR, ALB, EBS, VPC, NAT Gateway, CloudWatch, and Secrets Manager resources.
- AWS CLI, Docker, kubectl, eksctl, and Helm are not installed yet.
- No EKS cluster exists yet.
- The repository is not cloned yet.
- You will create files with `vim`.
- You will type commands manually.
- You will not use shell scripts.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What This Phase Covers

This phase deploys the N-tier application on Amazon EKS and then adds production security controls on top of it. The deployment comes first (Steps 1–11), then security hardening is layered on (Steps 12–21).

Security controls you will implement:

| Control | What It Does | Why It Matters |
| --- | --- | --- |
| Pod Security Admission | Rejects Pods with dangerous configurations | Prevents privileged containers, host namespace access, root escalation |
| RBAC | Limits what identities can do in the cluster | Deployers get only what they need, not cluster-admin |
| NetworkPolicy | Controls which Pods can talk to each other | A compromised frontend cannot reach the database directly |
| ResourceQuota | Caps total CPU, memory, and object counts per namespace | One app cannot consume the entire cluster |
| LimitRange | Sets default and maximum resource limits per container | Prevents containers with no limits from starving others |
| Trivy image scanning | Scans Docker images for known vulnerabilities | Catches CVEs before images reach the cluster |
| Semgrep SAST | Scans source code for security anti-patterns | Finds hardcoded secrets and unsafe code before merge |
| SonarQube (optional) | Code quality and security dashboard | Continuous visibility into code health |
| AWS Secrets Manager | Stores secrets outside Kubernetes | Versioning, audit trails, rotation, IAM access control |
| External Secrets Operator (optional) | Syncs cloud secrets into Kubernetes Secrets automatically | Keeps plaintext out of Git and out of manual YAML |
| Sealed Secrets (optional) | Encrypts secrets so they can be committed to Git safely | Enables GitOps for secrets |
| Vault policy (optional) | Dedicated secrets platform with fine-grained policies | Shows the production-grade secret management pattern |

## When To Use This Architecture

Use this architecture when:

- You already know how to deploy the app on Kubernetes (Phases 6 or 8).
- You want to learn the security controls that real platform teams add after the app is running.
- You need least-privilege Kubernetes access.
- You need network isolation between frontend, backend, and database Pods.
- You need image vulnerability scanning before deployment.
- You want to learn safer secret handling options.

Do not start here if:

- You only want a small local demo.
- You are not ready for AWS costs.
- You want the fastest beginner deployment path.

## Cost Warning

Same cost profile as Phase 8 and 9. The security tools themselves (Pod Security Admission, RBAC, NetworkPolicy, ResourceQuota, LimitRange) are built into Kubernetes and cost nothing extra. Trivy and Semgrep run as one-off Docker containers and cost nothing. The optional SonarQube Deployment needs ~2 GB memory and a 20 GB PVC, which may require scaling to 3 worker nodes.

| Resource | Approximate Cost |
| --- | --- |
| EKS control plane | ~$0.10/hour |
| 2 × t3.medium workers | ~$0.08/hour |
| NAT Gateway | ~$0.045/hour |
| ALB | ~$0.02/hour |
| EBS volumes | ~$0.01/hour |
| AWS Secrets Manager | $0.40/secret/month + $0.05 per 10,000 API calls |

Running for 8 hours costs roughly $2 to $3. Delete the cluster after each lab session.

Create an AWS Budget before starting: AWS Console > Billing > Budgets > Create budget.

Reference:

- EKS pricing: https://aws.amazon.com/eks/pricing/
- AWS Budgets: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html

## Architecture

```text
Browser
  |
  | HTTP port 80
  v
AWS Application Load Balancer
  |
  v
Frontend Pod (Nginx on port 8080)
  |                                     [NetworkPolicy: only frontend can reach backend]
  | /api traffic proxied by Nginx
  v
Backend Pod (FastAPI on port 8000)
  |                                     [NetworkPolicy: only backend + migrate can reach DB]
  | DATABASE_URL from Secret
  v
PostgreSQL Pod (port 5432)
  |
  v
Encrypted gp3 EBS Volume

Security controls applied:
  [Pod Security Admission]  → restricted level on namespace, rejects unsafe Pods
  [RBAC]                    → deployer ServiceAccount with scoped permissions
  [ResourceQuota]           → caps total CPU, memory, Pods, PVCs, Secrets in namespace
  [LimitRange]              → default + max resource limits per container
  [NetworkPolicy]           → default-deny + explicit allow rules
  [Trivy]                   → image scan before push
  [Semgrep]                 → source code scan before merge
  [Secrets Manager]         → secrets stored in AWS, synced by External Secrets Operator
```

## Files Included In This Phase

```text
deployment/phase-10-security/
+-- cluster/
|   +-- eksctl-cluster.yaml                    (EKS cluster definition)
+-- ecr/
|   +-- lifecycle-policy.json                  (auto-expire old ECR images)
+-- app-k8s/
|   +-- namespace.yaml                         (app namespace)
|   +-- storageclass.yaml                      (gp3 encrypted EBS)
|   +-- configmap.yaml                         (app configuration)
|   +-- secret.example.yaml                    (example secret)
|   +-- pvc.yaml                               (PostgreSQL persistent storage)
|   +-- launchboard-postgres-deployment.yaml   (database Pod)
|   +-- launchboard-postgres-service.yaml      (database DNS)
|   +-- launchboard-migration-job.yaml         (Alembic migrations)
|   +-- launchboard-backend-deployment.yaml    (FastAPI backend)
|   +-- launchboard-backend-service.yaml       (backend DNS)
|   +-- launchboard-frontend-deployment.yaml   (React frontend)
|   +-- launchboard-frontend-service.yaml      (frontend DNS)
|   +-- ingress.yaml                           (ALB Ingress)
|   +-- hpa.yaml                               (backend autoscaler)
|   +-- kustomization.yaml                     (groups app manifests)
+-- k8s-security/
|   +-- pod-security-standards.yaml            (PSA namespace labels)
|   +-- rbac.yaml                              (deployer ServiceAccount + Role)
|   +-- resource-quota.yaml                    (namespace resource caps)
|   +-- limit-range.yaml                       (per-container defaults and maximums)
|   +-- network-policy.yaml                    (Pod-to-Pod traffic rules)
|   +-- kustomization.yaml                     (optional: groups the 5 files above for one-command apply)
+-- secrets-management/
|   +-- aws-secrets-manager-policy.json        (IAM policy for secret reads)
|   +-- external-secret.example.yaml           (External Secrets Operator config)
|   +-- sealed-secret.example.yaml             (Sealed Secrets example)
+-- sast/
|   +-- semgrep-config.yaml                    (custom Semgrep rules)
|   +-- sonarqube.yaml                         (optional SonarQube deployment)
+-- vault/
|   +-- vault-values.yaml                      (Vault Helm values)
|   +-- launchboard-policy.hcl                 (Vault read-only policy)
+-- Dockerfile.backend                         (multi-stage FastAPI image)
+-- Dockerfile.frontend                        (multi-stage React/Nginx image)
+-- nginx-frontend.conf                        (Nginx reverse proxy config)
+-- README.md
```

## Step 1: Create EC2 Workstation And Install Tools

Create one Ubuntu EC2 workstation:

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-10-workstation` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` |
| Storage | 30 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | SSH port 22, your IP only |

SSH in:

```bash
chmod 400 devops-launchboard-key.pem
ssh -i devops-launchboard-key.pem ubuntu@YOUR_WORKSTATION_PUBLIC_IP
```

Install all tools:

```bash
cd ~
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl wget vim unzip jq ca-certificates gnupg lsb-release

# Docker
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo ${UBUNTU_CODENAME:-$VERSION_CODENAME}) stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
sudo systemctl enable docker && sudo systemctl start docker
sudo usermod -aG docker ubuntu

# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install && rm -rf aws awscliv2.zip

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/kubectl

# eksctl
curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz
sudo mv eksctl /usr/local/bin/eksctl

# Helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
rm get_helm.sh
```

Log out and SSH back in for docker group:

```bash
exit
ssh -i devops-launchboard-key.pem ubuntu@YOUR_WORKSTATION_PUBLIC_IP
```

Configure AWS and verify:

```bash
aws configure
aws sts get-caller-identity
docker --version && kubectl version --client && eksctl version && helm version
```

Command explanation:

- `curl ... -o "awscliv2.zip"` downloads the AWS CLI v2 installer; `unzip` extracts it; `sudo ./aws/install` installs it to `/usr/local/bin/aws`; the cleanup removes the installer files.
- `aws configure` prompts for your Access Key ID, Secret Access Key, default region, and output format. Get keys from IAM Console > Users > your user > Security credentials > Create access key, using the "Command Line Interface (CLI)" use case. Save both values immediately — the secret key is shown only once.
- `aws sts get-caller-identity` confirms the credentials work by printing your account ID, user ARN, and user ID.
- `kubectl` is the Kubernetes CLI; `eksctl` is the official CLI for creating and managing EKS clusters, wrapping CloudFormation so one `eksctl create cluster` command provisions the VPC, IAM roles, control plane, and node group together.
- `helm` is the Kubernetes package manager, used later in this phase to install the AWS Load Balancer Controller and, optionally, External Secrets Operator and Vault — each distributed as a Helm chart.

Reference:

- Install AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- eksctl install: https://eksctl.io/installation/
- Helm install: https://helm.sh/docs/intro/install/

## Step 2: Clone Repository

```bash
cd ~
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-10" -f ~/.ssh/devops_launchboard_github_key
cat ~/.ssh/devops_launchboard_github_key.pub
```

Add the public key to GitHub as a read-only deploy key.

```bash
cat > ~/.ssh/config << 'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/devops_launchboard_github_key
  IdentitiesOnly yes
EOF
chmod 600 ~/.ssh/config ~/.ssh/devops_launchboard_github_key
ssh -T git@github.com

sudo mkdir -p /opt/devops-launchboard
sudo chown -R ubuntu:ubuntu /opt/devops-launchboard
cd /opt/devops-launchboard
git clone git@github.com:ashraful2430/N-tier-application.git app-source
cd app-source
```

## Step 3: Create Phase 10 Folders

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-10-security/{cluster,ecr,app-k8s,k8s-security,secrets-management,sast,vault}
```

Each folder owns one concern: `cluster/` for eksctl config, `ecr/` for image lifecycle, `app-k8s/` for the application manifests, `k8s-security/` for hardening controls, `secrets-management/` for secret delivery patterns, `sast/` for source code scanning, and `vault/` for the Vault learning deployment.

## Step 4: Create EKS Cluster

```bash
vim deployment/phase-10-security/cluster/eksctl-cluster.yaml
```

Paste:

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: devops-launchboard-phase-10
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
      Environment: phase-10
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

Replace `YOUR_AWS_REGION` in three places: `metadata.region`, and both entries under `availabilityZones`. For example, if your region is `us-east-1`:

```yaml
metadata:
  region: us-east-1
availabilityZones:
  - us-east-1a
  - us-east-1b
```

Line explanation:

- `metadata.name: devops-launchboard-phase-10` names the cluster; eksctl creates CloudFormation stacks named after it.
- `metadata.version: "1.34"` pins the Kubernetes version, quoted because YAML would otherwise read `1.34` as a number.
- `iam.withOIDC: true` creates an OIDC provider — the foundation of IAM Roles for Service Accounts (IRSA), which lets Kubernetes ServiceAccounts assume IAM roles without storing AWS credentials in the cluster. The EBS CSI driver and the AWS Load Balancer Controller both need this.
- `vpc.nat.gateway: Single` creates one shared NAT Gateway instead of one per AZ, at roughly half the cost.
- `managedNodeGroups[0].privateNetworking: true` keeps worker nodes in private subnets with no public IPs; all inbound traffic goes through the ALB.
- `cloudWatch.clusterLogging.enableTypes` ships control plane logs (API server, audit, authenticator, controller manager, scheduler) to CloudWatch Logs — particularly relevant in a security-focused phase, since the audit log records every API request made against the cluster.
- `addons[0].name: aws-ebs-csi-driver` installs the EBS CSI driver as an EKS managed add-on; without it, PVCs requesting storage stay `Pending` forever.

Reference:

- eksctl ClusterConfig schema: https://eksctl.io/usage/schema/
- EKS audit logging: https://docs.aws.amazon.com/eks/latest/userguide/logging-monitoring.html

Set variables and create the cluster (20–40 minutes):

```bash
export AWS_REGION=YOUR_AWS_REGION
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export CLUSTER_NAME=devops-launchboard-phase-10
echo "Account: $ACCOUNT_ID  Region: $AWS_REGION  Cluster: $CLUSTER_NAME"

eksctl create cluster -f deployment/phase-10-security/cluster/eksctl-cluster.yaml
kubectl get nodes
```

## Step 5: Create ECR Repositories

```bash
aws ecr create-repository --repository-name launchboard-backend --region "$AWS_REGION"
aws ecr create-repository --repository-name launchboard-frontend --region "$AWS_REGION"
```

Create lifecycle policy:

```bash
vim deployment/phase-10-security/ecr/lifecycle-policy.json
```

Paste:

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep the latest 10 phase 10 images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["phase-10"],
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

Apply:

```bash
aws ecr put-lifecycle-policy \
  --repository-name launchboard-backend \
  --lifecycle-policy-text file://deployment/phase-10-security/ecr/lifecycle-policy.json \
  --region "$AWS_REGION"

aws ecr put-lifecycle-policy \
  --repository-name launchboard-frontend \
  --lifecycle-policy-text file://deployment/phase-10-security/ecr/lifecycle-policy.json \
  --region "$AWS_REGION"
```

Line explanation:

- `rulePriority: 1` keeps only the 10 most recent images tagged with the `phase-10` prefix — older ones beyond the 10 most recent are expired automatically.
- `rulePriority: 2` deletes untagged images (orphaned layers left behind when a tag is moved or overwritten) after 7 days.
- `put-lifecycle-policy` attaches this same policy to both repositories, so neither one accumulates old release images forever.

## Step 6: Create Dockerfiles And Nginx Config

### Dockerfile.backend

```bash
vim deployment/phase-10-security/Dockerfile.backend
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
- `ENV VIRTUAL_ENV=/opt/venv` and `ENV PATH="/opt/venv/bin:${PATH}"` create and prioritize a virtual environment at a known path so it can be copied between stages.
- `COPY backend/pyproject.toml backend/alembic.ini ./` copies dependency definitions before source code — a Docker layer-caching trick: unchanged dependencies mean a cached, faster rebuild.
- `RUN pip install --no-cache-dir .` installs the app and its base dependencies. Alembic is a base dependency, not a dev extra, so this plain install is enough for the migration Job too.
- `groupadd --system --gid 10001 app` / `useradd --system --uid 10001 --gid 10001 ...` pin an explicit numeric UID/GID instead of letting the system auto-assign one. A name-only `USER app` produces a non-numeric user the kubelet cannot verify against `runAsNonRoot`; pinning a fixed UID/GID keeps this Dockerfile and the Kubernetes `securityContext` deterministic and in sync — important in a security-hardening phase where Pod Security Admission (Step 10) enforces `restricted` and rejects any Pod it cannot verify as non-root.
- `USER app` switches to the non-root user for the rest of the image.
- `CMD [...]` starts Uvicorn with `--proxy-headers` so it trusts the `X-Forwarded-*` headers added by the ALB and the frontend Nginx in front of it.

Reference:

- Dockerfile reference: https://docs.docker.com/reference/dockerfile/

### Dockerfile.frontend

```bash
vim deployment/phase-10-security/Dockerfile.frontend
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

COPY deployment/phase-10-security/nginx-frontend.conf /etc/nginx/conf.d/default.conf
COPY --from=builder --chown=101:101 /app/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

Line explanation:

- `FROM node:22-alpine AS builder` uses a minimal Node.js image only to compile the React app; Node.js does not appear in the final image.
- `RUN npm ci` installs exact versions from `package-lock.json` for reproducible builds.
- `FROM nginxinc/nginx-unprivileged:1.27-alpine` is the official Nginx image designed to run as a non-root user on port 8080 — UID 101, consistent with all other phases.
- `COPY --from=builder --chown=101:101 ...` copies the compiled app into the web root, owned by that same UID/GID.

### nginx-frontend.conf

```bash
vim deployment/phase-10-security/nginx-frontend.conf
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
- `location = /healthz` returns a plain `200 ok` without hitting the backend — what Kubernetes probes check.
- `location /api/`, `location = /health`, and `location = /ready` proxy those paths to `http://launchboard-backend:8000/...`, the backend's Kubernetes Service DNS name.
- `location / { try_files $uri $uri/ /index.html; }` falls back to `index.html` for any unmatched path, required for React Router to handle direct navigation to client-side routes.

Reference:

- Nginx server block documentation: https://nginx.org/en/docs/http/ngx_http_core_module.html

### Root .dockerignore

```bash
vim /opt/devops-launchboard/app-source/.dockerignore
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

## Step 7: Build, Scan, And Push Images

Set a short variable for the registry URL so the commands below stay readable, then log in:

```bash
ECR_REGISTRY=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin $ECR_REGISTRY
```

`ECR_REGISTRY=...` builds the registry hostname once so every later command can reference `$ECR_REGISTRY` instead of repeating the full account ID and region. `aws ecr get-login-password` asks AWS for a short-lived authentication token; `--username AWS` is always the literal string `AWS` for ECR, not your IAM username.

Build:

```bash
cd /opt/devops-launchboard/app-source

docker build -f deployment/phase-10-security/Dockerfile.backend \
  -t launchboard-backend:phase-10 .

docker build -f deployment/phase-10-security/Dockerfile.frontend \
  --build-arg VITE_API_URL= \
  -t launchboard-frontend:phase-10 .
```

### Scan with Trivy before pushing

This is the security gate: scan both images for known HIGH and CRITICAL vulnerabilities before they are allowed into the registry. If Trivy exits with code 1, the image has fixable vulnerabilities and should not be pushed until the base image is updated.

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  --exit-code 1 \
  launchboard-backend:phase-10

docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  --exit-code 1 \
  launchboard-frontend:phase-10
```

Command explanation:

- `docker run --rm` runs Trivy as a disposable container. `-v /var/run/docker.sock:/var/run/docker.sock` gives Trivy access to the Docker daemon so it can inspect the local image.
- `--severity HIGH,CRITICAL` only reports vulnerabilities at these two levels. LOW and MEDIUM findings are informational and usually do not block deployment.
- `--ignore-unfixed` skips vulnerabilities that have no released fix yet. Failing the build over something nobody can fix teaches students to ignore the scanner, which is worse than having the vulnerability.
- `--exit-code 1` makes Trivy return a non-zero exit code if any matching vulnerability is found. In a CI pipeline (Phase 7), this would fail the build. Here you run it manually.

If Trivy finds vulnerabilities: read the table it prints. Each row shows the package name, installed version, and fixed version. The fix is usually to rebuild on a newer base image (`python:3.12-slim` or `node:22-alpine` with a newer digest that includes the patched OS packages).

Tag and push:

```bash
docker tag launchboard-backend:phase-10 $ECR_REGISTRY/launchboard-backend:phase-10
docker tag launchboard-frontend:phase-10 $ECR_REGISTRY/launchboard-frontend:phase-10

docker push $ECR_REGISTRY/launchboard-backend:phase-10
docker push $ECR_REGISTRY/launchboard-frontend:phase-10
```

`docker tag <local-name> <new-name>` does not copy or rebuild anything — it adds a second name pointing at the same image bytes already on disk, this time including the ECR registry hostname `docker push` needs to know where to upload to.

Reference:

- Trivy documentation: https://aquasecurity.github.io/trivy/
- ECR push: https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html

## Step 8: Install AWS Load Balancer Controller

```bash
cd ~
curl -o aws-load-balancer-controller-policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicyPhase10 \
  --policy-document file://aws-load-balancer-controller-policy.json

eksctl create iamserviceaccount \
  --cluster "$CLUSTER_NAME" \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicyPhase10" \
  --approve \
  --region "$AWS_REGION"

helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

Verify:

```bash
kubectl -n kube-system rollout status deployment/aws-load-balancer-controller
```

This uses the official least-privilege IAM policy from the controller repository, not `ElasticLoadBalancingFullAccess`. In a security-focused phase, using the broadest possible AWS managed policy would contradict the principle of least privilege.

Command explanation:

- `eksctl create iamserviceaccount` creates three things at once: an IAM role with the downloaded policy attached, a Kubernetes ServiceAccount in `kube-system`, and a trust relationship between them via the cluster's OIDC provider. This is IRSA (IAM Roles for Service Accounts) — when the controller Pod runs with this ServiceAccount, the AWS SDK inside it automatically receives temporary credentials for the IAM role, with no access keys stored in the cluster.
- `helm install` deploys the controller from the official EKS Helm chart repository. `--set serviceAccount.create=false` tells Helm not to create its own ServiceAccount, because `eksctl create iamserviceaccount` already created one with the IAM role attached; `--set serviceAccount.name=...` tells the controller to use that existing one.
- Without this controller running, the Ingress applied in the next step would sit idle with no `ADDRESS` and no ALB would ever be created.

Reference:

- AWS Load Balancer Controller installation: https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/
- IRSA: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html

## Step 9: Deploy The Application

All manifests go inside `deployment/phase-10-security/app-k8s/`. Unlike Phase 8, every container here already sets `allowPrivilegeEscalation: false` and drops all Linux capabilities — these manifests are written to already satisfy the `restricted` Pod Security Admission level you apply in Step 10, instead of needing to be patched afterward.

#### namespace.yaml

```bash
vim deployment/phase-10-security/app-k8s/namespace.yaml
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

A Namespace is a logical boundary inside Kubernetes; every other resource below sets `namespace: devops-launchboard` to belong to it. The Pod Security Admission labels you add in Step 10 attach to this same Namespace object.

#### storageclass.yaml

```bash
vim deployment/phase-10-security/app-k8s/storageclass.yaml
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

`parameters.encrypted: "true"` enables EBS encryption at rest with the default AWS KMS key, at no extra cost — directly relevant to a security-hardening phase. `volumeBindingMode: WaitForFirstConsumer` delays volume creation until a Pod is scheduled, so the EBS volume lands in the same AZ as the Pod's node.

#### configmap.yaml

```bash
vim deployment/phase-10-security/app-k8s/configmap.yaml
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

`CORS_ORIGINS` is a placeholder because the ALB DNS name does not exist until AWS creates the load balancer; you update it later in this step once the Ingress is applied.

#### secret.example.yaml

```bash
vim deployment/phase-10-security/app-k8s/secret.example.yaml
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

Example only — the real Secret is created with `kubectl create secret` later in this step. Step 16 of this phase replaces this pattern entirely with AWS Secrets Manager.

#### pvc.yaml

```bash
vim deployment/phase-10-security/app-k8s/pvc.yaml
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
      storage: 10Gi
```

`storageClassName: gp3` connects this PVC to the EBS CSI driver, which creates a 10 GB encrypted volume in the same AZ as the Pod that mounts it.

#### launchboard-postgres-deployment.yaml

```bash
vim deployment/phase-10-security/app-k8s/launchboard-postgres-deployment.yaml
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
      securityContext:
        runAsNonRoot: true
        runAsUser: 999
        runAsGroup: 999
        fsGroup: 999
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: postgres
          image: postgres:16-alpine
          imagePullPolicy: IfNotPresent
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
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
              cpu: 1000m
              memory: 1Gi
      volumes:
        - name: postgres-data
          persistentVolumeClaim:
            claimName: launchboard-postgres-pvc
```

This is the first phase where the PostgreSQL Pod itself gets a full `securityContext`. Earlier phases left PostgreSQL running as whatever user the official image defaults to; here it explicitly runs as UID 999 (the `postgres` image's own built-in user — confirm with `docker run --rm postgres:16-alpine id -u`), drops every Linux capability, and blocks privilege escalation. This is required for the Pod Security Admission `restricted` level applied in Step 10: without these fields, the namespace would reject this Deployment outright once the labels are in place. `strategy.type: Recreate` is unchanged from earlier phases — a single-writer database cannot run two Pods against the same `ReadWriteOnce` volume. `PGDATA: /var/lib/postgresql/data/pgdata` points Postgres at a subdirectory of the mounted volume rather than the mount point itself — a freshly provisioned EBS volume's filesystem always contains a `lost+found` directory at its root, and `initdb` refuses to initialize a data directory it considers non-empty, crash-looping the Pod without this.

#### launchboard-postgres-service.yaml

```bash
vim deployment/phase-10-security/app-k8s/launchboard-postgres-service.yaml
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

`launchboard-db` becomes the DNS name in `DATABASE_URL`; `ClusterIP` keeps the database unreachable from outside the cluster, which the NetworkPolicy in Step 13 reinforces at the network layer.

#### launchboard-migration-job.yaml

```bash
vim deployment/phase-10-security/app-k8s/launchboard-migration-job.yaml
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
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: migrate
          image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-backend:phase-10
          imagePullPolicy: IfNotPresent
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
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

`image` pulls from your private ECR repository — replace both placeholders, e.g. `123456789012.dkr.ecr.us-east-1.amazonaws.com/launchboard-backend:phase-10`. The Pod-level `securityContext.runAsNonRoot: true` here relies on the image's own `USER app` (which the Dockerfile pins to numeric UID 10001), and the container-level `allowPrivilegeEscalation: false` / `capabilities.drop: [ALL]` are the same restricted-profile fields every container in this phase needs.

#### launchboard-backend-deployment.yaml

```bash
vim deployment/phase-10-security/app-k8s/launchboard-backend-deployment.yaml
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
          image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-backend:phase-10
          imagePullPolicy: IfNotPresent
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
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

`runAsUser: 10001` and `runAsGroup: 10001` must match the `--uid 10001 --gid 10001` pinned in the Dockerfile, or the Pod fails with `CreateContainerConfigError` because the kubelet cannot verify a name-based `USER app` against `runAsNonRoot`. `allowPrivilegeEscalation: false` blocks a process from gaining more privileges than its parent (for example, via a setuid binary); `capabilities.drop: [ALL]` removes every Linux capability the container would otherwise inherit (such as `NET_RAW` or `SYS_ADMIN`), leaving only what an unprivileged process needs. Together these two container-level fields plus the Pod-level `securityContext` above are exactly what the `restricted` Pod Security Standard checks for.

#### launchboard-backend-service.yaml

```bash
vim deployment/phase-10-security/app-k8s/launchboard-backend-service.yaml
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

#### launchboard-frontend-deployment.yaml

```bash
vim deployment/phase-10-security/app-k8s/launchboard-frontend-deployment.yaml
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
          image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-frontend:phase-10
          imagePullPolicy: IfNotPresent
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
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

`runAsUser: 101` matches the nginx user baked into the `nginxinc/nginx-unprivileged` image, the same pattern as the backend's pinned UID 10001 but for a different base image's built-in user. The same `allowPrivilegeEscalation: false` / `capabilities.drop: [ALL]` pair applies here too.

#### launchboard-frontend-service.yaml

```bash
vim deployment/phase-10-security/app-k8s/launchboard-frontend-service.yaml
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

Port 80 is what the Ingress targets; port 8080 is the Pod's actual non-root port.

#### ingress.yaml

```bash
vim deployment/phase-10-security/app-k8s/ingress.yaml
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
    alb.ingress.kubernetes.io/load-balancer-name: launchboard-phase-10
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

`spec.ingressClassName: alb` tells the AWS Load Balancer Controller installed in Step 8 to handle this Ingress. `alb.ingress.kubernetes.io/target-type: ip` sends ALB traffic directly to Pod IPs via the AWS VPC CNI. `load-balancer-name` gives the ALB a predictable name in the EC2 Console.

#### hpa.yaml

```bash
vim deployment/phase-10-security/app-k8s/hpa.yaml
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

If average backend CPU usage exceeds 70% of requested CPU, the HPA scales up to a maximum of 5 Pods; it never scales below 2. EKS includes the Metrics Server by default, so this works immediately with no extra installation. The ResourceQuota you create in Step 12 caps how many Pods can exist in this namespace overall — the HPA's `maxReplicas` should stay comfortably under that cap.

#### kustomization.yaml

```bash
vim deployment/phase-10-security/app-k8s/kustomization.yaml
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

Lists every manifest so one `kubectl apply -k` applies them all in order. `secret.example.yaml` is deliberately not listed — the real Secret is created separately with `kubectl create secret`.

Reference:

- Kubernetes Deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
- Pod security context: https://kubernetes.io/docs/tasks/configure-pod-container/security-context/
- Kustomize documentation: https://kustomize.io/

Replace image placeholders:

```bash
cd /opt/devops-launchboard/app-source
sed -i "s|YOUR_ACCOUNT_ID|${ACCOUNT_ID}|g; s|YOUR_AWS_REGION|${AWS_REGION}|g" \
  deployment/phase-10-security/app-k8s/launchboard-backend-deployment.yaml \
  deployment/phase-10-security/app-k8s/launchboard-migration-job.yaml \
  deployment/phase-10-security/app-k8s/launchboard-frontend-deployment.yaml
```

Create namespace and Secret:

```bash
kubectl apply -f deployment/phase-10-security/app-k8s/namespace.yaml

kubectl create secret generic launchboard-secret \
  --namespace devops-launchboard \
  --from-literal=POSTGRES_PASSWORD='CHANGE_ME_STRONG_PASSWORD' \
  --from-literal=DATABASE_URL='postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@launchboard-db:5432/launchboard'
```

Apply and verify:

```bash
kubectl apply -k deployment/phase-10-security/app-k8s

kubectl -n devops-launchboard rollout status deployment/launchboard-db --timeout=300s
kubectl -n devops-launchboard wait --for=condition=complete job/launchboard-migrate --timeout=300s
kubectl -n devops-launchboard rollout status deployment/launchboard-backend --timeout=300s
kubectl -n devops-launchboard rollout status deployment/launchboard-frontend --timeout=300s

kubectl -n devops-launchboard get ingress launchboard-ingress
```

Wait for the ALB DNS to appear, then update CORS:

```bash
ALB_DNS=$(kubectl -n devops-launchboard get ingress launchboard-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB: $ALB_DNS"

vim deployment/phase-10-security/app-k8s/configmap.yaml
```

Set `CORS_ORIGINS` to `http://YOUR_ALB_DNS_NAME`, then:

```bash
kubectl apply -f deployment/phase-10-security/app-k8s/configmap.yaml
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
curl -s "http://$ALB_DNS/health" | jq
```

The application is running. Everything from here adds security controls on top of it.

---

# Security Hardening (Steps 10–21)

The application is running. Every step from here adds a security control. Each control is independent — if one breaks the app, you can delete it and the app still works.

---

## Step 10: Pod Security Admission

Pod Security Admission (PSA) is built into Kubernetes since v1.23. It evaluates every Pod against a security profile before allowing it to start. The `restricted` profile is the most secure: it requires non-root containers, drops all Linux capabilities, enforces read-only root filesystems (when possible), and requires seccomp profiles.

Your application already meets the `restricted` requirements because the Dockerfiles run as non-root and the Deployments set `securityContext` with `runAsNonRoot`, `runAsUser`, and `seccompProfile`. Applying PSA formalizes this: if anyone later adds a Deployment that tries to run as root, Kubernetes rejects it immediately instead of letting it run.

```bash
vim deployment/phase-10-security/k8s-security/pod-security-standards.yaml
```

Paste:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: devops-launchboard
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
```

Apply:

```bash
kubectl apply -f deployment/phase-10-security/k8s-security/pod-security-standards.yaml
```

Line explanation:

- `pod-security.kubernetes.io/enforce: restricted` rejects any Pod that violates the restricted policy. The Pod cannot be created.
- `pod-security.kubernetes.io/audit: restricted` logs violations to the API server audit log even if they are also enforced. Useful for security incident investigation.
- `pod-security.kubernetes.io/warn: restricted` shows a warning in the kubectl output when a Pod would violate the policy. Useful during migration to catch issues before switching to enforce.
- Setting all three to `restricted` means violations are blocked, warned about, and logged.

Test that a privileged Pod is rejected:

```bash
kubectl run test-privileged --image=nginx -n devops-launchboard \
  --overrides='{"spec":{"containers":[{"name":"test","image":"nginx","securityContext":{"privileged":true}}]}}' \
  --restart=Never
```

Expected:

```text
Error from server (Forbidden): ... violates PodSecurity "restricted:latest"
```

This proves the control works. Clean up:

```bash
kubectl delete pod test-privileged -n devops-launchboard --ignore-not-found
```

Verify existing Pods still run (they already meet restricted requirements):

```bash
kubectl -n devops-launchboard get pods
```

Reference:

- Pod Security Standards: https://kubernetes.io/docs/concepts/security/pod-security-standards/
- Pod Security Admission: https://kubernetes.io/docs/concepts/security/pod-security-admission/

## Step 11: RBAC (Role-Based Access Control)

Right now, you are using cluster-admin access (from the kubeconfig that eksctl configured). In production, different people and automation tools need different levels of access. A CI/CD pipeline that deploys the app needs permission to create Deployments but not to delete namespaces. A developer debugging needs permission to read Pods and logs but not to modify Secrets.

This step creates a `launchboard-deployer` ServiceAccount with only the permissions needed to deploy and manage the application in the `devops-launchboard` namespace — nothing more.

```bash
vim deployment/phase-10-security/k8s-security/rbac.yaml
```

Paste:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: launchboard-deployer
  namespace: devops-launchboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: launchboard-deployer
  namespace: devops-launchboard
rules:
  - apiGroups: [""]
    resources: ["configmaps", "pods", "services"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "create", "update", "patch"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses", "networkpolicies"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: ["autoscaling"]
    resources: ["horizontalpodautoscalers"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: launchboard-deployer
  namespace: devops-launchboard
subjects:
  - kind: ServiceAccount
    name: launchboard-deployer
    namespace: devops-launchboard
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: launchboard-deployer
```

Apply:

```bash
kubectl apply -f deployment/phase-10-security/k8s-security/rbac.yaml
```

Line explanation:

- `kind: ServiceAccount` creates an identity that Pods or CI pipelines can use to authenticate with the Kubernetes API. Unlike a human user, a ServiceAccount is namespace-scoped and has no password — it uses a JWT token.
- `kind: Role` defines what the identity can do, scoped to the `devops-launchboard` namespace only. A Role cannot grant access to other namespaces; for that you would need a ClusterRole.
- Each `rules` entry grants specific verbs on specific resources. Notice: Jobs have `delete` because the deploy workflow (Phase 7) needs to delete the old migration Job before re-creating it (Jobs are immutable). Other resources do not have `delete` — the deployer can create and update them but not remove them. Secrets have no `delete` either — the deployer can create/update secrets but cannot wipe them.
- `kind: RoleBinding` connects the Role to the ServiceAccount. Without the binding, the Role exists but nobody has it.

Test with impersonation:

```bash
kubectl auth can-i get pods -n devops-launchboard --as=system:serviceaccount:devops-launchboard:launchboard-deployer
kubectl auth can-i delete namespaces --as=system:serviceaccount:devops-launchboard:launchboard-deployer
kubectl auth can-i get pods -n kube-system --as=system:serviceaccount:devops-launchboard:launchboard-deployer
```

Expected:

```text
yes   (can get pods in own namespace)
no    (cannot delete namespaces)
no    (cannot access kube-system)
```

Reference:

- Kubernetes RBAC: https://kubernetes.io/docs/reference/access-authn-authz/rbac/

## Step 12: ResourceQuota And LimitRange

ResourceQuota caps the total resources a namespace can consume. LimitRange sets per-container defaults and maximums. Together they prevent any single container or namespace from monopolizing the cluster.

### resource-quota.yaml

```bash
vim deployment/phase-10-security/k8s-security/resource-quota.yaml
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
    requests.memory: 4Gi
    limits.cpu: "6"
    limits.memory: 10Gi
    pods: "20"
    persistentvolumeclaims: "4"
    services: "10"
    secrets: "20"
    configmaps: "20"
```

Line explanation:

- `requests.cpu: "2"` means the sum of all `resources.requests.cpu` across all Pods cannot exceed 2 CPU cores. Kubernetes refuses to create a new Pod if it would push the total past this limit.
- `requests.memory: 4Gi` caps total memory requests at 4 GiB.
- `limits.cpu: "6"` and `limits.memory: 10Gi` cap the total limits (the burst ceiling).
- `pods: "20"` prevents runaway HPA or a misconfigured Deployment from creating unlimited Pods.
- `persistentvolumeclaims: "4"` prevents accidental EBS volume sprawl (each PVC creates a real EBS volume that costs money).
- `services: "10"`, `secrets: "20"`, `configmaps: "20"` cap object counts for defense in depth.

### limit-range.yaml

```bash
vim deployment/phase-10-security/k8s-security/limit-range.yaml
```

Paste:

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: launchboard-default-limits
  namespace: devops-launchboard
spec:
  limits:
    - type: Container
      defaultRequest:
        cpu: 100m
        memory: 128Mi
      default:
        cpu: 500m
        memory: 512Mi
      max:
        cpu: "2"
        memory: 2Gi
      min:
        cpu: 25m
        memory: 64Mi
```

Line explanation:

- `defaultRequest` is applied to any container that does not specify `resources.requests`. This prevents "no-request" Pods that the scheduler cannot account for.
- `default` is applied as the `resources.limits` for containers that do not set their own limits. Without limits, a single container could consume all node memory and trigger OOMKilled events for other Pods.
- `max` is the absolute ceiling per container. A Deployment that asks for `cpu: "4"` is rejected.
- `min` is the floor. A container requesting less than 25m CPU or 64Mi memory is rejected (such small values usually indicate a copy-paste error).

Apply both:

```bash
kubectl apply -f deployment/phase-10-security/k8s-security/resource-quota.yaml
kubectl apply -f deployment/phase-10-security/k8s-security/limit-range.yaml
kubectl -n devops-launchboard describe resourcequota launchboard-quota
kubectl -n devops-launchboard describe limitrange launchboard-default-limits
```

Reference:

- ResourceQuota: https://kubernetes.io/docs/concepts/policy/resource-quotas/
- LimitRange: https://kubernetes.io/docs/concepts/policy/limit-range/

## Step 13: NetworkPolicy

Without NetworkPolicy, every Pod in the cluster can reach every other Pod on any port. This is the Kubernetes default and it is dangerous: if an attacker compromises the frontend Pod, nothing stops them from connecting directly to the PostgreSQL Pod and dumping the database.

NetworkPolicy is the Kubernetes firewall. You start with a default-deny rule (block everything), then add explicit allow rules for only the traffic your application needs.

Important: on EKS, NetworkPolicy enforcement requires the VPC CNI network policy feature, which is enabled by default on EKS clusters running Kubernetes 1.25+. If your cluster is older, you need to enable it or install Calico.

```bash
vim deployment/phase-10-security/k8s-security/network-policy.yaml
```

Paste:

```yaml
# 1. Default deny all traffic in the namespace
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
# 2. Allow all Pods to make DNS queries
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
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
---
# 3. Allow ALB/public traffic to reach frontend, allow frontend to reach backend
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-public-to-frontend
  namespace: devops-launchboard
spec:
  podSelector:
    matchLabels:
      app: launchboard-frontend
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - ipBlock:
            cidr: 0.0.0.0/0
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: launchboard-backend
      ports:
        - protocol: TCP
          port: 8000
---
# 4. Allow frontend to reach backend, allow backend to reach database
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
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: launchboard-frontend
      ports:
        - protocol: TCP
          port: 8000
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: launchboard-db
      ports:
        - protocol: TCP
          port: 5432
---
# 5. Allow backend and migration job to reach PostgreSQL
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-backend-to-postgres
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
# 6. Allow migration job to reach PostgreSQL
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-migration-to-postgres
  namespace: devops-launchboard
spec:
  podSelector:
    matchLabels:
      app: launchboard-migrate
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

Apply:

```bash
kubectl apply -f deployment/phase-10-security/k8s-security/network-policy.yaml
kubectl -n devops-launchboard get networkpolicy
```

Verify the app still works:

```bash
curl -s "http://$ALB_DNS/health" | jq
curl -s "http://$ALB_DNS/api/summary" | jq
```

Traffic flow after NetworkPolicy:

```text
ALB → frontend:8080     ✓ (policy 3: allow public to frontend)
frontend → backend:8000  ✓ (policy 3 egress + policy 4 ingress)
backend → postgres:5432  ✓ (policy 4 egress + policy 5 ingress)
migrate → postgres:5432  ✓ (policy 6 egress + policy 5 ingress)
frontend → postgres:5432 ✗ (no policy allows this)
backend → frontend:8080  ✗ (no policy allows this)
any pod → internet       ✗ (default deny, only DNS allowed)
```

Reference:

- NetworkPolicy: https://kubernetes.io/docs/concepts/services-networking/network-policies/
- EKS VPC CNI network policy: https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy.html

## Step 14: Semgrep SAST Scanning

SAST (Static Application Security Testing) scans source code for security anti-patterns without running the application. Semgrep is an open-source SAST tool that uses pattern-matching rules.

```bash
vim deployment/phase-10-security/sast/semgrep-config.yaml
```

Paste:

```yaml
rules:
  - id: launchboard-hardcoded-secret
    message: >
      Hardcoded secret-like value detected.
      Move the value to a secret manager or environment variable.
    severity: ERROR
    languages:
      - python
      - javascript
      - typescript
    pattern-regex: (?i)(password|secret|token|api_key)\s*=\s*["'][^"']{8,}["']

  - id: launchboard-python-subprocess-shell-true
    message: >
      subprocess with shell=True can execute unexpected shell input.
      Use shell=False and pass arguments as a list instead.
    severity: WARNING
    languages:
      - python
    patterns:
      - pattern: subprocess.$FUNC(..., shell=True, ...)
```

Line explanation:

- `id: launchboard-hardcoded-secret` names the rule. IDs appear in scan output so you can identify which rule flagged a finding.
- `pattern-regex` matches assignments where a variable named `password`, `secret`, `token`, or `api_key` (case-insensitive) is set to a string literal of 8+ characters. This catches patterns like `password = "mysecretvalue123"` in Python or JavaScript files.
- `severity: ERROR` makes this rule a blocking finding. `WARNING` is informational.
- The second rule catches `subprocess.run(cmd, shell=True)` in Python, which is a code injection risk: if `cmd` contains user input, an attacker can append shell commands.

Run the scan:

```bash
cd /opt/devops-launchboard/app-source
docker run --rm -v "$PWD:/src" returntocorp/semgrep:latest \
  semgrep scan --config /src/deployment/phase-10-security/sast/semgrep-config.yaml /src
```

Command explanation:

- `docker run --rm -v "$PWD:/src"` mounts the repository into the Semgrep container at `/src`.
- `semgrep scan --config ...` runs the scan using the custom rules file. Semgrep also supports `--config auto` to use community-maintained rules from the Semgrep registry.
- Output shows each finding with file path, line number, matched code, and rule ID.

If findings appear: review each one. Hardcoded secrets should be moved to environment variables or a secret manager. `shell=True` calls should be rewritten with `shell=False` and a list of arguments.

Reference:

- Semgrep documentation: https://semgrep.dev/docs/
- Semgrep rules registry: https://semgrep.dev/r

## Step 15: Optional SonarQube Learning Deployment

SonarQube provides a web dashboard for continuous code quality and security analysis. It is heavier than Semgrep (requires 2+ GB memory and a persistent volume) so it is optional.

```bash
vim deployment/phase-10-security/sast/sonarqube.yaml
```

Paste:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: security
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: sonarqube-data
  namespace: security
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 20Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sonarqube
  namespace: security
  labels:
    app: sonarqube
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sonarqube
  template:
    metadata:
      labels:
        app: sonarqube
    spec:
      securityContext:
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      initContainers:
        - name: fix-permissions
          image: busybox:1.36
          command: ["sh", "-c", "chown -R 1000:1000 /opt/sonarqube/data"]
          volumeMounts:
            - name: sonarqube-data
              mountPath: /opt/sonarqube/data
          securityContext:
            runAsUser: 0
      containers:
        - name: sonarqube
          image: sonarqube:10-community
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 9000
          resources:
            requests:
              cpu: 500m
              memory: 2Gi
            limits:
              cpu: "2"
              memory: 4Gi
          volumeMounts:
            - name: sonarqube-data
              mountPath: /opt/sonarqube/data
      volumes:
        - name: sonarqube-data
          persistentVolumeClaim:
            claimName: sonarqube-data
---
apiVersion: v1
kind: Service
metadata:
  name: sonarqube
  namespace: security
spec:
  type: ClusterIP
  selector:
    app: sonarqube
  ports:
    - name: http
      port: 9000
      targetPort: 9000
```

Line explanation:

- `kind: Namespace` creates a separate `security` namespace — SonarQube is a platform tool, not part of the application, so it does not belong in `devops-launchboard`.
- `storageClassName: gp3` with `storage: 20Gi` gives SonarQube's database and search index a real EBS volume; without persistence, every analysis history and configuration setting would be lost on Pod restart.
- `securityContext.fsGroup: 1000` sets the group that owns the mounted volume, matching the UID the SonarQube image runs its process as.
- `initContainers` runs `chown -R 1000:1000` on the data directory as root (`runAsUser: 0`, scoped only to this init container) before the main container starts as a non-root user. This exists because a fresh EBS volume is owned by `root` by default, and the SonarQube process — running as UID 1000 — cannot write to it otherwise. This is one of the few legitimate reasons to run any container as root in this phase.
- `resources.requests.memory: 2Gi` / `limits.memory: 4Gi` reflect SonarQube's real footprint: it runs an embedded Elasticsearch instance for its search index, which alone typically needs 1+ GB.

Apply and access:

```bash
kubectl apply -f deployment/phase-10-security/sast/sonarqube.yaml
kubectl -n security rollout status deployment/sonarqube --timeout=300s

kubectl -n security port-forward svc/sonarqube 9000:9000 --address 0.0.0.0 &
```

Add port 9000 to the workstation security group, then open `http://YOUR_WORKSTATION_IP:9000`. Default login: `admin` / `admin` (you will be prompted to change the password on first login).

SonarQube lives in the `security` namespace, separate from the application, because it is a platform tool, not part of the app.

Reference:

- SonarQube documentation: https://docs.sonarsource.com/sonarqube-server/

## Step 16: AWS Secrets Manager

Kubernetes Secrets are base64-encoded, not encrypted (by default), and anyone with `get secrets` RBAC permission can read them in plaintext. Production teams store sensitive values in a dedicated secrets platform and sync them into Kubernetes. AWS Secrets Manager is the AWS-native option: it encrypts secrets at rest with KMS, provides version history, supports automatic rotation, and integrates with IAM for access control.

Create the secret in AWS:

```bash
aws secretsmanager create-secret \
  --name devops-launchboard/phase-10/database \
  --secret-string '{"POSTGRES_PASSWORD":"CHANGE_ME_STRONG_PASSWORD","DATABASE_URL":"postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@launchboard-db:5432/launchboard"}' \
  --region "$AWS_REGION"
```

Command explanation:

- `--name devops-launchboard/phase-10/database` uses a path-like naming convention that matches the app and phase. Slashes in the name are cosmetic (Secrets Manager treats the whole string as one name), but they make the console and IAM policies more readable.
- `--secret-string` stores a JSON object with the same keys the Kubernetes Secret uses. The External Secrets Operator (Step 17) will read individual properties from this JSON.
- AWS encrypts this at rest with the default `aws/secretsmanager` KMS key. You can specify a custom KMS key for tighter access control.

Create the IAM policy that allows reading this specific secret:

```bash
vim deployment/phase-10-security/secrets-management/aws-secrets-manager-policy.json
```

Paste:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadLaunchboardDatabaseSecret",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:YOUR_AWS_REGION:YOUR_ACCOUNT_ID:secret:devops-launchboard/phase-10/database-*"
    }
  ]
}
```

Replace `YOUR_AWS_REGION` and `YOUR_ACCOUNT_ID`. The trailing `-*` wildcard in the Resource ARN is required because Secrets Manager appends a random 6-character suffix to the secret ARN.

Line explanation:

- `secretsmanager:GetSecretValue` allows reading the secret's encrypted value. This is the only action the application needs.
- `secretsmanager:DescribeSecret` allows reading metadata (version, rotation status) without the value. The External Secrets Operator uses this to check if the secret has changed.
- `Resource` is scoped to exactly one secret. The operator cannot read any other secret in the account.

Create the policy:

```bash
sed -i "s|YOUR_AWS_REGION|${AWS_REGION}|g; s|YOUR_ACCOUNT_ID|${ACCOUNT_ID}|g" \
  deployment/phase-10-security/secrets-management/aws-secrets-manager-policy.json

aws iam create-policy \
  --policy-name devops-launchboard-phase-10-secrets-read \
  --policy-document file://deployment/phase-10-security/secrets-management/aws-secrets-manager-policy.json
```

Reference:

- AWS Secrets Manager: https://docs.aws.amazon.com/secretsmanager/
- Secrets Manager pricing: https://aws.amazon.com/secrets-manager/pricing/

## Step 17: Optional — External Secrets Operator

The External Secrets Operator (ESO) watches for `ExternalSecret` custom resources in Kubernetes, reads the referenced secret from AWS Secrets Manager, and creates a normal Kubernetes Secret that your Pods consume via `envFrom`. The loop runs on a configurable refresh interval, so if you rotate the secret in AWS, the Kubernetes Secret updates automatically.

Install ESO:

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true
```

Create an IRSA service account so ESO can read the AWS secret:

```bash
eksctl create iamserviceaccount \
  --cluster "$CLUSTER_NAME" \
  --namespace devops-launchboard \
  --name launchboard-secrets-reader \
  --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/devops-launchboard-phase-10-secrets-read" \
  --approve \
  --region "$AWS_REGION"
```

Create the SecretStore and ExternalSecret:

```bash
vim deployment/phase-10-security/secrets-management/external-secret.example.yaml
```

Paste:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: devops-launchboard
spec:
  provider:
    aws:
      service: SecretsManager
      region: YOUR_AWS_REGION
      auth:
        jwt:
          serviceAccountRef:
            name: launchboard-secrets-reader
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: launchboard-secret
  namespace: devops-launchboard
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: launchboard-secret
    creationPolicy: Owner
  data:
    - secretKey: POSTGRES_PASSWORD
      remoteRef:
        key: devops-launchboard/phase-10/database
        property: POSTGRES_PASSWORD
    - secretKey: DATABASE_URL
      remoteRef:
        key: devops-launchboard/phase-10/database
        property: DATABASE_URL
```

Replace `YOUR_AWS_REGION`.

Line explanation:

- `kind: SecretStore` configures how ESO connects to the secret provider. `auth.jwt.serviceAccountRef` tells ESO to use the IRSA-enabled ServiceAccount for authentication. No AWS access keys are stored in the cluster.
- `kind: ExternalSecret` defines what to sync. `refreshInterval: 1h` checks for changes every hour. `target.name: launchboard-secret` is the Kubernetes Secret that ESO creates — it has the same name as the manual Secret from Step 9. `creationPolicy: Owner` means ESO owns the Secret and recreates it if deleted.
- Each `data` entry maps a Kubernetes Secret key (`secretKey`) to a JSON property in the AWS secret (`remoteRef.property`).

Important: before applying this, delete the manually created Secret so ESO can take ownership:

```bash
kubectl -n devops-launchboard delete secret launchboard-secret
```

Apply:

```bash
sed -i "s|YOUR_AWS_REGION|${AWS_REGION}|g" \
  deployment/phase-10-security/secrets-management/external-secret.example.yaml
kubectl apply -f deployment/phase-10-security/secrets-management/external-secret.example.yaml
```

Verify:

```bash
kubectl -n devops-launchboard get externalsecret
kubectl -n devops-launchboard get secret launchboard-secret
```

Expected: ExternalSecret shows `SecretSynced` status, and the Kubernetes Secret exists with the values from AWS.

Restart the backend to pick up the new Secret:

```bash
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
```

Reference:

- External Secrets Operator: https://external-secrets.io/latest/
- ESO AWS provider: https://external-secrets.io/latest/provider/aws-secrets-manager/

## Step 18: Optional — Sealed Secrets

Sealed Secrets takes a different approach: you encrypt the secret locally with a public key, commit the encrypted version to Git, and the Sealed Secrets controller inside the cluster decrypts it. This enables GitOps for secrets — the encrypted `SealedSecret` YAML is safe to commit because only the controller's private key (which never leaves the cluster) can decrypt it.

Install the controller:

```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update

helm install sealed-secrets sealed-secrets/sealed-secrets --namespace kube-system
```

This installs the Sealed Secrets controller into the cluster. The controller holds a private key (generated automatically on first install) and is the only thing that can decrypt a `SealedSecret` back into a normal Kubernetes `Secret` — encryption happens client-side with the matching public key, so the plaintext never has to leave your workstation unencrypted except in the temporary file created below.

Install the `kubeseal` CLI on the workstation:

```bash
KUBESEAL_VERSION=$(curl -s https://api.github.com/repos/bitnami-labs/sealed-secrets/releases/latest \
  | jq -r .tag_name | sed 's/v//')

curl -OL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"

tar -xzf kubeseal-*.tar.gz kubeseal
sudo mv kubeseal /usr/local/bin/kubeseal
rm kubeseal-*.tar.gz
```

Line explanation:

- `curl -s .../releases/latest` queries the GitHub API for the latest Sealed Secrets release; `jq -r .tag_name` extracts just the tag (for example `v0.27.0`); `sed 's/v//'` strips the leading `v` so the variable holds a bare version number usable in a filename.
- The second `curl` downloads the matching `kubeseal` CLI binary release archive — `kubeseal` is the client-side tool that talks to the controller's public key endpoint; it is a separate binary from the controller itself, run on your workstation rather than in the cluster.
- `tar -xzf ... kubeseal` extracts only the `kubeseal` binary from the archive, `sudo mv` puts it on the PATH, and `rm` cleans up the downloaded archive.

Create a normal Secret YAML locally (never commit this file):

```bash
kubectl -n devops-launchboard create secret generic launchboard-secret \
  --from-literal=POSTGRES_PASSWORD='CHANGE_ME_STRONG_PASSWORD' \
  --from-literal=DATABASE_URL='postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@launchboard-db:5432/launchboard' \
  --dry-run=client -o yaml > /tmp/launchboard-secret.yaml
```

`--dry-run=client -o yaml` builds the Secret object and prints its YAML without ever sending it to the cluster — the plaintext only ever touches your workstation's `/tmp`, which is removed below.

Seal it:

```bash
kubeseal --format yaml < /tmp/launchboard-secret.yaml \
  > deployment/phase-10-security/secrets-management/sealed-secret.yaml

rm /tmp/launchboard-secret.yaml
```

`kubeseal` fetches the controller's public key over the Kubernetes API, encrypts each value in the Secret with it, and writes out a `SealedSecret` resource. Because only the controller's private key (which never leaves the cluster) can decrypt it, the resulting `sealed-secret.yaml` file is safe to commit to Git even though it is derived from real credentials.

Apply it:

```bash
kubectl apply -f deployment/phase-10-security/secrets-management/sealed-secret.yaml
```

The controller watches for `SealedSecret` resources, decrypts the one you just applied with its private key, and creates a normal Kubernetes `Secret` from the result — `launchboard-secret` ends up identical to the one you would have created directly in Step 9, just without ever committing plaintext to version control.

Reference:

- Sealed Secrets: https://github.com/bitnami-labs/sealed-secrets

## Step 19: Optional — Vault Policy Example

HashiCorp Vault is a dedicated secrets management platform. It is more complex than Secrets Manager or Sealed Secrets but offers fine-grained access policies, dynamic secrets (generated on demand), lease-based expiration, and a rich audit log.

This step deploys Vault in HA mode as a learning exercise. It is optional and requires ~1.5 GB memory across the 3 replicas.

```bash
vim deployment/phase-10-security/vault/vault-values.yaml
```

Paste:

```yaml
server:
  ha:
    enabled: true
    replicas: 3
    raft:
      enabled: true
      setNodeId: true
  dataStorage:
    enabled: true
    size: 10Gi
    storageClass: gp3
  auditStorage:
    enabled: true
    size: 5Gi
    storageClass: gp3
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: "1"
      memory: 1Gi
ui:
  enabled: true
  serviceType: ClusterIP
injector:
  enabled: true
```

Line explanation:

- `ha.enabled: true` with `replicas: 3` runs Vault in high-availability mode using the integrated Raft storage backend. Three Vault Pods form a consensus cluster; if one fails, the other two continue serving.
- `raft.enabled: true` uses Raft for internal storage instead of requiring an external backend like Consul.
- `dataStorage` and `auditStorage` use the `gp3` encrypted EBS StorageClass created earlier in this phase to persist Vault's encrypted data and audit logs.
- `injector.enabled: true` installs the Vault Agent Injector, which can automatically inject secrets into Pod containers via annotations.

Create the application-scoped policy:

```bash
vim deployment/phase-10-security/vault/launchboard-policy.hcl
```

Paste:

```hcl
# Allow reading secrets under the launchboard path
path "secret/data/devops-launchboard/phase-10/*" {
  capabilities = ["read", "list"]
}

# Allow listing secret metadata (for discovery)
path "secret/metadata/devops-launchboard/phase-10/*" {
  capabilities = ["read", "list"]
}
```

This policy grants read-only access to secrets under a specific path. The application cannot write, delete, or access secrets outside its path. This is least-privilege applied to secrets.

Install Vault:

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm install vault hashicorp/vault \
  --namespace vault \
  --create-namespace \
  -f deployment/phase-10-security/vault/vault-values.yaml
```

Note: Vault starts sealed and requires initialization and unsealing before use. This is a manual process in a lab:

```bash
kubectl -n vault exec vault-0 -- vault operator init -key-shares=1 -key-threshold=1
```

`vault operator init` generates Vault's master encryption key and splits it into the given number of key shares using Shamir's Secret Sharing — `-key-shares=1 -key-threshold=1` is a lab simplification that produces a single unseal key requiring no quorum; a real production Vault would use multiple shares (for example 5) held by different people, with a threshold (for example 3) of them required together to unseal. The command also prints a root token, which is the initial all-powerful credential for logging into Vault.

Save the unseal key and root token from the output. Then unseal each replica:

```bash
kubectl -n vault exec vault-0 -- vault operator unseal YOUR_UNSEAL_KEY
kubectl -n vault exec vault-1 -- vault operator unseal YOUR_UNSEAL_KEY
kubectl -n vault exec vault-2 -- vault operator unseal YOUR_UNSEAL_KEY
```

Every Vault replica starts sealed independently and holds its data encrypted on disk until it receives the unseal key directly — unsealing one Pod does not unseal the others, which is why all three need this command run against them individually, even though they share the same Raft-replicated data.

Access the UI:

```bash
kubectl -n vault port-forward svc/vault 8200:8200 --address 0.0.0.0 &
```

Open `http://YOUR_WORKSTATION_IP:8200` and log in with the root token.

Reference:

- Vault on Kubernetes: https://developer.hashicorp.com/vault/docs/platform/k8s
- Vault policies: https://developer.hashicorp.com/vault/docs/concepts/policies

## Step 20: Verify All Security Controls

```bash
echo "=== Pod Security Admission ==="
kubectl get namespace devops-launchboard --show-labels | grep pod-security

echo ""
echo "=== RBAC ==="
kubectl -n devops-launchboard get serviceaccount,role,rolebinding
kubectl auth can-i delete namespaces --as=system:serviceaccount:devops-launchboard:launchboard-deployer

echo ""
echo "=== ResourceQuota ==="
kubectl -n devops-launchboard describe resourcequota launchboard-quota

echo ""
echo "=== LimitRange ==="
kubectl -n devops-launchboard describe limitrange launchboard-default-limits

echo ""
echo "=== NetworkPolicy ==="
kubectl -n devops-launchboard get networkpolicy

echo ""
echo "=== Application ==="
kubectl -n devops-launchboard get pods
curl -s "http://$ALB_DNS/health" | jq
curl -s "http://$ALB_DNS/api/summary" | jq
```

Expected: all controls active, app still functional, deployer cannot delete namespaces, privileged Pods are rejected.

## Troubleshooting

### Migration Job stuck in CreateContainerConfigError, backend in CrashLoopBackOff

```bash
kubectl -n devops-launchboard describe pod -l app=launchboard-migrate | grep -A3 "Events:"
```

If the event says `container has runAsNonRoot and image has non-numeric user (app), cannot verify user is non-root`:

The Job's Pod sets `runAsNonRoot: true` but no numeric `runAsUser`. The backend image's Dockerfile ends with `USER app` — a user *name* — and the kubelet can only verify non-root by number, so it refuses to create the container. (The backend Deployment works because it sets `runAsUser: 10001` explicitly.)

The backend CrashLoopBackOff (uvicorn exit code 3) is a knock-on effect: the migration never ran, the schema does not exist, and the app fails at startup. Fix the Job and the backend heals on its next restart.

Fix: add the numeric UID/GID to the Job's Pod securityContext:

```yaml
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        seccompProfile:
          type: RuntimeDefault
```

Jobs are immutable once created, so delete and re-apply:

```bash
vim deployment/phase-10-security/app-k8s/launchboard-migration-job.yaml
kubectl -n devops-launchboard delete job launchboard-migrate
kubectl apply -f deployment/phase-10-security/app-k8s/launchboard-migration-job.yaml
kubectl -n devops-launchboard wait --for=condition=complete job/launchboard-migrate --timeout=300s
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
kubectl -n devops-launchboard rollout status deployment/launchboard-backend --timeout=180s
```

### Pods rejected after Pod Security labels

```bash
kubectl -n devops-launchboard get events --sort-by=.lastTimestamp | grep Forbidden
kubectl -n devops-launchboard describe pod POD_NAME
```

The rejection message tells you which `restricted` rule was violated (e.g., missing `runAsNonRoot`, missing `seccompProfile`). Fix the Deployment's `securityContext` and re-apply.

### Frontend works but API calls fail after NetworkPolicy

```bash
kubectl -n devops-launchboard get networkpolicy
kubectl -n devops-launchboard describe networkpolicy allow-frontend-to-backend
```

Common causes: the backend Pod labels do not match the NetworkPolicy selector, the port number in the policy does not match the container port, or the DNS egress policy is missing (Pods cannot resolve Service names without DNS access).

### External Secret shows error status

```bash
kubectl -n devops-launchboard describe externalsecret launchboard-secret
kubectl -n external-secrets logs deploy/external-secrets
```

Common causes: the IRSA role is not attached (check `kubectl -n devops-launchboard get sa launchboard-secrets-reader -o yaml` for the annotation), the AWS secret name or property does not match, or the IAM policy Resource ARN is wrong (missing the trailing `-*` wildcard).

### ResourceQuota blocks Pod creation

```bash
kubectl -n devops-launchboard describe resourcequota launchboard-quota
```

Look at the "Used" vs "Hard" columns. If `pods` shows `20/20`, no more Pods can be created. Either delete unused Pods or increase the quota.

## Cleanup

Stop port-forwards:

```bash
pkill -f "port-forward"
```

Delete optional tools:

```bash
helm uninstall vault -n vault 2>/dev/null
helm uninstall sealed-secrets -n kube-system 2>/dev/null
helm uninstall external-secrets -n external-secrets 2>/dev/null
kubectl delete namespace vault external-secrets security 2>/dev/null
```

Delete security controls:

```bash
kubectl delete -f deployment/phase-10-security/k8s-security/ 2>/dev/null
```

Delete application:

```bash
kubectl delete namespace devops-launchboard
```

Wait 2 to 3 minutes for the ALB to be deleted.

Delete LB controller:

```bash
helm uninstall aws-load-balancer-controller -n kube-system
```

Delete cluster (10–20 minutes):

```bash
eksctl delete cluster --name devops-launchboard-phase-10 --region "$AWS_REGION"
```

Delete ECR:

```bash
aws ecr delete-repository --repository-name launchboard-backend --force --region "$AWS_REGION"
aws ecr delete-repository --repository-name launchboard-frontend --force --region "$AWS_REGION"
```

Delete AWS secret:

```bash
aws secretsmanager delete-secret \
  --secret-id devops-launchboard/phase-10/database \
  --force-delete-without-recovery --region "$AWS_REGION"
```

Delete IAM policies:

```bash
aws iam delete-policy \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/devops-launchboard-phase-10-secrets-read" \
  2>/dev/null

aws iam delete-policy \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicyPhase10" \
  2>/dev/null
```

Check the AWS Console for leftover resources:

```text
EC2 > Load Balancers, Target Groups, Volumes
VPC > NAT Gateways, Elastic IPs
CloudWatch > Log Groups
```

Terminate the workstation EC2.

## Production Checklist

```text
=== Infrastructure ===
[ ] AWS Budget created
[ ] EKS cluster created
[ ] ECR repositories created with lifecycle policies
[ ] Docker images built and scanned with Trivy
[ ] Docker images pushed to ECR
[ ] AWS Load Balancer Controller installed with least-privilege IAM
[ ] Application deployed and ALB working
[ ] CORS updated to ALB DNS

=== Kubernetes Hardening ===
[ ] Pod Security Admission restricted labels applied
[ ] Privileged Pod test rejected
[ ] RBAC deployer ServiceAccount created with scoped Role
[ ] Deployer cannot access kube-system or delete namespaces
[ ] ResourceQuota applied and visible in describe
[ ] LimitRange applied with default requests/limits
[ ] NetworkPolicy default-deny applied
[ ] Explicit allow rules for frontend→backend→postgres traffic
[ ] App still works after all policies applied

=== Code And Image Scanning ===
[ ] Trivy scan completed on both images before push
[ ] Semgrep scan completed on source code
[ ] SonarQube accessible (optional)

=== Secrets Management ===
[ ] AWS Secrets Manager secret created
[ ] IAM policy scoped to one secret
[ ] External Secrets Operator installed and syncing (optional)
[ ] Sealed Secrets controller installed and seal/unseal tested (optional)
[ ] Vault deployed and policy created (optional)
[ ] No plaintext secrets committed to Git

=== Cleanup ===
[ ] Cleanup plan understood
[ ] AWS Budget reviewed
```

## Reference Documentation

| Topic | Link |
| --- | --- |
| EKS | https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html |
| eksctl | https://eksctl.io/ |
| ECR | https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html |
| Kubernetes RBAC | https://kubernetes.io/docs/reference/access-authn-authz/rbac/ |
| NetworkPolicy | https://kubernetes.io/docs/concepts/services-networking/network-policies/ |
| EKS VPC CNI network policy | https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy.html |
| Pod Security Standards | https://kubernetes.io/docs/concepts/security/pod-security-standards/ |
| ResourceQuota | https://kubernetes.io/docs/concepts/policy/resource-quotas/ |
| LimitRange | https://kubernetes.io/docs/concepts/policy/limit-range/ |
| Trivy | https://aquasecurity.github.io/trivy/ |
| Semgrep | https://semgrep.dev/docs/ |
| SonarQube | https://docs.sonarsource.com/sonarqube-server/ |
| AWS Secrets Manager | https://docs.aws.amazon.com/secretsmanager/ |
| External Secrets Operator | https://external-secrets.io/latest/ |
| Sealed Secrets | https://github.com/bitnami-labs/sealed-secrets |
| Vault on Kubernetes | https://developer.hashicorp.com/vault/docs/platform/k8s |

## What To Do Next

Move to:

```text
Phase 11: Advanced Deployment Strategies
```

Why:

After the platform is deployed, observed, and hardened, the next step is to learn safer release strategies: blue-green deployments, canary releases, rollout verification gates, and progressive delivery with Argo Rollouts.
