# Phase 7 (Part 3): GitOps With ArgoCD On EKS

## Fresh Start Assumption

This phase starts from a clean AWS environment and a clean Ubuntu workstation.

You do not need to complete the other Phase 7 labs first, but you should understand what they teach: `phase-7-cicd-EKS` and `phase-7-cicd-jenkins` both end with a pipeline that runs `kubectl apply`. This lab replaces that final step with something fundamentally different.

This guide assumes:

- You have an AWS account with permissions to create EKS, EC2, IAM, ECR, ALB, EBS, and VPC resources.
- No tools are installed yet.
- You will create files with `vim` and type commands manually.
- Your fork of the repository is **public** (ArgoCD reads it without credentials; a private repo needs one extra step, covered in Step 8).

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What Is GitOps, And Why Does It Beat "Pipeline Runs kubectl"?

In the Jenkins lab, deployment works like this: a pipeline authenticates to the cluster and **pushes** changes into it. That works, but it has structural weaknesses that show up at scale:

- The CI system holds cluster credentials — a compromised pipeline is a compromised cluster.
- Nothing detects drift. If someone runs `kubectl edit` at 2 AM, the cluster silently diverges from Git until the next deploy overwrites it (or doesn't).
- "What is running right now?" requires asking the cluster. Git only shows what *should have been* deployed at some point.
- Rollback means re-running a pipeline with old inputs and hoping the pipeline itself still works.

GitOps inverts the flow. An agent (ArgoCD) runs **inside** the cluster and continuously **pulls**:

```text
        Push model (Jenkins lab)                 Pull model (this lab)

  Git ──> CI pipeline ──kubectl──> Cluster    Git <──watches── ArgoCD (in cluster)
           (holds cluster creds)                                  │ compares Git vs live
                                                                  └─ applies the diff

  Deploy   = pipeline run                     Deploy   = git merge
  Rollback = re-run old pipeline              Rollback = git revert
  Drift    = invisible                        Drift    = detected and auto-reverted
  Audit    = pipeline logs                    Audit    = git log
```

Four principles define GitOps: the desired state is **declarative** (manifests), stored in **Git** (versioned, reviewed), **pulled automatically** by an agent, and **continuously reconciled** (drift gets corrected, not just detected). By the end of this lab you will have seen all four happen in front of you.

CI does not disappear in this model — it still tests, builds, scans, and pushes images (the other Phase 7 labs). It just stops at "push the image and update the manifest in Git." Delivery to the cluster belongs to ArgoCD.

## What You Will Deploy

```text
                    You (git push to GitHub)
                              │
                              ▼
              GitHub: deployment branch
              deployment/phase-07-cicd-self-hosted/phase-7-gitops-argocd/k8s/
                              │
                              │  polls every ~3 minutes (or webhook)
                              ▼
        ┌─────────────────── EKS cluster ───────────────────┐
        │  argocd namespace:                                │
        │    ArgoCD (API server, repo server, controller)   │
        │        │ renders kustomization, diffs, applies    │
        │        ▼                                          │
        │  devops-launchboard namespace:                    │
        │    full app stack: PostgreSQL + PVC, migration    │
        │    Job, backend x2 + HPA, frontend x2,            │
        │    ALB Ingress, PDBs, NetworkPolicies             │
        └───────────────────────────────────────────────────┘
                              │
                              ▼
                     Browser ── ALB (HTTP :80)
```

The Kubernetes manifests are the production-hardened set from the capstone (non-root, probes, PDBs, default-deny NetworkPolicies). What is new is *how they reach the cluster*: after initial setup you will not run `kubectl apply` on the app again.

## Cost Warning

| Resource | Approximate Cost |
| --- | --- |
| EKS control plane | ~$0.10/hour |
| 2 × t3.medium workers | ~$0.08/hour |
| NAT Gateway | ~$0.045/hour |
| ALB | ~$0.02/hour |
| EBS, ECR | ~$0.01/hour |

~$0.26/hour. Delete the cluster after each session; create an AWS Budget first.

## Files Included In This Phase

```text
deployment/phase-07-cicd-self-hosted/phase-7-gitops-argocd/
+-- cluster/eksctl-cluster.yaml        (EKS + OIDC + EBS CSI + NetworkPolicy enforcement)
+-- ecr/lifecycle-policy.json          (image retention)
+-- Dockerfile.backend                 (FastAPI image)
+-- Dockerfile.frontend                (React/Nginx image)
+-- nginx-frontend.conf                (frontend Nginx config)
+-- k8s/                               (the app manifests ArgoCD watches - 17 files)
|   +-- namespace.yaml  storageclass.yaml  configmap.yaml  secret.example.yaml
|   +-- pvc.yaml  launchboard-postgres-deployment.yaml  launchboard-postgres-service.yaml
|   +-- launchboard-migration-job.yaml
|   +-- launchboard-backend-deployment.yaml  launchboard-backend-service.yaml
|   +-- launchboard-frontend-deployment.yaml  launchboard-frontend-service.yaml
|   +-- ingress.yaml  hpa.yaml  pdb.yaml  networkpolicies.yaml  kustomization.yaml
+-- argocd/application.yaml            (the ArgoCD Application - GitOps entry point)
+-- README.md
```

The `k8s/` manifests are byte-identical in structure to the Phase 16 capstone set with `phase-7-gitops` naming; each file's full line-by-line explanation lives in the Phase 11 and Phase 16 guides. This guide's focus is the GitOps machinery around them.

## Step 1: Create AWS Workstation

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-7-gitops-workstation` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` |
| Storage | 30 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | SSH port 22, your IP only |

```bash
chmod 400 devops-launchboard-key.pem
ssh -i devops-launchboard-key.pem ubuntu@YOUR_WORKSTATION_PUBLIC_IP
```

## Step 2: Install Tools

Base tools and Docker:

```bash
cd ~
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl wget vim unzip jq ca-certificates gnupg lsb-release

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo ${UBUNTU_CODENAME:-$VERSION_CODENAME}) stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
sudo systemctl enable docker
sudo usermod -aG docker ubuntu
exit
```

SSH back in, then AWS CLI, kubectl, eksctl, Helm, and the ArgoCD CLI:

```bash
ssh -i devops-launchboard-key.pem ubuntu@YOUR_WORKSTATION_PUBLIC_IP
cd ~

# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install && rm -rf aws awscliv2.zip
aws configure
aws sts get-caller-identity

# kubectl
curl -LO "https://dl.k8s.io/release/stable.txt"
KUBECTL_VERSION=$(cat stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/kubectl && rm stable.txt

# eksctl
curl --silent --location "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" -o eksctl.tar.gz
tar -xzf eksctl.tar.gz && sudo mv eksctl /usr/local/bin/eksctl && rm eksctl.tar.gz

# Helm (official installer script)
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh && ./get_helm.sh && rm get_helm.sh

# ArgoCD CLI
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd && sudo mv argocd /usr/local/bin/argocd
```

Verify:

```bash
docker --version && aws --version && kubectl version --client && eksctl version && helm version && argocd version --client
```

Reference:

- ArgoCD CLI installation: https://argo-cd.readthedocs.io/en/stable/cli_installation/

## Step 3: Clone Repository

```bash
cd ~
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-7-gitops" -f ~/.ssh/devops_launchboard_github_key
cat ~/.ssh/devops_launchboard_github_key.pub
```

Add the key to GitHub as a deploy key — **with "Allow write access" checked this time**. In every other phase the workstation only reads the repository; in GitOps the workstation is where you edit manifests and `git push`, because pushing *is* deploying.

```bash
vim ~/.ssh/config
```

```text
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/devops_launchboard_github_key
  IdentitiesOnly yes
```

```bash
chmod 600 ~/.ssh/config ~/.ssh/devops_launchboard_github_key
ssh -T git@github.com
sudo mkdir -p /opt/devops-launchboard
sudo chown -R ubuntu:ubuntu /opt/devops-launchboard
cd /opt/devops-launchboard
git clone git@github.com:ashraful2430/N-tier-application.git app-source
cd app-source
git checkout deployment
git config user.name "Your Name"
git config user.email "you@example.com"
```

`git checkout deployment` matters: the manifests ArgoCD watches live on the `deployment` branch, and the `Application` you create later points its `targetRevision` there.

## Step 4: Create The EKS Cluster

The cluster config is the proven capstone setup (OIDC, private workers, single NAT, EBS CSI, NetworkPolicy enforcement):

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-gitops-argocd/cluster/eksctl-cluster.yaml
```

Paste (replace `YOUR_AWS_REGION` in three places):

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: devops-launchboard-phase-7-gitops
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
      Environment: phase-7-gitops
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
  - name: vpc-cni
    configurationValues: |-
      enableNetworkPolicy: "true"
```

Create it (20-40 minutes):

```bash
export AWS_REGION=YOUR_AWS_REGION
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export CLUSTER_NAME=devops-launchboard-phase-7-gitops

cd /opt/devops-launchboard/app-source
eksctl create cluster -f deployment/phase-07-cicd-self-hosted/phase-7-gitops-argocd/cluster/eksctl-cluster.yaml
kubectl get nodes
```

## Step 5: ECR And Images

```bash
aws ecr create-repository --repository-name launchboard-backend --region "$AWS_REGION" --image-scanning-configuration scanOnPush=true
aws ecr create-repository --repository-name launchboard-frontend --region "$AWS_REGION" --image-scanning-configuration scanOnPush=true

aws ecr put-lifecycle-policy --repository-name launchboard-backend \
  --lifecycle-policy-text file://deployment/phase-07-cicd-self-hosted/phase-7-gitops-argocd/ecr/lifecycle-policy.json --region "$AWS_REGION"
aws ecr put-lifecycle-policy --repository-name launchboard-frontend \
  --lifecycle-policy-text file://deployment/phase-07-cicd-self-hosted/phase-7-gitops-argocd/ecr/lifecycle-policy.json --region "$AWS_REGION"

ECR_REGISTRY=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin $ECR_REGISTRY

docker build -f deployment/phase-07-cicd-self-hosted/phase-7-gitops-argocd/Dockerfile.backend \
  -t $ECR_REGISTRY/launchboard-backend:phase-7-gitops .
docker build -f deployment/phase-07-cicd-self-hosted/phase-7-gitops-argocd/Dockerfile.frontend \
  --build-arg VITE_API_URL= \
  -t $ECR_REGISTRY/launchboard-frontend:phase-7-gitops .

docker push $ECR_REGISTRY/launchboard-backend:phase-7-gitops
docker push $ECR_REGISTRY/launchboard-frontend:phase-7-gitops
```

(The Dockerfiles and lifecycle policy are the standard hardened set — full line-by-line in the Phase 11 guide.)

## Step 6: Install The AWS Load Balancer Controller

```bash
cd ~
curl -o aws-load-balancer-controller-policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicyPhase7GitOps \
  --policy-document file://aws-load-balancer-controller-policy.json

eksctl create iamserviceaccount \
  --cluster "$CLUSTER_NAME" \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicyPhase7GitOps" \
  --approve \
  --region "$AWS_REGION"

helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

kubectl -n kube-system rollout status deployment/aws-load-balancer-controller
```

## Step 7: Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl -n argocd wait --for=condition=ready pod \
  --selector=app.kubernetes.io/name=argocd-server --timeout=300s
kubectl -n argocd get pods
```

Expected Pods and what each does:

```text
argocd-application-controller-0     the reconciler: compares Git to cluster, applies diffs
argocd-repo-server-...              clones Git, renders Kustomize/Helm into plain manifests
argocd-server-...                   API + web UI
argocd-redis-...                    internal cache
argocd-dex-server-...               SSO (unused in this lab)
argocd-applicationset-controller-.. templating many apps from one spec (unused here)
argocd-notifications-controller-... sync notifications to Slack etc. (unused here)
```

Access the UI via port-forward (add port 8080 to the workstation security group, your IP only):

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443 --address 0.0.0.0 &
```

Get the initial admin password and log in — both browser (`https://YOUR_WORKSTATION_IP:8080`, accept the self-signed-certificate warning) and CLI:

```bash
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "$ARGOCD_PASSWORD"

argocd login localhost:8080 --username admin --password "$ARGOCD_PASSWORD" --insecure
```

Change the password immediately (real habit, and the initial secret is meant to be deleted):

```bash
argocd account update-password --current-password "$ARGOCD_PASSWORD" --new-password 'YOUR_NEW_STRONG_PASSWORD'
kubectl -n argocd delete secret argocd-initial-admin-secret
```

Reference:

- ArgoCD getting started: https://argo-cd.readthedocs.io/en/stable/getting_started/
- ArgoCD architecture: https://argo-cd.readthedocs.io/en/stable/operator-manual/architecture/

## Step 8: Pre-Sync Setup — The Two Things That Do NOT Live In Git

Two objects are created by hand exactly once, and understanding *why* is a core GitOps lesson:

**1. The Secret.** Plaintext credentials never go in Git, so ArgoCD cannot sync what Git must not contain:

```bash
kubectl apply -f deployment/phase-07-cicd-self-hosted/phase-7-gitops-argocd/k8s/namespace.yaml

kubectl create secret generic launchboard-secret \
  --namespace devops-launchboard \
  --from-literal=POSTGRES_PASSWORD='CHANGE_ME_STRONG_PASSWORD' \
  --from-literal=DATABASE_URL='postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@launchboard-db:5432/launchboard'
```

In a full production setup this gap is closed with the tools from Phase 12: External Secrets Operator (the ExternalSecret manifest IS committed to Git, and it pulls the value from AWS Secrets Manager) or Sealed Secrets (the encrypted blob is committed). Either makes secrets GitOps-compatible; for this lab, one manual `kubectl create secret` keeps the focus on the sync loop.

**2. Repository access (only if your repository is private).** ArgoCD reads public repositories anonymously. For a private repo, register credentials first:

```bash
argocd repo add https://github.com/ashraful2430/N-tier-application.git \
  --username YOUR_GITHUB_USERNAME --password YOUR_GITHUB_PAT
```

(A fine-grained PAT with read-only Contents permission is enough.)

Also stamp your account/region into the three manifests that reference ECR, **and push the change** — this is the first taste of the workflow: the manifests in Git must be complete and correct, because Git is what deploys:

```bash
cd /opt/devops-launchboard/app-source
sed -i "s|YOUR_ACCOUNT_ID|${ACCOUNT_ID}|g; s|YOUR_AWS_REGION|${AWS_REGION}|g" \
  deployment/phase-07-cicd-self-hosted/phase-7-gitops-argocd/k8s/launchboard-backend-deployment.yaml \
  deployment/phase-07-cicd-self-hosted/phase-7-gitops-argocd/k8s/launchboard-migration-job.yaml \
  deployment/phase-07-cicd-self-hosted/phase-7-gitops-argocd/k8s/launchboard-frontend-deployment.yaml

git add deployment/phase-07-cicd-self-hosted/phase-7-gitops-argocd/k8s
git commit -m "Stamp ECR registry into phase 7 gitops manifests"
git push origin deployment
```

## Step 9: Create The Application — The GitOps Entry Point

An `Application` is ArgoCD's custom resource that says: *this Git path, at this revision, must equal this namespace in this cluster.* It is the only thing you ever `kubectl apply` for the app.

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-gitops-argocd/argocd/application.yaml
```

Paste (replace the repoURL with your fork if you forked):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: launchboard
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/ashraful2430/N-tier-application.git
    targetRevision: deployment
    path: deployment/phase-07-cicd-self-hosted/phase-7-gitops-argocd/k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: devops-launchboard
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
  ignoreDifferences:
    - group: apps
      kind: Deployment
      name: launchboard-backend
      jsonPointers:
        - /spec/replicas
```

Line explanation:

- `metadata.namespace: argocd` — Applications live where ArgoCD lives, not in the app namespace.
- `source` is the Git half of the contract: `repoURL` + `targetRevision: deployment` (the branch) + `path` (the folder containing `kustomization.yaml` — ArgoCD detects Kustomize automatically and renders it exactly like `kubectl apply -k` would).
- `destination` is the cluster half: `https://kubernetes.default.svc` means "the cluster I am running in" (ArgoCD can also manage remote clusters), and the target namespace.
- `syncPolicy.automated` turns the loop on: without it, ArgoCD only *shows* the diff and waits for a human to press Sync. `prune: true` deletes cluster resources whose manifests were removed from Git — without it, deleting a file from Git orphans the object forever. `selfHeal: true` reverts manual cluster edits — the setting you will test in Step 12.
- `CreateNamespace=false` because the namespace manifest is part of the Kustomization itself.
- `ignoreDifferences` on the backend's `/spec/replicas` solves a real conflict you would otherwise hit within minutes: the **HPA** owns the replica count at runtime (scaling 2→5 under load), while Git says `replicas: 2`. Without this stanza, every HPA scale-up looks like drift, and `selfHeal` would fight the autoscaler in a loop. Rule of thumb: ignore exactly the fields that another controller legitimately owns, nothing more.
- One expected wrinkle: Kubernetes **Jobs are immutable**, so after the migration Job completes, its live object can never be made to match a changed manifest. The Application may show the Job as `OutOfSync` after the first sync cycle — harmless here. The production pattern is the annotation `argocd.argoproj.io/hook: Sync`, which tells ArgoCD to delete-and-recreate the Job on every sync instead of diffing it.

Apply it — the last manual apply of the lab:

```bash
kubectl apply -f deployment/phase-07-cicd-self-hosted/phase-7-gitops-argocd/argocd/application.yaml
```

Watch the first sync:

```bash
argocd app get launchboard
argocd app wait launchboard --timeout 600
kubectl -n devops-launchboard get pods
```

In the UI, open the `launchboard` application: the resource tree shows all 17 objects, their health (heart icon), and sync state. This visual "what is actually running vs what Git says" view is half of ArgoCD's daily value.

## Step 10: Fix CORS — The GitOps Way

The ConfigMap in Git has a placeholder CORS origin. In previous phases you patched the live ConfigMap with `kubectl`. **You cannot do that here** — selfHeal would revert your patch within minutes, and that is the correct behavior: the cluster is not the place to make changes. Git is.

```bash
ALB_DNS=$(kubectl -n devops-launchboard get ingress launchboard-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB: $ALB_DNS"

sed -i "s|http://YOUR_ALB_DNS_NAME|http://${ALB_DNS}|" \
  deployment/phase-07-cicd-self-hosted/phase-7-gitops-argocd/k8s/configmap.yaml

git add deployment/phase-07-cicd-self-hosted/phase-7-gitops-argocd/k8s/configmap.yaml
git commit -m "Set CORS origin to the phase 7 gitops ALB"
git push origin deployment
```

Force an immediate re-check instead of waiting for the ~3-minute poll, then restart the backend so it re-reads the ConfigMap (a rollout restart is an *operational* action, not a configuration change, so kubectl is legitimate for it):

```bash
argocd app sync launchboard
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
kubectl -n devops-launchboard rollout status deployment/launchboard-backend --timeout=180s

curl -s "http://$ALB_DNS/health" | jq
curl -s "http://$ALB_DNS/api/summary" | jq
```

Open `http://$ALB_DNS` in the browser — the app is live, and its configuration history is now a Git history.

## Step 11: Deploy A Change With Nothing But Git

Scale the frontend from 2 to 3 replicas by editing the manifest:

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-gitops-argocd/k8s/launchboard-frontend-deployment.yaml
```

Change `replicas: 2` to `replicas: 3`, then:

```bash
git add -A
git commit -m "Scale frontend to 3 replicas"
git push origin deployment

argocd app sync launchboard
kubectl -n devops-launchboard get pods -l app=launchboard-frontend
```

Three frontend Pods — deployed by a commit. In a team, that commit would arrive via a reviewed pull request, which means **every production change gets a reviewer, a diff, and an author** — the audit and approval process falls out of the workflow for free.

Roll it back the GitOps way:

```bash
git revert --no-edit HEAD
git push origin deployment
argocd app sync launchboard
kubectl -n devops-launchboard get pods -l app=launchboard-frontend
```

Back to 2 Pods. `git revert` creates a *new* commit that undoes the old one — history stays intact, and the rollback itself is audited. Compare this with the Jenkins lab's rollback pipeline: an entire second Jenkinsfile replaced by one Git command.

## Step 12: Watch Self-Heal Defeat Manual Drift

Simulate the 2 AM hotfix that bypasses process:

```bash
kubectl -n devops-launchboard scale deployment launchboard-frontend --replicas=5
kubectl -n devops-launchboard get pods -l app=launchboard-frontend
```

Five Pods... briefly. Watch ArgoCD notice and correct:

```bash
argocd app get launchboard --refresh
kubectl -n devops-launchboard get pods -l app=launchboard-frontend -w
```

Within moments the count returns to 2 — the application controller saw live state diverge from Git and re-applied Git. Press Ctrl+C. Check the event trail in the UI (application → Sync Status / History) — the drift and correction are both recorded.

This is the guarantee that makes auditors and security teams love GitOps: **the cluster cannot quietly diverge from its reviewed state.** (And note the contrast with the backend Deployment, where you deliberately told ArgoCD to ignore `/spec/replicas` because the HPA owns it — policy is per-field, not all-or-nothing.)

## Step 13: Ship A New Image Version

The complete flow, end to end, the way a real release moves — CI builds and pushes the image; Git changes the tag; ArgoCD delivers:

```bash
# "CI" builds and pushes a new version (you are the CI today)
docker build -f deployment/phase-07-cicd-self-hosted/phase-7-gitops-argocd/Dockerfile.frontend \
  --build-arg VITE_API_URL= \
  -t $ECR_REGISTRY/launchboard-frontend:phase-7-gitops-v2 .
docker push $ECR_REGISTRY/launchboard-frontend:phase-7-gitops-v2

# the deployment change is a one-line Git edit
sed -i "s|launchboard-frontend:phase-7-gitops|launchboard-frontend:phase-7-gitops-v2|" \
  deployment/phase-07-cicd-self-hosted/phase-7-gitops-argocd/k8s/launchboard-frontend-deployment.yaml
git add -A
git commit -m "Release frontend phase-7-gitops-v2"
git push origin deployment

argocd app sync launchboard
kubectl -n devops-launchboard rollout status deployment/launchboard-frontend --timeout=180s
kubectl -n devops-launchboard get pods -l app=launchboard-frontend \
  -o jsonpath='{.items[*].spec.containers[0].image}'; echo
```

All Pods now run `:phase-7-gitops-v2`, rolled out with the Deployment's zero-downtime strategy. A bad release? `git revert && argocd app sync` — the old tag comes back the same way it went out.

In production this last manual edit is also automated: **ArgoCD Image Updater** watches the registry and commits the tag bump itself, or the CI pipeline's final step is a commit to the manifest repo instead of a `kubectl apply`. Either way, the invariant holds: *nothing reaches the cluster except through Git.*

Reference:

- ArgoCD Image Updater: https://argocd-image-updater.readthedocs.io/en/stable/

## Cleanup

```bash
pkill -f "port-forward" || true

# Delete the Application with cascade - ArgoCD prunes everything it created
argocd app delete launchboard --cascade --yes
kubectl delete namespace devops-launchboard --ignore-not-found

# ArgoCD itself
kubectl delete namespace argocd

# Wait 2-3 minutes for the ALB to be removed, then:
helm uninstall aws-load-balancer-controller --namespace kube-system
eksctl delete iamserviceaccount --cluster "$CLUSTER_NAME" --namespace kube-system \
  --name aws-load-balancer-controller --region "$AWS_REGION"

eksctl delete cluster --name "$CLUSTER_NAME" --region "$AWS_REGION"

aws ecr delete-repository --repository-name launchboard-backend --force --region "$AWS_REGION"
aws ecr delete-repository --repository-name launchboard-frontend --force --region "$AWS_REGION"
aws iam delete-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicyPhase7GitOps"
```

Check the console for leftovers (Load Balancers, Volumes, NAT Gateways, Elastic IPs), then terminate the workstation.

## Troubleshooting

### Problem 1: Application stuck in `Unknown` / `ComparisonError`

```bash
argocd app get launchboard
kubectl -n argocd logs deployment/argocd-repo-server --tail=30
```

Usual causes: wrong `repoURL` (your fork vs the original), wrong `targetRevision` (manifests are on `deployment`, not `main`), a typo in `path`, or a private repository without registered credentials (Step 8).

### Problem 2: Sync succeeds but backend Pods CrashLoopBackOff

The Secret is missing — it is deliberately not in Git (Step 8). `kubectl -n devops-launchboard get secret launchboard-secret` — if absent, create it and the Pods recover on their next restart.

### Problem 3: Application constantly flips OutOfSync on the backend Deployment

The `ignoreDifferences` stanza for `/spec/replicas` is missing or misspelled, so the HPA's scaling fights selfHeal. Compare your Application against Step 9 exactly, re-apply it, and refresh.

### Problem 4: The migration Job shows OutOfSync forever

Expected — Jobs are immutable (see Step 9's line explanation). Harmless for this lab; the production fix is the `argocd.argoproj.io/hook: Sync` annotation.

### Problem 5: Your Git push deployed nothing for ~3 minutes

Not a bug: ArgoCD polls the repository roughly every 3 minutes. `argocd app sync launchboard` forces an immediate reconcile; production setups add a GitHub webhook to ArgoCD's `/api/webhook` endpoint so pushes trigger instantly.

### Problem 6: `kubectl scale` in Step 12 did NOT get reverted

Check that `selfHeal: true` is actually in the live Application (`kubectl -n argocd get application launchboard -o yaml | grep -A3 automated`) — if you edited the file but never re-applied it, the cluster still runs the old spec. Also confirm you scaled the *frontend* (the backend's replica field is deliberately ignored).

## Production Checklist

```text
[ ] ArgoCD installed; initial admin secret deleted after password change
[ ] Application created - the only kubectl apply for the app
[ ] All 17 resources Healthy and Synced in the UI
[ ] Secret exists in the cluster but NOT in Git
[ ] CORS fixed via Git commit, not kubectl patch
[ ] Change deployed via commit + sync (frontend 2 -> 3)
[ ] Rollback via git revert
[ ] Manual drift reverted by selfHeal (watched it happen)
[ ] HPA vs selfHeal conflict understood (ignoreDifferences)
[ ] New image version shipped by editing the tag in Git
[ ] Cleanup completed
```

## Reference Documentation

| Topic | Link |
| --- | --- |
| ArgoCD documentation | https://argo-cd.readthedocs.io/en/stable/ |
| Application specification | https://argo-cd.readthedocs.io/en/stable/user-guide/application-specification/ |
| Sync policies | https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/ |
| Diffing customization (ignoreDifferences) | https://argo-cd.readthedocs.io/en/stable/user-guide/diffing/ |
| Resource hooks | https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/ |
| ArgoCD Image Updater | https://argocd-image-updater.readthedocs.io/en/stable/ |
| OpenGitOps principles | https://opengitops.dev/ |

## What To Do Next

Move to Phase 8 (EKS fundamentals) if you have not done it, or continue the track order. When you reach the Phase 16 capstone, consider running it GitOps-style: point an ArgoCD Application at the capstone's `app-k8s/` folder instead of using `kubectl apply -k` — everything you learned here transfers directly.
