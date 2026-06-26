# Phase 15: Performance And Load Validation

## Fresh Start Assumption

This phase starts from a clean machine and a clean AWS setup.

You do not need to complete any previous phase before using this phase.

This guide assumes:

- You have an AWS account.
- You have GitHub access to this repository.
- You will clone the repository with SSH.
- You will create a new EKS cluster for this phase.
- You will create fresh ECR repositories.
- You will deploy the N-tier application from scratch.
- You will install Metrics Server.
- You will run k6 performance tests.
- You will record final pass/fail results.
- You will use `vim` to create files.
- You will not use custom shell scripts.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What This Phase Deploys

This final phase deploys:

- Vite frontend served by Nginx
- FastAPI backend
- PostgreSQL database in Kubernetes for the lab
- EKS cluster
- ECR repositories
- AWS Load Balancer Controller
- Metrics Server
- Backend HPA
- k6 smoke, baseline, stress, and soak tests
- Final performance report

## When To Use This Architecture

Use this phase when:

- You want a final production-readiness validation.
- You need pass/fail performance gates.
- You want to see whether HPA reacts under load.
- You need to record latency, error rate, pod CPU, pod memory, and scaling.
- You want a go/no-go release decision.

Do not use this phase when:

- The app is not deployed successfully yet.
- You only need local development testing.
- You do not have permission to test the target URL.
- You cannot afford temporary AWS load-test costs.

Important rule:

```text
Only load test systems you own or have permission to test.
```

## Performance Gates

| Test | Gate |
| --- | --- |
| Smoke | p95 latency under 500 ms, error rate under 1 percent |
| Baseline load | p95 under 800 ms, p99 under 1500 ms, error rate under 2 percent |
| Stress | p95 under 2000 ms, error rate under 5 percent |
| Soak | p95 under 1000 ms, error rate under 2 percent |

These are student lab gates. Real production gates depend on the application, users, business rules, and infrastructure budget.

## Architecture

```text
k6
  |
  v
AWS Application Load Balancer
  |
  v
Frontend Nginx pods
  |
  v
FastAPI backend pods
  |
  v
PostgreSQL pod

Metrics Server feeds CPU metrics to HPA.
HPA scales backend pods during higher load.
The final report records whether the deployment is ready.
```

## Step 1: Install Tools

Run from your local machine:

```bash
git --version
ssh -V
docker --version
aws --version
kubectl version --client
eksctl version
helm version
```

Optional:

```bash
k6 version
```

If k6 is not installed locally, use Docker to run k6 in later steps.

Install missing tools:

- Git: https://git-scm.com/downloads
- Docker: https://docs.docker.com/get-docker/
- AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- kubectl: https://kubernetes.io/docs/tasks/tools/
- eksctl: https://eksctl.io/installation/
- Helm: https://helm.sh/docs/intro/install/
- k6: https://grafana.com/docs/k6/latest/set-up/install-k6/

Why this step exists:

The final validation phase uses AWS, Docker, Kubernetes, Helm, and k6. Checking tools first makes the rest of the guide smoother.

## Step 2: Configure AWS

Run:

```bash
aws configure
aws sts get-caller-identity
```

Set variables:

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

Why this step exists:

The AWS CLI uses these credentials and region for EKS, ECR, IAM, load balancer, and node resources.

## Step 3: Create SSH Key And Clone

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-15" -f ~/.ssh/devops_launchboard_phase_15
cat ~/.ssh/devops_launchboard_phase_15.pub
```

Add the public key to GitHub.

Create SSH config:

```bash
vim ~/.ssh/config
```

Paste:

```text
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/devops_launchboard_phase_15
  IdentitiesOnly yes
```

Run:

```bash
chmod 600 ~/.ssh/config
chmod 600 ~/.ssh/devops_launchboard_phase_15
chmod 644 ~/.ssh/devops_launchboard_phase_15.pub
ssh -T git@github.com
```

Clone:

```bash
sudo mkdir -p /opt/devops-launchboard
sudo chown -R $USER:$USER /opt/devops-launchboard
cd /opt/devops-launchboard
git clone git@github.com:ashraful2430/N-tier-application.git app-source
cd app-source
```

Why this step exists:

The machine needs the source code, deployment files, and k6 tests before it can deploy or validate the app.

## Step 4: Create Phase 15 Folders

Run:

```bash
mkdir -p deployment/phase-15-performance-and-load-validation/cluster
mkdir -p deployment/phase-15-performance-and-load-validation/ecr
mkdir -p deployment/phase-15-performance-and-load-validation/app-k8s
mkdir -p deployment/phase-15-performance-and-load-validation/monitoring
mkdir -p deployment/phase-15-performance-and-load-validation/tests/k6
mkdir -p deployment/phase-15-performance-and-load-validation/reports
```

Why these folders exist:

- `cluster` stores EKS cluster configuration.
- `ecr` stores image cleanup policy.
- `app-k8s` stores app manifests.
- `monitoring` stores metrics setup values.
- `tests/k6` stores performance tests.
- `reports` stores the final performance report.

## Step 5: Create EKS Cluster

Create:

```bash
vim deployment/phase-15-performance-and-load-validation/cluster/eksctl-cluster.yaml
```

Paste:

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: devops-launchboard-phase-15
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
      Environment: phase-15
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

Replace `YOUR_AWS_REGION`, then run:

```bash
eksctl create cluster -f deployment/phase-15-performance-and-load-validation/cluster/eksctl-cluster.yaml
kubectl get nodes
```

Why this file exists:

This creates the environment where final validation runs. A repeatable cluster makes performance results easier to compare.

## Step 6: Create ECR And Images

Create repositories:

```bash
aws ecr create-repository --repository-name launchboard-backend --region $AWS_REGION
aws ecr create-repository --repository-name launchboard-frontend --region $AWS_REGION
```

Create lifecycle policy:

```bash
vim deployment/phase-15-performance-and-load-validation/ecr/lifecycle-policy.json
```

Paste:

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep the latest 10 phase 15 images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["phase-15"],
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
aws ecr put-lifecycle-policy --repository-name launchboard-backend --lifecycle-policy-text file://deployment/phase-15-performance-and-load-validation/ecr/lifecycle-policy.json --region $AWS_REGION
aws ecr put-lifecycle-policy --repository-name launchboard-frontend --lifecycle-policy-text file://deployment/phase-15-performance-and-load-validation/ecr/lifecycle-policy.json --region $AWS_REGION
```

