# Phase 16: Production Capstone

## Fresh Start Assumption

This phase starts from a clean AWS environment and a clean Ubuntu workstation.

You do not need to complete any previous phase before using this guide — but this is the capstone: every design decision below was taught somewhere in phases 1-15, and this guide explains *what* and *why* at production depth without re-teaching each tool from zero.

This guide assumes:

- You have an AWS account with permissions to create EKS, EC2, IAM, ECR, ALB, EBS, S3, VPC, NAT Gateway, and CloudWatch resources.
- No tools are installed yet.
- You will create files with `vim` and type commands manually.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What You Will Deploy

Everything the journey taught, assembled into one deployment you could genuinely run for real users — minus only a domain name and TLS certificate (both cost money; the Extensions section at the end shows exactly where they would slot in).

```text
                               Browser
                                 |
                                 | HTTP :80
                                 v
                    AWS Application Load Balancer
                                 |
                                 v
                     Ingress (ALB controller, IRSA)
                                 |
                        Frontend Service
                                 |
                 Frontend Pods x2 (non-root Nginx)  <--- PDB: min 1 always up
                                 |
                        Backend Service                  NetworkPolicy:
                                 |                       only frontend -> backend
                 Backend Pods 2-5 (FastAPI, HPA)    <--- PDB: min 1 always up
                                 |
                                 |  :5432 (security group: cluster nodes only)
                                 v
                     Amazon RDS PostgreSQL 16
              (private subnets, encrypted, automated
                      daily backups, managed by AWS)

  ---------------- Operations layer ----------------

  Prometheus + Grafana + Alertmanager   (kube-prometheus-stack, metrics + dashboards)
  Metrics Server                        (feeds the HPA)
  Velero + S3 + EBS snapshots           (daily backups, tested restore)
  k6                                    (load validation before calling it done)
  Runbook                               (what to do when things break)
```

## What Makes This "Production Grade"

| Concern | What this phase does | Learned in |
| --- | --- | --- |
| Repeatable infrastructure | Declarative eksctl config, all manifests in Git | 8, 9 |
| Container hygiene | Multi-stage builds, non-root, pinned UIDs, image scanning | 3, 12 |
| Zero-downtime deploys | RollingUpdate, maxUnavailable 0, readiness gates | 6, 13 |
| Self-healing | Deployments, liveness probes, managed node groups | 6, 8 |
| Managed database | Amazon RDS PostgreSQL: automated backups, patching, storage growth | 9 |
| Autoscaling | HPA 2-5 on CPU, node group 2-4 | 8, 15 |
| Availability under maintenance | PodDisruptionBudgets | new here |
| Network segmentation | Default-deny NetworkPolicies per tier | 12 |
| Secrets | Kubernetes Secret created out-of-band, never in Git | 6-8, 11-15 |
| Observability | Prometheus, Grafana dashboards, Alertmanager | 11 |
| Backups + DR | Velero daily schedule to S3 + EBS snapshots, restore drill | 14 |
| Load validation | k6 load test with latency/error thresholds, HPA verified | 15 |
| Operations | Written runbook with incident situations | 14 |

Deliberately out of scope (each costs money or needs an org): custom domain + TLS (Route 53 + ACM — see Extensions for the exact steps), RDS Multi-AZ (one flag, roughly doubles the database cost; noted where it applies), CI/CD automation (Phase 7 shows the Jenkins and GitOps pipelines — this phase deploys manually so every step is visible one last time).

## Cost Warning

| Resource | Approximate Cost |
| --- | --- |
| EKS control plane | ~$0.10/hour |
| 2 × t3.medium workers | ~$0.08/hour |
| NAT Gateway | ~$0.045/hour |
| ALB | ~$0.02/hour |
| RDS db.t3.micro (single-AZ) | ~$0.017/hour |
| EBS volumes + snapshots, S3, ECR | ~$0.02/hour |

Roughly **$0.29/hour** (~$2.40 for an 8-hour session). Delete everything after each session (Cleanup section). Create an AWS Budget first: Console > Billing > Budgets.

## Files Included In This Phase

```text
deployment/phase-16-production-capstone/
+-- cluster/eksctl-cluster.yaml            (EKS + OIDC + EBS CSI + NetworkPolicy enforcement)
+-- ecr/lifecycle-policy.json              (image retention)
+-- Dockerfile.backend                     (FastAPI image)
+-- Dockerfile.frontend                    (React/Nginx image)
+-- nginx-frontend.conf                    (frontend Nginx config)
+-- app-k8s/
|   +-- namespace.yaml
|   +-- storageclass.yaml                  (gp3 encrypted, WaitForFirstConsumer)
|   +-- configmap.yaml
|   +-- secret.example.yaml                (template only - real Secret via kubectl)
|   +-- launchboard-migration-job.yaml
|   +-- launchboard-backend-deployment.yaml
|   +-- launchboard-backend-service.yaml
|   +-- launchboard-frontend-deployment.yaml
|   +-- launchboard-frontend-service.yaml
|   +-- ingress.yaml
|   +-- hpa.yaml
|   +-- pdb.yaml                           (NEW: PodDisruptionBudgets)
|   +-- networkpolicies.yaml               (NEW: default-deny + tier rules)
|   +-- kustomization.yaml
+-- monitoring/
|   +-- metrics-server-values.yaml
|   +-- kube-prometheus-stack-values.yaml
+-- backup/
|   +-- velero-iam-policy.json
|   +-- velero-daily-schedule.yaml
|   +-- velero-manual-backup.yaml
+-- tests/k6/load-test.js
+-- runbooks/production-runbook.md
+-- README.md
```

## Step 1: Create AWS Workstation

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-16-workstation` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` |
| Storage | 30 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | SSH port 22, your IP only |

```bash
chmod 400 devops-launchboard-key.pem
ssh -i devops-launchboard-key.pem ubuntu@YOUR_WORKSTATION_PUBLIC_IP
```

## Step 2: Install All Tools

Base tools and Docker:

```bash
cd ~
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl wget vim unzip jq ca-certificates gnupg lsb-release

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo ${UBUNTU_CODENAME:-$VERSION_CODENAME}) stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
sudo systemctl enable docker
sudo usermod -aG docker ubuntu
exit
```

SSH back in, then AWS CLI, kubectl, eksctl, Helm, and Velero CLI:

