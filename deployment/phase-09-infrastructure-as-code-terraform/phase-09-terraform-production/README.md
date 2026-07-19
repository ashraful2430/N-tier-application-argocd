# Phase 9 (Part 2): Terraform Production

## Fresh Start Assumption

This phase starts from a clean AWS environment and a clean Ubuntu workstation.

You must complete `phase-09-terraform-basics` first — this guide uses every concept it taught (providers, variables, data sources, state, plan/apply) without re-explaining them from zero.

This guide assumes:

- You have an AWS account with permissions to create VPC, EC2, ALB, RDS, ECR, IAM, SSM, and S3 resources.
- Terraform, AWS CLI, and Docker are not installed yet.
- You will create files with `vim`.
- You will type commands manually.

Project repository:

```text
git@github.com:Ashik-DevOps-Class/N-tier-application.git
```

## What You Will Deploy

The same application, deployed the way a real company deploys containerized workloads on plain EC2 (no Kubernetes):

```text
                        Browser
                          |
                          | HTTP :80
                          v
              Application Load Balancer          (public subnets)
                          |
            +-------------+--------------+
            |                            |
     App Server 1                  App Server 2   (private subnets,
     [frontend :80]                [frontend :80]  Auto Scaling Group,
     [backend  :8000]              [backend :8000] 2-4 instances)
            |                            |
            +-------------+--------------+
                          |
                          | :5432
                          v
                 RDS PostgreSQL 16               (private subnets,
                                                  managed by AWS)

  Supporting services:
  - ECR: stores the backend and frontend images (built once, pulled by every instance)
  - SSM Parameter Store: holds the DB password (instances read it at boot via IAM role)
  - S3: holds the Terraform state file (shared, locked, encrypted)
  - NAT Gateway: lets private instances reach ECR, apt, and SSM
```

What makes this "production" compared to the basics lab:

| Concern | Basics | Production |
| --- | --- | --- |
| Availability | 1 instance | 2+ instances across 2 AZs, ASG replaces failed ones |
| Database | Container on the app instance | RDS: managed backups, patching, failover option |
| Network exposure | App instance has a public IP | Instances have no public IP; only the ALB is public |
| Images | Built from source on every boot | Built once, versioned in ECR, pulled in seconds |
| Secrets | In user data | In SSM Parameter Store, read at boot via IAM role |
| State | Local file | S3 bucket with locking and encryption |
| Code structure | Flat files | Reusable modules |
| Server access | SSH | SSM Session Manager (no SSH port, no key pair) |

## Wait — Real Companies Use Kubernetes. Is EC2-Without-Kubernetes A Mistake?

No — and this question deserves a straight answer, because both beliefs floating around ("everything serious runs on Kubernetes" and "Kubernetes is overkill hype") are wrong.

