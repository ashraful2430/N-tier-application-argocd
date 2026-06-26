# Phase 7: CI/CD Automation — Docker Hub + Amazon EKS

## Fresh Start Assumption

This phase starts from a clean AWS environment and a clean Ubuntu EC2 workstation.

You do not need to complete any previous phase before using this guide.

This guide assumes:

- You have an AWS account with permissions to create EKS, EC2, IAM, VPC, ALB, EBS, and NAT Gateway resources.
- You have a Docker Hub account (free at https://hub.docker.com).
- You have a GitHub repository with the N-tier application source code.
- AWS CLI, Docker, kubectl, eksctl, and Helm are not installed yet.
- No EKS cluster exists yet.
- The repository is not cloned yet.
- You will create files with `vim` and type commands manually.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What You Will Build

This phase creates a production CI/CD pipeline that:

- Runs backend lint and smoke checks on every push.
- Runs frontend lint and build checks on every push.
- Builds backend and frontend Docker images tagged with the Git commit SHA.
- Scans images with Trivy for known vulnerabilities.
- Pushes images to Docker Hub automatically.
- Deploys to Amazon EKS automatically after a successful build.
- Updates running Deployments with the new image tag using `kubectl set image`.
- Waits for rollout to complete and verifies the app via the ALB.
- Supports one-click rollback from the GitHub Actions UI.

All CI/CD workflows run on free GitHub-hosted runners. No self-hosted runner is needed because EKS is accessible over the internet with AWS credentials.

## Architecture

```text
Developer pushes to GitHub main
  |
  v
GitHub-hosted runner (ubuntu-latest, free)
  |
  | 1. Lint + test backend and frontend
  | 2. Docker build + Trivy scan
  | 3. Docker push to Docker Hub (commit SHA tag)
  |
  v
GitHub-hosted runner (ubuntu-latest, free)
  |
  | 4. Configure AWS credentials
  | 5. aws eks update-kubeconfig
  | 6. kubectl set image → new Docker Hub tag
  | 7. kubectl rollout status → wait
  | 8. curl ALB → verify
  |
  v
Amazon EKS cluster
  |
  | Worker nodes pull new image from Docker Hub
  v
DevOps LaunchBoard app (live, updated)
```

## Cost Warning

| Resource | Approximate Cost |
| --- | --- |
| EKS control plane | ~$0.10/hour (~$73/month) |
| 2 × t3.medium workers | ~$0.08/hour (~$60/month) |
| NAT Gateway | ~$0.045/hour (~$33/month) |
| Application Load Balancer | ~$0.02/hour (~$16/month) |
| EBS volumes | ~$0.01/hour |
| Docker Hub (public repos) | Free |
| GitHub Actions (hosted runners) | Free for public repos |

Running for 8 hours costs roughly $2 to $3. Running 24/7 for a month costs ~$180. The NAT Gateway alone is $33/month. Delete the cluster after each lab session.

Create an AWS Budget before starting: AWS Console > Billing > Budgets > Create budget.

## Files Included In This Phase

```text
deployment/phase-07-cicd-self-hosted/
+-- eks/
|   +-- eksctl-cluster.yaml              (EKS cluster definition)
+-- eks-k8s/
|   +-- namespace.yaml                   (app namespace)
|   +-- storageclass.yaml                (gp3 encrypted EBS)
|   +-- configmap.yaml                   (app configuration)
|   +-- secret.example.yaml              (example secret)
|   +-- pvc.yaml                         (PostgreSQL persistent storage)
|   +-- launchboard-postgres-deployment.yaml
|   +-- launchboard-postgres-service.yaml
|   +-- launchboard-migration-job.yaml
|   +-- launchboard-backend-deployment.yaml
|   +-- launchboard-backend-service.yaml
|   +-- launchboard-frontend-deployment.yaml
|   +-- launchboard-frontend-service.yaml
|   +-- ingress.yaml                     (ALB Ingress)
|   +-- hpa.yaml                         (backend autoscaler)
|   +-- kustomization.yaml
+-- Dockerfile.backend
+-- Dockerfile.frontend
+-- nginx-frontend.conf
.github/workflows/
+-- build-and-test.yml                   (lint + tests)
+-- docker-build-push-hub.yml            (build, scan, push to Docker Hub)
+-- deploy-eks.yml                       (deploy to EKS, auto-triggered after push)
+-- rollback-eks.yml                     (manual rollback from GitHub UI)
```

## Step 1: Create EC2 Workstation And Install Tools

Create one Ubuntu EC2 for running commands:

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-7-workstation` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` |
| Storage | 30 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | SSH port 22, your IP only |

No other inbound ports are needed. This machine only makes outbound connections.

SSH in:

```bash
chmod 400 devops-launchboard-key.pem
ssh -i devops-launchboard-key.pem ubuntu@YOUR_WORKSTATION_IP
```

Install all tools:

```bash
cd ~
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl wget vim unzip jq ca-certificates gnupg lsb-release

# Docker

sudo install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update

sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin

sudo systemctl enable docker
sudo systemctl start docker

sudo usermod -aG docker ubuntu


# AWS CLI

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip

unzip awscliv2.zip

sudo ./aws/install

rm -rf awscliv2.zip


# kubectl

curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

chmod +x kubectl

sudo mv kubectl /usr/local/bin/kubectl


# eksctl

curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz

sudo mv eksctl /usr/local/bin/eksctl


# Helm

curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash


# Verify

docker --version
aws --version
kubectl version --client
eksctl version
helm version
```

Log out and back in for docker group:

```bash
exit
ssh -i devops-launchboard-key.pem ubuntu@YOUR_WORKSTATION_IP
```

Configure AWS:

```bash
aws configure
```

Enter your Access Key ID, Secret Access Key, region (e.g. `us-east-1`), and `json` for output format.

Verify all tools:

```bash
docker --version
aws --version && aws sts get-caller-identity
kubectl version --client
eksctl version
helm version
```

## Step 2: Clone The Repository

```bash
cd ~
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-7" -f ~/.ssh/devops_launchboard_github_key
cat ~/.ssh/devops_launchboard_github_key.pub
```

Add the public key to GitHub: Repository > Settings > Deploy keys > Add deploy key (read-only).

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

Create working folders:

```bash
mkdir -p deployment/phase-07-cicd-self-hosted/eks
mkdir -p deployment/phase-07-cicd-self-hosted/eks-k8s
mkdir -p .github/workflows
```

Create root `.dockerignore`:

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

## Step 3: Create EKS Cluster

Set variables you will reuse throughout:

```bash
export AWS_REGION=YOUR_AWS_REGION
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export CLUSTER_NAME=devops-launchboard-phase-7
echo "Account: $ACCOUNT_ID  Region: $AWS_REGION  Cluster: $CLUSTER_NAME"
```

Replace `YOUR_AWS_REGION` with your region (e.g. `us-east-1`).

```bash
vim deployment/phase-07-cicd-self-hosted/eks/eksctl-cluster.yaml
```

Paste:

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: devops-launchboard-phase-7
  region: YOUR_AWS_REGION
  version: "1.32"

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
      Environment: phase-7

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

Create the cluster (20 to 40 minutes):

```bash
eksctl create cluster -f deployment/phase-07-cicd-self-hosted/eks/eksctl-cluster.yaml
kubectl get nodes
```

Expected: 2 nodes Ready.

See Phase 8 Step 11 for the full line-by-line explanation of every field in this config.

## Step 4: Install AWS Load Balancer Controller

```bash
cd ~
curl -o aws-load-balancer-controller-policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicyPhase7 \
  --policy-document file://aws-load-balancer-controller-policy.json

eksctl create iamserviceaccount \
  --cluster "$CLUSTER_NAME" \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicyPhase7" \
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

See Phase 8 Step 18 for the full IRSA explanation.

## Step 5: Create Dockerfiles And Nginx Config

### Dockerfile.backend

```bash
vim deployment/phase-07-cicd-self-hosted/Dockerfile.backend
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

### Dockerfile.frontend

```bash
vim deployment/phase-07-cicd-self-hosted/Dockerfile.frontend
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

COPY deployment/phase-07-cicd-self-hosted/nginx-frontend.conf /etc/nginx/conf.d/default.conf
COPY --from=builder --chown=101:101 /app/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

### nginx-frontend.conf

```bash
vim deployment/phase-07-cicd-self-hosted/nginx-frontend.conf
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

See Phase 6 Scenario 1 Steps 12–14 for line-by-line explanations.

## Step 6: Build And Push Initial Images To Docker Hub

The EKS cluster needs images before the first deployment. You push them manually now; after that, the CI/CD workflows handle every subsequent push.

Log in to Docker Hub:

```bash
docker login -u YOUR_DOCKERHUB_USERNAME
```

When prompted, use an access token (Docker Hub > Account Settings > Personal access tokens > Read & Write), not your password.

Build and push:

```bash
cd /opt/devops-launchboard/app-source

docker build -f deployment/phase-07-cicd-self-hosted/Dockerfile.backend \
  -t YOUR_DOCKERHUB_USERNAME/launchboard-backend-k8s:initial .

docker build -f deployment/phase-07-cicd-self-hosted/Dockerfile.frontend \
  --build-arg VITE_API_URL= \
  -t YOUR_DOCKERHUB_USERNAME/launchboard-frontend-k8s:initial .

docker push YOUR_DOCKERHUB_USERNAME/launchboard-backend-k8s:initial
docker push YOUR_DOCKERHUB_USERNAME/launchboard-frontend-k8s:initial
```

Replace `YOUR_DOCKERHUB_USERNAME` with your actual username.

Make sure the Docker Hub repositories are set to **Public** (hub.docker.com > each repo > Settings > Visibility). Public repos let EKS worker nodes pull without an `imagePullSecret`.

## Step 7: Create Kubernetes Manifests And Deploy

```bash
cd /opt/devops-launchboard/app-source
```

Create every file below with `vim` in `deployment/phase-07-cicd-self-hosted/eks-k8s/`.

### namespace.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/eks-k8s/namespace.yaml
```

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: devops-launchboard
  labels:
    app.kubernetes.io/name: devops-launchboard
```

### storageclass.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/eks-k8s/storageclass.yaml
```

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3-encrypted
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
  fsType: ext4
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

### configmap.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/eks-k8s/configmap.yaml
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
  CORS_ORIGINS: http://PLACEHOLDER_UPDATED_AFTER_ALB
  SEED_DEMO_DATA: "true"
  POSTGRES_DB: launchboard
  POSTGRES_USER: launchboard_user
```

### secret.example.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/eks-k8s/secret.example.yaml
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

### pvc.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/eks-k8s/pvc.yaml
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
  storageClassName: gp3-encrypted
  resources:
    requests:
      storage: 5Gi
```

### launchboard-postgres-deployment.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/eks-k8s/launchboard-postgres-deployment.yaml
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
          volumeMounts:
            - name: postgres-data
              mountPath: /var/lib/postgresql/data
          readinessProbe:
            exec:
              command: ["pg_isready", "-U", "launchboard_user", "-d", "launchboard"]
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            exec:
              command: ["pg_isready", "-U", "launchboard_user", "-d", "launchboard"]
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

### launchboard-postgres-service.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/eks-k8s/launchboard-postgres-service.yaml
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

### launchboard-migration-job.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/eks-k8s/launchboard-migration-job.yaml
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
          image: YOUR_DOCKERHUB_USERNAME/launchboard-backend-k8s:initial
          imagePullPolicy: Always
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

### launchboard-backend-deployment.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/eks-k8s/launchboard-backend-deployment.yaml
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
        runAsNonRoot: true
        runAsUser: 999
        runAsGroup: 999
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: backend
          image: YOUR_DOCKERHUB_USERNAME/launchboard-backend-k8s:initial
          imagePullPolicy: Always
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

### launchboard-backend-service.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/eks-k8s/launchboard-backend-service.yaml
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

### launchboard-frontend-deployment.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/eks-k8s/launchboard-frontend-deployment.yaml
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
          image: YOUR_DOCKERHUB_USERNAME/launchboard-frontend-k8s:initial
          imagePullPolicy: Always
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

### launchboard-frontend-service.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/eks-k8s/launchboard-frontend-service.yaml
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

### ingress.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/eks-k8s/ingress.yaml
```

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: launchboard-ingress
  namespace: devops-launchboard
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
    alb.ingress.kubernetes.io/healthcheck-port: "8080"
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: "15"
    alb.ingress.kubernetes.io/healthcheck-timeout-seconds: "5"
    alb.ingress.kubernetes.io/healthy-threshold-count: "2"
    alb.ingress.kubernetes.io/unhealthy-threshold-count: "3"
    alb.ingress.kubernetes.io/tags: Project=devops-launchboard,Environment=phase-7
spec:
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

See Phase 8 Step 14 for the full ALB annotation explanation.

### hpa.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/eks-k8s/hpa.yaml
```

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

### kustomization.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/eks-k8s/kustomization.yaml
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

### Replace placeholders and deploy

```bash
cd /opt/devops-launchboard/app-source
DOCKERHUB_USER=YOUR_DOCKERHUB_USERNAME

sed -i "s|YOUR_DOCKERHUB_USERNAME|${DOCKERHUB_USER}|g" \
  deployment/phase-07-cicd-self-hosted/eks-k8s/launchboard-backend-deployment.yaml \
  deployment/phase-07-cicd-self-hosted/eks-k8s/launchboard-frontend-deployment.yaml \
  deployment/phase-07-cicd-self-hosted/eks-k8s/launchboard-migration-job.yaml
```

Create namespace and Secret:

```bash
kubectl apply -f deployment/phase-07-cicd-self-hosted/eks-k8s/namespace.yaml

kubectl create secret generic launchboard-secret \
  --namespace devops-launchboard \
  --from-literal=POSTGRES_PASSWORD='CHANGE_ME_STRONG_PASSWORD' \
  --from-literal=DATABASE_URL='postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@launchboard-db:5432/launchboard'
```

Apply:

```bash
kubectl apply -k deployment/phase-07-cicd-self-hosted/eks-k8s
```

Wait:

```bash
kubectl -n devops-launchboard rollout status deployment/launchboard-db --timeout=300s
kubectl -n devops-launchboard wait --for=condition=complete job/launchboard-migrate --timeout=300s
kubectl -n devops-launchboard rollout status deployment/launchboard-backend --timeout=300s
kubectl -n devops-launchboard rollout status deployment/launchboard-frontend --timeout=300s
```

Get ALB DNS (wait 2–5 minutes):

```bash
kubectl -n devops-launchboard get ingress launchboard-ingress
```

Update CORS with the ALB DNS:

```bash
ALB_DNS=$(kubectl -n devops-launchboard get ingress launchboard-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB: http://$ALB_DNS"

kubectl -n devops-launchboard patch configmap launchboard-config --type merge \
  -p "{\"data\":{\"CORS_ORIGINS\":\"http://${ALB_DNS}\"}}"
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
```

Verify:

```bash
curl -s "http://$ALB_DNS/health" | jq
curl -s "http://$ALB_DNS/api/summary" | jq
```

Open `http://YOUR_ALB_DNS` in a browser. The app is live on EKS.

## Step 8: Add GitHub Secrets And Variables

Go to your repository: Settings > Secrets and variables > Actions.

Add these **Secrets** (all six are required):

| Name | Value | Where To Find It |
| --- | --- | --- |
| `DOCKERHUB_USERNAME` | Your Docker Hub username | hub.docker.com profile |
| `DOCKERHUB_TOKEN` | Docker Hub access token (Read & Write) | hub.docker.com > Account Settings > Personal access tokens |
| `AWS_ACCESS_KEY_ID` | Your IAM access key ID | IAM Console > Users > Security credentials |
| `AWS_SECRET_ACCESS_KEY` | Your IAM secret access key | Shown once when creating the key |
| `EKS_CLUSTER_NAME` | `devops-launchboard-phase-7` | The cluster name from Step 3 |
| `AWS_REGION` | Your region (e.g. `us-east-1`) | The region your EKS cluster runs in |

Add this **Variable** (under the Variables tab):

| Name | Value |
| --- | --- |
| `EKS_ALB_URL` | `http://YOUR_ALB_DNS_NAME` (the ALB DNS from Step 7) |

Why Secrets vs Variables: AWS credentials and Docker Hub tokens are sensitive — they must be encrypted and masked in logs. The ALB URL is public information, so a Variable is fine.

## Step 9: Create CI/CD Workflows

### build-and-test.yml

```bash
vim .github/workflows/build-and-test.yml
```

Paste:

```yaml
name: build-and-test

on:
  workflow_dispatch:
  pull_request:
    branches: [main]
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  backend:
    name: Backend checks
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: pip
      - name: Install and lint
        working-directory: backend
        run: |
          pip install --upgrade pip
          pip install -e ".[dev]"
          ruff check .
      - name: Smoke test
        working-directory: backend
        run: python -c "from app.main import app; print(app.title)"

  frontend:
    name: Frontend checks
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: npm
          cache-dependency-path: frontend/package-lock.json
      - name: Install, lint, build
        working-directory: frontend
        run: |
          npm ci
          npm run lint
          npm run build
```

### docker-build-push-hub.yml

```bash
vim .github/workflows/docker-build-push-hub.yml
```

Paste:

```yaml
name: docker-build-push-hub

on:
  workflow_dispatch:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  build-scan-push:
    name: Build, scan, push ${{ matrix.component }}
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        include:
          - component: backend
            dockerfile: deployment/phase-07-cicd-self-hosted/Dockerfile.backend
            repo_suffix: launchboard-backend-k8s
          - component: frontend
            dockerfile: deployment/phase-07-cicd-self-hosted/Dockerfile.frontend
            repo_suffix: launchboard-frontend-k8s
    steps:
      - uses: actions/checkout@v4

      - name: Set image variables
        run: |
          echo "IMAGE_TAG=${GITHUB_SHA::7}" >> "$GITHUB_ENV"
          echo "FULL_IMAGE=${{ secrets.DOCKERHUB_USERNAME }}/${{ matrix.repo_suffix }}" >> "$GITHUB_ENV"

      - uses: docker/setup-buildx-action@v3

      - name: Build image
        uses: docker/build-push-action@v6
        with:
          context: .
          file: ${{ matrix.dockerfile }}
          load: true
          push: false
          tags: |
            ${{ env.FULL_IMAGE }}:${{ env.IMAGE_TAG }}
            ${{ env.FULL_IMAGE }}:latest

      - name: Scan with Trivy
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.FULL_IMAGE }}:${{ env.IMAGE_TAG }}
          format: table
          severity: CRITICAL,HIGH
          ignore-unfixed: true
          exit-code: "0"

      - name: Log in to Docker Hub
        if: github.ref == 'refs/heads/main'
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Push to Docker Hub
        if: github.ref == 'refs/heads/main'
        run: |
          docker push ${{ env.FULL_IMAGE }}:${{ env.IMAGE_TAG }}
          docker push ${{ env.FULL_IMAGE }}:latest
```

### deploy-eks.yml

This workflow triggers automatically after the build-push workflow completes successfully. It can also be triggered manually.

```bash
vim .github/workflows/deploy-eks.yml
```

Paste:

```yaml
name: deploy-eks

on:
  workflow_dispatch:
  workflow_run:
    workflows: ["docker-build-push-hub"]
    types: [completed]
    branches: [main]

permissions:
  contents: read

concurrency:
  group: deploy-eks
  cancel-in-progress: false

jobs:
  deploy:
    name: Deploy to EKS
    runs-on: ubuntu-latest
    if: ${{ github.event_name == 'workflow_dispatch' || github.event.workflow_run.conclusion == 'success' }}
    env:
      NAMESPACE: devops-launchboard
    steps:
      - name: Set image tag
        run: |
          if [ "${{ github.event_name }}" = "workflow_dispatch" ]; then
            echo "IMAGE_TAG=${GITHUB_SHA::7}" >> "$GITHUB_ENV"
          else
            FULL_SHA="${{ github.event.workflow_run.head_sha }}"
            echo "IMAGE_TAG=${FULL_SHA::7}" >> "$GITHUB_ENV"
          fi

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Update kubeconfig
        run: |
          aws eks update-kubeconfig \
            --name "${{ secrets.EKS_CLUSTER_NAME }}" \
            --region "${{ secrets.AWS_REGION }}"
          kubectl get nodes

      - name: Update backend image
        run: |
          kubectl -n "${NAMESPACE}" set image deployment/launchboard-backend \
            backend=${{ secrets.DOCKERHUB_USERNAME }}/launchboard-backend-k8s:${IMAGE_TAG}

      - name: Update frontend image
        run: |
          kubectl -n "${NAMESPACE}" set image deployment/launchboard-frontend \
            frontend=${{ secrets.DOCKERHUB_USERNAME }}/launchboard-frontend-k8s:${IMAGE_TAG}

      - name: Wait for rollout
        run: |
          kubectl -n "${NAMESPACE}" rollout status deployment/launchboard-backend --timeout=300s
          kubectl -n "${NAMESPACE}" rollout status deployment/launchboard-frontend --timeout=300s

      - name: Update CORS
        run: |
          if [ -n "${{ vars.EKS_ALB_URL }}" ]; then
            kubectl -n "${NAMESPACE}" patch configmap launchboard-config --type merge \
              -p '{"data":{"CORS_ORIGINS":"${{ vars.EKS_ALB_URL }}"}}'
          fi

      - name: Verify
        run: |
          ALB_URL="${{ vars.EKS_ALB_URL }}"
          if [ -n "$ALB_URL" ]; then
            sleep 10
            curl -fsS "${ALB_URL}/health" || echo "Health check pending"
            curl -fsS "${ALB_URL}/api/summary" | head -c 400 || echo "API pending"
            echo ""
          fi
          echo "Deployed ${IMAGE_TAG}."

      - name: Show deployed images
        run: |
          echo "Backend: $(kubectl -n ${NAMESPACE} get deploy launchboard-backend -o jsonpath='{.spec.template.spec.containers[0].image}')"
          echo "Frontend: $(kubectl -n ${NAMESPACE} get deploy launchboard-frontend -o jsonpath='{.spec.template.spec.containers[0].image}')"
```

### rollback-eks.yml

```bash
vim .github/workflows/rollback-eks.yml
```

Paste:

```yaml
name: rollback-eks

on:
  workflow_dispatch:
    inputs:
      deployment:
        description: Deployment to roll back
        required: true
        type: choice
        options:
          - launchboard-backend
          - launchboard-frontend

permissions:
  contents: read

concurrency:
  group: deploy-eks
  cancel-in-progress: false

jobs:
  rollback:
    name: Roll back ${{ inputs.deployment }}
    runs-on: ubuntu-latest
    env:
      NAMESPACE: devops-launchboard
    steps:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Update kubeconfig
        run: |
          aws eks update-kubeconfig \
            --name "${{ secrets.EKS_CLUSTER_NAME }}" \
            --region "${{ secrets.AWS_REGION }}"

      - name: Show history
        run: kubectl -n "${NAMESPACE}" rollout history deployment/${{ inputs.deployment }}

      - name: Roll back
        run: kubectl -n "${NAMESPACE}" rollout undo deployment/${{ inputs.deployment }}

      - name: Wait
        run: kubectl -n "${NAMESPACE}" rollout status deployment/${{ inputs.deployment }} --timeout=300s

      - name: Show current image
        run: |
          kubectl -n "${NAMESPACE}" get deployment ${{ inputs.deployment }} \
            -o jsonpath='{.spec.template.spec.containers[0].image}'
          echo ""

      - name: Verify
        run: |
          ALB_URL="${{ vars.EKS_ALB_URL }}"
          if [ -n "$ALB_URL" ]; then
            curl -fsS "${ALB_URL}/health" || echo "Health check pending"
            echo "Rollback verified."
          fi
```

## Step 10: Commit, Push, And Watch

```bash
cd /opt/devops-launchboard/app-source
git add .dockerignore .github/workflows deployment/phase-07-cicd-self-hosted
git commit -m "Add Phase 7 CI/CD with Docker Hub and EKS"
git push origin main
```

What happens automatically:

1. `build-and-test` runs lint and tests on a GitHub-hosted runner.
2. `docker-build-push-hub` builds both images, scans with Trivy, pushes to Docker Hub with the commit SHA tag.
3. When step 2 completes successfully, `deploy-eks` triggers automatically, connects to EKS, updates both Deployment images, waits for rollout, and verifies via the ALB.

Watch the Actions tab. Total time from push to verified deployment: about 5 to 8 minutes.

## Step 11: Test The Full CI/CD Loop

Make a visible change:

```bash
vim deployment/phase-07-cicd-self-hosted/eks-k8s/configmap.yaml
```

Change `APP_NAME`:

```yaml
  APP_NAME: DevOps LaunchBoard API v2
```

Commit and push:

```bash
git add deployment/phase-07-cicd-self-hosted/eks-k8s/configmap.yaml
git commit -m "test CI/CD loop"
git push origin main
```

Watch the Actions tab. After all workflows complete, the change is live on EKS. No kubectl commands were typed.

## Step 12: Test Rollback

Go to:

```text
Actions > rollback-eks > Run workflow
```

Choose `launchboard-backend` or `launchboard-frontend` and click Run. The workflow connects to EKS from a GitHub-hosted runner, rolls back, waits, and verifies. No SSH, no self-hosted runner.

## Troubleshooting

### Build-and-test backend fails with ruff F401

If `ruff check .` fails with `imported but unused` on `alembic/env.py`, add `# noqa: F401` to the import line:

```python
from app.models.deployment import Deployment, Service  # noqa: F401
```

Commit and push.

### Deploy fails with "Unable to connect to the server"

AWS credentials in GitHub Secrets are wrong or expired. Verify locally: `aws sts get-caller-identity`. Update the secrets.

### Deploy fails with "You must be logged in to the server"

The IAM user in GitHub Secrets does not have EKS access. The IAM user that created the cluster must match the credentials in Secrets, or update the cluster's `aws-auth` ConfigMap.

### Pods show ImagePullBackOff

Docker Hub repos must be **public**. Check at hub.docker.com > each repo > Settings > Visibility. Also verify the image name and tag match what was pushed.

### Deploy workflow doesn't trigger after build

The `workflow_run` trigger requires the name to match exactly. The `deploy-eks.yml` has `workflows: ["docker-build-push-hub"]` which must match the `name:` in `docker-build-push-hub.yml`.

### ALB returns 502 Bad Gateway

Backend Pods are not ready. Check:

```bash
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard describe pod -l app=launchboard-backend | tail -20
```

### CORS errors in browser

```bash
kubectl -n devops-launchboard get configmap launchboard-config -o jsonpath='{.data.CORS_ORIGINS}'
```

Must exactly match the URL in the browser (including `http://`, no trailing slash). Update the `EKS_ALB_URL` variable in GitHub and re-run the deploy workflow.

## Cleanup

Delete the app (wait 2–3 minutes for ALB deletion):

```bash
kubectl delete namespace devops-launchboard
```

Delete the LB controller:

```bash
helm uninstall aws-load-balancer-controller --namespace kube-system
```

Delete the EKS cluster (10–20 minutes):

```bash
eksctl delete cluster --name devops-launchboard-phase-7 --region "$AWS_REGION"
```

Delete IAM policy:

```bash
aws iam delete-policy \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicyPhase7"
```

Remove GitHub Secrets and Variables (Settings > Secrets > delete each one).

Check AWS Console for leftover resources:

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
[ ] EC2 workstation created and tools installed
[ ] AWS CLI configured and verified
[ ] Repository cloned
[ ] EKS cluster created
[ ] All nodes Ready
[ ] AWS Load Balancer Controller installed
[ ] Docker Hub account with two public repos
[ ] Dockerfiles and nginx config created
[ ] Initial images built and pushed to Docker Hub
[ ] All k8s manifests created in eks-k8s/
[ ] App deployed to EKS
[ ] ALB DNS working in browser
[ ] CORS updated to ALB DNS

=== CI/CD ===
[ ] GitHub Secret: DOCKERHUB_USERNAME
[ ] GitHub Secret: DOCKERHUB_TOKEN
[ ] GitHub Secret: AWS_ACCESS_KEY_ID
[ ] GitHub Secret: AWS_SECRET_ACCESS_KEY
[ ] GitHub Secret: EKS_CLUSTER_NAME
[ ] GitHub Secret: AWS_REGION
[ ] GitHub Variable: EKS_ALB_URL
[ ] build-and-test.yml created
[ ] docker-build-push-hub.yml created
[ ] deploy-eks.yml created
[ ] rollback-eks.yml created
[ ] Push triggers build → scan → push → deploy chain
[ ] Deployed image SHA matches latest commit
[ ] Full CI/CD loop tested with a code change
[ ] Rollback tested from GitHub Actions UI

=== Cleanup ===
[ ] Cleanup plan understood
[ ] AWS Budget reviewed
```

## Reference Documentation

| Topic | Link |
| --- | --- |
| GitHub Actions | https://docs.github.com/en/actions |
| GitHub Actions workflow syntax | https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions |
| GitHub Actions secrets | https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions |
| Docker Hub | https://docs.docker.com/docker-hub/ |
| Docker Hub access tokens | https://docs.docker.com/security/access-tokens/ |
| Docker build-push action | https://github.com/docker/build-push-action |
| Trivy action | https://github.com/aquasecurity/trivy-action |
| AWS configure-credentials action | https://github.com/aws-actions/configure-aws-credentials |
| Amazon EKS | https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html |
| eksctl | https://eksctl.io/ |
| AWS Load Balancer Controller | https://kubernetes-sigs.github.io/aws-load-balancer-controller/ |
| Kubernetes Deployments | https://kubernetes.io/docs/concepts/workloads/controllers/deployment/ |
| kubectl rollout | https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/ |
| kubectl set image | https://kubernetes.io/docs/reference/kubectl/generated/kubectl_set/kubectl_set_image/ |
| EKS pricing | https://aws.amazon.com/eks/pricing/ |

## What To Do Next

Move to:

```text
Phase 8: EKS (deep dive)
```

Phase 7 automated the deployment pipeline. Phase 8 goes deeper into EKS-specific topics: ECR as a private registry, OIDC authentication, EBS CSI driver details, and production EKS operations.
