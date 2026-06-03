# Phase 14: Disaster Recovery

## Fresh Start Assumption

This phase starts from a clean machine and a clean AWS setup.

You do not need to complete any previous phase before using this phase.

This guide assumes:

- You have an AWS account.
- You have GitHub access to this repository.
- You will clone the repository with SSH.
- You will create a new EKS cluster for this phase.
- You will create fresh ECR repositories.
- You will deploy the N-tier app from scratch.
- You will configure Kubernetes and PostgreSQL backup paths.
- You will test restore, rollback, and cluster rebuild thinking.
- You will use `vim` to create files.
- You will not use custom shell scripts.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What This Phase Deploys

This phase deploys the app and adds disaster recovery controls:

- Vite frontend served by Nginx
- FastAPI backend
- PostgreSQL running in Kubernetes for the lab
- EKS cluster
- ECR repositories
- AWS Load Balancer Controller
- Velero backup and restore
- S3 backup bucket with lifecycle policy
- EBS volume snapshots
- PostgreSQL dump CronJob
- Restore job example
- Incident response runbooks
- Cluster rebuild runbook

## When To Use This Architecture

Use this architecture when:

- The application is important enough that downtime matters.
- You need a tested restore process.
- You want students to learn RTO and RPO.
- You need Kubernetes resource backup and persistent volume snapshots.
- You want both platform-level backup and database-level backup.
- You want a realistic recovery drill, not only a deployment guide.

Do not use this phase when:

- You only need a quick demo.
- You cannot afford EKS, S3, EBS snapshots, and load balancer costs.
- You are not ready to test restore.

Important idea:

```text
A backup that has never been restored is only a hope, not a recovery plan.
```

## RTO And RPO

| Term | Meaning | Lab Target |
| --- | --- | --- |
| RTO | How long recovery should take | 30 minutes |
| RPO | How much data loss is acceptable | Last successful backup |

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
EBS-backed PVC

Disaster recovery:

Velero backs up Kubernetes resources and EBS snapshots.
S3 stores Velero backup metadata.
PostgreSQL CronJob creates SQL dump files.
Runbooks guide human recovery decisions.
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

Disaster recovery touches AWS, Kubernetes, Docker images, S3, snapshots, and Velero. Checking tools first avoids getting blocked halfway through the lab.

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
export DR_BUCKET=devops-launchboard-dr-$AWS_ACCOUNT_ID-$AWS_REGION
```

Why this step exists:

The AWS CLI needs credentials before it can create EKS, ECR, IAM, S3, and load balancer resources. The variables keep later commands easier to read.

## Step 3: Create SSH Key And Clone

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-14" -f ~/.ssh/devops_launchboard_phase_14
cat ~/.ssh/devops_launchboard_phase_14.pub
```

Add the printed public key in GitHub.

Create SSH config:

```bash
vim ~/.ssh/config
```

Paste:

```text
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/devops_launchboard_phase_14
  IdentitiesOnly yes
```

Run:

```bash
chmod 600 ~/.ssh/config
chmod 600 ~/.ssh/devops_launchboard_phase_14
chmod 644 ~/.ssh/devops_launchboard_phase_14.pub
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

Students need the app source code and phase files before they can build images, deploy Kubernetes resources, or create recovery files.

## Step 4: Create Phase 14 Folders

Run:

```bash
mkdir -p deployment/phase-14-disaster-recovery/cluster
mkdir -p deployment/phase-14-disaster-recovery/ecr
mkdir -p deployment/phase-14-disaster-recovery/app-k8s
mkdir -p deployment/phase-14-disaster-recovery/aws
mkdir -p deployment/phase-14-disaster-recovery/velero
mkdir -p deployment/phase-14-disaster-recovery/backups
mkdir -p deployment/phase-14-disaster-recovery/runbooks
```

Why these folders exist:

- `cluster` stores the EKS cluster definition.
- `ecr` stores image cleanup policy.
- `app-k8s` stores app manifests.
- `aws` stores IAM and S3 policies.
- `velero` stores Kubernetes backup and restore objects.
- `backups` stores PostgreSQL dump resources.
- `runbooks` stores human recovery instructions.

## Step 5: Create EKS Cluster

Create:

```bash
vim deployment/phase-14-disaster-recovery/cluster/eksctl-cluster.yaml
```

Paste:

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: devops-launchboard-phase-14
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
      Environment: phase-14
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
eksctl create cluster -f deployment/phase-14-disaster-recovery/cluster/eksctl-cluster.yaml
kubectl get nodes
```

Why this file exists:

