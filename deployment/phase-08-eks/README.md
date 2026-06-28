# Phase 8: Amazon EKS

## Fresh Start Assumption

This phase starts from a clean AWS environment and a clean Ubuntu EC2 workstation.

You do not need to complete any previous phase before using this guide.

This guide assumes:

- You have an AWS account.
- You have permission to create EKS, EC2, IAM, ECR, ALB, CloudWatch, VPC, NAT Gateway, and EBS resources.
- You have a fresh Ubuntu EC2 server for running commands.
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

- Amazon EKS cluster with a managed control plane (you never SSH into or maintain the masters).
- Managed node group with 2 worker EC2 instances.
- EKS OIDC provider for secure pod-to-AWS-service authentication.
- EBS CSI driver so Kubernetes PVCs become real EBS volumes.
- ECR repositories for backend and frontend images (private, AWS-native registry).
- AWS Load Balancer Controller that turns Kubernetes Ingress objects into real ALBs.
- PostgreSQL running inside Kubernetes (lab only; production would use RDS).
- FastAPI backend Deployment with rolling updates.
- React/Vite frontend Nginx Deployment.
- Application Load Balancer created automatically from Kubernetes Ingress.
- HPA for backend autoscaling.

Architecture:

```text
Browser
  |
  | HTTP port 80
  v
AWS Application Load Balancer (ALB)
  |
  | Target group registered by AWS Load Balancer Controller
  v
Kubernetes Ingress (ALB class)
  |
  v
launchboard-frontend Service (ClusterIP port 80)
  |
  v
Frontend Pods (Nginx on port 8080)
  |
  | /api, /health, /ready (proxied by frontend Nginx)
  v
launchboard-backend Service (ClusterIP port 8000)
  |
  v
Backend Pods (Uvicorn on port 8000)
  |
  v
launchboard-db Service (ClusterIP port 5432)
  |
  v
PostgreSQL Pod + encrypted gp3 EBS volume (via EBS CSI driver)
```

How this differs from Phase 6 kubeadm:

| Concern | Phase 6 kubeadm | Phase 8 EKS |
| --- | --- | --- |
| Control plane | You build and maintain it | AWS manages it, you never see the master nodes |
| Worker nodes | You set up each EC2 manually | eksctl creates a managed node group, AWS handles AMI updates |
| Storage | local-path provisioner (data on node disk) | EBS CSI driver (data on network-attached EBS volumes that survive node replacement) |
| Load balancer | MetalLB (software, single-node) | ALB (AWS-managed, multi-AZ, auto-scaling) |
| Ingress controller | Nginx Ingress Controller you install | AWS Load Balancer Controller creates real ALBs from Ingress resources |
| Image registry | Docker Hub (public, free) | ECR (private, AWS-native, IAM-authenticated) |
| Pod-to-AWS auth | Not applicable | OIDC + IAM Roles for Service Accounts (IRSA) |
| Networking | Flannel overlay | AWS VPC CNI (Pods get real VPC IPs) |

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

EKS is significantly more expensive than the previous phases. Before starting, understand what you will be paying for:

| Resource | Approximate Cost | Why It Exists |
| --- | --- | --- |
| EKS control plane | ~$0.10/hour (~$73/month) | The managed Kubernetes API server, etcd, scheduler, controller manager |
| 2 × t3.medium workers | ~$0.08/hour combined (~$60/month) | The EC2 instances that run your Pods |
| NAT Gateway | ~$0.045/hour + data (~$33/month) | Lets worker nodes in private subnets reach the internet (pull images, etc.) |
| Application Load Balancer | ~$0.02/hour + data (~$16/month) | Public entry point for browser traffic |
| 2 × gp3 EBS 30GB | ~$5/month each | Worker node root volumes |
| 1 × gp3 EBS 5GB | ~$0.40/month | PostgreSQL persistent volume |
| ECR storage | ~$0.10/GB/month | Docker image storage |
| CloudWatch logs | ~$0.50/GB ingested | Cluster API/audit/scheduler logs |

Running this full stack for 8 hours costs roughly $2 to $3. Running it 24/7 for a month costs roughly $180 to $200. The NAT Gateway alone accounts for about $33 of that.

Action: Create an AWS Budget before starting:

```text
AWS Console > Billing > Budgets > Create budget > Cost budget
Amount: $20 (or whatever your credit allows)
Alert at: 80%
```

After each lab session: if you are done for the day, delete the cluster with `eksctl delete cluster`. Recreating it takes 20 to 40 minutes but saves the hourly costs. The cleanup section at the end of this guide covers everything to delete.

Reference:

- AWS Budgets: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html
- EKS pricing: https://aws.amazon.com/eks/pricing/
- NAT Gateway pricing: https://aws.amazon.com/vpc/pricing/

## Recommended AWS Setup

| Item | Recommended Value |
| --- | --- |
| AWS Region | `us-east-1` or your closest region |
| EKS Cluster Name | `devops-launchboard-phase-8` |
| Kubernetes Version | `1.32` |
| Node Group | `launchboard-workers` |
| Node Type | `t3.medium` |
| Desired Nodes | `2` |
| ECR Backend Repo | `launchboard-backend` |
| ECR Frontend Repo | `launchboard-frontend` |
| Public Access | ALB only |

## Files Included In This Phase

```text
deployment/phase-08-eks/
+-- cluster/
|   +-- eksctl-cluster.yaml              (EKS cluster definition for eksctl)
+-- ecr/
|   +-- lifecycle-policy.json            (auto-expire old ECR images to control cost)
+-- k8s/
|   +-- namespace.yaml                   (Kubernetes namespace)
|   +-- storageclass.yaml                (gp3 encrypted EBS StorageClass)
|   +-- configmap.yaml                   (non-secret app configuration)
|   +-- secret.example.yaml              (example secret, never commit real values)
|   +-- pvc.yaml                         (persistent storage for PostgreSQL on EBS)
|   +-- launchboard-postgres-deployment.yaml  (PostgreSQL database Pod)
|   +-- launchboard-postgres-service.yaml     (database internal DNS)
|   +-- launchboard-migration-job.yaml        (Alembic migration runner)
|   +-- launchboard-backend-deployment.yaml   (FastAPI backend Pods)
|   +-- launchboard-backend-service.yaml      (backend internal DNS)
|   +-- launchboard-frontend-deployment.yaml  (React frontend Pods)
|   +-- launchboard-frontend-service.yaml     (frontend internal DNS)
|   +-- ingress.yaml                     (ALB Ingress for public HTTP traffic)
|   +-- hpa.yaml                         (autoscaling rules for backend)
|   +-- kustomization.yaml               (groups all manifests for one-command apply)
+-- Dockerfile.backend                   (multi-stage Docker build for FastAPI)
+-- Dockerfile.frontend                  (multi-stage Docker build for React/Vite)
+-- nginx-frontend.conf                  (Nginx config for the frontend container)
+-- README.md
```

What each file does and why it exists:

| File | What It Does | Why You Need It |
| --- | --- | --- |
| `eksctl-cluster.yaml` | Defines the EKS cluster, node group, OIDC, logging, and EBS CSI add-on | One command creates the entire infrastructure |
| `lifecycle-policy.json` | Expires old ECR images automatically | Prevents image storage costs from growing forever |
| `storageclass.yaml` | Creates a gp3 encrypted StorageClass | EKS needs to know which EBS volume type to provision for PVCs |
| `namespace.yaml` | Creates the `devops-launchboard` namespace | Isolates app resources |
| `configmap.yaml` | Non-secret environment values | Configures app without hardcoding in the image |
| `secret.example.yaml` | Example Secret structure | Reference only, real secret created with kubectl |
| `pvc.yaml` | Requests 5GB EBS volume for PostgreSQL | Data survives Pod restarts and node replacements |
| `launchboard-postgres-*` | Runs and exposes the database | Same as Phase 6, but storage is EBS instead of local disk |
| `launchboard-migration-job.yaml` | Runs Alembic migrations | Creates database tables before backend starts |
| `launchboard-backend-*` | Runs and exposes the FastAPI backend | Same as Phase 6, images from ECR instead of Docker Hub |
| `launchboard-frontend-*` | Runs and exposes the React frontend | Same as Phase 6, images from ECR |
| `ingress.yaml` | ALB Ingress with AWS annotations | AWS Load Balancer Controller reads this and creates a real ALB |
| `hpa.yaml` | Autoscaling rules for the backend | Scales backend Pods based on CPU load |
| `kustomization.yaml` | Groups all manifests | One command deploys everything |
| `Dockerfile.backend` | Multi-stage build for FastAPI | Same as Phase 6, COPY path points to phase-08-eks |
| `Dockerfile.frontend` | Multi-stage build for React | Same as Phase 6, COPY path points to phase-08-eks |
| `nginx-frontend.conf` | Nginx config for frontend | Same as Phase 6 |

## Step 1: Prepare AWS IAM User Or Role

Use an IAM principal that can create:

```text
EKS clusters
EC2 instances
VPC resources (subnets, route tables, internet gateways, NAT gateways)
IAM roles and policies
ECR repositories
CloudWatch log groups
Elastic Load Balancers
EBS volumes
CloudFormation stacks (eksctl uses CloudFormation internally)
```

If you are using the root account for a student lab, that works but is not recommended for production. For a dedicated IAM user, attach the `AdministratorAccess` policy for the lab, and scope it down later when you understand which permissions are needed.

Why this step exists:

EKS creates many AWS resources across multiple services. Missing IAM permissions are one of the most common reasons EKS setup fails. The error messages from CloudFormation are often vague ("resource creation failed"), and the real cause is buried in the IAM deny log.

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
| Key Pair | `devops-launchboard-key` |
| Security Group | SSH port 22, your IP only |

No other inbound ports are needed. This machine only makes outbound connections to AWS APIs, GitHub, and Docker registries. The application will run on EKS worker nodes, not on this workstation. 30 GB storage is needed because the Docker builds for backend and frontend images consume disk space temporarily.

Why this step exists:

This server is only the admin workstation. You run `eksctl`, `kubectl`, `docker build`, and `docker push` from here. The application runs on EKS worker nodes that eksctl creates separately.

Reference:

- AWS EC2 docs: https://docs.aws.amazon.com/ec2/

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

Expected:

```text
ubuntu
ip-...
/home/ubuntu
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

These tools let you clone the repository, install AWS tooling, edit files, and test endpoints. Same packages as every previous phase.

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

Log out and SSH back in so the docker group membership takes effect:

```bash
exit
ssh -i devops-launchboard-key.pem ubuntu@YOUR_WORKSTATION_PUBLIC_IP
```

Verify:

```bash
docker --version
docker info
```

Why this step exists:

You build the backend and frontend Docker images on this workstation and push them to ECR. Docker is not installed on the EKS worker nodes by you — they run containerd, managed by AWS.

Reference:

- Docker Engine Ubuntu install: https://docs.docker.com/engine/install/ubuntu/

## Step 6: Install AWS CLI

Run:

```bash
cd ~
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip
```

Command explanation:

- `curl ... -o "awscliv2.zip"` downloads the AWS CLI v2 installer for Linux x86_64.
- `unzip awscliv2.zip` extracts the installer into an `aws/` directory.
- `sudo ./aws/install` installs the CLI to `/usr/local/bin/aws`. It requires sudo because it writes to system directories.
- `rm -rf aws awscliv2.zip` cleans up the installer files.

Configure AWS credentials:

```bash
aws configure
```

Enter your credentials when prompted:

```text
AWS Access Key ID:     YOUR_ACCESS_KEY_ID
AWS Secret Access Key: YOUR_SECRET_ACCESS_KEY
Default region name:   YOUR_AWS_REGION (e.g. us-east-1)
Default output format: json
```

Where to get the access key: IAM Console > Users > your user > Security credentials > Create access key. For a student lab, choose the "Command Line Interface (CLI)" use case. Save both keys immediately — the secret key is shown only once.

Verify:

```bash
aws --version
aws sts get-caller-identity
```

Expected: the `get-caller-identity` output shows your account ID, user ARN, and user ID. If it fails with "Unable to locate credentials", re-run `aws configure`.

Why this step exists:

Every AWS operation in this phase (creating EKS clusters, ECR repositories, IAM roles, pushing images) goes through the AWS CLI. The credentials you configure here determine which AWS account and which permissions are used.

Reference:

- Install AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- Configure AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html

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

Command explanation:

- `kubectl` is the Kubernetes CLI, same as Phase 6. After the EKS cluster is created, `eksctl` configures kubectl to connect to it automatically.
- `eksctl` is the official CLI for creating and managing EKS clusters. It wraps CloudFormation under the hood: one `eksctl create cluster` command generates and runs multiple CloudFormation stacks that create the VPC, subnets, security groups, IAM roles, the EKS control plane, and the node group.
- `helm` is the Kubernetes package manager. You use it to install the AWS Load Balancer Controller, which is distributed as a Helm chart. A Helm chart is a bundle of Kubernetes manifests with configurable values — similar to how `apt install` installs a package with its dependencies.

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
ssh-keygen -t ed25519 -C "devops-launchboard-phase-08-eks" -f ~/.ssh/devops_launchboard_github_key
cat ~/.ssh/devops_launchboard_github_key.pub
```

Add the public key to GitHub as a read-only deploy key:

```text
GitHub repository > Settings > Deploy keys > Add deploy key
Title: devops-launchboard-phase-08-eks
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

Clone:

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

Reference:

- GitHub deploy keys: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys

## Step 9: Create Phase 8 Folders

Run:

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-08-eks/cluster
mkdir -p deployment/phase-08-eks/ecr
mkdir -p deployment/phase-08-eks/k8s
```

Why this step exists:

The phase folder keeps cluster config, image registry policy, Dockerfiles, and Kubernetes manifests together. The `cluster/` subfolder holds the eksctl config, `ecr/` holds the lifecycle policy, and `k8s/` holds the Kubernetes manifests.

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
deployment/phase-04-docker-compose/.env
```

Line explanation:

- `.git` keeps Git history out of Docker builds.
- `.github` keeps GitHub Actions workflow files out of images.
- `.venv` and `backend/.venv` keep local Python virtual environments out of images; the Dockerfile creates its own inside the build.
- `frontend/node_modules` keeps local frontend dependencies out of images; the Dockerfile's builder stage runs its own install.
- `frontend/dist` ignores any old local build output.
- `node_modules` ignores any root-level Node dependencies outside `frontend/`.
- `__pycache__`, `**/__pycache__`, and `*.pyc` ignore Python bytecode caches.
- `.pytest_cache` and `.ruff_cache` ignore test and lint caches.
- `.env` and `.env.*` keep real secret env files out of images.
- `deployment/phase-04-docker-compose/.env` ignores the real env file from the Phase 4 lab, in case a student worked through phases in order on the same checkout.

Why this file exists:

Docker should not send secrets, dependency folders, virtual environments, caches, or build output into image builds. Same file as every previous phase.

Reference:

- Docker build context: https://docs.docker.com/build/concepts/context/

## Step 11: Create EKS Cluster Config

This file is the blueprint for your entire EKS infrastructure. One `eksctl create cluster -f` command reads it and creates everything: the VPC, subnets, NAT gateway, security groups, IAM roles, the EKS control plane, the managed node group, the OIDC provider, CloudWatch logging, and the EBS CSI add-on.

```bash
vim deployment/phase-08-eks/cluster/eksctl-cluster.yaml
```

Paste:

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: devops-launchboard-phase-8
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

Replace `YOUR_AWS_REGION` in three places: `metadata.region`, and both entries under `availabilityZones`. For example, if your region is `us-east-1`:

```yaml
metadata:
  region: us-east-1
availabilityZones:
  - us-east-1a
  - us-east-1b
```

Line explanation:

- `apiVersion: eksctl.io/v1alpha5` is the eksctl config schema version.
- `kind: ClusterConfig` tells eksctl this file describes a cluster.
- `metadata.name: devops-launchboard-phase-8` names the EKS cluster. This name appears in the AWS Console, in `kubectl` contexts, and in CloudFormation stack names. eksctl creates stacks named `eksctl-devops-launchboard-phase-8-cluster` and `eksctl-devops-launchboard-phase-8-nodegroup-launchboard-workers`.
- `metadata.region` sets the AWS region where all resources are created.
- `metadata.version: "1.32"` pins the Kubernetes version. EKS supports specific versions; `1.32` is a current stable version. Quoted as a string because YAML would interpret `1.32` as a floating-point number and potentially truncate it to `1.3`.
- `availabilityZones` lists which AZs to use for the VPC subnets. Two AZs give you high availability: if one AZ has an outage, the other still runs. EKS requires at least two AZs.
- `iam.withOIDC: true` creates an OpenID Connect (OIDC) provider for the cluster. This is the foundation of IAM Roles for Service Accounts (IRSA): it lets Kubernetes service accounts assume IAM roles without storing AWS credentials in the cluster. The EBS CSI driver and the Load Balancer Controller both need this to authenticate with AWS APIs.
- `vpc.clusterEndpoints.publicAccess: true` makes the Kubernetes API server reachable from the internet. This is how your workstation runs `kubectl` commands against the cluster.
- `vpc.clusterEndpoints.privateAccess: true` makes the API server reachable from within the VPC. This is how worker nodes communicate with the API server over the private network, without going through the internet.
- `vpc.nat.gateway: Single` creates one NAT Gateway shared across AZs. Worker nodes are in private subnets (they have no public IPs), so they need the NAT Gateway to reach the internet for pulling container images from ECR and downloading updates. `Single` is cheaper than `HighlyAvailable` (which creates one NAT Gateway per AZ). For a student lab, `Single` is the right choice: it costs ~$33/month instead of ~$66/month. The tradeoff is that if the NAT Gateway's AZ goes down, worker nodes in the other AZ lose internet access until the gateway recovers.
- `managedNodeGroups` defines the worker nodes. A managed node group means AWS handles the EC2 instance lifecycle: launching, health checking, and replacing unhealthy instances.
- `instanceType: t3.medium` gives each worker 2 vCPUs and 4 GB RAM. This is the minimum for running the full stack. t3.small has only 2 GB and runs out of memory when running PostgreSQL, backend, and frontend Pods together.
- `desiredCapacity: 2` starts with 2 worker nodes.
- `minSize: 2` and `maxSize: 4` set the autoscaling boundaries for the node group. The Cluster Autoscaler (if installed) can scale between these limits.
- `privateNetworking: true` places worker nodes in private subnets. They have no public IP addresses and are not directly reachable from the internet. All inbound traffic goes through the ALB, and all outbound traffic goes through the NAT Gateway. This is the production-standard network layout.
- `volumeSize: 30` gives each worker a 30 GB root EBS volume for the OS, container images, and container logs.
- `volumeType: gp3` uses the latest general-purpose SSD type, which is cheaper and faster than gp2.
- `amiFamily: AmazonLinux2023` uses the Amazon Linux 2023 AMI optimized for EKS. It includes containerd, kubelet, and the AWS VPC CNI plugin pre-installed.
- `labels.workload: launchboard` adds a label to the nodes. You can use this in `nodeSelector` to target specific workloads at these nodes.
- `tags` add AWS resource tags for cost tracking and organization.
- `cloudWatch.clusterLogging.enableTypes` sends control plane logs to CloudWatch Logs. `api` logs API server requests. `audit` logs who did what in the cluster. `authenticator` logs authentication events. `controllerManager` and `scheduler` log their decision-making. These logs are essential for debugging cluster issues but incur CloudWatch ingestion costs.
- `addons[0].name: aws-ebs-csi-driver` installs the EBS CSI (Container Storage Interface) driver as an EKS managed add-on. This driver is what translates Kubernetes PersistentVolumeClaims into real AWS EBS volumes. Without it, PVCs requesting EBS storage stay Pending forever (the same problem Phase 6 kubeadm had without a storage provisioner).
- `wellKnownPolicies.ebsCSIController: true` tells eksctl to create an IAM role with the `AmazonEBSCSIDriverPolicy` and attach it to the EBS CSI driver's service account via IRSA. This is how the driver gets permission to create, attach, and delete EBS volumes without storing AWS credentials in the cluster.

Reference:

- eksctl ClusterConfig schema: https://eksctl.io/usage/schema/
- eksctl managed node groups: https://eksctl.io/usage/managing-nodegroups/
- EKS OIDC: https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html
- EBS CSI driver: https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html

## Step 12: Create ECR Lifecycle Policy

ECR stores your Docker images. Without a lifecycle policy, every image you push stays in the repository forever, and storage costs grow. This policy automatically expires old images.

```bash
vim deployment/phase-08-eks/ecr/lifecycle-policy.json
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

