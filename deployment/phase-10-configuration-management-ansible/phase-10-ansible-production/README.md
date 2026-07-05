# Phase 15 (Part 2): Ansible Production

## Fresh Start Assumption

This phase starts from a clean AWS environment.

You must complete `phase-15-ansible-basics` first — this guide assumes you know inventories, modules, playbooks, variables, templates, handlers, and idempotency.

This guide assumes:

- You have an AWS account with permission to create EC2 instances and security groups.
- You will create files with `vim`.
- You will type commands manually.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What You Will Deploy

A four-server, three-tier deployment — the Phase 2 bare-metal architecture, but fully automated and repeatable:

```text
                     Browser
                        |
                        | HTTP :80
                        v
              +------------------+
              |  Load Balancer   |  Nginx upstream, proxies to both app servers,
              |  (t3.small)      |  retries the other server if one fails
              +------------------+
                   |         |
             :80   |         |   :80        (private IPs)
                   v         v
        +--------------+  +--------------+
        | App Server 1 |  | App Server 2 |   each runs two containers:
        | (t3.medium)  |  | (t3.medium)  |   launchboard-frontend (Nginx :80->8080)
        +--------------+  +--------------+   launchboard-backend  (FastAPI :8000)
                   |         |
             :5432 |         |               (private IPs)
                   v         v
              +------------------+
              |  Database        |  postgres:16-alpine container
              |  (t3.small)      |  with a named Docker volume
              +------------------+
```

What makes this "production" compared to the basics lab:

| Concern | Basics | Production |
| --- | --- | --- |
| Topology | Everything on one host | Separate LB, app, and DB tiers |
| Availability | One app server | Two app servers; LB retries the healthy one |
| Code structure | Flat playbooks | Roles (`common`, `docker`, `postgres`, `app`, `loadbalancer`) |
| Secrets | Plain YAML file | Ansible Vault, encrypted at rest, safe to commit |
| Deployment | All at once | `serial: 1` rolling deploy with a health gate per server |
| Configuration | Hand-edited IPs | Every IP derived from the inventory via `hostvars` |

## Cost Warning

| Resource | Approximate Cost |
| --- | --- |
| Control node t3.small | ~$0.02/hour |
| LB t3.small | ~$0.02/hour |
| 2 × app t3.medium | ~$0.08/hour |
| DB t3.small | ~$0.02/hour |

About **$0.14/hour** total. Terminate all five instances after each session.

## Files Included In This Phase

```text
deployment/phase-15-configuration-management-ansible/phase-15-ansible-production/
+-- ansible.cfg
+-- inventory.ini.example            (copy to inventory.ini)
+-- site.yml                         (full environment: all tiers, in order)
+-- deploy-app.yml                   (rolling redeploy of the app tier only)
+-- group_vars/
|   +-- all/
|       +-- main.yml                 (derived vars - no secrets)
|       +-- vault.yml.example        (copy to vault.yml, then encrypt)
+-- roles/
    +-- common/tasks/main.yml        (baseline packages, timezone)
    +-- docker/
    |   +-- tasks/main.yml           (Docker Engine + Python SDK + log rotation)
    |   +-- handlers/main.yml        (restart docker)
    +-- postgres/tasks/main.yml      (DB container + volume + wait)
    +-- app/tasks/main.yml           (build images, migrate, run containers, health gate)
    +-- loadbalancer/
        +-- tasks/main.yml           (nginx + site config)
        +-- handlers/main.yml        (reload nginx)
        +-- templates/launchboard-lb.conf.j2
+-- README.md
```

## What Is A Role?

A role is Ansible's module system for playbooks: a folder with a fixed layout that Ansible knows how to load.

```text
roles/docker/
+-- tasks/main.yml       (the tasks - loaded automatically)
+-- handlers/main.yml    (handlers - loaded automatically)
+-- templates/           (templates, referenced by bare filename)
+-- defaults/main.yml    (lowest-priority default variables, if any)
```

A playbook then just says `roles: [docker]` instead of containing fifty task lines. Roles are what make Ansible code shareable across projects and teams (Ansible Galaxy is a public registry of them).

## Step 1: Create Five EC2 Instances

