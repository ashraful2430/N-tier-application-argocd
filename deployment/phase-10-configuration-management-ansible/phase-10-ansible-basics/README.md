# Phase 10 (Part 1): Ansible Basics

## Fresh Start Assumption

This phase starts from a clean AWS environment.

You do not need to complete any previous phase before using this guide (Phase 9 is recommended context but not required).

This guide assumes:

- You have an AWS account with permission to create EC2 instances.
- Ansible is not installed yet.
- You will create files with `vim`.
- You will type commands manually.

Project repository:

```text
git@github.com:Ashik-DevOps-Class/N-tier-application.git
```

## What You Will Deploy

Two EC2 instances with different jobs:

```text
+---------------------------+          SSH           +---------------------------+
|  Control Node             | ---------------------> |  Managed Node             |
|  (workstation)            |                        |  (app server)             |
|                           |    Ansible modules     |                           |
|  - Ansible installed      |    run Python here     |  - NO Ansible installed   |
|  - playbooks + inventory  |                        |  - just Python + SSH      |
|  - your SSH key           |                        |                           |
+---------------------------+                        |  After the playbooks:     |
                                                     |  - Docker + Compose       |
                                                     |  - LaunchBoard running    |
                                                     |    (db, backend, frontend)|
                                                     +---------------------------+
```

The key idea: **Ansible is agentless.** Nothing is installed on the managed node. The control node connects over plain SSH, copies small Python programs (modules) over, runs them, reads the results, and deletes them. If you can SSH to a machine, Ansible can manage it.

By the end, the same app you deployed by hand in Phase 3/4 and with Terraform user data in Phase 9 is deployed by three playbooks — and re-running them is a no-op, because every task is idempotent.

## Core Vocabulary

| Term | Meaning |
| --- | --- |
| Control node | The machine where Ansible runs (your workstation) |
| Managed node | A machine Ansible configures over SSH |
| Inventory | The file listing managed nodes, organized into groups |
| Module | A unit of work Ansible executes (`apt`, `copy`, `service`, `git`, ...) |
| Task | One invocation of a module with arguments |
| Playbook | A YAML file of plays; a play maps a group of hosts to a list of tasks |
| Handler | A task that runs only when notified by a changed task (e.g. restart a service after its config changed) |
| Idempotency | Running the same task twice changes nothing the second time |
| Facts | Variables Ansible gathers about each host automatically (OS, IPs, CPU, ...) |

## Cost Warning

| Resource | Approximate Cost |
| --- | --- |
| 1 × t3.small (control) | ~$0.02/hour |
| 1 × t3.medium (managed) | ~$0.04/hour |

Terminate both instances after each session.

## Files Included In This Phase

```text
deployment/phase-10-configuration-management-ansible/phase-10-ansible-basics/
+-- ansible.cfg                       (Ansible defaults for this folder)
+-- inventory.ini.example             (managed node list - copy to inventory.ini)
+-- group_vars/
|   +-- app_servers.yml.example      (variables - copy to app_servers.yml)
+-- templates/
|   +-- launchboard.env.j2           (Jinja2 template for the app .env)
+-- playbooks/
    +-- 01-baseline.yml              (updates, base packages, timezone)
    +-- 02-docker.yml                (Docker Engine + log rotation + handler)
    +-- 03-deploy-app.yml            (clone, configure, compose up, health check)
+-- README.md
```

## Step 1: Create Two EC2 Instances

Create both from the AWS Console:

**Control node:**

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-10-control` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` |
| Storage | 20 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | SSH port 22, your IP only |

**Managed node (app server):**

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-10-app` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.medium` |
| Storage | 30 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | see below |

Managed node security group rules:

| Type | Port | Source | Purpose |
| --- | ---: | --- | --- |
| SSH | 22 | Control node's **private** IP `/32` (or its security group) | Ansible connections |
| SSH | 22 | Your IP | Optional direct debugging |
| HTTP | 80 | `0.0.0.0/0` | The app |

The managed node is `t3.medium` because playbook 03 builds the frontend image (`npm run build` needs ~4 GB RAM).

SSH into the **control node**:

```bash
chmod 400 devops-launchboard-key.pem
ssh -i devops-launchboard-key.pem ubuntu@YOUR_CONTROL_NODE_PUBLIC_IP
```

