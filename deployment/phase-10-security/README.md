# Phase 10: Security Hardening

## Fresh Start Assumption

This phase starts from a clean machine and a clean AWS setup.

You do not need to finish any previous phase before using this phase.

This guide assumes:

- You have an AWS account.
- You have GitHub access to this repository.
- You will clone the repository with SSH.
- You will create a new EKS cluster for this phase.
- You will build and push fresh Docker images for this phase.
- You will deploy the frontend, backend, and PostgreSQL database to Kubernetes.
- You will then add security controls on top of the running application.
- You will type commands manually.
- You will use `vim` to create files.
- You will not use custom shell scripts for deployment automation.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What This Phase Deploys

This phase deploys the N-tier application on Amazon EKS and then hardens it.

The deployment includes:

- Vite frontend served by Nginx
- FastAPI backend
- PostgreSQL database running inside Kubernetes for the lab
- Amazon ECR repositories
- Amazon EKS cluster
- AWS Load Balancer Controller
- Kubernetes RBAC
- Kubernetes NetworkPolicy
- Kubernetes Pod Security Admission labels
- ResourceQuota and LimitRange
- Trivy image scanning
- Semgrep SAST scanning
- SonarQube learning deployment
- AWS Secrets Manager example
- External Secrets Operator example
- Sealed Secrets example
- Vault policy example

## When To Use This Architecture

Use this architecture when:

- You already know how to deploy the app on Kubernetes.
- You want to learn security controls that real platform teams add after the app is running.
- You need least-privilege Kubernetes access.
- You need network isolation between frontend, backend, and database pods.
- You need image vulnerability scanning before deployment.
- You need SAST scanning before merging code.
- You want to learn safer secret handling options.

Do not start here if:

- You only want a small local demo.
- You are not ready for AWS costs.
- You do not want to manage Kubernetes security settings.
- You want the fastest beginner deployment path.

For a simple first deployment, use bare metal EC2 or Docker Compose. Use this phase when students are ready to understand how production teams reduce risk after moving to Kubernetes.

## Recommended AWS Setup

| Item | Recommended Value |
| --- | --- |
| AWS Region | `ap-southeast-1` or the closest region |
| Cluster Name | `devops-launchboard-phase-10` |
| Kubernetes Version | `1.34` |
| Node Type | `t3.medium` |
| Desired Nodes | `2` |
| Minimum Nodes | `2` |
| Maximum Nodes | `4` |
| Node Storage | `30 GB gp3` |
| ECR Backend Repo | `launchboard-backend` |
| ECR Frontend Repo | `launchboard-frontend` |
| Public Access | Through AWS Application Load Balancer |
| Database | PostgreSQL inside Kubernetes for student lab |

Cost warning:

- EKS has a cluster hourly cost.
- EC2 worker nodes cost money.
- EBS volumes cost money.
- Load balancers cost money.
- ECR storage may cost money.
- CloudWatch logs may cost money.
- Delete everything after practice.

Reference:

- AWS EKS pricing: https://aws.amazon.com/eks/pricing/
- AWS Budgets: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html

## Architecture

```text
Browser
  |
  | HTTPS or HTTP
  v
AWS Application Load Balancer
  |
  v
Frontend pod running Nginx on port 8080
  |
  | /api traffic
  v
Backend pod running FastAPI on port 8000
  |
  v
PostgreSQL pod on port 5432

Security controls:

RBAC limits what deployment identities can do.
NetworkPolicy limits which pods can talk to each other.
Pod Security Admission rejects unsafe pod settings.
ResourceQuota prevents one app from using too much namespace capacity.
Trivy scans container images.
Semgrep scans source code.
Secrets Manager, External Secrets, Sealed Secrets, and Vault show safer secret patterns.
```

## Step 1: Install Local Tools

Run from: your local machine

Why this step exists: this phase uses AWS, Docker, Kubernetes, Helm, Git, and SSH. These tools let your laptop create cloud resources, build images, push images, and deploy Kubernetes files.

Check tools:

```bash
git --version
ssh -V
docker --version
aws --version
kubectl version --client
eksctl version
helm version
```

If a tool is missing, install it from the official documentation:

- Git: https://git-scm.com/downloads
- Docker: https://docs.docker.com/get-docker/
- AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- kubectl: https://kubernetes.io/docs/tasks/tools/
- eksctl: https://eksctl.io/installation/
- Helm: https://helm.sh/docs/intro/install/