All Ubuntu Server 24.04 LTS, key pair `devops-launchboard-key`:

| Name | Type | Storage | Role |
| --- | --- | --- | --- |
| `devops-launchboard-phase-15-control` | t3.small | 20 GB | Control node |
| `devops-launchboard-phase-15-lb` | t3.small | 20 GB | Load balancer |
| `devops-launchboard-phase-15-app-1` | t3.medium | 30 GB | App server |
| `devops-launchboard-phase-15-app-2` | t3.medium | 30 GB | App server |
| `devops-launchboard-phase-15-db` | t3.small | 20 GB | Database |

Create four security groups first (EC2 > Security Groups > Create), all in the default VPC:

**`phase-15-control-sg`** (control node):

| Type | Port | Source |
| --- | ---: | --- |
| SSH | 22 | Your IP |

**`phase-15-lb-sg`** (load balancer):

| Type | Port | Source |
| --- | ---: | --- |
| SSH | 22 | `phase-15-control-sg` |
| HTTP | 80 | `0.0.0.0/0` |

**`phase-15-app-sg`** (app servers):

| Type | Port | Source |
| --- | ---: | --- |
| SSH | 22 | `phase-15-control-sg` |
| HTTP | 80 | `phase-15-lb-sg` |

**`phase-15-db-sg`** (database):

| Type | Port | Source |
| --- | ---: | --- |
| SSH | 22 | `phase-15-control-sg` |
| PostgreSQL | 5432 | `phase-15-app-sg` |

Using security groups as sources (instead of IPs) is the same referencing pattern Terraform declared in Phase 14: "app servers may reach the database" survives any instance replacement. Note the tier isolation: nothing reaches the app servers except the LB, nothing reaches the database except the app servers.

Write down the **public and private IP** of every instance (EC2 > Instances > select > Details). Public IPs are for SSH from the control node; private IPs are how the tiers talk to each other.

SSH into the **control node** and prepare it exactly like the basics lab (install Ansible + collections, copy the key):

```bash
chmod 400 devops-launchboard-key.pem
ssh -i devops-launchboard-key.pem ubuntu@CONTROL_NODE_PUBLIC_IP

sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl vim software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible
ansible-galaxy collection install community.general community.docker
```

From your local machine, copy the key up:

```bash
scp -i devops-launchboard-key.pem devops-launchboard-key.pem ubuntu@CONTROL_NODE_PUBLIC_IP:/home/ubuntu/.ssh/devops-launchboard-key.pem
```

Back on the control node:

```bash
chmod 400 ~/.ssh/devops-launchboard-key.pem
```

## Step 2: Create The Project Skeleton

```bash
cd ~
mkdir -p ansible-prod/group_vars/all
mkdir -p ansible-prod/roles/common/tasks
mkdir -p ansible-prod/roles/docker/tasks ansible-prod/roles/docker/handlers
mkdir -p ansible-prod/roles/postgres/tasks
mkdir -p ansible-prod/roles/app/tasks
mkdir -p ansible-prod/roles/loadbalancer/tasks ansible-prod/roles/loadbalancer/handlers ansible-prod/roles/loadbalancer/templates
cd ansible-prod
```

### ansible.cfg

```bash
vim ansible.cfg
```

Paste:

```ini
[defaults]
inventory = inventory.ini
remote_user = ubuntu
private_key_file = ~/.ssh/devops-launchboard-key.pem
host_key_checking = False
interpreter_python = auto_silent
roles_path = roles

[privilege_escalation]
become = True
become_method = sudo
```

Same as the basics lab plus `roles_path = roles`, which tells Ansible to resolve role names against this project's `roles/` folder.

### inventory.ini

```bash
vim inventory.ini
```

Paste, filling in all eight IPs from Step 1:

```ini
[loadbalancer]
launchboard-lb ansible_host=LB_PUBLIC_IP private_ip=LB_PRIVATE_IP

[app_servers]
launchboard-app-1 ansible_host=APP1_PUBLIC_IP private_ip=APP1_PRIVATE_IP
launchboard-app-2 ansible_host=APP2_PUBLIC_IP private_ip=APP2_PRIVATE_IP

[database]
launchboard-db ansible_host=DB_PUBLIC_IP private_ip=DB_PRIVATE_IP
```

