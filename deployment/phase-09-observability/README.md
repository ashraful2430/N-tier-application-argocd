# Phase 9: Observability

## Fresh Start Assumption

This phase starts from a clean AWS environment and a clean Ubuntu workstation.

You do not need to complete any previous phase before using this guide.

This guide assumes:

- You have an AWS account with permissions to create EKS, EC2, IAM, ECR, ALB, EBS, VPC, NAT Gateway, and CloudWatch resources.
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

This phase deploys the full application stack AND three observability pillars on top of it:

- EKS cluster with managed node group (same as Phase 8).
- ECR repositories and app images.
- DevOps LaunchBoard application (PostgreSQL, FastAPI backend, React frontend, ALB Ingress).
- **Metrics**: Prometheus + Grafana (via the kube-prometheus-stack Helm chart) for cluster and application metrics with pre-built dashboards.
- **Logs**: Fluent Bit + Elasticsearch + Kibana (the "EFK stack") for centralized, searchable container logs.
- **Traces**: Jaeger all-in-one for distributed tracing visualization.

Architecture after this phase:

```text
                          Browser
                            |
                            | HTTP port 80
                            v
                     AWS Application Load Balancer
                            |
                            v
                    Kubernetes Ingress (ALB)
                            |
              +-------------+-------------+
              |                           |
    Frontend Service              Backend Service
         |                              |
    Frontend Pods                  Backend Pods
         |                              |
         +----------> Backend <---------+
                         |
                    PostgreSQL Pod
                         |
                    EBS gp3 Volume

  ========== Observability Layer ==========

  Prometheus ──scrapes──> All Pods (metrics endpoints)
       |                  Nodes (kubelet, cAdvisor)
       |                  kube-state-metrics
       v
    Grafana ──dashboards──> Browser (port-forward 3000)

  Fluent Bit (DaemonSet on every node)
       |
       | reads /var/log/containers/*.log
       v
  Elasticsearch (StatefulSet + PVC)
       |
       v
    Kibana ──search UI──> Browser (port-forward 5601)

  Jaeger (all-in-one)
       |
       | receives traces via OTLP (ports 4317/4318)
       v
    Jaeger UI ──trace viewer──> Browser (port-forward 16686)
```

## The Three Pillars Of Observability

Before diving into the steps, understand what you are building and why:

**Metrics** answer "how much" and "how fast." CPU usage, memory consumption, request latency, error rates, Pod restart counts. Prometheus scrapes these numbers from endpoints every 15 to 30 seconds and stores them as time series. Grafana turns them into graphs and dashboards. You use metrics to spot trends, set alerts, and decide when to scale.

**Logs** answer "what happened." Every line your application prints to stdout (FastAPI request logs, Alembic migration output, Nginx access logs, PostgreSQL startup messages) is a log entry. On a single server you read logs with `cat` or `tail`. On a Kubernetes cluster with dozens of Pods across multiple nodes, you need a system that collects logs from every container, ships them to a central store, and lets you search across all of them. That is what Fluent Bit (collector) + Elasticsearch (store + index) + Kibana (search UI) do.

**Traces** answer "where did the time go" in a single request that crosses multiple services. When a browser request hits the frontend, which calls the backend, which calls the database, a trace connects all three hops into one timeline. Jaeger visualizes this. In this lab, Jaeger is deployed and ready to receive traces; full tracing instrumentation of the FastAPI backend (adding OpenTelemetry spans) is a natural next step.

## When To Use This Architecture

Use this architecture when:

- You want to learn metrics, logs, and traces on Kubernetes.
- You want dashboards for cluster and app health.
- You want searchable container logs.
- You want a tracing UI before adopting a full tracing platform.
- You are preparing for production operations.

Do not use this exact lab architecture when:

- You need HA Elasticsearch (this lab runs a single-node instance).
- You need long-term log retention (Elasticsearch here has no backup).
- You need production-grade tracing storage (Jaeger all-in-one uses in-memory storage).
- You want managed observability services from the start (use Amazon Managed Prometheus, Amazon Managed Grafana, CloudWatch, or OpenSearch instead).

## Cost Warning

This phase is more expensive than Phase 8 because the observability tools (especially Elasticsearch) need more memory. You need at least 2 × t3.medium workers, and 3 × t3.medium is recommended if Elasticsearch runs out of memory on 2 nodes.

| Resource | Approximate Cost |
| --- | --- |
| EKS control plane | ~$0.10/hour |
| 2-3 × t3.medium workers | ~$0.08-$0.12/hour |
| NAT Gateway | ~$0.045/hour |
| ALB | ~$0.02/hour |
| EBS volumes (worker roots + Elasticsearch PVC + PostgreSQL PVC) | ~$0.01/hour |
| ECR, CloudWatch | minimal |

Running for 8 hours costs roughly $2 to $4. Running 24/7 for a month costs $180 to $250. Delete the cluster after each lab session.

Create an AWS Budget before starting: AWS Console > Billing > Budgets > Create budget.

## Files Included In This Phase

```text
deployment/phase-09-observability/
+-- cluster/
|   +-- eksctl-cluster.yaml                    (EKS cluster definition)
+-- ecr/
|   +-- lifecycle-policy.json                  (auto-expire old ECR images)
+-- app-k8s/
|   +-- namespace.yaml                         (app namespace)
|   +-- storageclass.yaml                      (gp3 encrypted EBS)
|   +-- configmap.yaml                         (app configuration)
|   +-- secret.example.yaml                    (example secret)
|   +-- pvc.yaml                               (PostgreSQL persistent storage)
|   +-- launchboard-postgres-deployment.yaml   (database Pod)
|   +-- launchboard-postgres-service.yaml      (database DNS)
|   +-- launchboard-migration-job.yaml         (Alembic migrations)
|   +-- launchboard-backend-deployment.yaml    (FastAPI backend)
|   +-- launchboard-backend-service.yaml       (backend DNS)
|   +-- launchboard-frontend-deployment.yaml   (React frontend)
|   +-- launchboard-frontend-service.yaml      (frontend DNS)
|   +-- ingress.yaml                           (ALB Ingress)
|   +-- hpa.yaml                               (backend autoscaler)
|   +-- kustomization.yaml                     (groups app manifests)
+-- helm/
|   +-- kube-prometheus-stack-values.yaml      (Prometheus + Grafana Helm values)
+-- grafana/                                   (optional: reference dashboards and datasource provisioning, not created in this walkthrough)
|   +-- dashboards/application-metrics.json
|   +-- dashboards/infrastructure-metrics.json
|   +-- grafana.yml
|   +-- provisioning/datasources/prometheus.yml
+-- prometheus/                                (optional: standalone Prometheus config for reference; this phase configures Prometheus through the Helm values above instead)
|   +-- prometheus.yml
|   +-- rules.yml
|   +-- alert-rules.yaml
+-- elk-stack/
|   +-- elasticsearch.yaml                     (Elasticsearch StatefulSet + Service)
|   +-- kibana.yaml                            (Kibana Deployment + Service)
|   +-- fluent-bit.yaml                        (Fluent Bit DaemonSet + ConfigMap)
|   +-- filebeat.yml                           (optional: alternative log shipper, not used; this phase uses Fluent Bit instead)
+-- jaeger/
|   +-- jaeger.yaml                            (Jaeger all-in-one Deployment + Service)
+-- observability-namespace.yaml               (observability namespace)
+-- Dockerfile.backend                         (FastAPI image)
+-- Dockerfile.frontend                        (React/Nginx image)
+-- nginx-frontend.conf                        (Nginx config)
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
| Key Pair | `devops-launchboard-key` |
| Security Group | SSH port 22, your IP only |

SSH in:

```bash
chmod 400 devops-launchboard-key.pem
ssh -i devops-launchboard-key.pem ubuntu@YOUR_WORKSTATION_PUBLIC_IP
```

This machine is the admin workstation only. The application and observability tools run on EKS worker nodes.

## Step 2: Install Base Tools

```bash
cd ~
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl wget vim unzip jq ca-certificates gnupg lsb-release
```

## Step 3: Install Docker

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

Verify:

```bash
docker --version
docker info
```

## Step 4: Install AWS CLI, kubectl, eksctl, And Helm

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

See Phase 8 Steps 6-7 for detailed command explanations.

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

## Step 6: Create Working Folders

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-09-observability/cluster
mkdir -p deployment/phase-09-observability/ecr
mkdir -p deployment/phase-09-observability/app-k8s
mkdir -p deployment/phase-09-observability/helm
mkdir -p deployment/phase-09-observability/elk-stack
mkdir -p deployment/phase-09-observability/jaeger
```

