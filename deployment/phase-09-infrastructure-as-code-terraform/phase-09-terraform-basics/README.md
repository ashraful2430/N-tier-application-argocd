# Phase 14 (Part 1): Terraform Basics

## Fresh Start Assumption

This phase starts from a clean AWS environment and a clean Ubuntu workstation.

You do not need to complete any previous phase before using this guide.

This guide assumes:

- You have an AWS account with permissions to create EC2, VPC, and IAM resources.
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
                            - clones the repo
                            - writes .env
                            - docker compose up -d --build
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

The `phase-14-terraform-production` lab fixes all three.

## Cost Warning

| Resource | Approximate Cost |
| --- | --- |
| 1 × t3.medium | ~$0.04/hour |
| 30 GB gp3 EBS | ~$0.003/hour |

Running for 8 hours costs well under $1. Run `terraform destroy` after each session.

## Files Included In This Phase

```text
deployment/phase-14-infrastructure-as-code-terraform/phase-14-terraform-basics/
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
| Name | `devops-launchboard-phase-14-workstation` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` |
| Storage | 20 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | SSH port 22, your IP only |

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
- If `sudo apt update` fails with a GPG or "clearsigned file" error (the same class of problem as the Helm apt repo in Phase 9), fall back to the direct binary download:

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

Create GitHub SSH key:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-14" -f ~/.ssh/devops_launchboard_github_key
cat ~/.ssh/devops_launchboard_github_key.pub
```

Add it to GitHub as a read-only deploy key (repository > Settings > Deploy keys > Add deploy key, leave "Allow write access" unchecked).

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

Secure and test:

```bash
chmod 600 ~/.ssh/config ~/.ssh/devops_launchboard_github_key
chmod 644 ~/.ssh/devops_launchboard_github_key.pub
ssh -T git@github.com
```

Clone:

```bash
sudo mkdir -p /opt/devops-launchboard
sudo chown -R ubuntu:ubuntu /opt/devops-launchboard
cd /opt/devops-launchboard
git clone git@github.com:ashraful2430/N-tier-application.git app-source
cd app-source
```

Reference:

- Generate an SSH key: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent
- GitHub deploy keys: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys#deploy-keys

## Step 5: Create The Terraform Files

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-14-infrastructure-as-code-terraform/phase-14-terraform-basics
cd deployment/phase-14-infrastructure-as-code-terraform/phase-14-terraform-basics
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
      Environment = "phase-14-terraform-basics"
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
  default     = "t3.medium"
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
  description = "PostgreSQL password injected into the app .env file"
  type        = string
  sensitive   = true
}
```

Line explanation:

- Each `variable` block declares one input. Variables are how the same configuration deploys to different regions, accounts, or environments without editing `.tf` files.
- `type = string` makes Terraform reject wrong-typed values at plan time instead of failing halfway through an apply.
- `instance_type` has a `default`, so it is optional. `aws_region`, `key_name`, `my_ip_cidr`, and `db_password` have no default, so Terraform requires a value for them (from `terraform.tfvars`, a `-var` flag, or an interactive prompt).
- `sensitive = true` on `db_password` makes Terraform mask the value in plan/apply output (it prints `(sensitive value)` instead). Note this does **not** encrypt it — the value still appears in plain text inside the state file, which is one of the reasons the production lab moves state into a private S3 bucket.

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

### security.tf

```bash
vim security.tf
```

Paste:

```hcl
resource "aws_security_group" "app" {
  name        = "launchboard-phase-14-basics-sg"
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
    Name = "launchboard-phase-14-basics-sg"
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
    db_password = var.db_password
  })

  tags = {
    Name = "launchboard-phase-14-basics"
  }
}
```

Line explanation:

- `ami = data.aws_ssm_parameter.ubuntu_ami.value` uses the always-current Ubuntu AMI from the data source.
- `instance_type = var.instance_type` defaults to `t3.medium` (4 GB RAM). The frontend's `npm run build` inside `docker compose up --build` needs more memory than a `t3.small` (2 GB) reliably provides.
- `key_name` attaches the existing key pair so you can SSH in for debugging. Terraform does not create the key pair — it references one that already exists (you created `devops-launchboard-key` in Step 1 or an earlier phase).
- `vpc_security_group_ids = [aws_security_group.app.id]` attaches the security group. Referencing it also tells Terraform to create the security group first.
- `root_block_device` sizes the root disk to 30 GB (Docker images and build caches need more than the 8 GB default) and encrypts it at rest.
- `user_data` is a script that cloud-init runs **once, on first boot, as root**. `templatefile()` reads `user-data.sh.tpl` and substitutes every `${db_password}` placeholder with the variable's value before handing the final script to AWS. This is how Terraform passes values from your configuration *into* the instance.
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
apt-get install -y ca-certificates curl git
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker ubuntu