Line explanation:

- Three groups, one per tier. Plays and roles target tiers by group name.
- `private_ip=...` is a **host variable** you define yourself (any `key=value` after the host name becomes one). Other hosts read it through `hostvars` — this is how the LB config learns the app servers' addresses and the app servers learn the database's address, with zero IPs hardcoded in any role.

Verify connectivity to all four:

```bash
ansible all -m ping
```

Expected: four `pong`s.

## Step 3: Group Variables And The Vault

### group_vars/all/main.yml

Variables in `group_vars/all/` apply to every host. This file holds everything **derived** — and no secrets:

```bash
vim group_vars/all/main.yml
```

Paste:

```yaml
---
# Secret indirection: the real value lives encrypted in vault.yml
db_password: "{{ vault_db_password }}"

# Derived connection values - no IPs are hardcoded anywhere but the inventory
db_host: "{{ hostvars[groups['database'][0]].private_ip }}"
database_url: "postgresql+asyncpg://launchboard_user:{{ db_password }}@{{ db_host }}:5432/launchboard"
lb_public_ip: "{{ hostvars[groups['loadbalancer'][0]].ansible_host }}"
cors_origins: "http://{{ lb_public_ip }}"

# App source
app_repo: https://github.com/ashraful2430/N-tier-application.git
app_dir: /opt/launchboard
app_version: main
image_tag: phase-15
```

Line explanation:

- `db_password: "{{ vault_db_password }}"` is the standard **vault indirection pattern**: playbooks and roles reference the readable name `db_password`; the actual value lives in an encrypted file under the `vault_` prefixed name. `grep -r db_password` still shows you where the secret is *used* even though its value is unreadable.
- `groups['database'][0]` is "the first host in the database group"; `hostvars[...]` accesses that host's variables from anywhere. So `db_host` is the database's private IP, `database_url` assembles the full connection string, and `cors_origins` becomes the load balancer's public URL — the single value users will hit in the browser, which is what the backend must allow for CORS. In previous phases these were `sed` placeholders; here they are all derived from the inventory.

### group_vars/all/vault.yml

```bash
vim group_vars/all/vault.yml
```

Paste with a real password:

```yaml
---
vault_db_password: CHANGE_ME_STRONG_PASSWORD
```

Now encrypt it:

```bash
ansible-vault encrypt group_vars/all/vault.yml
```

You are prompted to create a **vault password** (this protects the file — do not confuse it with the DB password inside). Look at the result:

```bash
cat group_vars/all/vault.yml
```

```text
$ANSIBLE_VAULT;1.1;AES256
66386439653236336462626566653063336164663966303231363934653561363964363833313662...
```

The file is now AES256-encrypted and **safe to commit to Git** — this is the point of Vault. Useful commands:

```bash
ansible-vault view group_vars/all/vault.yml     # decrypt to screen
ansible-vault edit group_vars/all/vault.yml     # decrypt, open editor, re-encrypt
ansible-vault rekey group_vars/all/vault.yml    # change the vault password
```

From now on, every playbook run needs `--ask-vault-pass`. (Teams store the vault password in a file referenced by `vault_password_file` in `ansible.cfg`, or in a secrets manager — for this lab, typing it is fine.)

Reference:

- Ansible Vault: https://docs.ansible.com/ansible/latest/vault_guide/index.html

## Step 4: The common And docker Roles

### roles/common/tasks/main.yml

```bash
vim roles/common/tasks/main.yml
```

Paste:

```yaml
---
- name: Update apt cache and upgrade packages
  ansible.builtin.apt:
    update_cache: true
    upgrade: safe
    cache_valid_time: 3600

- name: Install base packages
  ansible.builtin.apt:
    name:
      - git
      - curl
      - vim
      - unzip
      - ca-certificates
    state: present

- name: Set the timezone to UTC
  community.general.timezone:
    name: Etc/UTC
```

The same baseline as the basics lab's playbook 01 — but now it is a role, applied to **all four servers** by one line in `site.yml`. Note a role's task file has no `hosts:` — roles are host-agnostic; the playbook decides where they run.

### roles/docker/tasks/main.yml

```bash
vim roles/docker/tasks/main.yml
```

