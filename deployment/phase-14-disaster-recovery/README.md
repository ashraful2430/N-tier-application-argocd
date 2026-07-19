# Phase 14: Disaster Recovery

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
- You will install Velero for Kubernetes backup and restore.
- You will create PostgreSQL dumps for database-level recovery.
- You will run a small chaos test manually.
- You will use `vim` to create files.
- You will not use custom shell scripts.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What This Phase Deploys

This phase deploys the N-tier application on Amazon EKS and then practices disaster recovery.

The deployment includes:

- Vite frontend served by Nginx
- FastAPI backend
- PostgreSQL database running inside Kubernetes for the lab
- Amazon ECR repositories
- Amazon EKS cluster
- AWS Load Balancer Controller
- Velero backups stored in S3
- EBS volume snapshots through Velero
- Manual PostgreSQL dump and restore commands
- LitmusChaos pod-delete experiment
- Incident response and recovery runbooks

## When To Use This Architecture

DR work is bought with fear and paid for after incidents — these are the real-world moments this phase prepares you for:

- **There is data someone would cry over.** The moment a database contains orders, patient records, or three years of anyone's work, "we should have backups" becomes a professional obligation. This phase turns it from a wish into schedules, snapshots, and tested restores.
- **A contract names RTO and RPO.** Enterprise customers put recovery objectives in procurement questionnaires; auditors ask for the *test evidence*, not the intention. The runbooks and drills here are that evidence.
- **Ransomware changed the rules.** Modern attacks encrypt the primaries *and* hunt reachable backups. Off-cluster, separately-permissioned backups (Velero to S3 with its own IAM) are the pattern insurers and security teams now expect.
- **The cluster is cattle, the data is not.** Real platform teams rehearse "rebuild the entire cluster from Git + restore state" because it converts the worst Tuesday of the year into a documented afternoon. That rehearsal is literally this phase's drill.
- **The on-call truth.** An untested backup is a rumor. Companies discover this at the worst possible moment; you get to discover it in a lab.

Skip the depth when: everything is stateless and rebuildable from Git in minutes — then Git *is* your DR, and this phase teaches you to recognize that too.

## Database Note: Why Still A Pod And Not RDS?

This phase runs PostgreSQL as a Pod on an EBS volume, even though the production answer is a managed database. That is deliberate: this phase's lessons need a database *inside* the cluster — in fact it is most of the point: Velero's EBS volume snapshots, the pg_dump CronJob, and the restore drills all exist to protect in-cluster state. With RDS, AWS does this for you (automated snapshots, point-in-time recovery — the capstone shows that division); this phase teaches what that convenience is replacing, which is exactly what you need to understand to trust it. The managed-database pattern has its own homes in this track — Phase 9 (Terraform production) provisions RDS as code, and Phase 16 (capstone) runs the full Kubernetes stack against RDS with the security groups, `DB_HOST` wiring, and backup division of labor spelled out. If you want RDS here, the capstone's "Create The Database First" section is a drop-in recipe: create the instance, remove the postgres Deployment/Service/PVC from the kustomization, point `DATABASE_URL` and the wait loops at the RDS endpoint.

## Cost Warning

| Resource | Approximate Cost |
| --- | --- |
| EKS control plane | ~$0.10/hour |
| 2 × t3.medium workers | ~$0.08/hour |
| NAT Gateway | ~$0.045/hour |
| ALB | ~$0.02/hour |
| EBS volumes, ECR | ~$0.01/hour |
| S3 backup bucket + EBS snapshots (Velero) | ~$0.01/hour, grows with each backup |

Roughly **$0.27/hour** (~$2.20 for an 8-hour session; $190+/month if left running). Two extra cost traps specific to this phase: **EBS snapshots** created by Velero backups persist after the cluster is deleted — the Cleanup section deletes them explicitly (EC2 Console > Snapshots) — and the **S3 bucket** keeps charging for stored backups until emptied and deleted. Delete the cluster after each session.

Create an AWS Budget before starting: AWS Console > Billing > Budgets > Create budget.

## Recommended AWS Setup

| Item | Recommended Value |
| --- | --- |
| AWS Region | `us-east-1` or the closest region |
| Cluster Name | `devops-launchboard-phase-14` |
| Kubernetes Version | `1.34` |
| Node Type | `t3.medium` |
| Desired Nodes | `2` |
| ECR Backend Repo | `launchboard-backend` |
| ECR Frontend Repo | `launchboard-frontend` |
| Velero Bucket | `devops-launchboard-velero-YOUR_ACCOUNT_ID-YOUR_AWS_REGION` |
| Backup Schedule | Daily at 03:00 |
| Backup TTL | 7 days |

Cost warning:

- EKS costs money.
- EC2 worker nodes cost money.
- EBS volumes and snapshots cost money.
- S3 backup storage costs money.
- Load balancers cost money.
- Delete resources after practice.

Reference:

- EKS pricing: https://aws.amazon.com/eks/pricing/
- S3 pricing: https://aws.amazon.com/s3/pricing/
- AWS Budgets: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html

## Architecture

```text
Browser
  |
  v
AWS Application Load Balancer
  |
  v
Frontend pods
  |
  v
Backend pods
  |
  v
PostgreSQL pod
  |
  v
PersistentVolumeClaim backed by EBS

Recovery tools:

Velero backs up Kubernetes resources.
Velero snapshots EBS volumes.
S3 stores backup metadata.
PostgreSQL dump gives database-level restore.
Runbooks guide the human recovery process.
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
velero version --client-only
```

Install missing tools:

- Git: https://git-scm.com/downloads
- Docker: https://docs.docker.com/get-docker/
- AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- kubectl: https://kubernetes.io/docs/tasks/tools/
- eksctl: https://eksctl.io/installation/
- Helm: https://helm.sh/docs/intro/install/
- Velero CLI: https://velero.io/docs/

Why this step exists:

Disaster recovery uses more than app deployment tools. You need AWS CLI for cloud resources, Docker for images, Kubernetes tools for app resources, and Velero for backup and restore.