Each folder owns one part of the phase: `cluster/` for the eksctl config, `ecr/` for image lifecycle policy, `app-k8s/` for the application manifests, `helm/` for Prometheus/Grafana values, `elk-stack/` for the logging pipeline, and `jaeger/` for tracing.

## Step 7: Create EKS Cluster Config And Dockerfiles

These files are functionally identical to Phase 8, with the cluster name changed to `devops-launchboard-phase-9` and image tags changed to `phase-9`. See Phase 8 for full line-by-line explanations.

### eksctl-cluster.yaml

```bash
vim deployment/phase-09-observability/cluster/eksctl-cluster.yaml
```

Paste:

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: devops-launchboard-phase-9
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
      Environment: phase-9
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

Replace `YOUR_AWS_REGION` in three places. See Phase 8 Step 11 for the full explanation of every field.

Note: `desiredCapacity: 2` starts with 2 nodes. If Elasticsearch runs out of memory alongside the application, increase to 3 nodes: edit this file and run `eksctl scale nodegroup --cluster devops-launchboard-phase-9 --name launchboard-workers --nodes 3 --region $AWS_REGION`.

### ECR lifecycle policy

```bash
vim deployment/phase-09-observability/ecr/lifecycle-policy.json
```

Paste:

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep the latest 10 phase 9 images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["phase-9"],
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

### Root .dockerignore

```bash
vim /opt/devops-launchboard/app-source/.dockerignore
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

### Dockerfiles and nginx config

```bash
vim deployment/phase-09-observability/Dockerfile.backend
```

Paste the exact same content as Phase 8 Step 13 `Dockerfile.backend`.

```bash
vim deployment/phase-09-observability/Dockerfile.frontend
```

Paste the same content as Phase 8 Step 13 `Dockerfile.frontend`, but change the COPY path:

```dockerfile
COPY deployment/phase-09-observability/nginx-frontend.conf /etc/nginx/conf.d/default.conf
```

```bash
vim deployment/phase-09-observability/nginx-frontend.conf
```

Paste the exact same content as Phase 8 Step 13 `nginx-frontend.conf`.

### Application Kubernetes manifests

Create every file under `deployment/phase-09-observability/app-k8s/` with the exact same content as Phase 8 Step 14. The files are:

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

The only difference from Phase 8: the image tags in the three ECR image references are `phase-9` instead of `phase-8`:

```text
image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-backend:phase-9
image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_AWS_REGION.amazonaws.com/launchboard-frontend:phase-9
```

This applies to `launchboard-migration-job.yaml`, `launchboard-backend-deployment.yaml`, and `launchboard-frontend-deployment.yaml`.

See Phase 8 Step 14 for the full content and line-by-line explanations of every manifest.

## Step 8: Create EKS Cluster

Set variables you will reuse throughout the phase:

```bash
export AWS_REGION=YOUR_AWS_REGION
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export CLUSTER_NAME=devops-launchboard-phase-9
echo "Account: $ACCOUNT_ID  Region: $AWS_REGION  Cluster: $CLUSTER_NAME"
```

Create the cluster (20 to 40 minutes):

```bash
cd /opt/devops-launchboard/app-source
eksctl create cluster -f deployment/phase-09-observability/cluster/eksctl-cluster.yaml
```

Verify:

```bash
kubectl get nodes
kubectl get pods -A
kubectl get pods -n kube-system | grep ebs
```

Expected: 2 nodes Ready, EBS CSI driver Pods running. See Phase 8 Step 17 for the full explanation of what eksctl creates.

## Step 9: Create ECR Repositories And Push Images

```bash
aws ecr create-repository --repository-name launchboard-backend --region "$AWS_REGION"
aws ecr create-repository --repository-name launchboard-frontend --region "$AWS_REGION"

aws ecr put-lifecycle-policy --repository-name launchboard-backend \
  --lifecycle-policy-text file://deployment/phase-09-observability/ecr/lifecycle-policy.json --region "$AWS_REGION"
aws ecr put-lifecycle-policy --repository-name launchboard-frontend \
  --lifecycle-policy-text file://deployment/phase-09-observability/ecr/lifecycle-policy.json --region "$AWS_REGION"

aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

cd /opt/devops-launchboard/app-source

docker build -f deployment/phase-09-observability/Dockerfile.backend \
  -t launchboard-backend:phase-9 .
docker build -f deployment/phase-09-observability/Dockerfile.frontend \
  --build-arg VITE_API_URL= -t launchboard-frontend:phase-9 .

docker tag launchboard-backend:phase-9 \
  "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-9"
docker tag launchboard-frontend:phase-9 \
  "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-frontend:phase-9"

docker push "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-9"
docker push "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-frontend:phase-9"
```

See Phase 8 Steps 15-16 for full explanations.

## Step 10: Install AWS Load Balancer Controller

```bash
cd ~
curl -o aws-load-balancer-controller-policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicyPhase9 \
  --policy-document file://aws-load-balancer-controller-policy.json

eksctl create iamserviceaccount \
  --cluster "$CLUSTER_NAME" \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicyPhase9" \
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

See Phase 8 Step 18 for the full IRSA and Helm explanation.

## Step 11: Deploy The Application

Replace image placeholders in manifests:

```bash
cd /opt/devops-launchboard/app-source
sed -i "s|YOUR_ACCOUNT_ID|${ACCOUNT_ID}|g; s|YOUR_AWS_REGION|${AWS_REGION}|g" \
  deployment/phase-09-observability/app-k8s/launchboard-backend-deployment.yaml \
  deployment/phase-09-observability/app-k8s/launchboard-migration-job.yaml \
  deployment/phase-09-observability/app-k8s/launchboard-frontend-deployment.yaml
```

Create namespace and Secret:

```bash
kubectl apply -f deployment/phase-09-observability/app-k8s/namespace.yaml

kubectl create secret generic launchboard-secret \
  --namespace devops-launchboard \
  --from-literal=POSTGRES_PASSWORD='CHANGE_ME_STRONG_PASSWORD' \
  --from-literal=DATABASE_URL='postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@launchboard-db:5432/launchboard'
```

Apply:

```bash
kubectl apply -k deployment/phase-09-observability/app-k8s
```

Wait:

```bash
kubectl -n devops-launchboard rollout status deployment/launchboard-db --timeout=300s
kubectl -n devops-launchboard wait --for=condition=complete job/launchboard-migrate --timeout=300s
kubectl -n devops-launchboard rollout status deployment/launchboard-backend --timeout=300s
kubectl -n devops-launchboard rollout status deployment/launchboard-frontend --timeout=300s
```

Get ALB DNS and update CORS:

```bash
kubectl -n devops-launchboard get ingress launchboard-ingress
```

Wait until the ADDRESS column shows a DNS name, then:

```bash
ALB_DNS=$(kubectl -n devops-launchboard get ingress launchboard-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB DNS: $ALB_DNS"

vim deployment/phase-09-observability/app-k8s/configmap.yaml
```

Set `CORS_ORIGINS` to `http://YOUR_ALB_DNS_NAME` with the real DNS, then:

```bash
kubectl apply -f deployment/phase-09-observability/app-k8s/configmap.yaml
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
```

Verify the app:

```bash
curl -s "http://$ALB_DNS/health" | jq
curl -s "http://$ALB_DNS/api/summary" | jq
```

The application is now running. Everything from this point forward adds observability on top of it.

## Step 12: Create Observability Namespace

All observability tools live in a separate namespace to keep them isolated from the application.

```bash
vim deployment/phase-09-observability/observability-namespace.yaml
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
kubectl apply -f deployment/phase-09-observability/observability-namespace.yaml
```

Verify:

```bash
kubectl get namespace observability
```

## Step 13: Install Prometheus And Grafana

The kube-prometheus-stack Helm chart installs Prometheus, Grafana, node-exporter, kube-state-metrics, and Alertmanager in one command. It also installs pre-built dashboards for Kubernetes cluster monitoring, node health, Pod resource usage, and more.

What each component does:

- **Prometheus** scrapes metrics from endpoints (Pods, nodes, kubelets, the API server) at regular intervals and stores them as time series data. A time series is a sequence of timestamped values: for example, `container_cpu_usage_seconds_total{pod="launchboard-backend-abc"}` with a value every 15 seconds.
- **Grafana** queries Prometheus and renders the data as graphs, gauges, tables, and heatmaps. It ships with dozens of pre-built Kubernetes dashboards.
- **node-exporter** is a DaemonSet that runs on every node and exposes hardware/OS metrics: CPU, memory, disk, network. Prometheus scrapes these.
- **kube-state-metrics** is a Deployment that watches the Kubernetes API and generates metrics about the state of objects: Deployment replica counts, Pod statuses, Job completion counts. Prometheus scrapes these too.
- **Alertmanager** receives alert notifications from Prometheus and routes them (to email, Slack, PagerDuty, etc.). In this lab you set it up but do not configure external routing.

### Create Helm values

```bash
vim deployment/phase-09-observability/helm/kube-prometheus-stack-values.yaml
```

Paste:

```yaml
# Grafana configuration
grafana:
  enabled: true
  adminUser: admin
  adminPassword: CHANGE_ME_GRAFANA_PASSWORD
  service:
    type: ClusterIP
    port: 80
  persistence:
    enabled: false
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: default
          orgId: 1
          folder: ""
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/default
  dashboards:
    default:
      kubernetes-cluster:
        gnetId: 7249
        revision: 1
        datasource: Prometheus
      node-exporter-full:
        gnetId: 1860
        revision: 37
        datasource: Prometheus
      kubernetes-pods:
        gnetId: 6417
        revision: 1
        datasource: Prometheus

# Prometheus configuration
prometheus:
  prometheusSpec:
    retention: 3d
    retentionSize: 5GB
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 2Gi
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3-encrypted
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false

# Alertmanager configuration
alertmanager:
  enabled: true
  alertmanagerSpec:
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 200m
        memory: 256Mi

# node-exporter configuration
nodeExporter:
  enabled: true

# kube-state-metrics configuration
kubeStateMetrics:
  enabled: true

# Default rules (pre-built Prometheus alerting rules)
defaultRules:
  create: true
  rules:
    etcd: false
    kubeScheduler: false
```

Replace `CHANGE_ME_GRAFANA_PASSWORD` with a real password.

Line explanation:

- `grafana.adminUser: admin` and `grafana.adminPassword` set the Grafana login credentials. You use these to access the Grafana web UI.
- `grafana.service.type: ClusterIP` keeps Grafana internal. You access it via `kubectl port-forward`. In production you would add an Ingress with authentication.
- `grafana.persistence.enabled: false` means Grafana dashboards and settings are stored in memory and lost when the Pod restarts. For a student lab this is acceptable. For production, set this to `true` with a PVC.
- `grafana.resources` keeps Grafana within reasonable bounds on a t3.medium cluster.
- `grafana.dashboardProviders` and `grafana.dashboards` configure Grafana to automatically import dashboards from Grafana.com by their ID. `gnetId: 7249` is the "Kubernetes Cluster" dashboard. `gnetId: 1860` is the "Node Exporter Full" dashboard, one of the most popular Grafana dashboards with 40+ panels showing every node metric. `gnetId: 6417` is "Kubernetes Pods" showing per-Pod CPU, memory, and network. These import on first startup so you have useful dashboards without manual configuration.
- `prometheus.prometheusSpec.retention: 3d` keeps metrics for 3 days. Older data is deleted automatically. In production you would set this to 15d or 30d depending on storage budget.
- `prometheus.prometheusSpec.retentionSize: 5GB` caps total storage. Prometheus deletes the oldest data if the 5 GB limit is hit before the 3-day retention window.
- `storageSpec.volumeClaimTemplate` gives Prometheus a 10 GB gp3 encrypted EBS volume via the StorageClass you created in the app manifests. Prometheus data survives Pod restarts. Without this, a Prometheus restart loses all historical metrics.
- `serviceMonitorSelectorNilUsesHelmValues: false` tells Prometheus to scrape ALL ServiceMonitors in ALL namespaces, not just ones in the `observability` namespace. This is important because your application Pods live in `devops-launchboard`. With the default value (`true`), Prometheus would only scrape monitors that match Helm's release labels, missing your app entirely.
- `podMonitorSelectorNilUsesHelmValues: false` does the same for PodMonitors.
- `alertmanager.enabled: true` installs Alertmanager. It receives alerts from Prometheus (like "backend Pod has restarted 5 times in 10 minutes") and can route them to external notification channels.
- `nodeExporter.enabled: true` installs the node-exporter DaemonSet. One Pod per node, exposing hardware metrics.
- `kubeStateMetrics.enabled: true` installs the kube-state-metrics Deployment, which generates metrics about Kubernetes object states.
- `defaultRules.rules.etcd: false` and `kubeScheduler: false` disable alerting rules for etcd and the scheduler because on EKS the control plane is managed by AWS and these metrics endpoints are not exposed to scraping.

