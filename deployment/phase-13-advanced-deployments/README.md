# Phase 13: Advanced Deployment Strategies

## Fresh Start Assumption

This phase starts from a clean machine and a clean AWS setup.

You do not need to finish any previous phase before using this phase.

This guide assumes:

- You have an AWS account.
- You have GitHub access to this repository.
- You will clone the repository with SSH.
- You will create a new EKS cluster for this phase.
- You will create fresh ECR repositories.
- You will build fresh frontend and backend Docker images.
- You will deploy the application to Kubernetes first.
- You will then practice blue-green deployments, canary releases, and feature flags.
- You will type commands manually.
- You will use `vim` to create files.
- You will not use custom shell scripts for deployment automation.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What This Phase Deploys

This phase deploys the N-tier application on Amazon EKS and then practices safer release strategies.

The deployment includes:

- Vite frontend served by Nginx
- FastAPI backend
- PostgreSQL database running inside Kubernetes for the lab
- Amazon ECR repositories
- Amazon EKS cluster
- AWS Load Balancer Controller
- Blue-green backend release
- Argo Rollouts canary backend release
- Feature flag ConfigMap
- Manual verification and rollback commands

## When To Use This Architecture

Use this architecture when:

- You need safer releases than a normal rolling update.
- You want to test a new backend version before sending all users to it.
- You need a fast rollback path.
- You want to compare blue-green, canary, and feature-flag release styles.
- You are running a production Kubernetes application.
- Your team can monitor logs, health checks, and user impact during deployment.

Do not use this architecture when:

- The app is a tiny one-person demo.
- The team cannot afford the extra pods during blue-green releases.
- You do not have monitoring or clear health checks.
- You need the simplest possible deployment path.

Simple decision guide:

| Strategy | Best For | Tradeoff |
| --- | --- | --- |
| Rolling update | Normal low-risk updates | Slower rollback and mixed versions during rollout |
| Blue-green | Fast switch and fast rollback | Runs two versions at the same time |
| Canary | Gradual traffic exposure | Needs careful monitoring |
| Feature flags | Turning features on or off without redeploying | App code must support the flag |

## Database Note: Why Still A Pod And Not RDS?

This phase runs PostgreSQL as a Pod on an EBS volume, even though the production answer is a managed database. That is deliberate: this phase's lessons need a database *inside* the cluster: blue-green and canary strategies need a stable stateful backend both app versions share, and keeping it in-cluster keeps this already-busy phase self-contained. The managed-database pattern has its own homes in this track — Phase 9 (Terraform production) provisions RDS as code, and Phase 16 (capstone) runs the full Kubernetes stack against RDS with the security groups, `DB_HOST` wiring, and backup division of labor spelled out. If you want RDS here, the capstone's "Create The Database First" section is a drop-in recipe: create the instance, remove the postgres Deployment/Service/PVC from the kustomization, point `DATABASE_URL` and the wait loops at the RDS endpoint.

## Recommended AWS Setup

| Item | Recommended Value |
| --- | --- |
| AWS Region | `us-east-1` or the closest region |
| Cluster Name | `devops-launchboard-phase-13` |
| Kubernetes Version | `1.34` |
| Node Type | `t3.medium` |
| Desired Nodes | `2` |
| Minimum Nodes | `2` |
| Maximum Nodes | `4` |
| Node Storage | `30 GB gp3` |
| ECR Backend Repo | `launchboard-backend` |
| ECR Frontend Repo | `launchboard-frontend` |
| Public Access | Through AWS Application Load Balancer |

Cost warning:

- EKS has a cluster hourly cost.
- EC2 worker nodes cost money.
- EBS volumes cost money.
- Load balancers cost money.
- Blue-green releases temporarily run extra backend pods.
- Delete resources after practice.

Reference:

- AWS EKS pricing: https://aws.amazon.com/eks/pricing/
- AWS Budgets: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html

## Architecture

```text
Browser
  |
  v
AWS Application Load Balancer
  |
  v
Frontend service
  |
  v
Frontend pods
  |
  | /api
  v
Backend service
  |
  | blue-green mode selects blue or green pods
  | canary mode lets Argo Rollouts gradually replace pods
  v
Backend pods
  |
  v
PostgreSQL service and pod
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

Install missing tools from official docs:

- Git: https://git-scm.com/downloads
- Docker: https://docs.docker.com/get-docker/
- AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- kubectl: https://kubernetes.io/docs/tasks/tools/
- eksctl: https://eksctl.io/installation/
- Helm: https://helm.sh/docs/intro/install/

Why this step exists:

The cluster runs in AWS, images are built with Docker, and Kubernetes files are applied with `kubectl`. If these tools are missing, students cannot complete the phase.

## Step 2: Configure AWS Credentials

Run:

```bash
aws configure
aws sts get-caller-identity
```

Set helpful variables:

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

Why this step exists:

AWS commands need credentials and a region. The variables keep later commands shorter and reduce typing mistakes.

Reference:

- AWS CLI quickstart: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html

## Step 3: Create SSH Key For GitHub

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-13" -f ~/.ssh/devops_launchboard_phase_13
cat ~/.ssh/devops_launchboard_phase_13.pub
```

Add the printed public key to GitHub:

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
  IdentityFile ~/.ssh/devops_launchboard_phase_13
  IdentitiesOnly yes
```

Secure and test:

```bash
chmod 600 ~/.ssh/config
chmod 600 ~/.ssh/devops_launchboard_phase_13
chmod 644 ~/.ssh/devops_launchboard_phase_13.pub
ssh -T git@github.com
```

Why this step exists:

The repository uses an SSH URL. GitHub must trust your public key before your machine can clone the code.

Reference:

- GitHub SSH docs: https://docs.github.com/en/authentication/connecting-to-github-with-ssh

## Step 4: Clone The Repository

Run:

```bash
sudo mkdir -p /opt/devops-launchboard
sudo chown -R $USER:$USER /opt/devops-launchboard
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

The application code, Dockerfiles, and deployment files must exist locally before we build images or deploy to Kubernetes.

## Step 5: Create Phase 13 Folders

