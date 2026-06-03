# Phase 12: Disaster Recovery

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
- You will install Velero for Kubernetes backup and restore.
- You will create PostgreSQL dumps for database-level recovery.
- You will run a small chaos test manually.
- You will use `vim` to create files.
- You will not use custom shell scripts.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What This Phase Deploys

This phase deploys the N-tier application on Amazon EKS and then practices disaster recovery.

The deployment includes:

- Vite frontend served by Nginx
- FastAPI backend
- PostgreSQL database running inside Kubernetes for the lab
- Amazon ECR repositories
- Amazon EKS cluster
- AWS Load Balancer Controller
- Velero backups stored in S3
- EBS volume snapshots through Velero
- Manual PostgreSQL dump and restore commands
- LitmusChaos pod-delete experiment
- Incident response and recovery runbooks

## When To Use This Architecture

Use this phase when:

- You want to learn how production teams prepare for failure.
- You need Kubernetes namespace backup and restore.
- You need persistent volume snapshot recovery.
- You need database dump recovery practice.
- You want to test whether the app survives pod failure.
- You want students to understand RTO and RPO.

Do not use this phase as the first deployment if:

- You only want to see the app running quickly.
- You are not ready for EKS, S3, snapshots, and load balancer costs.
- You do not have time to test restore.

Important production idea:

Backups are not useful until restore is tested. This phase focuses on both backup and restore.

## Recommended AWS Setup

| Item | Recommended Value |
| --- | --- |
| AWS Region | `ap-southeast-1` or the closest region |
| Cluster Name | `devops-launchboard-phase-12` |
| Kubernetes Version | `1.34` |
| Node Type | `t3.medium` |
| Desired Nodes | `2` |
| ECR Backend Repo | `launchboard-backend` |
| ECR Frontend Repo | `launchboard-frontend` |
| Velero Bucket | `devops-launchboard-velero-YOUR_ACCOUNT_ID-YOUR_AWS_REGION` |
| Backup Schedule | Daily at 03:00 |
| Backup TTL | 7 days |

Cost warning:

- EKS costs money.
- EC2 worker nodes cost money.
- EBS volumes and snapshots cost money.
- S3 backup storage costs money.
- Load balancers cost money.
- Delete resources after practice.

Reference:

- EKS pricing: https://aws.amazon.com/eks/pricing/
- S3 pricing: https://aws.amazon.com/s3/pricing/
- AWS Budgets: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html

## Architecture

```text
Browser
  |
  v
AWS Application Load Balancer
  |
  v
Frontend pods
  |
  v
Backend pods
  |
  v
PostgreSQL pod
  |
  v
PersistentVolumeClaim backed by EBS

Recovery tools:

Velero backs up Kubernetes resources.
Velero snapshots EBS volumes.
S3 stores backup metadata.
PostgreSQL dump gives database-level restore.
Runbooks guide the human recovery process.
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
velero version --client-only
```

Install missing tools:

- Git: https://git-scm.com/downloads
- Docker: https://docs.docker.com/get-docker/
- AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- kubectl: https://kubernetes.io/docs/tasks/tools/
- eksctl: https://eksctl.io/installation/
- Helm: https://helm.sh/docs/intro/install/
- Velero CLI: https://velero.io/docs/

Why this step exists:

Disaster recovery uses more than app deployment tools. You need AWS CLI for cloud resources, Docker for images, Kubernetes tools for app resources, and Velero for backup and restore.

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
export VELERO_BUCKET=devops-launchboard-velero-$AWS_ACCOUNT_ID-$AWS_REGION
```

Why this step exists:

The variables keep later commands short and reduce copy-paste mistakes. The bucket name includes account and region so it is more likely to be globally unique.

## Step 3: Create SSH Key And Clone

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-12" -f ~/.ssh/devops_launchboard_phase_12
cat ~/.ssh/devops_launchboard_phase_12.pub
```

Add the public key to GitHub, then create SSH config:

```bash
vim ~/.ssh/config
```

Paste:

```text
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/devops_launchboard_phase_12
  IdentitiesOnly yes
```

Run:

```bash
chmod 600 ~/.ssh/config
chmod 600 ~/.ssh/devops_launchboard_phase_12
chmod 644 ~/.ssh/devops_launchboard_phase_12.pub
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

The machine must have the source code before it can build images or create deployment files. SSH keeps GitHub access key-based instead of password-based.

## Step 4: Create Phase 12 Folders

Run:

```bash
mkdir -p deployment/phase-12-disaster-recovery/cluster
mkdir -p deployment/phase-12-disaster-recovery/ecr
mkdir -p deployment/phase-12-disaster-recovery/app-k8s
mkdir -p deployment/phase-12-disaster-recovery/backup
mkdir -p deployment/phase-12-disaster-recovery/disaster-recovery
mkdir -p deployment/phase-12-disaster-recovery/chaos-engineering
mkdir -p deployment/phase-12-disaster-recovery/runbooks
```

Why these folders exist:

- `cluster` stores the EKS cluster definition.
- `ecr` stores image cleanup policy.
- `app-k8s` stores the app deployment.
- `backup` stores Velero backup and restore files.
- `disaster-recovery` stores recovery planning documents.
- `chaos-engineering` stores failure test files.
- `runbooks` stores step-by-step incident documents.

## Step 5: Create EKS Cluster

Create:

```bash
vim deployment/phase-12-disaster-recovery/cluster/eksctl-cluster.yaml
```

Paste:

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: devops-launchboard-phase-12
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
      Environment: phase-12
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
eksctl create cluster -f deployment/phase-12-disaster-recovery/cluster/eksctl-cluster.yaml
kubectl get nodes
```

Why this file exists:

The app needs a Kubernetes platform before backup and recovery can be tested. The EBS CSI driver is important because PostgreSQL uses persistent storage, and Velero can snapshot that storage.

## Step 6: Create ECR And Build Images

Create repositories:

```bash
aws ecr create-repository --repository-name launchboard-backend --region $AWS_REGION
aws ecr create-repository --repository-name launchboard-frontend --region $AWS_REGION
```

Create lifecycle policy:

```bash
vim deployment/phase-12-disaster-recovery/ecr/lifecycle-policy.json
```

Paste:

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep the latest 10 phase 12 images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["phase-12"],
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
aws ecr put-lifecycle-policy --repository-name launchboard-backend --lifecycle-policy-text file://deployment/phase-12-disaster-recovery/ecr/lifecycle-policy.json --region $AWS_REGION
aws ecr put-lifecycle-policy --repository-name launchboard-frontend --lifecycle-policy-text file://deployment/phase-12-disaster-recovery/ecr/lifecycle-policy.json --region $AWS_REGION
```

Build and push:

```bash
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

docker build -f deployment/phase-12-disaster-recovery/Dockerfile.backend -t launchboard-backend:phase-12 .
docker build -f deployment/phase-12-disaster-recovery/Dockerfile.frontend --build-arg VITE_API_URL=/api -t launchboard-frontend:phase-12 .

docker tag launchboard-backend:phase-12 $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-12
docker tag launchboard-frontend:phase-12 $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-frontend:phase-12

docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-12
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-frontend:phase-12
```

Why this step exists:

Kubernetes pulls app images from ECR. The lifecycle policy prevents old lab images from staying forever and creating storage clutter.

## Step 7: Deploy The Application

Create app files in:

```text
deployment/phase-12-disaster-recovery/app-k8s
```

Use `vim` to create the files from this phase folder:

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
cd deployment/phase-12-disaster-recovery/app-k8s
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
kubectl apply -f deployment/phase-12-disaster-recovery/app-k8s/secret.yaml
kubectl apply -k deployment/phase-12-disaster-recovery/app-k8s
kubectl -n devops-launchboard get pods
```

Why this step exists:

Recovery practice is meaningful only when a real app is running. This app gives students frontend, backend, database, persistent volume, service, ingress, and migration resources to protect.

## Step 8: Install AWS Load Balancer Controller

Run:

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

eksctl create iamserviceaccount \
  --cluster devops-launchboard-phase-12 \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --role-name devops-launchboard-phase-12-alb-controller \
  --attach-policy-arn arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess \
  --approve

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=devops-launchboard-phase-12 \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