### Install with Helm

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --values deployment/phase-09-observability/helm/kube-prometheus-stack-values.yaml \
  --timeout 10m
```

Command explanation:

- `helm repo add` registers the Prometheus community chart repository.
- `helm install kube-prometheus-stack` installs the chart with the release name `kube-prometheus-stack` in the `observability` namespace.
- `--values` provides the custom configuration file. Without it, Helm uses default values (no password, no persistence, no imported dashboards).
- `--timeout 10m` gives the installation up to 10 minutes. The chart creates many resources and the PVC needs time to bind.

Wait for all Pods:

```bash
kubectl -n observability get pods -w
```

Press Ctrl+C when all Pods show `Running` or `Completed`. Expected Pods:

```text
alertmanager-kube-prometheus-stack-alertmanager-0     Running
kube-prometheus-stack-grafana-...                      Running
kube-prometheus-stack-kube-state-metrics-...           Running
kube-prometheus-stack-operator-...                     Running
kube-prometheus-stack-prometheus-node-exporter-...     Running  (one per node)
prometheus-kube-prometheus-stack-prometheus-0           Running
```

### Access Grafana

Open a port-forward from the workstation:

```bash
kubectl -n observability port-forward service/kube-prometheus-stack-grafana 3000:80 --address 0.0.0.0 &
```

The `&` runs it in the background so you can continue using the terminal. `--address 0.0.0.0` listens on all interfaces so you can access it from your browser via the workstation's public IP.

Important: add port 3000 to the workstation security group temporarily:

```text
Type: Custom TCP
Port: 3000
Source: Your IP
```

Open in browser:

```text
http://YOUR_WORKSTATION_PUBLIC_IP:3000
```

Log in with `admin` and the password you set.

### Explore The Dashboards

After logging in:

1. Click the hamburger menu (three horizontal lines) on the left.
2. Click Dashboards.
3. You should see the three imported dashboards: Kubernetes Cluster, Node Exporter Full, and Kubernetes Pods.
4. Open "Node Exporter Full" — this shows CPU, memory, disk, and network for each worker node.
5. Open "Kubernetes Pods" — this shows per-Pod resource usage. Look for your `launchboard-backend` and `launchboard-frontend` Pods.

If dashboards are empty, wait 2 to 3 minutes for Prometheus to scrape its first data points.

### Access Prometheus directly (optional)

```bash
kubectl -n observability port-forward service/kube-prometheus-stack-prometheus 9090:9090 --address 0.0.0.0 &
```

Add port 9090 to the security group, then open:

```text
http://YOUR_WORKSTATION_PUBLIC_IP:9090
```

Try a query in the Prometheus expression browser:

```promql
sum(rate(container_cpu_usage_seconds_total{namespace="devops-launchboard"}[5m])) by (pod)
```

This shows the CPU usage rate for each Pod in the `devops-launchboard` namespace over the last 5 minutes.

Reference:

- kube-prometheus-stack chart: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
- Prometheus documentation: https://prometheus.io/docs/
- Grafana documentation: https://grafana.com/docs/grafana/latest/
- PromQL basics: https://prometheus.io/docs/prometheus/latest/querying/basics/

## Step 14: Install EFK Logging Stack

The EFK stack (Elasticsearch, Fluent Bit, Kibana) gives you centralized, searchable logs from every container in the cluster. Without it, reading logs means running `kubectl logs` one Pod at a time, which does not scale and loses history when Pods are replaced.

How the pipeline works:

```text
Every container writes to stdout/stderr
  |
  v
Kubernetes writes each container's output to a log file on the node
  /var/log/containers/POD_NAMESPACE_CONTAINER-ID.log
  |
  v
Fluent Bit (DaemonSet, one Pod per node) tails these log files
  |
  | parses, enriches with Kubernetes metadata (pod name, namespace, labels)
  v
Elasticsearch (StatefulSet) receives, indexes, and stores the log entries
  |
  v
Kibana (Deployment) queries Elasticsearch and shows a search UI
```

### elasticsearch.yaml

```bash
vim deployment/phase-09-observability/elk-stack/elasticsearch.yaml
```

Paste:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: elasticsearch
  namespace: observability
  labels:
    app: elasticsearch
spec:
  serviceName: elasticsearch
  replicas: 1
  selector:
    matchLabels:
      app: elasticsearch
  template:
    metadata:
      labels:
        app: elasticsearch
    spec:
      initContainers:
        - name: fix-permissions
          image: busybox:1.36
          command: ["sh", "-c", "chown -R 1000:1000 /usr/share/elasticsearch/data"]
          volumeMounts:
            - name: elasticsearch-data
              mountPath: /usr/share/elasticsearch/data
          securityContext:
            runAsUser: 0
      containers:
        - name: elasticsearch
          image: docker.elastic.co/elasticsearch/elasticsearch:8.13.4
          ports:
            - name: http
              containerPort: 9200
            - name: transport
              containerPort: 9300
          env:
            - name: discovery.type
              value: single-node
            - name: xpack.security.enabled
              value: "false"
            - name: ES_JAVA_OPTS
              value: "-Xms512m -Xmx512m"
            - name: cluster.name
              value: launchboard-logs
          volumeMounts:
            - name: elasticsearch-data
              mountPath: /usr/share/elasticsearch/data
          resources:
            requests:
              cpu: 200m
              memory: 1Gi
            limits:
              cpu: 1000m
              memory: 1536Mi
          readinessProbe:
            httpGet:
              path: /_cluster/health?wait_for_status=yellow&timeout=5s
              port: 9200
            initialDelaySeconds: 30
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /_cluster/health?local=true
              port: 9200
            initialDelaySeconds: 60
            periodSeconds: 15
  volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: gp3-encrypted
        resources:
          requests:
            storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
  namespace: observability
  labels:
    app: elasticsearch
spec:
  type: ClusterIP
  selector:
    app: elasticsearch
  ports:
    - name: http
      port: 9200
      targetPort: 9200
    - name: transport
      port: 9300
      targetPort: 9300
```

