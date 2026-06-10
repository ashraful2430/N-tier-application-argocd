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
Scenario 9  - (Skipped, covered in a later phase)
Scenario 10 - (Skipped, covered in a later phase)
Scenario 11 - ArgoCD GitOps
Scenario 12 - Production Hardening
```

## Important Notes Before You Start

Read this before doing anything.

**About AWS costs:**

Scenario 1 uses Kind on a single t3.small EC2. That is AWS free-tier eligible.

Scenarios 2 through 12 use kubeadm on t3.medium EC2 instances. t3.medium is not free tier. A t3.medium costs roughly $0.04 per hour. Three t3.medium instances running for 8 hours costs around $1.00. Stop or terminate EC2 instances when you are not using them.

**About following the guide:**

Each scenario tells you exactly what to run. Type commands manually. Do not copy-paste blindly without reading the explanation below each command. The explanation tells you why each command exists, which helps you learn, not just follow steps.

**About the project folder:**

All work lives inside:

```text
/opt/devops-launchboard/app-source
```

Each scenario adds new files to the project. You do not delete previous scenario files unless the guide says to.

---

# Scenario 1: Kubernetes Fundamentals with Kind

## What This Scenario Covers

Kind stands for Kubernetes IN Docker. It creates a Kubernetes cluster by running Kubernetes nodes as Docker containers on your EC2 server. This is a local Kubernetes cluster, meaning everything runs on one machine.

You will use this scenario to:

- Learn how to create a Kubernetes cluster.
- Learn how Pods, Deployments, Services, ConfigMaps, Secrets, Jobs, PVCs, and Ingress work.
- Deploy the N-tier LaunchBoard application into Kubernetes for the first time.
- Understand rolling updates and rollback.

This is your starting point before moving to real multi-node Kubernetes in Scenarios 2 and 3.

## Fresh Start Assumption

This scenario starts from a clean Ubuntu EC2 server.

You do not need to complete any previous phase before using this guide.

This guide assumes:

- You have a fresh AWS EC2 server.
- Docker is not installed yet.
- Kubernetes tools are not installed yet.
- Kind is not installed yet.
- The repository is not cloned yet.
- You will create files with `vim`.
- You will type commands manually.
- You will not use shell scripts.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What You Will Deploy

This scenario deploys the N-tier application into a local Kubernetes cluster created with Kind.

You will deploy:

- PostgreSQL database as a Kubernetes Deployment.
- PostgreSQL PersistentVolumeClaim for database storage.
- Kubernetes Secret for sensitive database values.
- Kubernetes ConfigMap for non-secret application values.
- Alembic migration Job.
- FastAPI backend Deployment with 2 replicas.
- Backend ClusterIP Service.
- React/Vite frontend Deployment with 2 replicas.
- Frontend ClusterIP Service.
- Nginx Ingress Controller.
- Ingress route for public browser traffic.
- Optional HPA example for backend autoscaling.

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
launchboard-frontend Service
  |
  v
launchboard-frontend Pods
  |
  | /api, /health, /ready
  v
launchboard-backend Service
  |
  v
launchboard-backend Pods
  |
  v
launchboard-db Service
  |
  v
PostgreSQL Pod + PVC
```

## Recommended AWS Setup

| Item | Recommended Value |
| --- | --- |
| EC2 Name | `devops-launchboard-phase-6-s1` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` |
| Storage | 25 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | `devops-launchboard-phase-6-sg` |
| SSH Port | `22`, your IP only |
| HTTP Port | `80`, anywhere |
| HTTPS Port | `443`, anywhere |

Do not open these publicly:

```text
8000
5432
6443
```

## Files For This Scenario

```text
deployment/phase-6-kubernetes-local/
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
+-- kind-config.yaml
+-- nginx-frontend.conf
```

## Tool Explanation

| Tool | Purpose |
| --- | --- |
| Docker | Builds container images and runs Kind nodes as containers. |
| Kind | Creates a local Kubernetes cluster using Docker containers as nodes. |
| kubectl | Controls Kubernetes resources from the terminal. |
| Kustomize | Applies multiple Kubernetes YAML files with one command through `kubectl apply -k`. |
| Nginx Ingress Controller | Receives public HTTP traffic and routes it to Kubernetes Services. |
| ConfigMap | Stores non-secret application configuration. |
| Secret | Stores sensitive configuration such as database password and database URL. |
| Deployment | Keeps application Pods running and supports rolling updates. |
| Service | Gives Pods a stable internal DNS name and virtual IP. |
| Job | Runs one-time tasks such as database migrations. |
| PVC | Requests persistent storage for PostgreSQL data. |
| Ingress | Defines public HTTP routing rules. |

## Step 1: Create EC2 Server

Run this step from the AWS Console.

Create one EC2 instance:

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-6-s1` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` |
| Storage | 25 GB gp3 |
| Public IP | Enabled |

Security group inbound rules:

| Type | Port | Source |
| --- | ---: | --- |
| SSH | 22 | Your IP |
| HTTP | 80 | Anywhere |
| HTTPS | 443 | Anywhere |

Why this step exists:

Kind runs Kubernetes nodes as Docker containers. EC2 gives you the Linux server that runs Docker, Kind, kubectl, and the application workload.

## Step 2: SSH Into EC2

Run from your local machine:

```bash
chmod 400 devops-launchboard-key.pem
ssh -i devops-launchboard-key.pem ubuntu@YOUR_EC2_PUBLIC_IP
```

Command explanation:

- `chmod 400` makes the private key readable only by your user.
- `ssh -i` uses that private key to connect to the EC2 server.
- `ubuntu@YOUR_EC2_PUBLIC_IP` means you are logging in as the default Ubuntu user.

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

Command explanation:

- `sudo apt update` refreshes Ubuntu package metadata.
- `sudo apt upgrade -y` installs available package updates.
- `git` is used to clone the repository.
- `curl` and `wget` download tools and test HTTP endpoints.
- `vim` is used to create and edit files.
- `jq` formats JSON output from API responses.
- `ca-certificates`, `gnupg`, `lsb-release` are needed for adding Docker's apt repository securely.

## Step 4: Install Docker Engine

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

Why this step exists:

Kind creates Kubernetes nodes as Docker containers. Without Docker, Kind cannot create the local Kubernetes cluster.

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

Verify:

```bash
kubectl version --client
```

## Step 6: Install Kind

Run:

```bash
cd ~
curl -Lo kind https://kind.sigs.k8s.io/dl/v0.29.0/kind-linux-amd64
chmod +x kind
sudo mv kind /usr/local/bin/kind
```

Verify:

```bash
kind version
```

## Step 7: Create GitHub SSH Key On EC2

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-6-ec2" -f ~/.ssh/devops_launchboard_github_key
cat ~/.ssh/devops_launchboard_github_key.pub
```

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

Expected:

```text
main
```

## Step 9: Create Phase 6 Working Folders

Run:

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-6-kubernetes-local/k8s
```

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

- `kind: Cluster` tells Kind this file describes a cluster.
- `nodes` defines the Kubernetes nodes Kind creates.
- `role: control-plane` creates one control-plane node.
- `node-labels: ingress-ready=true` allows the Ingress Nginx manifest to schedule the controller on this node.
- `extraPortMappings` maps EC2 host ports into the Kind node container so public HTTP traffic reaches the cluster.

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

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3).read()" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
```

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

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

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

## Step 15: Create Kubernetes Manifests

```bash
cd /opt/devops-launchboard/app-source
```

### 15.1 namespace.yaml

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

### 15.2 configmap.yaml

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

Replace `YOUR_EC2_PUBLIC_IP` with your actual EC2 public IP.

### 15.3 secret.example.yaml

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

This is an example file only. Do not commit real passwords to Git. You will create the real Secret with `kubectl` in a later step.

### 15.4 pvc.yaml

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

### 15.5 launchboard-postgres-deployment.yaml

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

### 15.6 launchboard-postgres-service.yaml

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