Paste:

```yaml
---
- name: Create the apt keyrings directory
  ansible.builtin.file:
    path: /etc/apt/keyrings
    state: directory
    mode: "0755"

- name: Download Docker's GPG key
  ansible.builtin.get_url:
    url: https://download.docker.com/linux/ubuntu/gpg
    dest: /etc/apt/keyrings/docker.asc
    mode: "0644"

- name: Add the Docker apt repository
  ansible.builtin.apt_repository:
    repo: "deb [arch={{ ansible_architecture | replace('x86_64', 'amd64') }} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu {{ ansible_distribution_release }} stable"
    filename: docker
    state: present

- name: Install Docker packages
  ansible.builtin.apt:
    name:
      - docker-ce
      - docker-ce-cli
      - containerd.io
      - docker-buildx-plugin
    update_cache: true
    state: present

- name: Install the Docker SDK for Python (required by community.docker modules)
  ansible.builtin.apt:
    name: python3-docker
    state: present

- name: Configure Docker log rotation
  ansible.builtin.copy:
    content: |
      {
        "log-driver": "json-file",
        "log-opts": {
          "max-size": "10m",
          "max-file": "3"
        }
      }
    dest: /etc/docker/daemon.json
    mode: "0644"
  notify: Restart docker

- name: Enable and start the Docker service
  ansible.builtin.service:
    name: docker
    enabled: true
    state: started

- name: Add ubuntu to the docker group
  ansible.builtin.user:
    name: ubuntu
    groups: docker
    append: true
```

One addition versus the basics lab: `python3-docker`, the Docker SDK for Python. The `community.docker` modules (`docker_image`, `docker_container`, `docker_network`, `docker_volume`) run **on the managed node** and talk to the Docker daemon through this library — without it they fail with "Failed to import docker".

### roles/docker/handlers/main.yml

```bash
vim roles/docker/handlers/main.yml
```

Paste:

```yaml
---
- name: Restart docker
  ansible.builtin.service:
    name: docker
    state: restarted
```

Handlers live in their own file inside a role; `notify: Restart docker` in the tasks finds it automatically.

## Step 5: The postgres Role

```bash
vim roles/postgres/tasks/main.yml
```

Paste:

```yaml
---
- name: Create the PostgreSQL data volume
  community.docker.docker_volume:
    name: launchboard-postgres-data

- name: Run the PostgreSQL container
  community.docker.docker_container:
    name: launchboard-db
    image: postgres:16-alpine
    restart_policy: unless-stopped
    ports:
      - "5432:5432"
    env:
      POSTGRES_DB: launchboard
      POSTGRES_USER: launchboard_user
      POSTGRES_PASSWORD: "{{ db_password }}"
    volumes:
      - launchboard-postgres-data:/var/lib/postgresql/data

- name: Wait for PostgreSQL to accept connections
  ansible.builtin.wait_for:
    host: 127.0.0.1
    port: 5432
    timeout: 60
```

Line explanation:

- `docker_volume` + the `volumes:` mount give the database persistent storage that survives container recreation — the same reason every Kubernetes phase used a PVC.
- `ports: "5432:5432"` publishes PostgreSQL on the host. The **security group** (5432 only from `phase-15-app-sg`) is what keeps it private — network policy enforced at the AWS layer, not the application layer.
- `{{ db_password }}` resolves through the vault indirection: `db_password` → `vault_db_password` → decrypted at runtime with your vault password.
- `wait_for` blocks until the port actually accepts connections, so the play that runs *after* this one (the app tier, which immediately runs migrations) never races a starting database.

## Step 6: The app Role

```bash
vim roles/app/tasks/main.yml
```

Paste:

```yaml
---
- name: Clone the application repository
  ansible.builtin.git:
    repo: "{{ app_repo }}"
    dest: "{{ app_dir }}"
    version: "{{ app_version }}"
    force: true

- name: Build the backend image
  community.docker.docker_image:
    name: launchboard-backend
    tag: "{{ image_tag }}"
    source: build
    force_source: true
    build:
      path: "{{ app_dir }}"
      dockerfile: "{{ app_dir }}/deployment/phase-04-docker-compose/Dockerfile.backend"

- name: Build the frontend image
  community.docker.docker_image:
    name: launchboard-frontend
    tag: "{{ image_tag }}"
    source: build
    force_source: true
    build:
      path: "{{ app_dir }}"
      dockerfile: "{{ app_dir }}/deployment/phase-04-docker-compose/Dockerfile.frontend"
      args:
        VITE_API_URL: ""

- name: Create the app Docker network
  community.docker.docker_network:
    name: launchboard

- name: Run database migrations (first app server in the batch only)
  community.docker.docker_container:
    name: launchboard-migrate
    image: "launchboard-backend:{{ image_tag }}"
    command: ["alembic", "upgrade", "head"]
    networks:
      - name: launchboard
    env:
      DATABASE_URL: "{{ database_url }}"
    detach: false
    cleanup: true
  run_once: true

- name: Start the backend container
  community.docker.docker_container:
    name: launchboard-backend
    image: "launchboard-backend:{{ image_tag }}"
    restart_policy: unless-stopped
    recreate: true
    networks:
      - name: launchboard
    env:
      DATABASE_URL: "{{ database_url }}"
      APP_NAME: "DevOps LaunchBoard API"
      APP_ENV: "production"
      CORS_ORIGINS: "{{ cors_origins }}"
      SEED_DEMO_DATA: "true"

- name: Start the frontend container
  community.docker.docker_container:
    name: launchboard-frontend
    image: "launchboard-frontend:{{ image_tag }}"
    restart_policy: unless-stopped
    recreate: true
    networks:
      - name: launchboard
    ports:
      - "80:8080"

- name: Wait for this server to answer health checks
  ansible.builtin.uri:
    url: "http://127.0.0.1/health"
    status_code: 200
  register: health_result
  retries: 12
  delay: 10
  until: health_result.status == 200
```

Line explanation:

- `docker_image` with `source: build` builds from the cloned repo using the Phase 4 Dockerfiles (whose frontend Nginx config proxies `/api`, `/health`, `/ready` to a container named `launchboard-backend` — exactly the name used below). `force_source: true` rebuilds on every run so a redeploy always picks up the latest `app_version` code. Building on each app server keeps the lab registry-free; the registry-based build-once flow is what Phase 14 production and Phase 7 CI/CD teach.
- The migration task runs `alembic upgrade head` as a one-shot container: `detach: false` waits for it to finish (a failure fails the play — you never start an app against a half-migrated schema), `cleanup: true` removes the container afterwards.
- `run_once: true` executes the task on only one host even though the play targets the whole group — the standard pattern for "do this once per deployment, not once per server."
- `recreate: true` on the backend/frontend containers forces replacement with the newly built image. Without it, `docker_container` would see a running container with the right name and report `ok`.
- There is **no database container here** — `DATABASE_URL` points at the database server's private IP via the derived variable.
- The final `uri` health gate is what makes the rolling deploy safe (next step).

## Step 7: The loadbalancer Role

```bash
vim roles/loadbalancer/templates/launchboard-lb.conf.j2
```

Paste:

```text
upstream launchboard_app {
{% for host in groups['app_servers'] %}
    server {{ hostvars[host].private_ip }}:80 max_fails=3 fail_timeout=15s;
{% endfor %}
}

server {
    listen 80;
    server_name _;

    client_max_body_size 10M;

    location / {
        proxy_pass http://launchboard_app;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_next_upstream error timeout http_502 http_503 http_504;
    }
}
```

Line explanation:

- The `{% for %}` loop renders one `server` line **per host in the app_servers group**, reading each host's `private_ip` from the inventory. Add a third app server to the inventory and re-run — the LB config updates itself. This template-over-inventory pattern is the heart of production Ansible.
- `max_fails=3 fail_timeout=15s` is Nginx's passive health checking: three failed connections mark a server down for 15 seconds.
- `proxy_next_upstream ...` retries the request on the other app server when one returns a connection error or 5xx — this is what makes the rolling deploy invisible to users.

```bash
vim roles/loadbalancer/tasks/main.yml
```

Paste:

```yaml
---
- name: Install Nginx
  ansible.builtin.apt:
    name: nginx
    update_cache: true
    state: present

- name: Remove the default site
  ansible.builtin.file:
    path: /etc/nginx/sites-enabled/default
    state: absent
  notify: Reload nginx

- name: Write the load balancer configuration
  ansible.builtin.template:
    src: launchboard-lb.conf.j2
    dest: /etc/nginx/sites-available/launchboard
    mode: "0644"
  notify: Reload nginx

- name: Enable the load balancer site
  ansible.builtin.file:
    src: /etc/nginx/sites-available/launchboard
    dest: /etc/nginx/sites-enabled/launchboard
    state: link
  notify: Reload nginx

- name: Enable and start Nginx
  ansible.builtin.service:
    name: nginx
    enabled: true
    state: started
```

- `src: launchboard-lb.conf.j2` is a bare filename — roles resolve templates from their own `templates/` folder.
- Config changes notify `Reload nginx` (graceful — existing connections finish), not restart.

```bash
vim roles/loadbalancer/handlers/main.yml
```

Paste:

```yaml
---
- name: Reload nginx
  ansible.builtin.service:
    name: nginx
    state: reloaded
```

## Step 8: The Site Playbook

```bash
vim site.yml
```

Paste:

```yaml
---
- name: Baseline every server
  hosts: all
  roles:
    - common

- name: Install Docker where containers run
  hosts: app_servers:database
  roles:
    - docker

- name: Set up the database tier
  hosts: database
  roles:
    - postgres

- name: Deploy the app tier (one server at a time)
  hosts: app_servers
  serial: 1
  roles:
    - app

- name: Set up the load balancer tier
  hosts: loadbalancer
  roles:
    - loadbalancer
```

Line explanation:

- `site.yml` is the conventional name for "the playbook that builds the whole environment." Five plays run in order; each maps a tier (group) to its roles.
- `hosts: app_servers:database` targets the **union** of two groups — Docker goes where containers run; the LB gets plain Nginx instead.
- `serial: 1` is the production star: the app play runs **to completion on one server before starting the next**. Combined with the health gate at the end of the `app` role, a broken deployment stops after damaging only one server, while the LB keeps serving from the other. Without `serial`, Ansible runs each task across all hosts in parallel — fine for installs, wrong for deployments.
- Tier ordering also matters: the database play (with its `wait_for`) completes before the app play runs migrations against it.

Also write the redeploy playbook — same app play, standalone, for day-to-day releases:

```bash
vim deploy-app.yml
```

Paste:

```yaml
---
- name: Rolling redeploy of the app tier
  hosts: app_servers
  serial: 1
  roles:
    - app
```

## Step 9: Run It

```bash
ansible-playbook site.yml --syntax-check
ansible-playbook site.yml --ask-vault-pass
```

Enter the vault password when prompted. The first run takes 10-15 minutes (apt upgrades on four servers plus two image builds). Watch the play structure in the output: baseline on all four → Docker on three → postgres on one → app on `launchboard-app-1` fully, then `launchboard-app-2` fully → LB last.

Verify:

```bash
curl -s http://LB_PUBLIC_IP/health | python3 -m json.tool
curl -s http://LB_PUBLIC_IP/api/summary | python3 -m json.tool
```

Open `http://LB_PUBLIC_IP` in the browser — the LaunchBoard UI, served through the load balancer.

Prove the load balancing works:

```bash
ssh -i devops-launchboard-key.pem ubuntu@CONTROL_NODE_PUBLIC_IP   # if not already there
ansible launchboard-app-1 -m ansible.builtin.command -a "docker stop launchboard-frontend"
curl -s http://LB_PUBLIC_IP/health | python3 -m json.tool          # still works - served by app-2
ansible launchboard-app-1 -m ansible.builtin.command -a "docker start launchboard-frontend"
```

## Step 10: Watch A Rolling Deployment

Run the redeploy while watching the app from another terminal:

Terminal 1 (your local machine):

```bash
while true; do curl -s -o /dev/null -w "%{http_code}\n" http://LB_PUBLIC_IP/health; sleep 1; done
```

Terminal 2 (control node):

```bash
ansible-playbook deploy-app.yml --ask-vault-pass
```