# Discover this instance's public IP from the metadata service (IMDSv2)
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)

# Clone the app and configure the Compose environment
git clone https://github.com/ashraful2430/N-tier-application.git /opt/launchboard
cd /opt/launchboard/deployment/phase-04-docker-compose
cp .env.example .env
sed -i "s|CHANGE_ME_STRONG_PASSWORD|${db_password}|g" .env
sed -i "s|http://YOUR_EC2_PUBLIC_IP|http://$PUBLIC_IP|g" .env

# Build and start the full stack
docker compose up -d --build
```

Line explanation:

- `set -eux` makes the script exit on the first error (`-e`), treat unset variables as errors (`-u`), and print each command before running it (`-x`) — the `-x` output lands in `/var/log/cloud-init-output.log` on the instance, which is where you debug user data problems.
- The Docker install block is the same official-repository installation used in every previous phase, just non-interactive.
- The two `curl 169.254.169.254` calls query the **EC2 instance metadata service** — a link-local endpoint every instance can reach that answers questions about itself. The first call gets a session token (IMDSv2 requires token-based access), the second asks for the instance's own public IP. This matters because the public IP does not exist until the instance is running, so Terraform cannot substitute it at plan time — the instance must discover it at boot time.
- `${db_password}` (note: no `$` escape) is a **Terraform template placeholder**, substituted by `templatefile()` before the script ever reaches the instance. `$TOKEN` and `$PUBLIC_IP` are ordinary **shell variables**, resolved at boot time on the instance. `templatefile()` only substitutes `${...}` expressions that match its variable map; plain `$NAME` shell syntax passes through untouched.
- The clone uses HTTPS (not SSH) because this fresh instance has no GitHub deploy key. HTTPS works for public repositories with no credentials.
- The two `sed` commands fill in the same two `.env` placeholders you edited by hand in Phase 4: the database password and the CORS origin.
- `docker compose up -d --build` builds the backend and frontend images from source on the instance and starts all four services (db, migrate, backend, frontend). The first boot takes 4 to 6 minutes because of the image builds.

Security note: user data (including the substituted password) is visible to anyone who can read the instance's metadata or your Terraform state file. Acceptable for a lab; the production lab passes secrets through SSM Parameter Store instead.

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

Paste, replacing all three placeholder values:

```hcl
aws_region    = "us-east-1"
instance_type = "t3.medium"
key_name      = "devops-launchboard-key"
my_ip_cidr    = "YOUR_PUBLIC_IP/32"
db_password   = "CHANGE_ME_STRONG_PASSWORD"
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

## Step 6: Initialize

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

## Step 7: Format And Validate

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

## Step 8: Plan

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

## Step 9: Apply

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

**Wait 4 to 6 minutes** before opening the URL — the apply finishes when the *instance* exists, but the user data script is still installing Docker and building the app images. Then verify:

```bash
APP_IP=$(terraform output -raw public_ip)
curl -s "http://$APP_IP/health" | jq
curl -s "http://$APP_IP/api/summary" | jq
```

Open `http://YOUR_PUBLIC_IP` in the browser — the full LaunchBoard UI should load with demo data.

If it does not come up after 6 minutes, SSH in and read the boot log:

```bash
ssh -i devops-launchboard-key.pem ubuntu@$APP_IP
sudo tail -50 /var/log/cloud-init-output.log
sudo docker ps
```

## Step 10: Understand State

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

## Step 11: Make A Change And See The Diff

This is the workflow that makes Terraform valuable. Edit the security group description:

```bash
vim security.tf
```

Change the `Name` tag value from `launchboard-phase-14-basics-sg` to `launchboard-phase-14-basics-firewall`, then:

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

## Step 12: Destroy

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

The `key_name` in `terraform.tfvars` does not exist **in the region you are deploying to**. Key pairs are regional. Check EC2 Console > Key Pairs in your target region, or create one there and update the variable.

### Problem 3: Apply succeeds but the app never loads

The user data script failed partway. SSH in and check:

```bash
sudo tail -100 /var/log/cloud-init-output.log
```

Common causes: GitHub unreachable (check the repository is public), Docker build out of memory (use `t3.medium`, not `t3.small`), or apt mirror hiccups (rerun the script section by hand or `terraform destroy` and `apply` again — user data only runs on first boot, so fixing it means recreating the instance: `terraform apply -replace=aws_instance.app`).

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
deployment/phase-14-infrastructure-as-code-terraform/phase-14-terraform-production
```

Why:

You now know resources, variables, data sources, outputs, state, plan, apply, and destroy. The production lab applies all of it the way a real company does: a custom VPC with private subnets, images built once and stored in ECR, multiple app servers in an Auto Scaling Group behind an ALB, a managed RDS PostgreSQL database, secrets in SSM Parameter Store, remote state in S3, and everything organized into reusable modules.