This creates the Kubernetes environment that the app and recovery tools run on. EBS CSI is required because PostgreSQL uses persistent storage and Velero needs snapshot support.

## Step 6: Create ECR And Build Images

Create ECR repositories:

```bash
aws ecr create-repository --repository-name launchboard-backend --region $AWS_REGION
aws ecr create-repository --repository-name launchboard-frontend --region $AWS_REGION
```

Create lifecycle policy:

```bash
vim deployment/phase-14-disaster-recovery/ecr/lifecycle-policy.json
```

Paste:

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep the latest 10 phase 14 images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["phase-14"],
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
aws ecr put-lifecycle-policy --repository-name launchboard-backend --lifecycle-policy-text file://deployment/phase-14-disaster-recovery/ecr/lifecycle-policy.json --region $AWS_REGION
aws ecr put-lifecycle-policy --repository-name launchboard-frontend --lifecycle-policy-text file://deployment/phase-14-disaster-recovery/ecr/lifecycle-policy.json --region $AWS_REGION
```

Create Dockerfiles with `vim`:

```bash
vim deployment/phase-14-disaster-recovery/Dockerfile.backend
vim deployment/phase-14-disaster-recovery/Dockerfile.frontend
vim deployment/phase-14-disaster-recovery/nginx-frontend.conf
```

Use the production file contents stored in this phase folder.

Build and push:

```bash
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

docker build -f deployment/phase-14-disaster-recovery/Dockerfile.backend -t launchboard-backend:phase-14 .
docker build -f deployment/phase-14-disaster-recovery/Dockerfile.frontend --build-arg VITE_API_URL=/api -t launchboard-frontend:phase-14 .

docker tag launchboard-backend:phase-14 $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-14
docker tag launchboard-frontend:phase-14 $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-frontend:phase-14

docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-backend:phase-14
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/launchboard-frontend:phase-14
```

Why this step exists:

The app must be deployable before recovery can be tested. ECR stores the backend and frontend images that EKS pulls.

## Step 7: Deploy The App

Create app files in:

```text
deployment/phase-14-disaster-recovery/app-k8s
```

Use the app manifests stored in this phase folder. Then prepare the secret:

```bash
cd deployment/phase-14-disaster-recovery/app-k8s
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
kubectl apply -f deployment/phase-14-disaster-recovery/app-k8s/secret.yaml
kubectl apply -k deployment/phase-14-disaster-recovery/app-k8s
kubectl -n devops-launchboard get pods
```

Why this step exists:

Disaster recovery needs real resources to protect: namespace, deployments, services, database, persistent volume, ingress, and HPA.

## Step 8: Install AWS Load Balancer Controller

Run:

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

eksctl create iamserviceaccount \
  --cluster devops-launchboard-phase-14 \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --role-name devops-launchboard-phase-14-alb-controller \
  --attach-policy-arn arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess \
  --approve

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=devops-launchboard-phase-14 \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

Verify:

```bash
kubectl -n devops-launchboard get ingress
```

Why this step exists:

The app should be reachable through a public ALB before you test outage and recovery.

## Step 9: Create DR S3 Bucket

Run:

```bash
aws s3api create-bucket \
  --bucket $DR_BUCKET \
  --region $AWS_REGION \
  --create-bucket-configuration LocationConstraint=$AWS_REGION

aws s3api put-bucket-versioning \
  --bucket $DR_BUCKET \
  --versioning-configuration Status=Enabled
```

Create lifecycle policy:

```bash
vim deployment/phase-14-disaster-recovery/aws/s3-lifecycle-policy.json
```

Paste:

```json
{
  "Rules": [
    {
      "ID": "expire-old-velero-backups",
      "Status": "Enabled",
      "Filter": {
        "Prefix": ""
      },
      "Expiration": {
        "Days": 30
      },
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 14
      }
    }
  ]
}
```

Apply:

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket $DR_BUCKET \
  --lifecycle-configuration file://deployment/phase-14-disaster-recovery/aws/s3-lifecycle-policy.json
```

Why this step exists:

Velero stores backup metadata in S3. Versioning helps recovery from accidental deletion or overwrite. Lifecycle rules prevent old lab backups from staying forever.

## Step 10: Create Velero IAM Policy

Create:

```bash
vim deployment/phase-14-disaster-recovery/aws/velero-iam-policy.json
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
      "Resource": "arn:aws:s3:::YOUR_DR_BUCKET/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::YOUR_DR_BUCKET"
    }
  ]
}
```

Replace:

```text
YOUR_DR_BUCKET
```