```bash
ssh -i devops-launchboard-key.pem ubuntu@YOUR_WORKSTATION_PUBLIC_IP
cd ~

# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install && rm -rf aws awscliv2.zip
aws configure
aws sts get-caller-identity

# kubectl
curl -LO "https://dl.k8s.io/release/stable.txt"
KUBECTL_VERSION=$(cat stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/kubectl && rm stable.txt

# eksctl
curl --silent --location "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" -o eksctl.tar.gz
tar -xzf eksctl.tar.gz && sudo mv eksctl /usr/local/bin/eksctl && rm eksctl.tar.gz

# Helm (official installer script - the apt repo method is unreliable)
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh && ./get_helm.sh && rm get_helm.sh

# Velero CLI (check https://github.com/vmware-tanzu/velero/releases for the current version)
VELERO_VERSION=v1.16.0
curl -fsSL -o velero.tar.gz "https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz"
tar -xzf velero.tar.gz
sudo mv "velero-${VELERO_VERSION}-linux-amd64/velero" /usr/local/bin/velero
rm -rf velero.tar.gz "velero-${VELERO_VERSION}-linux-amd64"
```

Verify everything:

```bash
docker --version && aws --version && kubectl version --client && eksctl version && helm version && velero version --client-only
```

Reference:

- AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
- eksctl: https://eksctl.io/installation/
- Helm: https://helm.sh/docs/intro/install/
- Velero: https://velero.io/docs/main/basic-install/

## Step 3: Clone Repository

```bash
cd ~
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-16" -f ~/.ssh/devops_launchboard_github_key
cat ~/.ssh/devops_launchboard_github_key.pub
```

Add as a read-only deploy key on GitHub, then:

```bash
vim ~/.ssh/config
```

```text
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/devops_launchboard_github_key
  IdentitiesOnly yes
```

```bash
chmod 600 ~/.ssh/config ~/.ssh/devops_launchboard_github_key
ssh -T git@github.com
sudo mkdir -p /opt/devops-launchboard
sudo chown -R ubuntu:ubuntu /opt/devops-launchboard
cd /opt/devops-launchboard
git clone git@github.com:ashraful2430/N-tier-application.git app-source
cd app-source
```

## Step 4: Create The EKS Cluster

```bash
vim deployment/phase-16-production-capstone/cluster/eksctl-cluster.yaml
```

Paste (replace `YOUR_AWS_REGION` in all three places):

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: devops-launchboard-phase-16
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
      Environment: phase-16
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
  - name: vpc-cni
    configurationValues: |-
      enableNetworkPolicy: "true"
```

The config is the proven Phase 8-13 setup (OIDC for IRSA, private workers behind a single NAT, control plane logs, EBS CSI with its IAM role) plus **one capstone addition**:

- The `vpc-cni` addon entry with `enableNetworkPolicy: "true"` turns on the VPC CNI's NetworkPolicy enforcement. Without it, the NetworkPolicy objects you apply in Step 7 would be accepted by the API server but **silently not enforced** — the most dangerous kind of security control. This flag deploys the network policy agent on every node so default-deny actually denies.

Create the cluster (20-40 minutes):

```bash
export AWS_REGION=YOUR_AWS_REGION
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export CLUSTER_NAME=devops-launchboard-phase-16

cd /opt/devops-launchboard/app-source
eksctl create cluster -f deployment/phase-16-production-capstone/cluster/eksctl-cluster.yaml
```

Verify:

```bash
kubectl get nodes
kubectl get pods -n kube-system | grep -E "ebs|aws-node"
```

Expected: 2 nodes Ready, EBS CSI pods Running, and the `aws-node` pods now include the network policy agent container.

Reference:

- eksctl ClusterConfig schema: https://eksctl.io/usage/schema/
- VPC CNI network policies: https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy.html

## Step 5: ECR, Images, And Lifecycle

### Dockerfiles and Nginx config

The images are the hardened builds used since Phase 8. Full line-by-line explanations live in the Phase 11 guide; the production-relevant properties: multi-stage (no compilers/Node in runtime images), non-root with pinned UIDs (10001 backend, 101 frontend), HEALTHCHECKs, `--proxy-headers` for correct client IPs behind the ALB.

```bash
vim deployment/phase-16-production-capstone/Dockerfile.backend
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

```bash
vim deployment/phase-16-production-capstone/Dockerfile.frontend
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

COPY deployment/phase-16-production-capstone/nginx-frontend.conf /etc/nginx/conf.d/default.conf
COPY --from=builder --chown=101:101 /app/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

```bash
vim deployment/phase-16-production-capstone/nginx-frontend.conf
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

Root `.dockerignore` (if not already present in your clone):

```bash
vim /opt/devops-launchboard/app-source/.dockerignore
```

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

### Lifecycle policy

```bash
vim deployment/phase-16-production-capstone/ecr/lifecycle-policy.json
```

Paste:

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep the latest 10 phase 16 images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["phase-16"],
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

### Create repositories, build, push

```bash
aws ecr create-repository --repository-name launchboard-backend --region "$AWS_REGION" --image-scanning-configuration scanOnPush=true
aws ecr create-repository --repository-name launchboard-frontend --region "$AWS_REGION" --image-scanning-configuration scanOnPush=true

aws ecr put-lifecycle-policy --repository-name launchboard-backend \
  --lifecycle-policy-text file://deployment/phase-16-production-capstone/ecr/lifecycle-policy.json --region "$AWS_REGION"
aws ecr put-lifecycle-policy --repository-name launchboard-frontend \
  --lifecycle-policy-text file://deployment/phase-16-production-capstone/ecr/lifecycle-policy.json --region "$AWS_REGION"

ECR_REGISTRY=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin $ECR_REGISTRY

cd /opt/devops-launchboard/app-source

docker build -f deployment/phase-16-production-capstone/Dockerfile.backend \
  -t $ECR_REGISTRY/launchboard-backend:phase-16 .

docker build -f deployment/phase-16-production-capstone/Dockerfile.frontend \
  --build-arg VITE_API_URL= \
  -t $ECR_REGISTRY/launchboard-frontend:phase-16 .

docker push $ECR_REGISTRY/launchboard-backend:phase-16
docker push $ECR_REGISTRY/launchboard-frontend:phase-16
```

`--image-scanning-configuration scanOnPush=true` is the production touch: every push is scanned for known CVEs. After pushing, check Console > ECR > repository > Images > scan findings.

Verify:

```bash
aws ecr describe-images --repository-name launchboard-backend --region "$AWS_REGION" \
  --query 'imageDetails[?imageTags!=null].imageTags' --output table
```

## Step 6: Install The AWS Load Balancer Controller