Line explanation:

- `kind: StatefulSet` is used instead of a Deployment because Elasticsearch needs stable network identities and stable persistent storage. A StatefulSet gives each Pod a predictable name (`elasticsearch-0`) and a dedicated PVC that follows the Pod across restarts.
- `serviceName: elasticsearch` is the headless service name required by StatefulSet for DNS resolution between Elasticsearch nodes (not relevant for single-node, but required by the spec).
- `replicas: 1` runs a single Elasticsearch instance. This is not highly available, but it is enough for a student lab. Production Elasticsearch uses 3+ nodes across availability zones.
- The `initContainers` section runs a busybox container as root (`runAsUser: 0`) to fix ownership of the data directory before Elasticsearch starts. Elasticsearch runs as UID 1000 and needs to own its data directory. The PVC is provisioned by the EBS CSI driver and may have root ownership initially.
- `image: docker.elastic.co/elasticsearch/elasticsearch:8.13.4` is the official Elasticsearch 8.13 image. Pinning the version prevents unexpected behavior from automatic updates.
- `discovery.type: single-node` tells Elasticsearch not to look for other nodes to form a cluster. Without this, Elasticsearch waits for other nodes and enters a bootstrap loop.
- `xpack.security.enabled: "false"` disables the built-in security features (authentication, TLS between nodes) for simplicity. In production, security must be enabled.
- `ES_JAVA_OPTS: "-Xms512m -Xmx512m"` sets the JVM heap to 512 MB minimum and maximum. Elasticsearch is Java-based and heap sizing is critical: too low and it crashes, too high and it competes with the OS page cache. The recommendation is to set the heap to half the container's memory limit, capped at 50% of total available memory. With a 1536 Mi limit, 512 MB heap leaves ~1 GB for the OS file cache, which Elasticsearch relies on heavily for search performance.
- `cluster.name: launchboard-logs` gives the Elasticsearch cluster a human-readable name.
- `volumeClaimTemplates` creates a 10 GB gp3 encrypted PVC for each replica (here just one). Log data is stored on this EBS volume and survives Pod restarts.
- The readiness probe checks `/_cluster/health?wait_for_status=yellow&timeout=5s`. Yellow means the cluster is functional with all primary shards allocated. Green means all replicas are allocated too, but a single-node cluster with replicas=0 shows yellow, which is healthy for this setup.
- The liveness probe checks `/_cluster/health?local=true` which returns the local node's health without cluster-wide checks, making it lightweight.
- The Service exposes port 9200 (HTTP API, used by Fluent Bit to send logs and by Kibana to query) and port 9300 (transport protocol, used for inter-node communication in multi-node clusters).

### kibana.yaml

```bash
vim deployment/phase-09-observability/elk-stack/kibana.yaml
```

Paste:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kibana
  namespace: observability
  labels:
    app: kibana
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kibana
  template:
    metadata:
      labels:
        app: kibana
    spec:
      containers:
        - name: kibana
          image: docker.elastic.co/kibana/kibana:8.13.4
          ports:
            - name: http
              containerPort: 5601
          env:
            - name: ELASTICSEARCH_HOSTS
              value: '["http://elasticsearch:9200"]'
            - name: xpack.security.enabled
              value: "false"
          resources:
            requests:
              cpu: 100m
              memory: 512Mi
            limits:
              cpu: 500m
              memory: 1Gi
          readinessProbe:
            httpGet:
              path: /api/status
              port: 5601
            initialDelaySeconds: 30
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /api/status
              port: 5601
            initialDelaySeconds: 60
            periodSeconds: 15
---
apiVersion: v1
kind: Service
metadata:
  name: kibana
  namespace: observability
  labels:
    app: kibana
spec:
  type: ClusterIP
  selector:
    app: kibana
  ports:
    - name: http
      port: 5601
      targetPort: 5601
```

Line explanation:

- `kind: Deployment` because Kibana is stateless — it stores nothing locally and queries Elasticsearch for everything.
- `image: docker.elastic.co/kibana/kibana:8.13.4` must match the Elasticsearch version exactly. Kibana 8.13.4 with Elasticsearch 8.12.x will show version mismatch warnings or refuse to start.
- `ELASTICSEARCH_HOSTS: '["http://elasticsearch:9200"]'` tells Kibana where to find Elasticsearch. `elasticsearch` is the Kubernetes Service name from the `elasticsearch.yaml` above, which resolves via cluster DNS to the Elasticsearch Pod.
- `xpack.security.enabled: "false"` matches the Elasticsearch setting. Both must agree.
- The readiness and liveness probes check `/api/status`, Kibana's built-in health endpoint.
- The Service exposes port 5601, which you access via `kubectl port-forward`.

### fluent-bit.yaml

Fluent Bit is the log collector. It runs as a DaemonSet (one Pod per node) and reads the container log files that kubelet writes to `/var/log/containers/`.

```bash
vim deployment/phase-09-observability/elk-stack/fluent-bit.yaml
```

Paste:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
  namespace: observability
  labels:
    app: fluent-bit
data:
  fluent-bit.conf: |
    [SERVICE]
        Flush         5
        Log_Level     info
        Daemon        off
        Parsers_File  parsers.conf
        HTTP_Server   On
        HTTP_Listen   0.0.0.0
        HTTP_Port     2020

    [INPUT]
        Name              tail
        Tag               kube.*
        Path              /var/log/containers/*.log
        Parser            cri
        DB                /var/log/flb_kube.db
        Mem_Buf_Limit     5MB
        Skip_Long_Lines   On
        Refresh_Interval  10

    [FILTER]
        Name                kubernetes
        Match               kube.*
        Kube_URL            https://kubernetes.default.svc:443
        Kube_CA_File        /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        Kube_Token_File     /var/run/secrets/kubernetes.io/serviceaccount/token
        Kube_Tag_Prefix     kube.var.log.containers.
        Merge_Log           On
        Keep_Log            Off
        K8S-Logging.Parser  On
        K8S-Logging.Exclude Off

    [OUTPUT]
        Name            es
        Match           *
        Host            elasticsearch
        Port            9200
        Logstash_Format On
        Logstash_Prefix k8s-logs
        Suppress_Type_Name On
        Retry_Limit     3

  parsers.conf: |
    [PARSER]
        Name        cri
        Format      regex
        Regex       ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>[^ ]*) (?<log>.*)$
        Time_Key    time
        Time_Format %Y-%m-%dT%H:%M:%S.%L%z
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluent-bit
  namespace: observability
  labels:
    app: fluent-bit
spec:
  selector:
    matchLabels:
      app: fluent-bit
  template:
    metadata:
      labels:
        app: fluent-bit
    spec:
      serviceAccountName: fluent-bit
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          effect: NoSchedule
      containers:
        - name: fluent-bit
          image: fluent/fluent-bit:3.0
          ports:
            - name: http
              containerPort: 2020
          volumeMounts:
            - name: varlog
              mountPath: /var/log
              readOnly: true
            - name: config
              mountPath: /fluent-bit/etc/
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 256Mi
          readinessProbe:
            httpGet:
              path: /api/v1/health
              port: 2020
            initialDelaySeconds: 10
            periodSeconds: 10
      volumes:
        - name: varlog
          hostPath:
            path: /var/log
        - name: config
          configMap:
            name: fluent-bit-config
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fluent-bit
  namespace: observability
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: fluent-bit
rules:
  - apiGroups: [""]
    resources: ["namespaces", "pods"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: fluent-bit
subjects:
  - kind: ServiceAccount
    name: fluent-bit
    namespace: observability
roleRef:
  kind: ClusterRole
  name: fluent-bit
  apiGroup: rbac.authorization.k8s.io
```

