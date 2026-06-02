# Phase 6: Kubernetes Local

## Fresh Start Assumption

This phase starts from a clean Ubuntu EC2 server.

You do not need to complete any previous phase before using this guide.

This guide assumes:

- You have a fresh AWS EC2 server.
- Docker is not installed yet.
- Kubernetes tools are not installed yet.
- The repository is not cloned yet.
- You will create files with `vim`.
- You will type commands manually.
- You will not use shell scripts.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What You Will Deploy

This phase deploys the N-tier application into a local Kubernetes cluster created with Kind:

- PostgreSQL Deployment.
- PostgreSQL PersistentVolumeClaim.
- Kubernetes Secret for database password and backend database URL.
- ConfigMap for non-secret app settings.
- Alembic migration Job.
- FastAPI backend Deployment with 2 replicas.
- Backend ClusterIP Service.
- React/Vite frontend Deployment with 2 replicas.
- Frontend ClusterIP Service.
- Nginx Ingress Controller.
- Ingress route for public browser traffic.
- HPA example for backend scaling.

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

## When To Use This Architecture

Use local Kubernetes when:

- You want to learn Kubernetes objects before using EKS.
- You want a low-cost lab on one server.
- You want to understand Pods, Deployments, Jobs, Services, ConfigMaps, Secrets, Ingress, PVCs, probes, and HPA.
- You want to test Kubernetes manifests before cloud Kubernetes.

Do not use local Kubernetes when:

- You need real production high availability.
- You need managed node groups, load balancers, and cloud storage.
- You need multiple worker nodes.
- You need production-grade database backups.

Important note:

Kind is excellent for learning and local validation. It is not a replacement for production Kubernetes platforms like EKS, GKE, AKS, or a properly operated self-managed cluster.

## Recommended AWS Setup

| Item | Recommended Value |
| --- | --- |
| EC2 Name | `devops-launchboard-phase-6` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` |
| Storage | 25 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | `devops-launchboard-phase-6-sg` |
| SSH Port | `22`, your IP only |
| HTTP Port | `80`, anywhere |
| HTTPS Port | `443`, anywhere if you later test HTTPS |

Do not open these publicly:

```text
8000
5432
6443
```

Why:

- `8000` is backend traffic inside Kubernetes.
- `5432` is PostgreSQL traffic inside Kubernetes.
- `6443` is Kubernetes API traffic and should not be public in this student lab.

## Files Included In This Phase

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
+-- README.md
```

The README shows all file contents inline so students can create the files while reading from GitHub.

## Step 1: Create EC2 Server

Run this step from the AWS Console.

Create one EC2 instance:

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-6` |
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

Kind runs a Kubernetes cluster inside Docker containers. EC2 gives you the Linux server that runs Docker, Kind, and the Kubernetes workload.

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

Why this step exists:

The server needs tools for cloning, installing Docker, installing Kubernetes tools, editing files, and testing HTTP endpoints.

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

Kind creates Kubernetes nodes as Docker containers. Without Docker, Kind cannot create the local cluster.

Reference:

- Docker Engine Ubuntu install: https://docs.docker.com/engine/install/ubuntu/

## Step 5: Install Kubectl

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

Why this step exists:

`kubectl` is the command-line tool used to create, inspect, update, and delete Kubernetes resources.

Reference:

- Install kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/

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

Why this step exists:

Kind creates a local Kubernetes cluster using Docker containers as nodes.

Reference:

- Kind quick start: https://kind.sigs.k8s.io/docs/user/quick-start/

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

Reference:

- GitHub SSH docs: https://docs.github.com/en/authentication/connecting-to-github-with-ssh

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

Why this folder exists:

The phase folder keeps Dockerfiles, Kind config, Nginx config, and Kubernetes manifests together.

## Step 10: Create Root `.dockerignore`

Run:

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
deployment/phase-4-docker-compose/.env
```

Why this file exists:

Docker builds use the repository root as context. This file keeps local dependencies, caches, build output, and secrets out of images.

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

Explanation:

- `kind: Cluster` tells Kind this file describes a cluster.
- `control-plane` creates one Kubernetes control-plane node.
- `node-labels: ingress-ready=true` lets the Kind Ingress Nginx manifest schedule the controller on this node.
- `extraPortMappings` maps EC2 port `80` and `443` into the Kind node.
- This allows the browser to reach the Ingress Controller through the EC2 public IP.

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
    && pip install --no-cache-dir .

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