## Step 2: Configure AWS

Run:

```bash
aws configure
aws sts get-caller-identity
```

Set variables:

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export VELERO_BUCKET=devops-launchboard-velero-$AWS_ACCOUNT_ID-$AWS_REGION
```

Why this step exists:

The variables keep later commands short and reduce copy-paste mistakes. The bucket name includes account and region so it is more likely to be globally unique.

## Step 3: Create SSH Key And Clone

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-14" -f ~/.ssh/devops_launchboard_phase_14
cat ~/.ssh/devops_launchboard_phase_14.pub
```

Add the public key to GitHub, then create SSH config:

```bash
vim ~/.ssh/config
```

Paste:

```text
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/devops_launchboard_phase_14
  IdentitiesOnly yes
```

Run:

```bash
chmod 600 ~/.ssh/config
chmod 600 ~/.ssh/devops_launchboard_phase_14
chmod 644 ~/.ssh/devops_launchboard_phase_14.pub
ssh -T git@github.com
```

Clone:

```bash
sudo mkdir -p /opt/devops-launchboard
sudo chown -R $USER:$USER /opt/devops-launchboard
cd /opt/devops-launchboard
git clone git@github.com:ashraful2430/N-tier-application.git app-source
cd app-source
```

Why this step exists:

The machine must have the source code before it can build images or create deployment files. SSH keeps GitHub access key-based instead of password-based.

## Step 4: Create Phase 14 Folders

Run:

```bash
mkdir -p deployment/phase-14-disaster-recovery/cluster
mkdir -p deployment/phase-14-disaster-recovery/ecr
mkdir -p deployment/phase-14-disaster-recovery/app-k8s
mkdir -p deployment/phase-14-disaster-recovery/backup
mkdir -p deployment/phase-14-disaster-recovery/disaster-recovery
mkdir -p deployment/phase-14-disaster-recovery/chaos-engineering
mkdir -p deployment/phase-14-disaster-recovery/runbooks
```

Why these folders exist:

- `cluster` stores the EKS cluster definition.
- `ecr` stores image cleanup policy.
- `app-k8s` stores the app deployment.
- `backup` stores Velero backup and restore files.
- `disaster-recovery` stores recovery planning documents.
- `chaos-engineering` stores failure test files.
- `runbooks` stores step-by-step incident documents.

## Step 5: Create EKS Cluster

Create:

```bash
vim deployment/phase-14-disaster-recovery/cluster/eksctl-cluster.yaml
```

Paste:

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: devops-launchboard-phase-14
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
      Environment: phase-14
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

- `metadata.name: devops-launchboard-phase-14` names the cluster; eksctl creates CloudFormation stacks named after it.
- `metadata.version: "1.34"` pins the Kubernetes version, quoted because YAML would otherwise read `1.34` as a number.
- `iam.withOIDC: true` creates an OIDC provider — the foundation of IAM Roles for Service Accounts (IRSA), which lets Kubernetes ServiceAccounts assume IAM roles without storing AWS credentials in the cluster. Both the EBS CSI driver and Velero (installed later in this phase) need this.
- `vpc.nat.gateway: Single` creates one shared NAT Gateway instead of one per AZ, at roughly half the cost.
- `managedNodeGroups[0].privateNetworking: true` keeps worker nodes in private subnets with no public IPs; all inbound traffic goes through the ALB.
- `cloudWatch.clusterLogging.enableTypes` ships control plane logs (API server, audit, authenticator, controller manager, scheduler) to CloudWatch Logs, useful for confirming exactly what happened to a resource before a recovery.
- `addons[0].name: aws-ebs-csi-driver` installs the EBS CSI driver as an EKS managed add-on. Without it, PVCs requesting storage stay `Pending` forever, and Velero has nothing to snapshot.

Create the cluster (20–40 minutes):

```bash
eksctl create cluster -f deployment/phase-14-disaster-recovery/cluster/eksctl-cluster.yaml
kubectl get nodes
```

Why this file exists:

The app needs a Kubernetes platform before backup and recovery can be tested. The EBS CSI driver is important because PostgreSQL uses persistent storage, and Velero can snapshot that storage.

Reference:

- eksctl ClusterConfig schema: https://eksctl.io/usage/schema/
- EBS CSI driver: https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html

## Step 6: Create ECR And Build Images

Create repositories:

```bash
aws ecr create-repository --repository-name launchboard-backend --region $AWS_REGION
aws ecr create-repository --repository-name launchboard-frontend --region $AWS_REGION
```

Create lifecycle policy:

```bash
vim deployment/phase-14-disaster-recovery/ecr/lifecycle-policy.json
```

Paste:

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep the latest 10 phase 14 images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["phase-14"],
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
  --lifecycle-policy-text file://deployment/phase-14-disaster-recovery/ecr/lifecycle-policy.json \
  --region $AWS_REGION

aws ecr put-lifecycle-policy \
  --repository-name launchboard-frontend \
  --lifecycle-policy-text file://deployment/phase-14-disaster-recovery/ecr/lifecycle-policy.json \
  --region $AWS_REGION
```

Line explanation:

- `rulePriority: 1` keeps only the 10 most recent images tagged with the `phase-14` prefix — older ones beyond the 10 most recent are expired automatically.
- `rulePriority: 2` deletes untagged images (orphaned layers left behind when a tag is moved or overwritten) after 7 days.
- `put-lifecycle-policy` attaches this same policy to both repositories, so neither one accumulates old release images forever.

### Dockerfile.backend

```bash
vim deployment/phase-14-disaster-recovery/Dockerfile.backend
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

### Dockerfile.frontend

```bash
vim deployment/phase-14-disaster-recovery/Dockerfile.frontend
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

COPY deployment/phase-14-disaster-recovery/nginx-frontend.conf /etc/nginx/conf.d/default.conf
COPY --from=builder --chown=101:101 /app/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

This uses the `nginxinc/nginx-unprivileged` image (UID 101), consistent with the other phases, instead of a plain `nginx:alpine` image with a manually created user.

### nginx-frontend.conf

```bash
vim deployment/phase-14-disaster-recovery/nginx-frontend.conf
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