Simple explanation:

- `git` downloads the project.
- `ssh` authenticates to GitHub.
- `docker` builds container images.
- `aws` talks to your AWS account.
- `kubectl` talks to Kubernetes.
- `eksctl` creates EKS clusters.
- `helm` installs Kubernetes add-ons.

## Step 2: Configure AWS Credentials

Run from: your local machine

```bash
aws configure
```

Enter:

```text
AWS Access Key ID
AWS Secret Access Key
Default region name: ap-southeast-1
Default output format: json
```

Verify:

```bash
aws sts get-caller-identity
```

Expected output:

```json
{
  "Account": "123456789012"
}
```

Replace placeholders:

```text
YOUR_AWS_REGION
YOUR_ACCOUNT_ID
```

Create the IAM policy:

```bash
aws iam create-policy \
  --policy-name devops-launchboard-phase-10-secrets-read \
  --policy-document file://deployment/phase-10-security/secrets-management/aws-secrets-manager-policy.json
```

Why this step exists:

AWS CLI needs credentials before it can create EKS clusters, ECR repositories, IAM roles, and secrets. Without this step, every AWS command fails because AWS does not know who is making the request.

Reference:

- AWS CLI configure: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html

## Step 3: Create SSH Key For GitHub

Run from: your local machine

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-10" -f ~/.ssh/devops_launchboard_phase_10
```

Press Enter twice when it asks for a passphrase for this student lab.

Print the public key:

```bash
cat ~/.ssh/devops_launchboard_phase_10.pub
```

Add that public key to GitHub:

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
  IdentityFile ~/.ssh/devops_launchboard_phase_10
  IdentitiesOnly yes
```

Save and secure the files:

```bash
chmod 600 ~/.ssh/config
chmod 600 ~/.ssh/devops_launchboard_phase_10
chmod 644 ~/.ssh/devops_launchboard_phase_10.pub
ssh -T git@github.com
```

Why this step exists:

The project uses an SSH clone URL. GitHub allows the clone only when your machine owns a private key that matches a public key saved in GitHub. The SSH config tells your machine which private key to use for `github.com`.

Reference:

- GitHub SSH docs: https://docs.github.com/en/authentication/connecting-to-github-with-ssh

## Step 4: Clone The Repository

Run from: your local machine

```bash
sudo mkdir -p /opt/devops-launchboard
sudo chown -R $USER:$USER /opt/devops-launchboard
cd /opt/devops-launchboard
git clone git@github.com:ashraful2430/N-tier-application.git app-source
cd app-source
git branch --show-current
```

Expected output:

```text
main
```

Why this step exists:

The deployment files and application source code must be on your machine before you can build Docker images or create Kubernetes manifests. The `/opt/devops-launchboard` folder gives the project a stable home.

## Step 5: Create Phase 10 Folders

Run from: `/opt/devops-launchboard/app-source`

```bash
mkdir -p deployment/phase-10-security/cluster
mkdir -p deployment/phase-10-security/ecr
mkdir -p deployment/phase-10-security/app-k8s
mkdir -p deployment/phase-10-security/k8s-security
mkdir -p deployment/phase-10-security/secrets-management
mkdir -p deployment/phase-10-security/sast
mkdir -p deployment/phase-10-security/vault
```

Why these folders exist:

- `cluster` stores the EKS cluster definition.
- `ecr` stores the ECR lifecycle policy.
- `app-k8s` stores the normal application Kubernetes manifests.
- `k8s-security` stores Kubernetes hardening controls.
- `secrets-management` stores examples for safer secret delivery.
- `sast` stores source scanning configuration.
- `vault` stores Vault learning files.

## Step 6: Create The EKS Cluster File

Run:

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

Replace:

```text
YOUR_AWS_REGION
```

Example for Singapore:

```text
ap-southeast-1
ap-southeast-1a
ap-southeast-1b
```

Create the cluster:

```bash
eksctl create cluster -f deployment/phase-10-security/cluster/eksctl-cluster.yaml
kubectl get nodes
```

What this file means:

- `metadata.name` names the EKS cluster.
- `metadata.region` chooses where AWS creates the cluster.
- `version` pins the Kubernetes version so students know what they are using.
- `withOIDC` enables IAM Roles for Service Accounts, which is important for secure AWS access from pods.
- `privateNetworking` places worker nodes in private subnets.
- `nat.gateway: Single` lets private nodes reach the internet for image pulls while keeping the lab cost lower than one NAT Gateway per AZ.
- `cloudWatch.clusterLogging` enables control plane logs so security events are easier to investigate.
- `aws-ebs-csi-driver` lets Kubernetes create EBS volumes for PostgreSQL storage.