Line explanation:

- `rulePriority: 1` is evaluated first. ECR evaluates rules in priority order and applies the first matching rule to each image.
- `tagStatus: "tagged"` with `tagPrefixList: ["phase-8"]` selects images whose tags start with `phase-8` (such as `phase-8`, `phase-8-v2`, `phase-8-abc1234`).
- `countType: "imageCountMoreThan"` with `countNumber: 10` means: if there are more than 10 images matching this rule, expire the oldest ones until only 10 remain. This keeps your last 10 deployments available for rollback.
- `rulePriority: 2` catches images that have no tag (build artifacts, failed pushes). `sinceImagePushed` with `countNumber: 7` expires them after 7 days.
- `action.type: "expire"` deletes the matching images.

Reference:

- ECR lifecycle policies: https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html

## Step 13: Create Dockerfiles And Nginx Config

These are the same files from Phase 6, with one difference: the frontend Dockerfile's COPY path points to `deployment/phase-08-eks/nginx-frontend.conf`.

### Dockerfile.backend

```bash
vim deployment/phase-08-eks/Dockerfile.backend
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

- `FROM python:3.12-slim AS builder` starts the first stage of a multi-stage build. `python:3.12-slim` is a Debian-based Python image with only the minimum packages needed to run Python. `AS builder` gives this stage a name so the second stage can copy files from it. Using a named stage means the builder stage is not included in the final image.
- `ENV PYTHONDONTWRITEBYTECODE=1` tells Python not to write `.pyc` compiled bytecode files to disk, keeping the image smaller and avoiding stale cache files.
- `ENV PYTHONUNBUFFERED=1` forces Python to write output directly to stdout and stderr without buffering, so logs appear in real time in `kubectl logs`.
- `ENV VIRTUAL_ENV=/opt/venv` and `ENV PATH="/opt/venv/bin:${PATH}"` create and prioritize a virtual environment at a known path so it can be copied between stages and so `python`, `uvicorn`, and `alembic` resolve to the venv versions.
- `WORKDIR /app` sets the working directory inside the container to `/app`. All subsequent `COPY` and `RUN` commands use this as the base path.
- `RUN python -m venv /opt/venv` creates the virtual environment during the build, isolating the app's Python dependencies from the system Python.
- `COPY backend/pyproject.toml backend/alembic.ini ./` copies the dependency definition and Alembic config files before the source code. This is a Docker layer-caching trick: if these files have not changed between commits, Docker reuses the cached install layer and skips reinstalling packages.
- `COPY backend/app ./app` copies the FastAPI application source code into `/app/app`.
- `COPY backend/alembic ./alembic` copies the Alembic migration files into `/app/alembic`. The migration Job needs these files to apply database schema changes.
- `RUN pip install --no-cache-dir --upgrade pip` upgrades pip without keeping a download cache, which keeps the image smaller.
- `RUN pip install --no-cache-dir .` installs the application and its base dependencies. Alembic is one of those base dependencies (not a dev-only extra), so this single install is enough for the migration Job too.
- `FROM python:3.12-slim AS runtime` starts a completely fresh second stage. This stage becomes the final image: no build tools, no pip cache, nothing from the builder stage except what is explicitly copied.
- `RUN groupadd --system --gid 10001 app` and `useradd --system --uid 10001 --gid 10001 ...` create a non-login service user, but unlike Phase 6, they pin an explicit `--uid 10001 --gid 10001` instead of letting the system auto-assign one. A name-only `USER app` produces a non-numeric user that the kubelet cannot verify against `runAsNonRoot`, and an auto-assigned UID can also shift if the base image changes. Pinning a fixed numeric UID/GID keeps the Dockerfile and the Kubernetes `securityContext` (below) deterministic and in sync — this is the "longer-term alternative" flagged in Phase 6 Scenario 1 Step 15.8's troubleshooting note, adopted here as the default.
- `COPY --from=builder /opt/venv /opt/venv` copies the entire virtual environment from the builder stage, giving the runtime image all installed Python packages without needing pip or build tools.
- `COPY --from=builder /app /app` copies the application code from the builder stage.
- `RUN chown -R app:app /app /opt/venv` gives the non-root `app` user ownership of the app directory and virtual environment. Without this, the `app` user cannot read its own files.
- `USER app` switches from root to the `app` user for all subsequent commands. The container runs as non-root from this point forward.
- `EXPOSE 8000` documents that the container listens on port 8000. This is metadata for humans and tools, not an actual port-opening action.
- `HEALTHCHECK` runs a Python request against `/health` every 30 seconds. If it fails 3 times in a row, the container is marked unhealthy.
- `CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]` starts Uvicorn listening on all interfaces. `--proxy-headers` makes Uvicorn trust the `X-Forwarded-*` headers added by the ALB and the frontend Nginx in front of it.

Reference:

- Dockerfile reference: https://docs.docker.com/reference/dockerfile/
- Multi-stage builds: https://docs.docker.com/build/building/multi-stage/

### Dockerfile.frontend

```bash
vim deployment/phase-08-eks/Dockerfile.frontend
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

COPY deployment/phase-08-eks/nginx-frontend.conf /etc/nginx/conf.d/default.conf
COPY --from=builder --chown=101:101 /app/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

Line explanation:

- `FROM node:22-alpine AS builder` uses the official Node.js 22 image based on Alpine Linux to build the React app. This stage is not included in the final image.
- `WORKDIR /app` sets the working directory inside the build container.
- `ARG VITE_API_URL=""` declares a build argument with a default empty value, passed in at build time with `--build-arg`. Vite reads this during the build to know the API base URL.
- `ENV VITE_API_URL=${VITE_API_URL}` transfers the build argument into an environment variable so Vite can embed it into the compiled JavaScript at build time. Left empty here because the frontend uses relative `/api` paths, which the Nginx config proxies.
- `COPY frontend/package*.json ./` followed by `RUN npm ci` copies the lockfile before the source code, so an unchanged lockfile reuses the cached install layer. `npm ci` installs exact versions from `package-lock.json` for reproducible builds.
- `COPY frontend/ ./` copies the rest of the frontend source code.
- `RUN npm run build` compiles the React app into static files in `/app/dist`.
- `FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime` starts the final stage using the official unprivileged Nginx image, which runs without root privileges on port 8080 instead of 80. Node.js does not appear in the final image at all.
- `COPY deployment/phase-08-eks/nginx-frontend.conf /etc/nginx/conf.d/default.conf` installs the custom config from the Phase 8 folder. This is the one line that differs from Phase 6, which copied from the phase-6 folder; if you copy this Dockerfile from Phase 6, update this line or the build fails at the COPY step.
- `COPY --from=builder --chown=101:101 /app/dist /usr/share/nginx/html` copies the compiled frontend into the web root, owned by UID/GID 101, the nginx user in the unprivileged image. Without `--chown`, Nginx cannot read the files.
- `EXPOSE 8080` documents the port. The unprivileged image uses 8080 because non-root users cannot bind to ports below 1024.
- `HEALTHCHECK` runs `wget -qO- http://127.0.0.1:8080/healthz` to confirm Nginx is serving.
- `CMD ["nginx", "-g", "daemon off;"]` keeps Nginx in the foreground so Docker does not think the process exited.

Reference:

- Vite environment variables: https://vite.dev/guide/env-and-mode
- Nginx unprivileged image: https://hub.docker.com/r/nginxinc/nginx-unprivileged

### nginx-frontend.conf