Build and push:

```bash
ECR_REGISTRY=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin $ECR_REGISTRY

docker build -f deployment/phase-14-disaster-recovery/Dockerfile.backend \
  -t launchboard-backend:phase-14 .

docker build -f deployment/phase-14-disaster-recovery/Dockerfile.frontend \
  --build-arg VITE_API_URL=/api \
  -t launchboard-frontend:phase-14 .

docker tag launchboard-backend:phase-14 $ECR_REGISTRY/launchboard-backend:phase-14
docker tag launchboard-frontend:phase-14 $ECR_REGISTRY/launchboard-frontend:phase-14

docker push $ECR_REGISTRY/launchboard-backend:phase-14
docker push $ECR_REGISTRY/launchboard-frontend:phase-14
```

Line explanation:

- `ECR_REGISTRY=...` builds the registry hostname once so every later command can reference `$ECR_REGISTRY` instead of repeating the full account ID and region.
- `aws ecr get-login-password | docker login` authenticates Docker with ECR using a short-lived token; `--username AWS` is always the literal string `AWS` for ECR, not your IAM username.
- The trailing `.` on each `docker build` is the build context — it must be the repository root, because both Dockerfiles `COPY backend/...` / `COPY frontend/...` relative to it.
- `docker tag <local-name> <new-name>` does not copy or rebuild anything — it adds a second name pointing at the same image bytes already on disk, this time including the ECR registry hostname `docker push` needs to know where to upload to.

Why this step exists:

Kubernetes pulls app images from ECR. The lifecycle policy prevents old lab images from staying forever and creating storage clutter.

Reference:

- Dockerfile reference: https://docs.docker.com/reference/dockerfile/
- Push images to ECR: https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html

## Step 7: Deploy The Application

All manifests go inside `deployment/phase-14-disaster-recovery/app-k8s/`. Every container here already sets `allowPrivilegeEscalation: false` and drops all Linux capabilities, the same hardened pattern used from Phase 12 onward.

#### namespace.yaml

```bash
vim deployment/phase-14-disaster-recovery/app-k8s/namespace.yaml
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
vim deployment/phase-14-disaster-recovery/app-k8s/storageclass.yaml
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
vim deployment/phase-14-disaster-recovery/app-k8s/configmap.yaml
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

`CORS_ORIGINS` is a placeholder because the ALB DNS name does not exist until AWS creates the load balancer; you update it after applying the Ingress later in this step.

#### secret.example.yaml

```bash
vim deployment/phase-14-disaster-recovery/app-k8s/secret.example.yaml
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

Example only — you copy this to `secret.yaml` and edit it below, so the placeholder file itself stays untouched in Git.

#### pvc.yaml

```bash
vim deployment/phase-14-disaster-recovery/app-k8s/pvc.yaml
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

`storageClassName: gp3` connects this PVC to the EBS CSI driver, which creates a 10 GB encrypted volume in the same AZ as the Pod that mounts it. This is the volume Velero snapshots in the backup steps later in this phase.

#### launchboard-postgres-deployment.yaml

```bash
vim deployment/phase-14-disaster-recovery/app-k8s/launchboard-postgres-deployment.yaml
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

This is the Deployment whose PVC you back up with Velero and restore from a PostgreSQL dump later in this phase. `strategy.type: Recreate` terminates the existing Pod before creating a new one — required for a single-writer database holding an exclusive lock on its `ReadWriteOnce` volume. `runAsUser: 999` is the `postgres:16-alpine` image's own built-in user (confirm with `docker run --rm postgres:16-alpine id -u`); `allowPrivilegeEscalation: false` and `capabilities.drop: [ALL]` satisfy the same restricted-profile pattern as every other container in this phase. `PGDATA: /var/lib/postgresql/data/pgdata` points Postgres at a subdirectory of the mounted volume rather than the mount point itself — a freshly provisioned EBS volume's filesystem always contains a `lost+found` directory at its root, and `initdb` refuses to initialize a data directory it considers non-empty, crash-looping the Pod without this.

#### launchboard-postgres-service.yaml

```bash
vim deployment/phase-14-disaster-recovery/app-k8s/launchboard-postgres-service.yaml
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
vim deployment/phase-14-disaster-recovery/app-k8s/launchboard-migration-job.yaml
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
          image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-backend:phase-14
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

`image` pulls from your private ECR repository — replace both placeholders, e.g. `123456789012.dkr.ecr.us-east-1.amazonaws.com/launchboard-backend:phase-14`. A Job runs its Pod once to completion and stops, unlike a Deployment; the `until python -c "import socket"; ...` loop blocks until PostgreSQL accepts connections, preventing `alembic upgrade head` from running too early.

#### launchboard-backend-deployment.yaml

```bash
vim deployment/phase-14-disaster-recovery/app-k8s/launchboard-backend-deployment.yaml
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
          image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-backend:phase-14
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

`runAsUser: 10001` and `runAsGroup: 10001` must match the `--uid 10001 --gid 10001` pinned in the Dockerfile, or the Pod fails with `CreateContainerConfigError` because the kubelet cannot verify a name-based `USER app` against `runAsNonRoot`. `image` points to ECR — replace the two placeholders.

#### launchboard-backend-service.yaml

```bash
vim deployment/phase-14-disaster-recovery/app-k8s/launchboard-backend-service.yaml
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
vim deployment/phase-14-disaster-recovery/app-k8s/launchboard-frontend-deployment.yaml
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
          image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-frontend:phase-14
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

`runAsUser: 101` matches the nginx user baked into the `nginxinc/nginx-unprivileged` image — the same pattern as the backend's pinned UID 10001, for a different base image's built-in user. `image` points to ECR — replace the two placeholders.

#### launchboard-frontend-service.yaml

```bash
vim deployment/phase-14-disaster-recovery/app-k8s/launchboard-frontend-service.yaml
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
vim deployment/phase-14-disaster-recovery/app-k8s/ingress.yaml
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
    alb.ingress.kubernetes.io/load-balancer-name: launchboard-phase-14
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