### 15.7 launchboard-migration-job.yaml

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

### 15.12 ingress.yaml

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

### 15.13 hpa.yaml

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

This file is created now but not applied yet. You will apply it in Scenario 8 after Metrics Server is installed.

### 15.14 kustomization.yaml

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

Note: `secret.example.yaml` and `hpa.yaml` are not listed here on purpose. Secrets are created manually. HPA is added in Scenario 8.

## Step 16: Create Kind Cluster

Run:

```bash
cd /opt/devops-launchboard/app-source/deployment/phase-6-kubernetes-local
kind create cluster --name launchboard-local --config kind-config.yaml
```

Verify:

```bash
kubectl get nodes
kubectl get pods -A
```

## Step 17: Install Nginx Ingress Controller

Run:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
```

Wait:

```bash
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s
```

## Step 18: Build And Load Images Into Kind

Run:

```bash
cd /opt/devops-launchboard/app-source
docker build -f deployment/phase-6-kubernetes-local/Dockerfile.backend -t launchboard-backend:phase-6 .
docker build -f deployment/phase-6-kubernetes-local/Dockerfile.frontend --build-arg VITE_API_URL= -t launchboard-frontend:phase-6 .
kind load docker-image launchboard-backend:phase-6 --name launchboard-local
kind load docker-image launchboard-frontend:phase-6 --name launchboard-local
```

Command explanation:

- `docker build -f ...` builds each image from the repository root.
- `--build-arg VITE_API_URL=` keeps the frontend API URL empty so the browser uses same-origin paths like `/api/summary`.
- `kind load docker-image` copies images from your EC2 Docker into the Kind cluster. Kind nodes do not see EC2 Docker images automatically.

Verify:

```bash
docker images | grep launchboard
```

## Step 19: Create Namespace And Secret

```bash
cd /opt/devops-launchboard/app-source
kubectl apply -f deployment/phase-6-kubernetes-local/k8s/namespace.yaml
```

Create the real Secret:

```bash
kubectl create secret generic launchboard-secret \
  --namespace devops-launchboard \
  --from-literal=POSTGRES_PASSWORD='CHANGE_ME_STRONG_PASSWORD' \
  --from-literal=DATABASE_URL='postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@launchboard-db:5432/launchboard'
```

Replace `CHANGE_ME_STRONG_PASSWORD` with a strong password. Use the same password in both values.

Verify:

```bash
kubectl -n devops-launchboard get secret launchboard-secret
```

## Step 20: Apply Kubernetes Manifests

Run:

```bash
cd /opt/devops-launchboard/app-source
kubectl apply -k deployment/phase-6-kubernetes-local/k8s
```

## Step 21: Verify Kubernetes Resources

Run:

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
Backend Pods: Running
Frontend Pods: Running
Ingress: exists
PVC: Bound
```

## Step 22: Verify The App

Run from EC2:

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
No browser CORS error appears.
```

## Step 23: Test Rollout And Rollback

Build and load a new backend image:

```bash
cd /opt/devops-launchboard/app-source
docker build -f deployment/phase-6-kubernetes-local/Dockerfile.backend -t launchboard-backend:phase-6-v2 .
kind load docker-image launchboard-backend:phase-6-v2 --name launchboard-local
```

Update backend image:

```bash
kubectl -n devops-launchboard set image deployment/launchboard-backend backend=launchboard-backend:phase-6-v2
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

Why this step exists:

Kubernetes Deployments support rolling updates and rollback out of the box. In production, rollback lets you recover quickly when a bad image is deployed. This is one of the most important things to understand before working on a real Kubernetes cluster.

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

Common causes: Secret not created, DATABASE_URL password mismatch, PostgreSQL Pod not ready.

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
curl -I http://127.0.0.1
```

Common causes: Ingress Controller not ready, Kind cluster created without port mappings, AWS security group blocking port 80.

## Cleanup For This Scenario

If you want to clean up before moving to Scenario 2:

```bash
kubectl delete namespace devops-launchboard
kind delete cluster --name launchboard-local
docker rmi launchboard-backend:phase-6 launchboard-backend:phase-6-v2 launchboard-frontend:phase-6 || true
docker system prune -f
```

Then terminate the EC2 instance from the AWS Console.

---

# Scenario 2: Self-Managed Kubernetes with kubeadm (Single Control Plane)

## What This Scenario Covers

In Scenario 1 you used Kind, which is Kubernetes inside Docker containers on one machine. That is great for learning but it is not how real Kubernetes clusters work.

In a real environment, each Kubernetes node is its own server. The control plane node runs the Kubernetes brain (API server, scheduler, etcd). Worker nodes run your application Pods.

kubeadm is the official tool to set up a real Kubernetes cluster on bare Linux servers. You will use it to create a real single-node control plane cluster on an EC2 instance.

In this scenario you will:

- Create a fresh EC2 server for the Kubernetes control plane.
- Install the Kubernetes components (kubelet, kubeadm, kubectl) manually.
- Initialize the cluster with kubeadm.
- Install a Pod network add-on (Flannel) so Pods can communicate.
- Understand what each Kubernetes component does.

After this scenario, your control plane will be running and ready. In Scenario 3 you will add 2 worker nodes to this same cluster.

## What Is The Difference Between Kind And kubeadm

| | Kind | kubeadm |
| --- | --- | --- |
| Nodes | Docker containers on 1 machine | Actual Linux servers |
| Use case | Learning, testing manifests | Real clusters, staging, production |
| Networking | Simulated | Real CNI plugin |
| Persistent volumes | Local storage inside Kind | Real disk on the server |
| Load balancers | Port mappings | MetalLB or cloud LBs |
| Cost | One small EC2 | One EC2 per node |

## AWS Cost Warning

kubeadm requires t3.medium (2 vCPU, 4GB RAM) as the minimum. t3.small does not have enough memory to run Kubernetes components reliably. t3.medium is not AWS free tier. A t3.medium costs roughly $0.04 per hour. Stop or terminate this instance when you are not using it.

## Recommended AWS Setup For Control Plane

| Item | Value |
| --- | --- |
| EC2 Name | `devops-launchboard-k8s-control` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.medium` |
| Storage | 20 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | `devops-launchboard-k8s-sg` |

Security group inbound rules for the control plane:

| Type | Port | Source | Why |
| --- | ---: | --- | --- |
| SSH | 22 | Your IP | Terminal access |
| Custom TCP | 6443 | Your IP, worker node IPs | Kubernetes API server |
| Custom TCP | 2379-2380 | Control plane IP | etcd |
| Custom TCP | 10250 | Control plane IP, worker IPs | kubelet API |
| Custom TCP | 10259 | Control plane IP | kube-scheduler |
| Custom TCP | 10257 | Control plane IP | kube-controller-manager |

You will add worker node IPs to the security group in Scenario 3 after you create those EC2 instances.

## Step 1: Create EC2 For Control Plane

Create one EC2 instance with the values from the table above.

After creating the instance, note the public IP and private IP. You need both.

```text
Control plane public IP:  YOUR_CONTROL_PLANE_PUBLIC_IP
Control plane private IP: YOUR_CONTROL_PLANE_PRIVATE_IP
```

The private IP is shown in the EC2 console under Private IPv4 addresses. It usually starts with `172.31.`.

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

## Step 4: Disable Swap

Kubernetes requires swap to be disabled. If swap is on, kubelet will refuse to start.

Check if swap is on:

```bash
free -h
```

If you see a non-zero value under Swap, disable it:

```bash
sudo swapoff -a
```

Make it permanent so it stays off after reboot:

```bash
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

Verify swap is off:

```bash
free -h
```

Expected: Swap line shows 0B.

Why swap must be off:

Kubernetes needs predictable memory behavior. Swap allows the OS to move RAM data to disk, which causes unpredictable latency. Kubernetes assumes if a Pod needs memory and memory is full, the Pod should be killed (OOMKilled), not swapped to disk. With swap on, that assumption breaks and kubelet refuses to start.

## Step 5: Load Required Kernel Modules

Kubernetes networking needs two kernel modules: `overlay` and `br_netfilter`.

```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