```bash
vim deployment/phase-08-eks/nginx-frontend.conf
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

- `listen 8080` tells Nginx to listen on port 8080 inside the container. The unprivileged image cannot use port 80 because ports below 1024 require root.
- `server_name _` is a catch-all that matches any hostname.
- `root /usr/share/nginx/html` and `index index.html` point Nginx at the compiled React files and the default file to serve for directory requests.
- `client_max_body_size 10M` allows request bodies up to 10 MB, in case the app allows file uploads through the API.
- `location = /healthz` exact-matches the health check path, disables access logging for it, and returns a plain `200 ok` — this is what the ALB target group and the Kubernetes probes check.
- `location /api/`, `location = /health`, and `location = /ready` proxy those paths to `http://launchboard-backend:8000/...`. `launchboard-backend` is the Kubernetes Service DNS name; inside the cluster, Kubernetes DNS resolves it to the backend Service's ClusterIP. The `proxy_set_header` lines forward the original Host, client IP, and protocol to the backend.
- `location / { try_files $uri $uri/ /index.html; }` falls back to `index.html` for any path that does not match a real file. This is required for React Router: navigating directly to a route like `/dashboard` has no matching file, so Nginx serves `index.html` and React Router renders the right page client-side.

Reference:

- Nginx server block documentation: https://nginx.org/en/docs/http/ngx_http_core_module.html
- Nginx proxy module: https://nginx.org/en/docs/http/ngx_http_proxy_module.html

## Step 14: Create Kubernetes Manifests

All manifests go inside `deployment/phase-08-eks/k8s/`. These are similar to the Phase 6 kubeadm manifests with key differences for EKS: images come from ECR, storage uses the gp3 EBS StorageClass, and the Ingress uses ALB annotations instead of Nginx Ingress.

Important: three placeholders appear throughout the manifests. Replace them before applying:

| Placeholder | Where To Find The Real Value | Example |
| --- | --- | --- |
| `YOUR_ACCOUNT_ID` | `aws sts get-caller-identity --query Account --output text` | `123456789012` |
| `YOUR_AWS_REGION` | The region you chose in Step 11 | `us-east-1` |
| `YOUR_ALB_DNS_NAME` | `kubectl get ingress` after applying (Step 22) | `k8s-devopsla-launchbo-abc123.us-east-1.elb.amazonaws.com` |

Move to the project root:

```bash
cd /opt/devops-launchboard/app-source
```

### namespace.yaml

```bash
vim deployment/phase-08-eks/k8s/namespace.yaml
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

Line explanation:

- `apiVersion: v1` and `kind: Namespace` use the core Kubernetes API. Namespaces, Services, ConfigMaps, Secrets, and PersistentVolumeClaims all use `v1`.
- `metadata.name: devops-launchboard` is the name of the namespace. Every other resource in this phase sets `namespace: devops-launchboard` to belong to it, isolating these resources from system namespaces like `kube-system`.
- `app.kubernetes.io/name` and `app.kubernetes.io/part-of` are standardized Kubernetes labels that make these resources compatible with dashboards and monitoring tools that look for them.

Reference:

- Kubernetes Namespaces: https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/

### storageclass.yaml

This file does not exist in Phase 6. It is EKS-specific.

```bash
vim deployment/phase-08-eks/k8s/storageclass.yaml
```

Paste:

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

Line explanation:

- `apiVersion: storage.k8s.io/v1` uses the storage API group.
- `kind: StorageClass` defines a class of storage that PVCs can request. Different classes can offer different performance, encryption, or cost characteristics.
- `metadata.name: gp3` names this class. The PVC references this name in its `storageClassName` field.
- `provisioner: ebs.csi.aws.com` tells Kubernetes which CSI driver handles storage requests for this class. This is the AWS EBS CSI driver installed as an EKS add-on in Step 11.
- `parameters.type: gp3` creates gp3 EBS volumes. gp3 is the current-generation general-purpose SSD type. It is cheaper than gp2 and provides a baseline of 3,000 IOPS and 125 MB/s throughput included in the price.
- `parameters.encrypted: "true"` enables EBS encryption at rest using the default AWS KMS key. Every byte written to the volume is encrypted transparently. This is a production best practice and costs nothing extra.
- `volumeBindingMode: WaitForFirstConsumer` delays volume creation until a Pod using the PVC is scheduled. This ensures the EBS volume is created in the same Availability Zone as the Pod's node. Without this, the volume might be created in AZ-a while the Pod lands on a node in AZ-b, and the Pod would be stuck Pending because EBS volumes cannot cross AZs.
- `allowVolumeExpansion: true` lets you increase the PVC size later without recreating it. You edit the PVC spec to request more storage, and the CSI driver expands the underlying EBS volume.

Why this file is EKS-specific:

In Phase 6 with Kind, the local-path provisioner automatically created volumes from the node's local disk. In Phase 6 kubeadm, the Rancher local-path provisioner did the same. On EKS, storage is network-attached EBS volumes managed by the EBS CSI driver. This StorageClass tells the driver what type of volume to create. The key advantage over local storage: an EBS volume survives node replacement. If a worker node is terminated and replaced by the node group, the EBS volume is re-attached to the new node, and your database data is intact.

Reference:

- StorageClass: https://kubernetes.io/docs/concepts/storage/storage-classes/
- EBS CSI StorageClass parameters: https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/docs/parameters.md
- gp3 volumes: https://docs.aws.amazon.com/ebs/latest/userguide/general-purpose.html

### configmap.yaml

```bash
vim deployment/phase-08-eks/k8s/configmap.yaml
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
  CORS_ORIGINS: http://YOUR_ALB_DNS_NAME
  SEED_DEMO_DATA: "true"
  POSTGRES_DB: launchboard
  POSTGRES_USER: launchboard_user
```

Line explanation:

- `CORS_ORIGINS` is set to a placeholder because you do not know the ALB DNS name until AWS creates the load balancer in Step 22. You will update this value after the ALB is created in Step 23. This tells the FastAPI backend which browser origin is allowed to call the API; if it does not match the URL you open in the browser, the browser blocks the API responses.
- `APP_NAME` is the display name read by the backend.
- `APP_ENV: production` affects logging behavior and error responses.
- `SEED_DEMO_DATA: "true"` tells the backend to insert sample data on first run so the dashboard is not empty.
- `POSTGRES_DB` and `POSTGRES_USER` are the database name and username the backend connects with; the password comes from the Secret, not the ConfigMap.

Reference:

- Kubernetes ConfigMaps: https://kubernetes.io/docs/concepts/configuration/configmap/

### secret.example.yaml

```bash
vim deployment/phase-08-eks/k8s/secret.example.yaml
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

Line explanation:

- `type: Opaque` means this is a generic secret with no special structure, the right type for application credentials.
- `stringData` lets you write plain text values; Kubernetes base64-encodes them automatically when storing.
- `POSTGRES_PASSWORD` is the PostgreSQL superuser password. `DATABASE_URL` is the full async connection string the FastAPI backend uses; `launchboard-db` is the Service DNS name, and the password here must exactly match `POSTGRES_PASSWORD`.

This file has placeholder values only. Never commit real credentials. The real Secret is created with `kubectl create secret` in Step 19.

Reference:

- Kubernetes Secrets: https://kubernetes.io/docs/concepts/configuration/secret/

### pvc.yaml

```bash
vim deployment/phase-08-eks/k8s/pvc.yaml
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
  storageClassName: gp3
  resources:
    requests:
      storage: 10Gi
```

Line explanation:

- `storageClassName: gp3` references the StorageClass you created above. This is the line that connects the PVC to the EBS CSI driver. When a Pod using this PVC is scheduled, the driver creates a 10 GB gp3 encrypted EBS volume in the same AZ as the node, attaches it, and mounts it at the path specified in the Deployment.
- `accessModes: ReadWriteOnce` means one node can mount the volume for read-write. This is the only access mode EBS supports.
- `storage: 10Gi` requests 10 gibibytes. The EBS volume is exactly this size. Unlike local-path storage where the limit is informational, EBS enforces the size at the block device level.

How this differs from Phase 6:

In Phase 6, the PVC had no `storageClassName` and relied on the cluster's default StorageClass. Here you name the class explicitly (`gp3`) to make the intent clear and to ensure the encrypted gp3 type is used even if the cluster's default class changes.

Reference:

- PersistentVolumeClaims: https://kubernetes.io/docs/concepts/storage/persistent-volumes/#persistentvolumeclaims
- EBS CSI dynamic provisioning: https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html

### launchboard-postgres-deployment.yaml