```bash
cd ~
curl -o aws-load-balancer-controller-policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicyPhase16 \
  --policy-document file://aws-load-balancer-controller-policy.json

eksctl create iamserviceaccount \
  --cluster "$CLUSTER_NAME" \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicyPhase16" \
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

This is the least-privilege IRSA install from Phases 8-13: the controller's official policy attached to an IAM role, bound to a ServiceAccount through the cluster's OIDC provider — no access keys anywhere in the cluster.

Reference:

- ALB controller install: https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/
- IRSA: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html

## Step 7: Create And Deploy The Application Manifests

All files go in `deployment/phase-16-production-capstone/app-k8s/`. These are the battle-tested manifests from phases 8 and 11-15 (deep line-by-line in the Phase 11 and Phase 15 guides) with two capstone additions explained in full (`pdb.yaml`, `networkpolicies.yaml`) and one capstone **upgrade**: the database is Amazon RDS, not a Pod.

### Create The Database First — Amazon RDS

Every Kubernetes phase so far ran PostgreSQL as a single Pod on an EBS volume. That was the right way to *learn* storage (PVCs, StorageClasses, the EBS CSI driver, even the `lost+found`/PGDATA failure mode), but it is not how production runs a primary database: one Pod is a single point of failure, you patch PostgreSQL yourself, and backup/restore is entirely on you. RDS moves all of that to AWS — automated daily backups with point-in-time recovery, managed minor-version patching, storage autoscaling, and an optional standby in a second AZ that is literally one flag.

The database must exist before the app deploys, and it must live in the cluster's VPC so Pods can reach it privately. Discover the cluster's network first:

```bash
VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
  --query 'cluster.resourcesVpcConfig.vpcId' --output text)
CLUSTER_SG=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
PRIVATE_SUBNETS=$(aws ec2 describe-subnets --region "$AWS_REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:kubernetes.io/role/internal-elb,Values=1" \
  --query 'Subnets[].SubnetId' --output text)
echo "VPC: $VPC_ID  ClusterSG: $CLUSTER_SG  Private subnets: $PRIVATE_SUBNETS"
```

Command explanation:

- `resourcesVpcConfig.vpcId` is the VPC eksctl created for the cluster — RDS must live in the same one for private connectivity.
- `clusterSecurityGroupId` is the security group **every worker node and Pod ENI carries**. Allowing database access "from this security group" therefore means "from anything running in the cluster" — the same SG-references-SG pattern as the Terraform and Ansible phases, and it survives node replacement and autoscaling.
- The `kubernetes.io/role/internal-elb` tag is how eksctl marks the **private** subnets; the database goes where nothing public can route.

Create the database security group and subnet group:

```bash
DB_SG=$(aws ec2 create-security-group --region "$AWS_REGION" \
  --group-name launchboard-phase-16-db-sg \
  --description "PostgreSQL from the EKS cluster only" \
  --vpc-id "$VPC_ID" --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --region "$AWS_REGION" \
  --group-id "$DB_SG" --protocol tcp --port 5432 --source-group "$CLUSTER_SG"

aws rds create-db-subnet-group --region "$AWS_REGION" \
  --db-subnet-group-name launchboard-phase-16-db-subnets \
  --db-subnet-group-description "Private subnets for the capstone database" \
  --subnet-ids $PRIVATE_SUBNETS
```

Create the instance (choose a strong master password — the same one you will put in the Kubernetes Secret):

```bash
aws rds create-db-instance --region "$AWS_REGION" \
  --db-instance-identifier launchboard-phase-16 \
  --engine postgres \
  --engine-version 16 \
  --db-instance-class db.t3.micro \
  --allocated-storage 20 \
  --storage-type gp3 \
  --storage-encrypted \
  --db-name launchboard \
  --master-username launchboard_user \
  --master-user-password 'CHANGE_ME_STRONG_PASSWORD' \
  --db-subnet-group-name launchboard-phase-16-db-subnets \
  --vpc-security-group-ids "$DB_SG" \
  --no-publicly-accessible \
  --backup-retention-period 1 \
  --no-multi-az
```

Line explanation:

- `--db-name launchboard` and `--master-username launchboard_user` match what every previous phase used, so `DATABASE_URL` keeps its familiar shape.
- `--no-publicly-accessible` plus the security group (5432 only from the cluster SG) is the same defense-in-depth as the NetworkPolicies inside the cluster — enforced at the VPC layer.
- `--backup-retention-period 1` turns on automated daily backups **and** point-in-time recovery — capabilities the PostgreSQL Pod never had without Velero. Production would use 7-30 days.
- `--no-multi-az` keeps the lab at ~$0.017/hour. `--multi-az` is the production flag: a synchronous standby in the second AZ with automatic failover, for roughly double the cost.

Creation takes 5-10 minutes. Wait for it, then capture the endpoint — you will substitute it into the manifests below:

```bash
aws rds wait db-instance-available --db-instance-identifier launchboard-phase-16 --region "$AWS_REGION"

RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier launchboard-phase-16 \
  --region "$AWS_REGION" --query 'DBInstances[0].Endpoint.Address' --output text)
echo "RDS endpoint: $RDS_ENDPOINT"
```

Reference:

- RDS for PostgreSQL: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html
- create-db-instance CLI: https://docs.aws.amazon.com/cli/latest/reference/rds/create-db-instance.html
- RDS Multi-AZ: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.html

### namespace.yaml

```bash
vim deployment/phase-16-production-capstone/app-k8s/namespace.yaml
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

### storageclass.yaml

```bash
vim deployment/phase-16-production-capstone/app-k8s/storageclass.yaml
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

Encrypted gp3 volumes, created in the Pod's AZ (`WaitForFirstConsumer`), expandable without recreation. The app itself no longer claims a volume (the database is RDS) — this StorageClass stays because **Prometheus** persists its metrics on it in Step 9.

### configmap.yaml

```bash
vim deployment/phase-16-production-capstone/app-k8s/configmap.yaml
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
  DB_HOST: YOUR_RDS_ENDPOINT
```

Two placeholders here: `CORS_ORIGINS` stays one until the ALB exists (the patch command at the end of this step fixes it), and `DB_HOST` gets the RDS endpoint stamped in by the `sed` in the deploy section. `DB_HOST` exists because the backend's and migration Job's wait loops need to know where PostgreSQL lives now that there is no `launchboard-db` Service inside the cluster. The `POSTGRES_DB`/`POSTGRES_USER` keys from earlier phases are gone — they existed to configure the postgres *container's* first boot, and RDS was configured at creation time instead.

### secret.example.yaml

```bash
vim deployment/phase-16-production-capstone/app-k8s/secret.example.yaml
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
  DATABASE_URL: postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@YOUR_RDS_ENDPOINT:5432/launchboard