Create Docker files with `vim`:

```bash
vim deployment/phase-15-performance-and-load-validation/Dockerfile.backend
vim deployment/phase-15-performance-and-load-validation/Dockerfile.frontend
vim deployment/phase-15-performance-and-load-validation/nginx-frontend.conf
```

Use the production file contents stored in this phase folder.

Build and push:

```bash
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

docker build -f deployment/phase-15-performance-and-load-validation/Dockerfile.backend -t launchboard-backend:phase-15 .
docker build -f deployment/phase-15-performance-and-load-validation/Dockerfile.frontend --build-arg VITE_API_URL=/api -t launchboard-frontend:phase-15 .

docker tag launchboard-backend:phase-15 $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-15
docker tag launchboard-frontend:phase-15 $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-frontend:phase-15

docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-15
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-frontend:phase-15
```

Why this step exists:

Final load validation should test production-style images, not development servers.

## Step 7: Deploy The App

Create the files in:

```text
deployment/phase-15-performance-and-load-validation/app-k8s
```

Use the app manifests stored in this phase folder. Prepare secret:

```bash
cd deployment/phase-15-performance-and-load-validation/app-k8s
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
kubectl apply -f deployment/phase-15-performance-and-load-validation/app-k8s/secret.yaml
kubectl apply -k deployment/phase-15-performance-and-load-validation/app-k8s
kubectl -n devops-launchboard get pods
```

Why this step exists:

The tests need a full deployed app path: frontend, backend, database, ingress, HPA, health checks, and persistent storage.

## Step 8: Install AWS Load Balancer Controller

Run:

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

eksctl create iamserviceaccount \
  --cluster devops-launchboard-phase-15 \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --role-name devops-launchboard-phase-15-alb-controller \
  --attach-policy-arn arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess \
  --approve

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=devops-launchboard-phase-15 \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

Get public URL:

```bash
kubectl -n devops-launchboard get ingress launchboard-ingress
export BASE_URL=http://YOUR_ALB_DNS_NAME
```

Why this step exists:

k6 should test the same public route that users will use.

## Step 9: Install Metrics Server

Create:

```bash
vim deployment/phase-15-performance-and-load-validation/monitoring/metrics-server-values.yaml
```

Paste:

```yaml
args:
  - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
  - --kubelet-use-node-status-port
  - --metric-resolution=15s
```

Install:

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  -f deployment/phase-15-performance-and-load-validation/monitoring/metrics-server-values.yaml
```

Verify:

```bash
kubectl top nodes
kubectl -n devops-launchboard top pods
kubectl -n devops-launchboard get hpa
```

Why this step exists:

Metrics Server provides the CPU data that HPA uses to scale backend pods.

## Step 10: Create k6 Test Files

Create:

```bash
vim deployment/phase-15-performance-and-load-validation/tests/k6/01-smoke.js
vim deployment/phase-15-performance-and-load-validation/tests/k6/02-baseline-load.js
vim deployment/phase-15-performance-and-load-validation/tests/k6/03-stress.js
vim deployment/phase-15-performance-and-load-validation/tests/k6/04-soak.js
```

Use the full test file contents stored in this phase folder.

Why these files exist:

- `01-smoke.js` proves the app works before load begins.
- `02-baseline-load.js` checks expected traffic.
- `03-stress.js` finds the limit.
- `04-soak.js` checks stability over time.

## Step 11: Run Smoke Test

Run:

```bash
docker run --rm -i \
  -e BASE_URL=$BASE_URL \
  -v "$PWD:/workspace" \
  grafana/k6:latest run /workspace/deployment/phase-15-performance-and-load-validation/tests/k6/01-smoke.js