Line explanation for the ConfigMap:

- `[SERVICE]` configures Fluent Bit globally. `Flush 5` sends buffered logs to the output every 5 seconds. `Daemon off` keeps Fluent Bit in the foreground (required in containers). `HTTP_Server On` exposes a health check endpoint on port 2020.
- `[INPUT]` with `Name tail` reads log files by tailing them (like `tail -f`). `Path /var/log/containers/*.log` matches all container log files on the node. `Parser cri` uses the CRI log format parser defined in `parsers.conf` because EKS nodes use containerd, which writes CRI-format logs. `DB /var/log/flb_kube.db` is an SQLite database that tracks which file offsets Fluent Bit has already read. On restart, it resumes from where it left off instead of re-reading everything. `Mem_Buf_Limit 5MB` caps the in-memory buffer per input to prevent runaway memory usage from a log flood.
- `[FILTER]` with `Name kubernetes` enriches each log entry with Kubernetes metadata: the Pod name, namespace, container name, labels, and annotations. It queries the Kubernetes API to get this information (using the ServiceAccount token mounted automatically). `Merge_Log On` tries to parse the log body as JSON and merge the parsed fields into the top-level record. This is useful for structured logging: if your FastAPI backend logs JSON, each field becomes a searchable field in Elasticsearch.
- `[OUTPUT]` with `Name es` sends logs to Elasticsearch. `Host elasticsearch` uses the Service DNS name. `Logstash_Format On` creates daily indices named `k8s-logs-YYYY.MM.DD`, which is the standard pattern for time-series log data in Elasticsearch. `Suppress_Type_Name On` is required for Elasticsearch 8.x, which no longer supports document type names.
- The `parsers.conf` defines the CRI log format parser. CRI logs have the format `TIMESTAMP STREAM LOGTAG MESSAGE`, for example: `2026-06-17T10:30:45.123456789Z stdout F INFO: Request received`. The regex captures each field.

Line explanation for the DaemonSet:

- `kind: DaemonSet` runs exactly one Fluent Bit Pod on every node. This is the correct pattern for log collection because each node has its own `/var/log/containers/` directory. A Deployment with 2 replicas would miss logs on nodes without a Fluent Bit Pod.
- `serviceAccountName: fluent-bit` uses the ServiceAccount created below, which has permission to read Pod and Namespace metadata from the Kubernetes API.
- `tolerations` for the control-plane taint allows Fluent Bit to run on control plane nodes too. On EKS the control plane is managed by AWS and this toleration has no effect, but it makes the manifest portable to self-managed clusters.
- `volumeMounts.name: varlog` mounts the host's `/var/log` directory read-only into the container. This is how Fluent Bit sees the container log files.
- `volumeMounts.name: config` mounts the ConfigMap as files in `/fluent-bit/etc/`, which is where Fluent Bit reads its configuration.
- The `hostPath` volume gives Fluent Bit direct access to the node's filesystem. This is one of the few legitimate uses of hostPath: the log files only exist on the node's disk and there is no other way to read them.
- The RBAC resources (ServiceAccount, ClusterRole, ClusterRoleBinding) give Fluent Bit read access to Pods and Namespaces across all namespaces. It needs this to enrich logs with metadata. The ClusterRole is cluster-wide because logs come from every namespace.

### Apply the EFK stack

```bash
kubectl apply -f deployment/phase-09-observability/elk-stack/elasticsearch.yaml
kubectl apply -f deployment/phase-09-observability/elk-stack/kibana.yaml
kubectl apply -f deployment/phase-09-observability/elk-stack/fluent-bit.yaml
```

Wait for each component:

```bash
kubectl -n observability rollout status statefulset/elasticsearch --timeout=300s
kubectl -n observability rollout status deployment/kibana --timeout=300s
kubectl -n observability rollout status daemonset/fluent-bit --timeout=120s
```

Verify:

```bash
kubectl -n observability get pods | grep -E "elasticsearch|kibana|fluent-bit"
```

Expected:

```text
elasticsearch-0          1/1     Running
kibana-...               1/1     Running
fluent-bit-...           1/1     Running   (one per node)
fluent-bit-...           1/1     Running
```

### Access Kibana

```bash
kubectl -n observability port-forward service/kibana 5601:5601 --address 0.0.0.0 &
```

Add port 5601 to the workstation security group temporarily, then open:

```text
http://YOUR_WORKSTATION_PUBLIC_IP:5601
```

### Create the index pattern in Kibana

Kibana needs to know which Elasticsearch indices to search. On first visit:

1. If Kibana shows a welcome screen, click "Explore on my own."
2. Open the hamburger menu > Stack Management > Data Views (or Index Patterns in older Kibana versions).
3. Click "Create data view."
4. In the "Index pattern" field, type: `k8s-logs-*`
5. For the "Timestamp field," select `@timestamp`.
6. Click "Save data view."
7. Go to the hamburger menu > Discover.
8. You should see log entries flowing in from all containers in the cluster.

Try searching for: `kubernetes.namespace_name: "devops-launchboard"` to see only your application's logs. Click on a log entry to see the enriched Kubernetes metadata: pod name, container name, namespace, labels.

Reference:

- Fluent Bit documentation: https://docs.fluentbit.io/manual/
- Fluent Bit Kubernetes filter: https://docs.fluentbit.io/manual/pipeline/filters/kubernetes
- Elasticsearch documentation: https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html
- Kibana documentation: https://www.elastic.co/guide/en/kibana/current/index.html

## Step 15: Install Jaeger Tracing

Jaeger is a distributed tracing platform. It receives trace data from applications, stores it, and provides a web UI for viewing request timelines across services.

In this lab, Jaeger runs in "all-in-one" mode: collector, query engine, UI, and storage all in a single Pod. Storage is in-memory, which means traces are lost when the Pod restarts. This is fine for a learning lab; production Jaeger uses Elasticsearch, Cassandra, or Kafka as the storage backend.

The app does not send traces to Jaeger yet. This step deploys the tracing platform and makes it ready to receive traces. Adding OpenTelemetry instrumentation to the FastAPI backend (which sends spans to Jaeger) is a natural next step that you can explore independently.

