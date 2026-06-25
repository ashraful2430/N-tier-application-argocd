# Phase 11: Advanced Deployment Strategies

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

## Recommended AWS Setup

| Item | Recommended Value |
| --- | --- |
| AWS Region | `ap-southeast-1` or the closest region |
| Cluster Name | `devops-launchboard-phase-11` |
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
export AWS_REGION=ap-southeast-1
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
ssh-keygen -t ed25519 -C "devops-launchboard-phase-11" -f ~/.ssh/devops_launchboard_phase_11
cat ~/.ssh/devops_launchboard_phase_11.pub
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
  IdentityFile ~/.ssh/devops_launchboard_phase_11
  IdentitiesOnly yes
```

Secure and test:

```bash
chmod 600 ~/.ssh/config
chmod 600 ~/.ssh/devops_launchboard_phase_11
chmod 644 ~/.ssh/devops_launchboard_phase_11.pub
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

## Step 5: Create Phase 11 Folders

Run:

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-11-advanced-deployments/cluster
mkdir -p deployment/phase-11-advanced-deployments/ecr
mkdir -p deployment/phase-11-advanced-deployments/app-k8s
mkdir -p deployment/phase-11-advanced-deployments/blue-green
mkdir -p deployment/phase-11-advanced-deployments/canary
mkdir -p deployment/phase-11-advanced-deployments/feature-flags
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
vim deployment/phase-11-advanced-deployments/cluster/eksctl-cluster.yaml
```

Paste:

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: devops-launchboard-phase-11
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
      Environment: phase-11
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
eksctl create cluster -f deployment/phase-11-advanced-deployments/cluster/eksctl-cluster.yaml
kubectl get nodes
```

Why this file exists:

This file creates the Kubernetes platform for the phase. Private worker networking, OIDC, EBS CSI, and control plane logs are production-minded settings that support safer deployments and debugging.

## Step 7: Create ECR Repositories

Run:

```bash
aws ecr create-repository --repository-name launchboard-backend --region $AWS_REGION
aws ecr create-repository --repository-name launchboard-frontend --region $AWS_REGION
```

Create lifecycle policy:

```bash
vim deployment/phase-11-advanced-deployments/ecr/lifecycle-policy.json
```

Paste:

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep the latest 10 phase 11 images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["phase-11"],
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
aws ecr put-lifecycle-policy --repository-name launchboard-backend --lifecycle-policy-text file://deployment/phase-11-advanced-deployments/ecr/lifecycle-policy.json --region $AWS_REGION
aws ecr put-lifecycle-policy --repository-name launchboard-frontend --lifecycle-policy-text file://deployment/phase-11-advanced-deployments/ecr/lifecycle-policy.json --region $AWS_REGION
```

Why this step exists:

Advanced releases create multiple image tags. Lifecycle policy keeps the registry clean so old release images do not pile up forever.

## Step 8: Create Production Dockerfiles

Create:

```bash
vim deployment/phase-11-advanced-deployments/Dockerfile.backend
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

`groupadd`/`useradd` pin an explicit `--uid 10001 --gid 10001` so the numeric UID is deterministic and matches the Kubernetes `securityContext`, instead of relying on whatever UID the system auto-assigns to a name-only `USER app`.

Create:

```bash
vim deployment/phase-11-advanced-deployments/Dockerfile.frontend
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

COPY deployment/phase-11-advanced-deployments/nginx-frontend.conf /etc/nginx/conf.d/default.conf
COPY --from=builder --chown=101:101 /app/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

This uses the `nginxinc/nginx-unprivileged` image (UID 101), consistent with the other phases, instead of a plain `nginx:alpine` image with a manually created user.

Create:

```bash
vim deployment/phase-11-advanced-deployments/nginx-frontend.conf
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

Why these files exist:

The backend and frontend images are built the same way every time. Multi-stage builds keep runtime images smaller, non-root users reduce container risk, and health checks let Kubernetes verify each release.

## Step 9: Build And Push Images

Login:

```bash
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
```

Build images:

```bash
docker build -f deployment/phase-11-advanced-deployments/Dockerfile.backend -t launchboard-backend:phase-11 .
docker build -f deployment/phase-11-advanced-deployments/Dockerfile.frontend --build-arg VITE_API_URL=/api -t launchboard-frontend:phase-11 .
```

Create release tags:

```bash
docker tag launchboard-backend:phase-11 $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-11
docker tag launchboard-backend:phase-11 $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-11-blue
docker tag launchboard-backend:phase-11 $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-11-green
docker tag launchboard-backend:phase-11 $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-11-canary
docker tag launchboard-frontend:phase-11 $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-frontend:phase-11
```

Push:

```bash
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-11
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-11-blue
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-11-green
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-11-canary
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-frontend:phase-11
```

Why this step exists:

Blue-green and canary releases compare versions. For a lab, these tags may point to the same code. In real production, `green` or `canary` would usually be a newer build.

## Step 10: Deploy The Base Application

Create the app files in:

```text
deployment/phase-11-advanced-deployments/app-k8s
```

Use the files in this phase folder:

```text
namespace.yaml
storageclass.yaml
configmap.yaml
secret.example.yaml
pvc.yaml
launchboard-postgres-deployment.yaml
launchboard-postgres-service.yaml
launchboard-migration-job.yaml
launchboard-backend-deployment.yaml
launchboard-backend-service.yaml
launchboard-frontend-deployment.yaml
launchboard-frontend-service.yaml
ingress.yaml
hpa.yaml
kustomization.yaml
```

Prepare secret:

```bash
cd deployment/phase-11-advanced-deployments/app-k8s
cp secret.example.yaml secret.yaml
vim secret.yaml
```

Replace:

```text
CHANGE_ME_STRONG_PASSWORD
YOUR_ACCOUNT_ID
YOUR_AWS_REGION
YOUR_ALB_DNS_NAME
```

Apply:

```bash
cd /opt/devops-launchboard/app-source
kubectl apply -f deployment/phase-11-advanced-deployments/app-k8s/secret.yaml
kubectl apply -k deployment/phase-11-advanced-deployments/app-k8s
kubectl -n devops-launchboard get pods
```

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
  --cluster devops-launchboard-phase-11 \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --role-name devops-launchboard-phase-11-alb-controller \
  --attach-policy-arn arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess \
  --approve
```

Install:

```bash
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=devops-launchboard-phase-11 \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

Verify:

```bash
kubectl -n devops-launchboard get ingress
```

Why this step exists:

The Ingress file asks for public traffic routing. The AWS Load Balancer Controller creates the real ALB in AWS.

Reference:

- AWS Load Balancer Controller: https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/

## Step 12: Blue-Green Deployment

Blue-green means two versions run at the same time:

- `blue` is the current stable version.
- `green` is the new version.
- A service selector decides which version receives traffic.

Create:

```bash
vim deployment/phase-11-advanced-deployments/blue-green/active-backend-service.yaml
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
vim deployment/phase-11-advanced-deployments/blue-green/blue-deployment.yaml
vim deployment/phase-11-advanced-deployments/blue-green/green-deployment.yaml
vim deployment/phase-11-advanced-deployments/blue-green/kustomization.yaml
```

Use the matching full file contents from the `blue-green` folder in this phase.

Deploy blue-green:

```bash
kubectl -n devops-launchboard delete deployment launchboard-backend
kubectl apply -k deployment/phase-11-advanced-deployments/blue-green
kubectl -n devops-launchboard get pods -l app=launchboard-backend --show-labels
kubectl -n devops-launchboard describe service launchboard-backend
```

Switch traffic to green:

```bash
kubectl -n devops-launchboard patch service launchboard-backend -p '{"spec":{"selector":{"app":"launchboard-backend","track":"green"}}}'
kubectl -n devops-launchboard describe service launchboard-backend
```

Rollback to blue:

```bash
kubectl -n devops-launchboard patch service launchboard-backend -p '{"spec":{"selector":{"app":"launchboard-backend","track":"blue"}}}'
kubectl -n devops-launchboard describe service launchboard-backend
```