Verify:

```bash
kubectl -n devops-launchboard get ingress
```

Why this step exists:

The Ingress resource needs the AWS Load Balancer Controller to create a real Application Load Balancer.

## Step 9: Create Velero S3 Bucket

Run:

```bash
aws s3api create-bucket \
  --bucket $VELERO_BUCKET \
  --region $AWS_REGION \
  --create-bucket-configuration LocationConstraint=$AWS_REGION

aws s3api put-bucket-versioning \
  --bucket $VELERO_BUCKET \
  --versioning-configuration Status=Enabled
```

Why this step exists:

Velero stores backup metadata in object storage. S3 versioning adds another safety layer because overwritten or deleted backup objects are easier to investigate.

## Step 10: Create Velero IAM Policy

Create:

```bash
vim deployment/phase-12-disaster-recovery/backup/velero-aws-policy.json
```

Paste:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeVolumes",
        "ec2:DescribeSnapshots",
        "ec2:DescribeAvailabilityZones",
        "ec2:CreateVolume",
        "ec2:DeleteVolume",
        "ec2:CreateSnapshot",
        "ec2:DeleteSnapshot",
        "ec2:AttachVolume",
        "ec2:DetachVolume",
        "ec2:CreateTags",
        "ec2:DescribeVolumeAttribute",
        "ec2:DescribeVolumeStatus",
        "ec2:DescribeInstances"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:PutObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": "arn:aws:s3:::YOUR_VELERO_BUCKET/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::YOUR_VELERO_BUCKET"
    }
  ]
}
```

Replace:

```text
YOUR_VELERO_BUCKET
```

Create policy:

```bash
aws iam create-policy \
  --policy-name devops-launchboard-phase-12-velero \
  --policy-document file://deployment/phase-12-disaster-recovery/backup/velero-aws-policy.json
```

Create service account:

```bash
eksctl create iamserviceaccount \
  --cluster devops-launchboard-phase-12 \
  --namespace velero \
  --name velero \
  --role-name devops-launchboard-phase-12-velero \
  --attach-policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/devops-launchboard-phase-12-velero \
  --approve
```

Why this file exists:

Velero needs permission to write backup data to S3 and create/restore EBS snapshots. The policy gives those permissions to the Velero service account instead of using broad user credentials inside the cluster.

Reference:

- Velero AWS plugin: https://github.com/vmware-tanzu/velero-plugin-for-aws
- Velero AWS install guide: https://velero.io/docs/

## Step 11: Install Velero

Run:

```bash
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.13.0 \
  --bucket $VELERO_BUCKET \
  --backup-location-config region=$AWS_REGION \
  --snapshot-location-config region=$AWS_REGION \
  --namespace velero \
  --service-account-name velero \
  --no-secret
```

Verify:

```bash
kubectl -n velero get pods
velero backup-location get
```

Why this step exists:

Velero runs inside Kubernetes and watches backup/restore resources. The AWS plugin lets it store metadata in S3 and snapshot EBS volumes.

## Step 12: Create Scheduled And Manual Backups

Create schedule:

```bash
vim deployment/phase-12-disaster-recovery/backup/velero-schedule.yaml
```

Paste:

```yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: launchboard-daily
  namespace: velero
spec:
  schedule: "0 3 * * *"
  template:
    includedNamespaces:
      - devops-launchboard
    snapshotVolumes: true
    ttl: 168h0m0s
    storageLocation: default
    volumeSnapshotLocations:
      - default
```

Create manual backup:

```bash
vim deployment/phase-12-disaster-recovery/backup/velero-backup.yaml
```

Paste:

```yaml
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: launchboard-manual
  namespace: velero
spec:
  includedNamespaces:
    - devops-launchboard
  snapshotVolumes: true
  ttl: 168h0m0s
  storageLocation: default
  volumeSnapshotLocations:
    - default