```bash
vim deployment/phase-09-observability/jaeger/jaeger.yaml
```

Paste:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jaeger
  namespace: observability
  labels:
    app: jaeger
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jaeger
  template:
    metadata:
      labels:
        app: jaeger
    spec:
      containers:
        - name: jaeger
          image: jaegertracing/all-in-one:1.57
          ports:
            - name: ui
              containerPort: 16686
            - name: otlp-grpc
              containerPort: 4317
            - name: otlp-http
              containerPort: 4318
            - name: zipkin
              containerPort: 9411
          env:
            - name: COLLECTOR_OTLP_ENABLED
              value: "true"
            - name: SPAN_STORAGE_TYPE
              value: memory
            - name: MEMORY_MAX_TRACES
              value: "10000"
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
          readinessProbe:
            httpGet:
              path: /
              port: 16686
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /
              port: 16686
            initialDelaySeconds: 15
            periodSeconds: 15
---
apiVersion: v1
kind: Service
metadata:
  name: jaeger
  namespace: observability
  labels:
    app: jaeger
spec:
  type: ClusterIP
  selector:
    app: jaeger
  ports:
    - name: ui
      port: 16686
      targetPort: 16686
    - name: otlp-grpc
      port: 4317
      targetPort: 4317
    - name: otlp-http
      port: 4318
      targetPort: 4318
    - name: zipkin
      port: 9411
      targetPort: 9411
```

Line explanation:

- `image: jaegertracing/all-in-one:1.57` runs the all-in-one image that bundles the collector (receives traces), the query service (serves the UI and API), and an in-memory storage backend in a single binary.
- `port: 16686` is the Jaeger UI and query API. You access this through port-forward.
- `port: 4317` is the OTLP (OpenTelemetry Protocol) gRPC receiver. If you instrument the FastAPI backend with the OpenTelemetry Python SDK, the SDK sends spans to this port.
- `port: 4318` is the OTLP HTTP receiver, an alternative to gRPC for environments where gRPC is harder to configure.
- `port: 9411` is the Zipkin-compatible receiver. Some older tracing libraries use the Zipkin format.
- `COLLECTOR_OTLP_ENABLED: "true"` enables the OTLP receiver. Without this, Jaeger only accepts its own native Thrift format.
- `SPAN_STORAGE_TYPE: memory` stores traces in RAM. Fast and simple, but traces are lost on Pod restart. Production Jaeger uses `elasticsearch` or `cassandra` as the storage type.
- `MEMORY_MAX_TRACES: "10000"` caps stored traces at 10,000. Oldest traces are evicted when the limit is reached. This prevents unbounded memory growth.
- The Service exposes all four ports so applications in any namespace can send traces to `jaeger.observability.svc.cluster.local:4317`.

Apply:

```bash
kubectl apply -f deployment/phase-09-observability/jaeger/jaeger.yaml
kubectl -n observability rollout status deployment/jaeger --timeout=180s
```

### Access Jaeger UI

```bash
kubectl -n observability port-forward service/jaeger 16686:16686 --address 0.0.0.0 &
```

Add port 16686 to the workstation security group temporarily, then open:

```text
http://YOUR_WORKSTATION_PUBLIC_IP:16686
```

The Jaeger UI shows a "Search" page with a Service dropdown. Since no application has sent traces yet, the dropdown is empty or shows only `jaeger-all-in-one` (Jaeger traces itself). This is expected. When you later add OpenTelemetry instrumentation to the backend, traces from `launchboard-backend` will appear here.

What a trace looks like (for context):

A trace represents one end-to-end request. It consists of spans. Each span is one unit of work: "frontend received HTTP request" → "frontend called backend /api/summary" → "backend queried PostgreSQL" → "PostgreSQL returned rows." Jaeger displays these as a waterfall timeline showing which span started when, how long it took, and which service produced it. This is how you find out that a slow request spent 800ms waiting for a database query and only 5ms in application logic.

Reference:

- Jaeger documentation: https://www.jaegertracing.io/docs/
- OpenTelemetry Python SDK: https://opentelemetry.io/docs/languages/python/
- OTLP specification: https://opentelemetry.io/docs/specs/otlp/

## Step 16: Verify The Full Observability Stack

Run all checks:

```bash
echo "=== Application ==="
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard get ingress

echo ""
echo "=== Prometheus + Grafana ==="
kubectl -n observability get pods | grep -E "prometheus|grafana|node-exporter|kube-state"

echo ""
echo "=== EFK Logging ==="
kubectl -n observability get pods | grep -E "elasticsearch|kibana|fluent-bit"

echo ""
echo "=== Jaeger ==="
kubectl -n observability get pods | grep jaeger

echo ""
echo "=== Storage ==="
kubectl -n observability get pvc
kubectl -n devops-launchboard get pvc
```

Expected:

```text
=== Application ===
All Pods Running, Ingress has ALB address

=== Prometheus + Grafana ===
alertmanager-...         Running
kube-prometheus-stack-grafana-...   Running
kube-prometheus-stack-kube-state-metrics-...  Running
kube-prometheus-stack-operator-...  Running
kube-prometheus-stack-prometheus-node-exporter-...  Running (one per node)
prometheus-kube-prometheus-stack-prometheus-0  Running

=== EFK Logging ===
elasticsearch-0          Running
kibana-...               Running
fluent-bit-...           Running (one per node)

=== Jaeger ===
jaeger-...               Running

=== Storage ===
PVCs for Prometheus and Elasticsearch show Bound
PVC for PostgreSQL shows Bound
```

Quick access summary for your browser (all require port-forward and security group rules):

| Tool | Port-Forward Command | URL |
| --- | --- | --- |
| App | via ALB | `http://YOUR_ALB_DNS_NAME` |
| Grafana | `kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80 --address 0.0.0.0 &` | `http://WORKSTATION_IP:3000` |
| Prometheus | `kubectl -n observability port-forward svc/kube-prometheus-stack-prometheus 9090:9090 --address 0.0.0.0 &` | `http://WORKSTATION_IP:9090` |
| Kibana | `kubectl -n observability port-forward svc/kibana 5601:5601 --address 0.0.0.0 &` | `http://WORKSTATION_IP:5601` |
| Jaeger | `kubectl -n observability port-forward svc/jaeger 16686:16686 --address 0.0.0.0 &` | `http://WORKSTATION_IP:16686` |

## Troubleshooting

### Problem 1: Prometheus Or Grafana Pods Pending

```bash
kubectl -n observability describe pod POD_NAME
kubectl get nodes -o wide
kubectl top nodes
```

Common causes: not enough CPU or memory on the worker nodes. The kube-prometheus-stack plus EFK plus the application can exceed what 2 × t3.medium (4 GB each) can handle, especially when Elasticsearch is running. Fix: scale the node group to 3 nodes:

```bash
eksctl scale nodegroup --cluster devops-launchboard-phase-9 \
  --name launchboard-workers --nodes 3 --region "$AWS_REGION"
```