Reference:

- Launch EC2 instance: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EC2_GetStarted.html

## Step 2: Install Ansible On The Control Node

```bash
cd ~
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl vim software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible
```

Verify:

```bash
ansible --version
```

Expected: `ansible [core 2.1x.x]` plus the Python it uses.

Command explanation:

- `add-apt-repository ppa:ansible/ansible` registers Ansible's official Ubuntu PPA, which carries much newer versions than Ubuntu's default repositories. `--update` refreshes the package index in the same command.
- Ansible is installed **only here**. The managed node needs nothing (Ubuntu ships the Python that Ansible modules require).

Install the two collections the playbooks use:

```bash
ansible-galaxy collection install community.general community.docker
```

- Collections are Ansible's plugin packages. `ansible.builtin` modules (apt, copy, service...) ship with Ansible itself; `community.general` provides the `timezone` module and `community.docker` provides `docker_compose_v2`.

Reference:

- Installing Ansible: https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html
- Ansible collections: https://docs.ansible.com/ansible/latest/collections_guide/index.html

## Step 3: Give The Control Node SSH Access To The Managed Node

Ansible connects exactly like you do: SSH with a key. Copy the key pair's private key onto the control node.

On your **local machine** (where `devops-launchboard-key.pem` lives):

```bash
scp -i devops-launchboard-key.pem devops-launchboard-key.pem ubuntu@YOUR_CONTROL_NODE_PUBLIC_IP:/home/ubuntu/.ssh/devops-launchboard-key.pem
```

Back on the control node:

```bash
chmod 400 ~/.ssh/devops-launchboard-key.pem
ssh -i ~/.ssh/devops-launchboard-key.pem ubuntu@YOUR_APP_SERVER_PUBLIC_IP echo "manual ssh works"
exit
```

If that echo prints, Ansible will work — Ansible has no connection magic of its own.

