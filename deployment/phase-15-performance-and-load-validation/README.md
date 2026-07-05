# Phase 15: Performance And Load Validation

## Fresh Start Assumption

This phase starts from a clean machine and a clean AWS setup.

You do not need to finish any previous phase before using this phase.

This guide assumes:

- You have an AWS account.
- You have GitHub access to this repository.
- You will clone the repository with SSH.
- You will create a new EKS cluster for this phase.
- You will create fresh ECR repositories.
- You will build and push fresh Docker images.
- You will deploy the application to Kubernetes.
- You will install Metrics Server so HPA and `kubectl top` work.
- You will run k6 smoke, load, stress, and soak tests.
- You will write a short performance report.
- You will use `vim` to create files.
- You will not use custom shell scripts.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What This Phase Deploys

This phase deploys the N-tier application on Amazon EKS and validates it under controlled traffic.

The deployment includes:

- Vite frontend served by Nginx
- FastAPI backend
- PostgreSQL database running inside Kubernetes for the lab
- Amazon ECR repositories
- Amazon EKS cluster
- AWS Load Balancer Controller
- Metrics Server
- HorizontalPodAutoscaler
- k6 performance tests
- Performance report template

## When To Use This Architecture

Use this phase when:

- The app is already deployable and you need to prove it can handle traffic.
- You want students to understand smoke, load, stress, and soak tests.
- You need to validate backend HPA behavior.
- You want to find bottlenecks before a production launch.
- You want a repeatable performance report.

Do not use this phase when:

- You only need a quick local demo.
- You do not have a stable deployed app yet.
- You cannot afford temporary AWS load-test resources.
- You are testing someone else's public service without permission.

Important production idea:

Performance testing is not only about high traffic. It is about proving what the system can handle, where it fails, and whether it recovers cleanly.

## Test Types

| Test | Purpose | Example |
| --- | --- | --- |
| Smoke test | Proves the app basically works | 1 user for 30 seconds |
| Load test | Proves expected traffic works | 20 users for several minutes |
| Stress test | Finds the breaking point | Increase to 100 users |
| Soak test | Finds slow leaks over time | 15 users for 30 minutes |

## Database Note: Why Still A Pod And Not RDS?

This phase runs PostgreSQL as a Pod on an EBS volume, even though the production answer is a managed database. That is deliberate: this phase's lessons need a database *inside* the cluster, because the load tests exercise the whole stack including database CPU and I/O on the node — watching the database Pod saturate in Grafana during the stress test is one of this phase's best lessons. The managed-database pattern has its own homes in this track — Phase 9 (Terraform production) provisions RDS as code, and Phase 16 (capstone) runs the full Kubernetes stack against RDS with the security groups, `DB_HOST` wiring, and backup division of labor spelled out. If you want RDS here, the capstone's "Create The Database First" section is a drop-in recipe: create the instance, remove the postgres Deployment/Service/PVC from the kustomization, point `DATABASE_URL` and the wait loops at the RDS endpoint.

## Recommended AWS Setup

| Item | Recommended Value |
| --- | --- |
| AWS Region | `us-east-1` or closest region |
| Cluster Name | `devops-launchboard-phase-15` |
| Kubernetes Version | `1.34` |
| Node Type | `t3.medium` |
| Desired Nodes | `2` |
| ECR Backend Repo | `launchboard-backend` |
| ECR Frontend Repo | `launchboard-frontend` |
| Load Tool | k6 |

Cost warning:

- EKS costs money.
- EC2 worker nodes cost money.
- Load balancers cost money.
- EBS volumes cost money.
- Load testing can increase data transfer and log volume.
- Delete resources after practice.

Reference:

- EKS pricing: https://aws.amazon.com/eks/pricing/
- AWS Budgets: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html

## Architecture

```text
k6 load generator
  |
  v
AWS Application Load Balancer
  |
  v
Frontend Nginx pods
  |
  | /api, /health, /ready
  v
FastAPI backend pods
  |
  v
PostgreSQL pod and EBS-backed PVC

Metrics Server
  |
  v
HPA scales backend pods when CPU rises
```

## Step 1: Install Local Tools

Run from: your local machine

```bash
git --version
ssh -V
docker --version
aws --version
kubectl version --client
eksctl version
helm version
```

Optional local k6 check:

```bash
k6 version
```

If k6 is not installed, you can run it with Docker later.

Install missing tools:

- Git: https://git-scm.com/downloads
- Docker: https://docs.docker.com/get-docker/
- AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- kubectl: https://kubernetes.io/docs/tasks/tools/
- eksctl: https://eksctl.io/installation/
- Helm: https://helm.sh/docs/intro/install/
- k6: https://grafana.com/docs/k6/latest/set-up/install-k6/

Why this step exists:

The deployment uses AWS, Docker, Kubernetes, Helm, and k6. Checking tools first prevents students from reaching the middle of the guide and discovering a missing command.

## Step 2: Configure AWS

Run:

```bash
aws configure
aws sts get-caller-identity
```

Command explanation:

- `aws configure` prompts for an Access Key ID, Secret Access Key, default region, and output format, then saves them to `~/.aws/credentials` and `~/.aws/config`. Every AWS CLI command in this guide reads credentials from these files.
- `aws sts get-caller-identity` calls AWS and prints which IAM identity the configured credentials resolve to. If this fails with "Unable to locate credentials," `aws configure` did not save correctly.

Set variables:

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

Command explanation:

- `export AWS_REGION=us-east-1` sets the region every later `--region $AWS_REGION` flag reuses. Replace `us-east-1` with your actual region.
- `export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)` captures your 12-digit AWS account ID into a variable, used later to build the full ECR registry hostname (`$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com`).

Why this step exists:

AWS CLI needs credentials before it can create EKS, ECR, IAM, and load balancer resources. The variables keep the later commands shorter.

Important: `export` only lasts for the current shell session. If you disconnect and reconnect over SSH, or open a new terminal, re-run both `export` lines before continuing.