```bash
vim deployment/phase-08-eks/k8s/launchboard-postgres-deployment.yaml
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

Line explanation:

- `spec.replicas: 1` runs a single PostgreSQL Pod. Running more than one replica of a single-writer database without a replication setup would cause data corruption, so this is intentionally not scaled like the backend or frontend.
- `spec.strategy.type: Recreate` terminates the existing Pod completely before creating a new one. This is required for the database: `RollingUpdate` would briefly run two Pods against the same EBS volume, and EBS only supports `ReadWriteOnce`, so the second Pod could not even mount it.
- `image: postgres:16-alpine` comes from Docker Hub (public), not ECR, because it is an official upstream image you do not build. EKS worker nodes can pull public images through the NAT Gateway.
- `env` reads `POSTGRES_DB` and `POSTGRES_USER` from the ConfigMap and `POSTGRES_PASSWORD` from the Secret, which is how the official Postgres image's entrypoint script creates the database and user on first start.
- `volumeMounts` mounts the `postgres-data` volume at `/var/lib/postgresql/data`, which is where PostgreSQL stores its files.
- `readinessProbe`/`livenessProbe` both run `pg_isready` inside the container to check PostgreSQL is accepting connections, rather than an HTTP check.
- `resources` gives the database more memory than the backend or frontend (`256Mi` request, `512Mi` limit), since PostgreSQL benefits from more memory for caching.
- `volumes[0].persistentVolumeClaim.claimName: launchboard-postgres-pvc` binds this Pod to the PVC created earlier.

The key difference from Phase 6 is invisible in this manifest: the PVC now creates a real EBS volume via the `gp3` StorageClass. If the worker node running this Pod is terminated by the node group, AWS creates a new node, the EBS CSI driver re-attaches the same volume, and PostgreSQL starts with its data intact. This could not happen with local-path storage.

Reference:

- Kubernetes Deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/

### launchboard-postgres-service.yaml

```bash
vim deployment/phase-08-eks/k8s/launchboard-postgres-service.yaml
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

Line explanation:

- `metadata.name: launchboard-db` becomes the DNS entry inside the cluster. Any Pod in the `devops-launchboard` namespace can reach the database at `launchboard-db:5432`; the `DATABASE_URL` in the Secret uses this exact name.
- `spec.type: ClusterIP` creates an internal-only Service with no external access, keeping the database private.
- `spec.selector.app: launchboard-db` routes traffic to Pods carrying that label.
- `ports[0].port` and `ports[0].targetPort` are both `5432` because PostgreSQL listens on 5432 inside the container.

Reference:

- Kubernetes Services: https://kubernetes.io/docs/concepts/services-networking/service/

### launchboard-migration-job.yaml

```bash
vim deployment/phase-08-eks/k8s/launchboard-migration-job.yaml
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
          image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-backend:phase-8
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

Line explanation:

- `apiVersion: batch/v1` and `kind: Job` create a one-time task: unlike a Deployment, a Job runs its Pod to completion and then stops, instead of keeping it running forever.
- `spec.backoffLimit: 3` retries the Job up to 3 times if it fails before Kubernetes marks it failed and stops retrying, preventing an infinite retry loop on a permanent migration error.
- `spec.template.spec.restartPolicy: OnFailure` restarts the container only on failure, not on success — Jobs cannot use `Always`, which would restart even after a successful run.
- `image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-backend:phase-8` pulls from your private ECR repository. Replace both placeholders. Example: `123456789012.dkr.ecr.us-east-1.amazonaws.com/launchboard-backend:phase-8`. The migration Job reuses the backend image because Alembic is already installed in it.
- `imagePullPolicy: IfNotPresent` skips re-pulling if the node already has this exact tag cached, fine here since this phase pushes one image per build with a static `phase-8` tag rather than a unique tag per push. EKS worker nodes authenticate to ECR using temporary IAM credentials that the kubelet refreshes automatically (via the `ecr-credential-provider` built into the EKS-optimized AMI), so no `imagePullSecret` is needed for ECR in the same account.
- `command` overrides the Dockerfile's `CMD` for this Job. The `until python -c "import socket; ..."` loop tries a TCP connection to `launchboard-db:5432` every 2 seconds until PostgreSQL accepts it, preventing Alembic from running before the database is ready.
- `alembic upgrade head` applies all pending migrations up to the latest version.
- `envFrom` loads every key from the ConfigMap and the Secret as environment variables; Alembic reads `DATABASE_URL` from the Secret to know which database to connect to.
- `resources.requests`/`resources.limits` are smaller than the main backend because migrations run briefly and do not need much compute.

Reference:

- Kubernetes Jobs: https://kubernetes.io/docs/concepts/workloads/controllers/job/

### launchboard-backend-deployment.yaml

```bash
vim deployment/phase-08-eks/k8s/launchboard-backend-deployment.yaml
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
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: backend
          image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-backend:phase-8
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

- `spec.replicas: 2` runs two backend Pods so one keeps serving traffic while the other is restarted or updated.
- `spec.strategy.type: RollingUpdate` with `maxSurge: 1` and `maxUnavailable: 0` updates Pods gradually with zero downtime: one extra Pod can exist during a rollout, but Kubernetes never removes an old Pod until its replacement is ready.
- `runAsUser: 10001` and `runAsGroup: 10001` are required because the Dockerfile uses `USER app` (a name), and the kubelet can only verify numeric UIDs. They must match the `--uid 10001 --gid 10001` pinned in the Dockerfile, or the Pod fails with `CreateContainerConfigError`. See Phase 6 Scenario 1 section 15.8 for the background on this error.
- `fsGroup: 10001` sets the GID that owns any mounted volumes, so the `app` user can read and write them.
- `seccompProfile.type: RuntimeDefault` applies the container runtime's default seccomp profile, blocking dangerous syscalls while allowing everything the app needs — a separate protection layer from the UID checks above.
- `image` points to ECR. Replace the two placeholders. `imagePullPolicy: IfNotPresent` is fine here for the same static-tag reasoning as the migration Job.
- `command` waits for PostgreSQL to accept connections, then uses `exec` to replace the shell with Uvicorn so it becomes PID 1 and receives termination signals directly — this is what makes `kubectl rollout` and graceful shutdowns work correctly.
- `envFrom` loads the ConfigMap and Secret as environment variables.
- `readinessProbe` checks `/ready` (typically database connectivity) before the Pod receives traffic; `livenessProbe` checks `/health` and restarts the container if it fails.
- `resources.requests`/`resources.limits` cap the backend at modest CPU and memory, appropriate for a student lab on small worker nodes.

Reference:

- Kubernetes Deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
- Pod security context: https://kubernetes.io/docs/tasks/configure-pod-container/security-context/

### launchboard-backend-service.yaml

```bash
vim deployment/phase-08-eks/k8s/launchboard-backend-service.yaml
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

Line explanation:

- `metadata.name: launchboard-backend` becomes the DNS name the frontend Nginx config proxies to (`http://launchboard-backend:8000/api/`).
- `spec.type: ClusterIP` keeps the backend internal; all public traffic goes through the frontend and the ALB.
- `spec.selector.app: launchboard-backend` routes traffic only to healthy backend Pods.
- `ports[0].port`/`targetPort` are both `8000`, matching the container port.

Reference:

- Kubernetes Services: https://kubernetes.io/docs/concepts/services-networking/service/

### launchboard-frontend-deployment.yaml

```bash
vim deployment/phase-08-eks/k8s/launchboard-frontend-deployment.yaml
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
          image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-frontend:phase-8
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

- `spec.replicas: 2` runs two frontend Pods for the same availability reasons as the backend.
- `securityContext.runAsNonRoot: true` plus `runAsUser: 101` and `runAsGroup: 101` set the process to the nginx user/group baked into the `nginxinc/nginx-unprivileged` image. `fsGroup: 101` gives that user ownership of any mounted volumes.
- `image` points to ECR. Replace the two placeholders.
- `containerPort: 8080` documents that the unprivileged image listens on 8080, not 80, since non-root processes cannot bind to ports below 1024.
- `readinessProbe`/`livenessProbe` both check `/healthz`, the static health endpoint defined in the Nginx config.
- `resources.requests`/`resources.limits` are low because the frontend only serves static files.

Reference:

- Kubernetes Deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/

### launchboard-frontend-service.yaml

```bash
vim deployment/phase-08-eks/k8s/launchboard-frontend-service.yaml
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

Line explanation:

- `metadata.name: launchboard-frontend` becomes the DNS name the Ingress's backend Service reference uses.
- `spec.type: ClusterIP` keeps the Service internal; the Ingress/ALB routes external traffic to it.
- `ports[0].port: 80` is what the Ingress targets; `targetPort: 8080` is the actual Pod port. The Service translates between the two so external traffic can use the standard port 80 while the container keeps its non-root port.

Reference:

- Kubernetes Services: https://kubernetes.io/docs/concepts/services-networking/service/

### ingress.yaml

This is the file that differs most from Phase 6. In Phase 6, the Ingress was handled by the Nginx Ingress Controller. Here, the AWS Load Balancer Controller reads the Ingress and creates a real AWS Application Load Balancer.

```bash
vim deployment/phase-08-eks/k8s/ingress.yaml
```

Paste:

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
    alb.ingress.kubernetes.io/load-balancer-name: launchboard-phase-8
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

Line explanation:

- `spec.ingressClassName: alb` tells the AWS Load Balancer Controller to handle this Ingress. This is the modern equivalent of `ingressClassName: nginx` in Phase 6 — it determines which controller acts on the resource. The ALB controller ignores Ingresses that do not name it.
- `alb.ingress.kubernetes.io/scheme: internet-facing` creates a public ALB. The alternative, `internal`, creates an ALB accessible only from within the VPC.
- `alb.ingress.kubernetes.io/target-type: ip` tells the ALB to send traffic directly to the Pod IPs. This works because EKS uses the AWS VPC CNI plugin, which assigns real VPC IP addresses to each Pod (unlike Flannel in Phase 6, which assigns overlay IPs). The alternative, `instance`, sends traffic to the NodePort on each worker node, which adds an extra network hop. `ip` mode is more efficient and is the recommended setting for EKS.
- `alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'` configures the ALB listener on port 80. To add HTTPS, you would add `{"HTTPS":443}` and a certificate ARN annotation.
- `alb.ingress.kubernetes.io/healthcheck-path: /healthz` tells the ALB which path to probe to determine if a target (Pod) is healthy. This is the ALB's own health check, separate from the Kubernetes readiness probe. The ALB sends HTTP requests to this path and expects a 200 response.
- `alb.ingress.kubernetes.io/load-balancer-name: launchboard-phase-8` gives the ALB a predictable name in the EC2 Console instead of an auto-generated one, useful when several phases' ALBs exist in the same account at once.
- `spec.rules` routes all traffic to the frontend Service, same as Phase 6. The frontend's Nginx then proxies `/api`, `/health`, and `/ready` to the backend.

