# Phase 8: Amazon EKS

## Fresh Start Assumption

This phase starts from a clean AWS environment and a clean Ubuntu EC2 workstation.

You do not need to complete any previous phase before using this guide.

This guide assumes:

- You have an AWS account.
- You have permission to create EKS, EC2, IAM, ECR, ALB, CloudWatch, VPC, NAT Gateway, and EBS resources.
- You have a fresh Ubuntu EC2 server or local Ubuntu machine for running commands.
- Docker, AWS CLI, kubectl, eksctl, and Helm are not installed yet.
- The repository is not cloned yet.
- You will create files with `vim`.
- You will type commands manually.
- You will not use shell scripts.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What You Will Deploy

This phase deploys the N-tier application to Amazon EKS:

- Amazon EKS cluster.
- Managed node group.
- EKS OIDC provider.
- EBS CSI driver for persistent volumes.
- ECR repositories for backend and frontend images.
- AWS Load Balancer Controller.
- PostgreSQL running inside Kubernetes for the student lab.
- FastAPI backend Deployment.
- React/Vite frontend Nginx Deployment.
- Application Load Balancer through Kubernetes Ingress.
- HPA example for backend scaling.

Architecture:

```text
Browser
  |
  | HTTP
  v
AWS Application Load Balancer
  |
  v
AWS Load Balancer Controller / Kubernetes Ingress
  |
  v
Frontend Service
  |
  v
Frontend Pods
  |
  | /api, /health, /ready
  v
Backend Service
  |
  v
Backend Pods
  |
  v
PostgreSQL Service
  |
  v
PostgreSQL Pod + encrypted gp3 EBS volume
```

## When To Use This Architecture

Use EKS when:

- You want managed Kubernetes on AWS.
- You need production-style Kubernetes features without managing the control plane yourself.
- You want to learn IAM, ECR, node groups, managed add-ons, ALB Ingress, and cloud Kubernetes operations.
- You want a path toward autoscaling, GitOps, observability, security, and disaster recovery.

Do not use this architecture when:

- You only need a tiny app and do not need Kubernetes.
- You cannot accept EKS, EC2, ALB, NAT Gateway, EBS, and data transfer costs.
- You are not ready to manage Kubernetes operations.

Production note:

This lab runs PostgreSQL inside Kubernetes to keep the phase self-contained. Serious production should use Amazon RDS or another managed database with backups, monitoring, encryption, and high availability.

## Cost Warning

EKS can become expensive.

Costs may include:

- EKS control plane hourly charge.
- EC2 worker nodes.
- EBS volumes.
- NAT Gateway.
- Application Load Balancer.
- ECR image storage.
- CloudWatch logs.
- Data transfer.

Create an AWS Budget before starting.

Reference:

- AWS Budgets: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html
- EKS pricing: https://aws.amazon.com/eks/pricing/

## Recommended AWS Setup

| Item | Recommended Value |
| --- | --- |
| AWS Region | `ap-southeast-1` or your closest region |
| EKS Cluster | `devops-launchboard-phase-8` |
| Kubernetes Version | `1.34` |
| Node Group | `launchboard-workers` |
| Node Type | `t3.medium` |
| Desired Nodes | `2` |
| ECR Backend Repo | `launchboard-backend` |
| ECR Frontend Repo | `launchboard-frontend` |
| Public Access | ALB only |

## Files Included In This Phase

```text
deployment/phase-8-eks/
+-- cluster/
|   +-- eksctl-cluster.yaml
+-- ecr/
|   +-- lifecycle-policy.json
+-- k8s/
|   +-- namespace.yaml
|   +-- storageclass.yaml
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
+-- nginx-frontend.conf
+-- README.md
```

## Step 1: Prepare AWS IAM User Or Role

Use an IAM principal that can create:

```text
EKS clusters
EC2 instances
VPC resources
IAM roles and policies
ECR repositories
CloudWatch logs
Elastic Load Balancers
EBS volumes
```

Why this step exists:

EKS creates many AWS resources. Missing IAM permissions are one of the most common reasons EKS setup fails.

Reference:

- EKS IAM: https://docs.aws.amazon.com/eks/latest/userguide/security-iam.html

## Step 2: Create EC2 Workstation