Why this works:

Kubernetes Services route traffic to pods that match their selector. Blue and green pods both exist, but only the selected `track` receives traffic. Rollback is fast because the old pods are still running.

Reference:

- Kubernetes Services: https://kubernetes.io/docs/concepts/services-networking/service/
- Kubernetes Deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/

## Step 13: Canary Deployment With Argo Rollouts

Install Argo Rollouts controller:

```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
kubectl -n argo-rollouts get pods
```

Install the Argo Rollouts kubectl plugin from the official guide:

```text
https://argo-rollouts.readthedocs.io/en/stable/installation/#kubectl-plugin-installation
```

Create:

```bash
vim deployment/phase-11-advanced-deployments/canary/argo-rollout.yaml
vim deployment/phase-11-advanced-deployments/canary/kustomization.yaml
```

Use the matching full file contents from the `canary` folder in this phase.

Before canary, clean up blue-green backend deployments:

```bash
kubectl -n devops-launchboard delete deployment launchboard-backend-blue launchboard-backend-green
kubectl -n devops-launchboard patch service launchboard-backend -p '{"spec":{"selector":{"app":"launchboard-backend"}}}'
```

Apply rollout:

```bash
kubectl apply -k deployment/phase-11-advanced-deployments/canary
kubectl -n devops-launchboard get rollout
kubectl -n devops-launchboard get pods -l app=launchboard-backend
```

Watch rollout:

```bash
kubectl -n devops-launchboard get rollout launchboard-backend -w
```

Promote manually after checking logs and health:

```bash
kubectl argo rollouts promote launchboard-backend -n devops-launchboard
```

Abort if the canary is bad:

```bash
kubectl argo rollouts abort launchboard-backend -n devops-launchboard
```

Why this works:

Argo Rollouts replaces the normal Deployment controller with a rollout controller. The canary steps send a small portion of pods to the new version first, pause, then continue only if the release looks healthy.

Reference:

- Argo Rollouts: https://argo-rollouts.readthedocs.io/

## Step 14: Feature Flags

Feature flags let teams enable or disable behavior without building a new image.

Create:

```bash
vim deployment/phase-11-advanced-deployments/feature-flags/configmap-flags.yaml
vim deployment/phase-11-advanced-deployments/feature-flags/kustomization.yaml
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
  RELEASE_BANNER: "Phase 11 controlled release"
```

Paste into `kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - configmap-flags.yaml
```

Apply:

```bash
kubectl apply -k deployment/phase-11-advanced-deployments/feature-flags
```

Attach flags to the normal backend deployment:

```bash
kubectl -n devops-launchboard set env deployment/launchboard-backend --from=configmap/launchboard-feature-flags
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
```

Attach flags to the Argo Rollout backend:

```bash
kubectl -n devops-launchboard edit rollout launchboard-backend
```

Why this works:

The ConfigMap stores non-secret runtime settings. `kubectl set env` copies those settings into a normal Deployment. For an Argo Rollout, students edit the rollout pod template and add the same ConfigMap under `envFrom`. Real applications must read those variables in code before the flag changes behavior.

Reference:

- Kubernetes ConfigMap: https://kubernetes.io/docs/concepts/configuration/configmap/

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
kubectl delete -k deployment/phase-11-advanced-deployments/feature-flags
kubectl delete -k deployment/phase-11-advanced-deployments/canary
kubectl delete -k deployment/phase-11-advanced-deployments/blue-green
```

Delete app:

```bash
kubectl delete -f deployment/phase-11-advanced-deployments/app-k8s/secret.yaml
kubectl delete -k deployment/phase-11-advanced-deployments/app-k8s
```

Delete Argo Rollouts:

```bash
kubectl delete namespace argo-rollouts
```

Delete cluster:

```bash
eksctl delete cluster -f deployment/phase-11-advanced-deployments/cluster/eksctl-cluster.yaml
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

Move to Phase 12 to learn disaster recovery, backup, restore, and incident response.
