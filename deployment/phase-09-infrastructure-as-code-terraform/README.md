# Phase 9: Infrastructure As Code With Terraform

This phase teaches Terraform in two stages, the same way Phase 7 splits CI/CD into two labs:

```text
deployment/phase-09-infrastructure-as-code-terraform/
+-- phase-09-terraform-basics/          (start here)
+-- phase-09-terraform-production/      (do this second)
```

## Which One Should You Do?

| | terraform-basics | terraform-production |
| --- | --- | --- |
| Goal | Learn Terraform fundamentals | Deploy like a real company |
| Infrastructure | 1 EC2 instance in the default VPC | Custom VPC, ALB, Auto Scaling Group, RDS |
| App runs on | Docker Compose on one instance | Docker containers on multiple instances behind a load balancer |
| Database | PostgreSQL container | Amazon RDS PostgreSQL (managed) |
| Images | Built on the instance from source | Built once, pushed to ECR, pulled by every instance |
| State | Local `terraform.tfstate` file | Remote state in S3 with locking |
| Structure | Flat `.tf` files in one folder | Reusable modules |
| Cost while running | ~$0.02/hour | ~$0.15/hour |

Do `phase-09-terraform-basics` first. Every concept in the production lab (modules, remote state, data sources, `templatefile`, `depends_on`) builds on what the basics lab teaches.

## Why Terraform After Eight Phases Of Manual Work?

In phases 1 through 8 you clicked through the AWS Console to create EC2 instances and security groups, and you typed `eksctl` and `aws` commands to create clusters and repositories. That works, but:

- Nothing is repeatable. Rebuilding an environment means re-doing every click and command in the right order from memory or from a README.
- Nothing is reviewable. There is no diff, no pull request, no approval before infrastructure changes.
- Nothing is documented by default. The infrastructure exists, but the only record of *why* it looks the way it does is in people's heads.
- Drift is invisible. If someone changes a security group by hand, nobody knows.

Terraform fixes all four: infrastructure is declared in files, changes are planned before they are applied (`terraform plan` is the diff), the files live in Git next to the app code, and `terraform plan` against a live environment reveals drift.

## What To Do Next

After completing both labs, move to Phase 10 (Configuration Management With Ansible) — Terraform creates the machines, Ansible configures what runs *inside* them. The two tools are complementary, and real companies use them together.