## Step 3: Create SSH Key And Clone

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-15" -f ~/.ssh/devops_launchboard_phase_15
cat ~/.ssh/devops_launchboard_phase_15.pub
```

Command explanation:

- `mkdir -p ~/.ssh` creates the SSH config directory if it does not already exist.
- `chmod 700 ~/.ssh` restricts the directory to the owner only — SSH refuses to use key files inside a world-readable directory.
- `ssh-keygen -t ed25519 -C "devops-launchboard-phase-15" -f ~/.ssh/devops_launchboard_phase_15` generates a new Ed25519 key pair. `-C` attaches a label comment so the key is identifiable later in GitHub's deploy key list. `-f` sets the output filename.
- `cat ~/.ssh/devops_launchboard_phase_15.pub` prints the public key so you can copy it into GitHub.

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
  IdentityFile ~/.ssh/devops_launchboard_phase_15
  IdentitiesOnly yes
```

Line explanation:

- `Host github.com` matches any SSH connection targeting `github.com`.
- `HostName github.com` is explicit here, but matters once you have multiple `Host` aliases pointing at the same real hostname.
- `User git` is the fixed username GitHub expects for all SSH Git operations, regardless of your own GitHub username.
- `IdentityFile ~/.ssh/devops_launchboard_phase_15` points SSH at the private key created above.
- `IdentitiesOnly yes` stops SSH from also trying any other keys loaded in your SSH agent, avoiding GitHub's "too many authentication failures" error if you have several keys.

Run:

```bash
chmod 600 ~/.ssh/config
chmod 600 ~/.ssh/devops_launchboard_phase_15
chmod 644 ~/.ssh/devops_launchboard_phase_15.pub
ssh -T git@github.com
```

Command explanation:

- `chmod 600` on the config and private key restricts them to owner-read-write only; SSH refuses to use a private key with looser permissions.
- `chmod 644` on the public key is fine since it is not secret.
- `ssh -T git@github.com` tests the connection without running a Git command. Expect `Hi <username>! You've successfully authenticated, but GitHub does not provide shell access.`

Clone:

```bash
sudo mkdir -p /opt/devops-launchboard
sudo chown -R $USER:$USER /opt/devops-launchboard
cd /opt/devops-launchboard
git clone git@github.com:ashraful2430/N-tier-application.git app-source
cd app-source
```

Command explanation:

- `sudo mkdir -p /opt/devops-launchboard` creates the parent folder for the project, following the same `/opt` convention used by every other phase in this repository.
- `sudo chown -R $USER:$USER /opt/devops-launchboard` gives your own user ownership so the rest of this guide does not need `sudo` for every file operation.
- `git clone git@github.com:... app-source` clones the repository over SSH using the key configured above, into a folder named `app-source`.

Why this step exists:

The source code and deployment files must exist locally before images can be built or tests can be created.

Reference:

- GitHub deploy keys: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys

## Step 4: Create Phase 15 Folders

Run:

```bash
mkdir -p deployment/phase-15-performance-and-load-validation/cluster
mkdir -p deployment/phase-15-performance-and-load-validation/ecr
mkdir -p deployment/phase-15-performance-and-load-validation/app-k8s
mkdir -p deployment/phase-15-performance-and-load-validation/monitoring
mkdir -p deployment/phase-15-performance-and-load-validation/tests/k6
mkdir -p deployment/phase-15-performance-and-load-validation/reports
```

Why these folders exist:

- `cluster` stores the EKS cluster file.
- `ecr` stores the ECR lifecycle policy.
- `app-k8s` stores Kubernetes app files.
- `monitoring` stores Metrics Server values.
- `tests/k6` stores load test definitions.
- `reports` stores performance report templates and final results.

## Step 5: Create EKS Cluster File

Create:

```bash
vim deployment/phase-15-performance-and-load-validation/cluster/eksctl-cluster.yaml
```

Paste:

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: devops-launchboard-phase-15
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
      Environment: phase-15
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

- `metadata.name` is the cluster name. Using `devops-launchboard-phase-15` keeps this cluster distinct from the ones created by other phases, so they can coexist in the same AWS account.
- `iam.withOIDC: true` creates an OpenID Connect provider for the cluster, the foundation of IAM Roles for Service Accounts (IRSA). The EBS CSI driver addon and the AWS Load Balancer Controller installed in Step 8 both need this to get AWS permissions without storing access keys in the cluster.
- `vpc.nat.gateway: Single` creates one NAT Gateway instead of one per availability zone, trading some redundancy for a meaningfully lower hourly cost in a lab.
- `managedNodeGroups` defines the EC2 worker nodes that run your Pods. `desiredCapacity: 2` with `minSize: 2`/`maxSize: 4` gives the backend's HPA room to schedule extra Pods when the load tests in Step 11-13 push CPU usage up.
- `cloudWatch.clusterLogging.enableTypes` turns on control plane log streams (API server, audit, authenticator, controller manager, scheduler) for debugging cluster-level problems in CloudWatch Logs.
- `addons.aws-ebs-csi-driver` with `wellKnownPolicies.ebsCSIController: true` tells eksctl to create an IAM role with the `AmazonEBSCSIDriverPolicy` and attach it to the EBS CSI driver's service account via IRSA. PostgreSQL's PVC in Step 7 needs this driver to provision a real EBS volume.

Create the cluster (20 to 40 minutes):

```bash
eksctl create cluster -f deployment/phase-15-performance-and-load-validation/cluster/eksctl-cluster.yaml
kubectl get nodes
```

Expected: 2 nodes `Ready`.

Why this file exists:

Performance tests need a real deployment environment. The cluster file creates a repeatable EKS environment with worker nodes, private networking, control plane logs, and EBS support.

Reference:

- eksctl: https://eksctl.io/
- Amazon EKS: https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html

## Step 6: Create ECR And Build Images

Create repositories:

```bash
aws ecr create-repository --repository-name launchboard-backend --region $AWS_REGION \
  --image-scanning-configuration scanOnPush=true
aws ecr create-repository --repository-name launchboard-frontend --region $AWS_REGION \
  --image-scanning-configuration scanOnPush=true
```

Command explanation:

- `aws ecr create-repository` creates a private container registry repository. One repository per image (backend, frontend) is the standard ECR layout.
- `--image-scanning-configuration scanOnPush=true` turns on automatic vulnerability scanning every time an image is pushed.