(A cleaner alternative for real environments: generate a dedicated key pair on the control node and add its public key to the managed node's `~/.ssh/authorized_keys`. The copied-key shortcut keeps this lab focused on Ansible.)

## Step 4: Create The Working Folder, Config, And Inventory

```bash
cd ~
mkdir -p ansible-lab/playbooks ansible-lab/templates ansible-lab/group_vars
cd ansible-lab
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

[privilege_escalation]
become = True
become_method = sudo
```

Line explanation:

- Ansible reads `ansible.cfg` from the **current directory** first, so this file configures everything you run from `~/ansible-lab` without global changes.
- `inventory = inventory.ini` means you never need `-i inventory.ini` on the command line.
- `remote_user = ubuntu` and `private_key_file` are the SSH settings — the same `-i key.pem ubuntu@host` you type manually, made default.
- `host_key_checking = False` skips the interactive "authenticity of host can't be established" prompt. Acceptable in a lab with fresh instances; in production you would pre-populate `known_hosts` instead, because this setting disables man-in-the-middle protection.
- `interpreter_python = auto_silent` lets Ansible pick the managed node's Python without printing a discovery warning.
- `become = True` runs every task with `sudo` by default — almost everything in these playbooks (apt, service, writing to `/opt`) needs root. Individual tasks could override it with `become: false`.

### inventory.ini

```bash
vim inventory.ini
```

Paste with the app server's **public IP**:

```ini
[app_servers]
launchboard-app ansible_host=YOUR_APP_SERVER_PUBLIC_IP
```

Line explanation:

- `[app_servers]` defines a **group**. Playbooks target groups (`hosts: app_servers`), so adding a second server to the group later means the same playbooks configure it too — that is the entire scaling story.
- `launchboard-app` is the inventory name (what appears in output); `ansible_host` is where SSH actually connects. Separating them lets you use readable names regardless of IPs.

### group_vars/app_servers.yml

Variables in `group_vars/GROUPNAME.yml` automatically apply to every host in that group.

```bash
vim group_vars/app_servers.yml
```

Paste with a real password:

```yaml
db_password: CHANGE_ME_STRONG_PASSWORD
app_repo: https://github.com/Ashik-DevOps-Class/N-tier-application.git
app_dir: /opt/launchboard
compose_dir: /opt/launchboard/deployment/phase-04-docker-compose
```

This file contains a secret, so keep it out of Git (the repository ships `app_servers.yml.example` instead — the same `secret.example.yaml` pattern as the Kubernetes phases). The production lab replaces this with Ansible Vault.

Note on `app_repo`: the managed nodes clone this URL **anonymously over HTTPS**, which only works while the repository is public. If your class repository is private, either point `app_repo` at a public copy of the project, or skip cloning entirely by converting the app tasks to pull prebuilt images from Docker Hub — the exact pattern the Phase 9 Terraform basics lab uses.

## Step 5: First Contact — Ad-Hoc Commands

Before playbooks, run single modules straight from the command line:

```bash
ansible app_servers -m ping
```

Expected:

```text
launchboard-app | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

- `ping` is not ICMP — it SSHes in, runs a tiny Python module, and confirms Ansible can execute code on the host. If this works, everything else will.

Try more:

```bash
ansible app_servers -m ansible.builtin.setup -a "filter=ansible_memtotal_mb"
ansible app_servers -m ansible.builtin.apt -a "name=htop state=present"
ansible app_servers -m ansible.builtin.command -a "uptime"
```

- `setup` is the fact-gathering module — that `filter` shows the host's RAM. Playbooks run it automatically at the start; that is where variables like `ansible_distribution_release` come from.
- The `apt` example already demonstrates idempotency: run it twice — first time `CHANGED`, second time `SUCCESS` with `"changed": false`.
- Ad-hoc commands are for exploration and one-offs. Anything you want to keep goes in a playbook.

## Step 6: Playbook 1 — Baseline

```bash
vim playbooks/01-baseline.yml
```

Paste:

```yaml
---
- name: Baseline server configuration
  hosts: app_servers

  tasks:
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

Line explanation:

- The file is one **play**: `hosts: app_servers` binds the task list to the inventory group. `name:` strings appear in the output — always write them.
- `ansible.builtin.apt` is the module's fully qualified name (collection `ansible.builtin`, module `apt`). Short names (`apt:`) work, but qualified names are unambiguous and are what current documentation uses.
- `update_cache: true` = `apt update`; `upgrade: safe` = `apt upgrade` (never removes packages); `cache_valid_time: 3600` skips the cache update if it is fresher than an hour — an idempotency optimization.
- `state: present` is the declarative heart of Ansible: not "install this" but "this must be installed." Already installed → `ok`, nothing happens.

Check syntax without connecting, then do a dry run, then run it:

```bash
ansible-playbook playbooks/01-baseline.yml --syntax-check
ansible-playbook playbooks/01-baseline.yml --check
ansible-playbook playbooks/01-baseline.yml
```

- `--check` is **check mode**: Ansible connects and reports what *would* change, changing nothing — Ansible's answer to `terraform plan`.

The run ends with a recap:

```text
PLAY RECAP *********************************************************
launchboard-app  : ok=4  changed=3  unreachable=0  failed=0  skipped=0
```

(`ok=4` counts the automatic fact-gathering task too.) Now run it **again** — the recap shows `changed=0`. That is idempotency, demonstrated.

## Step 7: Playbook 2 — Docker (And Your First Handler)

```bash
vim playbooks/02-docker.yml
```

Paste:

```yaml
---
- name: Install Docker Engine
  hosts: app_servers

  handlers:
    - name: Restart docker
      ansible.builtin.service:
        name: docker
        state: restarted

  tasks:
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
          - docker-compose-plugin
        update_cache: true
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

Line explanation:

- These tasks are the exact `curl | gpg` / `echo | tee` / `apt install` sequence you typed in Phases 3-14, expressed as idempotent modules.
- `{{ ... }}` is Jinja2 templating. `ansible_distribution_release` and `ansible_architecture` are **facts** gathered from the host — this playbook works unchanged on any Ubuntu version and architecture. The `| replace('x86_64', 'amd64')` filter converts kernel naming to Debian package naming.
- **The handler pattern**: `notify: Restart docker` on the `daemon.json` task means: *only if this task actually changed the file*, run the handler named "Restart docker" — once, at the end of the play, even if several tasks notified it. Run the playbook twice and watch: first run restarts Docker, second run does not (file unchanged → no notification). This is how config-file-plus-service-restart is done without restarting on every run.
- `ansible.builtin.user` with `groups: docker, append: true` adds the group **without removing** the user's other groups — omitting `append` would replace them, a classic Ansible beginner bug.

Run it:

```bash
ansible-playbook playbooks/02-docker.yml
```

Verify from the control node with an ad-hoc command:

```bash
ansible app_servers -m ansible.builtin.command -a "docker --version"
```

## Step 8: Playbook 3 — Deploy The App

First the template it uses:

```bash
vim templates/launchboard.env.j2
```

Paste:

```text
PROJECT_NAME=devops-launchboard
POSTGRES_DB=launchboard
POSTGRES_USER=launchboard_user
POSTGRES_PASSWORD={{ db_password }}
DATABASE_URL=postgresql+asyncpg://launchboard_user:{{ db_password }}@launchboard-db:5432/launchboard
APP_NAME=DevOps LaunchBoard API
APP_ENV=production
CORS_ORIGINS=http://{{ ansible_host }}
SEED_DEMO_DATA=true
VITE_API_URL=
BACKEND_IMAGE=launchboard-backend:phase-10
FRONTEND_IMAGE=launchboard-frontend:phase-10
```

- A `.j2` file is a Jinja2 template: the `template` module renders every `{{ variable }}` with real values *before* writing the file to the managed node. `db_password` comes from `group_vars/app_servers.yml`; `ansible_host` comes from the inventory — so CORS is automatically the server's own public IP, the value you edited by hand in Phase 4.

Now the playbook:

```bash
vim playbooks/03-deploy-app.yml
```

Paste:

```yaml
---
- name: Deploy DevOps LaunchBoard with Docker Compose
  hosts: app_servers

  tasks:
    - name: Clone the application repository
      ansible.builtin.git:
        repo: "{{ app_repo }}"
        dest: "{{ app_dir }}"
        version: main
        force: true

    - name: Write the Compose environment file
      ansible.builtin.template:
        src: ../templates/launchboard.env.j2
        dest: "{{ compose_dir }}/.env"
        mode: "0600"

    - name: Build and start the application stack
      community.docker.docker_compose_v2:
        project_src: "{{ compose_dir }}"
        build: always
        state: present

    - name: Wait for the backend to answer health checks
      ansible.builtin.uri:
        url: "http://127.0.0.1/health"
        status_code: 200
      register: health_result
      retries: 12
      delay: 10
      until: health_result.status == 200

    - name: Show the app URL
      ansible.builtin.debug:
        msg: "App is up at http://{{ ansible_host }}"
```

Line explanation:

- `ansible.builtin.git` clones on first run and fetches/updates on later runs (`version: main` pins the branch; `force: true` discards local modifications so the checkout always matches the repository).
- `ansible.builtin.template` renders the `.env` with `mode: "0600"` (owner-only, it contains the password). `src` is relative to the playbook file, hence `../templates/`.
- `community.docker.docker_compose_v2` drives `docker compose` as a module: `state: present` means "the stack is up", `build: always` rebuilds images from the cloned source. Re-running when nothing changed reports `ok`.
- The `uri` task polls `http://127.0.0.1/health` **from the managed node** (tasks run there, not on the control node): up to 12 retries, 10 seconds apart. `register` stores the response; `until` is the success condition. A deploy that says "done" before the app actually answers is not a deploy — this task encodes that principle.

Run it (first run takes several minutes — image builds):

```bash
ansible-playbook playbooks/03-deploy-app.yml
```

Open `http://YOUR_APP_SERVER_PUBLIC_IP` in the browser: the LaunchBoard UI with demo data.

Then re-run the playbook and read the recap: `changed=0` (or only the git task changed if the branch moved). Deploying is now safe to repeat any time.

## Step 9: The Payoff — Configure A Second Server In One Line

To see why inventories and groups matter: launch one more EC2 instance exactly like the managed node in Step 1, then add one line to `inventory.ini`:

```ini
[app_servers]
launchboard-app ansible_host=YOUR_APP_SERVER_PUBLIC_IP
launchboard-app-2 ansible_host=YOUR_SECOND_SERVER_PUBLIC_IP
```

Run all three playbooks again:

```bash
ansible-playbook playbooks/01-baseline.yml
ansible-playbook playbooks/02-docker.yml
ansible-playbook playbooks/03-deploy-app.yml
```

The existing server reports `ok` everywhere (idempotency); the new server gets fully configured and deployed from bare Ubuntu — no new code written. That is configuration management: servers are cattle described by group membership, not pets configured by hand.

(Terminate the second instance when done experimenting.)

## Cleanup

Terminate both EC2 instances from the AWS Console. There is nothing else to clean up — Ansible created no cloud resources, only configuration inside the instances.

## Troubleshooting

### Problem 1: `UNREACHABLE! ... Permission denied (publickey)`

Ansible's SSH failed. Debug it as plain SSH: `ssh -i ~/.ssh/devops-launchboard-key.pem ubuntu@THE_IP`. Usual causes: key not copied to the control node (Step 3), wrong `private_key_file` path in `ansible.cfg`, wrong IP in the inventory, or the managed node's security group does not allow SSH from the control node.

### Problem 2: `UNREACHABLE! ... Connection timed out`

Network, not auth: the security group blocks port 22 from the control node's IP, or the instance is stopped. If you allowed the control node's *private* IP, both instances must be in the same VPC (default VPC covers this if you changed nothing).

### Problem 3: `couldn't resolve module/action 'community.docker.docker_compose_v2'`

The collection is missing: `ansible-galaxy collection install community.docker`. If it is installed but still unresolved, your Ansible version predates v2 of the module — upgrade via the PPA (Step 2) rather than using Ubuntu's default package.

### Problem 4: The compose build task fails with exit code 137 or hangs

Out of memory during `npm run build` — the managed node is a `t3.small` or smaller. Stop the instance, change the type to `t3.medium`, start it, update the (possibly new) public IP in `inventory.ini`, and re-run playbook 03.

### Problem 5: Health check task fails after 12 retries

The stack did not come up. Check the containers from the control node:

```bash
ansible app_servers -m ansible.builtin.command -a "docker ps -a"
ansible app_servers -m ansible.builtin.command -a "docker logs launchboard-backend --tail 30"
```

Most common cause: a typo in `group_vars/app_servers.yml` breaking `DATABASE_URL` in the rendered `.env`.

### Problem 6: Every task is slow (~10s of SSH overhead per task)

Normal for a first run over long geographic distance; also make sure you are not running Ansible from your laptop against a far region. Ansible reuses SSH connections (ControlPersist) automatically, so subsequent tasks in a run are faster than the first.

## Production Checklist

```text
[ ] Ansible installed on the control node only
[ ] ansible app_servers -m ping returns pong
[ ] ansible.cfg, inventory.ini, group_vars in place
[ ] group_vars/app_servers.yml NOT committed (example file is)
[ ] Playbook 01 run twice - second run changed=0
[ ] Handler fired on first docker run, not on the second
[ ] App deployed by playbook 03 and reachable on port 80
[ ] Health check task passed (not just "playbook finished")
[ ] Understood: same playbooks configure any number of group members
```

## Reference Documentation

| Topic | Link |
| --- | --- |
| Ansible documentation | https://docs.ansible.com/ansible/latest/index.html |
| Getting started | https://docs.ansible.com/ansible/latest/getting_started/index.html |
| Inventory | https://docs.ansible.com/ansible/latest/inventory_guide/index.html |
| Playbooks | https://docs.ansible.com/ansible/latest/playbook_guide/index.html |
| Handlers | https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_handlers.html |
| Variables | https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html |
| Templating (Jinja2) | https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_templating.html |
| Module index | https://docs.ansible.com/ansible/latest/collections/index_module.html |
| community.docker collection | https://docs.ansible.com/ansible/latest/collections/community/docker/index.html |

## What To Do Next

Move to:

```text
deployment/phase-10-configuration-management-ansible/phase-10-ansible-production
```

Why:

You know inventories, modules, playbooks, variables, templates, handlers, and idempotency. The production lab organizes them the way real teams do: reusable **roles** instead of flat playbooks, **Ansible Vault** for encrypted secrets, a four-server topology (load balancer, two app servers, database), and a **rolling deployment** that updates one app server at a time behind the load balancer with health checks gating each step.
