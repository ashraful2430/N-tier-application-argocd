# Phase 15: Configuration Management With Ansible

This phase teaches Ansible in two stages, the same structure as Phase 7 (CI/CD) and Phase 14 (Terraform):

```text
deployment/phase-15-configuration-management-ansible/
+-- phase-15-ansible-basics/          (start here)
+-- phase-15-ansible-production/      (do this second)
```

## Which One Should You Do?

| | ansible-basics | ansible-production |
| --- | --- | --- |
| Goal | Learn Ansible fundamentals | Deploy like a real company |
| Servers | 1 managed node | 4 nodes: load balancer, 2 app servers, database |
| Structure | Flat playbooks | Roles |
| Secrets | Plain variable file (lab only) | Ansible Vault (encrypted at rest) |
| Deployment | All at once | Rolling, one app server at a time, with health checks |
| App runs as | Docker Compose on one host | Docker containers per tier across hosts |

Do `phase-15-ansible-basics` first — the production lab assumes you know inventories, modules, playbooks, variables, templates, and handlers.

## Terraform vs Ansible: Why Both Exist

Phase 14 (Terraform) **creates machines**. This phase (Ansible) **configures what runs inside machines that already exist**.

| | Terraform | Ansible |
| --- | --- | --- |
| Question it answers | What infrastructure exists? | What is installed and running on it? |
| Model | Declarative with state file | Mostly declarative tasks, no state file |
| Talks to | Cloud provider APIs | The machines themselves, over SSH |
| Typical unit | VPC, instance, load balancer | Package, config file, service, container |
| Repeat behavior | Plan shows drift vs state | Tasks are idempotent: re-running changes nothing if already correct |

Real companies commonly run both: `terraform apply` builds the servers, then `ansible-playbook` configures them. (Terraform's user data — which you used in Phase 14 — covers simple first-boot setup; Ansible takes over when configuration is bigger than one script, changes over time, or spans many hosts.)

The single most important Ansible concept is **idempotency**: a task describes a desired state ("this package is installed", "this line is in this file", "this container is running"), and running it twice is safe — the second run reports `ok` instead of `changed` and does nothing. This is what makes Ansible different from a pile of shell scripts.

## What To Do Next

After both labs, move to Phase 16 (Production Capstone) — the final phase that combines everything from the entire journey into one production-grade deployment.