```

Committed template only. The real Secret is created with `kubectl create secret` below (with the real password and the real RDS endpoint) and exists nowhere in Git — the same discipline as Terraform's `tfvars` and Ansible's Vault. Note the `DATABASE_URL` host is the RDS endpoint now, not a cluster-internal Service name.

### launchboard-migration-job.yaml

```bash
vim deployment/phase-16-production-capstone/app-k8s/launchboard-migration-job.yaml
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
          image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-backend:phase-16
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
              until python -c "import socket, os; s=socket.create_connection((os.environ['DB_HOST'], 5432), timeout=3); s.close()"; do
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

Migrations run once, as a Job, before the app — never from inside racing app replicas. The wait loop reads `DB_HOST` from the ConfigMap and blocks until RDS accepts connections.

### launchboard-backend-deployment.yaml

```bash
vim deployment/phase-16-production-capstone/app-k8s/launchboard-backend-deployment.yaml
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
          image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-backend:phase-16
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
              until python -c "import socket, os; s=socket.create_connection((os.environ['DB_HOST'], 5432), timeout=3); s.close()"; do
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

`maxUnavailable: 0` + readiness probe = zero-downtime rollouts: a new Pod must pass `/ready` before an old one is removed. UID 10001 matches the Dockerfile's pinned user exactly.

### launchboard-backend-service.yaml

```bash
vim deployment/phase-16-production-capstone/app-k8s/launchboard-backend-service.yaml
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
vim deployment/phase-16-production-capstone/app-k8s/launchboard-frontend-deployment.yaml
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
          image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-frontend:phase-16
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

### launchboard-frontend-service.yaml

```bash
vim deployment/phase-16-production-capstone/app-k8s/launchboard-frontend-service.yaml
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
vim deployment/phase-16-production-capstone/app-k8s/ingress.yaml
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
    alb.ingress.kubernetes.io/load-balancer-name: launchboard-phase-16
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

This is where a domain and TLS would plug in (see Extensions): an ACM certificate ARN annotation and an HTTPS listener. Everything else stays identical.

### hpa.yaml

```bash
vim deployment/phase-16-production-capstone/app-k8s/hpa.yaml
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

### pdb.yaml (new)

```bash
vim deployment/phase-16-production-capstone/app-k8s/pdb.yaml
```

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: launchboard-backend
  namespace: devops-launchboard
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: launchboard-backend
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: launchboard-frontend
  namespace: devops-launchboard
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: launchboard-frontend
```

Line explanation:

- A PodDisruptionBudget limits **voluntary disruptions**: node drains during upgrades, cluster autoscaler consolidation, `kubectl drain`. `minAvailable: 1` means the eviction API refuses to evict a Pod if doing so would leave fewer than one running.
- Concrete scenario it protects against: EKS replaces both worker nodes during a Kubernetes version upgrade. Without PDBs, both backend Pods can be evicted at the same moment — a user-visible outage even though replicas is 2. With the PDB, the drain of the second node waits until a replacement Pod is Ready elsewhere.
- PDBs do **not** protect against involuntary disruptions (node crash, OOM kill) — replicas across AZs and probes cover those.

Reference:

- PodDisruptionBudgets: https://kubernetes.io/docs/concepts/workloads/pods/disruptions/

### networkpolicies.yaml (new)

```bash
vim deployment/phase-16-production-capstone/app-k8s/networkpolicies.yaml
```

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: devops-launchboard
spec:
  podSelector: {}
  policyTypes:
    - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-from-anywhere
  namespace: devops-launchboard
spec:
  podSelector:
    matchLabels:
      app: launchboard-frontend
  policyTypes:
    - Ingress
  ingress:
    - ports:
        - protocol: TCP
          port: 8080
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-backend-from-frontend
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
```

Line explanation:

- `default-deny-ingress` has an empty `podSelector: {}` — it matches **every Pod in the namespace** and, by declaring `policyTypes: [Ingress]` with no `ingress` rules, denies all inbound traffic. Every rule after it is an explicit exception. Deny-by-default is the production posture: a compromised or misdeployed Pod cannot reach anything it was not explicitly granted.
- `allow-frontend-from-anywhere` permits inbound TCP 8080 to frontend Pods from any source — required because the ALB (target-type `ip`) sends traffic straight to Pod IPs from outside the cluster, so no `podSelector` could describe it.
- `allow-backend-from-frontend` is the tier rule: only Pods labeled `app: launchboard-frontend` may open connections to backend port 8000. `curl` from any other Pod in the cluster now times out — you can prove it after deploying (see verification below).
- There is no database policy because there is no database Pod — that boundary moved to the VPC layer: the RDS security group admits port 5432 only from the cluster security group. Same principle, enforced one layer down.
- These are the same tier boundaries the Phase 9 security groups and Phase 10 security groups drew at the VPC layer — here enforced between Pods by the VPC CNI's network policy agent enabled in Step 4.

Reference:

- NetworkPolicies: https://kubernetes.io/docs/concepts/services-networking/network-policies/
- EKS network policy: https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy.html

### kustomization.yaml

```bash
vim deployment/phase-16-production-capstone/app-k8s/kustomization.yaml
```

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - storageclass.yaml
  - configmap.yaml
  - launchboard-migration-job.yaml
  - launchboard-backend-deployment.yaml
  - launchboard-backend-service.yaml
  - launchboard-frontend-deployment.yaml
  - launchboard-frontend-service.yaml
  - ingress.yaml
  - hpa.yaml
  - pdb.yaml
  - networkpolicies.yaml
```

### Deploy

Stamp your account, region, and the RDS endpoint into the manifests:

```bash
cd /opt/devops-launchboard/app-source
sed -i "s|YOUR_ACCOUNT_ID|${ACCOUNT_ID}|g; s|YOUR_AWS_REGION|${AWS_REGION}|g" \
  deployment/phase-16-production-capstone/app-k8s/launchboard-backend-deployment.yaml \
  deployment/phase-16-production-capstone/app-k8s/launchboard-migration-job.yaml \
  deployment/phase-16-production-capstone/app-k8s/launchboard-frontend-deployment.yaml

sed -i "s|YOUR_RDS_ENDPOINT|${RDS_ENDPOINT}|g" \
  deployment/phase-16-production-capstone/app-k8s/configmap.yaml
```

(`$RDS_ENDPOINT` was exported at the end of the RDS creation step; if you opened a new shell, re-run that `describe-db-instances` command.)

Create the namespace and the real Secret — the password must match what you gave `create-db-instance`, and the host is the RDS endpoint:

```bash
kubectl apply -f deployment/phase-16-production-capstone/app-k8s/namespace.yaml

kubectl create secret generic launchboard-secret \
  --namespace devops-launchboard \
  --from-literal=POSTGRES_PASSWORD='CHANGE_ME_STRONG_PASSWORD' \
  --from-literal=DATABASE_URL="postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@${RDS_ENDPOINT}:5432/launchboard"