Command explanation:

- `overlay` is used by the container runtime for layered filesystems.
- `br_netfilter` allows iptables to see bridged traffic, which Kubernetes networking depends on.
- `modprobe` loads the modules immediately without a reboot.
- The config file makes them load automatically on reboot.

Verify:

```bash
lsmod | grep overlay
lsmod | grep br_netfilter
```

Both should show output.

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

- `net.bridge.bridge-nf-call-iptables = 1` makes iptables process bridged network traffic. Required for Kubernetes Pod networking.
- `net.ipv4.ip_forward = 1` allows the Linux kernel to forward packets between network interfaces. Required for Pod-to-Pod communication across nodes.
- `sysctl --system` applies all sysctl config files immediately.

Verify:

```bash
sysctl net.bridge.bridge-nf-call-iptables net.ipv4.ip_forward
```

Expected:

```text
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
```

## Step 7: Install containerd

containerd is the container runtime that Kubernetes uses to run containers. Docker Engine also uses containerd internally, but here you install containerd directly without the full Docker Engine.

```bash
sudo apt install -y containerd
```

Create the default containerd configuration:

```bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
```

Enable systemd cgroup driver. This is important. Kubernetes and containerd must use the same cgroup driver or kubelet will fail:

```bash
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
```

Verify the change was applied:

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

Expected: `Active: active (running)`

Why containerd and not Docker:

Kubernetes does not need the full Docker Engine. It needs a container runtime that follows the Container Runtime Interface (CRI). containerd implements CRI directly. Docker Engine adds extra layers on top of containerd that Kubernetes does not use. For a Kubernetes node, using containerd directly is lighter and simpler.

## Step 8: Install kubeadm, kubelet, kubectl

These are the three Kubernetes tools you need on every node.

What each one does:

- `kubelet` is the agent that runs on every node and manages Pods on that node.
- `kubeadm` is the tool you use once to set up the cluster.
- `kubectl` is the CLI you use to talk to the Kubernetes API server.

Add Kubernetes apt repository:

```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

Install:

```bash
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

Command explanation:

- `apt-mark hold` prevents Ubuntu from automatically upgrading these packages. Kubernetes version upgrades must be done carefully and intentionally, not automatically.

Enable kubelet:

```bash
sudo systemctl enable kubelet
```

Verify:

```bash
kubeadm version
kubectl version --client
kubelet --version
```

## Step 9: Initialize The Kubernetes Cluster

This is the most important step. `kubeadm init` creates the Kubernetes control plane.

```bash
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=YOUR_CONTROL_PLANE_PRIVATE_IP
```

Replace `YOUR_CONTROL_PLANE_PRIVATE_IP` with the actual private IP of this EC2 instance.

Why `--pod-network-cidr=10.244.0.0/16`:

This is the IP range Kubernetes assigns to Pods. Flannel (the network plugin you install next) expects this exact range. If you change this, Flannel will not work.

Why `--apiserver-advertise-address` uses the private IP:

The Kubernetes API server advertises this address to worker nodes so they know where to connect. Worker nodes are in the same AWS VPC and reach the control plane through the private IP. The public IP changes if you stop and start the EC2 instance.

This command will take 2 to 3 minutes. At the end you will see output like this:

```text
Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 172.31.X.X:6443 --token XXXX.XXXXXXXXXXXXXXXXXX \
    --discovery-token-ca-cert-hash sha256:XXXXXXXX...
```

Copy the `kubeadm join` command from your output and save it somewhere. You will need it in Scenario 3.

## Step 10: Configure kubectl Access

Run these commands as the ubuntu user (not root):

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Command explanation:

- `admin.conf` is the kubeconfig file created by kubeadm. It contains the API server address and credentials.
- Copying it to `~/.kube/config` lets kubectl find it automatically.
- `chown` gives your ubuntu user ownership of the file.

Verify:

```bash
kubectl get nodes
```

Expected:

```text
NAME       STATUS     ROLES           AGE   VERSION
ip-...     NotReady   control-plane   1m    v1.31.x
```

The node shows `NotReady` because there is no Pod network yet. You fix that in the next step.

## Step 11: Generate A Long-Lived Join Token

The default join token from `kubeadm init` expires in 24 hours. For a student lab where you work at your own pace, generate a token that never expires before you do anything else.

```bash
kubeadm token create --ttl 0 --print-join-command
```

Command explanation:

- `--ttl 0` means the token never expires.
- `--print-join-command` prints the full join command so you can copy it directly.

Save the full output. It looks like:

```text
kubeadm join 172.31.X.X:6443 --token XXXX.XXXXXXXXXXXXXXXXXX --discovery-token-ca-cert-hash sha256:XXXX...
```

You will run this command on the worker nodes in Scenario 3.

## Step 12: Install Flannel Pod Network

Pods on different nodes need a way to talk to each other. Kubernetes does not provide networking itself. You need a CNI (Container Network Interface) plugin. Flannel is a simple and widely used CNI plugin.

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

Verify node is now Ready:

```bash
kubectl get nodes
```

Expected:

```text
NAME       STATUS   ROLES           AGE   VERSION
ip-...     Ready    control-plane   3m    v1.31.x
```

Why Flannel:

Flannel creates a virtual network overlay across all nodes. Each node gets a subnet from the `10.244.0.0/16` range. When a Pod on node A talks to a Pod on node B, Flannel wraps the packet and routes it through the underlying network. This is why `--pod-network-cidr=10.244.0.0/16` matters. Flannel expects that exact range.

## Step 13: Verify Control Plane Components

```bash
kubectl get pods -n kube-system
kubectl get componentstatuses 2>/dev/null || kubectl get --raw='/healthz?verbose' | head -20
```

Expected Pods in `kube-system`:

```text
coredns                - Running
etcd                   - Running
kube-apiserver         - Running
kube-controller-manager - Running
kube-proxy             - Running
kube-scheduler         - Running
```

What each component does:

- `etcd` is the Kubernetes database. All cluster state is stored here.
- `kube-apiserver` is the brain. Every kubectl command talks to this.
- `kube-controller-manager` watches the cluster and makes sure the desired state matches the actual state.
- `kube-scheduler` decides which node a new Pod should run on.
- `coredns` provides DNS for Pods so they can find each other by name.
- `kube-proxy` manages networking rules on each node for Service traffic.

## Step 14: Allow Scheduling On Control Plane (Single Node Only)

By default, Kubernetes does not schedule application Pods on the control plane node. This is a safety measure in production, as the control plane should be dedicated to running Kubernetes components.

In this scenario you only have one node. If you do not remove the taint, no application Pods will run.

Check existing taints:

```bash
kubectl describe node | grep Taint
```

Remove the control-plane taint:

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

Expected:

```text
node/ip-... untainted
```

Important note:

You will re-apply this taint in Scenario 3 after adding worker nodes. In a real cluster with worker nodes, the control plane should not run application Pods.

Verify no taint remains:

```bash
kubectl describe node | grep Taint
```

Expected:

```text
Taints: <none>
```

## Step 15: Verify The Cluster Is Ready

```bash
kubectl get nodes
kubectl get pods -A
```

Expected:

```text
All system Pods: Running
Node status: Ready
```

Your single-node kubeadm cluster is now running. In Scenario 3 you will add 2 worker nodes to this cluster.

---

# Scenario 3: Multi-Node Kubernetes Cluster (1 Control Plane + 2 Workers)

## What This Scenario Covers

Right now you have a single-node Kubernetes cluster from Scenario 2. The control plane node is doing two jobs: running Kubernetes components and running application Pods.

In a real production cluster those jobs are separated. Control plane nodes manage the cluster. Worker nodes run your applications.

In this scenario you will:

- Create 2 new EC2 instances for worker nodes.
- Install Kubernetes components on both workers.
- Join both workers to the control plane from Scenario 2.
- Re-apply the control-plane taint so the control plane no longer runs application Pods.
- Verify that Pods schedule only on worker nodes.