Run:

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-13-advanced-deployments/cluster
mkdir -p deployment/phase-13-advanced-deployments/ecr
mkdir -p deployment/phase-13-advanced-deployments/app-k8s
mkdir -p deployment/phase-13-advanced-deployments/blue-green
mkdir -p deployment/phase-13-advanced-deployments/canary
mkdir -p deployment/phase-13-advanced-deployments/feature-flags
```

Why these folders exist:

- `cluster` contains the EKS cluster file.
- `ecr` contains image cleanup policy.
- `app-k8s` contains the normal app deployment.
- `blue-green` contains two backend versions and the active service.
- `canary` contains the Argo Rollout.
- `feature-flags` contains runtime flag settings.

## Step 6: Create EKS Cluster File

Run:

```bash
vim deployment/phase-13-advanced-deployments/cluster/eksctl-cluster.yaml
```

Paste:

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: devops-launchboard-phase-13
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
      Environment: phase-13
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

Replace `YOUR_AWS_REGION` and create the cluster:

```bash
eksctl create cluster -f deployment/phase-13-advanced-deployments/cluster/eksctl-cluster.yaml
kubectl get nodes
```

Line explanation:

- `metadata.version: "1.34"` pins the Kubernetes version, quoted because YAML would otherwise read `1.34` as a number.
- `iam.withOIDC: true` creates an OIDC provider — the foundation of IAM Roles for Service Accounts (IRSA), which lets Kubernetes ServiceAccounts assume IAM roles without storing AWS credentials in the cluster. The EBS CSI driver and the AWS Load Balancer Controller both need this.
- `vpc.nat.gateway: Single` creates one shared NAT Gateway instead of one per AZ, at roughly half the cost.
- `managedNodeGroups[0].privateNetworking: true` keeps worker nodes in private subnets with no public IPs; all inbound traffic goes through the ALB.
- `cloudWatch.clusterLogging.enableTypes` ships control plane logs (API server, audit, authenticator, controller manager, scheduler) to CloudWatch Logs, useful when debugging why a blue-green or canary rollout did not behave as expected.
- `addons[0].name: aws-ebs-csi-driver` installs the EBS CSI driver as an EKS managed add-on; without it, PVCs requesting storage stay `Pending` forever.

This file creates the Kubernetes platform for the phase. Private worker networking, OIDC, EBS CSI, and control plane logs are production-minded settings that support safer deployments and debugging.

Reference:

- eksctl ClusterConfig schema: https://eksctl.io/usage/schema/

## Step 7: Create ECR Repositories

Run:

```bash
aws ecr create-repository --repository-name launchboard-backend --region $AWS_REGION
aws ecr create-repository --repository-name launchboard-frontend --region $AWS_REGION
```

Create lifecycle policy:

```bash
vim deployment/phase-13-advanced-deployments/ecr/lifecycle-policy.json
```

Paste:

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep the latest 10 phase 13 images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["phase-13"],
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
  --lifecycle-policy-text file://deployment/phase-13-advanced-deployments/ecr/lifecycle-policy.json \
  --region $AWS_REGION

aws ecr put-lifecycle-policy \
  --repository-name launchboard-frontend \
  --lifecycle-policy-text file://deployment/phase-13-advanced-deployments/ecr/lifecycle-policy.json \
  --region $AWS_REGION
```

Line explanation:

- `rulePriority: 1` keeps only the 10 most recent images tagged with the `phase-13` prefix (which also matches `phase-13-blue`, `phase-13-green`, and `phase-13-canary` since ECR prefix matching is a string prefix, not an exact match) — older ones beyond the 10 most recent are expired automatically.
- `rulePriority: 2` deletes untagged images (orphaned layers left behind when a tag is moved or overwritten) after 7 days.
- `put-lifecycle-policy` attaches this same policy to both repositories, so neither one accumulates old release images forever.

Why this step exists:

Advanced releases create multiple image tags. Lifecycle policy keeps the registry clean so old release images do not pile up forever.

Reference:

- Amazon ECR lifecycle policies: https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html

## Step 8: Create Production Dockerfiles

Create:

```bash
vim deployment/phase-13-advanced-deployments/Dockerfile.backend
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
- `COPY backend/pyproject.toml backend/alembic.ini ./` copies dependency definitions before source code — a Docker layer-caching trick: unchanged dependencies mean a cached, faster rebuild.
- `RUN pip install --no-cache-dir .` installs the app and its base dependencies; Alembic is a base dependency, not a dev extra, so this is enough for the migration Job too.
- `groupadd`/`useradd` pin an explicit `--uid 10001 --gid 10001` so the numeric UID is deterministic and matches the Kubernetes `securityContext`, instead of relying on whatever UID the system auto-assigns to a name-only `USER app`.
- `USER app` switches to the non-root user for the rest of the image.
- `CMD [...]` starts Uvicorn with `--proxy-headers` so it trusts the `X-Forwarded-*` headers added by the ALB and the frontend Nginx in front of it.

Create:

```bash
vim deployment/phase-13-advanced-deployments/Dockerfile.frontend
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

COPY deployment/phase-13-advanced-deployments/nginx-frontend.conf /etc/nginx/conf.d/default.conf
COPY --from=builder --chown=101:101 /app/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

This uses the `nginxinc/nginx-unprivileged` image (UID 101), consistent with the other phases, instead of a plain `nginx:alpine` image with a manually created user.

Create:

```bash
vim deployment/phase-13-advanced-deployments/nginx-frontend.conf
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
- `location = /healthz` returns a plain `200 ok` without hitting the backend — what Kubernetes probes and the ALB health check both look at.
- `location /api/`, `location = /health`, and `location = /ready` proxy those paths to `http://launchboard-backend:8000/...`, the backend's Kubernetes Service DNS name.
- `location / { try_files $uri $uri/ /index.html; }` falls back to `index.html` for any unmatched path, required for React Router to handle direct navigation to client-side routes.

Why these files exist:

The backend and frontend images are built the same way every time. Multi-stage builds keep runtime images smaller, non-root users reduce container risk, and health checks let Kubernetes verify each release.

Reference:

- Dockerfile reference: https://docs.docker.com/reference/dockerfile/
- Nginx unprivileged image: https://hub.docker.com/r/nginxinc/nginx-unprivileged