Explanation:

This Dockerfile builds the FastAPI backend image. It uses a multi-stage build, installs dependencies into a virtual environment, and runs as a non-root user.

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

FROM nginx:1.27-alpine AS runtime

RUN addgroup -S app \
    && adduser -S app -G app \
    && mkdir -p /var/cache/nginx/client_temp /var/cache/nginx/proxy_temp /var/cache/nginx/fastcgi_temp /var/cache/nginx/uwsgi_temp /var/cache/nginx/scgi_temp /var/run /tmp/nginx \
    && chown -R app:app /usr/share/nginx/html /var/cache/nginx /var/run /tmp/nginx

COPY deployment/phase-6-kubernetes-local/nginx-frontend.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html

USER app

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

Explanation:

This Dockerfile builds the frontend and serves it with Nginx. `VITE_API_URL` stays empty so the frontend uses same-origin requests like `/api/summary`.

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

Explanation:

Nginx serves the frontend and proxies backend requests to the Kubernetes Service named `launchboard-backend`.

## Step 15: Create Kubernetes Manifests

Create each file from the repository root.

### `namespace.yaml`

```bash
vim deployment/phase-6-kubernetes-local/k8s/namespace.yaml
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

Why this file exists:

A Namespace groups all app resources and makes cleanup easier.

### `configmap.yaml`

```bash
vim deployment/phase-6-kubernetes-local/k8s/configmap.yaml
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
  CORS_ORIGINS: http://YOUR_EC2_PUBLIC_IP
  SEED_DEMO_DATA: "true"
  POSTGRES_DB: launchboard
  POSTGRES_USER: launchboard_user
```

Replace:

```text
YOUR_EC2_PUBLIC_IP
```

Why this file exists:

A ConfigMap stores non-secret configuration. The backend and database read these values as environment variables.

### `secret.example.yaml`

```bash
vim deployment/phase-6-kubernetes-local/k8s/secret.example.yaml
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

Why this file exists:

This is an example only. The guide creates the real Secret with `kubectl create secret` so real passwords do not need to be saved in Git.

### `pvc.yaml`

```bash
vim deployment/phase-6-kubernetes-local/k8s/pvc.yaml
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
  resources:
    requests:
      storage: 5Gi
```

Why this file exists:

PostgreSQL needs persistent storage. A PVC asks Kubernetes for storage that survives Pod restarts.

### `launchboard-postgres-deployment.yaml`

```bash
vim deployment/phase-6-kubernetes-local/k8s/launchboard-postgres-deployment.yaml
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

Why this file exists:

This runs PostgreSQL inside Kubernetes. `Recreate` is used because one local PostgreSQL PVC should not be mounted by multiple Pods at the same time.

### `launchboard-postgres-service.yaml`

```bash
vim deployment/phase-6-kubernetes-local/k8s/launchboard-postgres-service.yaml
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

Why this file exists:

The Service gives PostgreSQL a stable DNS name: `launchboard-db`.

### `launchboard-migration-job.yaml`

```bash
vim deployment/phase-6-kubernetes-local/k8s/launchboard-migration-job.yaml
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

Why this file exists:

The Job runs database migrations once. Jobs are better than using a long-running backend Pod for one-time setup work.

The wait loop gives PostgreSQL time to become reachable before Alembic starts.

### `launchboard-backend-deployment.yaml`

```bash
vim deployment/phase-6-kubernetes-local/k8s/launchboard-backend-deployment.yaml
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

Why this file exists:

This runs the FastAPI backend with two replicas, rolling updates, health checks, and resource limits.

The command waits for PostgreSQL before starting Uvicorn. This makes the first startup easier for students to troubleshoot.

### `launchboard-backend-service.yaml`

```bash
vim deployment/phase-6-kubernetes-local/k8s/launchboard-backend-service.yaml
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

Why this file exists:

The Service gives backend Pods a stable DNS name: `launchboard-backend`.

### `launchboard-frontend-deployment.yaml`

```bash
vim deployment/phase-6-kubernetes-local/k8s/launchboard-frontend-deployment.yaml
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