Create policy and service account:

```bash
aws iam create-policy \
  --policy-name devops-launchboard-phase-14-velero \
  --policy-document file://deployment/phase-14-disaster-recovery/aws/velero-iam-policy.json

eksctl create iamserviceaccount \
  --cluster devops-launchboard-phase-14 \
  --namespace velero \
  --name velero \
  --role-name devops-launchboard-phase-14-velero \
  --attach-policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/devops-launchboard-phase-14-velero \
  --approve
```

Why this step exists:

Velero needs permission to write to S3 and create EBS snapshots. The service account gives Velero only the AWS permissions it needs for backup and restore.

## Step 11: Install Velero

Run:

```bash
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.13.0 \
  --bucket $DR_BUCKET \
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

Velero is the Kubernetes backup and restore engine. It protects Kubernetes objects and persistent volumes.

Reference:

- Velero docs: https://velero.io/docs/
- Velero AWS plugin: https://github.com/vmware-tanzu/velero-plugin-for-aws

## Step 12: Create Velero Backups

Create:

```bash
vim deployment/phase-14-disaster-recovery/velero/daily-schedule.yaml
vim deployment/phase-14-disaster-recovery/velero/manual-backup.yaml
vim deployment/phase-14-disaster-recovery/velero/restore-from-manual-backup.yaml
```

Paste into `daily-schedule.yaml`:

```yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: launchboard-daily-dr
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

Paste into `manual-backup.yaml`:

```yaml
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: launchboard-manual-dr
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

Paste into `restore-from-manual-backup.yaml`:

```yaml
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: launchboard-manual-restore
  namespace: velero
spec:
  backupName: launchboard-manual-dr
  includedNamespaces:
    - devops-launchboard
  existingResourcePolicy: update
```

Apply schedule and manual backup:

```bash
kubectl apply -f deployment/phase-14-disaster-recovery/velero/daily-schedule.yaml
kubectl apply -f deployment/phase-14-disaster-recovery/velero/manual-backup.yaml
velero backup get
velero backup describe launchboard-manual-dr --details
```

Why these files exist:

The daily schedule creates automatic recovery points. The manual backup gives students a known checkpoint before a restore drill.

## Step 13: Create PostgreSQL Dump Backup

Create:

```bash
vim deployment/phase-14-disaster-recovery/backups/postgres-backup-pvc.yaml
vim deployment/phase-14-disaster-recovery/backups/postgres-dump-cronjob.yaml
vim deployment/phase-14-disaster-recovery/backups/postgres-restore-job.example.yaml
vim deployment/phase-14-disaster-recovery/backups/kustomization.yaml
```

Paste into `postgres-backup-pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: launchboard-postgres-backups
  namespace: devops-launchboard
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 5Gi
```

Paste into `postgres-dump-cronjob.yaml`:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: launchboard-postgres-dump
  namespace: devops-launchboard
spec:
  schedule: "30 3 * * *"
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: pg-dump
              image: postgres:16-alpine
              imagePullPolicy: IfNotPresent
              env:
                - name: PGPASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: launchboard-secret
                      key: POSTGRES_PASSWORD
              command:
                - /bin/sh
                - -c
                - |
                  mkdir -p /backups
                  pg_dump -h launchboard-db -U launchboard_user -d launchboard > /backups/launchboard-$(date +%Y%m%d%H%M%S).sql
                  find /backups -type f -name "launchboard-*.sql" -mtime +7 -delete
              volumeMounts:
                - name: backups
                  mountPath: /backups
          volumes:
            - name: backups
              persistentVolumeClaim:
                claimName: launchboard-postgres-backups
```

Paste into `kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - postgres-backup-pvc.yaml
  - postgres-dump-cronjob.yaml
```

Apply:

```bash
kubectl apply -k deployment/phase-14-disaster-recovery/backups
kubectl -n devops-launchboard get pvc,cronjob
```

Create a one-time dump immediately:

```bash
kubectl -n devops-launchboard create job --from=cronjob/launchboard-postgres-dump launchboard-postgres-dump-manual
kubectl -n devops-launchboard get jobs
```

Why this step exists:

Velero protects Kubernetes resources and volumes. PostgreSQL dumps protect database contents in a database-native format. Real recovery plans often use both.

## Step 14: Restore Drill

Restore Kubernetes resources:

```bash
kubectl apply -f deployment/phase-14-disaster-recovery/velero/restore-from-manual-backup.yaml
velero restore get
velero restore describe launchboard-manual-restore --details
```