```

Apply:

```bash
kubectl apply -f deployment/phase-12-disaster-recovery/backup/velero-schedule.yaml
kubectl apply -f deployment/phase-12-disaster-recovery/backup/velero-backup.yaml
velero backup get
velero backup describe launchboard-manual --details
```

Why these files exist:

The schedule creates automatic daily backups. The manual backup lets students create a known restore point before running a failure test.

## Step 13: Create PostgreSQL Dump

Run:

```bash
kubectl -n devops-launchboard exec deploy/launchboard-db -- pg_dump -U launchboard_user -d launchboard > launchboard-db-backup.sql
ls -lh launchboard-db-backup.sql
```

Why this step exists:

Velero protects Kubernetes resources and volumes. A PostgreSQL dump protects the database at the SQL level. Real production systems often use both infrastructure backups and database-native backups.

## Step 14: Simulate Failure

Delete one backend pod:

```bash
kubectl -n devops-launchboard get pods -l app=launchboard-backend
kubectl -n devops-launchboard delete pod POD_NAME
kubectl -n devops-launchboard get pods -w
```

Expected:

```text
Kubernetes creates a replacement pod.
The app remains available if another backend replica is ready.
```

Why this step exists:

This is the simplest chaos test. It proves Kubernetes can recover from one pod failure.

## Step 15: Optional LitmusChaos Pod Delete Test

Install LitmusChaos:

```bash
helm repo add litmuschaos https://litmuschaos.github.io/litmus-helm/
helm repo update
helm upgrade --install litmuschaos litmuschaos/litmus \
  --namespace litmus \
  --create-namespace
```

Create RBAC:

```bash
vim deployment/phase-12-disaster-recovery/chaos-engineering/litmus-rbac.yaml
```

Create experiment:

```bash
vim deployment/phase-12-disaster-recovery/chaos-engineering/pod-delete-chaosengine.yaml
```

Apply:

```bash
kubectl apply -f deployment/phase-12-disaster-recovery/chaos-engineering/litmus-rbac.yaml
kubectl apply -f deployment/phase-12-disaster-recovery/chaos-engineering/pod-delete-chaosengine.yaml
kubectl -n devops-launchboard get chaosengine
```

Why this step exists:

Chaos testing intentionally creates controlled failure. Students learn whether readiness probes, replicas, and recovery habits are good enough before a real incident happens.

Reference:

- LitmusChaos docs: https://litmuschaos.io/docs/

## Step 16: Restore Kubernetes Resources With Velero

Create restore file:

```bash
vim deployment/phase-12-disaster-recovery/backup/velero-restore.yaml
```

Paste:

```yaml
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: launchboard-restore
  namespace: velero
spec:
  backupName: launchboard-manual
  includedNamespaces:
    - devops-launchboard
  existingResourcePolicy: update