Reference:

- eksctl cluster config: https://eksctl.io/usage/schema/
- EKS cluster logging: https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html

## Step 7: Create ECR Repositories

Run:

```bash
export AWS_REGION=ap-southeast-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws ecr create-repository --repository-name launchboard-backend --region $AWS_REGION
aws ecr create-repository --repository-name launchboard-frontend --region $AWS_REGION
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

Apply lifecycle policy:

```bash
aws ecr put-lifecycle-policy \
  --repository-name launchboard-backend \
  --lifecycle-policy-text file://deployment/phase-10-security/ecr/lifecycle-policy.json \
  --region $AWS_REGION

aws ecr put-lifecycle-policy \
  --repository-name launchboard-frontend \
  --lifecycle-policy-text file://deployment/phase-10-security/ecr/lifecycle-policy.json \
  --region $AWS_REGION
```

Why this step exists:

ECR stores Docker images. Lifecycle policies stop old images from piling up forever. This matters because old images cost money and make security cleanup harder.

Reference:

- Amazon ECR lifecycle policies: https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html

## Step 8: Create Production Dockerfiles

Create backend Dockerfile:

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

Create frontend Dockerfile:

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

FROM nginx:1.27-alpine AS runtime

RUN addgroup -S app \
    && adduser -S app -G app \
    && mkdir -p /var/cache/nginx/client_temp /var/cache/nginx/proxy_temp /var/cache/nginx/fastcgi_temp /var/cache/nginx/uwsgi_temp /var/cache/nginx/scgi_temp /var/run /tmp/nginx \
    && chown -R app:app /usr/share/nginx/html /var/cache/nginx /var/run /tmp/nginx

COPY deployment/phase-10-security/nginx-frontend.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html

USER app

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

Create frontend Nginx config:

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

Why these files are production-grade:

- Multi-stage builds keep runtime images smaller.
- `npm ci` uses the lock file for repeatable frontend installs.
- The backend runs as a non-root Linux user.
- The frontend Nginx container also runs as a non-root user.
- Health checks let Docker and Kubernetes know when the app is unhealthy.
- Nginx proxies `/api` traffic to the backend service instead of exposing the backend directly.

Reference:

- Docker multi-stage builds: https://docs.docker.com/build/building/multi-stage/
- Dockerfile reference: https://docs.docker.com/reference/dockerfile/
- Nginx reverse proxy docs: https://nginx.org/en/docs/http/ngx_http_proxy_module.html

## Step 9: Build, Scan, And Push Images

Login to ECR:

```bash
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
```

Build backend:

```bash
docker build \
  -f deployment/phase-10-security/Dockerfile.backend \
  -t launchboard-backend:phase-10 \
  .
```

Build frontend:

```bash
docker build \
  -f deployment/phase-10-security/Dockerfile.frontend \
  --build-arg VITE_API_URL=/api \
  -t launchboard-frontend:phase-10 \
  .
```

Scan backend image:

```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  --exit-code 1 \
  launchboard-backend:phase-10
```

Scan frontend image:

```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  --exit-code 1 \
  launchboard-frontend:phase-10