`spec.ingressClassName: alb` tells the AWS Load Balancer Controller installed in the next step to handle this Ingress. `load-balancer-name` gives the ALB a predictable name in the EC2 Console.

#### hpa.yaml

```bash
vim deployment/phase-14-disaster-recovery/app-k8s/hpa.yaml
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

If average backend CPU usage exceeds 70% of requested CPU, the HPA scales up to a maximum of 5 Pods; it never scales below 2. EKS includes the Metrics Server by default, so this works immediately with no extra installation.

#### kustomization.yaml

```bash
vim deployment/phase-14-disaster-recovery/app-k8s/kustomization.yaml
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

Lists every manifest so one `kubectl apply -k` applies them all in order. `secret.example.yaml` is deliberately not listed — the real Secret is created separately, below.

Reference:

- Kubernetes Deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
- Kustomize documentation: https://kustomize.io/

Prepare and apply the Secret:

```bash
cd deployment/phase-14-disaster-recovery/app-k8s
cp secret.example.yaml secret.yaml
vim secret.yaml
```

Replace `CHANGE_ME_STRONG_PASSWORD` in `secret.yaml` with a real password (both occurrences), then:

```bash
cd /opt/devops-launchboard/app-source

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed -i "s|YOUR_ACCOUNT_ID|${ACCOUNT_ID}|g; s|YOUR_AWS_REGION|${AWS_REGION}|g" \
  deployment/phase-14-disaster-recovery/app-k8s/launchboard-backend-deployment.yaml \
  deployment/phase-14-disaster-recovery/app-k8s/launchboard-migration-job.yaml \
  deployment/phase-14-disaster-recovery/app-k8s/launchboard-frontend-deployment.yaml

kubectl apply -f deployment/phase-14-disaster-recovery/app-k8s/secret.yaml
kubectl apply -k deployment/phase-14-disaster-recovery/app-k8s
kubectl -n devops-launchboard get pods
```

Line explanation:

- `cp secret.example.yaml secret.yaml` makes a working copy so the placeholder file itself stays untouched in Git; `secret.yaml` is the one you actually edit and apply.
- `sed -i "s|YOUR_ACCOUNT_ID|...|g; ..."` edits the three manifests that contain ECR image references, replacing both placeholders with your real account ID and region.
- `kubectl apply -f .../secret.yaml` creates the Secret first, separately from the kustomization, since `secret.yaml` is intentionally not listed in `kustomization.yaml`.
- `kubectl apply -k .../app-k8s` then applies every manifest in `kustomization.yaml` together, in order.

Why this step exists:

Recovery practice is meaningful only when a real app is running. This app gives students frontend, backend, database, persistent volume, service, ingress, and migration resources to protect.

## Step 8: Install AWS Load Balancer Controller

Run:

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

eksctl create iamserviceaccount \
  --cluster devops-launchboard-phase-14 \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --role-name devops-launchboard-phase-14-alb-controller \
  --attach-policy-arn arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess \
  --approve

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=devops-launchboard-phase-14 \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

Verify:

```bash
kubectl -n devops-launchboard get ingress
```

Command explanation:

- `eksctl create iamserviceaccount` creates an IAM role, a Kubernetes ServiceAccount in `kube-system`, and a trust relationship between them via the cluster's OIDC provider (IRSA) — the controller Pod automatically receives temporary credentials for the role, with no access keys stored in the cluster.
- `--attach-policy-arn arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess` uses a broad AWS managed policy for simplicity in this phase, since the focus here is backup and recovery, not IAM hardening. Phase 12 walks through downloading the controller's official least-privilege policy instead and attaching a custom policy scoped to only what the controller needs.
- `helm upgrade --install` deploys the controller from the official EKS Helm chart repository; `--set serviceAccount.create=false` tells Helm to use the ServiceAccount `eksctl` already created instead of making its own.

Why this step exists:

The Ingress resource needs the AWS Load Balancer Controller to create a real Application Load Balancer.

Reference:

- AWS Load Balancer Controller installation: https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/
- IRSA: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html

## Step 9: Create Velero S3 Bucket

Run:

```bash
aws s3api create-bucket \
  --bucket $VELERO_BUCKET \
  --region $AWS_REGION \
  --create-bucket-configuration LocationConstraint=$AWS_REGION

aws s3api put-bucket-versioning \
  --bucket $VELERO_BUCKET \
  --versioning-configuration Status=Enabled
```

Line explanation:

- `aws s3api create-bucket` creates the bucket Velero will store backup metadata and EBS snapshot references in. `--create-bucket-configuration LocationConstraint=$AWS_REGION` is required for any region other than `us-east-1` — without it, S3 defaults to creating the bucket in `us-east-1` regardless of which region you specified.
- `aws s3api put-bucket-versioning --versioning-configuration Status=Enabled` keeps every previous version of an object instead of overwriting it. If a backup object were accidentally deleted or overwritten, versioning means the previous copy is still recoverable.

Why this step exists:

Velero stores backup metadata in object storage. S3 versioning adds another safety layer because overwritten or deleted backup objects are easier to investigate.

Reference:

- Velero AWS plugin setup: https://github.com/vmware-tanzu/velero-plugin-for-aws
- S3 bucket versioning: https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html

## Step 10: Create Velero IAM Policy

Create:

```bash
vim deployment/phase-14-disaster-recovery/backup/velero-aws-policy.json
```