## AWS Setup For Worker Nodes

Create 2 more EC2 instances with these settings:

| Item | Value |
| --- | --- |
| EC2 Name | `devops-launchboard-k8s-worker-1` (and `worker-2`) |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.medium` |
| Storage | 20 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | `devops-launchboard-k8s-worker-sg` |

Security group inbound rules for each worker node:

| Type | Port | Source | Why |
| --- | ---: | --- | --- |
| SSH | 22 | Your IP | Terminal access |
| Custom TCP | 10250 | Control plane private IP | kubelet API |
| Custom TCP | 30000-32767 | Anywhere | NodePort Services |

After creating both workers, note their private IPs:

```text
Worker 1 private IP: YOUR_WORKER_1_PRIVATE_IP
Worker 2 private IP: YOUR_WORKER_2_PRIVATE_IP
```

## Update Control Plane Security Group

Go to the control plane security group `devops-launchboard-k8s-sg` and add these inbound rules:

| Type | Port | Source |
| --- | ---: | --- |
| Custom TCP | 6443 | Worker 1 private IP/32 |
| Custom TCP | 6443 | Worker 2 private IP/32 |
| Custom TCP | 10250 | Worker 1 private IP/32 |
| Custom TCP | 10250 | Worker 2 private IP/32 |

Why: Worker nodes need to reach the API server on port 6443 to register with the cluster and receive work.

## Steps Below Run On Both Worker Nodes

SSH into worker 1 and complete Steps 1 through 6. Then do the same on worker 2.

```bash
ssh -i devops-launchboard-key.pem ubuntu@YOUR_WORKER_1_PUBLIC_IP
```

### Step 1: Update Server

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl wget vim unzip jq ca-certificates gnupg lsb-release apt-transport-https
```

### Step 2: Disable Swap

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

Verify:

```bash
free -h
```

### Step 3: Load Kernel Modules

```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

### Step 4: Set Kernel Networking Parameters

```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

### Step 5: Install containerd

```bash
sudo apt install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd
```

### Step 6: Install kubeadm, kubelet, kubectl

```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet
```

### Step 7: Join The Cluster

Use the join command you saved from Scenario 2 Step 11. It looks like this:

```bash
sudo kubeadm join 172.31.X.X:6443 \
  --token XXXX.XXXXXXXXXXXXXXXXXX \
  --discovery-token-ca-cert-hash sha256:XXXX...
```

Run this command on the worker node as root (with `sudo`).

If you lost the join command, go back to the control plane and regenerate it:

```bash
kubeadm token create --ttl 0 --print-join-command
```

After joining, you will see:

```text
This node has joined the cluster:
* Certificate signing request was sent to apiserver and a response was received.
* The kubelet was notified of the new secure configuration.
```

Repeat Steps 1 through 7 on worker 2.

## Verify From The Control Plane

SSH into the control plane:

```bash
ssh -i devops-launchboard-key.pem ubuntu@YOUR_CONTROL_PLANE_PUBLIC_IP
```

Check nodes:

```bash
kubectl get nodes
```

Expected (wait 1 to 2 minutes for workers to show Ready):

```text
NAME                        STATUS   ROLES           AGE   VERSION
ip-172-31-X-X (control)     Ready    control-plane   20m   v1.31.x
ip-172-31-X-X (worker-1)    Ready    <none>          2m    v1.31.x
ip-172-31-X-X (worker-2)    Ready    <none>          1m    v1.31.x
```

Check node details:

```bash
kubectl get nodes -o wide
```

This shows the private IP, OS, and container runtime of each node.

## Re-Apply Control Plane Taint

In Scenario 2 you removed the control plane taint so Pods could run on the single node. Now that you have worker nodes, re-apply the taint so the control plane is dedicated to Kubernetes components.

```bash
kubectl taint nodes $(kubectl get nodes --selector=node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}') node-role.kubernetes.io/control-plane:NoSchedule
```

Verify:

```bash
kubectl describe node $(kubectl get nodes --selector=node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}') | grep Taint
```

Expected:

```text
Taints: node-role.kubernetes.io/control-plane:NoSchedule
```

Now when you deploy application Pods, Kubernetes will schedule them only on the worker nodes.

## Label Worker Nodes

Labels help you understand and organize your cluster. Add a role label to worker nodes:

```bash
kubectl label node $(kubectl get nodes --selector='!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}') node-role.kubernetes.io/worker=worker
kubectl label node $(kubectl get nodes --selector='!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[1].metadata.name}') node-role.kubernetes.io/worker=worker
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

Your multi-node Kubernetes cluster is ready. In Scenario 4 you will deploy the LaunchBoard application onto this cluster.

---

# Scenario 4: Deploy LaunchBoard on Self-Managed Kubernetes

## What This Scenario Covers

You now have a real 3-node Kubernetes cluster. In this scenario you will deploy the LaunchBoard N-tier application on it.

The application manifests are almost the same as Scenario 1. The key differences are:

- Images are pulled from Docker Hub (no `kind load` needed).
- The Ingress uses MetalLB (installed in Scenario 5) or NodePort as a temporary workaround.
- Deployments spread across 2 worker nodes automatically.

For this scenario you will use a temporary NodePort approach so the app works now, before MetalLB is installed in Scenario 5.

## Files For This Scenario

```text
deployment/phase-6-kubeadm/
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
|   +-- frontend-nodeport-service.yaml
|   +-- kustomization.yaml
```

## Step 1: Prepare The Working Folder

Run on the control plane EC2:

```bash
sudo mkdir -p /opt/devops-launchboard
sudo chown -R ubuntu:ubuntu /opt/devops-launchboard
cd /opt/devops-launchboard
git clone git@github.com:ashraful2430/N-tier-application.git app-source
cd app-source
```

If you already cloned the repository in a previous scenario on this server, skip the clone and just pull:

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

Note: Port `30080` is the NodePort you will create in a moment. After installing MetalLB in Scenario 5, you will update this to use port 80.

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

### frontend-nodeport-service.yaml

This is a temporary NodePort Service. It exposes the frontend on port 30080 of every node's public IP. You will replace this with a proper LoadBalancer Service and Ingress in Scenario 5.

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

- `type: NodePort` opens a port on every node's real IP address.
- `nodePort: 30080` is the port number that opens on every node. You can access the app at `http://WORKER_PUBLIC_IP:30080`.
- NodePort ports must be in the range 30000 to 32767.

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

## Step 3: Create Namespace And Secret

```bash
cd /opt/devops-launchboard/app-source
kubectl apply -f deployment/phase-6-kubeadm/k8s/namespace.yaml

kubectl create secret generic launchboard-secret \
  --namespace devops-launchboard \
  --from-literal=POSTGRES_PASSWORD='CHANGE_ME_STRONG_PASSWORD' \
  --from-literal=DATABASE_URL='postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@launchboard-db:5432/launchboard'
```

Replace `CHANGE_ME_STRONG_PASSWORD` with a strong password. Use the same password in both values.

## Step 4: Apply Manifests

```bash
kubectl apply -k deployment/phase-6-kubeadm/k8s
```

## Step 5: Verify Deployment

```bash
kubectl -n devops-launchboard get all
kubectl -n devops-launchboard get pvc
```

Wait for all Deployments:

```bash
kubectl -n devops-launchboard rollout status deployment/launchboard-db
kubectl -n devops-launchboard rollout status deployment/launchboard-backend
kubectl -n devops-launchboard rollout status deployment/launchboard-frontend
```

Check migration:

```bash
kubectl -n devops-launchboard logs job/launchboard-migrate
```

Verify Pods are spreading across worker nodes:

```bash
kubectl -n devops-launchboard get pods -o wide
```

You should see Pods running on both worker nodes.

## Step 6: Add NodePort To Worker Security Group

The NodePort Service opens port 30080 on every node. You need to allow this in the AWS security group for worker nodes.