```

Apply everything and wait (no database rollout to wait for — RDS is already available):

```bash
kubectl apply -k deployment/phase-16-production-capstone/app-k8s

kubectl -n devops-launchboard wait --for=condition=complete job/launchboard-migrate --timeout=300s
kubectl -n devops-launchboard rollout status deployment/launchboard-backend --timeout=300s
kubectl -n devops-launchboard rollout status deployment/launchboard-frontend --timeout=300s
```

Fix CORS once the ALB exists:

```bash
kubectl -n devops-launchboard get ingress launchboard-ingress
```

Wait until ADDRESS shows a DNS name, then:

```bash
ALB_DNS=$(kubectl -n devops-launchboard get ingress launchboard-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "App URL: http://$ALB_DNS"

kubectl -n devops-launchboard patch configmap launchboard-config \
  -p "{\"data\":{\"CORS_ORIGINS\":\"http://${ALB_DNS}\"}}"
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
kubectl -n devops-launchboard rollout status deployment/launchboard-backend --timeout=180s
```

Verify the app and the security posture:

```bash
curl -s "http://$ALB_DNS/health" | jq
curl -s "http://$ALB_DNS/api/summary" | jq

# Prove the NetworkPolicy bites: this Pod is not the frontend,
# so the connection must TIME OUT (Ctrl+C after a few seconds)
kubectl -n devops-launchboard run netpol-test --rm -it --image=busybox:1.36 --restart=Never \
  -- nc -zv -w 3 launchboard-backend 8000

kubectl -n devops-launchboard get pdb
```

Open `http://$ALB_DNS` in the browser — the app is live. The `nc` probe should fail with a timeout, and both PDBs should show `ALLOWED DISRUPTIONS: 1`. The database boundary is verified at the AWS layer instead: RDS Console > launchboard-phase-16 > Connectivity shows `Publicly accessible: No` and only the `launchboard-phase-16-db-sg` security group.

## Step 8: Metrics Server And HPA

EKS does not ship the Metrics Server; the HPA shows `<unknown>` until it exists.

```bash
vim deployment/phase-16-production-capstone/monitoring/metrics-server-values.yaml
```

Paste:

```yaml
args:
  - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
  - --kubelet-use-node-status-port
  - --metric-resolution=15s
```

- `--kubelet-preferred-address-types=InternalIP,...` makes the Metrics Server reach kubelets by node IP first — the reliable path on private-networking EKS nodes.
- `--metric-resolution=15s` samples twice as often as the 30s default, so the HPA reacts faster during the load test.

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update

helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  -f deployment/phase-16-production-capstone/monitoring/metrics-server-values.yaml

kubectl -n kube-system rollout status deployment/metrics-server
```

Verify (give it one sampling window, ~30-60 seconds):

```bash
kubectl top nodes
kubectl -n devops-launchboard get hpa
```

The HPA TARGETS column should show a real percentage like `2%/70%` instead of `<unknown>/70%`.

## Step 9: Monitoring — Prometheus And Grafana

```bash
kubectl create namespace observability

vim deployment/phase-16-production-capstone/monitoring/kube-prometheus-stack-values.yaml
```

Paste:

```yaml
# Grafana configuration
grafana:
  enabled: true
  adminUser: admin
  adminPassword: CHANGE_ME_GRAFANA_PASSWORD
  service:
    type: ClusterIP
    port: 80
  persistence:
    enabled: false
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: default
          orgId: 1
          folder: ""
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/default
  dashboards:
    default:
      kubernetes-cluster:
        gnetId: 7249
        revision: 1
        datasource: Prometheus
      node-exporter-full:
        gnetId: 1860
        revision: 37
        datasource: Prometheus
      kubernetes-pods:
        gnetId: 6417
        revision: 1
        datasource: Prometheus

# Prometheus configuration
prometheus:
  prometheusSpec:
    retention: 3d
    retentionSize: 5GB
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 2Gi
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false

# Alertmanager configuration
alertmanager:
  enabled: true
  alertmanagerSpec:
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 200m
        memory: 256Mi

# node-exporter configuration
nodeExporter:
  enabled: true

# kube-state-metrics configuration
kubeStateMetrics:
  enabled: true

# Default rules (pre-built Prometheus alerting rules)
defaultRules:
  create: true
  rules:
    etcd: false
    kubeScheduler: false
```

Replace `CHANGE_ME_GRAFANA_PASSWORD`, then install:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --values deployment/phase-16-production-capstone/monitoring/kube-prometheus-stack-values.yaml \
  --timeout 10m

kubectl -n observability get pods
```

The values are the Phase 11 configuration (full line-by-line there): persistent Prometheus on a gp3 PVC with 3-day/5 GB retention, three auto-imported Grafana dashboards, all-namespace ServiceMonitor discovery, and etcd/scheduler rules disabled because EKS manages that control plane.

Access Grafana (add port 3000 to the workstation security group, your IP only):

```bash
kubectl -n observability port-forward service/kube-prometheus-stack-grafana 3000:80 --address 0.0.0.0 &
```

Open `http://YOUR_WORKSTATION_PUBLIC_IP:3000`, log in as `admin`, and confirm the Kubernetes Pods dashboard shows the launchboard Pods.

## Step 10: Backups — Velero With A Daily Schedule

### Bucket and IAM

```bash
export VELERO_BUCKET=devops-launchboard-velero-${ACCOUNT_ID}-${AWS_REGION}

aws s3api create-bucket \
  --bucket "$VELERO_BUCKET" \
  --region "$AWS_REGION" \
  $(if [ "$AWS_REGION" != "us-east-1" ]; then echo "--create-bucket-configuration LocationConstraint=$AWS_REGION"; fi)

aws s3api put-public-access-block \
  --bucket "$VELERO_BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

```bash
vim deployment/phase-16-production-capstone/backup/velero-iam-policy.json
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
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:CreateSnapshot",
        "ec2:DeleteSnapshot"
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
      "Resource": ["arn:aws:s3:::YOUR_VELERO_BUCKET/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": ["arn:aws:s3:::YOUR_VELERO_BUCKET"]
    }
  ]
}
```

The policy grants exactly what Velero needs: EBS snapshot lifecycle (that is how PVC data is backed up) and object access to this one bucket. Substitute the bucket name and create a dedicated IAM user for it:

```bash
sed -i "s|YOUR_VELERO_BUCKET|${VELERO_BUCKET}|g" deployment/phase-16-production-capstone/backup/velero-iam-policy.json

