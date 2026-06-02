# Phase 9: Observability

## Fresh Start Assumption

This phase starts from a clean AWS environment and a clean Ubuntu workstation.

You do not need to complete any previous phase before using this guide.

This guide assumes:

- AWS CLI, Docker, kubectl, eksctl, and Helm are not installed yet.
- No EKS cluster exists yet.
- No app images exist in ECR yet.
- The app is not deployed yet.
- You will create files with `vim`.
- You will type commands manually.
- You will not use shell scripts.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What You Will Deploy

This phase deploys:

- EKS cluster and managed node group.
- ECR repositories and app images.
- DevOps LaunchBoard application.
- Prometheus and Grafana with Helm.
- EFK-style logging with Elasticsearch, Fluent Bit, and Kibana.
- Jaeger all-in-one tracing.

## When To Use This Architecture

Use this architecture when:

- You want to learn metrics, logs, and traces on Kubernetes.
- You want dashboards for cluster and app health.
- You want searchable container logs.
- You want a tracing UI before adopting a full tracing platform.
- You are preparing for production operations.

Do not use this exact lab architecture when:

- You need HA Elasticsearch.
- You need long-term log retention.
- You need production-grade tracing storage.
- You want managed observability services from the start.

Production note:

This lab keeps observability tools inside the cluster for learning. Serious production often uses Amazon Managed Service for Prometheus, Amazon Managed Grafana, CloudWatch, OpenSearch, or another managed observability platform.

## Cost Warning

This phase is more expensive than earlier phases.

You may pay for:

- EKS control plane.
- EC2 worker nodes.
- NAT Gateway.
- EBS volumes.
- Application Load Balancer.
- CloudWatch logs.
- ECR image storage.

Create an AWS Budget before starting.

## Files Included In This Phase

```text
deployment/phase-9-observability/
+-- cluster/
|   +-- eksctl-cluster.yaml
+-- ecr/
|   +-- lifecycle-policy.json
+-- app-k8s/
|   +-- Kubernetes app manifests
+-- helm/
|   +-- kube-prometheus-stack-values.yaml
+-- elk-stack/
|   +-- elasticsearch.yaml
|   +-- kibana.yaml
|   +-- fluent-bit.yaml
+-- jaeger/
|   +-- jaeger.yaml
+-- Dockerfile.backend
+-- Dockerfile.frontend
+-- nginx-frontend.conf
+-- observability-namespace.yaml
+-- README.md
```

## Step 1: Create AWS Workstation

Create one Ubuntu EC2 workstation:

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-9-workstation` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` |
| Storage | 30 GB gp3 |
| SSH | Port `22`, your IP only |

SSH in:

```bash
chmod 400 devops-launchboard-key.pem
ssh -i devops-launchboard-key.pem ubuntu@YOUR_WORKSTATION_PUBLIC_IP
```

## Step 2: Install Base Tools

Run:

```bash
cd ~
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl wget vim unzip jq ca-certificates gnupg lsb-release
```

Why this step exists:

These tools are needed for cloning, installing AWS/Kubernetes tools, editing files, and checking HTTP endpoints.

## Step 3: Install Docker

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

## Step 4: Install AWS CLI, kubectl, eksctl, And Helm

AWS CLI:

```bash
cd ~
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws configure
aws sts get-caller-identity
```

kubectl:

```bash
cd ~
curl -LO "https://dl.k8s.io/release/stable.txt"
KUBECTL_VERSION=$(cat stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl
rm stable.txt
```

eksctl:

```bash
cd ~
curl --silent --location "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" -o eksctl.tar.gz
tar -xzf eksctl.tar.gz
sudo mv eksctl /usr/local/bin/eksctl
rm eksctl.tar.gz
```

Helm:

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
aws --version
kubectl version --client
eksctl version
helm version
```

## Step 5: Clone Repository

Create GitHub SSH key:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-9" -f ~/.ssh/devops_launchboard_github_key
cat ~/.ssh/devops_launchboard_github_key.pub
```

Add it to GitHub as a read-only deploy key.

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

Clone:

```bash
sudo mkdir -p /opt/devops-launchboard
sudo chown -R ubuntu:ubuntu /opt/devops-launchboard
cd /opt/devops-launchboard
git clone git@github.com:ashraful2430/N-tier-application.git app-source
cd app-source
```

## Step 6: Create Working Folders

Run:

```bash
mkdir -p deployment/phase-9-observability/cluster
mkdir -p deployment/phase-9-observability/ecr
mkdir -p deployment/phase-9-observability/app-k8s
mkdir -p deployment/phase-9-observability/helm
mkdir -p deployment/phase-9-observability/elk-stack
mkdir -p deployment/phase-9-observability/jaeger
```

Why this step exists:

Each folder owns one part of the phase: EKS cluster, ECR policy, app manifests, Helm values, logs, and traces.

## Step 7: Create EKS And App Files

Create these files with `vim`:

```text
deployment/phase-9-observability/cluster/eksctl-cluster.yaml
deployment/phase-9-observability/ecr/lifecycle-policy.json
deployment/phase-9-observability/Dockerfile.backend
deployment/phase-9-observability/Dockerfile.frontend
deployment/phase-9-observability/nginx-frontend.conf
deployment/phase-9-observability/app-k8s/*.yaml
```

Use the file contents provided in this phase folder.

Replace these placeholders:

```text
YOUR_AWS_REGION
YOUR_ACCOUNT_ID
YOUR_ALB_DNS_NAME
```

Why this step exists:

Phase 9 must deploy the app before observing it. Observability without a running workload is not useful for students.

## Step 8: Create EKS Cluster

Run:

```bash
AWS_REGION=YOUR_AWS_REGION
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
eksctl create cluster -f deployment/phase-9-observability/cluster/eksctl-cluster.yaml
```

Verify:

```bash
kubectl get nodes
kubectl get pods -A
```

## Step 9: Create ECR Repositories And Push Images

Create repositories:

```bash
aws ecr create-repository --repository-name launchboard-backend --region "$AWS_REGION"
aws ecr create-repository --repository-name launchboard-frontend --region "$AWS_REGION"
```

Apply lifecycle policy:

```bash
aws ecr put-lifecycle-policy --repository-name launchboard-backend --lifecycle-policy-text file://deployment/phase-9-observability/ecr/lifecycle-policy.json --region "$AWS_REGION"
aws ecr put-lifecycle-policy --repository-name launchboard-frontend --lifecycle-policy-text file://deployment/phase-9-observability/ecr/lifecycle-policy.json --region "$AWS_REGION"
```

Log in:

```bash
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
```

Build:

```bash
docker build -f deployment/phase-9-observability/Dockerfile.backend -t launchboard-backend:phase-9 .
docker build -f deployment/phase-9-observability/Dockerfile.frontend --build-arg VITE_API_URL= -t launchboard-frontend:phase-9 .
```

Tag and push:

```bash
docker tag launchboard-backend:phase-9 "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-9"
docker tag launchboard-frontend:phase-9 "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-frontend:phase-9"
docker push "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-9"
docker push "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-frontend:phase-9"
```

## Step 10: Install AWS Load Balancer Controller

Run:

```bash
CLUSTER_NAME=devops-launchboard-phase-9
curl -o aws-load-balancer-controller-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicyPhase9 --policy-document file://aws-load-balancer-controller-policy.json
eksctl create iamserviceaccount \
  --cluster "$CLUSTER_NAME" \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicyPhase9" \
  --approve \
  --region "$AWS_REGION"
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

## Step 11: Deploy The App

Create namespace and Secret:

```bash
kubectl apply -f deployment/phase-9-observability/app-k8s/namespace.yaml
kubectl create secret generic launchboard-secret \
  --namespace devops-launchboard \
  --from-literal=POSTGRES_PASSWORD='CHANGE_ME_STRONG_PASSWORD' \
  --from-literal=DATABASE_URL='postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@launchboard-db:5432/launchboard'
```

Apply manifests:

```bash
kubectl apply -k deployment/phase-9-observability/app-k8s
```

Wait:

```bash
kubectl -n devops-launchboard rollout status deployment/launchboard-db --timeout=300s
kubectl -n devops-launchboard wait --for=condition=complete job/launchboard-migrate --timeout=300s
kubectl -n devops-launchboard rollout status deployment/launchboard-backend --timeout=300s
kubectl -n devops-launchboard rollout status deployment/launchboard-frontend --timeout=300s
```

Get ALB DNS:

```bash
kubectl -n devops-launchboard get ingress launchboard-ingress
```

Update `CORS_ORIGINS` in:

```text
deployment/phase-9-observability/app-k8s/configmap.yaml
```

Then apply:

```bash
kubectl apply -f deployment/phase-9-observability/app-k8s/configmap.yaml
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
```

## Step 12: Create Observability Namespace

Run:

```bash
vim deployment/phase-9-observability/observability-namespace.yaml
```

Paste:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: observability
  labels:
    app.kubernetes.io/name: observability
```

Apply:

```bash
kubectl apply -f deployment/phase-9-observability/observability-namespace.yaml
```

Why this step exists:

Observability tools should live in their own namespace so app resources and monitoring resources stay organized.

## Step 13: Install Prometheus And Grafana

Create Helm values:

```bash
vim deployment/phase-9-observability/helm/kube-prometheus-stack-values.yaml
```

Use the file contents from this phase folder and change:

```text
CHANGE_ME_GRAFANA_PASSWORD
```