What happens when you apply this:

1. The AWS Load Balancer Controller sees the new Ingress with `ingress.class: alb`.
2. It calls the AWS APIs to create an Application Load Balancer, a target group, and a listener.
3. It registers the frontend Pod IPs as targets in the target group (because `target-type: ip`).
4. AWS assigns the ALB a DNS name like `k8s-devopsla-launchbo-abc123.us-east-1.elb.amazonaws.com`.
5. The DNS name appears in `kubectl get ingress` under the `ADDRESS` column after 2 to 5 minutes.
6. Browser traffic to that DNS name reaches the ALB, which forwards it to a healthy frontend Pod.

Reference:

- AWS Load Balancer Controller Ingress annotations: https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/annotations/
- ALB target types: https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/annotations/#target-type

### hpa.yaml

```bash
vim deployment/phase-08-eks/k8s/hpa.yaml
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

Line explanation:

- `apiVersion: autoscaling/v2` supports multiple metric types (CPU, memory, custom metrics); the older `v1` only supported CPU.
- `spec.scaleTargetRef` points the HPA at the `launchboard-backend` Deployment.
- `minReplicas: 2` / `maxReplicas: 5` bound the autoscaler: it never goes below 2 Pods or above 5, no matter how low or high CPU usage gets.
- `metrics[0].resource.name: cpu` with `target.type: Utilization` and `averageUtilization: 70` means: if average CPU usage across backend Pods exceeds 70% of their requested CPU, scale up; if it drops well below that, scale down.

EKS includes the Metrics Server by default, so unlike the kubeadm scenario in Phase 6 — where HPA had to wait until Metrics Server was installed separately — this HPA is applied and usable immediately, with no extra installation step.

Reference:

- Horizontal Pod Autoscaler: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/

### kustomization.yaml

```bash
vim deployment/phase-08-eks/k8s/kustomization.yaml
```

Paste:

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

- `storageclass.yaml` is listed because EKS does not ship with a gp3 StorageClass by default.
- `secret.example.yaml` is not listed; the real Secret is created with `kubectl create secret`.
- `hpa.yaml` is included because EKS has Metrics Server built in, unlike kubeadm.

## Step 15: Create ECR Repositories

Set variables that you will reuse throughout the rest of this guide:

```bash
export AWS_REGION=YOUR_AWS_REGION
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account: $ACCOUNT_ID  Region: $AWS_REGION"
```

Create the two repositories:

```bash
aws ecr create-repository --repository-name launchboard-backend --region "$AWS_REGION"
aws ecr create-repository --repository-name launchboard-frontend --region "$AWS_REGION"
```

Apply the lifecycle policy to both:

```bash
aws ecr put-lifecycle-policy \
  --repository-name launchboard-backend \
  --lifecycle-policy-text file://deployment/phase-08-eks/ecr/lifecycle-policy.json \
  --region "$AWS_REGION"

aws ecr put-lifecycle-policy \
  --repository-name launchboard-frontend \
  --lifecycle-policy-text file://deployment/phase-08-eks/ecr/lifecycle-policy.json \
  --region "$AWS_REGION"
```

Verify:

```bash
aws ecr describe-repositories --region "$AWS_REGION" --query 'repositories[*].[repositoryName,repositoryUri]' --output table
```

Command explanation:

- `aws ecr create-repository` creates a private ECR repository. Private means only IAM principals in your account (or those you explicitly grant access) can push and pull images.
- `--repository-name launchboard-backend` names the repository. The full image URL becomes `ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/launchboard-backend:TAG`.
- `aws ecr put-lifecycle-policy` attaches the policy from Step 12 that auto-expires old images.
- The `--query` flag on describe uses JMESPath to extract just the name and URI, making the output readable.

Why ECR instead of Docker Hub:

ECR is the AWS-native registry. EKS worker nodes authenticate to ECR automatically using IAM (no `imagePullSecret` needed). Images stay in your AWS account and region, so pulls are fast and free (no cross-region data transfer). Docker Hub has rate limits on free accounts (100 pulls per 6 hours); ECR has no pull limit within the same account.

Reference:

- Amazon ECR: https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html
- ECR private repositories: https://docs.aws.amazon.com/AmazonECR/latest/userguide/Repositories.html

## Step 16: Build And Push Images To ECR

Log in to ECR:

```bash
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
```

Command explanation:

- `aws ecr get-login-password` generates a temporary 12-hour authentication token for ECR. This is an AWS API call that uses your configured IAM credentials.
- `docker login --username AWS --password-stdin` authenticates Docker with the ECR registry. The username is always `AWS` for ECR. The token is piped via `--password-stdin` so it does not appear in your shell history.
- After login, `docker push` commands targeting this registry work for 12 hours.

Build images:

```bash
cd /opt/devops-launchboard/app-source

docker build -f deployment/phase-08-eks/Dockerfile.backend \
  -t launchboard-backend:phase-8 .

docker build -f deployment/phase-08-eks/Dockerfile.frontend \
  --build-arg VITE_API_URL= \
  -t launchboard-frontend:phase-8 .
```

Tag images for ECR:

```bash
docker tag launchboard-backend:phase-8 \
  "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-8"

docker tag launchboard-frontend:phase-8 \
  "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-frontend:phase-8"
```

Push images:

```bash
docker push "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-8"
docker push "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-frontend:phase-8"
```

Verify:

```bash
aws ecr describe-images --repository-name launchboard-backend --region "$AWS_REGION" \
  --query 'imageDetails[*].[imageTags,imageSizeInBytes]' --output table
aws ecr describe-images --repository-name launchboard-frontend --region "$AWS_REGION" \
  --query 'imageDetails[*].[imageTags,imageSizeInBytes]' --output table
```

Command explanation:

- `docker build` compiles the images locally on the workstation. The commands are the same as Phase 6 — only the `-f` path changes.
- `docker tag` creates an additional name for the same image. Docker requires the full registry URL in the tag for `docker push` to know where to send it. The format `ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/REPO:TAG` is the standard ECR image reference.
- `docker push` uploads the image layers to ECR. On the first push, all layers are uploaded. On subsequent pushes, Docker only uploads layers that changed, which makes rebuilds after small code changes very fast.

Reference:

- Push images to ECR: https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html

## Step 17: Create EKS Cluster

This is the longest step. eksctl creates the VPC, subnets, NAT gateway, security groups, IAM roles, the EKS control plane, the managed node group, the OIDC provider, and the EBS CSI add-on. It takes 20 to 40 minutes.

Run:

```bash
cd /opt/devops-launchboard/app-source
eksctl create cluster -f deployment/phase-08-eks/cluster/eksctl-cluster.yaml
```

What happens during this command (watch the output):

```text
1. eksctl creates a CloudFormation stack for the VPC and networking (~5 min)
2. eksctl creates the EKS control plane (~10-15 min)
3. eksctl creates the OIDC provider
4. eksctl creates a CloudFormation stack for the node group (~5-10 min)
5. eksctl installs the EBS CSI driver add-on
6. eksctl writes the kubeconfig to ~/.kube/config
```

After completion, verify:

```bash
kubectl get nodes
kubectl get pods -A
```

Expected:

```text
NAME                                STATUS   ROLES    AGE   VERSION
ip-192-168-X-X.ec2.internal        Ready    <none>   5m    v1.32.x
ip-192-168-X-X.ec2.internal        Ready    <none>   5m    v1.32.x
```

```bash
kubectl get storageclass
```

You should see at least `gp2 (default)`. Your `gp3` class will be created when you apply the manifests.

```bash
kubectl get pods -n kube-system | grep ebs
```

Expected: `ebs-csi-controller` and `ebs-csi-node` Pods running. These are the EBS CSI driver components installed by the add-on.

If the cluster creation fails: check `eksctl utils describe-stacks --region $AWS_REGION --cluster devops-launchboard-phase-8`. The CloudFormation events tell you the real reason (usually a permissions or quota issue).

Reference:

- eksctl create cluster: https://eksctl.io/usage/creating-and-managing-clusters/
- EKS getting started: https://docs.aws.amazon.com/eks/latest/userguide/getting-started-eksctl.html

## Step 18: Install AWS Load Balancer Controller

The AWS Load Balancer Controller is a Kubernetes controller that watches for Ingress resources with the `alb` class and creates real AWS Application Load Balancers. Without it, the Ingress resource you created in Step 14 does nothing.

Set variables:

```bash
export CLUSTER_NAME=devops-launchboard-phase-8
export AWS_REGION=YOUR_AWS_REGION
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

Download the IAM policy that the controller needs:

```bash
cd ~
curl -o aws-load-balancer-controller-policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
```

Create the IAM policy in your account:

```bash
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://aws-load-balancer-controller-policy.json
```

If the policy already exists from a previous attempt, this command prints an error. That is fine; the existing policy is used.

Create an IAM service account for the controller using IRSA:

```bash
eksctl create iamserviceaccount \
  --cluster "$CLUSTER_NAME" \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy" \
  --approve \
  --region "$AWS_REGION"
```

Command explanation:

- `eksctl create iamserviceaccount` creates three things: an IAM role with the specified policy, a Kubernetes ServiceAccount in `kube-system`, and a trust relationship between them via the cluster's OIDC provider.
- When the Load Balancer Controller Pod runs with this ServiceAccount, the AWS SDK inside it automatically receives temporary credentials for the IAM role, without any access keys stored in the cluster. This is IRSA (IAM Roles for Service Accounts) — the recommended way for Pods to access AWS APIs.
- `--approve` skips the confirmation prompt.

Install the controller with Helm:

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

Command explanation:

- `helm repo add eks` adds the AWS EKS Helm chart repository.
- `helm install` deploys the controller. `--set serviceAccount.create=false` tells Helm not to create a ServiceAccount because `eksctl create iamserviceaccount` already created one with the IAM role attached. `--set serviceAccount.name=aws-load-balancer-controller` tells the controller to use that existing ServiceAccount.

Verify:

```bash
kubectl -n kube-system rollout status deployment/aws-load-balancer-controller
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-load-balancer-controller
```

Expected: 2 controller Pods running.

Reference:

- AWS Load Balancer Controller installation: https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/
- IRSA: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html

## Step 19: Create Kubernetes Secret

Apply the namespace first:

```bash
kubectl apply -f deployment/phase-08-eks/k8s/namespace.yaml
```

Create the Secret:

```bash
kubectl create secret generic launchboard-secret \
  --namespace devops-launchboard \
  --from-literal=POSTGRES_PASSWORD='CHANGE_ME_STRONG_PASSWORD' \
  --from-literal=DATABASE_URL='postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@launchboard-db:5432/launchboard'
```

Use the same password in both values. Choose a stronger password than the placeholder.

## Step 20: Replace Image Placeholders In Manifests

Open these three files and replace `YOUR_ACCOUNT_ID` and `YOUR_AWS_REGION` with the real values:

```bash
vim deployment/phase-08-eks/k8s/launchboard-backend-deployment.yaml
vim deployment/phase-08-eks/k8s/launchboard-migration-job.yaml
vim deployment/phase-08-eks/k8s/launchboard-frontend-deployment.yaml
```

You can verify your values:

```bash
echo "Account: $ACCOUNT_ID  Region: $AWS_REGION"
```

The image lines should look like (example):

```text
image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/launchboard-backend:phase-8
image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/launchboard-frontend:phase-8
```

Or, to replace all placeholders in one command (optional, if you prefer sed over vim):

```bash
cd /opt/devops-launchboard/app-source
sed -i "s|YOUR_ACCOUNT_ID|${ACCOUNT_ID}|g; s|YOUR_AWS_REGION|${AWS_REGION}|g" \
  deployment/phase-08-eks/k8s/launchboard-backend-deployment.yaml \
  deployment/phase-08-eks/k8s/launchboard-migration-job.yaml \
  deployment/phase-08-eks/k8s/launchboard-frontend-deployment.yaml
```

Verify the substitution:

```bash
grep "image:" deployment/phase-08-eks/k8s/launchboard-backend-deployment.yaml
grep "image:" deployment/phase-08-eks/k8s/launchboard-migration-job.yaml
grep "image:" deployment/phase-08-eks/k8s/launchboard-frontend-deployment.yaml
```

None of the output lines should contain `YOUR_ACCOUNT_ID` or `YOUR_AWS_REGION`.

## Step 21: Apply Kubernetes Manifests

```bash
cd /opt/devops-launchboard/app-source
kubectl apply -k deployment/phase-08-eks/k8s
```

Wait for each component in order:

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

Expected: PVC `Bound`, all Pods `Running`, migration Job `Completed`, Ingress shows an `ADDRESS` after 2 to 5 minutes.

If the PVC is Pending: check that the EBS CSI driver is running (`kubectl get pods -n kube-system | grep ebs`), and that the StorageClass was created (`kubectl get sc gp3`).

If Pods show ImagePullBackOff: check that the image URLs in the manifests match exactly what you pushed to ECR (`aws ecr describe-images --repository-name launchboard-backend --region $AWS_REGION`).

## Step 22: Get ALB URL

```bash
kubectl -n devops-launchboard get ingress launchboard-ingress
```

It takes 2 to 5 minutes for AWS to provision the ALB and assign a DNS name. Re-run the command until the `ADDRESS` column shows a value like:

```text
k8s-devopsla-launchbo-abc123def4-567890123.us-east-1.elb.amazonaws.com
```

Test from the workstation:

```bash
curl -I http://$(kubectl -n devops-launchboard get ingress launchboard-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
```

If this returns `HTTP/1.1 200` or `HTTP/1.1 302`, the ALB is working.

If the Ingress has no address after 5 minutes: check the Load Balancer Controller logs (`kubectl -n kube-system logs deployment/aws-load-balancer-controller --tail=50`). Common causes: missing subnet tags (`kubernetes.io/role/elb: 1` on public subnets), missing controller IAM permissions, or security group issues.

## Step 23: Update CORS To ALB DNS

Now that you know the ALB DNS name, update the ConfigMap:

```bash
ALB_DNS=$(kubectl -n devops-launchboard get ingress launchboard-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB DNS: $ALB_DNS"
```

Edit the ConfigMap:

```bash
vim deployment/phase-08-eks/k8s/configmap.yaml
```

Replace the CORS_ORIGINS line:

```yaml
  CORS_ORIGINS: http://YOUR_ALB_DNS_NAME
```

with the actual ALB DNS name (include `http://`, no trailing slash):

```yaml
  CORS_ORIGINS: http://k8s-devopsla-launchbo-abc123def4-567890123.us-east-1.elb.amazonaws.com
```

Apply and restart the backend so it re-reads the environment:

```bash
kubectl apply -f deployment/phase-08-eks/k8s/configmap.yaml
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
kubectl -n devops-launchboard rollout status deployment/launchboard-backend
```

Why this step exists:

The ALB DNS name is generated by AWS after the load balancer is created. You cannot know it before Step 21. The FastAPI backend uses `CORS_ORIGINS` to decide which browser origins are allowed to make API calls. If this does not match the URL in the browser's address bar, the browser blocks API responses with a CORS error.

## Step 24: Verify The App

```bash
ALB_DNS=$(kubectl -n devops-launchboard get ingress launchboard-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl -I "http://$ALB_DNS"
curl -s "http://$ALB_DNS/health" | jq
curl -s "http://$ALB_DNS/ready" | jq
curl -s "http://$ALB_DNS/api/summary" | jq
```

Open in browser:

```text
http://YOUR_ALB_DNS_NAME
```

Expected:

```text
Frontend loads.
Dashboard data appears.
API works through /api.
No CORS errors in the browser console.
```

Check the HPA:

```bash
kubectl -n devops-launchboard get hpa
```

Expected: `TARGETS` shows a real CPU percentage (not `<unknown>`), confirming Metrics Server is working.

## Rollout And Rollback

Build and push a new backend image with a new tag:

```bash
cd /opt/devops-launchboard/app-source

docker build -f deployment/phase-08-eks/Dockerfile.backend \
  -t launchboard-backend:phase-8-v2 .

docker tag launchboard-backend:phase-8-v2 \
  "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-8-v2"

docker push "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-8-v2"
```

Update the Deployment image:

```bash
kubectl -n devops-launchboard set image deployment/launchboard-backend \
  backend="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-8-v2"
kubectl -n devops-launchboard rollout status deployment/launchboard-backend
```

Check rollout history:

```bash
kubectl -n devops-launchboard rollout history deployment/launchboard-backend
```

Rollback to the previous version:

```bash
kubectl -n devops-launchboard rollout undo deployment/launchboard-backend
kubectl -n devops-launchboard rollout status deployment/launchboard-backend
```

Verify the rolled-back image:

```bash
kubectl -n devops-launchboard get deployment launchboard-backend \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
echo
```

Expected: the image tag reverts to `phase-8`.

## Logs And Debugging

Kubernetes checks:

```bash
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard describe pod POD_NAME
kubectl -n devops-launchboard logs deployment/launchboard-backend
kubectl -n devops-launchboard logs deployment/launchboard-frontend
kubectl -n devops-launchboard logs deployment/launchboard-db
kubectl -n devops-launchboard logs job/launchboard-migrate
kubectl -n devops-launchboard describe ingress launchboard-ingress
kubectl -n devops-launchboard get events --sort-by=.metadata.creationTimestamp
```

Load Balancer Controller logs:

```bash
kubectl -n kube-system logs deployment/aws-load-balancer-controller --tail=50
```

AWS checks:

```bash
aws eks describe-cluster --name devops-launchboard-phase-8 --region "$AWS_REGION" --query 'cluster.status'
aws ecr describe-images --repository-name launchboard-backend --region "$AWS_REGION" --query 'imageDetails[*].imageTags'
aws elbv2 describe-load-balancers --region "$AWS_REGION" --query 'LoadBalancers[*].[LoadBalancerName,DNSName,State.Code]' --output table
```

## Troubleshooting

### Problem 1: EKS Cluster Creation Fails

```bash
eksctl utils describe-stacks --region "$AWS_REGION" --cluster devops-launchboard-phase-8
aws cloudformation describe-stack-events --stack-name eksctl-devops-launchboard-phase-8-cluster --region "$AWS_REGION" --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' --output table
```