```

Expected:

```text
checks pass
http_req_failed below 1 percent
p95 below 500 ms
```

Why this step exists:

Smoke test is the gate before heavier tests. If smoke fails, stop and fix the app.

## Step 12: Run Baseline Load Test

Run:

```bash
docker run --rm -i \
  -e BASE_URL=$BASE_URL \
  -v "$PWD:/workspace" \
  grafana/k6:latest run /workspace/deployment/phase-15-performance-and-load-validation/tests/k6/02-baseline-load.js
```

Watch in another terminal:

```bash
kubectl -n devops-launchboard get hpa -w
```

Why this step exists:

Baseline load proves the app can handle expected traffic before you push it harder.

## Step 13: Run Stress Test

Run:

```bash
docker run --rm -i \
  -e BASE_URL=$BASE_URL \
  -v "$PWD:/workspace" \
  grafana/k6:latest run /workspace/deployment/phase-15-performance-and-load-validation/tests/k6/03-stress.js
```

Why this step exists:

Stress testing tells you where the app starts to struggle. The goal is not just passing. The goal is learning the limit.

## Step 14: Run Soak Test

Run:

```bash
docker run --rm -i \
  -e BASE_URL=$BASE_URL \
  -v "$PWD:/workspace" \
  grafana/k6:latest run /workspace/deployment/phase-15-performance-and-load-validation/tests/k6/04-soak.js
```

Why this step exists:

Soak testing checks whether the app remains stable over time instead of slowly degrading.

## Step 15: Capture Kubernetes Metrics

Run during tests:

```bash
kubectl -n devops-launchboard top pods
kubectl -n devops-launchboard get hpa
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard logs deploy/launchboard-backend --tail=50
```

Record:

```text
backend pod count
backend CPU
backend memory
database CPU and memory
pod restarts
HPA scaling behavior
```

Why this step exists:

k6 shows user-facing performance. Kubernetes metrics show how the platform behaves internally.

## Step 16: Complete Final Report

Create:

```bash
vim deployment/phase-15-performance-and-load-validation/reports/final-performance-report.md
```

Use the report template stored in this phase folder.

Make a final decision:

```text
GO
  The deployment passed the gates.

NO-GO
  The deployment failed one or more gates and needs tuning.
```

Why this step exists:

Performance validation must end with a decision. A report helps students explain why the app is ready or not ready.

## Troubleshooting

Problem: k6 cannot reach the app.

Check:

```bash
kubectl -n devops-launchboard get ingress
curl -I $BASE_URL
curl -I $BASE_URL/health
```

Problem: HPA does not scale.

Check:

```bash
kubectl top nodes
kubectl -n devops-launchboard top pods
kubectl -n devops-launchboard describe hpa launchboard-backend
```

Problem: latency is too high.

Check:

```bash
kubectl -n devops-launchboard top pods
kubectl -n devops-launchboard logs deploy/launchboard-backend --tail=100
kubectl -n devops-launchboard describe pod POD_NAME
```

Problem: error rate is too high.

Action:

```text
Stop the test.
Record the failure point.
Check logs and pod resources.
Tune resources or replicas.
Run the test again.
```

## Cleanup

Delete app:

```bash
kubectl delete -f deployment/phase-15-performance-and-load-validation/app-k8s/secret.yaml
kubectl delete -k deployment/phase-15-performance-and-load-validation/app-k8s
```

Delete cluster:

```bash
eksctl delete cluster -f deployment/phase-15-performance-and-load-validation/cluster/eksctl-cluster.yaml
```

Delete ECR repositories:

```bash
aws ecr delete-repository --repository-name launchboard-backend --force --region $AWS_REGION
aws ecr delete-repository --repository-name launchboard-frontend --force --region $AWS_REGION
```

Why cleanup matters:

EKS, EC2, EBS, ALB, ECR, logs, and load-test traffic can all create charges.

## Final Production Checklist

```text
[ ] EKS cluster created
[ ] ECR images pushed
[ ] App deployed
[ ] ALB available
[ ] Metrics Server installed
[ ] HPA visible
[ ] Smoke test passed
[ ] Baseline load test passed
[ ] Stress test completed
[ ] Soak test completed
[ ] p95 latency recorded
[ ] p99 latency recorded
[ ] Error rate recorded
[ ] HPA behavior recorded
[ ] Pod restarts checked
[ ] Backend logs checked
[ ] Database resource behavior checked
[ ] Final report completed
[ ] GO or NO-GO decision written
[ ] Cleanup completed
```

## Reference Documentation

| Topic | Official Link |
| --- | --- |
| k6 | https://grafana.com/docs/k6/latest/ |
| k6 thresholds | https://grafana.com/docs/k6/latest/using-k6/thresholds/ |
| Metrics Server | https://github.com/kubernetes-sigs/metrics-server |
| Kubernetes HPA | https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/ |
| EKS | https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html |
| ECR | https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html |
| AWS Load Balancer Controller | https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/ |

## What To Do Next

Review every deployment phase and choose the architecture that matches the project:

```text
Small learning app: bare metal or Docker Compose
Container learning: Docker or Docker Swarm
Kubernetes learning: local Kubernetes or EKS
Team production workflow: CI/CD, security, observability, and disaster recovery
Final readiness: performance and load validation
```