## Step 9: Build And Push Images

Set a short variable for the registry URL so the commands below stay readable:

```bash
ECR_REGISTRY=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
```

Log in to ECR:

```bash
aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin $ECR_REGISTRY
```

Line explanation:

- `ECR_REGISTRY=...` builds the registry hostname once (`123456789012.dkr.ecr.us-east-1.amazonaws.com`) so every later command can reference `$ECR_REGISTRY` instead of repeating the full account ID and region.
- `aws ecr get-login-password --region $AWS_REGION` asks AWS for a short-lived authentication token tied to your IAM credentials.
- The `|` pipes that token into `docker login`. `--username AWS` is always the literal string `AWS` for ECR — it is not your IAM username. `--password-stdin` reads the token from the pipe instead of putting it on the command line, where it could end up in shell history.

Build images:

```bash
docker build -f deployment/phase-13-advanced-deployments/Dockerfile.backend \
  -t launchboard-backend:phase-13 .

docker build -f deployment/phase-13-advanced-deployments/Dockerfile.frontend \
  --build-arg VITE_API_URL=/api \
  -t launchboard-frontend:phase-13 .
```

Line explanation:

- `-f deployment/phase-13-advanced-deployments/Dockerfile.backend` points Docker at this phase's own Dockerfile rather than the default `./Dockerfile`.
- The trailing `.` on each command is the build context — the directory Docker reads `COPY` instructions relative to. It must be the repository root, because the Dockerfiles `COPY backend/...` and `COPY frontend/...`.
- `-t launchboard-backend:phase-13` tags the image locally with a name and tag before it has any relationship to ECR at all; the registry hostname is added separately in the tagging step below.
- `--build-arg VITE_API_URL=/api` on the frontend build embeds a relative API path into the compiled JavaScript at build time, so the frontend calls `/api/...` and lets Nginx proxy it to the backend rather than hardcoding a hostname.

Create release tags. This phase needs five different tags on the same two images: one plain release tag per image, plus `-blue`, `-green`, and `-canary` variants of the backend image so each release-strategy step in this phase has its own image to point at:

```bash
docker tag launchboard-backend:phase-13 $ECR_REGISTRY/launchboard-backend:phase-13
docker tag launchboard-backend:phase-13 $ECR_REGISTRY/launchboard-backend:phase-13-blue
docker tag launchboard-backend:phase-13 $ECR_REGISTRY/launchboard-backend:phase-13-green
docker tag launchboard-backend:phase-13 $ECR_REGISTRY/launchboard-backend:phase-13-canary
docker tag launchboard-frontend:phase-13 $ECR_REGISTRY/launchboard-frontend:phase-13
```

Line explanation:

- `docker tag <local-name> <new-name>` does not copy or rebuild anything — it just adds a second name pointing at the same image bytes already on disk. That is why all four backend lines are instant: they are four labels on one image.
- `$ECR_REGISTRY/launchboard-backend:phase-13` is the full name `docker push` needs: registry hostname, repository name, and tag, in that order.
- The `-blue`, `-green`, and `-canary` tags exist only so Step 12 and Step 13 have distinct image references to deploy under each release strategy. In this lab they point at identical image bytes; in real production, you would build `-green` or `-canary` from a newer commit so the new version is actually different code.

Push every tag to ECR:

```bash
docker push $ECR_REGISTRY/launchboard-backend:phase-13
docker push $ECR_REGISTRY/launchboard-backend:phase-13-blue
docker push $ECR_REGISTRY/launchboard-backend:phase-13-green
docker push $ECR_REGISTRY/launchboard-backend:phase-13-canary
docker push $ECR_REGISTRY/launchboard-frontend:phase-13
```

Line explanation:

- Each `docker push` uploads one tag to its ECR repository. Because all four backend tags reference the same underlying image layers, Docker uploads the actual layer data once and the remaining pushes only need to register the new tag name — they finish almost instantly after the first.
- After this step, `aws ecr describe-images --repository-name launchboard-backend --region $AWS_REGION` would list four tags (`phase-13`, `phase-13-blue`, `phase-13-green`, `phase-13-canary`) all pointing at the same image digest.

Why this step exists:

Blue-green and canary releases compare versions. For a lab, these tags may point to the same code. In real production, `green` or `canary` would usually be a newer build.

Reference:

- Push images to ECR: https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html

## Step 10: Deploy The Base Application

All manifests go inside `deployment/phase-13-advanced-deployments/app-k8s/`. Every container here already sets `allowPrivilegeEscalation: false` and drops all Linux capabilities, the same hardened baseline introduced in Phase 12, so that the safer-release techniques in this phase build on top of an already security-conscious deployment.

#### namespace.yaml

```bash
vim deployment/phase-13-advanced-deployments/app-k8s/namespace.yaml
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

#### storageclass.yaml

```bash
vim deployment/phase-13-advanced-deployments/app-k8s/storageclass.yaml
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

`parameters.encrypted: "true"` enables EBS encryption at rest at no extra cost. `volumeBindingMode: WaitForFirstConsumer` delays volume creation until a Pod is scheduled, so the EBS volume lands in the same AZ as the Pod's node.

#### configmap.yaml

```bash
vim deployment/phase-13-advanced-deployments/app-k8s/configmap.yaml
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

`CORS_ORIGINS` is a placeholder because the ALB DNS name does not exist until AWS creates the load balancer; you update it once the Ingress is applied later in this step.

#### secret.example.yaml

```bash
vim deployment/phase-13-advanced-deployments/app-k8s/secret.example.yaml
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

Example only — copy it to a real Secret and replace the placeholder password.

#### pvc.yaml

```bash
vim deployment/phase-13-advanced-deployments/app-k8s/pvc.yaml
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
vim deployment/phase-13-advanced-deployments/app-k8s/launchboard-postgres-deployment.yaml
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

`runAsUser: 999` is the `postgres:16-alpine` image's own built-in user (confirm with `docker run --rm postgres:16-alpine id -u`). `strategy.type: Recreate` is required because a single-writer database cannot run two Pods against the same `ReadWriteOnce` volume. `PGDATA: /var/lib/postgresql/data/pgdata` points Postgres at a subdirectory of the mounted volume rather than the mount point itself — a freshly provisioned EBS volume's filesystem always contains a `lost+found` directory at its root, and `initdb` refuses to initialize a data directory it considers non-empty, crash-looping the Pod without this.

#### launchboard-postgres-service.yaml

```bash
vim deployment/phase-13-advanced-deployments/app-k8s/launchboard-postgres-service.yaml
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