Go to the worker security group `devops-launchboard-k8s-worker-sg` and add:

| Type | Port | Source |
| --- | ---: | --- |
| Custom TCP | 30080 | Anywhere |

## Step 7: Verify The App

Open in browser:

```text
http://YOUR_WORKER_1_PUBLIC_IP:30080
```

Or use worker 2:

```text
http://YOUR_WORKER_2_PUBLIC_IP:30080
```

Both will work because NodePort opens the same port on every node.

Run from control plane:

```bash
curl -s http://YOUR_WORKER_1_PUBLIC_IP:30080/health | jq
curl -s http://YOUR_WORKER_1_PUBLIC_IP:30080/api/summary | jq
```

Expected:

```text
Frontend loads.
API works.
No CORS errors.
```

Your application is now running on a real multi-node Kubernetes cluster. In Scenario 5 you will install NGINX Ingress Controller with MetalLB so the app is accessible on the standard port 80.

---

# Scenario 5: NGINX Ingress Controller with MetalLB

## What This Scenario Covers

Right now the app is reachable at `http://WORKER_IP:30080`. That works but it is not how production traffic reaches a Kubernetes cluster. In production you want:

- Traffic entering on port 80 (HTTP) and 443 (HTTPS).
- A single IP address that receives all traffic.
- A routing layer that sends traffic to the right Service based on the request path or hostname.

In a cloud environment (AWS EKS, GKE, AKS) a cloud load balancer handles this automatically when you create a Service with `type: LoadBalancer`. On a self-managed kubeadm cluster there is no cloud load balancer. That is where MetalLB comes in.

MetalLB is a software load balancer for bare-metal Kubernetes. It watches for Services with `type: LoadBalancer` and assigns them a real IP address from a pool you define. When traffic arrives at that IP, MetalLB forwards it into the cluster.

In this scenario you will:

- Install MetalLB and assign it an IP address pool from your worker node IPs.
- Install NGINX Ingress Controller as a LoadBalancer Service.
- Create an Ingress resource to route traffic to the application.
- Update the frontend ConfigMap to use port 80.
- Remove the NodePort Service from Scenario 4.

## How MetalLB Works In This Lab

In a real bare-metal environment, MetalLB uses ARP (Layer 2 mode) or BGP to advertise IP addresses to the network. On EC2, MetalLB Layer 2 mode works because the worker nodes are in the same VPC subnet and can send ARP announcements to each other.

The IP pool you give MetalLB must be:

- IPs that are in the same subnet as your worker nodes.
- IPs that are not already assigned to any EC2 instance.
- IPs that are in the VPC subnet range.

For this lab you will use the private IP of worker 1 as the MetalLB pool. This means the LoadBalancer Service gets that IP, and traffic entering the worker 1 node on port 80 gets forwarded to the Ingress Controller.

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
controller - Running
speaker    - Running (one per node)
```

## Step 2: Configure MetalLB IP Address Pool

You will assign MetalLB a pool containing the private IP of worker 1. MetalLB will assign this IP to LoadBalancer Services.

First, find the private IP of worker 1:

```bash
kubectl get nodes -o wide
```

Note the INTERNAL-IP of one of your worker nodes. Use that IP as a single-IP range for MetalLB.

Create the MetalLB configuration:

```bash
vim /tmp/metallb-config.yaml
```

Paste the content below. Replace `WORKER_1_PRIVATE_IP` with the actual private IP of your worker 1 node (from `kubectl get nodes -o wide`):

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

Explanation:

- `IPAddressPool` defines the IP addresses MetalLB is allowed to assign.
- `/32` means this is a single IP address, not a range.
- `L2Advertisement` tells MetalLB to advertise this IP using ARP (Layer 2). This works within the same VPC subnet.

## Step 3: Install NGINX Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/baremetal/deploy.yaml
```

Wait for the controller to be ready:

```bash
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s
```

## Step 4: Patch Ingress Controller To Use LoadBalancer

The baremetal Ingress Nginx install uses NodePort by default. Patch it to use LoadBalancer so MetalLB assigns it an IP:

```bash
kubectl patch svc ingress-nginx-controller \
  -n ingress-nginx \
  -p '{"spec": {"type": "LoadBalancer"}}'
```

Wait a moment and check the external IP:

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

Expected (after 30 to 60 seconds):

```text
NAME                       TYPE           CLUSTER-IP     EXTERNAL-IP       PORT(S)
ingress-nginx-controller   LoadBalancer   10.96.X.X      WORKER_1_PRIVATE_IP   80:XXXXX/TCP,443:XXXXX/TCP
```

The EXTERNAL-IP should show the private IP of worker 1. This means MetalLB has assigned that IP to the Ingress Controller.

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

Apply:

```bash
kubectl apply -f deployment/phase-6-kubeadm/k8s/ingress.yaml
```

## Step 6: Update kustomization.yaml To Include Ingress

```bash
vim deployment/phase-6-kubeadm/k8s/kustomization.yaml
```

Replace the content with:

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

Note: `frontend-nodeport-service.yaml` is removed. You no longer need NodePort.

## Step 7: Delete NodePort Service And Update ConfigMap

Delete the NodePort Service:

```bash
kubectl -n devops-launchboard delete service launchboard-frontend-nodeport
```

Update the ConfigMap to use port 80:

```bash
vim deployment/phase-6-kubeadm/k8s/configmap.yaml
```

Change `CORS_ORIGINS` to:

```yaml
  CORS_ORIGINS: http://YOUR_WORKER_1_PUBLIC_IP
```

Remove the `:30080` port. Port 80 is the default for HTTP so no port number is needed.

Apply the update:

```bash
kubectl apply -k deployment/phase-6-kubeadm/k8s
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
kubectl -n devops-launchboard rollout restart deployment/launchboard-frontend
```

## Step 8: Update AWS Security Group

The Ingress Controller now listens on port 80 on the MetalLB IP. That IP is the private IP of worker 1. Update the worker security group to allow port 80:

Go to `devops-launchboard-k8s-worker-sg` and add:

| Type | Port | Source |
| --- | ---: | --- |
| HTTP | 80 | Anywhere |
| HTTPS | 443 | Anywhere |

You can remove the port 30080 rule if you want.

## Step 9: Verify

```bash
kubectl -n devops-launchboard get ingress
kubectl get svc -n ingress-nginx
```

Test from control plane:

```bash
curl -I http://YOUR_WORKER_1_PUBLIC_IP
curl -s http://YOUR_WORKER_1_PUBLIC_IP/health | jq
curl -s http://YOUR_WORKER_1_PUBLIC_IP/api/summary | jq
```

Open in browser:

```text
http://YOUR_WORKER_1_PUBLIC_IP
```

Expected:

```text
Frontend loads on port 80.
No port number needed in the URL.
API works.
```

Traffic flow now looks like this:

```text
Browser
  |
  | HTTP port 80
  v
Worker 1 public IP
  |
  v
MetalLB (private IP assigned to Ingress Controller)
  |
  v
NGINX Ingress Controller
  |
  v
launchboard-frontend Service (ClusterIP)
  |
  v
Frontend Pods (on worker nodes)
  |
  | /api, /health, /ready
  v
launchboard-backend Service (ClusterIP)
  |
  v
Backend Pods (on worker nodes)
  |
  v
PostgreSQL Pod
```

---

# Scenario 6: HTTPS with Cert-Manager (Optional, Free with Let's Encrypt)

## What This Scenario Covers

HTTPS means your application traffic is encrypted between the browser and the server. Without HTTPS, passwords and data travel as plain text over the internet.

Cert-Manager is a Kubernetes add-on that automatically requests, issues, and renews TLS certificates. Let's Encrypt is a free certificate authority that issues real, browser-trusted certificates at no cost.

To get a certificate from Let's Encrypt, your domain must be publicly reachable. This means you need a real domain name pointing to your worker IP.

## What You Need For This Scenario