The architecture in this lab — containers on an Auto Scaling Group behind an ALB with RDS — is a **first-class production pattern that runs an enormous share of the real internet**. Add Amazon ECS on top (AWS's own orchestrator, which schedules containers onto exactly this kind of ASG, or onto Fargate) and you have arguably the most common production shape on AWS, period. Companies choose it deliberately when:

- The service count is small (one to a handful) — a full Kubernetes platform is overhead with no one to share it.
- The team wants AWS-native operations: IAM, ALB, CloudWatch, and ASGs they already know, with no cluster to upgrade, no CNI to debug, no control-plane bill.
- Simplicity is a feature: fewer moving parts genuinely means fewer 2am pages.

Kubernetes (your Phases 8 and 11–16) earns its complexity at a different point: **many services, many teams, one shared platform** — when the org needs a uniform deploy primitive, autoscaling policies, network policy, and an ecosystem (operators, ArgoCD, Helm) that plain ASGs do not have. Real companies run both patterns side by side all the time: the main product on EKS, the internal tools and edge services on ECS or plain ASGs.

Why this *lab* stays off Kubernetes on purpose: the subject here is **Terraform** — modules, remote state, the VPC/IAM/ALB/RDS resource graph. Deploying to EKS from Terraform is absolutely a real-world pattern (the `terraform-aws-modules/eks` module is the standard route, and real platform teams provision whole clusters this way instead of eksctl) — but doing it here would bury the Terraform lessons under Kubernetes ones you learn elsewhere in this track. Once you have finished both this lab and Phase 8, combining them is a natural extension: swap this lab's `compute` module for an EKS module, keep the `network` and `database` modules as they are, and you have the full Terraform-managed Kubernetes platform. The capstone's manifests would deploy onto it unchanged.

## Cost Warning

| Resource | Approximate Cost |
| --- | --- |
| 2 × t3.small app servers | ~$0.04/hour |
| NAT Gateway | ~$0.045/hour |
| ALB | ~$0.02/hour |
| RDS db.t3.micro | ~$0.017/hour |
| EBS + S3 + ECR | ~$0.01/hour |

Roughly **$0.13-$0.15/hour** (~$1.20 for an 8-hour session). Run `terraform destroy` after each session. Create an AWS Budget before starting.

## Files Included In This Phase

```text
deployment/phase-09-infrastructure-as-code-terraform/phase-09-terraform-production/
+-- backend.tf                    (remote state in S3)
+-- providers.tf                  (Terraform + AWS provider, ECR image locals)
+-- variables.tf                  (all inputs)
+-- main.tf                       (wires the five modules together)
+-- ecr.tf                        (ECR repositories + lifecycle policies)
+-- ssm.tf                        (DB password parameter)
+-- outputs.tf                    (app URL, endpoints)
+-- terraform.tfvars.example      (example variable values)
+-- Dockerfile.backend            (FastAPI image)
+-- Dockerfile.frontend           (React/Nginx image)
+-- nginx-frontend.conf           (Nginx config baked into the frontend image)
+-- modules/
    +-- network/                  (VPC, subnets, IGW, NAT, route tables)
    |   +-- main.tf  variables.tf  outputs.tf
    +-- security/                 (ALB, app, and DB security groups)
    |   +-- main.tf  variables.tf  outputs.tf
    +-- database/                 (RDS PostgreSQL)
    |   +-- main.tf  variables.tf  outputs.tf
    +-- loadbalancer/             (ALB, target group, listener)
    |   +-- main.tf  variables.tf  outputs.tf
    +-- compute/                  (IAM, launch template, Auto Scaling Group)
        +-- main.tf  variables.tf  outputs.tf  user-data.sh.tpl
```

## What Is A Module?

A module is a folder of `.tf` files that you call like a function: it takes input variables, creates resources, and returns outputs. The root folder (where you run `terraform apply`) is itself a module — the "root module" — and it calls the five child modules in `main.tf`.

Why bother?

- **Encapsulation**: the database module's caller only needs to know "give me subnets and a password, I return an endpoint" — not the 15 RDS settings inside.
- **Reuse**: the same `network` module could create a staging VPC and a production VPC with different CIDR inputs.
- **Review**: a pull request touching only `modules/security/` is instantly scoped for the reviewer.

## Step 1: Create AWS Workstation

Same as the basics lab:

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-9-prod-workstation` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` |
| Storage | 30 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | SSH port 22, your IP only |

```bash
chmod 400 devops-launchboard-key.pem
ssh -i devops-launchboard-key.pem ubuntu@YOUR_WORKSTATION_PUBLIC_IP
```

## Step 2: Install Base Tools, AWS CLI, Terraform, And Docker

Base tools:

```bash
cd ~
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl wget vim unzip jq ca-certificates gnupg lsb-release
```

AWS CLI:

```bash
cd ~
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip
aws configure
aws sts get-caller-identity
```

Terraform:

```bash
cd ~
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update
sudo apt install -y terraform
terraform version
```

Docker (the workstation builds the images this time):

```bash
cd ~
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

SSH back in and verify:

```bash
ssh -i devops-launchboard-key.pem ubuntu@YOUR_WORKSTATION_PUBLIC_IP
docker info
```

Reference:

- Install Terraform: https://developer.hashicorp.com/terraform/install
- Install Docker Engine on Ubuntu: https://docs.docker.com/engine/install/ubuntu/

## Step 3: Clone Repository

Same GitHub deploy key flow as every phase:

```bash
cd ~
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-9-prod" -f ~/.ssh/devops_launchboard_github_key
cat ~/.ssh/devops_launchboard_github_key.pub
```

Add the printed key to GitHub as a read-only deploy key, then:

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
git clone git@github.com:Ashik-DevOps-Class/N-tier-application.git app-source
cd app-source
```

## Step 4: Create The State Bucket

Remote state must exist **before** `terraform init`, so this one bucket is created with the AWS CLI — the only chicken-and-egg resource in the whole setup.

```bash
export AWS_REGION=YOUR_AWS_REGION
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export STATE_BUCKET=launchboard-tfstate-${ACCOUNT_ID}-${AWS_REGION}
echo "State bucket: $STATE_BUCKET"

aws s3api create-bucket \
  --bucket "$STATE_BUCKET" \
  --region "$AWS_REGION" \
  $(if [ "$AWS_REGION" != "us-east-1" ]; then echo "--create-bucket-configuration LocationConstraint=$AWS_REGION"; fi)

aws s3api put-bucket-versioning \
  --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "$STATE_BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block \
  --bucket "$STATE_BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

Command explanation:

- The bucket name includes your account ID and region because S3 bucket names are globally unique across all AWS accounts.
- `us-east-1` is the one region where `--create-bucket-configuration` must be omitted, hence the inline `if`.
- **Versioning** means every state update keeps the previous version — if a state file is ever corrupted, you can restore the one before it. This is your state's undo button.
- **Encryption** matters because the state file contains the DB password in plain text.
- **Public access block** ensures no bucket policy or ACL can ever accidentally expose the state file.

Reference:

- Terraform S3 backend: https://developer.hashicorp.com/terraform/language/backend/s3
- S3 create-bucket: https://docs.aws.amazon.com/cli/latest/reference/s3api/create-bucket.html

## Step 5: Create The Root Module Files

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-09-infrastructure-as-code-terraform/phase-09-terraform-production
cd deployment/phase-09-infrastructure-as-code-terraform/phase-09-terraform-production
```

### backend.tf

```bash
vim backend.tf
```

Paste, then replace `YOUR_STATE_BUCKET_NAME` with the bucket name printed in Step 4 and `YOUR_AWS_REGION` with your region:

```hcl
terraform {
  backend "s3" {
    bucket       = "YOUR_STATE_BUCKET_NAME"
    key          = "phase-9/terraform-production.tfstate"
    region       = "YOUR_AWS_REGION"
    use_lockfile = true
    encrypt      = true
  }
}
```

Line explanation:

- The `backend "s3"` block tells Terraform to read and write state from S3 instead of a local file. Every teammate (and CI) pointing at the same bucket/key shares one source of truth.
- `key` is the object path inside the bucket — one bucket can hold state for many projects, separated by key.
- `use_lockfile = true` enables S3-native state locking (Terraform 1.11+): while one `apply` runs, a lock object in the bucket prevents a second `apply` from corrupting state. Older tutorials use a DynamoDB table for this — the lock file replaces it.
- `encrypt = true` requests server-side encryption on the state object (belt-and-suspenders with the bucket default from Step 4).
- Backend blocks cannot use variables — Terraform reads them before variables are processed. That is why you hardcode the bucket name here.

### providers.tf

```bash
vim providers.tf
```

Paste:

```hcl
terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "devops-launchboard"
      Environment = "phase-09-terraform-production"
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  ecr_registry   = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  backend_image  = "${local.ecr_registry}/launchboard-backend:${var.image_tag}"
  frontend_image = "${local.ecr_registry}/launchboard-frontend:${var.image_tag}"
}
```

Line explanation:

- `required_version = ">= 1.11.0"` because `use_lockfile` in the backend needs it.
- `data "aws_caller_identity" "current"` asks AWS "who am I?" and returns your account ID — the Terraform equivalent of `aws sts get-caller-identity`. No more `YOUR_ACCOUNT_ID` placeholders to search-and-replace: Terraform discovers it.
- `locals` define computed values used in several places. `ecr_registry` assembles the registry hostname from the discovered account ID and the region variable; the two image locals append the repository names and tag. Every previous phase made you `sed` these into manifests — here they are derived automatically.

### variables.tf

```bash
vim variables.tf
```

Paste:

```hcl
variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "launchboard-phase-9"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "instance_type" {
  description = "EC2 instance type for app servers (pull-only, no builds)"
  type        = string
  default     = "t3.small"
}

variable "asg_desired_capacity" {
  description = "Number of app servers to run"
  type        = number
  default     = 2
}

variable "asg_min_size" {
  description = "Minimum number of app servers"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of app servers"
  type        = number
  default     = 4
}

variable "image_tag" {
  description = "Tag of the app images in ECR"
  type        = string
  default     = "phase-9"
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "launchboard"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "launchboard_user"
}

variable "db_password" {
  description = "PostgreSQL master password"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}
```

Everything except `aws_region` and `db_password` has a default, so a minimal `terraform.tfvars` needs only two lines. `instance_type` defaults to `t3.small` (not `t3.medium` like the basics lab) because these instances only *pull* prebuilt images — the memory-hungry `npm run build` happened once on the workstation.

### ecr.tf

```bash
vim ecr.tf
```

Paste:

```hcl
resource "aws_ecr_repository" "backend" {
  name                 = "launchboard-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "frontend" {
  name                 = "launchboard-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

locals {
  ecr_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the latest 10 tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name
  policy     = local.ecr_lifecycle_policy
}

resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name
  policy     = local.ecr_lifecycle_policy
}
```

Line explanation:

- In phases 8-13 you created these repositories with `aws ecr create-repository` and attached the lifecycle policy from a JSON file. Same result here, but declared — Terraform creates them, tracks them, and deletes them on destroy.
- `force_delete = true` lets `terraform destroy` remove the repository even if it still contains images. Without it, destroy fails until you empty the repository by hand. Set this to `false` in a real production account where accidental image deletion would be a problem.
- `scan_on_push = true` enables ECR's built-in vulnerability scan on every push (the feature Phase 12 uses).
- `jsonencode()` converts an HCL object into a JSON string — the same lifecycle policy JSON you used before, but written in HCL so it is syntax-checked and shared by both repositories via a local instead of duplicated.

### ssm.tf

```bash
vim ssm.tf
```

Paste:

```hcl
resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.project_name}/db-password"
  type  = "SecureString"
  value = var.db_password
}
```

- `type = "SecureString"` stores the value encrypted with the default AWS-managed KMS key.
- This is how the password reaches the app servers **without** appearing in their user data: Terraform writes the parameter, the instances read it at boot with `aws ssm get-parameter --with-decryption`, and the IAM role in the compute module grants read access to exactly this one parameter.

### main.tf

```bash
vim main.tf
```

Paste:

```hcl
module "network" {
  source = "./modules/network"

  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
}

module "security" {
  source = "./modules/security"

  project_name = var.project_name
  vpc_id       = module.network.vpc_id
}

module "database" {
  source = "./modules/database"

  project_name       = var.project_name
  private_subnet_ids = module.network.private_subnet_ids
  db_sg_id           = module.security.db_sg_id
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
  db_instance_class  = var.db_instance_class
}

module "loadbalancer" {
  source = "./modules/loadbalancer"

  project_name      = var.project_name
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  alb_sg_id         = module.security.alb_sg_id
}

module "compute" {
  source = "./modules/compute"

  project_name         = var.project_name
  aws_region           = var.aws_region
  instance_type        = var.instance_type
  private_subnet_ids   = module.network.private_subnet_ids
  app_sg_id            = module.security.app_sg_id
  target_group_arn     = module.loadbalancer.target_group_arn
  alb_dns_name         = module.loadbalancer.alb_dns_name
  ecr_registry         = local.ecr_registry
  backend_image        = local.backend_image
  frontend_image       = local.frontend_image
  db_endpoint          = module.database.db_endpoint
  db_name              = var.db_name
  db_username          = var.db_username
  db_password_ssm_name = aws_ssm_parameter.db_password.name
  db_password_ssm_arn  = aws_ssm_parameter.db_password.arn
  asg_desired_capacity = var.asg_desired_capacity
  asg_min_size         = var.asg_min_size
  asg_max_size         = var.asg_max_size
}
```

Line explanation:

- Each `module` block calls a child module: `source` points at its folder, everything else is an input variable for it.
- Look at how outputs flow between modules: `module.network.vpc_id` feeds `security`, `module.security.db_sg_id` feeds `database`, `module.database.db_endpoint` feeds `compute`. These references build the dependency graph — Terraform knows it must create the VPC before the security groups, the security groups before RDS, and RDS + ALB before the launch template (whose user data embeds the DB endpoint and the ALB DNS name for CORS).
- That last point solves a problem every Kubernetes phase had to work around: the "apply, wait for the ALB, then patch CORS and restart" dance. Here the ALB is created *first* (Terraform sees `compute` depends on `module.loadbalancer.alb_dns_name`), so instances boot with the correct CORS origin from the start.

### outputs.tf

```bash
vim outputs.tf
```

Paste:

```hcl
output "app_url" {
  description = "URL to open in the browser"
  value       = "http://${module.loadbalancer.alb_dns_name}"
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.loadbalancer.alb_dns_name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (address:port)"
  value       = module.database.db_endpoint
}

output "ecr_backend_repository_url" {
  description = "ECR repository URL for the backend image"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_repository_url" {
  description = "ECR repository URL for the frontend image"
  value       = aws_ecr_repository.frontend.repository_url
}
```

Root outputs re-export values from child modules (a module's outputs are only visible to its direct caller — the root must pass them through for `terraform output` to show them).

### terraform.tfvars

```bash
vim terraform.tfvars
```

Paste with a real password:

```hcl
aws_region  = "us-east-1"
db_password = "CHANGE_ME_STRONG_PASSWORD"
```

Confirm the gitignore rules from the basics lab cover this folder too (they are repository-wide):

```bash
grep -E "tfvars|tfstate" /opt/devops-launchboard/app-source/.gitignore
```

## Step 6: Create The Docker Build Files

The Dockerfiles are identical to the EKS phases (multi-stage builds, non-root users, pinned UIDs) — only the frontend's `COPY` path for the Nginx config points at this phase's folder.

### Dockerfile.backend

```bash
vim Dockerfile.backend
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

Key points (full line-by-line in the Phase 11 guide, same file):

- Multi-stage: dependencies compile in `builder`, only the virtualenv and app code reach `runtime`.
- Non-root user with pinned UID 10001.
- `--proxy-headers` makes Uvicorn trust `X-Forwarded-*` headers added by Nginx and the ALB.

### Dockerfile.frontend

```bash
vim Dockerfile.frontend
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

COPY deployment/phase-09-infrastructure-as-code-terraform/phase-09-terraform-production/nginx-frontend.conf /etc/nginx/conf.d/default.conf
COPY --from=builder --chown=101:101 /app/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

### nginx-frontend.conf

```bash
vim nginx-frontend.conf
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

One detail changes meaning in this phase: `proxy_pass http://launchboard-backend:8000` resolved to a Kubernetes Service in the EKS phases. Here it resolves through **Docker's embedded DNS** to the container named `launchboard-backend` on the same Docker network — both containers run on the same EC2 instance, so every instance is a self-contained frontend+backend pair.

Also create the root `.dockerignore` if this workstation has not built images before:

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

## Step 7: Create The Network Module

```bash
mkdir -p modules/network modules/security modules/database modules/loadbalancer modules/compute
vim modules/network/variables.tf
```

Paste:

```hcl
variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}
```

```bash
vim modules/network/main.tf
```

Paste:

```hcl
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${local.azs[count.index]}"
  }
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 11)
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${var.project_name}-private-${local.azs[count.index]}"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.project_name}-nat"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
```

Line explanation:

- This module hand-builds what `eksctl` built invisibly in the EKS phases. Seeing it as code demystifies "the VPC eksctl creates."
- `data "aws_availability_zones"` + `slice(..., 0, 2)` picks the first two available AZs in whatever region you chose — no hardcoded `us-east-1a`.
- `count = 2` creates two copies of a resource; `count.index` (0 or 1) differentiates them. This is Terraform's loop.
- `cidrsubnet(var.vpc_cidr, 8, n)` carves subnet `n` out of the VPC block: with `10.0.0.0/16` and 8 extra bits, public subnets get `10.0.1.0/24` and `10.0.2.0/24`, private get `10.0.11.0/24` and `10.0.12.0/24`. Changing `vpc_cidr` re-derives everything consistently.
- `map_public_ip_on_launch = true` on public subnets gives the ALB nodes public IPs. Private subnets omit it — app servers get no public IP at all.
- One NAT Gateway (~$33/month) instead of one per AZ, the same cost tradeoff as `nat.gateway: Single` in every eksctl config.
- `depends_on = [aws_internet_gateway.this]` is one of the rare **explicit** dependencies: the NAT Gateway has no direct reference to the IGW, but AWS requires the IGW to exist before a NAT Gateway can be created in the VPC.
- The private route table sends internet-bound traffic (`0.0.0.0/0`) to the NAT Gateway — this is what lets private instances download Docker packages and pull from ECR while remaining unreachable from outside.

```bash
vim modules/network/outputs.tf
```

Paste:

```hcl
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "IDs of the two public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the two private subnets"
  value       = aws_subnet.private[*].id
}
```

`aws_subnet.public[*].id` is the splat expression: "the `id` of every instance of this counted resource" — it returns a list.

Reference:

- VPC and subnets: https://docs.aws.amazon.com/vpc/latest/userguide/configure-your-vpc.html
- cidrsubnet function: https://developer.hashicorp.com/terraform/language/functions/cidrsubnet
- NAT Gateways: https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html

## Step 8: Create The Security Module

```bash
vim modules/security/variables.tf
```

Paste:

```hcl
variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC to create security groups in"
  type        = string
}
```

```bash
vim modules/security/main.tf
```

Paste:

```hcl
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "HTTP from anywhere to the load balancer"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "HTTP from the ALB only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from the ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-app-sg"
  }
}

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "PostgreSQL from app servers only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from app servers"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-db-sg"
  }
}
```

Line explanation:

- Three groups form a strict chain: internet → ALB (port 80) → app servers (port 80, **only from the ALB's security group**) → database (port 5432, **only from the app security group**).
- `security_groups = [aws_security_group.alb.id]` in an ingress rule means "allow traffic from any resource that carries that security group" — no IP ranges to maintain. When the ASG adds a third instance, it automatically may talk to the database because it carries the app security group. This referencing pattern is the single most important security-group idiom in AWS.
- Note there is **no SSH rule anywhere**. Server access goes through SSM Session Manager (Step 12), which needs only outbound HTTPS.

```bash
vim modules/security/outputs.tf
```

Paste:

```hcl
output "alb_sg_id" {
  description = "Security group ID for the ALB"
  value       = aws_security_group.alb.id
}

output "app_sg_id" {
  description = "Security group ID for app servers"
  value       = aws_security_group.app.id
}

output "db_sg_id" {
  description = "Security group ID for the database"
  value       = aws_security_group.db.id
}
```

## Step 9: Create The Database Module

```bash
vim modules/database/variables.tf
```

Paste:

```hcl
variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the DB subnet group"
  type        = list(string)
}

variable "db_sg_id" {
  description = "Security group ID for the database"
  type        = string
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
}

variable "db_password" {
  description = "PostgreSQL master password"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
}
```

```bash
vim modules/database/main.tf
```

Paste:

```hcl
resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnets"
  }
}

resource "aws_db_instance" "this" {
  identifier     = "${var.project_name}-postgres"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.db_sg_id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = {
    Name = "${var.project_name}-postgres"
  }
}
```

Line explanation:

- This replaces the PostgreSQL container + PVC pattern from every previous phase with a **managed database**: AWS handles the OS, PostgreSQL patching, automated backups, and storage. This is the single biggest production upgrade in this lab — the `lost+found`/PGDATA class of problems simply does not exist here.
- `aws_db_subnet_group` tells RDS which subnets it may place the database in — both private, so the database has no route from the internet.
- `engine_version = "16"` pins the major version and lets AWS apply minor patches automatically.
- `publicly_accessible = false` plus the security group (5432 only from app servers) is defense in depth.
- `multi_az = false` keeps the lab cheap. Setting it `true` gives a synchronous standby in the second AZ with automatic failover — the one-line change that turns this into real production HA (roughly doubles the RDS cost).
- `backup_retention_period = 1` enables automated daily backups (production: 7-30). `skip_final_snapshot = true` and `deletion_protection = false` make `terraform destroy` clean and fast for a lab; in real production you would flip both.
- RDS creation is the slow part of the apply: **5 to 10 minutes**.

```bash
vim modules/database/outputs.tf
```

Paste:

```hcl
output "db_endpoint" {
  description = "RDS endpoint in address:port form"
  value       = aws_db_instance.this.endpoint
}
```

`endpoint` is `hostname:5432` — ready to drop into `DATABASE_URL`.

Reference:

- RDS for PostgreSQL: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html
- aws_db_instance: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance

## Step 10: Create The Load Balancer Module

```bash
vim modules/loadbalancer/variables.tf
```

Paste:

```hcl
variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the ALB"
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security group ID for the ALB"
  type        = string
}
```

```bash
vim modules/loadbalancer/main.tf
```

Paste:

```hcl
resource "aws_lb" "this" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  tags = {
    Name = "${var.project_name}-alb"
  }
}

resource "aws_lb_target_group" "app" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/healthz"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project_name}-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
```

Line explanation:

- In the EKS phases, the AWS Load Balancer Controller created this ALB for you from Ingress annotations. Here you declare the same three pieces explicitly: the load balancer, the target group, the listener.
- `internal = false` makes it internet-facing (the `alb.ingress.kubernetes.io/scheme: internet-facing` annotation equivalent).
- The target group health check hits `/healthz` on port 80 of each instance — the frontend Nginx's no-backend-required endpoint, exactly like the `healthcheck-path` annotation before. An instance only receives traffic after 2 consecutive passing checks and is pulled after 3 consecutive failures.
- The listener says: anything arriving on port 80 → forward to the target group. No TLS listener because this lab deliberately skips domains and certificates.

```bash
vim modules/loadbalancer/outputs.tf
```

Paste:

```hcl
output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.this.dns_name
}

output "target_group_arn" {
  description = "ARN of the app target group"
  value       = aws_lb_target_group.app.arn
}
```

## Step 11: Create The Compute Module

```bash
vim modules/compute/variables.tf
```

Paste:

```hcl
variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "aws_region" {
  description = "AWS region (used by the instance to reach ECR and SSM)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for app servers"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs the ASG launches instances into"
  type        = list(string)
}

variable "app_sg_id" {
  description = "Security group ID for app servers"
  type        = string
}

variable "target_group_arn" {
  description = "ALB target group the ASG registers instances with"
  type        = string
}

variable "alb_dns_name" {
  description = "ALB DNS name, used as the CORS origin"
  type        = string
}

variable "ecr_registry" {
  description = "ECR registry hostname"
  type        = string
}

variable "backend_image" {
  description = "Full backend image URL including tag"
  type        = string
}

variable "frontend_image" {
  description = "Full frontend image URL including tag"
  type        = string
}

variable "db_endpoint" {
  description = "RDS endpoint in address:port form"
  type        = string
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
}

variable "db_username" {
  description = "PostgreSQL username"
  type        = string
}

variable "db_password_ssm_name" {
  description = "Name of the SSM parameter holding the DB password"
  type        = string
}

variable "db_password_ssm_arn" {
  description = "ARN of the SSM parameter holding the DB password"
  type        = string
}

variable "asg_desired_capacity" {
  description = "Number of app servers to run"
  type        = number
}

variable "asg_min_size" {
  description = "Minimum number of app servers"
  type        = number
}

variable "asg_max_size" {
  description = "Maximum number of app servers"
  type        = number
}
```

```bash
vim modules/compute/main.tf
```

Paste:

```hcl
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "aws_iam_role" "app" {
  name = "${var.project_name}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "read_db_password" {
  name = "${var.project_name}-read-db-password"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = var.db_password_ssm_arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project_name}-app-profile"
  role = aws_iam_role.app.name
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-"
  image_id      = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type = var.instance_type

  vpc_security_group_ids = [var.app_sg_id]

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
    }
  }

  metadata_options {
    http_tokens = "required"
  }

  user_data = base64encode(templatefile("${path.module}/user-data.sh.tpl", {
    aws_region           = var.aws_region
    ecr_registry         = var.ecr_registry
    backend_image        = var.backend_image
    frontend_image       = var.frontend_image
    db_endpoint          = var.db_endpoint
    db_name              = var.db_name
    db_username          = var.db_username
    db_password_ssm_name = var.db_password_ssm_name
    alb_dns_name         = var.alb_dns_name
  }))

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.project_name}-app"
    }
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "${var.project_name}-asg"
  desired_capacity    = var.asg_desired_capacity
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [var.target_group_arn]

  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-app"
    propagate_at_launch = true
  }
}
```

Line explanation:

- **IAM role**: `assume_role_policy` says "EC2 instances may wear this role." Three permissions are attached: `AmazonEC2ContainerRegistryReadOnly` (pull from ECR), `AmazonSSMManagedInstanceCore` (be reachable through SSM Session Manager), and one inline policy allowing `ssm:GetParameter` on **exactly one parameter** — the DB password. This is the EC2 equivalent of IRSA from the EKS phases: credentials delivered by the platform, never stored on the machine.
- `aws_iam_instance_profile` is the wrapper object EC2 needs to attach a role to an instance — a historical AWS quirk; it adds nothing conceptually.
- **Launch template**: the recipe for every instance the ASG creates. `name_prefix` (instead of `name`) lets Terraform create a new template version alongside the old during changes.
- `metadata_options.http_tokens = "required"` enforces IMDSv2 on the metadata service, blocking a classic SSRF credential-theft vector.
- `user_data` must be `base64encode()`d in a launch template (unlike `aws_instance`, which encodes it for you).
- **ASG**: `vpc_zone_identifier` spreads instances across the two private subnets (two AZs). `target_group_arns` auto-registers every new instance with the ALB.
- `health_check_type = "ELB"` means an instance failing the **ALB's** `/healthz` check gets terminated and replaced — not just EC2-level "the VM is running." `health_check_grace_period = 300` gives user data five minutes to boot the containers before health enforcement starts.
- `instance_refresh` with `Rolling` is the deployment strategy: when the launch template changes (for example a new `image_tag`), the ASG replaces instances in batches, keeping at least 50% healthy — a rolling update without Kubernetes.

```bash
vim modules/compute/user-data.sh.tpl
```

Paste:

```bash
#!/bin/bash
set -eux

# Install Docker from the official repository
apt-get update
apt-get install -y ca-certificates curl unzip
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# Install AWS CLI v2 (needed for ECR login and SSM parameter read)
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/aws /tmp/awscliv2.zip

# Read the database password from SSM Parameter Store (IAM role grants access)
DB_PASSWORD=$(aws ssm get-parameter \
  --name "${db_password_ssm_name}" \
  --with-decryption \
  --region "${aws_region}" \
  --query Parameter.Value \
  --output text)

DATABASE_URL="postgresql+asyncpg://${db_username}:$DB_PASSWORD@${db_endpoint}/${db_name}"

# Log in to ECR and pull the app images
aws ecr get-login-password --region "${aws_region}" \
  | docker login --username AWS --password-stdin "${ecr_registry}"
docker pull "${backend_image}"
docker pull "${frontend_image}"

# Shared network so the frontend can reach the backend by container name
docker network create launchboard || true

# Run database migrations (alembic is idempotent; already-applied migrations are skipped)
docker run --rm --network launchboard \
  -e DATABASE_URL="$DATABASE_URL" \
  "${backend_image}" alembic upgrade head

# Backend API
docker run -d --name launchboard-backend --network launchboard \
  --restart unless-stopped \
  -e DATABASE_URL="$DATABASE_URL" \
  -e APP_NAME="DevOps LaunchBoard API" \
  -e APP_ENV=production \
  -e CORS_ORIGINS="http://${alb_dns_name}" \
  -e SEED_DEMO_DATA=true \
  "${backend_image}"

# Frontend (Nginx serving the built app and proxying /api to the backend)
docker run -d --name launchboard-frontend --network launchboard \
  --restart unless-stopped \
  -p 80:8080 \
  "${frontend_image}"
```

Line explanation:

- The password is fetched at boot with `aws ssm get-parameter --with-decryption`, authorized by the instance role — it never appears in the launch template, the Terraform files, or the instance's user data text. (`$DB_PASSWORD` and `$DATABASE_URL` are shell variables resolved on the instance; all `${...}` names are Terraform template placeholders substituted at plan time.)
- No image builds here — `docker pull` of prebuilt images takes seconds, so a replacement instance is serving traffic in ~3 minutes instead of ~6.
- The migration runs on every instance boot. `alembic upgrade head` is safe to repeat (it no-ops when the schema is current); two instances booting simultaneously could theoretically race, which a real pipeline avoids by running migrations as a dedicated CI step before deployment (exactly what the Phase 7 Jenkins pipeline and the Kubernetes migration Job do).
- `CORS_ORIGINS="http://${alb_dns_name}"` is correct from first boot because Terraform orders the ALB before the ASG.
- `--restart unless-stopped` makes Docker restart a crashed container automatically — the ASG replaces dead *instances*, Docker restarts dead *containers*.

```bash
vim modules/compute/outputs.tf
```

Paste:

```hcl
output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.app.name
}
```

Reference:

- Launch templates: https://docs.aws.amazon.com/autoscaling/ec2/userguide/launch-templates.html
- Auto Scaling groups: https://docs.aws.amazon.com/autoscaling/ec2/userguide/auto-scaling-groups.html
- Instance refresh: https://docs.aws.amazon.com/autoscaling/ec2/userguide/asg-instance-refresh.html
- IAM roles for EC2: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html
- SSM Parameter Store: https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html

## Step 12: Init And Create The ECR Repositories First

```bash
terraform init
```

Expected: `Terraform has been successfully initialized!` — this time it also configured the S3 backend (you will see "Initializing the backend..." succeed). Then:

```bash
terraform fmt -recursive
terraform validate
```

(`-recursive` formats the module folders too.)

There is one ordering problem to solve: instances pull images from ECR at boot, but the ECR repositories are part of this same configuration. If you applied everything at once, instances would boot before any image exists and their user data would fail. Create just the repositories first with a **targeted apply**:

```bash
terraform apply \
  -target=aws_ecr_repository.backend \
  -target=aws_ecr_repository.frontend
```

Type `yes`. Terraform warns that targeted applies are for exceptional situations — this bootstrap ordering is exactly such a situation; you will never need `-target` again in this phase.

## Step 13: Build And Push The Images

```bash
cd /opt/devops-launchboard/app-source

export AWS_REGION=YOUR_AWS_REGION
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin $ECR_REGISTRY

docker build -f deployment/phase-09-infrastructure-as-code-terraform/phase-09-terraform-production/Dockerfile.backend \
  -t $ECR_REGISTRY/launchboard-backend:phase-9 .

docker build -f deployment/phase-09-infrastructure-as-code-terraform/phase-09-terraform-production/Dockerfile.frontend \
  --build-arg VITE_API_URL= \
  -t $ECR_REGISTRY/launchboard-frontend:phase-9 .

docker push $ECR_REGISTRY/launchboard-backend:phase-9
docker push $ECR_REGISTRY/launchboard-frontend:phase-9
```

Verify both images exist:

```bash
aws ecr describe-images --repository-name launchboard-backend --region "$AWS_REGION" \
  --query 'imageDetails[?imageTags!=null].imageTags' --output table
aws ecr describe-images --repository-name launchboard-frontend --region "$AWS_REGION" \
  --query 'imageDetails[?imageTags!=null].imageTags' --output table
```

## Step 14: Apply Everything

```bash
cd deployment/phase-09-infrastructure-as-code-terraform/phase-09-terraform-production
terraform plan
```

Expected: roughly **35 to add** (VPC pieces, security groups, RDS, ALB pieces, IAM pieces, launch template, ASG, SSM parameter, lifecycle policies). Read through it once — you should now be able to name what every line is for. Then:

```bash
terraform apply
```

Type `yes`. Expect **10 to 15 minutes**, dominated by RDS (~5-10 min) and the NAT Gateway (~2 min). The outputs print at the end:

```text
Apply complete! Resources: 35 added, 0 changed, 0 destroyed.

Outputs:

alb_dns_name = "launchboard-phase-9-alb-1234567890.us-east-1.elb.amazonaws.com"
app_url = "http://launchboard-phase-9-alb-1234567890.us-east-1.elb.amazonaws.com"
...
```

Wait 3 to 5 more minutes (instances are booting and pulling images), then verify:

```bash
APP_URL=$(terraform output -raw app_url)
curl -s "$APP_URL/health" | jq
curl -s "$APP_URL/api/summary" | jq
```

Open the `app_url` in the browser — the LaunchBoard UI loads through the ALB, served by whichever instance the ALB picked, backed by RDS.

Check the target group in the console (EC2 > Target Groups > launchboard-phase-9-tg > Targets): both instances should show `healthy`.

## Step 15: Connect To A Private Instance With SSM

The instances have no public IP and no SSH port. Session Manager gives you a shell through the SSM agent (pre-installed on Ubuntu AMIs) using the IAM role:

```bash
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=launchboard-phase-9-app" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text --region "$AWS_REGION")

aws ssm start-session --target "$INSTANCE_ID" --region "$AWS_REGION"
```

If `start-session` complains about a missing plugin, install it on the workstation:

```bash
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o session-manager-plugin.deb
sudo dpkg -i session-manager-plugin.deb
rm session-manager-plugin.deb
```

Inside the session:

```bash
sudo docker ps
sudo docker logs launchboard-backend --tail 20
exit
```

This is how production teams access locked-down instances: every session is IAM-authenticated and logged in CloudTrail, and there is no SSH key to leak.

Reference:

- Session Manager: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html

## Step 16: Practice A Production Change

Scale from 2 to 3 app servers by editing one line:

```bash
vim terraform.tfvars
```

Add:

```hcl
asg_desired_capacity = 3
```

```bash
terraform plan
```

The plan shows exactly one in-place change to the ASG. Apply, then watch the third instance register in the target group and turn `healthy` (~3-4 minutes). Set it back to 2 (or remove the line) and apply again — the ASG terminates one instance gracefully.

For a **rolling redeploy** (new image version): push images with a new tag (for example `phase-9-v2`), set `image_tag = "phase-9-v2"` in `terraform.tfvars`, and apply. The launch template gets a new version, and `instance_refresh` replaces instances in batches while the ALB keeps serving from the healthy ones — a zero-downtime deployment driven entirely by one variable change.

## Step 17: Destroy

```bash
terraform destroy
```

Type `yes`. Takes ~10 minutes (RDS again). `force_delete = true` on the ECR repositories means the images inside do not block deletion.

The state bucket is outside Terraform, so remove it by hand once you are fully done with the phase:

```bash
aws s3 rm "s3://$STATE_BUCKET" --recursive
aws s3api delete-bucket --bucket "$STATE_BUCKET" --region "$AWS_REGION"
```

Terminate the workstation from the console. Then check for leftovers: EC2 > Load Balancers, EC2 > Volumes, VPC > NAT Gateways, VPC > Elastic IPs, RDS > Databases — all should be empty.

## Troubleshooting

### Problem 1: `Error: Failed to get existing workspaces: S3 bucket does not exist`

`backend.tf` still contains `YOUR_STATE_BUCKET_NAME`, or the bucket name/region does not match what you created in Step 4. Fix the values and re-run `terraform init`.

### Problem 2: `Error: creating ECR Repository: RepositoryAlreadyExistsException`

A repository named `launchboard-backend` already exists from an earlier phase you did not clean up. Either delete it (`aws ecr delete-repository --repository-name launchboard-backend --force --region $AWS_REGION`) or bring it under Terraform's management instead:

```bash
terraform import aws_ecr_repository.backend launchboard-backend
terraform import aws_ecr_repository.frontend launchboard-frontend
```

`terraform import` records an existing resource in state so Terraform manages it from now on instead of trying to create it.

### Problem 3: ALB returns 502 Bad Gateway or targets stay unhealthy

The containers on the instances are not up yet (wait the full 5-minute grace period), or user data failed. Open an SSM session (Step 15) and check:

```bash
sudo tail -100 /var/log/cloud-init-output.log
sudo docker ps -a
```

Common causes: images not pushed before instances booted (Step 13 skipped or done after Step 14 — fix by terminating the instances: `aws autoscaling start-instance-refresh --auto-scaling-group-name launchboard-phase-9-asg --region $AWS_REGION`), or migration failure because RDS was still initializing (same fix — replacement instances retry cleanly).

### Problem 4: `alembic upgrade head` fails with connection refused

RDS finished creating but was not yet accepting connections when the first instance booted. Instance refresh (command above) or waiting for the ASG's ELB health check to replace the instance both resolve it.

### Problem 5: `Error acquiring the state lock` in S3

Someone (or a crashed run) holds the lock. Check no other terraform process is running, then:

```bash
terraform force-unlock LOCK_ID_FROM_THE_ERROR
```

### Problem 6: Apply fails with `VcpuLimitExceeded` or subnet IP exhaustion

Your account's on-demand vCPU quota is too low for workstation + 2-3 app servers. Request a quota increase (Service Quotas > EC2 > Running On-Demand Standard instances) or reduce `asg_desired_capacity` to 1 temporarily.

### Problem 7: `terraform destroy` hangs on the VPC or subnets

Something outside Terraform still lives in the VPC (usually a manually created resource or an ENI left by a deleted ALB). Check EC2 > Network Interfaces filtered by the VPC, delete stragglers, and re-run destroy.

## Production Checklist

```text
[ ] State bucket created with versioning + encryption + public access block
[ ] backend.tf placeholders replaced, terraform init succeeds against S3
[ ] ECR repositories created via targeted apply
[ ] Images built once and pushed to ECR
[ ] Full apply: ~35 resources, no errors
[ ] App loads via the ALB URL
[ ] Both targets healthy in the target group
[ ] App servers have no public IPs (check EC2 console)
[ ] RDS not publicly accessible
[ ] DB password only in SSM (not in user data / launch template)
[ ] SSM session into an instance works (no SSH anywhere)
[ ] Scaled 2 -> 3 -> 2 via terraform.tfvars
[ ] terraform destroy completed, console shows no leftovers
[ ] State bucket deleted at the very end
```

## Reference Documentation

| Topic | Link |
| --- | --- |
| Terraform modules | https://developer.hashicorp.com/terraform/language/modules |
| S3 backend | https://developer.hashicorp.com/terraform/language/backend/s3 |
| AWS provider | https://registry.terraform.io/providers/hashicorp/aws/latest/docs |
| Amazon RDS | https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Welcome.html |
| Application Load Balancer | https://docs.aws.amazon.com/elasticloadbalancing/latest/application/introduction.html |
| EC2 Auto Scaling | https://docs.aws.amazon.com/autoscaling/ec2/userguide/what-is-amazon-ec2-auto-scaling.html |
| SSM Parameter Store | https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html |
| SSM Session Manager | https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html |
| Amazon ECR | https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html |

## What To Do Next

Move to:

```text
Phase 10: Configuration Management With Ansible
```

Why:

Terraform answered "how do machines get created?" Ansible answers the complementary question: "how does software get installed and configured on machines that already exist?" You will see where the two tools overlap, where they differ, and why many teams run `terraform apply` first and `ansible-playbook` second.