Restore PostgreSQL dump in a lab:

```bash
cp deployment/phase-14-disaster-recovery/backups/postgres-restore-job.example.yaml deployment/phase-14-disaster-recovery/backups/postgres-restore-job.yaml
vim deployment/phase-14-disaster-recovery/backups/postgres-restore-job.yaml
kubectl apply -f deployment/phase-14-disaster-recovery/backups/postgres-restore-job.yaml
kubectl -n devops-launchboard logs job/launchboard-postgres-restore
```

Replace this value before applying:

```text
RESTORE_FILE.sql
```

Why this step exists:

The restore drill proves that the backup files are usable. It also teaches students where recovery can fail: IAM, S3, snapshots, PVCs, secrets, and database permissions.

## Step 15: Create Runbooks

Create:

```bash
vim deployment/phase-14-disaster-recovery/runbooks/incident-response.md
vim deployment/phase-14-disaster-recovery/runbooks/restore-checklist.md
vim deployment/phase-14-disaster-recovery/runbooks/cluster-rebuild.md
```

Why these files exist:

Recovery is not only technical. During an incident, people need roles, steps, verification commands, and communication habits. Runbooks reduce panic and guessing.

## Verification Commands

Check app:

```bash
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard get pvc
kubectl -n devops-launchboard get ingress
```

Check Velero:

```bash
velero backup get
velero schedule get
velero restore get
```

Check database backup:

```bash
kubectl -n devops-launchboard get cronjob launchboard-postgres-dump
kubectl -n devops-launchboard get jobs
```

Check logs:

```bash
kubectl -n devops-launchboard logs deploy/launchboard-backend --tail=100
kubectl -n velero logs deploy/velero --tail=100
```

## Troubleshooting

Problem: Velero backup fails.

Check:

```bash
kubectl -n velero logs deploy/velero
velero backup describe launchboard-manual-dr --details
aws s3 ls s3://$DR_BUCKET
```

Problem: PostgreSQL dump job fails.

Check:

```bash
kubectl -n devops-launchboard logs job/launchboard-postgres-dump-manual
kubectl -n devops-launchboard get secret launchboard-secret
kubectl -n devops-launchboard get svc launchboard-db
```

Problem: restored app does not become ready.

Check:

```bash
kubectl -n devops-launchboard get events --sort-by=.lastTimestamp
kubectl -n devops-launchboard describe pod POD_NAME
kubectl -n devops-launchboard get pvc
```

## Cleanup

Delete backup resources:

```bash
kubectl delete -k deployment/phase-14-disaster-recovery/backups
kubectl delete -f deployment/phase-14-disaster-recovery/velero/daily-schedule.yaml
velero backup delete launchboard-manual-dr --confirm
kubectl delete namespace velero
```

Delete app:

```bash
kubectl delete -f deployment/phase-14-disaster-recovery/app-k8s/secret.yaml
kubectl delete -k deployment/phase-14-disaster-recovery/app-k8s
```

Delete cluster:

```bash
eksctl delete cluster -f deployment/phase-14-disaster-recovery/cluster/eksctl-cluster.yaml
```

Delete ECR and S3:

```bash
aws ecr delete-repository --repository-name launchboard-backend --force --region $AWS_REGION
aws ecr delete-repository --repository-name launchboard-frontend --force --region $AWS_REGION
aws s3 rm s3://$DR_BUCKET --recursive
aws s3api delete-bucket --bucket $DR_BUCKET --region $AWS_REGION
```

## Production Checklist

```text
[ ] EKS cluster created
[ ] App deployed
[ ] ALB working
[ ] DR bucket created
[ ] S3 lifecycle policy applied
[ ] Velero IAM policy created
[ ] Velero installed
[ ] Manual backup completed
[ ] Scheduled backup created
[ ] Restore object tested
[ ] PostgreSQL dump CronJob created
[ ] Manual database dump tested
[ ] Restore job reviewed
[ ] Incident response runbook created
[ ] Restore checklist created
[ ] Cluster rebuild runbook created
[ ] Cleanup completed
```

## Reference Documentation

| Topic | Official Link |
| --- | --- |
| EKS | https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html |
| ECR | https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html |
| Velero | https://velero.io/docs/ |
| Velero AWS Plugin | https://github.com/vmware-tanzu/velero-plugin-for-aws |
| S3 Lifecycle | https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html |
| PostgreSQL pg_dump | https://www.postgresql.org/docs/current/app-pgdump.html |
| Kubernetes CronJob | https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/ |

## Next Step

Move to Phase 15 for final performance and load validation.