Paste:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeVolumes",
        "ec2:DescribeSnapshots",
        "ec2:DescribeAvailabilityZones",
        "ec2:CreateVolume",
        "ec2:DeleteVolume",
        "ec2:CreateSnapshot",
        "ec2:DeleteSnapshot",
        "ec2:AttachVolume",
        "ec2:DetachVolume",
        "ec2:CreateTags",
        "ec2:DescribeVolumeAttribute",
        "ec2:DescribeVolumeStatus",
        "ec2:DescribeInstances"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:PutObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": "arn:aws:s3:::YOUR_VELERO_BUCKET/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::YOUR_VELERO_BUCKET"
    }
  ]
}
```

Replace:

```text
YOUR_VELERO_BUCKET
```

Line explanation:

- The first `Statement` grants EC2 volume and snapshot permissions (`CreateSnapshot`, `CreateVolume`, `AttachVolume`, and their describe/delete counterparts). This is how Velero implements EBS-level backup: it snapshots the actual PostgreSQL PVC's underlying volume, not just the Kubernetes object describing it.
- The second `Statement` grants read/write/delete on objects inside the Velero bucket (`s3:GetObject`, `PutObject`, `DeleteObject`) plus the two multipart-upload actions Velero needs when uploading large backup archives in chunks.
- The third `Statement` grants `s3:ListBucket` separately, scoped to the bucket itself rather than its contents — S3 requires this as a distinct permission from reading objects inside the bucket.
- `Resource: "*"` on the EC2 statement is broader than the S3 statements because AWS EC2 snapshot/volume APIs do not support resource-level ARN restrictions the way S3 objects do.

Create policy:

```bash
aws iam create-policy \
  --policy-name devops-launchboard-phase-14-velero \
  --policy-document file://deployment/phase-14-disaster-recovery/backup/velero-aws-policy.json
```

Create service account:

```bash
eksctl create iamserviceaccount \
  --cluster devops-launchboard-phase-14 \
  --namespace velero \
  --name velero \
  --role-name devops-launchboard-phase-14-velero \
  --attach-policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/devops-launchboard-phase-14-velero \
  --approve
```

Why this file exists:

Velero needs permission to write backup data to S3 and create/restore EBS snapshots. The policy gives those permissions to the Velero service account instead of using broad user credentials inside the cluster.

Reference:

- Velero AWS plugin: https://github.com/vmware-tanzu/velero-plugin-for-aws
- Velero AWS install guide: https://velero.io/docs/

## Step 11: Install Velero

Run:

```bash
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.13.0 \
  --bucket $VELERO_BUCKET \
  --backup-location-config region=$AWS_REGION \
  --snapshot-location-config region=$AWS_REGION \
  --namespace velero \
  --service-account-name velero \
  --no-secret
```

Line explanation:

- `--provider aws --plugins velero/velero-plugin-for-aws:...` installs Velero's core controller plus the AWS-specific plugin that knows how to talk to S3 and the EC2 snapshot API.
- `--bucket $VELERO_BUCKET` and the two `*-location-config region=...` flags point Velero at the S3 bucket and AWS region created in Step 9 for storing both backup metadata and EBS snapshots.
- `--service-account-name velero` tells the installer to reuse the IRSA-enabled ServiceAccount created in Step 10 instead of creating a new one, so the Velero Pod authenticates to AWS via the IAM role rather than stored credentials.
- `--no-secret` skips creating a Kubernetes Secret with AWS access keys — IRSA already provides credentials, so a static secret would be redundant and less secure.

Verify:

```bash
kubectl -n velero get pods
velero backup-location get
```

Why this step exists:

Velero runs inside Kubernetes and watches backup/restore resources. The AWS plugin lets it store metadata in S3 and snapshot EBS volumes.

Reference:

- Velero installation: https://velero.io/docs/main/basic-install/
- Velero AWS plugin: https://github.com/vmware-tanzu/velero-plugin-for-aws

## Step 12: Create Scheduled And Manual Backups

Create schedule:

```bash
vim deployment/phase-14-disaster-recovery/backup/velero-schedule.yaml
```

Paste:

```yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: launchboard-daily
  namespace: velero
spec:
  schedule: "0 3 * * *"
  template:
    includedNamespaces:
      - devops-launchboard
    snapshotVolumes: true
    ttl: 168h0m0s
    storageLocation: default
    volumeSnapshotLocations:
      - default
```

Line explanation:

- `spec.schedule: "0 3 * * *"` is standard cron syntax meaning every day at 03:00 — Velero runs a new `Backup` automatically at this time, without you applying anything further.
- `includedNamespaces: [devops-launchboard]` limits the backup to the application namespace; Velero would otherwise back up every namespace in the cluster, including `kube-system` and `velero` itself.
- `snapshotVolumes: true` tells Velero to also EBS-snapshot every PersistentVolume attached to a backed-up Pod (the PostgreSQL data volume), not just the Kubernetes object YAML. Without this, restoring would recreate an empty database.
- `ttl: 168h0m0s` is 7 days — Velero automatically deletes the backup (and its EBS snapshots) after this time to control storage cost.
- `storageLocation: default` and `volumeSnapshotLocations: [default]` reference the S3 bucket and snapshot region configured when Velero was installed in Step 11.

Create manual backup:

```bash
vim deployment/phase-14-disaster-recovery/backup/velero-backup.yaml
```

Paste:

```yaml
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: launchboard-manual
  namespace: velero
spec:
  includedNamespaces:
    - devops-launchboard
  snapshotVolumes: true
  ttl: 168h0m0s
  storageLocation: default
  volumeSnapshotLocations:
    - default
```

This is the same `spec` as the Schedule's `template`, but applied directly as a one-time `Backup` object instead of waiting for the cron schedule — useful for capturing a known-good restore point immediately before a planned change or a failure drill.

Apply:

```bash
kubectl apply -f deployment/phase-14-disaster-recovery/backup/velero-schedule.yaml
kubectl apply -f deployment/phase-14-disaster-recovery/backup/velero-backup.yaml
velero backup get
velero backup describe launchboard-manual --details
```

Why these files exist:

The schedule creates automatic daily backups. The manual backup lets students create a known restore point before running a failure test.

Reference:

- Velero Backup API: https://velero.io/docs/main/api-types/backup/
- Velero Schedule API: https://velero.io/docs/main/api-types/schedule/

## Step 13: Create PostgreSQL Dump

Run:

```bash
kubectl -n devops-launchboard exec deploy/launchboard-db -- \
  pg_dump -U launchboard_user -d launchboard > launchboard-db-backup.sql