aws iam create-user --user-name velero-phase-16
aws iam put-user-policy --user-name velero-phase-16 --policy-name velero-policy \
  --policy-document file://deployment/phase-16-production-capstone/backup/velero-iam-policy.json
aws iam create-access-key --user-name velero-phase-16 > /tmp/velero-key.json

cat > /tmp/credentials-velero <<EOF
[default]
aws_access_key_id=$(jq -r '.AccessKey.AccessKeyId' /tmp/velero-key.json)
aws_secret_access_key=$(jq -r '.AccessKey.SecretAccessKey' /tmp/velero-key.json)
EOF
```

### Install Velero into the cluster

```bash
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.10.0 \
  --bucket "$VELERO_BUCKET" \
  --backup-location-config region="$AWS_REGION" \
  --snapshot-location-config region="$AWS_REGION" \
  --secret-file /tmp/credentials-velero

kubectl -n velero rollout status deployment/velero
rm /tmp/velero-key.json /tmp/credentials-velero
```

Command explanation:

- `velero install` deploys the Velero server Deployment plus its CRDs (Backup, Restore, Schedule, ...) into a `velero` namespace.
- `--plugins velero/velero-plugin-for-aws` adds the AWS object-store and volume-snapshotter plugin; check https://github.com/vmware-tanzu/velero-plugin-for-aws#compatibility for the version matching your Velero.
- `--bucket` + `--backup-location-config` say where backup metadata and resource JSON go; `--snapshot-location-config` enables EBS snapshots for PVCs.
- The credentials file is deleted from the workstation afterwards — it now lives only as a Secret in the `velero` namespace.

### Take a backup, schedule dailies

```bash
velero backup create launchboard-first --include-namespaces devops-launchboard --wait
velero backup describe launchboard-first
```

Expected: `Phase: Completed`. No volume snapshots this time — the app namespace no longer contains a PVC, because the database lives in RDS with its **own** backup system (automated daily snapshots plus point-in-time recovery, enabled by `--backup-retention-period`). Velero now covers exactly what it should: the Kubernetes objects. This split — platform state in Velero, data in the database's native backups — is how real teams divide DR responsibility. Now the schedule:

```bash
vim deployment/phase-16-production-capstone/backup/velero-daily-schedule.yaml
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
```

- `schedule: "0 3 * * *"` is standard cron: daily at 03:00 UTC.
- `snapshotVolumes: true` snapshots any EBS-backed PVC included in the backup. The app namespace has none now (RDS holds the data), but leaving it on costs nothing and protects you if a PVC is ever added back.
- `ttl: 168h` expires each backup (and its snapshot) after 7 days, capping storage cost automatically.

```bash
kubectl apply -f deployment/phase-16-production-capstone/backup/velero-daily-schedule.yaml
velero schedule get
```

### The restore drill

A backup that has never been restored is a hope, not a plan. Prove it works — add a project or task in the app UI first so you can verify data survives, then:

```bash
velero backup create launchboard-drill --include-namespaces devops-launchboard --wait

kubectl delete namespace devops-launchboard    # the "disaster"