```

Tag images:

```bash
docker tag launchboard-backend:phase-10 $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-10
docker tag launchboard-frontend:phase-10 $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-frontend:phase-10
```

Push images:

```bash
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-10
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-frontend:phase-10
```

Why this step exists:

Kubernetes pulls images from a registry. ECR is the private registry for this phase. Trivy scanning happens before pushing so students can stop risky images before they reach the cluster.

Reference:

- Trivy docs: https://aquasecurity.github.io/trivy/
- Amazon ECR push image: https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html

## Step 10: Create Application Kubernetes Files

Create the application files in:

```text
deployment/phase-10-security/app-k8s
```

Use `vim` for each file.

Important replacement:

```text
YOUR_ACCOUNT_ID
YOUR_AWS_REGION
YOUR_ALB_DNS_NAME
CHANGE_ME_STRONG_PASSWORD
```

The full manifests are stored in this phase folder so students can copy them file by file:

```text
app-k8s/namespace.yaml
app-k8s/storageclass.yaml
app-k8s/configmap.yaml
app-k8s/secret.example.yaml
app-k8s/pvc.yaml
app-k8s/launchboard-postgres-deployment.yaml
app-k8s/launchboard-postgres-service.yaml
app-k8s/launchboard-migration-job.yaml
app-k8s/launchboard-backend-deployment.yaml
app-k8s/launchboard-backend-service.yaml
app-k8s/launchboard-frontend-deployment.yaml
app-k8s/launchboard-frontend-service.yaml
app-k8s/ingress.yaml
app-k8s/hpa.yaml
app-k8s/kustomization.yaml
```

Why these files exist:

- `namespace.yaml` gives the app its own Kubernetes area.
- `storageclass.yaml` tells Kubernetes to create gp3 EBS volumes.
- `configmap.yaml` stores non-secret app settings.
- `secret.example.yaml` shows secret keys without committing real secrets.
- `pvc.yaml` requests persistent storage for PostgreSQL.
- PostgreSQL deployment and service run the lab database.
- The migration job runs Alembic migrations before the backend serves traffic.
- Backend deployment and service run the FastAPI API.
- Frontend deployment and service run the Nginx frontend.
- Ingress creates the public ALB entry point.
- HPA scales backend pods based on CPU.
- Kustomization lets `kubectl apply -k` apply the folder as one unit.

Copy secret example to the real secret file:

```bash
cd deployment/phase-10-security/app-k8s
cp secret.example.yaml secret.yaml
vim secret.yaml
```

Change:

```text
CHANGE_ME_STRONG_PASSWORD
```

Edit image placeholders:

```bash
vim launchboard-backend-deployment.yaml
vim launchboard-frontend-deployment.yaml
vim launchboard-migration-job.yaml
```

Replace:

```text
YOUR_ACCOUNT_ID
YOUR_AWS_REGION
```

Apply app:

```bash
cd /opt/devops-launchboard/app-source
kubectl apply -f deployment/phase-10-security/app-k8s/secret.yaml
kubectl apply -k deployment/phase-10-security/app-k8s
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard get svc
kubectl -n devops-launchboard get ingress
```

## Step 11: Install AWS Load Balancer Controller

Run:

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update
```

Create IAM role:

```bash
eksctl create iamserviceaccount \
  --cluster devops-launchboard-phase-10 \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --role-name devops-launchboard-phase-10-alb-controller \
  --attach-policy-arn arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess \
  --approve
```

Install controller:

```bash
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=devops-launchboard-phase-10 \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

Why this step exists:

Kubernetes Ingress is only a request for external traffic routing. On EKS, the AWS Load Balancer Controller watches Ingress objects and creates a real AWS Application Load Balancer.

Reference:

- AWS Load Balancer Controller: https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/

## Step 12: Add Pod Security Admission Labels

Create:

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
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

Apply:

```bash
kubectl apply -f deployment/phase-10-security/k8s-security/pod-security-standards.yaml
```

Why this file exists:

Pod Security Admission is a built-in Kubernetes security control. The `restricted` level blocks common risky pod behavior, such as privileged containers and missing seccomp settings. This protects the cluster even if someone accidentally writes an unsafe deployment later.

Reference:

- Kubernetes Pod Security Standards: https://kubernetes.io/docs/concepts/security/pod-security-standards/

## Step 13: Add RBAC

Create:

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
  - apiGroups:
      - ""
    resources:
      - configmaps
      - pods
      - services
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
  - apiGroups:
      - ""
    resources:
      - secrets
    verbs:
      - get
      - list
      - create
      - update
      - patch
  - apiGroups:
      - apps
    resources:
      - deployments
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
  - apiGroups:
      - batch
    resources:
      - jobs
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
      - delete
  - apiGroups:
      - networking.k8s.io
    resources:
      - ingresses
      - networkpolicies
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
  - apiGroups:
      - autoscaling
    resources:
      - horizontalpodautoscalers
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
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
kubectl -n devops-launchboard get serviceaccount,role,rolebinding
```

Why this file exists:

RBAC means Role-Based Access Control. It decides what an identity can do inside Kubernetes. This phase creates a deployer service account with app-deployment permissions inside only the `devops-launchboard` namespace. That is safer than giving cluster-admin access.

Reference:

- Kubernetes RBAC: https://kubernetes.io/docs/reference/access-authn-authz/rbac/

## Step 14: Add ResourceQuota And LimitRange