ls -lh launchboard-db-backup.sql
```

`kubectl exec deploy/launchboard-db -- pg_dump ...` runs `pg_dump` inside the running PostgreSQL container itself, rather than connecting from outside the cluster. `-U launchboard_user -d launchboard` dumps the same database and user the application uses. The `>` redirect captures the dump's stdout into a local SQL file on your workstation, outside the cluster entirely — this file is your database backup independent of Velero's EBS snapshots.

Why this step exists:

Velero protects Kubernetes resources and volumes. A PostgreSQL dump protects the database at the SQL level. Real production systems often use both infrastructure backups and database-native backups.

Reference:

- pg_dump: https://www.postgresql.org/docs/current/app-pgdump.html

## Step 14: Simulate Failure

Delete one backend pod:

```bash
kubectl -n devops-launchboard get pods -l app=launchboard-backend
kubectl -n devops-launchboard delete pod POD_NAME
kubectl -n devops-launchboard get pods -w
```

Expected:

```text
Kubernetes creates a replacement pod.
The app remains available if another backend replica is ready.
```

Why this step exists:

This is the simplest chaos test. It proves Kubernetes can recover from one pod failure.

## Step 15: Optional LitmusChaos Pod Delete Test

Install LitmusChaos:

```bash
helm repo add litmuschaos https://litmuschaos.github.io/litmus-helm/
helm repo update
helm upgrade --install litmuschaos litmuschaos/litmus \
  --namespace litmus \
  --create-namespace
```

Create RBAC:

```bash
vim deployment/phase-14-disaster-recovery/chaos-engineering/litmus-rbac.yaml
```

Paste:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: litmus-admin
  namespace: devops-launchboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: litmus-pod-chaos
  namespace: devops-launchboard
rules:
  - apiGroups:
      - ""
    resources:
      - pods
      - events
    verbs:
      - get
      - list
      - watch
      - create
      - delete
      - patch
  - apiGroups:
      - apps
    resources:
      - deployments
    verbs:
      - get
      - list
      - patch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: litmus-pod-chaos
  namespace: devops-launchboard
subjects:
  - kind: ServiceAccount
    name: litmus-admin
    namespace: devops-launchboard
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: litmus-pod-chaos
```

Line explanation:

- `kind: ServiceAccount` named `litmus-admin` is the identity the chaos experiment runs as — scoped to the `devops-launchboard` namespace, not cluster-wide.
- `kind: Role` grants `delete` and `patch` on `pods` (so the experiment can actually kill a Pod) plus `get`/`list`/`watch` for it to find target Pods, and read/patch on `deployments` so it can identify and verify the Deployment a Pod belongs to. It deliberately does not grant access to Secrets, ConfigMaps, or other resources.
- `kind: RoleBinding` connects the Role to the ServiceAccount; this is the same RBAC pattern used for `launchboard-deployer` back in Phase 12.

Create experiment:

```bash
vim deployment/phase-14-disaster-recovery/chaos-engineering/pod-delete-chaosengine.yaml
```

Paste:

```yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosEngine
metadata:
  name: launchboard-backend-pod-delete
  namespace: devops-launchboard
spec:
  appinfo:
    appns: devops-launchboard
    applabel: app=launchboard-backend
    appkind: deployment
  chaosServiceAccount: litmus-admin
  engineState: active
  annotationCheck: "false"
  experiments:
    - name: pod-delete
      spec:
        components:
          env:
            - name: TOTAL_CHAOS_DURATION
              value: "30"
            - name: CHAOS_INTERVAL
              value: "10"
            - name: FORCE
              value: "false"
```

Line explanation:

- `appinfo.applabel: app=launchboard-backend` and `appkind: deployment` target the backend Deployment specifically — this experiment never touches the database or frontend.
- `chaosServiceAccount: litmus-admin` is the ServiceAccount from `litmus-rbac.yaml`; without the matching RBAC, the experiment Pod would fail with a permissions error when it tries to delete a Pod.
- `engineState: active` starts the experiment as soon as it is applied; setting this to `stop` later halts it.
- `experiments[0].name: pod-delete` selects LitmusChaos's built-in "pod-delete" experiment type from its experiment catalog.
- `TOTAL_CHAOS_DURATION: "30"` runs the experiment for 30 seconds; `CHAOS_INTERVAL: "10"` deletes a target Pod every 10 seconds during that window, so roughly 3 Pods get killed in this run.
- `FORCE: "false"` lets Pods terminate gracefully (respecting `terminationGracePeriodSeconds` and shutdown hooks) instead of a hard `kill -9`, which is closer to how a real node drain or eviction behaves.

Apply:

```bash
kubectl apply -f deployment/phase-14-disaster-recovery/chaos-engineering/litmus-rbac.yaml
kubectl apply -f deployment/phase-14-disaster-recovery/chaos-engineering/pod-delete-chaosengine.yaml
kubectl -n devops-launchboard get chaosengine
```

Why this step exists:

Chaos testing intentionally creates controlled failure. Students learn whether readiness probes, replicas, and recovery habits are good enough before a real incident happens.

Reference:

- LitmusChaos docs: https://litmuschaos.io/docs/

## Step 16: Restore Kubernetes Resources With Velero

Create restore file:

```bash
vim deployment/phase-14-disaster-recovery/backup/velero-restore.yaml
```

Paste:

```yaml
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: launchboard-restore
  namespace: velero
spec:
  backupName: launchboard-manual
  includedNamespaces:
    - devops-launchboard
  existingResourcePolicy: update
```

Line explanation:

- `spec.backupName: launchboard-manual` tells Velero which backup object to restore from — the manual one created in Step 12, not the daily scheduled one.
- `includedNamespaces: [devops-launchboard]` restricts the restore to the application namespace, mirroring the backup's own scope.
- `existingResourcePolicy: update` tells Velero to overwrite resources that already exist in the cluster with the backed-up version, instead of the default behavior of skipping any resource that is already present. This matters for this drill specifically: after Step 14/15 deleted or chaos-killed Pods, the Deployments and Services themselves are usually still present (only the Pods were destroyed), so without `update` the Restore would see "resource already exists" and do nothing useful.

Practice restore:

```bash
kubectl apply -f deployment/phase-14-disaster-recovery/backup/velero-restore.yaml

velero restore get
velero restore describe launchboard-restore --details
kubectl -n devops-launchboard get pods
```

Why this step exists:

A backup is only trusted after restore succeeds. This restore object tells Velero to restore resources from the `launchboard-manual` backup.

Reference:

- Velero Restore API: https://velero.io/docs/main/api-types/restore/

## Step 17: Restore PostgreSQL From Dump

Only do this in a lab or during an approved recovery window.

Run:

```bash
cat launchboard-db-backup.sql \
  | kubectl -n devops-launchboard exec -i deploy/launchboard-db -- psql -U launchboard_user -d launchboard

kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
kubectl -n devops-launchboard rollout status deployment/launchboard-backend
```

`cat launchboard-db-backup.sql | kubectl exec -i ... -- psql ...` streams the SQL file from your workstation, through stdin, into `psql` running inside the PostgreSQL container — `-i` keeps stdin open across the `exec` call, which is required for the pipe to work. `psql -U launchboard_user -d launchboard` replays every statement in the dump (the `INSERT`/`CREATE` statements `pg_dump` produced) against the live database. The `rollout restart` afterward is precautionary: if the backend held any open connections or cached query results from before the restore, this guarantees fresh connections against the restored data.

Why this step exists:

Database-level restore is useful when Kubernetes resources are healthy but the data is damaged. This command streams the SQL backup from your machine into the PostgreSQL pod.

Reference:

- psql: https://www.postgresql.org/docs/current/app-psql.html

## Step 18: Create Runbooks

Runbooks turn "what we discussed" into "what is written down" — during a real incident, people are stressed, and a checklist beats trying to remember the right command under pressure.

### failover-plan.md

```bash
vim deployment/phase-14-disaster-recovery/disaster-recovery/failover-plan.md
```

Paste:

```markdown
# Failover Plan

## Purpose

This plan tells the student what to do when the primary app path is unhealthy.

## Recovery Targets

- RTO: restore public app access within 30 minutes for the lab.
- RPO: lose no more than the latest verified backup window.

## Steps

1. Freeze deployments.
2. Assign incident commander and scribe.
3. Confirm whether the failure is frontend, backend, database, node, or cluster level.
4. Check current backups with `velero backup get`.
5. Export a fresh database dump if the database is still reachable.
6. Restore Kubernetes resources from Velero if namespace resources are damaged.
7. Restore PostgreSQL data from dump if the database content is damaged.
8. Restart backend pods.
9. Verify `/health`, `/ready`, frontend `/healthz`, and browser access.
10. Record the recovery time and data-loss estimate.
```

This is the top-level decision tree: it tells whoever is on call which of the tools from this phase (Velero restore, SQL dump restore, or a simple pod restart) applies to the failure they are looking at, in the order to try them.

### rto-rpo.md

```bash
vim deployment/phase-14-disaster-recovery/disaster-recovery/rto-rpo.md
```

Paste:

````markdown
# RTO And RPO

## RTO

Recovery Time Objective means how long the app is allowed to be unavailable.

For this lab:

```text
RTO = 30 minutes
```

## RPO

Recovery Point Objective means how much data the app is allowed to lose.

For this lab:

```text
RPO = 24 hours for Velero scheduled backups
RPO = near current time when a fresh PostgreSQL dump exists
```

## Why This Matters

Backup tools are not enough by themselves. Students must know how fast they need to recover and how much data loss is acceptable before choosing a backup schedule.
````

RTO and RPO are the two numbers every other decision in this phase traces back to: the daily Velero schedule from Step 12 (`schedule: "0 3 * * *"`) sets the RPO ceiling at 24 hours, and the existence of a fast `kubectl rollout undo` (Step 17 of Phase 13) is what makes a 30-minute RTO realistic at all.

### incident-response.md

```bash
vim deployment/phase-14-disaster-recovery/runbooks/incident-response.md
```

Paste:

````markdown
# Incident Response Runbook

## First Five Minutes

1. Name the incident.
2. Assign incident commander.
3. Assign scribe.
4. Freeze deployments.
5. Check the public app URL.
6. Check Kubernetes pods and events.

## Investigation Commands

```bash
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard get events --sort-by=.lastTimestamp
kubectl -n devops-launchboard logs deploy/launchboard-backend
kubectl -n devops-launchboard logs deploy/launchboard-frontend
velero backup get
```

## Stabilization Choices

- Restart failed pods.
- Roll back the latest deployment.
- Restore from Velero backup.
- Restore PostgreSQL from dump.
- Recreate the cluster if the cluster is unrecoverable.

## Closeout

1. Confirm app access.
2. Confirm API health.
3. Confirm database reads and writes.
4. Record timestamps.
5. Write a post-incident review.
````

The "Investigation Commands" block is deliberately the first place anyone touches `kubectl` during an incident — read-only commands only (`get`, `logs`), so the very first actions never risk making a confusing situation worse before anyone understands what broke.

### recovery-checklist.md

```bash
vim deployment/phase-14-disaster-recovery/runbooks/recovery-checklist.md
```

Paste:

````markdown
# Recovery Checklist