Terminal 1 keeps printing `200` the whole time: while app-1 is being rebuilt and its containers recreated, Nginx's `proxy_next_upstream` sends traffic to app-2, and vice versa. The health gate ensures Ansible never moves to app-2 until app-1 is serving again. This is a zero-downtime deployment built from four primitives: a load balancer, two servers, `serial: 1`, and a health check.

Press Ctrl+C in terminal 1 when done.

## Cleanup

Terminate all five EC2 instances and delete the four security groups from the AWS Console. Ansible itself created nothing outside the instances.

## Troubleshooting

### Problem 1: `ERROR! Attempting to decrypt but no vault secrets found`

You ran a playbook without `--ask-vault-pass` while `group_vars/all/vault.yml` is encrypted. Add the flag, or configure `vault_password_file` in `ansible.cfg` pointing at a file (chmod 600) containing the vault password.

### Problem 2: `The task includes an option with an undefined variable ... 'private_ip'`

A host in `inventory.ini` is missing its `private_ip=...` value, or has a typo in the key name. Every host needs both `ansible_host` and `private_ip`.

### Problem 3: `Failed to import the required Python library (Docker SDK for Python)`

The `docker` role did not run on that host (check `site.yml` play targets), or you are running a `community.docker` task against the LB, which intentionally has no Docker.

### Problem 4: Migration task fails with connection refused / timeout to port 5432

The app servers cannot reach the database. Check: the `phase-15-db-sg` inbound rule allows 5432 from `phase-15-app-sg` (not from an IP); `db_host` resolves to the database's **private** IP (`ansible-inventory --host launchboard-db` shows what Ansible sees); and the postgres play ran before the app play (it does, in `site.yml` order).

### Problem 5: Backend starts but the UI shows CORS errors in the browser console

`cors_origins` did not match how you opened the app. It is derived from the LB's `ansible_host` — make sure you browse to exactly `http://LB_PUBLIC_IP` (the same IP as in the inventory), and that you re-ran `deploy-app.yml` after any inventory change so the backend containers got the new value.

### Problem 6: Image build fails with exit code 137

Out of memory on an app server — they must be `t3.medium`. Resize (stop > change type > start), update the public IP in the inventory if it changed, re-run.

### Problem 7: LB returns 502 for everything

Nginx is up but no upstream answers. Check the rendered config on the LB (`ansible launchboard-lb -m ansible.builtin.command -a "cat /etc/nginx/sites-enabled/launchboard"`) — the `server` lines must show the app servers' private IPs. Then check the app SG allows port 80 from the LB SG, and that the frontend containers are running on both app servers.

## Production Checklist

```text
[ ] Four security groups with tier-to-tier (SG-to-SG) rules
[ ] ansible all -m ping: four pongs
[ ] vault.yml encrypted; cat shows $ANSIBLE_VAULT header
[ ] vault.yml.example committed, real vault.yml safe to commit (encrypted)
[ ] site.yml runs clean end to end
[ ] App reachable only through the LB (direct app IP times out from your machine)
[ ] Database unreachable from your machine
[ ] Stopping one app server's containers does not take the site down
[ ] deploy-app.yml rolling redeploy with 200s throughout
[ ] Second site.yml run: changed only where expected (git/build/recreate tasks)
```

## Reference Documentation

| Topic | Link |
| --- | --- |
| Roles | https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html |
| Ansible Vault | https://docs.ansible.com/ansible/latest/vault_guide/index.html |
| Rolling updates (serial) | https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_strategies.html#setting-the-batch-size-with-serial |
| hostvars and groups | https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_vars_facts.html#accessing-information-about-other-hosts-with-magic-variables |
| community.docker modules | https://docs.ansible.com/ansible/latest/collections/community/docker/index.html |
| Nginx upstream | https://nginx.org/en/docs/http/ngx_http_upstream_module.html |
| Sample directory layout | https://docs.ansible.com/ansible/latest/tips_tricks/sample_setup.html |

## What To Do Next

Move to:

```text
Phase 16: Production Capstone
```

Why:

You have now used every tool in the journey: Docker, Compose, Swarm, Kubernetes, EKS, CI/CD, observability, security, DR, load testing, Terraform, and Ansible. The capstone assembles the Kubernetes track's best pieces into one production-grade deployment — the way you would actually run this application for real users.