Create lifecycle policy:

```bash
vim deployment/phase-15-performance-and-load-validation/ecr/lifecycle-policy.json
```

Paste:

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep the latest 10 phase 15 images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["phase-15"],
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
- `tagStatus: "tagged"` with `tagPrefixList: ["phase-15"]` selects images whose tags start with `phase-15`.
- `countType: "imageCountMoreThan"` with `countNumber: 10` means: once there are more than 10 matching images, expire the oldest ones until only 10 remain. This keeps the last 10 builds available without the repository growing forever.
- `rulePriority: 2` catches untagged images (failed or interrupted pushes, or the attestation manifests modern `docker buildx` pushes alongside a tagged image) and expires them after 7 days.
- `action.type: "expire"` deletes the matching images.

Apply lifecycle policy:

```bash
aws ecr put-lifecycle-policy --repository-name launchboard-backend --region $AWS_REGION \
  --lifecycle-policy-text file://deployment/phase-15-performance-and-load-validation/ecr/lifecycle-policy.json
aws ecr put-lifecycle-policy --repository-name launchboard-frontend --region $AWS_REGION \
  --lifecycle-policy-text file://deployment/phase-15-performance-and-load-validation/ecr/lifecycle-policy.json
```

`--lifecycle-policy-text file://...` attaches the JSON policy you just wrote to each repository.

### Dockerfile.backend

```bash
vim deployment/phase-15-performance-and-load-validation/Dockerfile.backend
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

- `FROM python:3.12-slim AS builder` starts the first stage of a multi-stage build; the builder stage's build tools and caches never reach the final image.
- `ENV VIRTUAL_ENV=/opt/venv` with `ENV PATH="/opt/venv/bin:${PATH}"` creates a virtual environment at a fixed path so it can be copied between stages.
- `COPY backend/pyproject.toml backend/alembic.ini ./` before the rest of the source copies dependency definitions first — a Docker layer-caching trick: unchanged dependencies mean a cached, faster rebuild.
- `RUN pip install --no-cache-dir .` installs the application and its base dependencies, including Alembic, so this same image can also run database migrations.
- `groupadd --system --gid 10001 app` / `useradd --system --uid 10001 --gid 10001 ...` create a non-login service user with a pinned numeric UID/GID. A name-only `USER app` would produce a non-numeric identity Kubernetes cannot verify against `runAsNonRoot`; the pinned UID keeps this Dockerfile and the Kubernetes `securityContext` in Step 7 in sync.
- `COPY --from=builder /opt/venv /opt/venv` and `COPY --from=builder /app /app` bring only the installed dependencies and app code into the clean runtime stage.
- `HEALTHCHECK` polls `/health` every 30 seconds so Docker itself can report container health.
- `CMD [...]` starts Uvicorn on all interfaces. `--proxy-headers` makes FastAPI trust the `X-Forwarded-*` headers the AWS Application Load Balancer adds in front of it.

### Dockerfile.frontend

```bash
vim deployment/phase-15-performance-and-load-validation/Dockerfile.frontend
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

COPY deployment/phase-15-performance-and-load-validation/nginx-frontend.conf /etc/nginx/conf.d/default.conf
COPY --from=builder --chown=101:101 /app/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

Line explanation:

- `FROM node:22-alpine AS builder` uses a minimal Node.js image only to compile the React app; Node.js never appears in the final image.
- `ARG VITE_API_URL=""` with `ENV VITE_API_URL=${VITE_API_URL}` lets the build embed an API base URL at build time. Left empty, the frontend uses relative `/api` paths, which works because Nginx proxies those paths.
- `FROM nginxinc/nginx-unprivileged:1.27-alpine` is the official Nginx image designed to run as a non-root user on port 8080.
- `COPY --from=builder --chown=101:101 /app/dist /usr/share/nginx/html` copies the compiled app into the web root, owned by UID/GID 101, the nginx user baked into the unprivileged image.

### nginx-frontend.conf

```bash
vim deployment/phase-15-performance-and-load-validation/nginx-frontend.conf
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
- `location = /healthz` returns a plain `200 ok` without involving the backend — this is what the Kubernetes probes and the ALB's own health check (Step 7) check.
- `location /api/`, `location = /health`, and `location = /ready` proxy those paths to `http://launchboard-backend:8000/...`, the backend's Kubernetes Service DNS name.
- `location / { try_files $uri $uri/ /index.html; }` falls back to `index.html` for any unmatched path, which React Router needs for direct navigation to client-side routes.

Build and push:

```bash
ECR_REGISTRY=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin $ECR_REGISTRY
```

```bash
docker build -f deployment/phase-15-performance-and-load-validation/Dockerfile.backend \
  -t launchboard-backend:phase-15 .
docker build -f deployment/phase-15-performance-and-load-validation/Dockerfile.frontend \
  --build-arg VITE_API_URL=/api \
  -t launchboard-frontend:phase-15 .
```

```bash
docker tag launchboard-backend:phase-15 $ECR_REGISTRY/launchboard-backend:phase-15
docker tag launchboard-frontend:phase-15 $ECR_REGISTRY/launchboard-frontend:phase-15

docker push $ECR_REGISTRY/launchboard-backend:phase-15
docker push $ECR_REGISTRY/launchboard-frontend:phase-15
```

Command explanation:

- `ECR_REGISTRY=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com` builds the registry hostname once into a variable, instead of repeating the full expression on every later line.
- `aws ecr get-login-password | docker login ...` exchanges your AWS credentials for a short-lived Docker registry password (valid 12 hours) and feeds it to `docker login` over stdin, so the password never appears in a process listing or log line.
- `docker build -t launchboard-backend:phase-15` builds with a short local tag first; tagging the registry path is a separate step.
- `docker tag ... $ECR_REGISTRY/launchboard-backend:phase-15` adds the full registry path as a second name for the same image, which is what `docker push` needs to know where to send it.
- `docker push` uploads the image layers to ECR. The first push uploads every layer; later pushes only upload layers that changed.

Verify:

```bash
aws ecr describe-images --repository-name launchboard-backend --region "$AWS_REGION" \
  --query 'imageDetails[?imageTags!=null].[imageTags,imageSizeInBytes]' --output table
aws ecr describe-images --repository-name launchboard-frontend --region "$AWS_REGION" \
  --query 'imageDetails[?imageTags!=null].[imageTags,imageSizeInBytes]' --output table
```

`[?imageTags!=null]` filters out untagged entries (such as the attestation manifest `docker buildx` pushes alongside the real image) before selecting columns — without it, the AWS CLI's table renderer can crash with `Row should have 2 elements, instead it has 1` when some rows have a tag and others do not.

Why this step exists:

Load tests should run against production-style containers, not local development servers. ECR stores those containers so EKS can pull them.

Reference:

- Dockerfile reference: https://docs.docker.com/reference/dockerfile/
- ECR lifecycle policies: https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html

## Step 7: Deploy The Application

All manifests go inside `deployment/phase-15-performance-and-load-validation/app-k8s/`.

### namespace.yaml

```bash
vim deployment/phase-15-performance-and-load-validation/app-k8s/namespace.yaml
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
vim deployment/phase-15-performance-and-load-validation/app-k8s/storageclass.yaml
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

- `provisioner: ebs.csi.aws.com` is the EBS CSI driver installed as a cluster addon in Step 5. EKS has no default StorageClass, so this one must exist before the PostgreSQL PVC below can be satisfied.
- `volumeBindingMode: WaitForFirstConsumer` delays creating the actual EBS volume until a Pod using the PVC is scheduled, so the volume is created in the same availability zone as that Pod — EBS volumes cannot be attached across zones.
- `parameters.encrypted: "true"` encrypts the volume at rest using the AWS-managed EBS key.

### configmap.yaml

```bash
vim deployment/phase-15-performance-and-load-validation/app-k8s/configmap.yaml
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

`CORS_ORIGINS` tells the FastAPI backend which browser/load-test origin may call the API; it must match whatever URL k6 and your browser actually use, or requests get blocked. `YOUR_ALB_DNS_NAME` is a placeholder you only know once the ALB exists (Step 8) — Step 8 covers updating it.

### secret.example.yaml

```bash
vim deployment/phase-15-performance-and-load-validation/app-k8s/secret.example.yaml
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

Example only — never commit real credentials into this file. Copy it to `secret.yaml` (already excluded from Git in this repository's `.gitignore` pattern for this phase) and replace the password there.

### pvc.yaml

```bash
vim deployment/phase-15-performance-and-load-validation/app-k8s/pvc.yaml
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

`storageClassName: gp3` points at the StorageClass created above. `10Gi` is larger than the 5Gi used in most other phases, giving the soak test (Step 13) more headroom for data and WAL growth over its 30-minute run.

### launchboard-postgres-deployment.yaml

```bash
vim deployment/phase-15-performance-and-load-validation/app-k8s/launchboard-postgres-deployment.yaml
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

- `strategy.type: Recreate` terminates the existing Pod before creating a new one — required for a single-writer database holding an exclusive lock on its `ReadWriteOnce` EBS volume.
- `runAsUser: 999` is the `postgres:16-alpine` image's own built-in user (confirm with `docker run --rm postgres:16-alpine id -u`).
- `PGDATA: /var/lib/postgresql/data/pgdata` points Postgres at a subdirectory of the mounted volume instead of the mount point itself. A freshly provisioned EBS volume's filesystem always contains a `lost+found` directory at its root, and `initdb` refuses to initialize a data directory it considers non-empty without this.
- `resources.limits.cpu: 1000m`/`memory: 1Gi` is more headroom than other phases give Postgres, since this phase deliberately drives real concurrent load against it.
- `readinessProbe`/`livenessProbe` run `pg_isready` rather than an HTTP check, since PostgreSQL is not an HTTP service.

### launchboard-postgres-service.yaml

```bash
vim deployment/phase-15-performance-and-load-validation/app-k8s/launchboard-postgres-service.yaml
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

`launchboard-db` becomes the DNS name other Pods use to reach PostgreSQL; the `DATABASE_URL` in the Secret depends on this exact name. `ClusterIP` keeps the database unreachable from outside the cluster, including from k6.

### launchboard-migration-job.yaml

```bash
vim deployment/phase-15-performance-and-load-validation/app-k8s/launchboard-migration-job.yaml
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
          image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-backend:phase-15
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

- `image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-backend:phase-15` is a placeholder you replace with `sed` below — it reuses the backend image because the migration container just runs `alembic upgrade head` instead of starting Uvicorn.
- A Job runs its Pod once to completion and stops, unlike a Deployment. `restartPolicy: OnFailure` retries only on failure.
- The `until python -c "import socket; ..."` loop blocks until PostgreSQL accepts TCP connections, preventing `alembic upgrade head` from running before the database is ready.

### launchboard-backend-deployment.yaml

```bash
vim deployment/phase-15-performance-and-load-validation/app-k8s/launchboard-backend-deployment.yaml
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
          image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-backend:phase-15
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

- `replicas: 2` with the HPA from this same folder (`minReplicas: 2`, `maxReplicas: 5`) is the whole point of this phase: the load and stress tests in Step 11-12 should visibly drive this Deployment to scale up.
- `runAsUser: 10001` must match the `--uid 10001 --gid 10001` pinned in `Dockerfile.backend`, or the Pod fails with `CreateContainerConfigError`.
- `rollingUpdate.maxSurge: 1`/`maxUnavailable: 0` updates Pods with zero downtime, important if you redeploy mid-test.
- `resources.requests.cpu: 100m` is the baseline the HPA's `averageUtilization: 70` target is measured against — at 100m requested, sustained usage above 70m per Pod is what triggers scale-up.

### launchboard-backend-service.yaml

```bash
vim deployment/phase-15-performance-and-load-validation/app-k8s/launchboard-backend-service.yaml
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
vim deployment/phase-15-performance-and-load-validation/app-k8s/launchboard-frontend-deployment.yaml
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
          image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-frontend:phase-15
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

`runAsUser: 101` matches the nginx user baked into the `nginxinc/nginx-unprivileged` image. The frontend has no HPA in this phase — load tests in this guide focus on backend CPU scaling, since the frontend's Nginx is comparatively cheap to serve from.

### launchboard-frontend-service.yaml

```bash
vim deployment/phase-15-performance-and-load-validation/app-k8s/launchboard-frontend-service.yaml
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