`launchboard-db` becomes the DNS name in `DATABASE_URL`; `ClusterIP` keeps the database unreachable from outside the cluster.

#### launchboard-migration-job.yaml

```bash
vim deployment/phase-13-advanced-deployments/app-k8s/launchboard-migration-job.yaml
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
          image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-backend:phase-13
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

`image` pulls from your private ECR repository — replace both placeholders, e.g. `123456789012.dkr.ecr.us-east-1.amazonaws.com/launchboard-backend:phase-13`. A Job runs its Pod once to completion and stops, unlike a Deployment; `restartPolicy: OnFailure` retries only on failure.

#### launchboard-backend-deployment.yaml

```bash
vim deployment/phase-13-advanced-deployments/app-k8s/launchboard-backend-deployment.yaml
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
          image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-backend:phase-13
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

This is the Deployment you practice blue-green and canary releases against in Steps 12-13. `runAsUser: 10001` must match the `--uid 10001 --gid 10001` pinned in the Dockerfile, or the Pod fails with `CreateContainerConfigError`. `rollingUpdate.maxSurge: 1` / `maxUnavailable: 0` updates Pods with zero downtime under a normal rolling update — the baseline this phase's safer-release strategies improve on.

#### launchboard-backend-service.yaml

```bash
vim deployment/phase-13-advanced-deployments/app-k8s/launchboard-backend-service.yaml
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

`launchboard-backend` becomes the DNS name the frontend's Nginx config proxies `/api`, `/health`, and `/ready` to. The blue-green and canary steps later in this phase add their own Services and re-point traffic between them; this one stays as the steady baseline.

#### launchboard-frontend-deployment.yaml

```bash
vim deployment/phase-13-advanced-deployments/app-k8s/launchboard-frontend-deployment.yaml
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
          image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-frontend:phase-13
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

`runAsUser: 101` matches the nginx user baked into the `nginxinc/nginx-unprivileged` image.

#### launchboard-frontend-service.yaml

```bash
vim deployment/phase-13-advanced-deployments/app-k8s/launchboard-frontend-service.yaml
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
vim deployment/phase-13-advanced-deployments/app-k8s/ingress.yaml
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
    alb.ingress.kubernetes.io/load-balancer-name: launchboard-phase-13
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

`spec.ingressClassName: alb` tells the AWS Load Balancer Controller installed in Step 11 to handle this Ingress and create a real Application Load Balancer.

#### hpa.yaml

```bash
vim deployment/phase-13-advanced-deployments/app-k8s/hpa.yaml
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

If average backend CPU usage exceeds 70% of requested CPU, the HPA scales up to a maximum of 5 Pods. EKS includes the Metrics Server by default, so this works immediately.

#### kustomization.yaml

```bash
vim deployment/phase-13-advanced-deployments/app-k8s/kustomization.yaml
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

Lists every manifest so one `kubectl apply -k` applies them all in order. `secret.example.yaml` is deliberately not listed — the real Secret is created separately.

Reference:

- Kubernetes Deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
- Kustomize documentation: https://kustomize.io/

Replace placeholders and create the real Secret:

```bash
cd /opt/devops-launchboard/app-source
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

sed -i "s|YOUR_ACCOUNT_ID|${ACCOUNT_ID}|g; s|YOUR_AWS_REGION|${AWS_REGION}|g" \
  deployment/phase-13-advanced-deployments/app-k8s/launchboard-backend-deployment.yaml \
  deployment/phase-13-advanced-deployments/app-k8s/launchboard-migration-job.yaml \
  deployment/phase-13-advanced-deployments/app-k8s/launchboard-frontend-deployment.yaml

cp deployment/phase-13-advanced-deployments/app-k8s/secret.example.yaml \
   deployment/phase-13-advanced-deployments/app-k8s/secret.yaml
vim deployment/phase-13-advanced-deployments/app-k8s/secret.yaml
```

Line explanation:

- `sed -i "s|YOUR_ACCOUNT_ID|${ACCOUNT_ID}|g; ..."` edits the three manifests in place, replacing every occurrence of the two placeholder strings with your real account ID and region — these are the manifests that contain ECR image references.
- `cp secret.example.yaml secret.yaml` makes a working copy of the example so the placeholder file itself stays untouched in Git; `secret.yaml` is the one you actually edit and apply.

Replace `CHANGE_ME_STRONG_PASSWORD` in `secret.yaml` with a real password (both occurrences), then apply:

```bash
kubectl apply -f deployment/phase-13-advanced-deployments/app-k8s/secret.yaml
kubectl apply -k deployment/phase-13-advanced-deployments/app-k8s
kubectl -n devops-launchboard get pods
```

Line explanation:

- `kubectl apply -f .../secret.yaml` creates the Secret first, separately from the kustomization, since `secret.yaml` is intentionally not listed in `kustomization.yaml`.
- `kubectl apply -k .../app-k8s` then applies every manifest in `kustomization.yaml` together — namespace, storage class, ConfigMap, PVC, both Deployments and Services, the migration Job, the Ingress, and the HPA — in the order listed.
- `kubectl -n devops-launchboard get pods` confirms Pods are being created; expect to see `launchboard-db`, `launchboard-migrate` (briefly, until it completes), `launchboard-backend`, and `launchboard-frontend`.

Why this step exists:

Advanced releases need a normal working application first. Students should verify the app works before practicing blue-green or canary updates.

## Step 11: Install AWS Load Balancer Controller

Run:

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update
```

Create controller service account:

```bash
eksctl create iamserviceaccount \
  --cluster devops-launchboard-phase-13 \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --role-name devops-launchboard-phase-13-alb-controller \
  --attach-policy-arn arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess \
  --approve
```

Install:

```bash
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=devops-launchboard-phase-13 \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

Verify:

```bash
kubectl -n devops-launchboard get ingress
```

Command explanation:

- `eksctl create iamserviceaccount` creates an IAM role, a Kubernetes ServiceAccount in `kube-system`, and a trust relationship between them via the cluster's OIDC provider (IRSA) — the controller Pod automatically receives temporary credentials for the role, with no access keys stored in the cluster.
- `--attach-policy-arn arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess` uses a broad AWS managed policy for simplicity in this phase, since the focus here is release strategy, not IAM hardening. Phase 12 walks through downloading the controller's official least-privilege policy instead and attaching a custom policy scoped to only what the controller needs — worth doing here too if you want stricter IAM alongside blue-green and canary practice.
- `helm upgrade --install` deploys the controller from the official EKS Helm chart repository; `--set serviceAccount.create=false` tells Helm to use the ServiceAccount `eksctl` already created instead of making its own.

Why this step exists:

The Ingress file asks for public traffic routing. The AWS Load Balancer Controller creates the real ALB in AWS — without it running, the Ingress sits idle with no `ADDRESS`.

Reference:

- AWS Load Balancer Controller: https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/
- IRSA: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html

## Step 12: Blue-Green Deployment

Blue-green means two versions run at the same time:

- `blue` is the current stable version.
- `green` is the new version.
- A service selector decides which version receives traffic.

Create:

```bash
vim deployment/phase-13-advanced-deployments/blue-green/active-backend-service.yaml
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
    track: blue
  ports:
    - name: http
      port: 8000
      targetPort: 8000
```

Create:

```bash
vim deployment/phase-13-advanced-deployments/blue-green/blue-deployment.yaml
```

Paste:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: launchboard-backend-blue
  namespace: devops-launchboard
  labels:
    app: launchboard-backend
    track: blue
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
      track: blue
  template:
    metadata:
      labels:
        app: launchboard-backend
        track: blue
    spec:
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: backend
          image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-backend:phase-13-blue
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

`labels.track: blue` and `selector.matchLabels.track: blue` are what separates this Deployment from `green` below — both carry `app: launchboard-backend` so either can be selected by the `active-backend-service.yaml` Service created above, but only one `track` value at a time.

```bash
vim deployment/phase-13-advanced-deployments/blue-green/green-deployment.yaml
```

Paste the same content as `blue-deployment.yaml`, but change every occurrence of `blue` to `green`: `metadata.name: launchboard-backend-green`, `labels.track: green`, `selector.matchLabels.track: green`, `template.metadata.labels.track: green`, and the image tag `:phase-13-green`.

```bash
vim deployment/phase-13-advanced-deployments/blue-green/kustomization.yaml
```

Paste:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - blue-deployment.yaml
  - green-deployment.yaml
  - active-backend-service.yaml
```

This groups the two track Deployments with the Service that switches between them, so `kubectl apply -k` applies all three together.

Deploy blue-green:

```bash
kubectl -n devops-launchboard delete deployment launchboard-backend

kubectl apply -k deployment/phase-13-advanced-deployments/blue-green

kubectl -n devops-launchboard get pods -l app=launchboard-backend --show-labels
kubectl -n devops-launchboard describe service launchboard-backend
```

Line explanation:

- `kubectl delete deployment launchboard-backend` removes the single normal Deployment created in Step 10. It must go first: that Deployment's Pods carry the label `app: launchboard-backend` with no `track` label, which would otherwise also match the `active-backend-service.yaml` Service's selector and mix in with the blue/green Pods.
- `kubectl apply -k .../blue-green` creates `launchboard-backend-blue`, `launchboard-backend-green`, and re-applies the Service from the kustomization.
- `--show-labels` on the `get pods` command prints each Pod's full label set in the output, so you can see the `track=blue` / `track=green` labels directly instead of guessing which Pod belongs to which version.
- `describe service` prints the Service's `Endpoints` field — the actual Pod IPs currently receiving traffic — which is the fastest way to confirm which track is live.

Switch traffic to green:

```bash
kubectl -n devops-launchboard patch service launchboard-backend \
  -p '{"spec":{"selector":{"app":"launchboard-backend","track":"green"}}}'

kubectl -n devops-launchboard describe service launchboard-backend
```

Line explanation:

- `kubectl patch service ... -p '{...}'` merges the given JSON into the Service's existing spec rather than replacing the whole object. Here it overwrites just `spec.selector`, changing `track` from `blue` to `green`.
- The moment this patch applies, the Service's `Endpoints` switch from the blue Pods' IPs to the green Pods' IPs — traffic redirects instantly because both sets of Pods were already running and passing their readiness probes before the switch.
- `describe service` again confirms the `Endpoints` field now lists the green Pods' IPs.

Rollback to blue:

```bash
kubectl -n devops-launchboard patch service launchboard-backend \
  -p '{"spec":{"selector":{"app":"launchboard-backend","track":"blue"}}}'

kubectl -n devops-launchboard describe service launchboard-backend
```

This is the same patch command with `track` set back to `blue`. Rollback is just as instant as the forward switch, for the same reason: the blue Pods never stopped running, so there is nothing to wait for.

Why this works:

Kubernetes Services route traffic to pods that match their selector. Blue and green pods both exist, but only the selected `track` receives traffic. Rollback is fast because the old pods are still running.

Reference:

- Kubernetes Services: https://kubernetes.io/docs/concepts/services-networking/service/
- Kubernetes Deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/

## Step 13: Canary Deployment With Argo Rollouts

Install Argo Rollouts controller:

```bash
kubectl create namespace argo-rollouts

kubectl apply -n argo-rollouts \
  -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

kubectl -n argo-rollouts get pods
```

Line explanation:

- `kubectl create namespace argo-rollouts` creates a dedicated namespace for the controller, separate from `devops-launchboard` where the app runs — the controller manages Rollouts across every namespace in the cluster, so it does not need to live alongside the app it manages.
- `kubectl apply -n argo-rollouts -f https://...install.yaml` installs the controller itself: a Deployment, CRDs (including the `Rollout` kind used below), RBAC roles, and a metrics service, all bundled in one manifest maintained by the Argo project.
- `kubectl -n argo-rollouts get pods` confirms the controller Pod reaches `Running` before you create any Rollout — if it never starts, applying a `Rollout` resource later would have nothing to act on it.