- A domain name or subdomain pointing to `YOUR_WORKER_1_PUBLIC_IP`.
- Port 80 open on that IP (already done in Scenario 5).
- Port 443 open on that IP.

If you do not have a domain, you have two options:

**Option A: Buy a domain.** Cheap domain registrars include:

- Namecheap: https://www.namecheap.com (as cheap as $1 to $3/year for `.xyz` or `.site` domains)
- Cloudflare Registrar: https://www.cloudflare.com/products/registrar/ (at-cost pricing)
- Name.com: https://www.name.com

After buying a domain, create an A record pointing your domain or subdomain to `YOUR_WORKER_1_PUBLIC_IP`.

Example:

```text
A record: launchboard.yourdomain.com -> YOUR_WORKER_1_PUBLIC_IP
```

**Option B: Skip this scenario.** The application works fine on HTTP for this lab. HTTPS is important in production but optional here. If you skip, move directly to Scenario 7.

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
cert-manager           - Running
cert-manager-cainjector - Running
cert-manager-webhook   - Running
```

## Step 2: Create Let's Encrypt ClusterIssuer

A ClusterIssuer tells Cert-Manager where to get certificates from and how to prove domain ownership.

Let's Encrypt uses HTTP-01 challenge to verify you control a domain. It makes a request to `http://YOUR_DOMAIN/.well-known/acme-challenge/TOKEN`. Your Ingress must be publicly reachable for this to work.

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

Replace `YOUR_EMAIL_ADDRESS` with your real email. Let's Encrypt sends certificate expiry reminders to this address.

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

## Step 3: Update Ingress To Request A Certificate

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

Replace `YOUR_DOMAIN` with your actual domain (example: `launchboard.yourdomain.com`).

Apply:

```bash
kubectl apply -f deployment/phase-6-kubeadm/k8s/ingress.yaml
```

## Step 4: Update ConfigMap For HTTPS

```bash
vim deployment/phase-6-kubeadm/k8s/configmap.yaml
```

Update `CORS_ORIGINS`:

```yaml
  CORS_ORIGINS: https://YOUR_DOMAIN
```

Apply:

```bash
kubectl apply -k deployment/phase-6-kubeadm/k8s
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
kubectl -n devops-launchboard rollout restart deployment/launchboard-frontend
```

## Step 5: Monitor Certificate Issuance

```bash
kubectl -n devops-launchboard get certificate
kubectl -n devops-launchboard describe certificate launchboard-tls
```

It takes 1 to 3 minutes for Let's Encrypt to issue the certificate. Watch the events:

```bash
kubectl -n devops-launchboard get certificaterequest
kubectl -n devops-launchboard describe certificaterequest
```

When ready:

```bash
kubectl -n devops-launchboard get certificate
```

Expected:

```text
NAME             READY   SECRET           AGE
launchboard-tls  True    launchboard-tls  2m
```

## Step 6: Verify HTTPS

Open in browser:

```text
https://YOUR_DOMAIN
```

Expected:

```text
Padlock icon appears in the browser.
Certificate is valid.
Frontend loads over HTTPS.
HTTP requests redirect to HTTPS automatically.
```

---

# Scenario 7: Metrics Server

## What This Scenario Covers

Kubernetes has a `kubectl top` command that shows CPU and memory usage for nodes and Pods. By default, this command does not work. It needs Metrics Server to collect resource usage data from each node.

Metrics Server is also required for Horizontal Pod Autoscaler (HPA) to work. Without it, HPA cannot decide when to scale Pods up or down.

In this scenario you will install Metrics Server and use it to observe how much CPU and memory your application Pods are using.

## Step 1: Install Metrics Server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

For a kubeadm cluster on EC2, Metrics Server needs `--kubelet-insecure-tls` because the kubelets use self-signed certificates.

Patch Metrics Server to add this flag:

```bash
kubectl patch deployment metrics-server \
  -n kube-system \
  --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
```

Wait for Metrics Server to be ready:

```bash
kubectl wait --namespace kube-system \
  --for=condition=ready pod \
  --selector=k8s-app=metrics-server \
  --timeout=120s
```

## Step 2: Verify Metrics Server

```bash
kubectl top nodes
```

Expected:

```text
NAME          CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
ip-...        45m          2%     1200Mi          30%
ip-...        38m          1%     980Mi           24%
ip-...        42m          2%     1050Mi          26%
```

Check Pod resource usage:

```bash
kubectl top pods -n devops-launchboard
```

Expected:

```text
NAME                                    CPU(cores)   MEMORY(bytes)
launchboard-backend-XXX                 5m           80Mi
launchboard-backend-XXX                 4m           78Mi
launchboard-db-XXX                      8m           120Mi
launchboard-frontend-XXX               2m           30Mi
launchboard-frontend-XXX               2m           28Mi
```

Why this matters:

Looking at real resource usage helps you set accurate resource requests and limits in your manifests. If your `requests` are too high, Pods cannot schedule. If your `limits` are too low, Pods get killed. Real data from `kubectl top` tells you what your app actually needs.

## Step 3: Compare Actual Usage To Defined Resources

Run:

```bash
kubectl -n devops-launchboard get pods -o custom-columns=\
"NAME:.metadata.name,\
CPU_REQ:.spec.containers[0].resources.requests.cpu,\
CPU_LIM:.spec.containers[0].resources.limits.cpu,\
MEM_REQ:.spec.containers[0].resources.requests.memory,\
MEM_LIM:.spec.containers[0].resources.limits.memory"
```

Compare the output to what you see in `kubectl top pods`. If actual usage is much lower than your limits, you can reduce limits. If actual usage is close to your limits, increase them.

---

# Scenario 8: Horizontal Pod Autoscaler

## What This Scenario Covers

Horizontal Pod Autoscaler (HPA) watches the CPU or memory usage of a Deployment and automatically increases or decreases the number of Pods to match the load.

For example: you define a backend Deployment with `minReplicas: 2` and `maxReplicas: 5`. When CPU usage per Pod exceeds 70%, HPA adds more Pods. When load drops, HPA removes extra Pods. This means your application scales automatically without you doing anything.

HPA requires Metrics Server (installed in Scenario 7) to read CPU usage data.

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

Apply:

```bash
kubectl apply -f deployment/phase-6-kubeadm/k8s/hpa.yaml
```

## Step 2: Verify HPA

```bash
kubectl -n devops-launchboard get hpa
```

Expected:

```text
NAME                      REFERENCE                       TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
launchboard-backend-hpa   Deployment/launchboard-backend  3%/70%    2         5         2          1m
```

The `TARGETS` column shows current CPU usage / target. Here it shows 3%/70% meaning current usage is 3% and the target is 70%.

## Step 3: Test Autoscaling With A Load Generator

Install a simple load generator:

```bash
kubectl run load-generator \
  --image=busybox:1.28 \
  --restart=Never \
  -n devops-launchboard \
  -- /bin/sh -c "while true; do wget -q -O- http://launchboard-backend:8000/health > /dev/null; done"
```

Watch HPA react:

```bash
kubectl -n devops-launchboard get hpa -w
```

Within 1 to 2 minutes you should see REPLICAS increase as CPU usage goes up.

Watch Pods being created:

```bash
kubectl -n devops-launchboard get pods -w
```

Stop the load generator:

```bash
kubectl delete pod load-generator -n devops-launchboard
```

Watch Pods scale back down. HPA waits 5 minutes of low usage before scaling down to avoid thrashing.

## Step 4: Add HPA To kustomization.yaml

```bash
vim deployment/phase-6-kubeadm/k8s/kustomization.yaml
```

Add `hpa.yaml` to the resources list:

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

---

# Scenario 11: ArgoCD GitOps

## What This Scenario Covers

Until now you deployed the application by running `kubectl apply` manually from the terminal. In production, manual deployments are risky and hard to track. Someone might apply the wrong manifest, forget to apply a change, or deploy from a laptop that has different files than the Git repository.