Why this file exists:

This runs the frontend Nginx container with two replicas.

### `launchboard-frontend-service.yaml`

```bash
vim deployment/phase-6-kubernetes-local/k8s/launchboard-frontend-service.yaml
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

Why this file exists:

The Ingress sends traffic to this Service.

### `ingress.yaml`

```bash
vim deployment/phase-6-kubernetes-local/k8s/ingress.yaml
```

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

Why this file exists:

Ingress is the public HTTP entry point. It sends browser traffic to the frontend Service.

### `hpa.yaml`

```bash
vim deployment/phase-6-kubernetes-local/k8s/hpa.yaml
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

Why this file exists:

The HPA shows how Kubernetes can scale backend replicas based on CPU usage. In Kind, full HPA behavior may need metrics-server.

### `kustomization.yaml`

```bash
vim deployment/phase-6-kubernetes-local/k8s/kustomization.yaml
```

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

Why this file exists:

Kustomize lets students apply many Kubernetes manifests with one command.

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

Why this step exists:

This creates the local Kubernetes cluster where the app will run.

## Step 17: Install Nginx Ingress Controller

Run:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
```

Wait:

```bash
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=180s
```

Why this step exists:

Ingress resources need an Ingress Controller. This installs Nginx Ingress for Kind.

Reference:

- Kind ingress guide: https://kind.sigs.k8s.io/docs/user/ingress/
- Ingress Nginx docs: https://kubernetes.github.io/ingress-nginx/

## Step 18: Build Images And Load Them Into Kind

Run:

```bash
cd /opt/devops-launchboard/app-source
docker build -f deployment/phase-6-kubernetes-local/Dockerfile.backend -t launchboard-backend:phase-6 .
docker build -f deployment/phase-6-kubernetes-local/Dockerfile.frontend --build-arg VITE_API_URL= -t launchboard-frontend:phase-6 .
kind load docker-image launchboard-backend:phase-6 --name launchboard-local
kind load docker-image launchboard-frontend:phase-6 --name launchboard-local
```

Verify:

```bash
docker images | grep launchboard
```

Why this step exists:

Kind nodes cannot automatically see images built on the host. `kind load docker-image` copies the local Docker images into the Kind cluster.

## Step 19: Create Namespace And Secret

Apply namespace first:

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

Verify:

```bash
kubectl -n devops-launchboard get secret launchboard-secret
```

Why this step exists:

The Secret must exist before PostgreSQL, the migration Job, and backend Pods start.

## Step 20: Apply Kubernetes Manifests

Run:

```bash
cd /opt/devops-launchboard/app-source
kubectl apply -k deployment/phase-6-kubernetes-local/k8s
```

Why this step exists:

This applies the ConfigMap, PVC, Deployments, Services, Job, Ingress, and HPA.

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
PostgreSQL Pod Running
Migration Job Completed
Backend Pods Running
Frontend Pods Running
Ingress exists
PVC bound
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

Rollback:

```bash
kubectl -n devops-launchboard rollout undo deployment/launchboard-backend
kubectl -n devops-launchboard rollout status deployment/launchboard-backend
```

Why this step exists:

Kubernetes Deployments keep rollout history and can roll back when a new version breaks.

Reference:

- Kubernetes deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/

## Logs And Debugging

Useful commands:

```bash
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard describe pod POD_NAME
kubectl -n devops-launchboard logs deployment/launchboard-backend
kubectl -n devops-launchboard logs deployment/launchboard-frontend
kubectl -n devops-launchboard logs deployment/launchboard-db
kubectl -n devops-launchboard get events --sort-by=.metadata.creationTimestamp
```

Port-forward fallback:

```bash
kubectl -n devops-launchboard port-forward service/launchboard-frontend 8080:80
```

Then open:

```text
http://127.0.0.1:8080
```

Why this section exists:

Kubernetes troubleshooting usually starts with Pods, events, rollout status, and logs.

## Troubleshooting

### Problem 1: Pod Shows ImagePullBackOff

Check:

```bash
kubectl -n devops-launchboard describe pod POD_NAME
```

Fix:

```bash
kind load docker-image launchboard-backend:phase-6 --name launchboard-local
kind load docker-image launchboard-frontend:phase-6 --name launchboard-local
```

### Problem 2: Backend Cannot Connect To Database

Check:

```bash
kubectl -n devops-launchboard logs deployment/launchboard-backend
kubectl -n devops-launchboard get secret launchboard-secret
kubectl -n devops-launchboard get service launchboard-db
```

Common causes:

```text
Secret was not created.
DATABASE_URL password does not match POSTGRES_PASSWORD.
PostgreSQL Pod is not ready.
```

### Problem 3: Ingress Does Not Work

Check:

```bash
kubectl get pods -n ingress-nginx
kubectl -n devops-launchboard get ingress
curl -I http://127.0.0.1
```

Common causes:

```text
Ingress Controller is not ready.
Kind cluster was created without port mappings.
AWS security group does not allow port 80.
```

### Problem 4: Migration Job Failed

Check:

```bash
kubectl -n devops-launchboard describe job launchboard-migrate
kubectl -n devops-launchboard logs job/launchboard-migrate
```

Lab fix after correcting the issue:

```bash
kubectl -n devops-launchboard delete job launchboard-migrate
kubectl apply -f deployment/phase-6-kubernetes-local/k8s/launchboard-migration-job.yaml
```

## Cleanup

Delete app resources:

```bash
kubectl delete namespace devops-launchboard
```

Delete Kind cluster:

```bash
kind delete cluster --name launchboard-local
```

Remove Docker images:

```bash
docker rmi launchboard-backend:phase-6 launchboard-backend:phase-6-v2 launchboard-frontend:phase-6 || true
```

AWS cleanup:

- Terminate the EC2 instance.
- Delete unused EBS volumes.
- Release unused Elastic IPs.
- Check AWS Billing.

## Security Notes

- Do not expose PostgreSQL publicly.
- Do not expose backend directly.
- Use Secrets for passwords.
- Do not commit real Secret YAML.
- Use Ingress as the public entry point.
- Use resource requests and limits.
- Use readiness and liveness probes.
- Use managed database storage for serious production.

## Production Checklist

```text
[ ] EC2 security group exposes only 22, 80, and optionally 443
[ ] Docker installed
[ ] kubectl installed
[ ] Kind installed
[ ] GitHub SSH key created and tested
[ ] Repository cloned with SSH
[ ] Root .dockerignore created
[ ] Kind config created
[ ] Backend Dockerfile created
[ ] Frontend Dockerfile created
[ ] Nginx config created
[ ] Kubernetes manifests created
[ ] CORS_ORIGINS updated
[ ] Kind cluster created
[ ] Ingress Controller installed
[ ] Images built
[ ] Images loaded into Kind
[ ] Namespace created
[ ] Secret created
[ ] Manifests applied
[ ] PostgreSQL rollout successful
[ ] Migration Job completed
[ ] Backend rollout successful
[ ] Frontend rollout successful
[ ] Ingress works
[ ] Public browser URL works
[ ] Rollout tested
[ ] Rollback tested
[ ] Cleanup plan understood
```

## Reference Documentation

| Topic | Link |
| --- | --- |
| Kubernetes docs | https://kubernetes.io/docs/ |
| kubectl install | https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/ |
| Kind quick start | https://kind.sigs.k8s.io/docs/user/quick-start/ |
| Kind ingress | https://kind.sigs.k8s.io/docs/user/ingress/ |
| Ingress Nginx | https://kubernetes.github.io/ingress-nginx/ |
| Deployments | https://kubernetes.io/docs/concepts/workloads/controllers/deployment/ |
| Services | https://kubernetes.io/docs/concepts/services-networking/service/ |
| ConfigMaps | https://kubernetes.io/docs/concepts/configuration/configmap/ |
| Secrets | https://kubernetes.io/docs/concepts/configuration/secret/ |
| Jobs | https://kubernetes.io/docs/concepts/workloads/controllers/job/ |
| Persistent Volumes | https://kubernetes.io/docs/concepts/storage/persistent-volumes/ |
| Ingress | https://kubernetes.io/docs/concepts/services-networking/ingress/ |
| HPA | https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/ |

## What To Do Next

Move to:

```text
Phase 7: CI/CD
```

Why:

Phase 6 teaches Kubernetes deployment manually. Phase 7 teaches how to automate checks, builds, and deployment steps through CI/CD.