```text
[ ] Incident commander assigned
[ ] Deployment freeze announced
[ ] App health checked
[ ] Kubernetes events checked
[ ] Latest Velero backup identified
[ ] PostgreSQL dump created if database is reachable
[ ] Restore command tested
[ ] Backend restarted
[ ] Frontend verified
[ ] API verified
[ ] Database write verified
[ ] RTO recorded
[ ] RPO recorded
[ ] Cleanup completed
```
````

This is the same flow as `incident-response.md` and `failover-plan.md`, condensed into tickable boxes — meant to be printed or pasted into an incident ticket and checked off in real time, rather than read as prose while you are also trying to fix the outage.

### rollback-procedures.md

```bash
vim deployment/phase-14-disaster-recovery/runbooks/rollback-procedures.md
```

Paste:

````markdown
# Rollback Procedures

## Standard Kubernetes Deployment

```bash
kubectl -n devops-launchboard rollout history deployment/launchboard-backend
kubectl -n devops-launchboard rollout undo deployment/launchboard-backend
kubectl -n devops-launchboard rollout status deployment/launchboard-backend
```

## Frontend Deployment

```bash
kubectl -n devops-launchboard rollout history deployment/launchboard-frontend
kubectl -n devops-launchboard rollout undo deployment/launchboard-frontend
kubectl -n devops-launchboard rollout status deployment/launchboard-frontend
```

## Database Restore

Use rollback only when schema/data damage is confirmed and the team accepts the RPO impact.

```bash
kubectl -n devops-launchboard exec -it deploy/launchboard-db -- psql -U launchboard_user -d launchboard
```
````

This separates the cheap, fast rollback (`rollout undo` — instant, because the previous ReplicaSet's Pods need no rebuild, the same mechanism taught in Phase 7 and Phase 13) from the expensive, slow one (database restore — explicitly gated behind "schema/data damage is confirmed," because unlike a code rollback, undoing a database write is not always possible).

## Verification Commands

Check app:

```bash
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard get svc
kubectl -n devops-launchboard get ingress
```

Check Velero:

```bash
kubectl -n velero get pods
velero backup get
velero schedule get
velero restore get
```

Check database backup:

```bash
ls -lh launchboard-db-backup.sql
```

Check health:

```bash
kubectl -n devops-launchboard logs deploy/launchboard-backend
kubectl -n devops-launchboard logs deploy/launchboard-frontend
```

## Troubleshooting

Problem: Velero backup is stuck.

Cause:

```text
Velero cannot write to S3, cannot create snapshots, or the IAM role is wrong.
```

Fix:

```bash
kubectl -n velero logs deploy/velero
velero backup describe launchboard-manual --details
aws s3 ls s3://$VELERO_BUCKET
```

Problem: PostgreSQL dump fails.

Cause:

```text
Database pod is not ready, username is wrong, or database name is wrong.
```

Fix:

```bash
kubectl -n devops-launchboard get pods -l app=launchboard-db
kubectl -n devops-launchboard logs deploy/launchboard-db
```

Problem: restore creates resources but app still fails.

Cause:

```text
Secret values, image tags, or database readiness may still be wrong.
```

Fix:

```bash
kubectl -n devops-launchboard get events --sort-by=.lastTimestamp
kubectl -n devops-launchboard describe pod POD_NAME
kubectl -n devops-launchboard get secret launchboard-secret
```

## Cleanup

Delete Litmus:

```bash
helm uninstall litmuschaos -n litmus
kubectl delete namespace litmus
```

Delete Velero backups and install:

```bash
velero backup delete launchboard-manual --confirm
kubectl delete -f deployment/phase-14-disaster-recovery/backup/velero-schedule.yaml
kubectl delete namespace velero
```

Delete app:

```bash
kubectl delete -f deployment/phase-14-disaster-recovery/app-k8s/secret.yaml
kubectl delete -k deployment/phase-14-disaster-recovery/app-k8s
```

Delete cluster:

```bash
eksctl delete cluster -f deployment/phase-14-disaster-recovery/cluster/eksctl-cluster.yaml
```

Delete ECR and S3:

```bash
aws ecr delete-repository --repository-name launchboard-backend --force --region $AWS_REGION
aws ecr delete-repository --repository-name launchboard-frontend --force --region $AWS_REGION
aws s3 rm s3://$VELERO_BUCKET --recursive
aws s3api delete-bucket --bucket $VELERO_BUCKET --region $AWS_REGION
```

Why cleanup matters:

Disaster recovery labs create snapshots, S3 objects, clusters, nodes, and load balancers. These can keep charging after the lesson.

## Production Checklist

```text
[ ] AWS credentials configured
[ ] Repository cloned with SSH
[ ] EKS cluster created
[ ] ECR repositories created
[ ] Images pushed
[ ] Application deployed
[ ] ALB working
[ ] Velero bucket created
[ ] Velero IAM policy created
[ ] Velero installed
[ ] Manual Velero backup completed
[ ] Scheduled Velero backup created
[ ] PostgreSQL dump created
[ ] Pod failure tested
[ ] Velero restore tested
[ ] PostgreSQL restore command tested in lab
[ ] RTO documented
[ ] RPO documented
[ ] Incident runbooks created
[ ] Cleanup completed
```

## Reference Documentation

| Topic | Official Link |
| --- | --- |
| EKS | https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html |
| ECR | https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html |
| EBS CSI Driver | https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html |
| Velero | https://velero.io/docs/ |
| Velero AWS Plugin | https://github.com/vmware-tanzu/velero-plugin-for-aws |
| S3 | https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html |
| Kubernetes Backup Concepts | https://kubernetes.io/docs/concepts/storage/volume-snapshots/ |
| PostgreSQL pg_dump | https://www.postgresql.org/docs/current/app-pgdump.html |
| LitmusChaos | https://litmuschaos.io/docs/ |

## Next Step

Run a game-day exercise where students follow the runbooks without help, then move to:

```text
Phase 15: Performance And Load Validation
```

Why:

After proving the platform can recover from failure, the next question is whether it can handle real traffic - Phase 15 load-tests the deployment with k6 and validates the autoscaler before anything is called production-ready.