```

Practice restore:

```bash
kubectl apply -f deployment/phase-12-disaster-recovery/backup/velero-restore.yaml
velero restore get
velero restore describe launchboard-restore --details
kubectl -n devops-launchboard get pods
```

Why this step exists:

A backup is only trusted after restore succeeds. This restore object tells Velero to restore resources from the `launchboard-manual` backup.

## Step 17: Restore PostgreSQL From Dump

Only do this in a lab or during an approved recovery window.

Run:

```bash
cat launchboard-db-backup.sql | kubectl -n devops-launchboard exec -i deploy/launchboard-db -- psql -U launchboard_user -d launchboard
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
kubectl -n devops-launchboard rollout status deployment/launchboard-backend
```

Why this step exists:

Database-level restore is useful when Kubernetes resources are healthy but the data is damaged. This command streams the SQL backup from your machine into the PostgreSQL pod.

## Step 18: Create Runbooks

Create:

```bash
vim deployment/phase-12-disaster-recovery/disaster-recovery/failover-plan.md
vim deployment/phase-12-disaster-recovery/disaster-recovery/rto-rpo.md
vim deployment/phase-12-disaster-recovery/runbooks/incident-response.md
vim deployment/phase-12-disaster-recovery/runbooks/recovery-checklist.md
vim deployment/phase-12-disaster-recovery/runbooks/rollback-procedures.md
```

Why these files exist:

During an incident, people are stressed. Runbooks reduce guessing. They define who leads, which commands to run, how to verify recovery, and what to record afterward.

## Verification Commands

Check app:

```bash
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard get svc
kubectl -n devops-launchboard get ingress
```

Check Velero:

```bash
kubectl -n velero get pods
velero backup get
velero schedule get
velero restore get
```

Check database backup:

```bash
ls -lh launchboard-db-backup.sql
```

Check health:

```bash
kubectl -n devops-launchboard logs deploy/launchboard-backend
kubectl -n devops-launchboard logs deploy/launchboard-frontend
```

## Troubleshooting

Problem: Velero backup is stuck.

Cause:

```text
Velero cannot write to S3, cannot create snapshots, or the IAM role is wrong.
```

Fix:

```bash
kubectl -n velero logs deploy/velero
velero backup describe launchboard-manual --details
aws s3 ls s3://$VELERO_BUCKET
```

Problem: PostgreSQL dump fails.

Cause:

```text
Database pod is not ready, username is wrong, or database name is wrong.
```

Fix:

```bash
kubectl -n devops-launchboard get pods -l app=launchboard-db
kubectl -n devops-launchboard logs deploy/launchboard-db
```

Problem: restore creates resources but app still fails.

Cause:

```text
Secret values, image tags, or database readiness may still be wrong.
```

Fix:

```bash
kubectl -n devops-launchboard get events --sort-by=.lastTimestamp
kubectl -n devops-launchboard describe pod POD_NAME
kubectl -n devops-launchboard get secret launchboard-secret
```

## Cleanup

Delete Litmus:

```bash
helm uninstall litmuschaos -n litmus
kubectl delete namespace litmus
```

Delete Velero backups and install:

```bash
velero backup delete launchboard-manual --confirm
kubectl delete -f deployment/phase-12-disaster-recovery/backup/velero-schedule.yaml
kubectl delete namespace velero
```

Delete app:

```bash
kubectl delete -f deployment/phase-12-disaster-recovery/app-k8s/secret.yaml
kubectl delete -k deployment/phase-12-disaster-recovery/app-k8s
```

Delete cluster:

```bash
eksctl delete cluster -f deployment/phase-12-disaster-recovery/cluster/eksctl-cluster.yaml
```

Delete ECR and S3:

```bash
aws ecr delete-repository --repository-name launchboard-backend --force --region $AWS_REGION
aws ecr delete-repository --repository-name launchboard-frontend --force --region $AWS_REGION
aws s3 rm s3://$VELERO_BUCKET --recursive
aws s3api delete-bucket --bucket $VELERO_BUCKET --region $AWS_REGION
```

Why cleanup matters:

Disaster recovery labs create snapshots, S3 objects, clusters, nodes, and load balancers. These can keep charging after the lesson.

## Production Checklist

```text
[ ] AWS credentials configured
[ ] Repository cloned with SSH
[ ] EKS cluster created
[ ] ECR repositories created
[ ] Images pushed
[ ] Application deployed
[ ] ALB working
[ ] Velero bucket created
[ ] Velero IAM policy created
[ ] Velero installed
[ ] Manual Velero backup completed
[ ] Scheduled Velero backup created
[ ] PostgreSQL dump created
[ ] Pod failure tested
[ ] Velero restore tested
[ ] PostgreSQL restore command tested in lab
[ ] RTO documented
[ ] RPO documented
[ ] Incident runbooks created
[ ] Cleanup completed
```

## Reference Documentation

| Topic | Official Link |
| --- | --- |
| EKS | https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html |
| ECR | https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html |
| EBS CSI Driver | https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html |
| Velero | https://velero.io/docs/ |
| Velero AWS Plugin | https://github.com/vmware-tanzu/velero-plugin-for-aws |
| S3 | https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html |
| Kubernetes Backup Concepts | https://kubernetes.io/docs/concepts/storage/volume-snapshots/ |
| PostgreSQL pg_dump | https://www.postgresql.org/docs/current/app-pgdump.html |
| LitmusChaos | https://litmuschaos.io/docs/ |

## Next Step

Review the full deployment track and run a game-day exercise where students follow the runbooks without help.