Install:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --values deployment/phase-9-observability/helm/kube-prometheus-stack-values.yaml
```

Verify:

```bash
kubectl -n observability get pods
kubectl -n observability port-forward service/kube-prometheus-stack-grafana 3000:80
```

Open:

```text
http://127.0.0.1:3000
```

Why this step exists:

Prometheus collects metrics. Grafana visualizes those metrics with dashboards.

## Step 14: Install EFK Logging

Create files:

```bash
vim deployment/phase-9-observability/elk-stack/elasticsearch.yaml
vim deployment/phase-9-observability/elk-stack/kibana.yaml
vim deployment/phase-9-observability/elk-stack/fluent-bit.yaml
```

Apply:

```bash
kubectl apply -f deployment/phase-9-observability/elk-stack/elasticsearch.yaml
kubectl apply -f deployment/phase-9-observability/elk-stack/kibana.yaml
kubectl apply -f deployment/phase-9-observability/elk-stack/fluent-bit.yaml
```

Wait:

```bash
kubectl -n observability rollout status statefulset/elasticsearch --timeout=300s
kubectl -n observability rollout status deployment/kibana --timeout=300s
kubectl -n observability rollout status daemonset/fluent-bit --timeout=300s
```

Open Kibana:

```bash
kubectl -n observability port-forward service/kibana 5601:5601
```

Then open:

```text
http://127.0.0.1:5601
```

Why this step exists:

Fluent Bit reads container logs, sends them to Elasticsearch, and Kibana lets students search and inspect logs.

## Step 15: Install Jaeger

Create:

```bash
vim deployment/phase-9-observability/jaeger/jaeger.yaml
```

Apply:

```bash
kubectl apply -f deployment/phase-9-observability/jaeger/jaeger.yaml
kubectl -n observability rollout status deployment/jaeger --timeout=180s
```

Open Jaeger UI:

```bash
kubectl -n observability port-forward service/jaeger 16686:16686
```

Then open:

```text
http://127.0.0.1:16686
```

Why this step exists:

Jaeger shows distributed traces. This app may need tracing instrumentation later, but the platform is ready for trace collection through OTLP ports `4317` and `4318`.

## Step 16: Verify Observability

Prometheus:

```bash
kubectl -n observability get pods | grep prometheus
```

Grafana:

```bash
kubectl -n observability get service kube-prometheus-stack-grafana
```

EFK:

```bash
kubectl -n observability get pods | grep elasticsearch
kubectl -n observability get pods | grep kibana
kubectl -n observability get pods | grep fluent-bit
```

Jaeger:

```bash
kubectl -n observability get pods | grep jaeger
```

Application:

```bash
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard logs deployment/launchboard-backend
```

## Troubleshooting

### Prometheus Or Grafana Pods Pending

Check:

```bash
kubectl -n observability describe pod POD_NAME
kubectl get nodes
```

Common cause:

```text
Node group is too small for observability tools.
```

### Elasticsearch Does Not Start

Check:

```bash
kubectl -n observability describe statefulset elasticsearch
kubectl -n observability logs statefulset/elasticsearch
```

Common cause:

```text
Not enough memory on worker nodes.
PVC not bound.
```

### Grafana Is Empty

Check:

```bash
kubectl -n observability get servicemonitor
kubectl -n observability port-forward service/kube-prometheus-stack-prometheus 9090:9090
```

Open:

```text
http://127.0.0.1:9090/targets
```

## Cleanup

Delete observability:

```bash
helm uninstall kube-prometheus-stack --namespace observability
kubectl delete -f deployment/phase-9-observability/elk-stack/fluent-bit.yaml
kubectl delete -f deployment/phase-9-observability/elk-stack/kibana.yaml
kubectl delete -f deployment/phase-9-observability/elk-stack/elasticsearch.yaml
kubectl delete -f deployment/phase-9-observability/jaeger/jaeger.yaml
kubectl delete namespace observability
```

Delete app:

```bash
kubectl delete namespace devops-launchboard
```

Delete EKS cluster:

```bash
eksctl delete cluster --name devops-launchboard-phase-9 --region "$AWS_REGION"
```

Delete ECR repositories:

```bash
aws ecr delete-repository --repository-name launchboard-backend --force --region "$AWS_REGION"
aws ecr delete-repository --repository-name launchboard-frontend --force --region "$AWS_REGION"
```

## Production Checklist

```text
[ ] AWS Budget created
[ ] EKS cluster created
[ ] App images pushed to ECR
[ ] App deployed to EKS
[ ] ALB URL works
[ ] Prometheus installed
[ ] Grafana installed
[ ] EFK installed
[ ] Jaeger installed
[ ] Metrics verified
[ ] Logs verified
[ ] Tracing UI reachable
[ ] Cleanup plan understood
```

## Reference Documentation

| Topic | Link |
| --- | --- |
| Amazon EKS | https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html |
| Prometheus Operator Helm chart | https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack |
| Grafana docs | https://grafana.com/docs/grafana/latest/ |
| Fluent Bit Kubernetes | https://docs.fluentbit.io/manual/installation/kubernetes |
| Elasticsearch on Kubernetes | https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html |
| Kibana docs | https://www.elastic.co/guide/en/kibana/current/index.html |
| Jaeger docs | https://www.jaegertracing.io/docs/ |

## What To Do Next

Move to:

```text
Phase 10: Security
```

Why:

After you can observe the platform, the next step is to harden it with security controls, policy, scanning, and secrets management.