Create:

```bash
vim deployment/phase-10-security/k8s-security/resource-quota.yaml
vim deployment/phase-10-security/k8s-security/limit-range.yaml
```

Paste into `resource-quota.yaml`:

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

Paste into `limit-range.yaml`:

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

Apply:

```bash
kubectl apply -f deployment/phase-10-security/k8s-security/resource-quota.yaml
kubectl apply -f deployment/phase-10-security/k8s-security/limit-range.yaml
kubectl -n devops-launchboard describe resourcequota launchboard-quota
kubectl -n devops-launchboard describe limitrange launchboard-default-limits
```

Why these files exist:

`ResourceQuota` limits total namespace usage. It prevents one lab app from consuming too many pods, secrets, PVCs, CPU, or memory.

`LimitRange` gives containers default CPU and memory settings. It helps avoid pods with no limits, which is dangerous because one container can consume too many node resources.

Reference:

- Kubernetes ResourceQuota: https://kubernetes.io/docs/concepts/policy/resource-quotas/
- Kubernetes LimitRange: https://kubernetes.io/docs/concepts/policy/limit-range/

## Step 15: Add NetworkPolicy

Create:

```bash
vim deployment/phase-10-security/k8s-security/network-policy.yaml
```

Paste:

```yaml
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

Why this file exists:

Without NetworkPolicy, pods in the same cluster can often talk to each other freely. That is too open for production. These policies create a default deny rule, then allow only the traffic this app needs:

- Public traffic can reach the frontend on port `8080`.
- Frontend can reach backend on port `8000`.
- Backend and migration job can reach PostgreSQL on port `5432`.
- The migration job can send outbound traffic to PostgreSQL before the backend serves users.
- Pods can still reach DNS on port `53`.

Reference:

- Kubernetes NetworkPolicy: https://kubernetes.io/docs/concepts/services-networking/network-policies/

## Step 16: Run Semgrep SAST

Create:

```bash
vim deployment/phase-10-security/sast/semgrep-config.yaml
```

Paste:

```yaml
rules:
  - id: launchboard-hardcoded-secret
    message: Hardcoded secret-like value detected. Move the value to a secret manager or environment variable.
    severity: ERROR
    languages:
      - python
      - javascript
      - typescript
    pattern-regex: (?i)(password|secret|token|api_key)\s*=\s*["'][^"']{8,}["']
  - id: launchboard-python-subprocess-shell-true
    message: subprocess with shell=True can execute unexpected shell input.
    severity: WARNING
    languages:
      - python
    patterns:
      - pattern: subprocess.$FUNC(..., shell=True, ...)
```

Run scan:

```bash
docker run --rm \
  -v "$PWD:/src" \
  returntocorp/semgrep:latest \
  semgrep scan --config /src/deployment/phase-10-security/sast/semgrep-config.yaml /src
```

Why this step exists:

SAST means Static Application Security Testing. It scans source code before the app runs. This catches risky patterns like hardcoded secrets or unsafe shell execution early, before they become production incidents.

Reference:

- Semgrep docs: https://semgrep.dev/docs/

## Step 17: Optional SonarQube Learning Deployment

Create:

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

Apply:

```bash
kubectl apply -f deployment/phase-10-security/sast/sonarqube.yaml
kubectl -n security get pods,svc
kubectl -n security port-forward svc/sonarqube 9000:9000
```

Open:

```text
http://127.0.0.1:9000
```

Why this step exists:

SonarQube gives a dashboard for code quality and security findings. In real production, teams usually run it as a separate platform service instead of inside the app namespace. This lab keeps it isolated in the `security` namespace.

Reference:

- SonarQube docs: https://docs.sonarsource.com/sonarqube-server/

## Step 18: AWS Secrets Manager Example

Create the secret:

```bash
aws secretsmanager create-secret \
  --name devops-launchboard/phase-10/database \
  --secret-string '{"POSTGRES_PASSWORD":"CHANGE_ME_STRONG_PASSWORD","DATABASE_URL":"postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@launchboard-db:5432/launchboard"}' \
  --region $AWS_REGION
```

Create IAM policy file:

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

Why this step exists:

Kubernetes Secrets are convenient, but production teams often store real secrets in a cloud secret manager. AWS Secrets Manager gives versioning, IAM access control, audit trails, and rotation options.

Reference:

- AWS Secrets Manager: https://docs.aws.amazon.com/secretsmanager/

## Step 19: Optional External Secrets Operator

Install External Secrets Operator:

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true
```