Install the Argo Rollouts kubectl plugin from the official guide:

```text
https://argo-rollouts.readthedocs.io/en/stable/installation/#kubectl-plugin-installation
```

The plugin adds the `kubectl argo rollouts` subcommands used later in this step (`promote`, `abort`, and the `get rollout` status view) — it is a separate binary from the controller you just installed, run from your own machine rather than inside the cluster.

Create:

```bash
vim deployment/phase-13-advanced-deployments/canary/argo-rollout.yaml
```

Paste:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: launchboard-backend
  namespace: devops-launchboard
  labels:
    app: launchboard-backend
spec:
  replicas: 4
  revisionHistoryLimit: 3
  selector:
    matchLabels:
      app: launchboard-backend
  strategy:
    canary:
      maxSurge: 1
      maxUnavailable: 0
      steps:
        - setWeight: 25
        - pause:
            duration: 2m
        - setWeight: 50
        - pause:
            duration: 5m
        - setWeight: 100
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
          image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-backend:phase-13-canary
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

- `kind: Rollout` is a Custom Resource provided by Argo Rollouts; it replaces the standard `Deployment` as the thing that manages these Pods, which is why the blue-green Deployments are deleted before applying this.
- `strategy.canary.steps` defines the rollout sequence: shift 25% of traffic to the new version, pause 2 minutes for you to check logs and metrics, shift to 50%, pause 5 minutes, then go to 100%. The Rollout pauses automatically at each `pause` step and waits for either the duration to elapse or a manual `promote`.
- `maxSurge: 1` / `maxUnavailable: 0` controls how Pods are added/removed during each step, the same safety guarantee as a normal rolling update.

```bash
vim deployment/phase-13-advanced-deployments/canary/kustomization.yaml
```

Paste:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - argo-rollout.yaml
```

Reference:

- Argo Rollouts canary strategy: https://argo-rollouts.readthedocs.io/en/stable/features/canary/

Before canary, clean up blue-green backend deployments:

```bash
kubectl -n devops-launchboard delete deployment launchboard-backend-blue launchboard-backend-green

kubectl -n devops-launchboard patch service launchboard-backend \
  -p '{"spec":{"selector":{"app":"launchboard-backend"}}}'
```

Line explanation:

- The two track Deployments from Step 12 must be removed first; the `Rollout` resource you apply next creates its own Pods labeled only `app: launchboard-backend` with no `track` label, and leaving the old Deployments running would mean two different controllers both trying to manage Pods with overlapping labels.
- The `patch` removes `track` from the Service's selector entirely, so it goes back to matching on `app: launchboard-backend` alone — the same selector the Rollout's Pods carry.

Apply rollout:

```bash
kubectl apply -k deployment/phase-13-advanced-deployments/canary

kubectl -n devops-launchboard get rollout
kubectl -n devops-launchboard get pods -l app=launchboard-backend
```

Line explanation:

- `kubectl apply -k .../canary` creates the `Rollout` resource. Unlike a Deployment, a fresh `Rollout` with no prior revision skips the canary steps and goes straight to `replicas: 4` healthy Pods — the canary steps only take effect on the *next* update, once a previous revision exists to compare against.
- `kubectl get rollout` (a CRD providing custom columns, not a built-in kubectl noun) shows the Rollout's current phase (`Healthy`, `Progressing`, `Paused`, or `Degraded`) and how many Pods are on the new version versus the old one.

Watch rollout:

```bash
kubectl -n devops-launchboard get rollout launchboard-backend -w
```

`-w` (watch) streams live updates instead of printing once and exiting, so you can see the Rollout move through each `setWeight` and `pause` step from the `argo-rollout.yaml` strategy in real time. To actually trigger a canary rollout (rather than the initial healthy deploy above), push a new image tag and run `kubectl argo rollouts set image launchboard-backend backend=$ECR_REGISTRY/launchboard-backend:NEW_TAG -n devops-launchboard`, then watch this command show the step-by-step traffic shift.

Promote manually after checking logs and health:

```bash
kubectl argo rollouts promote launchboard-backend -n devops-launchboard
```

This skips the remaining `pause` duration and immediately advances to the next step (or to 100% if it was the last step) — the manual equivalent of deciding "this canary looks healthy, do not make me wait out the full pause."

Abort if the canary is bad:

```bash
kubectl argo rollouts abort launchboard-backend -n devops-launchboard
```

This immediately routes all traffic back to the stable (previous) ReplicaSet and marks the rollout `Degraded`, without waiting for any pause or further steps — the canary-strategy equivalent of the blue-green rollback in Step 12.

Why this works:

Argo Rollouts replaces the normal Deployment controller with a rollout controller. The canary steps send a small portion of pods to the new version first, pause, then continue only if the release looks healthy.

Reference:

- Argo Rollouts: https://argo-rollouts.readthedocs.io/

## Step 14: Feature Flags

Feature flags let teams enable or disable behavior without building a new image.

Create:

```bash
vim deployment/phase-13-advanced-deployments/feature-flags/configmap-flags.yaml
vim deployment/phase-13-advanced-deployments/feature-flags/kustomization.yaml
```

Paste into `configmap-flags.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: launchboard-feature-flags
  namespace: devops-launchboard
data:
  ENABLE_ADVANCED_METRICS: "true"
  ENABLE_DEMO_SEED: "false"
  RELEASE_BANNER: "Phase 13 controlled release"
```

Line explanation:

- `metadata.name: launchboard-feature-flags` is a separate ConfigMap from `launchboard-config` created in Step 10 — keeping flags in their own object means toggling a flag and redeploying it does not touch the unrelated app configuration (`APP_NAME`, `CORS_ORIGINS`, database settings) sitting in the other ConfigMap.
- `ENABLE_ADVANCED_METRICS` / `ENABLE_DEMO_SEED` are example boolean-style flags, stored as the strings `"true"`/`"false"` because every value in a ConfigMap's `data` map is a string — the application code is responsible for parsing them.
- `RELEASE_BANNER` is an example string flag, showing that feature flags are not limited to booleans.

Paste into `kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - configmap-flags.yaml
```

Apply:

```bash
kubectl apply -k deployment/phase-13-advanced-deployments/feature-flags
```

This creates the `launchboard-feature-flags` ConfigMap in the cluster. By itself this does nothing yet — no running Pod reads it until you attach it to a workload in one of the two ways below.

Attach flags to the normal backend deployment:

```bash
kubectl -n devops-launchboard set env deployment/launchboard-backend \
  --from=configmap/launchboard-feature-flags

kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
```

Line explanation:

- `kubectl set env --from=configmap/...` edits the Deployment's Pod template, adding every key in `launchboard-feature-flags` as an environment variable on the `backend` container (equivalent to adding an `envFrom.configMapRef` entry by hand).
- `rollout restart` is required afterward: `set env` changes the Deployment spec, but existing Pods keep their old environment until they are recreated. The restart triggers a normal rolling update so every new Pod picks up the flags.

Attach flags to the Argo Rollout backend:

```bash
kubectl -n devops-launchboard edit rollout launchboard-backend
```

This opens the Rollout in your default terminal editor. `kubectl set env` does not support the `Rollout` kind, so add the ConfigMap by hand instead: find `spec.template.spec.containers[0].envFrom` (created in Step 13's `argo-rollout.yaml`, which already has one `configMapRef` entry for `launchboard-config`) and add a second entry for the flags ConfigMap, so the block reads:

```yaml
envFrom:
  - configMapRef:
      name: launchboard-config
  - configMapRef:
      name: launchboard-feature-flags
```

Save and exit; Argo Rollouts applies the change as a new revision and rolls it out through the same canary steps defined in `strategy.canary.steps`, since changing the Pod template counts as a new version exactly like a new image tag would.

Why this works:

The ConfigMap stores non-secret runtime settings as environment variables, which both a normal Deployment and an Argo `Rollout` expose to containers via `envFrom`. Real application code must read those variables and branch on them before the flag actually changes behavior — Kubernetes only delivers the value, it does not interpret it.

Reference:

- Kubernetes ConfigMap: https://kubernetes.io/docs/concepts/configuration/configmap/
- kubectl set env: https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#set-env

## Step 15: Multi-Environment Overlays With Kustomize

Everything so far deployed one environment. Real teams run at least two — a dev/staging environment where changes land first, and production — and the single most common way to express the *differences* between them on Kubernetes is Kustomize's base-and-overlay pattern, which you have been half-using all along (`kubectl apply -k` reads a Kustomization).

The idea: `app-k8s/` is the **base** — the environment-agnostic truth. An **overlay** is a folder that inherits the base and patches only what differs:

```text
app-k8s/                      (base: all 13 manifests, unchanged)
overlays/
+-- dev/kustomization.yaml    (namespace devops-launchboard-dev, 1 replica, tiny HPA, own ALB)
+-- prod/kustomization.yaml   (3 replicas, bigger HPA, demo seeding OFF)
```

No manifest is copied. If you fix a probe in the base, both environments get the fix — the overlay only ever contains the *delta*. Compare that with the copy-the-folder-per-environment approach, where every fix must be applied N times and environments silently drift apart.

### overlays/dev/kustomization.yaml

```bash
mkdir -p deployment/phase-13-advanced-deployments/overlays/dev deployment/phase-13-advanced-deployments/overlays/prod
vim deployment/phase-13-advanced-deployments/overlays/dev/kustomization.yaml
```

Paste:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: devops-launchboard-dev

resources:
  - ../../app-k8s

patches:
  - target:
      kind: Deployment
      name: launchboard-backend
    patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: launchboard-backend
      spec:
        replicas: 1
  - target:
      kind: Deployment
      name: launchboard-frontend
    patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: launchboard-frontend
      spec:
        replicas: 1
  - target:
      kind: HorizontalPodAutoscaler
      name: launchboard-backend
    patch: |-
      apiVersion: autoscaling/v2
      kind: HorizontalPodAutoscaler
      metadata:
        name: launchboard-backend
      spec:
        minReplicas: 1
        maxReplicas: 2
  - target:
      kind: Ingress
      name: launchboard-ingress
    patch: |-
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: launchboard-ingress
        annotations:
          alb.ingress.kubernetes.io/load-balancer-name: launchboard-phase-13-dev
```

Line explanation:

- `namespace: devops-launchboard-dev` is the namespace transformer: it stamps this namespace onto **every** resource the base produces (and renames the Namespace object itself). One line turns the whole stack into a parallel environment.
- `resources: [../../app-k8s]` inherits the base. The overlay contains no manifests of its own.
- Each `patches` entry targets one object by kind and name and merges a fragment over it (strategic merge). Dev runs 1 replica of each tier and an HPA of 1-2 — dev does not need production capacity, and this is where the cost savings of the pattern come from.
- The Ingress patch changes only the `load-balancer-name` annotation, because two Ingresses cannot claim the same ALB name. Everything else about the Ingress is inherited.

### overlays/prod/kustomization.yaml

```bash
vim deployment/phase-13-advanced-deployments/overlays/prod/kustomization.yaml
```

Paste:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: devops-launchboard

resources:
  - ../../app-k8s

patches:
  - target:
      kind: Deployment
      name: launchboard-backend
    patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: launchboard-backend
      spec:
        replicas: 3
  - target:
      kind: ConfigMap
      name: launchboard-config
    patch: |-
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: launchboard-config
      data:
        SEED_DEMO_DATA: "false"
  - target:
      kind: HorizontalPodAutoscaler
      name: launchboard-backend
    patch: |-
      apiVersion: autoscaling/v2
      kind: HorizontalPodAutoscaler
      metadata:
        name: launchboard-backend
      spec:
        minReplicas: 3
        maxReplicas: 8