Create one EC2 server for running commands:

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-8-workstation` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` |
| Storage | 30 GB gp3 |
| SSH | Port `22`, your IP only |

Why this step exists:

This server is only the admin workstation. The application will run on EKS worker nodes.

## Step 3: SSH Into Workstation

Run from your local machine:

```bash
chmod 400 devops-launchboard-key.pem
ssh -i devops-launchboard-key.pem ubuntu@YOUR_WORKSTATION_PUBLIC_IP
```

Verify:

```bash
whoami
hostname
pwd
```

## Step 4: Install Base Tools

Run:

```bash
cd ~
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl wget vim unzip jq ca-certificates gnupg lsb-release
```

Why this step exists:

These tools let you clone the repository, install AWS tooling, edit files, and test endpoints.

## Step 5: Install Docker

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
ssh -i devops-launchboard-key.pem ubuntu@YOUR_WORKSTATION_PUBLIC_IP
```

Verify:

```bash
docker --version
docker info
```

Reference:

- Docker Engine Ubuntu install: https://docs.docker.com/engine/install/ubuntu/

## Step 6: Install AWS CLI

Run:

```bash
cd ~
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version
```

Configure AWS credentials:

```bash
aws configure
```

Enter:

```text
AWS Access Key ID
AWS Secret Access Key
Default region
Default output format: json
```

Verify:

```bash
aws sts get-caller-identity
```

Reference:

- Install AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

## Step 7: Install kubectl, eksctl, And Helm

Install kubectl:

```bash
cd ~
curl -LO "https://dl.k8s.io/release/stable.txt"
KUBECTL_VERSION=$(cat stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl
rm stable.txt
```

Install eksctl:

```bash
cd ~
curl --silent --location "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" -o eksctl.tar.gz
tar -xzf eksctl.tar.gz
sudo mv eksctl /usr/local/bin/eksctl
rm eksctl.tar.gz
```

Install Helm:

```bash
cd ~
curl -fsSL https://baltocdn.com/helm/signing.asc | sudo gpg --dearmor -o /usr/share/keyrings/helm.gpg
sudo apt install -y apt-transport-https
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt update
sudo apt install -y helm
```

Verify:

```bash
kubectl version --client
eksctl version
helm version
```

Reference:

- kubectl install: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
- eksctl install: https://eksctl.io/installation/
- Helm install: https://helm.sh/docs/intro/install/

## Step 8: Create GitHub SSH Key And Clone Repository

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-8-eks" -f ~/.ssh/devops_launchboard_github_key
cat ~/.ssh/devops_launchboard_github_key.pub
```

Add the public key to GitHub as a read-only deploy key.

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

Clone:

```bash
sudo mkdir -p /opt/devops-launchboard
sudo chown -R ubuntu:ubuntu /opt/devops-launchboard
cd /opt/devops-launchboard
git clone git@github.com:ashraful2430/N-tier-application.git app-source
cd app-source
```

## Step 9: Create Phase 8 Folders

Run:

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-8-eks/cluster
mkdir -p deployment/phase-8-eks/ecr
mkdir -p deployment/phase-8-eks/k8s
```

Why this step exists:

The phase folder keeps cluster config, image registry policy, Dockerfiles, and Kubernetes manifests together.

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

Docker should not send secrets, dependency folders, virtual environments, caches, or build output into image builds.

## Step 11: Create EKS Cluster Config

Run:

```bash
vim deployment/phase-8-eks/cluster/eksctl-cluster.yaml
```

Paste:

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: devops-launchboard-phase-8
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
      Environment: phase-8
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

Example:

```text
ap-southeast-1
```

Why this file exists:

This file tells `eksctl` how to create the EKS cluster, node group, OIDC provider, CloudWatch logging, and EBS CSI add-on.

## Step 12: Create ECR Lifecycle Policy

Run:

```bash
vim deployment/phase-8-eks/ecr/lifecycle-policy.json
```

Paste:

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep the latest 10 phase 8 images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["phase-8"],
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

Why this file exists:

ECR stores Docker images. Lifecycle policies prevent old images from piling up forever and creating unnecessary storage cost.

## Step 13: Create Dockerfiles And Nginx Config

Create:

```bash
vim deployment/phase-8-eks/Dockerfile.backend
vim deployment/phase-8-eks/Dockerfile.frontend
vim deployment/phase-8-eks/nginx-frontend.conf
```

Use the matching file contents from this phase folder. They are the same production multi-stage backend and frontend image style used in earlier container phases, but the frontend Dockerfile points to:

```text
deployment/phase-8-eks/nginx-frontend.conf
```

Why this step exists:

EKS worker nodes pull these images from ECR. The images must be built before the Kubernetes manifests can run.

## Step 14: Create Kubernetes Manifests

Create each file under:

```text
deployment/phase-8-eks/k8s/
```

Important replacements:

```text
YOUR_ACCOUNT_ID
YOUR_AWS_REGION
YOUR_ALB_DNS_NAME
```

Use `vim` to create or edit each file.

The important files are:

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

Why this step exists:

These manifests define the Kubernetes application. The image fields point to ECR because EKS nodes pull images from AWS ECR.

## Step 15: Create ECR Repositories

Set variables:

```bash
AWS_REGION=YOUR_AWS_REGION
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

Create repositories:

```bash
aws ecr create-repository --repository-name launchboard-backend --region "$AWS_REGION"
aws ecr create-repository --repository-name launchboard-frontend --region "$AWS_REGION"
```

Add lifecycle policy:

```bash
aws ecr put-lifecycle-policy --repository-name launchboard-backend --lifecycle-policy-text file://deployment/phase-8-eks/ecr/lifecycle-policy.json --region "$AWS_REGION"
aws ecr put-lifecycle-policy --repository-name launchboard-frontend --lifecycle-policy-text file://deployment/phase-8-eks/ecr/lifecycle-policy.json --region "$AWS_REGION"
```

Why this step exists:

EKS nodes need a registry to pull backend and frontend images.

Reference:

- Amazon ECR: https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html

## Step 16: Build And Push Images To ECR

Log in to ECR:

```bash
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
```

Build images:

```bash
cd /opt/devops-launchboard/app-source
docker build -f deployment/phase-8-eks/Dockerfile.backend -t launchboard-backend:phase-8 .
docker build -f deployment/phase-8-eks/Dockerfile.frontend --build-arg VITE_API_URL= -t launchboard-frontend:phase-8 .
```

Tag images:

```bash
docker tag launchboard-backend:phase-8 "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-8"
docker tag launchboard-frontend:phase-8 "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-frontend:phase-8"
```

Push images:

```bash
docker push "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-8"
docker push "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-frontend:phase-8"
```

Why this step exists:

Kubernetes manifests reference these ECR image URLs. If images are not pushed, EKS Pods fail with `ImagePullBackOff`.

## Step 17: Create EKS Cluster

Run:

```bash
cd /opt/devops-launchboard/app-source
eksctl create cluster -f deployment/phase-8-eks/cluster/eksctl-cluster.yaml
```

This can take 20 to 40 minutes.

Verify:

```bash
kubectl get nodes
kubectl get pods -A
```

Why this step exists:

This creates the managed EKS control plane, worker nodes, networking, OIDC provider, and EBS CSI add-on.

Reference:

- eksctl create cluster: https://eksctl.io/usage/creating-and-managing-clusters/

## Step 18: Install AWS Load Balancer Controller

Set variables:

```bash
CLUSTER_NAME=devops-launchboard-phase-8
AWS_REGION=YOUR_AWS_REGION
```

Download IAM policy:

```bash
curl -o aws-load-balancer-controller-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
```

Create IAM policy:

```bash
aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://aws-load-balancer-controller-policy.json
```

Create service account:

```bash
eksctl create iamserviceaccount \
  --cluster "$CLUSTER_NAME" \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy" \
  --approve \
  --region "$AWS_REGION"
```

Install controller with Helm:

```bash
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

Why this step exists:

The AWS Load Balancer Controller watches Kubernetes Ingress objects and creates AWS Application Load Balancers.

Reference:

- AWS Load Balancer Controller: https://kubernetes-sigs.github.io/aws-load-balancer-controller/

## Step 19: Create Kubernetes Secret

Apply namespace:

```bash
kubectl apply -f deployment/phase-8-eks/k8s/namespace.yaml
```

Create Secret:

```bash
kubectl create secret generic launchboard-secret \
  --namespace devops-launchboard \
  --from-literal=POSTGRES_PASSWORD='CHANGE_ME_STRONG_PASSWORD' \
  --from-literal=DATABASE_URL='postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@launchboard-db:5432/launchboard'
```

Use a stronger password for real labs.

Why this step exists:

The real secret should be created manually or by a secrets manager. It should not be committed into Git.

## Step 20: Update Image Placeholders

Open these files with `vim`:

```bash
vim deployment/phase-8-eks/k8s/launchboard-backend-deployment.yaml
vim deployment/phase-8-eks/k8s/launchboard-migration-job.yaml
vim deployment/phase-8-eks/k8s/launchboard-frontend-deployment.yaml
```

Replace:

```text
YOUR_ACCOUNT_ID
YOUR_AWS_REGION
```

Example image:

```text
123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/launchboard-backend:phase-8
```

Why this step exists:

Kubernetes must know the exact ECR image URLs.

## Step 21: Apply Kubernetes Manifests

Run:

```bash
kubectl apply -k deployment/phase-8-eks/k8s
```

Wait:

```bash
kubectl -n devops-launchboard rollout status deployment/launchboard-db --timeout=300s
kubectl -n devops-launchboard wait --for=condition=complete job/launchboard-migrate --timeout=300s
kubectl -n devops-launchboard rollout status deployment/launchboard-backend --timeout=300s
kubectl -n devops-launchboard rollout status deployment/launchboard-frontend --timeout=300s
```

Verify:

```bash
kubectl -n devops-launchboard get all
kubectl -n devops-launchboard get pvc
kubectl -n devops-launchboard get ingress
```

## Step 22: Get ALB URL

Run:

```bash
kubectl -n devops-launchboard get ingress launchboard-ingress
```

Wait until the `ADDRESS` field shows an ALB DNS name.

Example:

```text
launchboard-phase-8-123456.ap-southeast-1.elb.amazonaws.com
```

Open:

```text
http://YOUR_ALB_DNS_NAME
```

## Step 23: Update CORS To ALB DNS

Open:

```bash
vim deployment/phase-8-eks/k8s/configmap.yaml
```

Set:

```text
CORS_ORIGINS: http://YOUR_ALB_DNS_NAME
```

Apply and restart backend:

```bash
kubectl apply -f deployment/phase-8-eks/k8s/configmap.yaml
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
kubectl -n devops-launchboard rollout status deployment/launchboard-backend
```

Why this step exists:

The exact ALB DNS name is known only after AWS creates the load balancer.

## Step 24: Verify App

Run:

```bash
ALB_DNS=YOUR_ALB_DNS_NAME
curl -I "http://$ALB_DNS"
curl -s "http://$ALB_DNS/health" | jq
curl -s "http://$ALB_DNS/ready" | jq
curl -s "http://$ALB_DNS/api/summary" | jq
```

Expected:

```text
Frontend loads.
API returns data.
Backend readiness is healthy.
PostgreSQL data is seeded.
```

## Logs And Debugging

Useful commands:

```bash
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard describe pod POD_NAME
kubectl -n devops-launchboard logs deployment/launchboard-backend
kubectl -n devops-launchboard logs deployment/launchboard-frontend
kubectl -n devops-launchboard logs deployment/launchboard-db
kubectl -n devops-launchboard describe ingress launchboard-ingress
kubectl -n kube-system logs deployment/aws-load-balancer-controller
```

AWS checks:

```bash
aws eks describe-cluster --name devops-launchboard-phase-8 --region "$AWS_REGION"
aws ecr describe-repositories --region "$AWS_REGION"
aws elbv2 describe-load-balancers --region "$AWS_REGION"
```

## Rollout And Rollback

Build and push a new backend tag:

```bash
docker build -f deployment/phase-8-eks/Dockerfile.backend -t launchboard-backend:phase-8-v2 .
docker tag launchboard-backend:phase-8-v2 "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-8-v2"
docker push "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-8-v2"
```

Update image:

```bash
kubectl -n devops-launchboard set image deployment/launchboard-backend backend="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-8-v2"
kubectl -n devops-launchboard rollout status deployment/launchboard-backend
```

Rollback:

```bash
kubectl -n devops-launchboard rollout undo deployment/launchboard-backend
kubectl -n devops-launchboard rollout status deployment/launchboard-backend
```

## Troubleshooting

### Problem 1: EKS Cluster Creation Fails

Check:

```bash
eksctl get cluster
aws cloudformation list-stacks --region "$AWS_REGION"
```

Common causes:

```text
Missing IAM permissions.
Region typo.
Service quota too low.
Subnet or VPC creation failure.
```

### Problem 2: Pods Show ImagePullBackOff

Check:

```bash
kubectl -n devops-launchboard describe pod POD_NAME
aws ecr describe-images --repository-name launchboard-backend --region "$AWS_REGION"
```

Common causes:

```text
Image was not pushed.
Wrong account ID.
Wrong region.
Wrong tag.
```

### Problem 3: Ingress Has No Address

Check:

```bash
kubectl -n devops-launchboard describe ingress launchboard-ingress
kubectl -n kube-system logs deployment/aws-load-balancer-controller
```

Common causes:

```text
AWS Load Balancer Controller missing.
Controller IAM policy missing.
Subnet discovery tags missing.
Security group issue.
```

### Problem 4: PVC Is Pending

Check:

```bash
kubectl -n devops-launchboard describe pvc launchboard-postgres-pvc
kubectl get storageclass
kubectl -n kube-system get pods | grep ebs
```

Common causes:

```text
EBS CSI driver not installed.
No worker node available.
StorageClass name is wrong.
```

## Cleanup

Delete app:

```bash
kubectl delete namespace devops-launchboard
```

Delete ALB controller:

```bash
helm uninstall aws-load-balancer-controller --namespace kube-system
eksctl delete iamserviceaccount --cluster devops-launchboard-phase-8 --namespace kube-system --name aws-load-balancer-controller --region "$AWS_REGION"
```

Delete cluster:

```bash
eksctl delete cluster --name devops-launchboard-phase-8 --region "$AWS_REGION"
```

Delete ECR repositories:

```bash
aws ecr delete-repository --repository-name launchboard-backend --force --region "$AWS_REGION"
aws ecr delete-repository --repository-name launchboard-frontend --force --region "$AWS_REGION"
```

Check AWS Console for leftover:

```text
Load balancers
Target groups
EBS volumes
CloudWatch logs
NAT Gateways
Elastic IPs
```

## Security Notes

- Do not expose PostgreSQL publicly.
- Use Kubernetes Secrets for lab secrets.
- Use AWS Secrets Manager or External Secrets Operator for serious production.
- Use RDS instead of in-cluster PostgreSQL for serious production.
- Use HTTPS with ACM for public apps.
- Use least-privilege IAM.
- Keep ECR repositories private.
- Enable cluster logging.
- Clean up NAT Gateway and ALB after labs.

## Production Checklist

```text
[ ] AWS Budget created
[ ] AWS CLI installed and configured
[ ] Docker installed
[ ] kubectl installed
[ ] eksctl installed
[ ] Helm installed
[ ] Repository cloned with SSH
[ ] ECR repositories created
[ ] ECR lifecycle policies applied
[ ] Docker images built
[ ] Docker images pushed to ECR
[ ] EKS cluster created
[ ] EBS CSI add-on enabled
[ ] AWS Load Balancer Controller installed
[ ] Kubernetes Secret created
[ ] Image placeholders replaced
[ ] Kubernetes manifests applied
[ ] PostgreSQL rollout complete
[ ] Migration Job complete
[ ] Backend rollout complete
[ ] Frontend rollout complete
[ ] Ingress has ALB DNS
[ ] CORS updated to ALB DNS
[ ] Browser app works
[ ] API works
[ ] Rollback tested
[ ] Cleanup plan understood
```

## Reference Documentation

| Topic | Link |
| --- | --- |
| Amazon EKS | https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html |
| EKS Kubernetes versions | https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html |
| eksctl | https://eksctl.io/ |
| ECR | https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html |
| AWS Load Balancer Controller | https://kubernetes-sigs.github.io/aws-load-balancer-controller/ |
| EBS CSI Driver | https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html |
| kubectl | https://kubernetes.io/docs/reference/kubectl/ |
| Helm | https://helm.sh/docs/ |
| Kubernetes Ingress | https://kubernetes.io/docs/concepts/services-networking/ingress/ |

## What To Do Next

Move to:

```text
Phase 9: Observability
```

Why:

After EKS deployment, students should learn how to monitor the platform and application with metrics, logs, dashboards, and alerts.