Create service account for AWS secret reads:

```bash
eksctl create iamserviceaccount \
  --cluster devops-launchboard-phase-10 \
  --namespace devops-launchboard \
  --name launchboard-secrets-reader \
  --role-name devops-launchboard-phase-10-secrets-reader \
  --attach-policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/devops-launchboard-phase-10-secrets-read \
  --approve
```

Create:

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

Apply after replacing placeholders:

```bash
kubectl apply -f deployment/phase-10-security/secrets-management/external-secret.example.yaml
kubectl -n devops-launchboard get externalsecret,secret
```

Why this step exists:

External Secrets Operator reads from AWS Secrets Manager and creates a normal Kubernetes Secret for the app. This keeps raw secret values out of Git and out of manual YAML files.

Reference:

- External Secrets Operator: https://external-secrets.io/latest/

## Step 20: Optional Sealed Secrets

Create:

```bash
vim deployment/phase-10-security/secrets-management/sealed-secret.example.yaml
```

Paste:

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: launchboard-secret
  namespace: devops-launchboard
spec:
  encryptedData:
    POSTGRES_PASSWORD: REPLACE_WITH_KUBESEAL_OUTPUT
    DATABASE_URL: REPLACE_WITH_KUBESEAL_OUTPUT
  template:
    metadata:
      name: launchboard-secret
      namespace: devops-launchboard
    type: Opaque
```

Install controller:

```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system
```

Create a normal secret locally:

```bash
kubectl -n devops-launchboard create secret generic launchboard-secret \
  --from-literal=POSTGRES_PASSWORD='CHANGE_ME_STRONG_PASSWORD' \
  --from-literal=DATABASE_URL='postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@launchboard-db:5432/launchboard' \
  --dry-run=client \
  -o yaml > launchboard-secret.yaml
```

Seal it:

```bash
kubeseal --format yaml < launchboard-secret.yaml > deployment/phase-10-security/secrets-management/sealed-secret.yaml
```

Apply:

```bash
kubectl apply -f deployment/phase-10-security/secrets-management/sealed-secret.yaml
```

Why this step exists:

Sealed Secrets lets students commit encrypted secrets safely. The controller inside the cluster decrypts them. This is useful when a team wants GitOps but does not want plaintext Kubernetes Secrets in Git.

Reference:

- Sealed Secrets: https://github.com/bitnami-labs/sealed-secrets

## Step 21: Optional Vault Policy

Create:

```bash
vim deployment/phase-10-security/vault/vault-values.yaml
vim deployment/phase-10-security/vault/launchboard-policy.hcl
```

Paste into `vault-values.yaml`:

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
  auditStorage:
    enabled: true
    size: 5Gi
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

Paste into `launchboard-policy.hcl`:

```hcl
path "secret/data/devops-launchboard/phase-10/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/devops-launchboard/phase-10/*" {
  capabilities = ["read", "list"]
}
```

Install Vault:

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm upgrade --install vault hashicorp/vault \
  --namespace vault \
  --create-namespace \
  -f deployment/phase-10-security/vault/vault-values.yaml
```

Why this step exists:

Vault is a dedicated secrets platform. It is more advanced than the simple lab secret file. This phase shows the shape of a Vault policy so students understand that apps should receive narrowly scoped read access, not broad admin access.

Reference:

- HashiCorp Vault Kubernetes: https://developer.hashicorp.com/vault/docs/platform/k8s

## Step 22: Verify Security Controls

Check app:

```bash
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard get svc
kubectl -n devops-launchboard get ingress
```

Check pod security labels:

```bash
kubectl get namespace devops-launchboard --show-labels
```

Check RBAC:

```bash
kubectl -n devops-launchboard get serviceaccount,role,rolebinding
```

Check quota:

```bash
kubectl -n devops-launchboard describe resourcequota launchboard-quota
```

Check network policy:

```bash
kubectl -n devops-launchboard get networkpolicy
```

Check backend logs:

```bash
kubectl -n devops-launchboard logs deploy/launchboard-backend
```

Check frontend:

```bash
kubectl -n devops-launchboard get ingress launchboard-ingress
```

Open the ALB address in a browser after it becomes ready.

## Troubleshooting

Problem: pods fail after Pod Security labels.

Cause:

```text
The pod securityContext or container securityContext is missing required restricted settings.
```