### ingress.yaml

```bash
vim deployment/phase-15-performance-and-load-validation/app-k8s/ingress.yaml
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
    alb.ingress.kubernetes.io/load-balancer-name: launchboard-phase-15
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

- `ingressClassName: alb` tells Kubernetes the AWS Load Balancer Controller installed in Step 8 should handle this resource.
- `alb.ingress.kubernetes.io/scheme: internet-facing` provisions a public ALB with a public DNS name, since k6 needs to reach it the same way a real user would.
- `alb.ingress.kubernetes.io/healthcheck-path: /healthz` points the ALB's own health check at the frontend's lightweight endpoint.
- This ALB's DNS name is the `BASE_URL` every k6 test in this guide targets.

### hpa.yaml

```bash
vim deployment/phase-15-performance-and-load-validation/app-k8s/hpa.yaml
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

This is the object the whole phase exists to exercise. `minReplicas: 2`/`maxReplicas: 5` lets the backend scale up under the load and stress tests and back down once they finish. `averageUtilization: 70` triggers scale-up once average CPU usage across backend Pods crosses 70% of the `resources.requests.cpu` value (100m) set on the Deployment. This requires Metrics Server (Step 9) to be running — without it, the HPA can see its configuration but never sees a real CPU number.

### kustomization.yaml

```bash
vim deployment/phase-15-performance-and-load-validation/app-k8s/kustomization.yaml
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

Lists every manifest so a single `kubectl apply -k` applies them all in order. `secret.example.yaml` is deliberately not listed — you apply the real `secret.yaml` separately, the same convention every phase in this repository follows for credentials.

Replace the ECR account ID and region placeholders in the three manifests that reference container images:

```bash
cd deployment/phase-15-performance-and-load-validation/app-k8s
sed -i "s|YOUR_ACCOUNT_ID|$AWS_ACCOUNT_ID|g; s|YOUR_AWS_REGION|$AWS_REGION|g" \
  launchboard-backend-deployment.yaml \
  launchboard-frontend-deployment.yaml \
  launchboard-migration-job.yaml
