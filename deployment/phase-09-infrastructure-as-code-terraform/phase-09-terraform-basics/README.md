# Phase 9 (Part 1): Terraform Basics

## Fresh Start Assumption

This phase starts from a clean AWS environment and a clean Ubuntu workstation.

You do not need to complete any previous phase before using this guide.

This guide assumes:

- You have an AWS account with permissions to create EC2, VPC, and IAM resources.
- You have a free Docker Hub account (hub.docker.com) — you publish the app images there once, and the server pulls them. Your Git repository can stay **private**.
- Terraform and AWS CLI are not installed yet.
- You will create files with `vim`.
- You will type commands manually.
- You will not use shell scripts (the only script is the EC2 user data, which is part of the Terraform configuration itself).

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What You Will Deploy

One EC2 instance that runs the full DevOps LaunchBoard stack (PostgreSQL, FastAPI backend, React frontend) with Docker Compose — the same result as Phase 4, but this time **Terraform creates and configures everything**. You never open the EC2 Console to click "Launch instance."

The app images are built **once on your workstation** and pushed to Docker Hub; the server only pulls and runs them. That split — build the artifact once, run it anywhere — is a first taste of the pipeline the production lab formalizes with ECR, and it means the Git repository never has to be readable by the server (it can stay private).

```text
        You (terraform apply)
                |
                v
        AWS API (via Terraform AWS provider)
                |
    +-----------+------------+
    |                        |
Security Group          EC2 Instance (Ubuntu 24.04)
(22 from you,               |
 80 from anyone)        user data script runs on first boot:
                            - installs Docker + Compose
                            - writes the compose file
                            - pulls your images from Docker Hub
                            - docker compose up -d
                            |
                    +-------+--------+
                    |       |        |
                Frontend  Backend  PostgreSQL
                (Nginx)  (FastAPI) (container + volume)
                  :80
```

## What Is Terraform?

Terraform is an infrastructure-as-code tool. You describe the infrastructure you want in `.tf` files (declarative — you say *what* should exist, not *how* to create it), and Terraform:

1. **Reads** your configuration files.
2. **Compares** them to the real infrastructure it knows about (recorded in a *state file*).
3. **Plans** the exact set of API calls needed to make reality match the files.
4. **Applies** that plan after you approve it.

The three commands you will use constantly:

| Command | What it does |
| --- | --- |
| `terraform init` | Downloads the providers (plugins) your configuration needs |
| `terraform plan` | Shows what would change, without changing anything |
| `terraform apply` | Makes the changes after showing the plan and asking for confirmation |

## When To Use This Architecture

Use this lab when:

- You want to learn Terraform fundamentals: providers, resources, variables, data sources, outputs, state.
- You want to see a full app come up from a single command.

Do not use this exact architecture for production:

- One instance is a single point of failure.
- The database runs in a container on the same instance as the app.
- State is stored in a local file that only exists on your machine.

The `phase-09-terraform-production` lab fixes all three.

## Cost Warning

| Resource | Approximate Cost |
| --- | --- |
| 1 × t3.small (app server) | ~$0.02/hour |
| 30 GB gp3 EBS | ~$0.003/hour |

Running for 8 hours costs well under $1. Run `terraform destroy` after each session.

## Files Included In This Phase

```text
deployment/phase-09-infrastructure-as-code-terraform/phase-09-terraform-basics/
+-- providers.tf                (Terraform + AWS provider configuration)
+-- variables.tf                (input variables)
+-- data.tf                     (data sources: default VPC, Ubuntu AMI)
+-- security.tf                 (security group)
+-- ec2.tf                      (the app server)
+-- user-data.sh.tpl            (first-boot script template)
+-- outputs.tf                  (values printed after apply)
+-- terraform.tfvars.example    (example variable values)
+-- README.md
```

## Step 1: Create AWS Workstation

Create one Ubuntu EC2 workstation from the AWS Console (this is the last instance you will ever create by hand in this phase — Terraform creates the rest):

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-9-workstation` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.medium` |
| Storage | 30 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | SSH port 22, your IP only |

The workstation is `t3.medium` (4 GB RAM) because it is where the app images are **built** in Step 5 — the frontend's `npm run build` needs the memory. The app server Terraform creates only pulls images, so it stays a cheaper `t3.small`.

SSH in:

```bash
chmod 400 devops-launchboard-key.pem
ssh -i devops-launchboard-key.pem ubuntu@YOUR_WORKSTATION_PUBLIC_IP
```

Reference:

- Launch EC2 instance: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EC2_GetStarted.html
- Create EC2 key pair: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/create-key-pairs.html

## Step 2: Install Base Tools And AWS CLI

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

Command explanation:

