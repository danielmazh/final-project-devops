# ansible/

Configuration management playbooks that run after Terraform provisions the infrastructure. Four playbooks handle local tool verification, EKS cluster configuration, and Jenkins EC2 setup.

## Files

```
ansible/
├── inventory.ini                           # Host groups: [local] + [jenkins]
└── playbooks/
    ├── install-tools.yaml                  # Verify local DevOps tool versions
    ├── configure-eks.yaml                  # Update kubeconfig, create namespaces
    ├── configure-jenkins.yaml              # Install Docker + Jenkins on EC2
    └── configure-jenkins-tools.yaml        # Install shellcheck + yamllint for CI
```

## Playbook Details

### install-tools.yaml

**Target:** localhost  
**Purpose:** Verifies all required tools are present and prints their versions.

```bash
ansible-playbook ansible/playbooks/install-tools.yaml -i ansible/inventory.ini
```

Checks: `terraform`, `kubectl`, `helm`, `aws`, `ansible`.

### configure-eks.yaml

**Target:** localhost  
**Purpose:** Configures local kubectl to access the EKS cluster and creates project namespaces.

```bash
ansible-playbook ansible/playbooks/configure-eks.yaml -i ansible/inventory.ini
```

Steps:
1. `aws eks update-kubeconfig --name seyoawe-cluster`
2. Wait for cluster API (retries 10× with 15s delay)
3. Verify worker nodes are Ready
4. Create namespaces: `seyoawe`, `monitoring`

### configure-jenkins.yaml

**Target:** Jenkins EC2 (via SSH)  
**Purpose:** Installs Docker, starts Jenkins LTS container, and configures Docker-in-Jenkins.

```bash
JENKINS_IP=$(cd terraform && terraform output -raw jenkins_public_ip)
ansible-playbook ansible/playbooks/configure-jenkins.yaml \
  -i "${JENKINS_IP}," \
  --user ec2-user \
  --private-key ~/keys/devops-key-private-account.pem
```

Steps:
1. Install Docker via `dnf`
2. Start and enable Docker service
3. Add `ec2-user` to `docker` group
4. Create `/var/jenkins_home` directory
5. Start `jenkins/jenkins:lts` container (bind-mounted Docker socket + jenkins_home volume)
6. Copy Docker CLI binary into Jenkins container
7. Add `jenkins` user to docker group (matching host GID)
8. Download `kubectl` to host
9. Install `awscli` via pip3

### configure-jenkins-tools.yaml

**Target:** Jenkins EC2  
**Purpose:** Installs lint tools needed by CI pipelines.

```bash
ansible-playbook ansible/playbooks/configure-jenkins-tools.yaml \
  -i "${JENKINS_IP}," \
  --user ec2-user \
  --private-key ~/keys/devops-key-private-account.pem
```

Steps:
1. Download `shellcheck` binary from GitHub releases
2. Install to `/usr/local/bin/shellcheck` on host
3. Copy `shellcheck` into Jenkins container
4. Install `yamllint` via pip3
5. Verify both tools

## Inventory

```ini
[local]
localhost ansible_connection=local

[jenkins]
# Populated from terraform output — see playbook comments for ad-hoc usage
```

Jenkins host is typically passed inline (`-i "${IP},"`) rather than hard-coded, since the EC2 public IP changes after stop/start cycles.
