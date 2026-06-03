# Phase 13: Performance And Load Validation

## Fresh Start Assumption

This phase starts from a clean machine and a clean AWS setup.

You do not need to finish any previous phase before using this phase.

This guide assumes:

- You have an AWS account.
- You have GitHub access to this repository.
- You will clone the repository with SSH.
- You will create a new EKS cluster for this phase.
- You will create fresh ECR repositories.
- You will build and push fresh Docker images.
- You will deploy the application to Kubernetes.
- You will install Metrics Server so HPA and `kubectl top` work.
- You will run k6 smoke, load, stress, and soak tests.
- You will write a short performance report.
- You will use `vim` to create files.
- You will not use custom shell scripts.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What This Phase Deploys

This phase deploys the N-tier application on Amazon EKS and validates it under controlled traffic.

The deployment includes:

- Vite frontend served by Nginx
- FastAPI backend
- PostgreSQL database running inside Kubernetes for the lab
- Amazon ECR repositories
- Amazon EKS cluster
- AWS Load Balancer Controller
- Metrics Server
- HorizontalPodAutoscaler
- k6 performance tests
- Performance report template

## When To Use This Architecture

Use this phase when:

- The app is already deployable and you need to prove it can handle traffic.
- You want students to understand smoke, load, stress, and soak tests.
- You need to validate backend HPA behavior.
- You want to find bottlenecks before a production launch.
- You want a repeatable performance report.

Do not use this phase when:

- You only need a quick local demo.
- You do not have a stable deployed app yet.
- You cannot afford temporary AWS load-test resources.
- You are testing someone else's public service without permission.

Important production idea:

Performance testing is not only about high traffic. It is about proving what the system can handle, where it fails, and whether it recovers cleanly.

## Test Types

| Test | Purpose | Example |
| --- | --- | --- |
| Smoke test | Proves the app basically works | 1 user for 30 seconds |
| Load test | Proves expected traffic works | 20 users for several minutes |
| Stress test | Finds the breaking point | Increase to 100 users |
| Soak test | Finds slow leaks over time | 15 users for 30 minutes |

## Recommended AWS Setup

| Item | Recommended Value |
| --- | --- |
| AWS Region | `ap-southeast-1` or closest region |
| Cluster Name | `devops-launchboard-phase-13` |
| Kubernetes Version | `1.34` |
| Node Type | `t3.medium` |
| Desired Nodes | `2` |
| ECR Backend Repo | `launchboard-backend` |
| ECR Frontend Repo | `launchboard-frontend` |
| Load Tool | k6 |

Cost warning:

- EKS costs money.
- EC2 worker nodes cost money.
- Load balancers cost money.
- EBS volumes cost money.
- Load testing can increase data transfer and log volume.
- Delete resources after practice.

Reference:

- EKS pricing: https://aws.amazon.com/eks/pricing/
- AWS Budgets: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html

## Architecture

```text
k6 load generator
  |
  v
AWS Application Load Balancer
  |
  v
Frontend Nginx pods
  |
  | /api, /health, /ready
  v
FastAPI backend pods
  |
  v
PostgreSQL pod and EBS-backed PVC

Metrics Server
  |
  v
HPA scales backend pods when CPU rises
```

## Step 1: Install Local Tools

Run from: your local machine

```bash
git --version
ssh -V
docker --version
aws --version
kubectl version --client
eksctl version
helm version
```

Optional local k6 check:

```bash
k6 version
```

If k6 is not installed, you can run it with Docker later.

Install missing tools:

- Git: https://git-scm.com/downloads
- Docker: https://docs.docker.com/get-docker/
- AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- kubectl: https://kubernetes.io/docs/tasks/tools/
- eksctl: https://eksctl.io/installation/
- Helm: https://helm.sh/docs/intro/install/
- k6: https://grafana.com/docs/k6/latest/set-up/install-k6/

Why this step exists:

The deployment uses AWS, Docker, Kubernetes, Helm, and k6. Checking tools first prevents students from reaching the middle of the guide and discovering a missing command.

## Step 2: Configure AWS

Run:

```bash
aws configure
aws sts get-caller-identity
```

Set variables:

```bash
export AWS_REGION=ap-southeast-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

Why this step exists:

AWS CLI needs credentials before it can create EKS, ECR, IAM, and load balancer resources. The variables keep the later commands shorter.

## Step 3: Create SSH Key And Clone

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-13" -f ~/.ssh/devops_launchboard_phase_13
cat ~/.ssh/devops_launchboard_phase_13.pub
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
  IdentityFile ~/.ssh/devops_launchboard_phase_13
  IdentitiesOnly yes
```

Run:

```bash
chmod 600 ~/.ssh/config
chmod 600 ~/.ssh/devops_launchboard_phase_13
chmod 644 ~/.ssh/devops_launchboard_phase_13.pub
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

The source code and deployment files must exist locally before images can be built or tests can be created.

## Step 4: Create Phase 13 Folders

Run:

```bash
mkdir -p deployment/phase-13-performance-and-load-validation/cluster
mkdir -p deployment/phase-13-performance-and-load-validation/ecr
mkdir -p deployment/phase-13-performance-and-load-validation/app-k8s
mkdir -p deployment/phase-13-performance-and-load-validation/monitoring
mkdir -p deployment/phase-13-performance-and-load-validation/tests/k6
mkdir -p deployment/phase-13-performance-and-load-validation/reports
```

Why these folders exist:

- `cluster` stores the EKS cluster file.
- `ecr` stores the ECR lifecycle policy.
- `app-k8s` stores Kubernetes app files.
- `monitoring` stores Metrics Server values.
- `tests/k6` stores load test definitions.
- `reports` stores performance report templates and final results.

## Step 5: Create EKS Cluster File

Create:

```bash
vim deployment/phase-13-performance-and-load-validation/cluster/eksctl-cluster.yaml
```

Paste:

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: devops-launchboard-phase-13
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
      Environment: phase-13
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
eksctl create cluster -f deployment/phase-13-performance-and-load-validation/cluster/eksctl-cluster.yaml
kubectl get nodes
```

Why this file exists:

Performance tests need a real deployment environment. The cluster file creates a repeatable EKS environment with worker nodes, private networking, control plane logs, and EBS support.

## Step 6: Create ECR And Build Images

Create repositories:

```bash
aws ecr create-repository --repository-name launchboard-backend --region $AWS_REGION
aws ecr create-repository --repository-name launchboard-frontend --region $AWS_REGION
```

Create lifecycle policy:

```bash
vim deployment/phase-13-performance-and-load-validation/ecr/lifecycle-policy.json
```

Paste:

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep the latest 10 phase 13 images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["phase-13"],
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

Apply lifecycle policy:

```bash
aws ecr put-lifecycle-policy --repository-name launchboard-backend --lifecycle-policy-text file://deployment/phase-13-performance-and-load-validation/ecr/lifecycle-policy.json --region $AWS_REGION
aws ecr put-lifecycle-policy --repository-name launchboard-frontend --lifecycle-policy-text file://deployment/phase-13-performance-and-load-validation/ecr/lifecycle-policy.json --region $AWS_REGION
```

Create Dockerfiles:

```bash
vim deployment/phase-13-performance-and-load-validation/Dockerfile.backend
vim deployment/phase-13-performance-and-load-validation/Dockerfile.frontend
vim deployment/phase-13-performance-and-load-validation/nginx-frontend.conf
```

Use the production file contents from this phase folder.

Build and push:

```bash
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

docker build -f deployment/phase-13-performance-and-load-validation/Dockerfile.backend -t launchboard-backend:phase-13 .
docker build -f deployment/phase-13-performance-and-load-validation/Dockerfile.frontend --build-arg VITE_API_URL=/api -t launchboard-frontend:phase-13 .

docker tag launchboard-backend:phase-13 $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-13
docker tag launchboard-frontend:phase-13 $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-frontend:phase-13

docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-13
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-frontend:phase-13
```

Why this step exists:

Load tests should run against production-style containers, not local development servers. ECR stores those containers so EKS can pull them.

## Step 7: Deploy The Application

Create app files in:

```text
deployment/phase-13-performance-and-load-validation/app-k8s
```

Use the files in this phase folder:

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

Prepare secret:

```bash
cd deployment/phase-13-performance-and-load-validation/app-k8s
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
kubectl apply -f deployment/phase-13-performance-and-load-validation/app-k8s/secret.yaml
kubectl apply -k deployment/phase-13-performance-and-load-validation/app-k8s
kubectl -n devops-launchboard get pods
```

Why this step exists:

The load test needs a complete app path: ALB, frontend, backend, database, service discovery, health checks, and HPA.

## Step 8: Install AWS Load Balancer Controller

Run:

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

eksctl create iamserviceaccount \
  --cluster devops-launchboard-phase-13 \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --role-name devops-launchboard-phase-13-alb-controller \
  --attach-policy-arn arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess \
  --approve

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=devops-launchboard-phase-13 \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

Get ALB URL:

```bash
kubectl -n devops-launchboard get ingress launchboard-ingress
```

Set test URL:

```bash
export BASE_URL=http://YOUR_ALB_DNS_NAME
```

Why this step exists:

k6 should hit the same public entry point that users hit. The ALB gives a realistic public route through frontend and backend services.

## Step 9: Install Metrics Server

Create values file:

```bash
vim deployment/phase-13-performance-and-load-validation/monitoring/metrics-server-values.yaml
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
  -f deployment/phase-13-performance-and-load-validation/monitoring/metrics-server-values.yaml
```

Verify:

```bash
kubectl top nodes
kubectl top pods -n devops-launchboard
kubectl -n devops-launchboard get hpa
```

Why this step exists:

The HPA needs metrics to know when to scale. Without Metrics Server, `kubectl top` and CPU-based autoscaling usually do not work.

Reference:

- Metrics Server: https://github.com/kubernetes-sigs/metrics-server
- Kubernetes HPA: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/

## Step 10: Create k6 Smoke Test

Create:

```bash
vim deployment/phase-13-performance-and-load-validation/tests/k6/smoke-test.js
```

Paste:

```javascript
import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  vus: 1,
  duration: "30s",
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<500"]
  }
};

const baseUrl = __ENV.BASE_URL || "http://localhost";

export default function () {
  const frontend = http.get(`${baseUrl}/`);
  check(frontend, {
    "frontend returns 200": (response) => response.status === 200
  });

  const health = http.get(`${baseUrl}/health`);
  check(health, {
    "backend health returns 200": (response) => response.status === 200
  });

  const ready = http.get(`${baseUrl}/ready`);
  check(ready, {
    "backend ready returns 200": (response) => response.status === 200
  });

  sleep(1);
}
```

Run:

```bash
docker run --rm -i \
  -e BASE_URL=$BASE_URL \
  -v "$PWD:/workspace" \
  grafana/k6:latest run /workspace/deployment/phase-13-performance-and-load-validation/tests/k6/smoke-test.js
```

Why this test exists:

Smoke testing confirms the app works before adding real load. If this fails, load testing would only create noise.

## Step 11: Create k6 Load Test

Create:

```bash
vim deployment/phase-13-performance-and-load-validation/tests/k6/load-test.js
```

Paste the file contents from:

```text
deployment/phase-13-performance-and-load-validation/tests/k6/load-test.js
```

Run:

```bash
docker run --rm -i \
  -e BASE_URL=$BASE_URL \
  -v "$PWD:/workspace" \
  grafana/k6:latest run /workspace/deployment/phase-13-performance-and-load-validation/tests/k6/load-test.js
```

Watch scaling in another terminal:

```bash
kubectl -n devops-launchboard get hpa -w
```

Why this test exists:

The load test simulates expected traffic. The goal is not to break the system. The goal is to prove normal traffic stays within latency and error thresholds.

## Step 12: Create k6 Stress Test

Create:

```bash
vim deployment/phase-13-performance-and-load-validation/tests/k6/stress-test.js
```

Run:

```bash
docker run --rm -i \
  -e BASE_URL=$BASE_URL \
  -v "$PWD:/workspace" \
  grafana/k6:latest run /workspace/deployment/phase-13-performance-and-load-validation/tests/k6/stress-test.js
```

Why this test exists:

The stress test increases traffic beyond normal expectations. It helps students find where the app begins to slow down, produce errors, or scale.

## Step 13: Create k6 Soak Test

Create:

```bash
vim deployment/phase-13-performance-and-load-validation/tests/k6/soak-test.js
```

Run:

```bash
docker run --rm -i \
  -e BASE_URL=$BASE_URL \
  -v "$PWD:/workspace" \
  grafana/k6:latest run /workspace/deployment/phase-13-performance-and-load-validation/tests/k6/soak-test.js
```

Why this test exists:

The soak test checks whether the app stays healthy over time. It can reveal slow memory growth, database connection exhaustion, or gradual latency increases.

## Step 14: Capture Metrics During Tests

Run while k6 is active:

```bash
kubectl -n devops-launchboard top pods
kubectl -n devops-launchboard get hpa
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard logs deploy/launchboard-backend --tail=50
```

Expected:

```text
Backend pods stay ready.
Error rate stays below threshold.
HPA scales backend if CPU increases.
No repeated crash loops appear.
```

Why this step exists:

k6 tells you how users experience the app. Kubernetes metrics tell you how the infrastructure responds. Students need both views.

## Step 15: Create Performance Report

Create:

```bash
vim deployment/phase-13-performance-and-load-validation/reports/performance-report-template.md
```

Paste the template from this phase folder.

Copy it for your final result:

```bash
cp deployment/phase-13-performance-and-load-validation/reports/performance-report-template.md deployment/phase-13-performance-and-load-validation/reports/performance-report.md
vim deployment/phase-13-performance-and-load-validation/reports/performance-report.md
```

Why this report exists:

Performance validation is not finished when the command ends. The student should record load level, latency, errors, HPA behavior, bottlenecks, and whether the deployment passed.

## Troubleshooting

Problem: k6 cannot reach the app.

Cause:

```text
ALB is not ready, BASE_URL is wrong, or security routing is incomplete.
```

Fix:

```bash
kubectl -n devops-launchboard get ingress
curl -I $BASE_URL
curl -I $BASE_URL/health
```

Problem: HPA does not scale.

Cause:

```text
Metrics Server is missing, CPU is not high enough, or pod resource requests are missing.
```

Fix:

```bash
kubectl top nodes
kubectl -n devops-launchboard top pods
kubectl -n devops-launchboard describe hpa launchboard-backend
```

Problem: latency is high.

Cause:

```text
Backend CPU, database connection limits, pod startup time, or ALB warm-up may be bottlenecks.
```

Fix:

```bash
kubectl -n devops-launchboard top pods
kubectl -n devops-launchboard logs deploy/launchboard-backend --tail=100
kubectl -n devops-launchboard describe pod POD_NAME
```

Problem: error rate rises during stress test.

Cause:

```text
The system is past its safe capacity.
```

Fix:

```text
Record the breaking point.
Reduce traffic.
Tune resources.
Increase replicas.
Repeat the test.
```

## Cleanup

Delete app:

```bash
kubectl delete -f deployment/phase-13-performance-and-load-validation/app-k8s/secret.yaml
kubectl delete -k deployment/phase-13-performance-and-load-validation/app-k8s
```

Delete cluster:

```bash
eksctl delete cluster -f deployment/phase-13-performance-and-load-validation/cluster/eksctl-cluster.yaml
```

Delete ECR repositories:

```bash
aws ecr delete-repository --repository-name launchboard-backend --force --region $AWS_REGION
aws ecr delete-repository --repository-name launchboard-frontend --force --region $AWS_REGION
```

Why cleanup matters:

Performance labs can create cloud charges through EKS, EC2, EBS, ALB, ECR, CloudWatch logs, and data transfer.

## Production Checklist

```text
[ ] AWS credentials configured
[ ] Repository cloned with SSH
[ ] EKS cluster created
[ ] ECR repositories created
[ ] Images built and pushed
[ ] Application deployed
[ ] ALB URL available
[ ] Metrics Server installed
[ ] HPA visible
[ ] Smoke test passed
[ ] Load test passed
[ ] Stress test completed
[ ] Soak test completed
[ ] Pod CPU and memory checked
[ ] HPA behavior recorded
[ ] Error rate recorded
[ ] p95 and p99 latency recorded
[ ] Performance report completed
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

## Next Step

Review all deployment phases and choose which architecture best matches the project size, team skill, cost target, and production risk.