```

- Production keeps the original namespace (the base you already deployed *is* production — applying this overlay upgrades it in place), raises the floor to 3 replicas with an 3-8 HPA, and — the interesting one — flips `SEED_DEMO_DATA` to `"false"`: demo data belongs in dev, never in production. Environment-specific *behavior*, not just size, expressed as a patch.

### See The Diff Before Touching Anything

Kustomize renders locally without applying — the habit that makes overlays reviewable:

```bash
kubectl kustomize deployment/phase-13-advanced-deployments/overlays/dev | grep -E "kind:|namespace:|replicas:|SEED"
kubectl kustomize deployment/phase-13-advanced-deployments/overlays/prod | grep -E "replicas:|SEED"
```

Read the output: same objects, different namespaces, different replica counts, different seeding. In a team, a pull request touching `overlays/prod/` gets a very different review than one touching `overlays/dev/` — the folder structure *is* the blast-radius signal.

### Bring Up Dev Alongside Prod

The dev namespace needs its own Secret (secrets are namespaced and never in Git):

```bash
kubectl kustomize deployment/phase-13-advanced-deployments/overlays/dev | kubectl apply -f - --dry-run=client > /dev/null && echo "renders clean"

kubectl create namespace devops-launchboard-dev --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic launchboard-secret \
  --namespace devops-launchboard-dev \
  --from-literal=POSTGRES_PASSWORD='CHANGE_ME_STRONG_PASSWORD' \
  --from-literal=DATABASE_URL='postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@launchboard-db:5432/launchboard'

kubectl apply -k deployment/phase-13-advanced-deployments/overlays/dev
kubectl -n devops-launchboard-dev get pods
```

A complete second environment appears — its own database, backend, frontend, and (after 2-3 minutes) its own ALB named `launchboard-phase-13-dev`. Note dev's `DATABASE_URL` still points at `launchboard-db` — the Service DNS resolves *within its own namespace*, so dev automatically talks to dev's database, not prod's. Namespaces gave you data isolation for free.

Same CORS ritual as always, but scoped to dev (patch the dev ConfigMap with the dev ALB's DNS and restart the dev backend) if you want the dev UI fully working. For the overlay lesson itself, seeing both environments' Pods side by side is the point:

```bash
kubectl get pods -A | grep launchboard
```

### Tear Dev Down

Dev's ALB costs money; when done exploring:

```bash
kubectl delete namespace devops-launchboard-dev
```

One namespace delete removes the whole environment — the overlay can recreate it identically any time. That disposability is the real multi-environment superpower: environments stop being precious.

Where this connects: the Phase 7 GitOps lab deploys with an ArgoCD Application pointing at a Kustomize path — point one Application at `overlays/dev` and another at `overlays/prod`, and you have the standard production setup: every environment continuously synced from its own overlay, promoted by pull request.

Reference:

- Kustomize bases and overlays: https://kubectl.docs.kubernetes.io/guides/config_management/components/
- Kustomization reference: https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/
- Patches: https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/patches/

## Verification Commands

Check app:

```bash
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard get svc
kubectl -n devops-launchboard get ingress
```

Check backend service selector:

```bash
kubectl -n devops-launchboard describe service launchboard-backend
```

Check blue-green pods:

```bash
kubectl -n devops-launchboard get pods -l app=launchboard-backend --show-labels
```

Check canary rollout:

```bash
kubectl -n devops-launchboard get rollout launchboard-backend
```

Check logs:

```bash
kubectl -n devops-launchboard logs deploy/launchboard-frontend
kubectl -n devops-launchboard logs deploy/launchboard-backend-blue
kubectl -n devops-launchboard logs deploy/launchboard-backend-green
```

## Troubleshooting

Problem: traffic does not switch to green.

Cause:

```text
Service selector still points to blue, or green pods are not ready.
```

Fix:

```bash
kubectl -n devops-launchboard describe service launchboard-backend
kubectl -n devops-launchboard get pods -l track=green
kubectl -n devops-launchboard logs deploy/launchboard-backend-green
```

Problem: canary command fails.

Cause:

```text
Argo Rollouts controller or kubectl plugin is missing.
```

Fix:

```bash
kubectl -n argo-rollouts get pods
kubectl get crd | grep rollouts
```

Problem: frontend cannot call backend.

Cause:

```text
The backend service selector points to pods that are not ready.
```

Fix:

```bash
kubectl -n devops-launchboard get endpoints launchboard-backend
kubectl -n devops-launchboard describe service launchboard-backend
```

## Cleanup

Delete advanced release resources:

```bash
kubectl delete -k deployment/phase-13-advanced-deployments/feature-flags
kubectl delete -k deployment/phase-13-advanced-deployments/canary
kubectl delete -k deployment/phase-13-advanced-deployments/blue-green
```

Delete app:

```bash
kubectl delete -f deployment/phase-13-advanced-deployments/app-k8s/secret.yaml
kubectl delete -k deployment/phase-13-advanced-deployments/app-k8s
```

Delete Argo Rollouts:

```bash
kubectl delete namespace argo-rollouts
```

Delete cluster:

```bash
eksctl delete cluster -f deployment/phase-13-advanced-deployments/cluster/eksctl-cluster.yaml
```

Delete ECR repositories:

```bash
aws ecr delete-repository --repository-name launchboard-backend --force --region $AWS_REGION
aws ecr delete-repository --repository-name launchboard-frontend --force --region $AWS_REGION
```

## Production Checklist

```text
[ ] AWS credentials configured
[ ] GitHub SSH clone works
[ ] EKS cluster created
[ ] ECR repositories created
[ ] Images built and pushed
[ ] Base app deployed and healthy
[ ] ALB created
[ ] Blue and green backend pods ready
[ ] Service selector switches traffic
[ ] Rollback to blue tested
[ ] Argo Rollouts installed
[ ] Canary rollout tested
[ ] Canary abort command understood
[ ] Feature flags applied
[ ] Logs checked during release
[ ] Cleanup completed after lab
```

## Reference Documentation

| Topic | Official Link |
| --- | --- |
| EKS | https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html |
| ECR | https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html |
| Kubernetes Deployment | https://kubernetes.io/docs/concepts/workloads/controllers/deployment/ |
| Kubernetes Service | https://kubernetes.io/docs/concepts/services-networking/service/ |
| Kubernetes ConfigMap | https://kubernetes.io/docs/concepts/configuration/configmap/ |
| Argo Rollouts | https://argo-rollouts.readthedocs.io/ |
| AWS Load Balancer Controller | https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/ |

## Next Step

Move to Phase 14 to learn disaster recovery, backup, restore, and incident response.