- `aws configure` prompts for your Access Key ID, Secret Access Key, default region, and output format. Get keys from IAM Console > Users > your user > Security credentials > Create access key. Terraform reads these same credentials automatically — you do not configure credentials separately for Terraform.
- `aws sts get-caller-identity` confirms the credentials work by printing your account ID and user ARN.

Reference:

- Install AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- Terraform AWS provider authentication: https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication-and-configuration

## Step 3: Install Terraform

```bash
cd ~
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update
sudo apt install -y terraform
```

Verify:

```bash
terraform version
```

Command explanation:

- The first command downloads HashiCorp's GPG signing key and converts it to the binary keyring format apt expects (`gpg --dearmor`), storing it where apt looks for repository keys.
- The `echo ... | sudo tee` line registers HashiCorp's apt repository, restricted to packages signed by that key (`signed-by=`). `$(lsb_release -cs)` inserts your Ubuntu codename so apt picks the right package build.
- If `sudo apt update` fails with a GPG or "clearsigned file" error (the same class of problem as the Helm apt repo in Phase 11), fall back to the direct binary download:

```bash
TERRAFORM_VERSION=$(curl -sI https://github.com/hashicorp/terraform/releases/latest \
  | grep -i '^location:' | sed 's|.*/tag/v||' | tr -d '\r')
curl -LO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
unzip "terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
sudo mv terraform /usr/local/bin/terraform
rm "terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
terraform version
```

Reference:

- Install Terraform: https://developer.hashicorp.com/terraform/install
- Terraform releases: https://releases.hashicorp.com/terraform/

## Step 4: Clone Repository

The workstation needs the source code to build the images in the next step. Because this clone authenticates with your deploy key, the repository can stay **private** — nothing in this lab requires public Git access.

Create GitHub SSH key:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-9" -f ~/.ssh/devops_launchboard_github_key
cat ~/.ssh/devops_launchboard_github_key.pub
```

Command explanation:

- `mkdir -p ~/.ssh` creates the SSH directory if it does not exist (`-p` makes it a no-op if it does), and `chmod 700` restricts it to your user only — SSH refuses to use keys stored in a directory other users can read.
- `ssh-keygen -t ed25519` generates a modern Ed25519 key pair — shorter, faster, and at least as secure as the older RSA keys. `-C "devops-launchboard-phase-9"` is a comment label so you can recognize this key later in GitHub's key list, and `-f` names the files (`devops_launchboard_github_key` private, `.pub` public) instead of overwriting your default `id_ed25519`.
- `cat ...pub` prints the **public** key — the half that is safe to share. This is what you paste into GitHub. The private key never leaves the workstation.

Add it to GitHub as a read-only deploy key (repository > Settings > Deploy keys > Add deploy key, paste the key, leave "Allow write access" unchecked). A deploy key grants access to **this one repository only** — unlike an account-level SSH key, a leaked workstation cannot touch anything else you own, and read-only means it cannot push.

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

Line explanation:

- The config block tells SSH how to connect whenever the destination is `github.com`, so `git clone` needs no extra flags.
- `IdentityFile` points at the key you just generated instead of the default `~/.ssh/id_ed25519`.
- `IdentitiesOnly yes` makes SSH offer **only** this key. Without it, SSH tries every key it can find first — and GitHub rejects the connection after too many wrong keys, a confusing failure when you have several.

Secure and test:

```bash
chmod 600 ~/.ssh/config ~/.ssh/devops_launchboard_github_key
chmod 644 ~/.ssh/devops_launchboard_github_key.pub
ssh -T git@github.com
```

Command explanation:

- `chmod 600` (owner read/write only) on the config and the **private** key — SSH refuses outright to use a private key that other users could read ("UNPROTECTED PRIVATE KEY FILE" error). The public key can stay world-readable (`644`).
- `ssh -T git@github.com` tests authentication without opening a shell (`-T` = no terminal; GitHub does not offer shells anyway). Success looks like: `Hi ashraful2430/N-tier-application! You've successfully authenticated, but GitHub does not provide shell access.` — that message means the deploy key works. Type `yes` at the first-connection host-authenticity prompt.

Clone:

```bash
sudo mkdir -p /opt/devops-launchboard
sudo chown -R ubuntu:ubuntu /opt/devops-launchboard
cd /opt/devops-launchboard
git clone git@github.com:ashraful2430/N-tier-application.git app-source
cd app-source
```

Command explanation:

- `/opt` is the conventional Linux home for add-on software, but it is owned by root — hence `sudo mkdir` to create the folder and `sudo chown -R ubuntu:ubuntu` to hand it to your user, so every later `git` and `terraform` command runs **without** sudo.
- `git clone git@github.com:...` uses the SSH URL (not HTTPS), which is what routes through the deploy key you just configured. The final `app-source` argument names the target folder — every later step in this guide assumes the repository lives at `/opt/devops-launchboard/app-source`.

Reference:

- Generate an SSH key: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent
- GitHub deploy keys: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys#deploy-keys