velero restore create --from-backup launchboard-drill --wait
kubectl -n devops-launchboard get pods
```

Wait for everything to reach Running/Completed (a few minutes — no volume restore is needed, because the data never left: deleting the namespace destroyed the *application*, while RDS sat untouched outside the cluster). The ALB is recreated by the controller, so its DNS name changed — repeat the CORS fix:

```bash
ALB_DNS=$(kubectl -n devops-launchboard get ingress launchboard-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
kubectl -n devops-launchboard patch configmap launchboard-config \
  -p "{\"data\":{\"CORS_ORIGINS\":\"http://${ALB_DNS}\"}}"
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
```

Open the new URL: your test data is there — not because it was restored, but because it was never lost. That is the payoff of separating state (RDS) from workload (the cluster): the whole namespace, even the whole cluster, becomes disposable.

For the *database* disaster case (bad migration, data corruption), RDS gives you two levers Velero never could:

```bash
# a manual snapshot before anything risky (like a schema migration)
aws rds create-db-snapshot --db-instance-identifier launchboard-phase-16 \
  --db-snapshot-identifier launchboard-pre-migration --region "$AWS_REGION"

# and point-in-time recovery exists automatically - see your restorable window:
aws rds describe-db-instances --db-instance-identifier launchboard-phase-16 \
  --region "$AWS_REGION" --query 'DBInstances[0].LatestRestorableTime'
```

Restoring either one creates a **new** RDS instance from the snapshot/timestamp; you then point `DATABASE_URL` at it. Try `describe-db-snapshots --db-instance-identifier launchboard-phase-16` to see the automated dailies accumulating.

Reference:

- Velero docs: https://velero.io/docs/
- AWS plugin: https://github.com/vmware-tanzu/velero-plugin-for-aws

## Step 11: Load Validation With k6

Do not call a deployment production-ready until it has held real load with the autoscaler engaged.

```bash
vim deployment/phase-16-production-capstone/tests/k6/load-test.js
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

- `stages` ramp to 20 virtual users over 2 minutes, hold for 5, ramp down — the standard load-test shape (ramp/hold/ramp) from Phase 15.
- `thresholds` are the pass/fail contract: under 2% failed requests, 95th percentile under 800 ms, 99th under 1500 ms. If any threshold fails, k6 exits non-zero — in a pipeline, that fails the build.
- Each iteration fetches three endpoints in parallel with `http.batch` (frontend page, backend health through the frontend proxy, backend readiness) and `check`s each for 200.

Run it from the workstation via Docker, while watching the HPA in a second terminal:

Terminal 1:

```bash
kubectl -n devops-launchboard get hpa -w
```

Terminal 2:

```bash
cd /opt/devops-launchboard/app-source
docker run --rm -i -e BASE_URL="http://$ALB_DNS" grafana/k6 run - \
  < deployment/phase-16-production-capstone/tests/k6/load-test.js
```

What to look for:

- The k6 summary ends with all thresholds green (`✓`).
- The HPA watch shows CPU climbing; if it crosses 70%, REPLICAS steps up (3, 4...) and steps back down a few minutes after the ramp-down (scale-down is deliberately slow — the stabilization window prevents flapping).
- In Grafana (Kubernetes Pods dashboard), the backend Pods' CPU curves rise and the new replicas appear mid-test.

## Step 12: The Runbook

Operations knowledge in someone's head is not production grade; write it down where the next responder can find it.

```bash
vim deployment/phase-16-production-capstone/runbooks/production-runbook.md
```

The full runbook ships in this phase folder — it covers first-response commands and seven situations: app unreachable, backend CrashLoopBackOff, database down, rollback, restore from backup, ALB DNS change, and node/capacity problems, plus a weekly checks list. Read it end to end once now, and once more while everything is healthy — a runbook you first open during an incident is too late.

Walk through Situation 4 (rollback) right now as practice, since a rollout is harmless:

```bash
kubectl -n devops-launchboard rollout history deployment/launchboard-backend
kubectl -n devops-launchboard rollout undo deployment/launchboard-backend
kubectl -n devops-launchboard rollout status deployment/launchboard-backend
curl -s "http://$ALB_DNS/health" | jq
```

## Production Checklist

```text
=== Infrastructure ===
[ ] AWS Budget created
[ ] EKS cluster with OIDC, private workers, control plane logging
[ ] NetworkPolicy enforcement enabled (vpc-cni addon)
[ ] Images in ECR, scan-on-push enabled, lifecycle policy attached
[ ] RDS in private subnets, not publicly accessible, encrypted, backups on

=== Application ===
[ ] All Pods Running; migration Job Completed
[ ] App reachable via ALB URL
[ ] CORS patched to the real ALB DNS
[ ] All containers non-root, capabilities dropped, seccomp default
[ ] Secret created via kubectl only (nothing real in Git)
[ ] Zero-downtime rollout verified (maxUnavailable 0 + readiness)

=== Resilience ===
[ ] HPA shows real utilization and scaled during the load test
[ ] PDBs present with ALLOWED DISRUPTIONS >= 1
[ ] NetworkPolicy verified: test Pod CANNOT reach the backend
[ ] RDS reachable only from the cluster SG (checked in the console)
[ ] Rollback rehearsed with rollout undo

=== Operations ===
[ ] Prometheus + Grafana up; dashboards show the app Pods
[ ] Velero daily schedule active (velero schedule get)
[ ] Restore drill performed - data verified after restore
[ ] k6 load test passed all thresholds
[ ] Runbook read and rollback situation rehearsed

=== Cost ===
[ ] Cleanup plan understood; budget alarm in place
```

## Cleanup

```bash
pkill -f "port-forward" || true

# Observability and backups
helm uninstall kube-prometheus-stack --namespace observability
kubectl delete namespace observability
kubectl delete namespace velero

# Application (ALB is deleted by the controller - wait 2-3 minutes)
kubectl delete namespace devops-launchboard

# RDS - MUST be deleted before the cluster, or eksctl cannot delete the VPC
aws rds delete-db-instance --db-instance-identifier launchboard-phase-16 \
  --skip-final-snapshot --delete-automated-backups --region "$AWS_REGION"
aws rds wait db-instance-deleted --db-instance-identifier launchboard-phase-16 --region "$AWS_REGION"
aws rds delete-db-subnet-group --db-subnet-group-name launchboard-phase-16-db-subnets --region "$AWS_REGION"
DB_SG=$(aws ec2 describe-security-groups --region "$AWS_REGION" \
  --filters Name=group-name,Values=launchboard-phase-16-db-sg --query 'SecurityGroups[0].GroupId' --output text)
aws ec2 delete-security-group --group-id "$DB_SG" --region "$AWS_REGION"

# ALB controller + IAM
helm uninstall aws-load-balancer-controller --namespace kube-system
eksctl delete iamserviceaccount --cluster "$CLUSTER_NAME" --namespace kube-system \
  --name aws-load-balancer-controller --region "$AWS_REGION"

# Cluster (10-20 minutes)
eksctl delete cluster --name "$CLUSTER_NAME" --region "$AWS_REGION"

# ECR, S3, IAM
aws ecr delete-repository --repository-name launchboard-backend --force --region "$AWS_REGION"
aws ecr delete-repository --repository-name launchboard-frontend --force --region "$AWS_REGION"
aws s3 rm "s3://$VELERO_BUCKET" --recursive
aws s3api delete-bucket --bucket "$VELERO_BUCKET" --region "$AWS_REGION"
ACCESS_KEY_ID=$(aws iam list-access-keys --user-name velero-phase-16 --query 'AccessKeyMetadata[0].AccessKeyId' --output text)
aws iam delete-access-key --user-name velero-phase-16 --access-key-id "$ACCESS_KEY_ID"
aws iam delete-user-policy --user-name velero-phase-16 --policy-name velero-policy
aws iam delete-user --user-name velero-phase-16
aws iam delete-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicyPhase16"
```

Also delete the EBS **snapshots** Velero created (Console > EC2 > Snapshots — filter by the velero tag) and check Load Balancers, Volumes, NAT Gateways, and Elastic IPs are empty. Terminate the workstation last.

## Troubleshooting

### Problem 1: NetworkPolicies apply but nothing is blocked

The VPC CNI network policy agent is not enabled. Confirm the addon configuration: `aws eks describe-addon --cluster-name $CLUSTER_NAME --addon-name vpc-cni --region $AWS_REGION --query 'addon.configurationValues'` should show `enableNetworkPolicy: "true"`. If the cluster was created without it, update the addon: `aws eks update-addon --cluster-name $CLUSTER_NAME --addon-name vpc-cni --configuration-values '{"enableNetworkPolicy": "true"}' --region $AWS_REGION` and wait for the aws-node Pods to roll.

### Problem 2: Migration Job or backend stuck printing "waiting for postgres"

The wait loop cannot reach RDS on port 5432. Three checks, in order:

```bash
kubectl -n devops-launchboard get configmap launchboard-config -o jsonpath='{.data.DB_HOST}'; echo
```

1. If that prints `YOUR_RDS_ENDPOINT`, the `sed` stamping step was skipped — re-run it and `kubectl apply -k` again.
2. The DB security group must allow 5432 **from the cluster security group** (`aws ec2 describe-security-groups --group-ids "$DB_SG"` and check the ingress rule's source).
3. The instance must be `available`: `aws rds describe-db-instances --db-instance-identifier launchboard-phase-16 --query 'DBInstances[0].DBInstanceStatus'`.

If DATABASE_URL's password does not match the RDS master password, the wait loop *passes* (TCP connects) but the migration then fails with an authentication error — check `kubectl -n devops-launchboard logs job/launchboard-migrate`.

### Problem 3: ALB never gets an address

`kubectl -n kube-system logs deployment/aws-load-balancer-controller --tail=50`. Usual causes: the IRSA ServiceAccount was not created before the Helm install, or the IAM policy name collided with a leftover from a previous phase (this phase deliberately uses `...Phase16`).

### Problem 4: Velero backup PartiallyFailed with snapshot errors

The IAM user policy is missing or the bucket name inside it was not substituted (`grep YOUR_VELERO_BUCKET deployment/phase-16-production-capstone/backup/velero-iam-policy.json` must return nothing). Fix the policy, `aws iam put-user-policy` again, and restart the Velero Pod: `kubectl -n velero rollout restart deployment/velero`.

### Problem 5: Restore completes but the app is broken

Two known follow-ups after every restore: the ALB DNS changed (re-run the CORS patch — runbook Situation 6), and the migration Job restored as already-Completed (fine — the schema still exists in RDS, which the namespace deletion never touched).

### Problem 6: HPA never scales during the load test

Check `kubectl top pods -n devops-launchboard` works (Metrics Server), and that the load actually pushes CPU past 70% of *requests* (100m) — if your nodes are fast, raise the k6 `target` to 40-50 VUs. Remember the HPA formula uses requests, not limits.

### Problem 7: `eksctl delete cluster` hangs or fails deleting the VPC

RDS (or its security group / subnet group) still exists inside the cluster's VPC — AWS refuses to delete a VPC with resources in it. Run the RDS deletion commands from the Cleanup section first, wait for `db-instance-deleted`, then re-run `eksctl delete cluster`.

### Problem 8: Prometheus or Elasticsearch-style Pods Pending for resources

Two t3.medium nodes are close to full with app + monitoring + Velero. Scale to 3: `eksctl scale nodegroup --cluster $CLUSTER_NAME --name launchboard-workers --nodes 3 --region $AWS_REGION`.

## Reference Documentation

| Topic | Link |
| --- | --- |
| Amazon EKS | https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html |
| eksctl | https://eksctl.io/ |
| ALB controller | https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/ |
| NetworkPolicies | https://kubernetes.io/docs/concepts/services-networking/network-policies/ |
| PodDisruptionBudgets | https://kubernetes.io/docs/concepts/workloads/pods/disruptions/ |
| HPA | https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/ |
| kube-prometheus-stack | https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack |
| Velero | https://velero.io/docs/ |
| k6 | https://grafana.com/docs/k6/latest/ |
| EKS best practices | https://docs.aws.amazon.com/eks/latest/best-practices/introduction.html |

## Extensions: The Last Steps To "Real" Production

When you are ready to spend a few dollars a month, three additions complete the picture.

### Extension 1: Domain + HTTPS (~$12/year for the domain, certificate free)

1. Register a domain in Route 53 (Console > Route 53 > Registered domains), or transfer one you own.
2. Request a **public certificate** in ACM for `yourdomain.com` (and `*.yourdomain.com` if you want subdomains) — ACM certificates are free:

```bash
CERT_ARN=$(aws acm request-certificate --domain-name yourdomain.com \
  --validation-method DNS --region "$AWS_REGION" --query CertificateArn --output text)
aws acm describe-certificate --certificate-arn "$CERT_ARN" --region "$AWS_REGION" \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord'
```

3. Create the CNAME record ACM printed (Route 53 > your hosted zone > Create record) — with the domain in Route 53, the ACM console even has a "Create records in Route 53" button. Wait for the certificate status to become `ISSUED` (minutes).
4. Add three annotations to `ingress.yaml` and change the listen ports:

```yaml
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/certificate-arn: YOUR_CERT_ARN
    alb.ingress.kubernetes.io/ssl-redirect: "443"
```

5. Apply the Ingress, then point the domain at the ALB: Route 53 > hosted zone > Create record > A record > Alias > Application Load Balancer > pick `launchboard-phase-16`.
6. Update `CORS_ORIGINS` to `https://yourdomain.com` and restart the backend — and the DNS-changes-after-restore problem disappears forever, because the alias record follows any new ALB you point it at.

### Extension 2: Node Autoscaling (Cluster Autoscaler)

The HPA adds *Pods* under load, but when the nodes are full, new Pods sit `Pending` — you saw exactly this when Vault replicas would not schedule in Phase 12, and the fix was a manual `eksctl scale nodegroup`. The Cluster Autoscaler automates that: it watches for Pending Pods and grows the node group (within the `minSize`/`maxSize` you already set in the eksctl config), then shrinks it when nodes sit underused.

```bash
# IAM permissions via IRSA (the same pattern as the ALB controller)
cat > /tmp/cluster-autoscaler-policy.json << 'POLICY'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:DescribeImages",
        "ec2:GetInstanceTypesFromInstanceRequirements",
        "eks:DescribeNodegroup"
      ],
      "Resource": "*"
    }
  ]
}
POLICY

aws iam create-policy --policy-name ClusterAutoscalerPolicyPhase16 \
  --policy-document file:///tmp/cluster-autoscaler-policy.json

eksctl create iamserviceaccount --cluster "$CLUSTER_NAME" --namespace kube-system \
  --name cluster-autoscaler \
  --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/ClusterAutoscalerPolicyPhase16" \
  --approve --region "$AWS_REGION"

helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update
helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName="$CLUSTER_NAME" \
  --set awsRegion="$AWS_REGION" \
  --set rbac.serviceAccount.create=false \
  --set rbac.serviceAccount.name=cluster-autoscaler

kubectl -n kube-system rollout status deployment/cluster-autoscaler-aws-cluster-autoscaler
```

- `autoDiscovery.clusterName` makes the autoscaler find the node group by the `k8s.io/cluster-autoscaler/...` tags eksctl already put on it — no ASG names to hardcode.
- Test it: raise the backend HPA's `maxReplicas` to something the two nodes cannot hold (say 12), run the k6 stress shape, and watch `kubectl get nodes -w` — a third node appears within ~2 minutes of Pods going Pending, and disappears ~10 minutes after load ends. Your PDBs (Step 7) are what guarantee the scale-*down* never drops the app below one Pod per tier.
- The modern successor is **Karpenter** (https://karpenter.sh) — instead of resizing a fixed node group, it provisions right-sized instances directly, faster and often cheaper. Its setup (interruption queues, NodePool CRDs) deserves its own lab; learn the Cluster Autoscaler model first, then read Karpenter's docs with that mental model.

### Extension 3: Automate The Deploy

Wire the Phase 7 Jenkins pipeline (or GitHub Actions) at the front: build → test → scan → push to ECR → `kubectl apply -k` → rollout status → smoke test. Everything this guide did manually becomes one `git push`. Better yet, run it GitOps-style with the Phase 7 ArgoCD lab: point an Application at this phase's `app-k8s/` folder and let the cluster sync itself to Git — drift detection and audited rollbacks included.

## Congratulations

You have deployed the same application sixteen different ways — from `python main.py` on bare metal to an autoscaled, monitored, backed-up, network-segmented, load-validated Kubernetes deployment on AWS. More importantly, you now know *why* each layer exists, because you lived without it first. That is the whole point of the journey.