### Problem 2: Elasticsearch Does Not Start

```bash
kubectl -n observability describe statefulset elasticsearch
kubectl -n observability logs elasticsearch-0
kubectl -n observability get pvc
```

Common causes: PVC not bound (EBS CSI driver missing or StorageClass not created), not enough memory (Elasticsearch needs at least 1 GB), or the init container failed to fix permissions on the data directory. If the PVC is Pending, check `kubectl get sc` for `gp3-encrypted` and `kubectl get pods -n kube-system | grep ebs` for the CSI driver.

### Problem 3: Fluent Bit Pods In CrashLoopBackOff

```bash
kubectl -n observability logs daemonset/fluent-bit
```

Common causes: Elasticsearch is not reachable (check that the `elasticsearch` Service exists and the Pod is Running), or the Fluent Bit config has a syntax error (check the ConfigMap content).

### Problem 4: Kibana Shows No Logs

```bash
kubectl -n observability port-forward service/elasticsearch 9200:9200 &
curl -s http://127.0.0.1:9200/_cat/indices
```

If no `k8s-logs-*` indices appear: Fluent Bit is not sending data to Elasticsearch. Check Fluent Bit logs. If indices exist but Kibana shows nothing: you need to create the data view (Step 14, "Create the index pattern in Kibana").

### Problem 5: Grafana Dashboards Are Empty

```bash
kubectl -n observability port-forward service/kube-prometheus-stack-prometheus 9090:9090 &
curl -s http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets | length'
```

If the target count is 0: Prometheus is not scraping anything. Check that `serviceMonitorSelectorNilUsesHelmValues: false` is set in the Helm values and that the Prometheus Pod is Running. If targets exist but dashboards are empty: wait 2 to 3 minutes for the first scrape cycle, then refresh the dashboard.

### Problem 6: Port-Forward Dies After SSH Disconnect

When you close the SSH session, background port-forward processes are killed. Reconnect and re-run the port-forward commands. For a more persistent setup, use `nohup`:

```bash
nohup kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80 --address 0.0.0.0 > /dev/null 2>&1 &
```

## Cleanup

Stop all port-forwards:

```bash
pkill -f "port-forward"
```

Delete observability tools:

```bash
helm uninstall kube-prometheus-stack --namespace observability
kubectl delete -f deployment/phase-09-observability/jaeger/jaeger.yaml
kubectl delete -f deployment/phase-09-observability/elk-stack/fluent-bit.yaml
kubectl delete -f deployment/phase-09-observability/elk-stack/kibana.yaml
kubectl delete -f deployment/phase-09-observability/elk-stack/elasticsearch.yaml
kubectl delete namespace observability
```

Note: deleting the observability namespace also deletes the PVCs for Prometheus and Elasticsearch, which triggers deletion of the underlying EBS volumes (because `reclaimPolicy: Delete`).

Delete the application:

```bash
kubectl delete namespace devops-launchboard
```

Wait 2 to 3 minutes for the ALB to be deleted by the Load Balancer Controller.

Delete the Load Balancer Controller:

```bash
helm uninstall aws-load-balancer-controller --namespace kube-system
eksctl delete iamserviceaccount \
  --cluster devops-launchboard-phase-9 \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --region "$AWS_REGION"
```

Delete the EKS cluster (10 to 20 minutes):

```bash
eksctl delete cluster --name devops-launchboard-phase-9 --region "$AWS_REGION"
```

Delete ECR repositories:

```bash
aws ecr delete-repository --repository-name launchboard-backend --force --region "$AWS_REGION"
aws ecr delete-repository --repository-name launchboard-frontend --force --region "$AWS_REGION"
```

Delete the IAM policy:

```bash
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicyPhase9"
aws iam delete-policy --policy-arn "$POLICY_ARN"
```

Check the AWS Console for leftover resources:

```text
EC2 > Load Balancers (should be empty)
EC2 > Target Groups (should be empty)
EC2 > Volumes (check for orphaned EBS volumes)
VPC > NAT Gateways (should be deleted by eksctl)
VPC > Elastic IPs (should be released)
CloudWatch > Log Groups (cluster logs remain, delete manually)
```

Terminate the workstation EC2 from the AWS Console.

## Production Checklist

```text
[ ] AWS Budget created
[ ] EKS cluster created
[ ] App images pushed to ECR
[ ] App deployed to EKS
[ ] ALB URL works
[ ] CORS updated to ALB DNS

=== Metrics ===
[ ] kube-prometheus-stack Helm chart installed
[ ] Prometheus Pod running with EBS PVC
[ ] Grafana accessible via port-forward
[ ] Grafana login works
[ ] Kubernetes Cluster dashboard shows data
[ ] Node Exporter Full dashboard shows data
[ ] Kubernetes Pods dashboard shows launchboard pods
[ ] Prometheus targets page shows active scrape targets

=== Logs ===
[ ] Elasticsearch StatefulSet running with EBS PVC
[ ] Kibana Deployment running
[ ] Fluent Bit DaemonSet running (one Pod per node)
[ ] Kibana accessible via port-forward
[ ] k8s-logs-* data view created in Kibana
[ ] Logs from devops-launchboard namespace visible in Discover
[ ] Kubernetes metadata (pod name, namespace, labels) present in log entries

=== Traces ===
[ ] Jaeger Deployment running
[ ] Jaeger UI accessible via port-forward
[ ] OTLP ports 4317 and 4318 exposed via Service

=== Cleanup ===
[ ] Cleanup plan understood
[ ] AWS Budget reviewed for surprise charges
```

## Reference Documentation

| Topic | Link |
| --- | --- |
| Amazon EKS | https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html |
| kube-prometheus-stack Helm chart | https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack |
| Prometheus documentation | https://prometheus.io/docs/ |
| PromQL basics | https://prometheus.io/docs/prometheus/latest/querying/basics/ |
| Grafana documentation | https://grafana.com/docs/grafana/latest/ |
| Grafana dashboard library | https://grafana.com/grafana/dashboards/ |
| Fluent Bit documentation | https://docs.fluentbit.io/manual/ |
| Fluent Bit Kubernetes filter | https://docs.fluentbit.io/manual/pipeline/filters/kubernetes |
| Elasticsearch documentation | https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html |
| Kibana documentation | https://www.elastic.co/guide/en/kibana/current/index.html |
| Jaeger documentation | https://www.jaegertracing.io/docs/ |
| OpenTelemetry Python SDK | https://opentelemetry.io/docs/languages/python/ |
| OTLP specification | https://opentelemetry.io/docs/specs/otlp/ |

## What To Do Next

Move to:

```text
Phase 10: Security
```

Why:

After you can observe the platform with metrics, logs, and traces, the next step is to harden it with security controls: image scanning, Pod security policies, network policies, secrets management with AWS Secrets Manager, IAM least-privilege, and runtime security monitoring.