## Step 5: Build And Push The App Images To Docker Hub

The server will not build anything — it pulls ready images. So the images must exist first. You build them here, on the workstation, using the Phase 4 Dockerfiles from the repository you just cloned, and publish them to your Docker Hub account.

Install Docker on the workstation:

```bash
cd ~
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo ${UBUNTU_CODENAME:-$VERSION_CODENAME}) stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
sudo usermod -aG docker ubuntu
exit
```

SSH back in (the group change needs a new session), then log in to Docker Hub:

```bash
ssh -i devops-launchboard-key.pem ubuntu@YOUR_WORKSTATION_PUBLIC_IP
docker login -u YOUR_DOCKERHUB_USERNAME
```

For the password, use a **personal access token**, not your account password: hub.docker.com > your avatar > Account settings > Personal access tokens > Generate new token (Read & Write scope is enough). Tokens can be revoked individually and never unlock your whole account.

Build and push both images:

```bash
cd /opt/devops-launchboard/app-source

docker build -f deployment/phase-04-docker-compose/Dockerfile.backend \
  -t YOUR_DOCKERHUB_USERNAME/launchboard-backend:phase-9 .

docker build -f deployment/phase-04-docker-compose/Dockerfile.frontend \
  --build-arg VITE_API_URL= \
  -t YOUR_DOCKERHUB_USERNAME/launchboard-frontend:phase-9 .

docker push YOUR_DOCKERHUB_USERNAME/launchboard-backend:phase-9
docker push YOUR_DOCKERHUB_USERNAME/launchboard-frontend:phase-9
```

Command explanation:

- The image name format is `USERNAME/REPOSITORY:TAG` — for Docker Hub, the username prefix *is* the registry address (compare with ECR's `ACCOUNT.dkr.ecr.REGION.amazonaws.com/...` in the production lab).
- `-f deployment/phase-04-docker-compose/Dockerfile.backend` reuses the proven Phase 4 build files; the trailing `.` makes the repository root the build context, which those Dockerfiles expect.
- `--build-arg VITE_API_URL=` (empty) makes the frontend call the API with relative `/api` paths, proxied by its own Nginx.
- `docker push` uploads the layers. On a free Docker Hub account these repositories are **public** — anyone can pull them. That is what lets the app server pull anonymously with zero credentials. (Note what that implies: the *built app* inside the images is public even though your source repository is private. Fine for a course app; a company would use a private registry — which is exactly the production lab's ECR setup.)

Verify: open `https://hub.docker.com/u/YOUR_DOCKERHUB_USERNAME` — both repositories should show the `phase-9` tag.

Reference:

- Docker Hub quickstart: https://docs.docker.com/docker-hub/quickstart/
- Docker Hub access tokens: https://docs.docker.com/security/access-tokens/

## Step 6: Create The Terraform Files

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-09-infrastructure-as-code-terraform/phase-09-terraform-basics
cd deployment/phase-09-infrastructure-as-code-terraform/phase-09-terraform-basics
```

Terraform reads **every `.tf` file in the current folder** and merges them into one configuration. Splitting into multiple files is purely for human readability — `providers.tf`, `variables.tf`, `ec2.tf` could all be one file and Terraform would not care. The names below follow the common community convention.

### providers.tf

```bash
vim providers.tf
```

Paste:

```hcl
terraform {
  required_version = ">= 1.9.0"

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
      Environment = "phase-09-terraform-basics"
      ManagedBy   = "terraform"
    }
  }
}
```

Line explanation:

- The `terraform {}` block configures Terraform itself, not any cloud resource.
- `required_version = ">= 1.9.0"` refuses to run with an older Terraform binary. Without this, a teammate with an outdated version could corrupt shared state with incompatible behavior.
- `required_providers` declares which plugins this configuration needs. A *provider* is the plugin that translates Terraform resources into real API calls — `hashicorp/aws` knows how to call the AWS API.
- `version = "~> 6.0"` is a pessimistic constraint: any 6.x release, but never 7.0. Major provider versions can rename attributes and break configurations, so you pin the major version.
- The `provider "aws" {}` block configures the plugin. `region = var.aws_region` reads the region from a variable instead of hardcoding it.
- `default_tags` applies these three tags to **every resource this provider creates**, without repeating them on each resource. `ManagedBy = "terraform"` is a widely used convention that tells anyone looking at the AWS Console "do not edit this by hand — it will be overwritten."

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

variable "instance_type" {
  description = "EC2 instance type for the app server"
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH access"
  type        = string
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR form (x.x.x.x/32) for SSH access"
  type        = string
}

variable "db_password" {
  description = "PostgreSQL password injected into the app configuration"
  type        = string
  sensitive   = true
}

variable "dockerhub_user" {
  description = "Docker Hub username that owns the pre-built launchboard images"
  type        = string
}

variable "image_tag" {
  description = "Tag of the pre-built launchboard images on Docker Hub"
  type        = string
  default     = "phase-9"
}
```