GitOps solves this. The idea is simple: Git is the source of truth. Your Kubernetes cluster should always match what is in Git. ArgoCD watches your Git repository and automatically applies any changes it detects.

In this scenario you will:

- Install ArgoCD on your cluster.
- Create an ArgoCD Application that points to your Kubernetes manifests in Git.
- Let ArgoCD deploy the application instead of running `kubectl apply` manually.
- Make a change in Git and watch ArgoCD detect and apply it automatically.

## How ArgoCD Works

```text
You push a change to Git
  |
  v
ArgoCD detects the change (polls every 3 minutes, or on webhook)
  |
  v
ArgoCD compares Git state to cluster state
  |
  v
ArgoCD applies the diff to the cluster
  |
  v
Cluster matches Git
```

## Step 1: Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Wait for ArgoCD Pods:

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
argocd-application-controller  - Running
argocd-dex-server               - Running
argocd-redis                    - Running
argocd-repo-server              - Running
argocd-server                   - Running
```

## Step 2: Expose ArgoCD UI With NodePort

ArgoCD has a web UI. You will expose it using NodePort so you can access it from your browser without a domain.

```bash
kubectl patch svc argocd-server \
  -n argocd \
  -p '{"spec": {"type": "NodePort"}}'
```

Find the NodePort:

```bash
kubectl get svc argocd-server -n argocd
```

Expected:

```text
NAME           TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)
argocd-server  NodePort   10.96.X.X     <none>         80:3XXXX/TCP,443:3XXXX/TCP
```

Note the port mapped to 443 (the HTTPS port for ArgoCD). It will be something like `32443`.

Add this port to the worker security group:

Go to `devops-launchboard-k8s-worker-sg` and add:

| Type | Port | Source |
| --- | ---: | --- |
| Custom TCP | YOUR_ARGOCD_NODEPORT | Your IP |

Open in browser:

```text
https://YOUR_WORKER_1_PUBLIC_IP:YOUR_ARGOCD_NODEPORT
```

Your browser will show a certificate warning because ArgoCD uses a self-signed certificate. Click Advanced and proceed. This is expected in a lab.

## Step 3: Get ArgoCD Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Log in to the ArgoCD UI:

```text
Username: admin
Password: output from the command above
```

## Step 4: Install ArgoCD CLI

```bash
cd ~
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/argocd
```

Log in from the terminal:

```bash
ARGOCD_PORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.port==443)].nodePort}')
argocd login YOUR_WORKER_1_PUBLIC_IP:${ARGOCD_PORT} \
  --username admin \
  --password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d) \
  --insecure
```

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

- `--repo` points to your GitHub repository using HTTPS (no SSH key needed for ArgoCD to read a public repo).
- `--path` is the folder inside the repository that contains your Kubernetes manifests.
- `--dest-server https://kubernetes.default.svc` means deploy to the same cluster ArgoCD is running on.
- `--dest-namespace devops-launchboard` deploys into the application namespace.
- `--sync-policy automated` makes ArgoCD apply changes automatically when Git changes.
- `--auto-prune` removes resources from the cluster when they are deleted from Git.
- `--self-heal` re-applies changes if someone manually modifies the cluster outside of Git.

## Step 6: Verify ArgoCD Sync

Check the application status:

```bash
argocd app get launchboard
```

Expected:

```text
Health Status: Healthy
Sync Status:   Synced
```

In the ArgoCD UI you can see a visual graph of all the Kubernetes resources belonging to this application, their health status, and when they were last synced.

## Step 7: Test GitOps In Action

Make a change to your Git repository to see ArgoCD detect and apply it automatically.

On your local machine (or the EC2 server with git configured), edit the backend Deployment to change the replica count:

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

Watch ArgoCD detect the change:

```bash
argocd app get launchboard
```