```

Prepare the real secret:

```bash
cp secret.example.yaml secret.yaml
vim secret.yaml
```

Replace `CHANGE_ME_STRONG_PASSWORD` in `secret.yaml` with a strong password — this is the only placeholder that file contains. `YOUR_ALB_DNS_NAME` (in `configmap.yaml`) cannot be filled in yet, since the ALB does not exist until after the first `kubectl apply` — Step 8 covers fixing it once the ALB's hostname is known.

Apply:

```bash
cd /opt/devops-launchboard/app-source
kubectl apply -f deployment/phase-15-performance-and-load-validation/app-k8s/secret.yaml
kubectl apply -k deployment/phase-15-performance-and-load-validation/app-k8s
kubectl -n devops-launchboard get pods
```

Why this step exists:

The load test needs a complete app path: ALB, frontend, backend, database, service discovery, health checks, and HPA.

Reference:

- Kustomize documentation: https://kustomize.io/

## Step 8: Install AWS Load Balancer Controller

Run:

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

eksctl create iamserviceaccount \
  --cluster devops-launchboard-phase-15 \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --role-name devops-launchboard-phase-15-alb-controller \
  --attach-policy-arn arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess \
  --approve

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=devops-launchboard-phase-15 \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

Command explanation:

- `helm repo add eks ...` registers the official AWS chart repository that hosts the controller's Helm chart.
- `eksctl create iamserviceaccount` creates an IAM role, a Kubernetes ServiceAccount in `kube-system`, and a trust relationship between them via the cluster's OIDC provider (enabled by `iam.withOIDC: true` in Step 5). This is IRSA: the controller Pod gets temporary AWS credentials through this ServiceAccount, with no access keys stored in the cluster.
- `--attach-policy-arn arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess` uses a broad AWS-managed policy as a lab shortcut. Production setups should instead use the controller's own minimal IAM policy JSON (linked below), which grants only the specific ELB/EC2 actions the controller needs instead of full ELB access.
- `helm upgrade --install` deploys the controller. `--set serviceAccount.create=false` tells Helm not to create its own ServiceAccount, since `eksctl` already created one with the IAM role attached.

Why no IAM policy file is created here, unlike Phase 8: this phase deliberately takes the broad-policy shortcut to keep focus on the performance-testing workflow. If you want the least-privilege version, follow Phase 8 Step 18's policy download and substitute its ARN above.

Wait for the controller to be ready, then get the ALB hostname:

```bash
kubectl -n kube-system rollout status deployment/aws-load-balancer-controller
kubectl -n devops-launchboard get ingress launchboard-ingress
```

The `ADDRESS` column shows the ALB's DNS name once AWS finishes provisioning it (can take a couple of minutes after the Ingress was first applied in Step 7).

Fix CORS now that the real URL is known:

```bash
ALB_DNS=$(kubectl -n devops-launchboard get ingress launchboard-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
kubectl -n devops-launchboard patch configmap launchboard-config --type merge \
  -p "{\"data\":{\"CORS_ORIGINS\":\"http://${ALB_DNS}\"}}"
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
kubectl -n devops-launchboard rollout status deployment/launchboard-backend --timeout=180s
```

Command explanation:

- `ALB_DNS=$(... jsonpath ...)` captures the live ALB hostname into a shell variable.
- `kubectl patch configmap ... --type merge` updates only the `CORS_ORIGINS` key in the existing ConfigMap, replacing the `YOUR_ALB_DNS_NAME` placeholder from Step 7.
- `kubectl rollout restart deployment/launchboard-backend` is required because ConfigMap changes never propagate to already-running Pods on their own — the backend only reads `CORS_ORIGINS` once, at startup.

Set the test URL for k6:

```bash
export BASE_URL=http://${ALB_DNS}
```

Why this step exists:

k6 should hit the same public entry point that users hit. The ALB gives a realistic public route through frontend and backend services, and the backend's CORS setting must match that exact URL or browser-style requests get blocked.

Reference:

- AWS Load Balancer Controller: https://kubernetes-sigs.github.io/aws-load-balancer-controller/
- IAM roles for service accounts: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html

## Step 9: Install Metrics Server

Create values file:

```bash
vim deployment/phase-15-performance-and-load-validation/monitoring/metrics-server-values.yaml
```

Paste:

```yaml
args:
  - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
  - --kubelet-use-node-status-port
  - --metric-resolution=15s
```

Line explanation:

- `--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname` tells metrics-server which node address type to use when connecting to each kubelet to scrape stats, in priority order. EKS worker nodes normally only have an `InternalIP`, but listing the fallbacks avoids connection failures if that ever changes.
- `--kubelet-use-node-status-port` connects to the kubelet on the port recorded in the Node object's status instead of a hardcoded port, which is more reliable across different EKS AMI versions.
- `--metric-resolution=15s` scrapes CPU/memory stats from every node every 15 seconds instead of the default 60 seconds, so the HPA (which polls metrics-server every 15 seconds by default) sees fresher numbers — useful when running short load tests where you want scaling to react quickly.

Install:

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  -f deployment/phase-15-performance-and-load-validation/monitoring/metrics-server-values.yaml
```

Command explanation:

- `helm repo add metrics-server ...` registers the official metrics-server Helm chart repository.
- `helm upgrade --install` installs the chart if it is missing or upgrades it if already present, using the values file created above. `metrics-server` is not included in EKS by default — unlike some managed Kubernetes offerings, you must install it yourself before any HPA can read CPU/memory usage.

Verify:

```bash
kubectl top nodes
kubectl top pods -n devops-launchboard
kubectl -n devops-launchboard get hpa
```

`kubectl top` only returns data once metrics-server has completed at least one scrape cycle since it started — allow 30-60 seconds after install before expecting a result. The HPA's `TARGETS` column may show `<unknown>` for the same reason immediately after the backend Pods last restarted; this resolves once metrics-server has a full sampling window for those exact Pods.

Why this step exists:

The HPA needs metrics to know when to scale. Without Metrics Server, `kubectl top` and CPU-based autoscaling usually do not work.

Reference:

- Metrics Server: https://github.com/kubernetes-sigs/metrics-server
- Kubernetes HPA: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/

## Step 10: Create k6 Smoke Test

Create:

```bash
vim deployment/phase-15-performance-and-load-validation/tests/k6/smoke-test.js
```

Paste:

```javascript
import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  vus: 1,
  duration: "30s",
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<500"]
  }
};

const baseUrl = __ENV.BASE_URL || "http://localhost";

export default function () {
  const frontend = http.get(`${baseUrl}/`);
  check(frontend, {
    "frontend returns 200": (response) => response.status === 200
  });

  const health = http.get(`${baseUrl}/health`);
  check(health, {
    "backend health returns 200": (response) => response.status === 200
  });

  const ready = http.get(`${baseUrl}/ready`);
  check(ready, {
    "backend ready returns 200": (response) => response.status === 200
  });

  sleep(1);
}
```

Line explanation:

- `import http from "k6/http"` brings in k6's built-in HTTP client — k6 test scripts are JavaScript, but run inside k6's own Go-based runtime, not Node.js.
- `export const options = { vus: 1, duration: "30s" }` runs exactly 1 virtual user continuously for 30 seconds — the minimum traffic needed to prove the app responds at all.
- `thresholds.http_req_failed: ["rate<0.01"]` fails the whole test run if more than 1% of requests error. `http_req_duration: ["p(95)<500"]` fails it if the 95th-percentile response time exceeds 500ms. k6 exits with a non-zero code if any threshold is breached, which is what makes thresholds useful in a CI pipeline, not just informational here.
- `const baseUrl = __ENV.BASE_URL || "http://localhost"` reads the `BASE_URL` environment variable passed in at run time (set in Step 8) and falls back to `localhost` if it is not set.
- `export default function () { ... }` is the function k6 calls repeatedly for each virtual user, once per iteration.
- `http.get(...)` followed by `check(response, { ... })` makes a request and records a named pass/fail assertion. Unlike thresholds, a failed `check` does not stop the test — it is recorded as a percentage in the summary output.
- `sleep(1)` pauses 1 second between iterations, simulating a human pace rather than hammering the server as fast as possible.

Run:

```bash
docker run --rm -i \
  -e BASE_URL=$BASE_URL \
  -v "$PWD:/workspace" \
  grafana/k6:latest run /workspace/deployment/phase-15-performance-and-load-validation/tests/k6/smoke-test.js
```

Command explanation:

- `docker run --rm -i` runs the official `grafana/k6` image and removes the container when it exits; `-i` keeps stdin open so k6's progress output streams to your terminal.
- `-e BASE_URL=$BASE_URL` passes your shell's `BASE_URL` variable into the container as an environment variable, which the script reads via `__ENV.BASE_URL`.
- `-v "$PWD:/workspace"` mounts your current directory (expected to be the repository root, `app-source`) into the container at `/workspace`, so k6 inside the container can read the script file from your checkout.

Why this test exists:

Smoke testing confirms the app works before adding real load. If this fails, load testing would only create noise.

## Step 11: Create k6 Load Test

Create:

```bash
vim deployment/phase-15-performance-and-load-validation/tests/k6/load-test.js
```

Paste:

```javascript
import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  stages: [
    { duration: "2m", target: 20 },
    { duration: "5m", target: 20 },
    { duration: "2m", target: 0 }
  ],
  thresholds: {
    http_req_failed: ["rate<0.02"],
    http_req_duration: ["p(95)<800", "p(99)<1500"]
  }
};

const baseUrl = __ENV.BASE_URL || "http://localhost";

export default function () {
  const responses = http.batch([
    ["GET", `${baseUrl}/`],
    ["GET", `${baseUrl}/health`],
    ["GET", `${baseUrl}/ready`]
  ]);

  check(responses[0], {
    "frontend is successful": (response) => response.status === 200
  });

  check(responses[1], {
    "health is successful": (response) => response.status === 200
  });

  check(responses[2], {
    "ready is successful": (response) => response.status === 200
  });

  sleep(1);
}
```

Line explanation:

- `options.stages` replaces the flat `vus`/`duration` from the smoke test with a ramp: 2 minutes ramping up to 20 virtual users, 5 minutes holding steady at 20, then 2 minutes ramping back down to 0. This shape — ramp up, hold, ramp down — is the standard pattern for a load test, since an instant jump to full load does not resemble how real traffic arrives.
- `thresholds` are looser than the smoke test's (`rate<0.02` instead of `0.01`, `p(95)<800` instead of `500`) because 20 concurrent users create real queueing and contention that 1 user does not.
- `http.batch([...])` fires all three requests concurrently rather than one after another, simulating a browser loading a page and its API calls in parallel instead of sequentially.
- `check(responses[0], ...)`, `check(responses[1], ...)`, `check(responses[2], ...)` validate each of the three batched responses by their array index, in the same order they were listed in `http.batch`.

Run:

```bash
docker run --rm -i \
  -e BASE_URL=$BASE_URL \
  -v "$PWD:/workspace" \
  grafana/k6:latest run /workspace/deployment/phase-15-performance-and-load-validation/tests/k6/load-test.js
```

Watch scaling in another terminal:

```bash
kubectl -n devops-launchboard get hpa -w
```

`-w` watches the HPA object and prints a new line every time it changes, so you can see `REPLICAS` increase as CPU usage rises during the 5-minute steady stage, and decrease again after the ramp-down once Kubernetes' default 5-minute scale-down stabilization window passes.

Why this test exists:

The load test simulates expected traffic. The goal is not to break the system. The goal is to prove normal traffic stays within latency and error thresholds.

## Step 12: Create k6 Stress Test

Create:

```bash
vim deployment/phase-15-performance-and-load-validation/tests/k6/stress-test.js
```

Paste:

```javascript
import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  stages: [
    { duration: "2m", target: 25 },
    { duration: "2m", target: 50 },
    { duration: "2m", target: 75 },
    { duration: "2m", target: 100 },
    { duration: "3m", target: 100 },
    { duration: "2m", target: 0 }
  ],
  thresholds: {
    http_req_failed: ["rate<0.05"],
    http_req_duration: ["p(95)<2000"]
  }
};

const baseUrl = __ENV.BASE_URL || "http://localhost";

export default function () {
  const response = http.get(`${baseUrl}/ready`);

  check(response, {
    "ready endpoint responds": (result) => result.status === 200
  });

  sleep(1);
}
```

Line explanation:

- `options.stages` steps up in 25-user increments every 2 minutes (25, 50, 75, 100), holds at 100 for 3 minutes, then ramps down. Stepping gradually instead of jumping straight to 100 users lets you see, in the HPA and `kubectl top` output, roughly which user count is where things start to degrade.
- Thresholds are loosened further (`rate<0.05`, `p(95)<2000`) because the explicit goal of a stress test is to push past comfortable operating limits — some elevated error rate and latency is expected and is the data you are trying to collect, not a failure of the test itself.
- The script only hits `/ready` (a single lightweight endpoint) instead of all three pages, so the test isolates backend capacity rather than mixing in frontend and proxy overhead.

Run:

```bash
docker run --rm -i \
  -e BASE_URL=$BASE_URL \
  -v "$PWD:/workspace" \
  grafana/k6:latest run /workspace/deployment/phase-15-performance-and-load-validation/tests/k6/stress-test.js
```

Why this test exists:

The stress test increases traffic beyond normal expectations. It helps students find where the app begins to slow down, produce errors, or scale.

## Step 13: Create k6 Soak Test

Create:

```bash
vim deployment/phase-15-performance-and-load-validation/tests/k6/soak-test.js
```

Paste:

```javascript
import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  stages: [
    { duration: "5m", target: 15 },
    { duration: "30m", target: 15 },
    { duration: "5m", target: 0 }
  ],
  thresholds: {
    http_req_failed: ["rate<0.02"],
    http_req_duration: ["p(95)<1000"]
  }
};

const baseUrl = __ENV.BASE_URL || "http://localhost";

export default function () {
  const response = http.get(`${baseUrl}/health`);

  check(response, {
    "health endpoint stays healthy": (result) => result.status === 200
  });

  sleep(2);
}
```

Line explanation:

- `options.stages` holds a moderate 15 virtual users for 30 minutes — deliberately not the highest load this app can take, since a soak test's purpose is duration, not intensity. Problems like memory growth or connection-pool exhaustion only show up after sustained time, not after a brief burst.
- Thresholds match the load test's (`rate<0.02`, `p(95)<1000`), since steady moderate traffic should perform consistently the whole way through — any threshold breach partway through a soak run is itself a finding worth recording in the report (Step 15).
- `sleep(2)` is longer than the other tests' `sleep(1)`, keeping this test's request rate gentle and sustainable for a 30-minute window.

Run:

```bash
docker run --rm -i \
  -e BASE_URL=$BASE_URL \
  -v "$PWD:/workspace" \
  grafana/k6:latest run /workspace/deployment/phase-15-performance-and-load-validation/tests/k6/soak-test.js
```

Why this test exists:

The soak test checks whether the app stays healthy over time. It can reveal slow memory growth, database connection exhaustion, or gradual latency increases.

Reference:

- k6 thresholds: https://grafana.com/docs/k6/latest/using-k6/thresholds/
- k6 test life cycle: https://grafana.com/docs/k6/latest/using-k6/test-lifecycle/

## Step 14: Capture Metrics During Tests

Run while k6 is active:

```bash
kubectl -n devops-launchboard top pods
kubectl -n devops-launchboard get hpa
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard logs deploy/launchboard-backend --tail=50
```

Expected:

```text
Backend pods stay ready.
Error rate stays below threshold.
HPA scales backend if CPU increases.
No repeated crash loops appear.
```

Why this step exists:

k6 tells you how users experience the app. Kubernetes metrics tell you how the infrastructure responds. Students need both views.

## Step 15: Create Performance Report

Create:

```bash
vim deployment/phase-15-performance-and-load-validation/reports/performance-report-template.md
```

Paste:

````markdown
# Performance Report

## Test Context

| Item | Value |
| --- | --- |
| Date |  |
| Tester |  |
| AWS Region |  |
| Cluster Name | devops-launchboard-phase-15 |
| Backend Image Tag | phase-15 |
| Frontend Image Tag | phase-15 |
| Test Tool | k6 |

## Environment

| Component | Configuration |
| --- | --- |
| EKS Nodes |  |
| Backend Replicas |  |
| Frontend Replicas |  |
| HPA Min/Max |  |
| Database | PostgreSQL pod with EBS PVC |

## Results

| Test | Target Load | p95 Latency | p99 Latency | Error Rate | Pass/Fail |
| --- | ---: | ---: | ---: | ---: | --- |
| Smoke | 1 VU |  |  |  |  |
| Load | 20 VUs |  |  |  |  |
| Stress | 100 VUs |  |  |  |  |
| Soak | 15 VUs for 30m |  |  |  |  |

## Observations

```text
Write what changed during the test.
Example: backend HPA scaled from 2 pods to 4 pods after CPU increased.
```

## Bottlenecks

```text
Write the slowest part of the system.
Example: backend CPU reached 90 percent before HPA added pods.
```

## Tuning Actions

```text
Write what you changed after the test.
Example: increased backend memory limit from 512Mi to 768Mi.
```

## Final Decision

```text
Pass or fail the deployment for production-like traffic.
```
````

Section explanation:

- `Test Context` and `Environment` record exactly what was running, so a report from two months ago is still meaningful — image tags, replica counts, and node types all affect results, and "fast" or "slow" means nothing without them.
- `Results` is filled in directly from each test's k6 summary output, which prints `p(95)`, `p(99)`, and the failure rate for `http_req_duration`/`http_req_failed` when the run finishes.
- `Observations` and `Bottlenecks` are where you write down what you watched happen live — HPA scaling events from `kubectl get hpa -w`, CPU from `kubectl top pods`, anything in the backend logs — not just the final k6 numbers.
- `Final Decision` forces an explicit pass/fail call. A performance test that produces numbers but no decision has not actually validated anything.

Copy it for your final result:

```bash
cp deployment/phase-15-performance-and-load-validation/reports/performance-report-template.md \
  deployment/phase-15-performance-and-load-validation/reports/performance-report.md
vim deployment/phase-15-performance-and-load-validation/reports/performance-report.md
```

The template stays unmodified as a reusable starting point; `performance-report.md` is the filled-in copy specific to this test run.

Why this report exists:

Performance validation is not finished when the command ends. The student should record load level, latency, errors, HPA behavior, bottlenecks, and whether the deployment passed.

## Troubleshooting

Problem: k6 cannot reach the app.

Cause:

```text
ALB is not ready, BASE_URL is wrong, or security routing is incomplete.
```

Fix:

```bash
kubectl -n devops-launchboard get ingress
curl -I $BASE_URL
curl -I $BASE_URL/health
```

Problem: HPA does not scale.

Cause:

```text
Metrics Server is missing, CPU is not high enough, or pod resource requests are missing.
```

Fix:

```bash
kubectl top nodes
kubectl -n devops-launchboard top pods
kubectl -n devops-launchboard describe hpa launchboard-backend
```

Problem: latency is high.

Cause:

```text
Backend CPU, database connection limits, pod startup time, or ALB warm-up may be bottlenecks.
```

Fix:

```bash
kubectl -n devops-launchboard top pods
kubectl -n devops-launchboard logs deploy/launchboard-backend --tail=100
kubectl -n devops-launchboard describe pod POD_NAME
```

Problem: error rate rises during stress test.

Cause:

```text
The system is past its safe capacity.
```

Fix:

```text
Record the breaking point.
Reduce traffic.
Tune resources.
Increase replicas.
Repeat the test.
```

## Cleanup

Delete app:

```bash
kubectl delete -f deployment/phase-15-performance-and-load-validation/app-k8s/secret.yaml
kubectl delete -k deployment/phase-15-performance-and-load-validation/app-k8s
```

Delete cluster:

```bash
eksctl delete cluster -f deployment/phase-15-performance-and-load-validation/cluster/eksctl-cluster.yaml
```

Delete ECR repositories:

```bash
aws ecr delete-repository --repository-name launchboard-backend --force --region $AWS_REGION
aws ecr delete-repository --repository-name launchboard-frontend --force --region $AWS_REGION
```

Why cleanup matters:

Performance labs can create cloud charges through EKS, EC2, EBS, ALB, ECR, CloudWatch logs, and data transfer.

## Production Checklist

```text
[ ] AWS credentials configured
[ ] Repository cloned with SSH
[ ] EKS cluster created
[ ] ECR repositories created
[ ] Images built and pushed
[ ] Application deployed
[ ] ALB URL available
[ ] Metrics Server installed
[ ] HPA visible
[ ] Smoke test passed
[ ] Load test passed
[ ] Stress test completed
[ ] Soak test completed
[ ] Pod CPU and memory checked
[ ] HPA behavior recorded
[ ] Error rate recorded
[ ] p95 and p99 latency recorded
[ ] Performance report completed
[ ] Cleanup completed
```

## Reference Documentation

| Topic | Official Link |
| --- | --- |
| k6 | https://grafana.com/docs/k6/latest/ |
| k6 thresholds | https://grafana.com/docs/k6/latest/using-k6/thresholds/ |
| Metrics Server | https://github.com/kubernetes-sigs/metrics-server |
| Kubernetes HPA | https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/ |
| EKS | https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html |
| ECR | https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html |
| AWS Load Balancer Controller | https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/ |

## Next Step

Move to:

```text
Phase 16: Production Capstone
```

Why:

You have now used every tool in the journey: Docker, Compose, Swarm, Kubernetes, EKS, CI/CD, Terraform, Ansible, observability, security, advanced deployments, disaster recovery, and load testing. The capstone assembles the best pieces into one production-grade deployment — the way you would actually run this application for real users.