Line explanation:

- Each `variable` block declares one input. Variables are how the same configuration deploys to different regions, accounts, or environments without editing `.tf` files.
- `type = string` makes Terraform reject wrong-typed values at plan time instead of failing halfway through an apply.
- `instance_type` and `image_tag` have defaults, so they are optional. `aws_region`, `key_name`, `my_ip_cidr`, `db_password`, and `dockerhub_user` have no default, so Terraform requires a value for each (from `terraform.tfvars`, a `-var` flag, or an interactive prompt).
- `sensitive = true` on `db_password` makes Terraform mask the value in plan/apply output (it prints `(sensitive value)` instead). Note this does **not** encrypt it — the value still appears in plain text inside the state file, which is one of the reasons the production lab moves state into a private S3 bucket.
- `dockerhub_user` and `image_tag` together identify the images the server pulls: `YOUR_USER/launchboard-backend:phase-9` and `YOUR_USER/launchboard-frontend:phase-9`, the ones you pushed in Step 5. Later, pushing a new tag and changing `image_tag` here *is* a redeploy — Terraform sees the user data changed and replaces the instance with one running the new version.

### data.tf

```bash
vim data.tf
```

Paste:

```hcl
data "aws_vpc" "default" {
  default = true
}

data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}
```

Line explanation:

- A `data` block **reads** existing infrastructure instead of creating it. `resource` creates; `data` looks up.
- `data "aws_vpc" "default"` finds the default VPC that AWS creates in every region. The security group below needs a VPC ID, and using the default VPC keeps this lab simple (the production lab builds its own VPC).
- `data "aws_ssm_parameter" "ubuntu_ami"` reads a public parameter that Canonical (the Ubuntu publisher) maintains in AWS Systems Manager. It always contains the **current** Ubuntu 24.04 AMI ID for your region. This is better than hardcoding an AMI ID for two reasons: AMI IDs are different in every region (a hardcoded ID breaks the moment someone changes `aws_region`), and Canonical rotates AMIs when patching, so the parameter always points at a patched image.
- Common question: *"my workstation runs a newer Ubuntu — is `24.04` in this path a problem?"* No. This parameter selects the OS for the **instance Terraform creates**, which is completely independent of what your workstation runs — they never need to match. The guide pins 24.04 because it is an LTS release that every third-party apt repository (Docker especially) is guaranteed to support. If you want the instance on a different LTS, list what Canonical publishes and swap the version segment of the path:

```bash
aws ssm get-parameters-by-path \
  --path /aws/service/canonical/ubuntu/server \
  --recursive --query 'Parameters[].Name' --output text | tr '\t' '\n' | cut -d/ -f6 | sort -u
```

### security.tf

```bash
vim security.tf
```

Paste:

```hcl
resource "aws_security_group" "app" {
  name        = "launchboard-phase-9-basics-sg"
  description = "SSH from my IP, HTTP from anywhere"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from my IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

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
    Name = "launchboard-phase-9-basics-sg"
  }
}
```

Line explanation:

- `resource "aws_security_group" "app"` — the first label is the resource **type** (defined by the AWS provider), the second is the **local name** you use to reference it elsewhere (`aws_security_group.app.id`). The local name never appears in AWS.
- `vpc_id = data.aws_vpc.default.id` references the data source from `data.tf`. This line also teaches Terraform the *dependency order*: the VPC lookup must finish before the security group is created. Terraform builds this dependency graph automatically from references — you almost never need to specify ordering by hand.
- The first `ingress` block allows SSH only from `var.my_ip_cidr` — the same "your IP only" rule you configured by hand in every previous phase, now expressed as code.
- The second `ingress` block opens port 80 to the world, because the frontend must be reachable from any browser.
- The `egress` block allows all outbound traffic (`protocol = "-1"` means all protocols). The instance needs outbound access to download Docker packages, clone GitHub, and pull base images. AWS security groups allow all egress by default *when created in the Console*, but Terraform's `aws_security_group` resource removes the default egress rule, so you must declare it explicitly.

### ec2.tf

```bash
vim ec2.tf
```

Paste:

```hcl
resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.app.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user-data.sh.tpl", {
    db_password    = var.db_password
    backend_image  = "${var.dockerhub_user}/launchboard-backend:${var.image_tag}"
    frontend_image = "${var.dockerhub_user}/launchboard-frontend:${var.image_tag}"
  })

  tags = {
    Name = "launchboard-phase-9-basics"
  }
}
```

Line explanation:

- `ami = data.aws_ssm_parameter.ubuntu_ami.value` uses the always-current Ubuntu AMI from the data source.
- `instance_type = var.instance_type` defaults to `t3.small` (2 GB RAM) — enough, because this server only **pulls and runs** prebuilt images. The memory-hungry frontend build already happened on the workstation in Step 5.
- `key_name` attaches the existing key pair so you can SSH in for debugging. Terraform does not create the key pair — it references one that already exists (you created `devops-launchboard-key` in Step 1 or an earlier phase). At boot, AWS injects the key pair's **public** half into `/home/ubuntu/.ssh/authorized_keys`; the private half only ever exists in your downloaded `.pem` file.
- Want Terraform to manage the key too? Add an `aws_key_pair` resource that registers a public key you already have locally, and reference it:

  ```hcl
  resource "aws_key_pair" "app" {
    key_name   = "launchboard-terraform-key"
    public_key = file("~/.ssh/id_ed25519.pub")
  }
  ```

  Then set `key_name = aws_key_pair.app.key_name` in the instance. This uploads only the public key (not a secret), eliminates the regional key-pair-not-found error class, and works well if you generated your key with a local tool (ssh-keygen, MobaXterm's MobaKeyGen, PuTTYgen — export OpenSSH format). What you should **not** do is generate the key inside Terraform with the `tls_private_key` resource: it stores the private key in **plaintext in the state file**, turning your SSH credential into state contents — the same problem as `db_password`, but worse.
- `vpc_security_group_ids = [aws_security_group.app.id]` attaches the security group. Referencing it also tells Terraform to create the security group first.
- `root_block_device` sizes the root disk to 30 GB and encrypts it at rest.
- `user_data` is a script that cloud-init runs **once, on first boot, as root**. `templatefile()` reads `user-data.sh.tpl` and substitutes three placeholders before handing the final script to AWS: the database password and the two full image names, assembled here from `dockerhub_user` and `image_tag`. This is how Terraform passes values from your configuration *into* the instance.
- `${path.module}` is the folder containing the current `.tf` files — safer than a relative path, which would break if you ran Terraform from a different working directory.

### user-data.sh.tpl

```bash
vim user-data.sh.tpl
```

Paste:

```bash
#!/bin/bash
set -eux

# Install Docker from the official repository
apt-get update
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
usermod -aG docker ubuntu

# Discover this instance's public IP from the metadata service (IMDSv2)
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)

# Write the Compose file - images are pre-built and pulled from Docker Hub
mkdir -p /opt/launchboard
cat > /opt/launchboard/docker-compose.yml << COMPOSE
services:
  launchboard-db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: launchboard
      POSTGRES_USER: launchboard_user
      POSTGRES_PASSWORD: ${db_password}
    volumes:
      - launchboard-postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U launchboard_user -d launchboard"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 20s
    restart: unless-stopped

  launchboard-migrate:
    image: ${backend_image}
    command: ["alembic", "upgrade", "head"]
    environment:
      DATABASE_URL: postgresql+asyncpg://launchboard_user:${db_password}@launchboard-db:5432/launchboard
    depends_on:
      launchboard-db:
        condition: service_healthy
    restart: "no"

  launchboard-backend:
    image: ${backend_image}
    environment:
      DATABASE_URL: postgresql+asyncpg://launchboard_user:${db_password}@launchboard-db:5432/launchboard
      APP_NAME: DevOps LaunchBoard API
      APP_ENV: production
      CORS_ORIGINS: http://$PUBLIC_IP
      SEED_DEMO_DATA: "true"
    depends_on:
      launchboard-db:
        condition: service_healthy
      launchboard-migrate:
        condition: service_completed_successfully
    restart: unless-stopped

  launchboard-frontend:
    image: ${frontend_image}
    ports:
      - "80:8080"
    depends_on:
      launchboard-backend:
        condition: service_healthy
    restart: unless-stopped

volumes:
  launchboard-postgres-data:
COMPOSE

# Pull and start the stack
cd /opt/launchboard
docker compose pull
docker compose up -d
```

Line explanation:

- `set -eux` makes the script exit on the first error (`-e`), treat unset variables as errors (`-u`), and print each command before running it (`-x`) — the `-x` trace lands in `/var/log/cloud-init-output.log` on the instance, which is where you debug user data problems (the last `+` line before the log stops is the command that failed).
- The Docker install block is the same official-repository installation used in every previous phase, just non-interactive. `docker-compose-plugin` is included because Compose orchestrates the stack.
- The two `curl 169.254.169.254` calls query the **EC2 instance metadata service** — a link-local endpoint every instance can reach that answers questions about itself. The first call gets a session token (IMDSv2 requires token-based access), the second asks for the instance's own public IP, which becomes the backend's CORS origin. The public IP does not exist until the instance is running, so Terraform cannot substitute it at plan time — the instance discovers it at boot.
- Watch the two kinds of variables. `${db_password}`, `${backend_image}`, and `${frontend_image}` are **Terraform template placeholders** — `templatefile()` already replaced them before the script reached AWS. `$TOKEN` and `$PUBLIC_IP` are ordinary **shell variables**, resolved at boot on the instance. That is also why the heredoc delimiter is deliberately **unquoted** (`<< COMPOSE`, not `<< 'COMPOSE'`): the shell must still expand `$PUBLIC_IP` inside the compose file as it writes it.
- The compose file mirrors the Phase 4 stack, with `image:` lines instead of `build:` — pulled from Docker Hub, nothing compiled here:
  - the database gets a named volume and a `pg_isready` healthcheck;
  - `launchboard-migrate` runs `alembic upgrade head` exactly once (`restart: "no"`), gated on the database being healthy;
  - the backend starts only after the database is healthy **and** the migration completed (`service_completed_successfully`) — the same ordering the Phase 4 compose file taught;
  - the frontend waits for the backend to be healthy — its health status comes from the `HEALTHCHECK` baked into the backend image.
- `docker compose pull` then `up -d`: pulling three images takes well under a minute, so the whole first boot is **about 2 minutes** — compare with 5-6 minutes when images were built on the server.

Security note: user data (including the substituted password) is visible to anyone who can read the instance's metadata or your Terraform state file. Acceptable for a lab; the production lab passes secrets through SSM Parameter Store instead.

### Variation: Clone And Build On Boot Instead

If your repository is public and you prefer not to use a registry at all, the opposite design also works: user data installs Docker, `git clone`s the repository over HTTPS, and runs `docker compose up -d --build` with the Phase 4 compose file — the server builds its own images from source. Trade-offs:

| | Pre-built images (this lab) | Clone and build on boot |
| --- | --- | --- |
| Boot to running app | ~2 min | ~5-6 min |
| Git repository | can stay private | must be publicly readable |
| Registry account | Docker Hub (free) | none |
| App server size | t3.small | t3.medium (the frontend build needs RAM) |
| Classroom risk | Docker Hub pull rate limits behind one NAT | GitHub outage / repo visibility changes |

The production lab supersedes both: images built once on the workstation, pushed to **ECR** (private, IAM-authenticated, no pull limits), pulled by instances via an instance profile.

### outputs.tf

```bash
vim outputs.tf
```

Paste:

```hcl
output "public_ip" {
  description = "Public IP of the app server"
  value       = aws_instance.app.public_ip
}

output "app_url" {
  description = "URL to open in the browser"
  value       = "http://${aws_instance.app.public_ip}"
}

output "ssh_command" {
  description = "Command to SSH into the app server"
  value       = "ssh -i YOUR_KEY.pem ubuntu@${aws_instance.app.public_ip}"
}
```

Outputs are values Terraform prints after `apply` and on demand with `terraform output`. `aws_instance.app.public_ip` is an attribute that only exists after the instance is created — outputs are how you get computed values out of Terraform without digging through the Console.

### terraform.tfvars

```bash
vim terraform.tfvars
```

Paste, replacing the placeholder values (region, key pair name, your IP, a real password, and your Docker Hub username):

```hcl
aws_region     = "us-east-1"
instance_type  = "t3.small"
key_name       = "devops-launchboard-key"
my_ip_cidr     = "YOUR_PUBLIC_IP/32"
db_password    = "CHANGE_ME_STRONG_PASSWORD"
dockerhub_user = "YOUR_DOCKERHUB_USERNAME"
image_tag      = "phase-9"
```

Find your public IP with `curl -s https://checkip.amazonaws.com` (run it on your **local machine**, not the workstation — this must be the IP your SSH connection comes from).

Terraform automatically loads a file named exactly `terraform.tfvars`. Because it contains a real password, it must never be committed — the repository ships `terraform.tfvars.example` as a committed template, the same pattern as `secret.example.yaml` in the Kubernetes phases. Add the real file to `.gitignore` if it is not already covered:

```bash
grep -q "terraform.tfvars" /opt/devops-launchboard/app-source/.gitignore || echo -e "terraform.tfvars\n*.tfstate\n*.tfstate.*\n.terraform/" >> /opt/devops-launchboard/app-source/.gitignore
```

(`.tfstate` files are excluded too — the state file contains every attribute of every resource, including the sensitive ones.)

Reference:

- Terraform configuration syntax: https://developer.hashicorp.com/terraform/language/syntax/configuration
- AWS provider documentation: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- aws_instance resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance
- templatefile function: https://developer.hashicorp.com/terraform/language/functions/templatefile
- Input variables: https://developer.hashicorp.com/terraform/language/values/variables

## Step 7: Initialize

```bash
terraform init
```

Expected output ends with:

```text
Terraform has been successfully initialized!
```

What `init` did:

- Downloaded the AWS provider (~6.x) into a hidden `.terraform/` folder.
- Wrote `.terraform.lock.hcl`, which pins the **exact** provider version and its checksums. Commit this file — it guarantees teammates and CI use the identical provider build.

## Step 8: Format And Validate

```bash
terraform fmt
terraform validate
```

- `terraform fmt` rewrites the `.tf` files into canonical formatting (alignment, spacing). Run it before every commit; most teams enforce it in CI.
- `terraform validate` checks syntax and internal consistency (undeclared variables, bad references) without touching AWS.

Expected:

```text
Success! The configuration is valid.
```

## Step 9: Plan

```bash
terraform plan
```

Read the output carefully — learning to read plans is the core Terraform skill. Key symbols:

| Symbol | Meaning |
| --- | --- |
| `+` | resource will be created |
| `-` | resource will be destroyed |
| `~` | resource will be updated in place |
| `-/+` | resource will be destroyed and recreated |
| `(known after apply)` | value does not exist until the resource is created |

Expected summary line:

```text
Plan: 2 to add, 0 to change, 0 to destroy.
```

Two resources: the security group and the instance. The two `data` sources are lookups, not resources, so they do not count.

## Step 10: Apply

```bash
terraform apply
```

Terraform shows the plan again and prompts:

```text
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

Enter a value:
```

Type `yes`. The apply takes about a minute; the outputs print at the end:

```text
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

app_url = "http://54.XX.XX.XX"
public_ip = "54.XX.XX.XX"
ssh_command = "ssh -i YOUR_KEY.pem ubuntu@54.XX.XX.XX"
```

**Wait about 2 minutes** before opening the URL — the apply finishes when the *instance* exists, but the user data script is still installing Docker and pulling the images from Docker Hub. Then verify:

```bash
APP_IP=$(terraform output -raw public_ip)
curl -s "http://$APP_IP/health" | jq
curl -s "http://$APP_IP/api/summary" | jq
```

Open `http://YOUR_PUBLIC_IP` in the browser — the full LaunchBoard UI should load with demo data.

If it does not come up after 3 minutes, SSH in and read the boot log:

```bash
ssh -i devops-launchboard-key.pem ubuntu@$APP_IP
sudo tail -50 /var/log/cloud-init-output.log
sudo docker ps
```

## Step 11: Understand State

```bash
terraform state list
```

Expected:

```text
data.aws_ssm_parameter.ubuntu_ami
data.aws_vpc.default
aws_security_group.app
aws_instance.app
```

```bash
terraform state show aws_instance.app
```

This prints every attribute Terraform recorded about the instance. The file behind this is `terraform.tfstate` in the current folder — Terraform's memory of what it created. Three facts to internalize:

1. **State maps configuration to reality.** Without state, Terraform would not know that `aws_instance.app` in your files *is* instance `i-0abc...` in AWS.
2. **State contains secrets in plain text** (your `db_password` is in there). Never commit it.
3. **Local state does not scale.** It exists only on this machine; a teammate running `terraform apply` from their machine would try to create everything again. The production lab moves state to S3.

## Step 12: Make A Change And See The Diff

This is the workflow that makes Terraform valuable. Edit the security group description:

```bash
vim security.tf
```

Change the `Name` tag value from `launchboard-phase-9-basics-sg` to `launchboard-phase-9-basics-firewall`, then:

```bash
terraform plan
```

```text
~ update in-place
...
Plan: 0 to add, 1 to change, 0 to destroy.
```

Terraform proposes exactly one in-place tag update — nothing else. Apply it, then change it back and apply again. Every infrastructure change is now: edit file → review plan → apply → commit to Git.

Now see **drift detection**. In the AWS Console, manually add any bogus tag to the security group (EC2 > Security Groups > select it > Tags > add `Hacked = yes`). Then:

```bash
terraform plan
```

Terraform notices reality no longer matches the configuration and proposes removing the tag. Run `terraform apply` and the manual change is reverted. This is why `ManagedBy = "terraform"` matters: hand edits to Terraform-managed resources do not survive.

## Step 13: Destroy

```bash
terraform destroy
```

Terraform lists everything it will delete (2 resources) and prompts for `yes`. After it finishes:

```bash
terraform state list
```

Empty — state and reality both agree that nothing exists. This one-command teardown is also a cost-control superpower: no hunting through the Console for forgotten resources.

## Troubleshooting

### Problem 1: `Error: No valid credential sources found`

Terraform cannot find AWS credentials. Run `aws sts get-caller-identity` — if that also fails, re-run `aws configure`. Terraform uses the same credential chain as the AWS CLI.

### Problem 2: `Error: creating EC2 Instance ... InvalidKeyPair.NotFound`

`key_name` refers to an **EC2 Key Pair object registered in AWS**, not a key file on your machine — and key pairs are strictly regional. This error means the region in `terraform.tfvars` has no key pair with that name. See what actually exists there:

```bash
aws ec2 describe-key-pairs --region YOUR_AWS_REGION --query 'KeyPairs[].KeyName' --output table
```

Fix with whichever case matches:

- **No key pair anywhere** (common if you generated your SSH key locally with MobaXterm's MobaKeyGen, PuTTYgen, or `ssh-keygen` — those create files, not AWS objects): create one in the target region and save the private key:

```bash
aws ec2 create-key-pair --key-name devops-launchboard-key --region YOUR_AWS_REGION \
  --query 'KeyMaterial' --output text > devops-launchboard-key.pem
chmod 400 devops-launchboard-key.pem
```

- **You already have a local key you want to keep using**: import its *public* half so AWS knows it (MobaKeyGen/PuTTYgen users: export the public key in OpenSSH format first):

```bash
aws ec2 import-key-pair --key-name devops-launchboard-key --region YOUR_AWS_REGION \
  --public-key-material fileb://~/.ssh/id_ed25519.pub
```

- **A key pair exists under a different name**: set that name as `key_name` in `terraform.tfvars`.

Then run `terraform apply` again — the security group created before the failure is already in state, so Terraform only retries the instance.

### Problem 3: Apply succeeds but the app never loads

The user data script failed partway. SSH in and check:

```bash
sudo tail -100 /var/log/cloud-init-output.log
```

Common causes, with their log signatures:

- `pull access denied for YOUR_USER/launchboard-backend, repository does not exist or may require 'docker login'` — the `dockerhub_user` in `terraform.tfvars` has a typo, or the images were never pushed (Step 5). Verify at `https://hub.docker.com/u/YOUR_USER` and test from the workstation: `docker pull YOUR_USER/launchboard-backend:phase-9`.
- `toomanyrequests: You have reached your pull rate limit` — Docker Hub limits anonymous pulls per IP, and a classroom behind one NAT shares one IP. Wait for the window to reset, or have each student authenticate the pull (add `docker login` with a token to user data), or move the images to ECR (the production lab's approach, which has no such limit).
- `fatal: could not read Username for 'https://github.com'` — only possible if you switched to the clone-and-build variation with a private repository; make the repository public or return to pre-built images.
- apt/GPG errors early in the script — mirror hiccups; recreating the instance usually clears it.

In every case the fix path is the same: user data only runs on **first boot**, so after fixing the cause, recreate the instance rather than re-applying in place:

```bash
terraform apply -replace=aws_instance.app
```

### Problem 4: `Error acquiring the state lock`

A previous Terraform command crashed and left the local lock. If you are sure no other Terraform process is running:

```bash
terraform force-unlock LOCK_ID_FROM_THE_ERROR
```

### Problem 5: Changed `user-data.sh.tpl` but nothing happens on apply

Terraform sees the user data changed and plans a **destroy-and-recreate** (`-/+`) of the instance, because user data only runs at first boot. If the plan shows no change, you probably edited a part of the template that renders to the same final string. To force recreation explicitly:

```bash
terraform apply -replace=aws_instance.app
```

### Problem 6: SSH connection refused / timeout to the app server

Your current public IP no longer matches `my_ip_cidr` (home IPs rotate). Update `terraform.tfvars` with the new IP and run `terraform apply` — the plan will show one in-place security group rule change.

## Production Checklist

```text
[ ] Terraform installed and terraform version works
[ ] terraform init downloaded the AWS provider
[ ] .terraform.lock.hcl committed
[ ] terraform.tfvars NOT committed (in .gitignore)
[ ] terraform fmt and validate pass
[ ] Both images pushed and visible on hub.docker.com
[ ] Plan reviewed before every apply
[ ] App reachable at the app_url output
[ ] State inspected with terraform state list / show
[ ] A change applied via plan -> apply (not the Console)
[ ] Drift detected and reverted once
[ ] terraform destroy completed
```

## Reference Documentation

| Topic | Link |
| --- | --- |
| Terraform documentation | https://developer.hashicorp.com/terraform/docs |
| Terraform language | https://developer.hashicorp.com/terraform/language |
| AWS provider | https://registry.terraform.io/providers/hashicorp/aws/latest/docs |
| Terraform CLI commands | https://developer.hashicorp.com/terraform/cli/commands |
| State | https://developer.hashicorp.com/terraform/language/state |
| EC2 user data | https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html |
| Instance metadata service | https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html |

## What To Do Next

Move to:

```text
deployment/phase-09-infrastructure-as-code-terraform/phase-09-terraform-production
```

Why:

You now know resources, variables, data sources, outputs, state, plan, apply, and destroy. The production lab applies all of it the way a real company does: a custom VPC with private subnets, images built once and stored in ECR, multiple app servers in an Auto Scaling Group behind an ALB, a managed RDS PostgreSQL database, secrets in SSM Parameter Store, remote state in S3, and everything organized into reusable modules.