Within 3 minutes (ArgoCD's default poll interval), the sync status will change from `Synced` to `OutOfSync`, then ArgoCD will apply the change and return to `Synced`.

Verify the replica count increased:

```bash
kubectl -n devops-launchboard get pods -l app=launchboard-backend
```

Expected:

```text
3 backend Pods running.
```

Revert the change:

```bash
vim deployment/phase-6-kubeadm/k8s/launchboard-backend-deployment.yaml
```

Change `replicas: 3` back to `replicas: 2`, commit, and push. ArgoCD will scale back down.

## Step 8: Change ArgoCD Admin Password

Change the default password to something you know:

```bash
argocd account update-password \
  --account admin \
  --current-password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d) \
  --new-password YOUR_NEW_PASSWORD
```

---

# Scenario 12: Production Hardening

## What This Scenario Covers

The application is running and ArgoCD manages deployments. In this final scenario you apply production-level security and reliability measures that are standard in real Kubernetes environments.

You will cover:

- Pod Security Standards (replace the old PodSecurityPolicy)
- NetworkPolicy (restrict which Pods can talk to which)
- ResourceQuota (limit total resource usage in the namespace)
- RBAC (Role-Based Access Control)
- Pod Disruption Budgets (prevent too many Pods going down at once)
- Image Pull Policy hardening
- Namespace-level security labels

Each section explains why it matters in a real environment.

## Step 1: Create The Hardening Folder

```bash
mkdir -p deployment/phase-6-kubeadm/hardening
cd /opt/devops-launchboard/app-source
```

## Step 2: Pod Security Standards

Pod Security Standards are built into Kubernetes. You apply them to namespaces using labels. They enforce rules on what Pods are allowed to do.

There are three levels:

- `privileged`: no restrictions (only for trusted system workloads)
- `baseline`: blocks the most dangerous capabilities
- `restricted`: most secure, requires non-root, drops all capabilities

Your application already runs as non-root. The `restricted` level fits.

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

Explanation:

- `enforce` means Pods that violate the policy are rejected.
- `warn` means a warning is shown but the Pod still runs.
- `audit` means violations are logged.
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
Error from server (Forbidden): ... violates PodSecurity...
```

Clean up (the Pod was not created, but clean up if any partial resource exists):

```bash
kubectl delete pod test-privileged -n devops-launchboard --ignore-not-found
```

## Step 3: NetworkPolicy

By default, all Pods in Kubernetes can talk to all other Pods in the cluster. This is a security risk. If an attacker gets into the frontend Pod, they can reach the database directly.

NetworkPolicy restricts which Pods can communicate with which. You define rules like: "the backend is only allowed to receive traffic from the frontend" and "the database is only allowed to receive traffic from the backend."

Create the NetworkPolicy manifests:

```bash
vim deployment/phase-6-kubeadm/hardening/networkpolicy.yaml
```

Paste:

```yaml
# Deny all traffic by default in this namespace
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
# Allow frontend to receive traffic from Ingress Controller
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
# Allow frontend to call backend
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
# Allow backend to call database
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
# Allow all Pods to make DNS queries to CoreDNS
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
# Allow backend and frontend egress to each other (for proxy calls)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-app-egress
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

Apply:

```bash
kubectl apply -f deployment/phase-6-kubeadm/hardening/networkpolicy.yaml
```

Verify the app still works after applying NetworkPolicy:

```bash
curl -s http://YOUR_WORKER_1_PUBLIC_IP/health | jq
curl -s http://YOUR_WORKER_1_PUBLIC_IP/api/summary | jq
```

If something breaks, check which NetworkPolicy is blocking traffic:

```bash
kubectl -n devops-launchboard get networkpolicy
kubectl -n devops-launchboard describe networkpolicy default-deny-all
```

Note: NetworkPolicy enforcement requires the CNI plugin to support it. Flannel does not enforce NetworkPolicy by default. To enable enforcement, you need to install a NetworkPolicy controller alongside Flannel. For this lab, install `kube-router` as the policy enforcer:

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

## Step 4: ResourceQuota

ResourceQuota limits the total CPU and memory that all Pods in a namespace can use combined. This prevents one namespace from consuming all cluster resources.

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

Apply:

```bash
kubectl apply -f deployment/phase-6-kubeadm/hardening/resourcequota.yaml
```

View current usage:

```bash
kubectl -n devops-launchboard describe resourcequota launchboard-quota
```

This shows how much of the quota is used versus how much is available.

## Step 5: RBAC

Role-Based Access Control defines who can do what in Kubernetes. Instead of giving everyone full cluster admin access, you create specific roles with specific permissions.

For this lab, create a read-only role for a developer who needs to see Pod status and logs but cannot modify anything.

```bash
vim deployment/phase-6-kubeadm/hardening/rbac.yaml
```

Paste:

```yaml
# Role: read-only access to core resources in devops-launchboard namespace
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
# RoleBinding: bind the role to a user named "developer"
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

Apply:

```bash
kubectl apply -f deployment/phase-6-kubeadm/hardening/rbac.yaml
```

Verify:

```bash
kubectl -n devops-launchboard get role
kubectl -n devops-launchboard get rolebinding
```

Test what the developer user would be allowed to do:

```bash
kubectl auth can-i get pods -n devops-launchboard --as=developer
kubectl auth can-i delete pods -n devops-launchboard --as=developer
kubectl auth can-i create deployments -n devops-launchboard --as=developer
```

Expected:

```text
get pods:        yes
delete pods:     no
create deployments: no
```

## Step 6: Pod Disruption Budgets

A Pod Disruption Budget (PDB) tells Kubernetes: "when you do maintenance or drain a node, make sure at least N Pods of this Deployment are always running."

Without a PDB, Kubernetes might drain a node and take down all replicas of a Deployment at the same time, causing downtime.

```bash
vim deployment/phase-6-kubeadm/hardening/pdb.yaml
```

Paste:

```yaml
# Backend: always keep at least 1 Pod running during disruptions
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
# Frontend: always keep at least 1 Pod running during disruptions
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

`ALLOWED DISRUPTIONS: 1` means Kubernetes can safely take down 1 Pod during maintenance because 1 will always stay running.

## Step 7: Verify The Full Production Setup

Run these commands to confirm everything is healthy:

```bash
# All nodes ready
kubectl get nodes

# All Pods running
kubectl -n devops-launchboard get pods -o wide

# Resources within quota
kubectl -n devops-launchboard describe resourcequota launchboard-quota

# Network policies in place
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
[x] NetworkPolicy             - Pods can only talk to who they need to talk to
[x] ResourceQuota             - Namespace cannot consume unlimited cluster resources
[x] RBAC                      - Users get only the permissions they need
[x] Pod Disruption Budgets    - Maintenance cannot take down all replicas at once
[x] Resource requests/limits  - Every Pod has CPU and memory boundaries
[x] Non-root containers       - All app containers run as non-root users
[x] Readiness/liveness probes - Bad Pods stop receiving traffic and get restarted
[x] Rolling updates           - New versions deploy without downtime
[x] ArgoCD GitOps             - All changes go through Git, not manual kubectl
[x] Metrics Server            - Resource usage is visible
[x] HPA                       - Backend scales automatically under load
```

---

# Full Production Checklist

```text
Scenario 1 - Kind
[ ] EC2 t3.small created
[ ] Docker, kubectl, Kind installed
[ ] Kind cluster created with port mappings
[ ] Ingress Nginx installed
[ ] Images built and loaded
[ ] Namespace and Secret created
[ ] Manifests applied
[ ] App accessible on port 80
[ ] Rollout and rollback tested

Scenario 2 - kubeadm Control Plane
[ ] EC2 t3.medium created
[ ] Swap disabled
[ ] Kernel modules loaded
[ ] Sysctl networking set
[ ] containerd installed with SystemdCgroup=true
[ ] kubeadm, kubelet, kubectl installed
[ ] kubeadm init run
[ ] kubeconfig configured
[ ] Never-expiring join token generated
[ ] Flannel installed
[ ] Node shows Ready
[ ] Control plane taint removed (single node)

Scenario 3 - Worker Nodes
[ ] 2 x EC2 t3.medium created for workers
[ ] Security groups updated
[ ] Workers prepared (swap, modules, sysctl, containerd, k8s tools)
[ ] Workers joined with kubeadm join
[ ] All 3 nodes show Ready
[ ] Control plane taint re-applied
[ ] Workers labeled

Scenario 4 - App On kubeadm
[ ] Manifests created in deployment/phase-6-kubeadm/k8s
[ ] Namespace and Secret created
[ ] App deployed with kustomize
[ ] Pods spread across workers
[ ] App accessible on NodePort 30080

Scenario 5 - Ingress + MetalLB
[ ] MetalLB installed
[ ] IP pool configured with worker private IP
[ ] Ingress Nginx installed as LoadBalancer
[ ] MetalLB assigned external IP to Ingress Controller
[ ] Ingress resource created
[ ] NodePort Service removed
[ ] App accessible on port 80

Scenario 6 - HTTPS (Optional)
[ ] Domain pointing to worker IP
[ ] Cert-Manager installed
[ ] ClusterIssuer created
[ ] Ingress updated with TLS
[ ] Certificate issued by Let's Encrypt
[ ] App accessible on HTTPS

Scenario 7 - Metrics Server
[ ] Metrics Server installed
[ ] kubelet-insecure-tls flag added
[ ] kubectl top nodes works
[ ] kubectl top pods works

Scenario 8 - HPA
[ ] HPA manifest created
[ ] HPA applied
[ ] Load test run
[ ] Pods scaled up under load
[ ] Pods scaled down after load

Scenario 11 - ArgoCD
[ ] ArgoCD installed
[ ] ArgoCD UI exposed via NodePort
[ ] ArgoCD Application created
[ ] Cluster synced with Git
[ ] GitOps change tested

Scenario 12 - Production Hardening
[ ] Pod Security Standards applied
[ ] NetworkPolicy applied
[ ] ResourceQuota applied
[ ] RBAC role and binding created
[ ] Pod Disruption Budgets applied
[ ] App still works after hardening
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

## Delete Monitoring Tools

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

Go to the AWS Console and terminate:

```text
devops-launchboard-k8s-control
devops-launchboard-k8s-worker-1
devops-launchboard-k8s-worker-2
devops-launchboard-phase-6-s1 (Kind scenario)
```

Also:

- Delete any unused EBS volumes.
- Release unused Elastic IPs.
- Check AWS Billing to confirm no unexpected charges.

---

# Reference Documentation

| Topic | Link |
| --- | --- |
| Kubernetes docs | https://kubernetes.io/docs/ |
| kubeadm install | https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ |
| kubectl install | https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/ |
| Kind quick start | https://kind.sigs.k8s.io/docs/user/quick-start/ |
| Flannel | https://github.com/flannel-io/flannel |
| MetalLB | https://metallb.universe.tf/ |
| Ingress Nginx | https://kubernetes.github.io/ingress-nginx/ |
| Cert-Manager | https://cert-manager.io/docs/ |
| Let's Encrypt | https://letsencrypt.org/ |
| Metrics Server | https://github.com/kubernetes-sigs/metrics-server |
| HPA | https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/ |
| ArgoCD | https://argo-cd.readthedocs.io/ |
| NetworkPolicy | https://kubernetes.io/docs/concepts/services-networking/network-policies/ |
| Pod Security Standards | https://kubernetes.io/docs/concepts/security/pod-security-standards/ |
| RBAC | https://kubernetes.io/docs/reference/access-authn-authz/rbac/ |
| PodDisruptionBudget | https://kubernetes.io/docs/tasks/run-application/configure-pdb/ |
| ResourceQuota | https://kubernetes.io/docs/concepts/policy/resource-quotas/ |

---

# What To Do Next

Move to:

```text
Phase 7: CI/CD
```

Phase 6 taught you how Kubernetes works from the ground up: local clusters with Kind, real clusters with kubeadm, multi-node setups, traffic routing with MetalLB and Ingress, autoscaling, GitOps with ArgoCD, and production-level security. Phase 7 teaches how to automate the image build and deployment pipeline so changes in code automatically flow all the way to the cluster.
