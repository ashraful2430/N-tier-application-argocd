# Phase 2: Bare-Metal EC2 Deployment

## Easy Explanation

This phase teaches what containers and orchestrators normally hide: Linux packages, users, directories, systemd units, Nginx reverse proxying, firewall rules, PostgreSQL setup, and TLS certificates.

## What This Phase Teaches

- How this deployment style works in real production teams.
- Which files control infrastructure, application runtime, networking, and verification.
- How to validate success with simple commands instead of guessing.
- How to clean up resources so students do not create surprise bills.

## Files In This Phase

`setup-ec2.sh` prepares the server, `install-dependencies.sh` installs runtime dependencies, `systemd/` contains Linux services, `nginx/default.conf` routes traffic, and `ssl-setup.sh` enables HTTPS.

## Prerequisites

Complete `../phase-0-setup/prerequisites.md` first. Replace `[PROJECT_NAME]`, `[REGION]`, `[AWS_ACCOUNT_ID]`, `[DOMAIN_NAME]`, `[EMAIL]`, `[IMAGE_TAG]`, and `[DB_PASSWORD]` before running commands that use them.

## Cost And Free-Tier Notes

Creates EC2 and possibly EBS charges. A small Ubuntu instance can fit free-tier rules only if the AWS account is eligible and the instance type/storage stay within limits.

Always use AWS Budgets for cloud labs: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html

## Step-By-Step Commands

```bash
cd deployment/phase-2-bare-metal
sudo ./setup-ec2.sh [DOMAIN_NAME] [EMAIL]
sudo ./install-dependencies.sh
sudo cp systemd/*.service /etc/systemd/system/
sudo cp nginx/default.conf /etc/nginx/sites-available/default
sudo systemctl daemon-reload
sudo systemctl enable --now launchboard-backend launchboard-frontend
sudo nginx -t
sudo systemctl reload nginx
sudo ./ssl-setup.sh [DOMAIN_NAME] [EMAIL]
```

## Expected Output

`systemctl status launchboard-backend` shows `active (running)`, `nginx -t` reports successful syntax, and `curl https://[DOMAIN_NAME]/health` returns a healthy API response.

## Verification Checklist

- Required files exist in this phase directory.
- Secrets are not committed with real values.
- Health checks pass before moving to the next phase.
- Logs show normal startup with no repeated crash loops.
- Cloud resources, if any, have project and owner tags.

## Troubleshooting

If `/ready` fails, PostgreSQL or `DATABASE_URL` is wrong. If the frontend loads but API calls fail, check Nginx proxy routes and `CORS_ORIGINS`. If SSL fails, verify DNS points to the EC2 public IP.

Useful first commands:

```bash
curl -fsS http://localhost:8000/health
curl -fsS http://localhost:8000/ready
kubectl get pods -A
docker ps
```


## Useful URLs

- FastAPI deployment guide: https://fastapi.tiangolo.com/deployment/
- Docker documentation: https://docs.docker.com/
- Docker Compose documentation: https://docs.docker.com/compose/
- Kubernetes documentation: https://kubernetes.io/docs/
- Terraform AWS provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- AWS EKS user guide: https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html


## Cleanup

Stop containers, delete Kubernetes resources, or destroy Terraform-managed cloud resources when the lab is done. Confirm the AWS Billing dashboard does not show unexpected running resources.

## Next Step

After students understand manual deployment pain, move to Phase 3 and show how Docker packages the runtime.