Fix:

```bash
kubectl -n devops-launchboard describe pod POD_NAME
kubectl -n devops-launchboard get events --sort-by=.lastTimestamp
```

Problem: frontend works but API fails.

Cause:

```text
NetworkPolicy may be blocking frontend-to-backend traffic, or Nginx may point to the wrong backend service.
```

Fix:

```bash
kubectl -n devops-launchboard get networkpolicy
kubectl -n devops-launchboard get svc launchboard-backend
kubectl -n devops-launchboard logs deploy/launchboard-frontend
```

Problem: image pull fails.

Cause:

```text
The image placeholder was not replaced, the image was not pushed, or EKS cannot access ECR.
```

Fix:

```bash
kubectl -n devops-launchboard describe pod POD_NAME
aws ecr describe-images --repository-name launchboard-backend --region $AWS_REGION
aws ecr describe-images --repository-name launchboard-frontend --region $AWS_REGION
```

Problem: External Secret does not create a Kubernetes Secret.

Cause:

```text
IAM role, SecretStore, region, or AWS secret key is wrong.
```

Fix:

```bash
kubectl -n devops-launchboard describe externalsecret launchboard-secret
kubectl -n external-secrets logs deploy/external-secrets
```

## Cleanup

Delete optional tools:

```bash
helm uninstall vault -n vault
helm uninstall sealed-secrets -n kube-system
helm uninstall external-secrets -n external-secrets
kubectl delete namespace vault
kubectl delete namespace external-secrets
kubectl delete namespace security
```

Delete app:

```bash
kubectl delete -k deployment/phase-10-security/k8s-security
kubectl delete -k deployment/phase-10-security/app-k8s
```

Delete cluster:

```bash
eksctl delete cluster -f deployment/phase-10-security/cluster/eksctl-cluster.yaml
```

Delete ECR images and repositories if you are done:

```bash
aws ecr delete-repository --repository-name launchboard-backend --force --region $AWS_REGION
aws ecr delete-repository --repository-name launchboard-frontend --force --region $AWS_REGION
```

Delete secret:

```bash
aws secretsmanager delete-secret \
  --secret-id devops-launchboard/phase-10/database \
  --force-delete-without-recovery \
  --region $AWS_REGION
```

Why cleanup matters:

EKS clusters, EC2 nodes, EBS volumes, load balancers, CloudWatch logs, and stored images can continue charging after practice. Cleanup is part of production discipline.

## Production Checklist

```text
[ ] AWS credentials configured
[ ] GitHub SSH clone works
[ ] EKS cluster created
[ ] ECR repositories created
[ ] Docker images built
[ ] Docker images scanned with Trivy
[ ] Docker images pushed to ECR
[ ] Kubernetes manifests updated with real account and region
[ ] Application deployed
[ ] ALB created
[ ] Pod Security restricted labels applied
[ ] RBAC created
[ ] ResourceQuota created
[ ] LimitRange created
[ ] NetworkPolicy created
[ ] Semgrep scan completed
[ ] Secrets are not committed in plaintext
[ ] Optional external secret flow tested
[ ] Logs checked
[ ] Cleanup plan understood
```

## Reference Documentation

| Topic | Official Link |
| --- | --- |
| EKS | https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html |
| eksctl | https://eksctl.io/ |
| ECR | https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html |
| Kubernetes RBAC | https://kubernetes.io/docs/reference/access-authn-authz/rbac/ |
| NetworkPolicy | https://kubernetes.io/docs/concepts/services-networking/network-policies/ |
| Pod Security Standards | https://kubernetes.io/docs/concepts/security/pod-security-standards/ |
| ResourceQuota | https://kubernetes.io/docs/concepts/policy/resource-quotas/ |
| LimitRange | https://kubernetes.io/docs/concepts/policy/limit-range/ |
| Trivy | https://aquasecurity.github.io/trivy/ |
| Semgrep | https://semgrep.dev/docs/ |
| AWS Secrets Manager | https://docs.aws.amazon.com/secretsmanager/ |
| External Secrets Operator | https://external-secrets.io/latest/ |
| Sealed Secrets | https://github.com/bitnami-labs/sealed-secrets |
| Vault on Kubernetes | https://developer.hashicorp.com/vault/docs/platform/k8s |

## Next Step

Move to Phase 11 for advanced deployment strategies such as blue-green, canary, rollout verification, and safer release controls.