Common causes: missing IAM permissions (the error says which permission is needed), region typo in the config, service quota too low (check EC2 instance limits), or VPC/subnet creation failure. If a partial stack exists after a failure, delete it with `eksctl delete cluster --name devops-launchboard-phase-8 --region $AWS_REGION` before retrying.

### Problem 2: Pods Show ImagePullBackOff

```bash
kubectl -n devops-launchboard describe pod POD_NAME | tail -10
aws ecr describe-images --repository-name launchboard-backend --region "$AWS_REGION"
```

Common causes: image was not pushed to ECR, wrong account ID in the manifest, wrong region, wrong tag, or the ECR repository does not exist. Compare the image URL in the Pod events with what `aws ecr describe-images` shows. They must match exactly.

### Problem 3: Ingress Has No Address After 5 Minutes

```bash
kubectl -n devops-launchboard describe ingress launchboard-ingress
kubectl -n kube-system logs deployment/aws-load-balancer-controller --tail=50
```

Common causes: the AWS Load Balancer Controller is not installed or not running, the controller's IAM policy is missing a permission (check the logs for `AccessDenied`), the VPC subnets are missing the discovery tags (`kubernetes.io/role/elb: 1` on public subnets — eksctl sets these automatically, but verify if you modified the VPC), or the `kubernetes.io/ingress.class: alb` annotation is missing from the Ingress.

### Problem 4: PVC Is Pending

```bash
kubectl -n devops-launchboard describe pvc launchboard-postgres-pvc
kubectl get storageclass
kubectl get pods -n kube-system | grep ebs
```

Common causes: the EBS CSI driver is not installed (the add-on section in `eksctl-cluster.yaml` was removed or the add-on failed), the StorageClass `gp3` was not created (check `kubectl get sc`), or the IRSA role for the CSI driver is missing (the driver Pod logs will show `AccessDenied`).

### Problem 5: ALB Returns 502 Bad Gateway

The ALB is created but returns errors. This means traffic reaches the ALB but the ALB cannot reach healthy targets.

```bash
kubectl -n devops-launchboard get pods -o wide
kubectl -n devops-launchboard describe ingress launchboard-ingress
```

Common causes: the frontend Pods are not Ready (readiness probe failing), the `healthcheck-path` or `healthcheck-port` annotations do not match the frontend container's actual health endpoint, or the security group on the worker nodes does not allow traffic from the ALB's security group. Check the target group health in the AWS Console: EC2 > Target Groups > find the target group > Targets tab.

### Problem 6: CORS Errors In Browser

The frontend loads but API calls fail with `Access to fetch ... has been blocked by CORS policy`.

```bash
kubectl -n devops-launchboard get configmap launchboard-config -o jsonpath='{.data.CORS_ORIGINS}'
echo
```

The value must exactly match the URL in the browser address bar (including `http://`, no trailing slash, no extra spaces). If it does not match: update the ConfigMap, apply, and restart the backend (Step 23).

## Cleanup

Delete the application namespace (removes all Pods, Services, PVCs, and the Ingress, which triggers ALB deletion):

```bash
kubectl delete namespace devops-launchboard
```

Wait 2 to 3 minutes for the ALB to be fully deleted by the Load Balancer Controller before deleting the cluster, or the ALB may become an orphan.

Delete the Load Balancer Controller:

```bash
helm uninstall aws-load-balancer-controller --namespace kube-system
eksctl delete iamserviceaccount \
  --cluster devops-launchboard-phase-8 \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --region "$AWS_REGION"
```

Delete the EKS cluster (takes 10 to 20 minutes):

```bash
eksctl delete cluster --name devops-launchboard-phase-8 --region "$AWS_REGION"
```

This deletes the control plane, worker nodes, VPC, subnets, NAT Gateway, and security groups. eksctl uses CloudFormation, so all resources created by the stacks are removed.

Delete ECR repositories:

```bash
aws ecr delete-repository --repository-name launchboard-backend --force --region "$AWS_REGION"
aws ecr delete-repository --repository-name launchboard-frontend --force --region "$AWS_REGION"
```

`--force` deletes the repository even if it contains images.

Delete the IAM policy:

```bash
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy"
aws iam delete-policy --policy-arn "$POLICY_ARN"
```

Clean up the workstation policy file:

```bash
rm -f ~/aws-load-balancer-controller-policy.json
```

Check the AWS Console for leftover resources that may still incur cost:

```text
EC2 > Load Balancers (should be empty after namespace deletion + wait)
EC2 > Target Groups (should be empty)
EC2 > Volumes (orphaned EBS volumes from deleted PVCs, if reclaimPolicy was Retain)
VPC > NAT Gateways (should be deleted by eksctl, but verify)
VPC > Elastic IPs (NAT Gateway allocates one, should be released)
CloudWatch > Log Groups (cluster logs remain after deletion, delete manually if not needed)
```

Terminate the workstation EC2 from the AWS Console.

## Security Notes

- Do not expose PostgreSQL publicly. The database Service is ClusterIP, reachable only from inside the cluster.
- Use Kubernetes Secrets for lab secrets. For production, use AWS Secrets Manager with the External Secrets Operator, or the AWS Secrets Store CSI Driver.
- Use RDS instead of in-cluster PostgreSQL for production. RDS provides automated backups, multi-AZ failover, monitoring, and encryption.
- Use HTTPS with ACM for public apps. Request a free certificate in AWS Certificate Manager, create a CNAME or alias to the ALB, and add the `alb.ingress.kubernetes.io/certificate-arn` annotation to the Ingress.
- Use least-privilege IAM. The `AdministratorAccess` policy used in this lab is too broad for production.
- Keep ECR repositories private. The default is private, do not change it.
- Enable cluster logging (already done in the eksctl config). Review audit logs when investigating security events.
- Clean up NAT Gateway and ALB after labs — they incur hourly costs even with zero traffic.

## Production Checklist

```text
[ ] AWS Budget created
[ ] AWS CLI installed and configured
[ ] Docker installed on workstation
[ ] kubectl installed
[ ] eksctl installed
[ ] Helm installed
[ ] Repository cloned with SSH
[ ] Phase 8 folders created
[ ] Root .dockerignore created
[ ] eksctl-cluster.yaml created with correct region
[ ] ECR lifecycle-policy.json created
[ ] Dockerfile.backend created
[ ] Dockerfile.frontend created (COPY path points to phase-08-eks)
[ ] nginx-frontend.conf created
[ ] All k8s manifests created
[ ] storageclass.yaml created for gp3
[ ] ECR repositories created
[ ] ECR lifecycle policies applied
[ ] Docker images built
[ ] Docker images pushed to ECR
[ ] EKS cluster created (20-40 min)
[ ] All nodes Ready
[ ] EBS CSI driver running
[ ] AWS Load Balancer Controller installed
[ ] Controller Pods running in kube-system
[ ] Kubernetes namespace created
[ ] Kubernetes Secret created
[ ] Image placeholders replaced in manifests
[ ] Kubernetes manifests applied
[ ] PVC Bound to gp3 EBS volume
[ ] PostgreSQL rollout complete
[ ] Migration Job complete
[ ] Backend rollout complete
[ ] Frontend rollout complete
[ ] Ingress has ALB DNS name
[ ] CORS updated to ALB DNS
[ ] Browser app works
[ ] API works
[ ] HPA shows real CPU targets
[ ] Rollout and rollback tested
[ ] Cleanup plan understood
[ ] AWS Budget reviewed for surprise charges
```

## Reference Documentation

| Topic | Link |
| --- | --- |
| Amazon EKS | https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html |
| EKS Kubernetes versions | https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html |
| eksctl | https://eksctl.io/ |
| eksctl ClusterConfig schema | https://eksctl.io/usage/schema/ |
| Amazon ECR | https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html |
| ECR lifecycle policies | https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html |
| AWS Load Balancer Controller | https://kubernetes-sigs.github.io/aws-load-balancer-controller/ |
| ALB Ingress annotations | https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/annotations/ |
| EBS CSI Driver | https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html |
| EBS CSI StorageClass parameters | https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/docs/parameters.md |
| IRSA (IAM Roles for Service Accounts) | https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html |
| AWS VPC CNI | https://docs.aws.amazon.com/eks/latest/userguide/pod-networking.html |
| kubectl reference | https://kubernetes.io/docs/reference/kubectl/ |
| Helm | https://helm.sh/docs/ |
| Kubernetes Ingress | https://kubernetes.io/docs/concepts/services-networking/ingress/ |
| Kubernetes StorageClass | https://kubernetes.io/docs/concepts/storage/storage-classes/ |
| Kubernetes HPA | https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/ |
| Kubernetes Deployments | https://kubernetes.io/docs/concepts/workloads/controllers/deployment/ |
| Docker Engine install | https://docs.docker.com/engine/install/ubuntu/ |
| AWS CLI install | https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html |
| EKS pricing | https://aws.amazon.com/eks/pricing/ |
| NAT Gateway pricing | https://aws.amazon.com/vpc/pricing/ |

## What To Do Next

Move to:

```text
Phase 9: Observability
```

Why:

Phase 8 deployed the application to a production-grade managed Kubernetes platform. Phase 9 adds the visibility layer: Prometheus for metrics collection, Grafana for dashboards, structured logging, and alerting. Without observability, you are flying blind — you can deploy but you cannot see whether the app is healthy, how resources are being used, or when something is about to break.
