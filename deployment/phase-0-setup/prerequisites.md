# Prerequisites

Install Docker Engine 25+, Docker Compose v2, Git, Bash, curl, jq, Node.js 22 LTS, Python 3.12, kubectl, Helm 3, Terraform 1.8+, AWS CLI v2, eksctl, and Trivy.

Use a sandbox AWS account with AWS Budgets enabled. The lab IAM principal needs scoped permissions for EC2, ECR, EKS, IAM role creation, ELB, VPC, S3, CloudWatch, Secrets Manager, and KMS resources used by these phases.

```bash
export PROJECT_NAME=devops-launchboard
export AWS_REGION=[REGION]
export AWS_ACCOUNT_ID=[AWS_ACCOUNT_ID]
export DOMAIN_NAME=[DOMAIN_NAME]
export ADMIN_EMAIL=[EMAIL]
```

Use immutable image tags, preferably Git SHA values. Store passwords in a secret manager and never commit real secrets.
