# SeyoAWE Community — Full DevOps Lifecycle Implementation

## Final DevOps Project Presentation

**Daniel Mazmazhbits**  
**Version:** `0.1.1` | **Date:** March 2026

---

## Slide 1 — Introduction & Project Architecture

### Project Requirement

> Build a complete DevOps lifecycle around the SeyoAWE Community application — from Git to Observability.

### Technical Deep-Dive

This project wraps **SeyoAWE Community** — a YAML-driven workflow automation engine shipped as a compiled Go binary with a Python CLI (Command-Line Interface) (`sawectl`). The project implements every stage of the DevOps lifecycle:

- **Containerization** — Two Docker images: Engine (Go binary + Python modules) and CLI (Python)
- **CI (Continuous Integration)** — Two Jenkins Declarative Pipelines (Engine CI, CLI CI) with intelligent change detection
- **IaC (Infrastructure as Code)** — Full AWS infrastructure via Terraform: VPC (Virtual Private Cloud), EKS (Elastic Kubernetes Service), Jenkins EC2 (Elastic Compute Cloud), IRSA (IAM Roles for Service Accounts)
- **Configuration Management** — Four Ansible playbooks for Jenkins and EKS configuration
- **CD (Continuous Delivery)** — Third Jenkins pipeline with a Manual Approval Gate before infrastructure changes
- **K8s (Kubernetes)** — StatefulSet on EKS with PVC (PersistentVolumeClaim) and ConfigMap injection
- **Observability** — kube-prometheus-stack Helm chart (Prometheus + Grafana + Alertmanager)

**PoC-first philosophy:** Every architectural decision is driven by minimal cost and simplicity:

| Decision | Rationale |
|----------|-----------|
| `t3.medium` (3 instances) | Minimum viable instance type for EKS workers + Jenkins |
| Single NAT (Network Address Translation) Gateway | Saves ~$0.05/hr versus a HA (High Availability) dual-NAT setup |
| S3-only state locking (`use_lockfile = true`) | Terraform 1.14+ feature — **no DynamoDB table needed**, saves ~$0.25/hr and eliminates a managed resource |
| 1-replica StatefulSet | Sufficient for PoC, conserves node capacity |
| `lifecycle.sh` suspend/resume | Stop EC2/EKS when not working — **~$0.27/hr only when everything is running** |

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│  Developer Workstation                                              │
│  .venv/bin/ → terraform, kubectl, helm, aws, ansible, pytest        │
│  lifecycle.sh → stop/start/destroy AWS resources                    │
└──────┬──────────────────────────┬───────────────────────────────────┘
       │ git push                 │ kubectl / helm
       ▼                          ▼
┌─────────────┐       ┌────────────────────────────────────────────────┐
│   GitHub    │       │  AWS (us-east-1)                                │
│             │       │                                                │
│ Tags:       │       │  VPC 10.0.0.0/16                               │
│ engine-v0.1.1│      │  ├── Public-A  ── NAT GW + Jenkins EC2 :8080   │
│ cli-v0.1.1  │       │  ├── Public-B                                  │
└──────┬──────┘       │  ├── Private-A ── EKS Worker Node 1            │
       │              │  └── Private-B ── EKS Worker Node 2            │
       │ build        │                                                │
       ▼              │  EKS seyoawe-cluster (v1.32)                   │
┌─────────────┐       │  ├── ns: seyoawe                               │
│ Jenkins EC2 │───────│  │   ├── seyoawe-engine-0 (StatefulSet)        │
│ 3 Pipelines │       │  │   ├── Service :8080/:8081                   │
│ engine-ci   │       │  │   ├── ConfigMap (config.yaml)               │
│ cli-ci      │       │  │   └── PVC 2Gi (logs + lifetimes)            │
│ cd          │       │  └── ns: monitoring                            │
└──────┬──────┘       │      ├── Prometheus (14 scrape targets)        │
       │ push         │      ├── Grafana (28 dashboards)               │
       ▼              │      ├── Alertmanager                          │
┌─────────────┐       │      └── ServiceMonitor → seyoawe-engine       │
│  DockerHub  │       │                                                │
│ seyoawe-    │       │  S3: seyoawe-tf-state-632008729195             │
│ engine/cli  │       │  (Terraform remote state, S3-native lock)      │
└─────────────┘       └────────────────────────────────────────────────┘
```

### Key UI Access Points

| Component | URL | Credentials |
|-----------|-----|-------------|
| **Jenkins UI** | [http://JENKINS_IP:8080](http://44.201.6.188:8080) | Initial admin password from `jenkins logs` |
| **Grafana** | [http://localhost:3000](http://localhost:3000) (via port-forward) | `admin` / `seyoawe-grafana` |
| **Prometheus** | [http://localhost:9090](http://localhost:9090) (via port-forward) | No auth |
| **GitHub Repo** | [github.com/danielmazh/final-project-devops](https://github.com/danielmazh/final-project-devops) | — |
| **DockerHub Engine** | [hub.docker.com/r/danielmazh/seyoawe-engine](https://hub.docker.com/r/danielmazh/seyoawe-engine) | — |
| **DockerHub CLI** | [hub.docker.com/r/danielmazh/seyoawe-cli](https://hub.docker.com/r/danielmazh/seyoawe-cli) | — |

---

## Slide 2 — Phase 1: Repository & Environment Setup

### Project Requirement

> Task 1 — Code Structure & Documentation (5 pts)

### Technical Deep-Dive

Phase 1 establishes the project skeleton: a modular directory layout, comprehensive documentation, and **8 Design Logs** that formally record every architectural decision before implementation begins (design-first methodology).

**The `VERSION` file** serves as the **Single Source of Truth** for the entire project. Every CI/CD pipeline reads the version from this file using `cat VERSION | tr -d '[:space:]'`. Modifying the `VERSION` file triggers **both** CI pipelines simultaneously, guaranteeing full version coupling between Engine and CLI — they always share the same semantic version (`0.1.1`).

**Development environment (`setup-env.sh`):** A 241-line bootstrap script that creates a fully self-contained `.venv` with all required tools — Terraform 1.14, kubectl v1.34.1, Helm v3.17, AWS CLI (Command Line Interface), Ansible, pytest — without any global installations. AWS credentials are isolated in `.aws-project/` (not `~/.aws/`), so the project never interferes with the developer's personal AWS configuration. The script patches the venv's `activate` script to automatically export `AWS_CONFIG_FILE`, `AWS_SHARED_CREDENTIALS_FILE`, `AWS_PROFILE=seyoawe-tf`, and `TF_DIR`.

### Relevant Files & Structure

- **`VERSION`** — Plain text file containing `0.1.1`. Read by every Jenkinsfile via `cat VERSION | tr -d '[:space:]'`. Any change to this file triggers both Engine CI and CLI CI pipelines simultaneously, enforcing version coupling.
- **`setup-env.sh`** — 241-line bootstrap script: creates a Python venv, downloads Terraform/kubectl/Helm as static binaries into `.venv/bin/`, creates `.aws-project/config` with the `seyoawe-tf` profile, and idempotently patches the venv's `activate` script with project-specific environment variables.
- **`README.md`** — 189-line project documentation: architecture diagram (ASCII), repository structure, Quick Start guide, Access Points table, CI/CD pipeline overview, cost management commands.
- **`.cursor/design-logs/0001_phase1_repo_setup.md`** — Design Log for Phase 1: directory structure decisions, Flat Layout choice for Terraform, VERSION file strategy.
- **`.cursor/design-logs/0002_phase2_aws_infra.md`** — Design Log for Phase 2: VPC topology, EKS vs. self-managed Kubernetes, single NAT vs. HA NAT trade-off analysis.
- **`.cursor/design-logs/0003_lifecycle_management_script.md`** — Design Log for lifecycle.sh: Resource Registry pattern, suspend/resume/destroy flows, cost estimation logic.
- **`.cursor/design-logs/0004_project_venv_setup.md`** — Design Log for setup-env.sh: tool version pinning strategy, per-project AWS credential isolation, venv activate patching.
- **`.cursor/design-logs/0005_phase3_containerization.md`** — Design Log for Dockerization: binary guard pattern, HEALTHCHECK without a /health endpoint, version injection via `sed`.
- **`.cursor/design-logs/0006_phase4_ci_pipelines.md`** — Design Log for CI: change detection logic, `GIT_PREVIOUS_SUCCESSFUL_COMMIT` usage, `when` condition pattern for stage skipping.
- **`.cursor/design-logs/0007_phase5_cd_kubernetes.md`** — Design Log for CD + K8s: StatefulSet vs. Deployment reasoning, tcpSocket probes, IRSA (IAM Roles for Service Accounts) for EBS CSI (Container Storage Interface).
- **`.cursor/design-logs/0008_phase6_observability.md`** — Design Log for Observability: kube-prometheus-stack sizing for t3.medium nodes, ServiceMonitor configuration, quay.io → docker.io mirror workaround.
- **`.cursor/plans/0001_devops_final_project_master_plan.md`** — Master Plan covering all project phases with acceptance criteria.
- **`.cursor/reports/0001_final_project_technical_report.md`** — Comprehensive technical report summarizing the entire implementation.
- **`.cursor/reports/0002_requirements_traceability_report.md`** — Requirements traceability matrix mapping every rubric item to its implementation.

### Live Demo & Commands

```bash
# 1. Confirm the single source of truth for version — every pipeline and Docker build reads from this file
cat VERSION
# Expected output: 0.1.1

# 2. Bootstrap the fully isolated dev environment — downloads all tools into .venv without touching global installs
bash setup-env.sh
source .venv/bin/activate

# 3. Prove all 5 DevOps tools are installed at the exact pinned versions inside the venv
printf "%-14s %s\n" \
  "Terraform"  "$(terraform --version | head -1)" \
  "kubectl"    "$(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | awk '{print $2}')" \
  "Helm"       "$(helm version --short)" \
  "AWS CLI"    "$(aws --version 2>&1 | awk '{print $1}')" \
  "Ansible"    "$(ansible --version | head -1)"
# Expected output:
#   Terraform      Terraform v1.14.0
#   kubectl        v1.34.1
#   Helm           v3.17.0+g301108e
#   AWS CLI        aws-cli/1.44.68
#   Ansible        ansible [core 2.18.15]

# 4. Show all 8 design logs — proves design-first methodology was followed for every project phase
ls -la .cursor/design-logs/
# Expected output: 8 files (0001 through 0008)

# 5. Run the Ansible verification playbook — confirms tool versions are consistent across local and remote hosts
ansible-playbook ansible/playbooks/install-tools.yaml -i ansible/inventory.ini
```

---

## Slide 3 — Phase 2 & 5: Infrastructure as Code & CD Pipeline

### Project Requirement

> Task 5 — IaC (Infrastructure as Code) & CD (Continuous Delivery) Pipeline (20 pts): Terraform provisioning, Ansible configuration, Jenkins CD with Approval Gate

### Technical Deep-Dive

#### Terraform — Flat Layout

A **Flat Layout** was chosen (single `main.tf` with all resources) instead of a module-based layout. For a PoC with ~25 resources, this approach is simpler to review, easier to debug, and avoids the overhead of module interfaces. All resource definitions live in one 412-line file, making it straightforward for an examiner to see the complete infrastructure at a glance.

**Backend:** S3 with **S3-native locking** (`use_lockfile = true`) — a new capability in Terraform 1.14 that creates a `.tflock` file in the S3 bucket to prevent concurrent state modifications. This completely eliminates the need for a DynamoDB table for state locking, saving both cost (~$0.25/hr) and operational complexity (one fewer managed resource to track).

> **Verify — Terraform State & Backend:**
> ```bash
> # Confirm Terraform state is connected to the S3 backend and all 31 resources are tracked
> cd terraform && terraform state list | wc -l
> # Expected: 31 resources (including data sources and policy attachments)
>
> # Display every AWS resource managed by Terraform — proves IaC (Infrastructure as Code) manages the entire stack
> terraform state list
> # Expected (31 resources — data sources + managed):
> #   data.aws_ami.amazon_linux_2023
> #   data.aws_availability_zones.available
> #   data.aws_iam_policy_document.eks_cluster_assume_role
> #   data.aws_iam_policy_document.eks_node_assume_role
> #   aws_eip.nat
> #   aws_eks_addon.coredns
> #   aws_eks_addon.kube_proxy
> #   aws_eks_addon.vpc_cni
> #   aws_eks_cluster.main
> #   aws_eks_node_group.main
> #   aws_iam_role.eks_cluster
> #   aws_iam_role.eks_node
> #   aws_iam_role_policy_attachment.eks_cluster_policy
> #   aws_iam_role_policy_attachment.eks_cni_policy
> #   aws_iam_role_policy_attachment.eks_ecr_read_only
> #   aws_iam_role_policy_attachment.eks_worker_node_policy
> #   aws_instance.jenkins
> #   aws_internet_gateway.main
> #   aws_nat_gateway.main
> #   aws_route_table.private
> #   aws_route_table.public
> #   aws_route_table_association.private_a / .private_b / .public_a / .public_b
> #   aws_security_group.jenkins
> #   aws_subnet.private_a / .private_b / .public_a / .public_b
> #   aws_vpc.main
>
> # Prove the S3 remote state backend exists and holds the tfstate file — this is where Terraform persists infrastructure state
> aws s3 ls s3://seyoawe-tf-state-632008729195/dev/ --profile seyoawe-tf
> # Expected: YYYY-MM-DD HH:MM:SS  62138 terraform.tfstate
> ```

**VPC (Virtual Private Cloud) Topology:**
- CIDR (Classless Inter-Domain Routing): `10.0.0.0/16` — provides 65,536 IP addresses, far more than needed for PoC but follows best practice
- 2 Public Subnets (`10.0.1.0/24`, `10.0.2.0/24`) — house the Jenkins EC2 instance and the NAT Gateway
- 2 Private Subnets (`10.0.10.0/24`, `10.0.20.0/24`) — house the EKS worker nodes (no direct internet exposure)
- **Single NAT (Network Address Translation) Gateway** in Public-A — PoC choice; not HA (High Availability), but saves ~$0.05/hr. A production setup would place a NAT in each AZ (Availability Zone).
- IGW (Internet Gateway) for outbound traffic from public subnets
- Kubernetes-specific subnet tags (`kubernetes.io/cluster/seyoawe-cluster`, `kubernetes.io/role/elb`, `kubernetes.io/role/internal-elb`) for ELB (Elastic Load Balancer) auto-discovery

> **Verify — VPC & Networking:**
> ```bash
> # Prove the VPC (Virtual Private Cloud) was created with the correct CIDR block and is in available state
> aws ec2 describe-vpcs --filters "Name=tag:Name,Values=seyoawe-vpc" \
>     --query "Vpcs[0].{VpcId:VpcId, CIDR:CidrBlock, State:State}" \
>     --output table --profile seyoawe-tf
> # Expected: 10.0.0.0/16, available
>
> # Verify all 4 subnets exist with correct CIDR (Classless Inter-Domain Routing) blocks across 2 AZs (Availability Zones)
> aws ec2 describe-subnets --filters "Name=tag:Project,Values=seyoawe" \
>     --query "Subnets[].{Name:Tags[?Key=='Name']|[0].Value, CIDR:CidrBlock, AZ:AvailabilityZone}" \
>     --output table --profile seyoawe-tf
> # Expected: seyoawe-public-a (10.0.1.0/24), seyoawe-public-b (10.0.2.0/24),
> #           seyoawe-private-a (10.0.10.0/24), seyoawe-private-b (10.0.20.0/24)
>
> # Confirm the single NAT (Network Address Translation) Gateway is active — allows private subnet nodes to reach the internet
> aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=seyoawe-nat" \
>     --query "NatGateways[0].{State:State, SubnetId:SubnetId, PublicIp:NatGatewayAddresses[0].PublicIp}" \
>     --output table --profile seyoawe-tf
> # Expected: State=available, PublicIp=<EIP>
> ```

**EKS (Elastic Kubernetes Service) Cluster:**
- Version: `1.32` with dual endpoint access (`endpoint_public_access = true`, `endpoint_private_access = true`)
- Authentication mode: `API_AND_CONFIG_MAP` with bootstrap admin permissions
- Node Group: 2× `t3.medium` (4 vCPU, 8 GiB each), AMI (Amazon Machine Image) `AL2023_x86_64_STANDARD`, ON_DEMAND capacity
- Scaling config: min=2, max=3, desired=2
- Four managed addons: `vpc-cni` (pod networking), `kube-proxy` (service routing), `coredns` (DNS resolution, depends on node group), `aws-ebs-csi-driver` (persistent volumes, uses IRSA)
- OIDC (OpenID Connect) Provider for IRSA (IAM Roles for Service Accounts) — enables EBS (Elastic Block Store) CSI (Container Storage Interface) controller to create/attach EBS volumes without node-level IAM (Identity and Access Management) permissions

> **Verify — EKS (Elastic Kubernetes Service) Cluster & Nodes:**
> ```bash
> # Confirm the EKS cluster is ACTIVE and running Kubernetes v1.32 — the managed control plane is healthy
> aws eks describe-cluster --name seyoawe-cluster \
>     --query "cluster.{Status:status, Version:version, Endpoint:endpoint}" \
>     --output table --profile seyoawe-tf
> # Expected: Status=ACTIVE, Version=1.32
>
> # Verify the node group has 2 worker nodes of the correct instance type with the expected scaling bounds
> aws eks describe-nodegroup --cluster-name seyoawe-cluster --nodegroup-name seyoawe-nodes \
>     --query "nodegroup.{Status:status, InstanceType:instanceTypes[0], Desired:scalingConfig.desiredSize, Min:scalingConfig.minSize, Max:scalingConfig.maxSize}" \
>     --output table --profile seyoawe-tf
> # Expected: Status=ACTIVE, InstanceType=t3.medium, Desired=2, Min=2, Max=3
>
> # Prove both worker nodes are Ready and registered with the cluster — confirms the node group joined successfully
> kubectl get nodes -o wide
> # Expected: 2 nodes, STATUS=Ready, VERSION=v1.32.x-eks-xxxxxxx, OS=Amazon Linux 2023
>
> # List all 4 EKS managed addons — proves networking, DNS, proxy, and storage drivers are installed
> aws eks list-addons --cluster-name seyoawe-cluster --output table --profile seyoawe-tf
> # Expected: vpc-cni, kube-proxy, coredns, aws-ebs-csi-driver
> ```

**Jenkins EC2 (Elastic Compute Cloud):**
- Instance type: `t3.medium`, AMI (Amazon Machine Image): Amazon Linux 2023 (latest, auto-discovered via `data.aws_ami`)
- Placed in public subnet with a SG (Security Group) restricted to `operator_ip` variable (SSH port 22 + Jenkins UI port 8080)
- Root volume: 30GB gp3, encrypted at rest
- No EIP (Elastic IP) — IP changes on stop/start, but `lifecycle.sh start jenkins` reports the new IP

> **Verify — Jenkins EC2 (Elastic Compute Cloud):**
> ```bash
> # Confirm the Jenkins EC2 instance is running and show its public IP — proves Terraform provisioned the CI/CD server
> aws ec2 describe-instances --filters "Name=tag:Name,Values=seyoawe-jenkins" \
>     --query "Reservations[0].Instances[0].{State:State.Name, Type:InstanceType, IP:PublicIpAddress, AZ:Placement.AvailabilityZone}" \
>     --output table --profile seyoawe-tf
> # Expected: State=running, Type=t3.medium, IP=<public-ip>
>
> # Show the SG (Security Group) rules — proves Jenkins is locked down to only the operator's IP on ports 22 and 8080
> aws ec2 describe-security-groups --filters "Name=group-name,Values=seyoawe-jenkins-sg" \
>     --query "SecurityGroups[0].IpPermissions[].{Port:FromPort, Source:IpRanges[0].CidrIp}" \
>     --output table --profile seyoawe-tf
> # Expected: Port=22 Source=<your-ip>/32, Port=8080 Source=<your-ip>/32
>
> # Verify the Jenkins web UI is reachable — confirms Docker container + networking are functional
> # Prerequisites: Jenkins must be running (start with: ./lifecycle.sh start jenkins)
> # and your current IP must match the operator_ip in the SG (Security Group).
> curl -s -o /dev/null -w "HTTP %{http_code}\n" \
>     "http://$(cd terraform && terraform output -raw jenkins_public_ip):8080/login"
> # Expected: HTTP 200 (if SG allows your IP; HTTP 000 = connection refused / SG mismatch)
>
> # 🔗 Jenkins UI — shows all 3 pipelines (engine-ci, cli-ci, cd) and their build history
> # → Open: http://<JENKINS_IP>:8080
> # → What to show: Dashboard with 3 pipeline jobs, click each to see stage views and build logs
> ```

**IRSA (IAM Roles for Service Accounts) for EBS (Elastic Block Store) CSI (Container Storage Interface) Driver:**
The EBS CSI driver needs IAM (Identity and Access Management) permissions to create, attach, and delete EBS volumes. Rather than granting these permissions to the entire node role (overly broad), IRSA scopes them to just the `ebs-csi-controller-sa` Service Account in `kube-system`:
1. Terraform creates an OIDC (OpenID Connect) Provider from the EKS cluster's OIDC issuer
2. An IAM role (`seyoawe-ebs-csi-role`) trusts the OIDC provider with conditions scoped to `aud=sts.amazonaws.com` and `sub=system:serviceaccount:kube-system:ebs-csi-controller-sa`
3. The `AmazonEBSCSIDriverPolicy` managed policy is attached to this role
4. The EKS addon `aws-ebs-csi-driver` is configured with `service_account_role_arn` pointing to this role

> **Verify — IRSA (IAM Roles for Service Accounts) & EBS (Elastic Block Store) CSI (Container Storage Interface):**
> ```bash
> # Prove the OIDC (OpenID Connect) provider exists — this is the trust anchor that lets K8s pods assume IAM roles
> aws iam list-open-id-connect-providers --profile seyoawe-tf \
>     --query "OpenIDConnectProviderList[].Arn" --output table
> # Expected: 1 ARN (Amazon Resource Name) containing oidc.eks.us-east-1.amazonaws.com/id/<CLUSTER_ID>
>
> # Confirm the dedicated IAM (Identity and Access Management) role for EBS CSI exists with the correct ARN
> aws iam get-role --role-name seyoawe-ebs-csi-role \
>     --query "Role.{RoleName:RoleName, Arn:Arn}" --output table --profile seyoawe-tf
> # Expected:
> #   | arn:aws:iam::632008729195:role/seyoawe-ebs-csi-role | seyoawe-ebs-csi-role |
>
> # Verify the EBS CSI driver pods are healthy — controllers manage volume lifecycle, nodes mount volumes on workers
> kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver
> # Expected:
> #   ebs-csi-controller-...   6/6   Running   0   XXh   (2 replicas — manage create/attach/delete)
> #   ebs-csi-node-...         3/3   Running   0   XXh   (1 per worker — handles local mount/unmount)
>
> # Prove the K8s SA (Service Account) is annotated with the IAM role ARN — this is the IRSA link that grants permissions
> kubectl get sa ebs-csi-controller-sa -n kube-system -o yaml | grep role-arn
> # Expected: eks.amazonaws.com/role-arn: arn:aws:iam::632008729195:role/seyoawe-ebs-csi-role
> ```

#### Ansible Playbooks

Four playbooks handle post-provisioning configuration:

- **`configure-jenkins.yaml`** — 11 tasks: installs Docker (dnf), starts and enables Docker service (systemd), adds `ec2-user` to docker group, creates Jenkins home directory (`/var/jenkins_home`, UID 1000), runs Jenkins LTS (Long-Term Support) container (`docker run -d` with port 8080+50000, Docker socket bind-mount for Docker-in-Docker, `JAVA_OPTS=-Xmx2g`), waits for port 8080, downloads kubectl binary, installs pip3 and awscli, copies the Docker CLI binary into the Jenkins container, and adds the jenkins user to the host's docker GID inside the container.
- **`configure-jenkins-tools.yaml`** — 6 tasks: downloads the shellcheck binary (stable release), extracts and installs to `/usr/local/bin`, copies shellcheck into the Jenkins container, installs yamllint via pip3, and verifies both tools' versions. These tools are required by the CI lint stages.
- **`configure-eks.yaml`** — 5 tasks: runs `aws eks update-kubeconfig` for the `seyoawe-cluster`, waits for the cluster API to become reachable (retries 10 times, 15s delay), verifies worker nodes are in Ready state, and idempotently creates the `seyoawe` and `monitoring` namespaces.
- **`install-tools.yaml`** — 6 tasks: checks and prints versions of terraform, kubectl, helm, aws-cli, and ansible. Used for verification and documentation purposes.

> **Verify — Ansible / Jenkins Configuration:**
> ```bash
> # SSH into Jenkins EC2 and confirm the Jenkins Docker container is running with correct port bindings
> JENKINS_IP=$(cd terraform && terraform output -raw jenkins_public_ip)
> ssh ec2-user@${JENKINS_IP} -i ~/keys/devops-key-private-account.pem \
>     "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
> # Expected:
> #   NAMES     STATUS          PORTS
> #   jenkins   Up X days       0.0.0.0:8080->8080/tcp, 0.0.0.0:50000->50000/tcp
>
> # Verify lint tools (shellcheck + yamllint) are installed inside the Jenkins container — required for CI stages
> ssh ec2-user@${JENKINS_IP} -i ~/keys/devops-key-private-account.pem \
>     "docker exec jenkins bash -c 'shellcheck --version | head -2 && yamllint --version'"
> # Expected: shellcheck version: 0.x.x, yamllint 1.x.x
>
> # Confirm kubectl can reach the EKS control plane — proves the kubeconfig was configured by Ansible
> kubectl cluster-info
> # Expected: Kubernetes control plane is running at https://<eks-endpoint>
>
> # Show the two project namespaces created by the configure-eks playbook
> kubectl get namespaces --selector=project=seyoawe
> # Expected: seyoawe (Active), monitoring (Active)
>
> # Run the Ansible tool-verification playbook to confirm all tools are at expected versions
> ansible-playbook ansible/playbooks/install-tools.yaml -i ansible/inventory.ini
> # Expected: Terraform v1.14.0, kubectl v1.34.1, Helm v3.17.0, etc.
> ```

#### CD (Continuous Delivery) Pipeline — `Jenkinsfile.cd`

The pipeline has 10 stages with a deliberate human approval gate:

```
Checkout → Read VERSION → Terraform Init → Terraform Plan → ⏸ Manual Approval
→ Terraform Apply → Ansible Configure EKS → kubectl Apply → kubectl Update Image
→ kubectl Rollout Verify → Git Tag (deploy-v0.1.1)
```

**Manual Approval Gate** (`input` step) — The pipeline pauses after `terraform plan` and presents the plan output to the operator. The operator must click "Apply" to proceed. This is a critical safety mechanism that prevents unreviewed infrastructure changes. The `input` stage uses the message: `"Review the Terraform plan above. Approve to apply infrastructure changes?"`.

After applying infrastructure, the pipeline runs `ansible-playbook configure-eks.yaml` to update kubeconfig, then applies the K8s manifests (`kubectl apply -f k8s/namespace.yaml` + `kubectl apply -f k8s/engine/`), updates the container image to the current VERSION, and verifies the rollout with `kubectl rollout status statefulset/seyoawe-engine --timeout=300s`. Finally, it creates and pushes a `deploy-v{VERSION}` git tag.

> **Verify — CD Pipeline & Deployment:**
> ```bash
> # 🔗 Open the Jenkins CD pipeline page — shows the stage view with Manual Approval Gate
> JENKINS_IP=$(cd terraform && terraform output -raw jenkins_public_ip)
> open http://${JENKINS_IP}:8080/job/cd/
> # → What to show: Pipeline stage view with colored boxes for each stage
> # → Click into a completed build → show the "Review the Terraform plan" approval prompt
> # → Show all stages green (Checkout → VERSION → TF Init → TF Plan → Approval → Apply → ...)
>
> # Confirm the deploy git tag exists — only created after a successful CD pipeline run
> git tag -l "deploy-*"
> # Expected: deploy-v0.1.1  (if CD pipeline has run; empty otherwise)
>
> # Verify the StatefulSet rollout completed — proves the CD pipeline successfully deployed the new image
> kubectl rollout status statefulset/seyoawe-engine -n seyoawe
> # Expected: partitioned roll out complete: 1 new pods have been updated...
>
> # Confirm the running container image matches the VERSION file — proves the CD pipeline set the correct tag
> kubectl get sts seyoawe-engine -n seyoawe -o jsonpath='{.spec.template.spec.containers[0].image}'
> echo
> # Expected: danielmazh/seyoawe-engine:0.1.1
> ```

#### lifecycle.sh — Resource Lifecycle Manager

A 387-line Bash script that serves as the single entry point for managing all cloud resources:

- **Resource Registry** — A structured comment block at the top of the file listing every cloud resource: 21 Terraform-managed resources (VPC, 4 subnets, IGW, NAT GW, EIP, EKS cluster, node group, 2 Jenkins resources, 6 IAM roles/policies, OIDC provider, 4 EKS addons, 2 route tables), 4 Helm/kubectl-managed resources (monitoring release, PVC, 2 namespaces, StatefulSet), and 2 bootstrap resources (S3 bucket, IAM user). Every new resource must be registered here — an unregistered resource is a billing risk.
- `status` — Queries 5 resource states (EKS cluster, node group desired count, Jenkins EC2 state, Helm release, S3 bucket existence) and prints an hourly cost estimate (~$0.27/hr total).
- `stop jenkins` / `stop eks-nodes` / `stop monitoring` / `stop nat` — Stops individual components to halt billing. Jenkins EC2 is stopped via `aws ec2 stop-instances`. EKS nodes are scaled to 0 via `aws eks update-nodegroup-config --scaling-config minSize=0,maxSize=0,desiredSize=0`.
- `start jenkins` / `start eks-nodes` / `start monitoring` / `start nat` — Resumes components. Jenkins start includes `aws ec2 wait instance-running` and reports the new public IP.
- `destroy` — 5-step ordered teardown: (1) Helm uninstall monitoring, (2) delete K8s namespaces (triggers PVC/LB cleanup), (3) wait 15s for AWS resource cleanup, (4) `terraform destroy -auto-approve`, (5) skip bootstrap resources.
- `destroy --all` — Same 5 steps, plus deletes the S3 state bucket (`aws s3 rb --force`) and the `terraform-deployer` IAM user with all access keys. Achieves **zero residual footprint**.

> **Verify — lifecycle.sh:**
> ```bash
> # Run the status command — queries 5 AWS resource states and prints the hourly cost estimate for the entire stack
> ./lifecycle.sh status
> # Expected:
> #   EKS Cluster:         ACTIVE
> #   EKS Node Group:      desired=2
> #   Jenkins EC2:         running
> #   Monitoring Helm:     deployed
> #   TF State Bucket:     exists (seyoawe-tf-state-632008729195)
> #
> #   Estimated hourly cost while all resources are running:
> #     EKS control plane:  ~$0.10/hr
> #     2x t3.medium nodes: ~$0.08/hr
> #     1x t3.medium Jenkins: ~$0.04/hr
> #     NAT Gateway:        ~$0.05/hr
> #     Total:              ~$0.27/hr (~$6.50/day)
> ```

### Relevant Files & Structure

- **`terraform/backend.tf`** — 23 lines. S3 backend configuration: bucket `seyoawe-tf-state-632008729195`, key `dev/terraform.tfstate`, region `us-east-1`, `encrypt = true`, `use_lockfile = true` (Terraform ≥ 1.14 — no DynamoDB), profile `seyoawe-tf`. Required providers: `hashicorp/aws ~> 5.90`, `hashicorp/tls ~> 4.0`.
- **`terraform/variables.tf`** — 40 lines, 7 variables: `aws_region` (default `us-east-1`), `cluster_name` (default `seyoawe-cluster`), `node_instance_type` (default `t3.medium`), `node_desired_count` (default `2`), `jenkins_instance_type` (default `t3.medium`), `jenkins_key_pair` (required, no default), `operator_ip` (required, CIDR notation e.g. `1.2.3.4/32`).
- **`terraform/main.tf`** — 412 lines containing all infrastructure resources: AWS provider config, data sources (availability zones, Amazon Linux 2023 AMI), local tags (`Project=seyoawe`, `Environment=poc`, `ManagedBy=terraform`), VPC (`10.0.0.0/16`, DNS hostnames enabled), 4 Subnets (2 public with `map_public_ip_on_launch=true` and K8s ELB tags, 2 private with internal-ELB tags), Internet Gateway, NAT Gateway + Elastic IP in public-a, 2 Route Tables (public → IGW, private → NAT) with 4 associations, IAM Cluster Role (EKS assume-role policy) + `AmazonEKSClusterPolicy`, IAM Node Role (EC2 assume-role policy) + `AmazonEKSWorkerNodePolicy` + `AmazonEKS_CNI_Policy` + `AmazonEC2ContainerRegistryReadOnly`, EKS Cluster (v1.32, all 4 subnets, dual endpoint access, `API_AND_CONFIG_MAP` auth), EKS Node Group (2× t3.medium, AL2023, private subnets only, scaling 2/2/3, max_unavailable=1), TLS certificate data source + OIDC Provider, IRSA EBS CSI Role (federated trust policy with aud+sub conditions) + `AmazonEBSCSIDriverPolicy`, 4 EKS Addons (vpc-cni, kube-proxy, coredns, aws-ebs-csi-driver with service_account_role_arn), Jenkins Security Group (ingress 8080+22 from operator_ip, full egress), Jenkins EC2 Instance (Amazon Linux 2023, public subnet, 30GB gp3 encrypted root).
- **`terraform/outputs.tf`** — 35 lines, 7 outputs: `cluster_name`, `cluster_endpoint`, `kubeconfig_command` (ready-to-run aws eks update-kubeconfig command), `jenkins_public_ip`, `jenkins_ui_url` (http://<ip>:8080), `vpc_id`, `ebs_csi_role_arn`.
- **`ansible/inventory.ini`** — 14 lines with 2 groups: `[local]` (localhost with `ansible_connection=local`) and `[jenkins]` (commented template — IP is populated dynamically from `terraform output -raw jenkins_public_ip`).
- **`ansible/playbooks/configure-jenkins.yaml`** — 122 lines, 11 tasks: Install Docker (dnf), Start Docker service (systemd, enabled), Add ec2-user to docker group, Create Jenkins home directory (/var/jenkins_home, owner UID 1000, mode 0755), Start Jenkins container (docker run -d, --restart unless-stopped, -p 8080:8080 -p 50000:50000, -v jenkins_home, -v /var/run/docker.sock, -e JAVA_OPTS=-Xmx2g, jenkins/jenkins:lts), Wait for port 8080 (timeout 120s), Download kubectl binary (v1.34.1), Install pip3 (dnf), Install awscli (pip3), Copy Docker CLI binary into container (docker cp), Add jenkins user to docker GID inside container (matching host socket GID).
- **`ansible/playbooks/configure-eks.yaml`** — 61 lines, 5 tasks: Update kubeconfig (aws eks update-kubeconfig), Print result, Wait for cluster API (kubectl cluster-info, retries=10, delay=15), Verify worker nodes Ready (kubectl get nodes -o wide), Create project namespaces (kubectl create namespace --dry-run=client -o yaml | kubectl apply -f -, loop over [seyoawe, monitoring]).
- **`ansible/playbooks/configure-jenkins-tools.yaml`** — 60 lines, 6 tasks: Download shellcheck tarball, Extract, Install to /usr/local/bin on host, Copy shellcheck into Jenkins container (docker cp), Install yamllint (pip3), Verify both versions.
- **`ansible/playbooks/install-tools.yaml`** — 43 lines, 6 tasks: Check terraform/kubectl/helm/aws/ansible versions via `command`, Print all versions in a formatted debug message.
- **`jenkins/Jenkinsfile.cd`** — 164 lines, 10 stages. Environment block: `AWS_PROFILE=seyoawe-tf`, `AWS_REGION=us-east-1`, `CLUSTER_NAME=seyoawe-cluster`, `NAMESPACE=seyoawe`, `TF_DIR=terraform`. Stages: Checkout (checkout scm), Read VERSION (cat VERSION, trim), Terraform Init (with aws-credentials, -input=false), Terraform Plan (-out=tfplan -input=false), Approval (input message "Review the Terraform plan above. Approve to apply infrastructure changes?", ok="Apply"), Terraform Apply (-auto-approve tfplan), Ansible Configure (ansible-playbook configure-eks.yaml), K8s Deploy (kubectl apply namespace.yaml + engine/), K8s Update Image (kubectl set image or rollout restart), K8s Verify Rollout (kubectl rollout status --timeout=300s + kubectl get pods), Git Tag (deploy-v{VERSION}, push to GitHub).
- **`lifecycle.sh`** — 387 lines. Resource Registry header (21 Terraform resources, 4 Helm/kubectl resources, 2 bootstrap resources). Configuration: cluster name, nodegroup name, Jenkins tag, desired/min/max node counts. Helper functions: jenkins_instance_id, jenkins_state, eks_nodegroup_desired, eks_cluster_status, helm_release_exists, s3_bucket_name, confirm prompt. Commands: cmd_status (5 AWS queries + cost breakdown), cmd_stop (4 components: jenkins/eks-nodes/monitoring/nat), cmd_start (4 components with wait and IP reporting), cmd_destroy (5-step ordered teardown with --all flag for zero footprint).

### Live Demo & Commands

```bash
# 1. Run the lifecycle status command — single view of all 5 cloud resource states and total hourly cost
./lifecycle.sh status
# Expected output:
#   EKS Cluster:         ACTIVE
#   EKS Node Group:      desired=2
#   Jenkins EC2:         running
#   Monitoring Helm:     deployed
#   TF State Bucket:     exists (seyoawe-tf-state-632008729195)
#   Total:              ~$0.27/hr (~$6.50/day)

# 2. Show every Terraform-managed resource — proves the entire AWS stack is codified as IaC
cd terraform
terraform state list
# Expected output (31 resources):
#   data.aws_ami.amazon_linux_2023
#   data.aws_availability_zones.available
#   data.aws_iam_policy_document.eks_cluster_assume_role
#   data.aws_iam_policy_document.eks_node_assume_role
#   aws_eip.nat
#   aws_eks_addon.coredns / .kube_proxy / .vpc_cni
#   aws_eks_cluster.main
#   aws_eks_node_group.main
#   aws_iam_role.eks_cluster / .eks_node
#   aws_iam_role_policy_attachment.eks_cluster_policy / .eks_cni_policy / ...
#   aws_instance.jenkins
#   aws_internet_gateway.main / aws_nat_gateway.main
#   aws_route_table.private / .public + 4 associations
#   aws_security_group.jenkins
#   aws_subnet.private_a / .private_b / .public_a / .public_b
#   aws_vpc.main

# 3. 🔗 Open Jenkins UI — browse all 3 pipelines and show the CD Manual Approval Gate
open http://$(terraform output -raw jenkins_public_ip):8080
# → What to show: Dashboard → click "cd" job → Stage View → the ⏸ Approval step
# → Click into a completed build and show the "Review the Terraform plan" prompt

# 4. Demonstrate cost-saving suspend/resume — critical for PoC budget management
./lifecycle.sh stop jenkins
# Expected output: "[ok] Jenkins EC2 stop initiated. Billing for compute stops within minutes."

./lifecycle.sh start jenkins
# Expected output: "[ok] Jenkins EC2 running. UI: http://<NEW_IP>:8080"
```

---

## Slide 4 — Phase 3: Containerization & Testing

### Project Requirement

> Task 2 — Dockerize the App (10 pts) + Task 3 — Testing (10 pts)

### Technical Deep-Dive

#### Engine Dockerfile

The Engine is a **compiled Go binary** (`seyoawe.linux`) that internally runs a Flask server and loads Python-based modules. The Dockerfile is based on `python:3.11-slim` because the binary needs a Python runtime for its module system (Flask, requests, jinja2, gitpython):

- **Binary Guard** — `RUN test -f seyoawe.linux || (echo "ERROR..." && exit 1)` — Validates the binary exists at **build time**. If missing, it prints a highly visible ASCII-boxed error message with download instructions and fails immediately, preventing a broken image from being built. This is critical because the binary is not stored in Git (too large) and must be manually placed before building.
- **Symlink trick** — `cd modules && ln -sf . modules` — The engine's module loader expects `modules/modules/<name>/`, but the actual layout is `modules/<name>/`. Creating a self-referencing symlink (`modules/modules → modules/`) satisfies this expectation without duplicating the directory tree.
- **HEALTHCHECK** — `curl -s http://localhost:8080/ > /dev/null || exit 1` — The engine has **no dedicated `/health` endpoint**. Using `curl` without the `-f` flag returns exit code 0 for any HTTP response (including 404, 405), and returns non-zero only when the TCP connection itself fails (i.e., Flask is not accepting requests at all). This reliably detects whether the server is up. Configured with `--interval=30s --timeout=5s --start-period=30s --retries=3`.
- **Ports** — `EXPOSE 8080 8081` — 8080 for the main API, 8081 for the Module Dispatcher.
- **Runtime directories** — `mkdir -p lifetimes logs` — In Kubernetes, these are mounted to a PVC (PersistentVolumeClaim) at `/app/data`. Locally, they exist as ephemeral container directories.
- **Environment** — `ENV GIT_PYTHON_REFRESH=quiet` — Suppresses a startup warning from gitpython (bundled by the engine); the git CLI is installed via `apt-get`.

#### CLI Dockerfile

The CLI (`sawectl.py`) is a pure Python script with three commands: `validate-workflow`, `validate-module`, `list-modules`:

- **Version Injection** — `RUN sed -i "s/^VERSION = \"[^\"]*\"/VERSION = \"${VERSION}\"/" sawectl.py` — At build time, the `VERSION` build arg (passed from Jenkins via `--build-arg VERSION=${APP_VERSION}`) replaces the hardcoded `VERSION` constant in the Python source code. This ensures that `sawectl.py --help` displays the correct version without maintaining it in two places.
- **Layer optimization** — `COPY cli/requirements.txt .` is done before `COPY cli/ .`, so the `pip install` layer is cached and only rebuilds when dependencies change (not when source code changes).

#### Unit Tests — pytest

**13 tests across 5 test classes**, all completing in **under 2 seconds**:

| Class | Tests | What is validated |
|-------|-------|-------------------|
| `TestLoadYaml` | 3 | YAML loading: valid file returns dict, invalid YAML raises SystemExit, empty file raises SystemExit |
| `TestSchemaValidation` | 3 | `dsl.schema.json` exists and is valid JSON with `properties` or `$defs`, `module.schema.json` exists and is valid JSON, first sample workflow loads without error |
| `TestVersion` | 3 | `sawectl.VERSION` constant exists, VERSION is valid semver (X.Y.Z with all-numeric parts), `VERSION` file exists at repo root with valid semver content |
| `TestCLISubprocess` | 2 | `sawectl.py --help` exits with code 0 and stdout contains "sawectl", `validate-workflow` on first sample workflow exits 0 and stdout contains "PASSED" |
| `TestModuleManifest` | 2 | `load_module_manifest("slack_module")` returns dict with "name" key, `load_module_manifest("does_not_exist")` returns None |

The `conftest.py` adds `cli/` to `sys.path` so tests can `import sawectl` directly, and defines shared path constants (`REPO_ROOT`, `SCHEMAS_DIR`, `SAMPLES_DIR`, `MODULES_DIR`, `VERSION_FILE`) available to all test modules.

### Relevant Files & Structure

- **`docker/engine/Dockerfile`** — 51 lines. Base image: `python:3.11-slim`. `ARG VERSION=dev` for build-time version label. `apt-get install curl git` (curl for HEALTHCHECK, git for gitpython). `pip install requests pyyaml jinja2 gitpython` (module dependencies). `COPY engine/ .` (full engine tree). Symlink: `cd modules && ln -sf . modules`. Binary guard: `test -f seyoawe.linux || (echo "ERROR" && exit 1)`. `chmod +x seyoawe.linux run.sh`. `mkdir -p lifetimes logs`. `EXPOSE 8080 8081`. HEALTHCHECK: `curl -s http://localhost:8080/ > /dev/null || exit 1` with 30s interval, 5s timeout, 30s start period, 3 retries. `ENV GIT_PYTHON_REFRESH=quiet`. `ENTRYPOINT ["./seyoawe.linux"]`.
- **`docker/cli/Dockerfile`** — 21 lines. Base image: `python:3.11-slim`. `ARG VERSION=dev`. `COPY cli/requirements.txt .` → `pip install --no-cache-dir -r requirements.txt` (cached layer). `COPY cli/ .` (source code). Version injection: `sed -i "s/^VERSION = \"[^\"]*\"/VERSION = \"${VERSION}\"/" sawectl.py`. `ENTRYPOINT ["python", "sawectl.py"]`.
- **`cli/tests/test_sawectl.py`** — 138 lines, 13 tests across 5 classes. Imports: `json, subprocess, sys, Path, pytest, yaml, sawectl`. Path constants resolved relative to `__file__`: `CLI_DIR`, `REPO_ROOT`, `SCHEMAS_DIR`, `SAMPLES_DIR` (engine/workflows/samples/), `MODULES_DIR` (engine/modules/), `VERSION_FILE`. TestLoadYaml uses `tmp_path` fixture for isolated file creation. TestCLISubprocess uses `subprocess.run` with `capture_output=True`. TestModuleManifest tests the `sawectl.load_module_manifest()` function directly.
- **`cli/tests/conftest.py`** — 14 lines. Inserts `cli/` directory into `sys.path` at index 0 so `import sawectl` works. Exports shared path constants: `REPO_ROOT`, `SCHEMAS_DIR`, `SAMPLES_DIR`, `MODULES_DIR`, `VERSION_FILE`.
- **`cli/requirements.txt`** — Python dependencies: `pyyaml` (YAML parsing), `jsonschema` (schema validation), `requests` (HTTP client for engine communication).
- **`cli/sawectl.py`** — The CLI entrypoint: `VERSION` constant, `load_yaml()` function, `load_module_manifest()` function, argparse-based CLI with subcommands `validate-workflow`, `validate-module`, `list-modules`.
- **`cli/dsl.schema.json`** — JSON Schema for validating workflow YAML files (checks required fields, step structure, trigger types).
- **`cli/module.schema.json`** — JSON Schema for validating module manifest files (checks module name, version, entrypoint).
- **`.flake8`** — Python linting configuration for flake8 (used by CLI CI pipeline).
- **`.dockerignore`** — Prevents `.venv`, `.git`, `terraform/`, `.aws-project/`, `__pycache__` from being copied into the Docker build context, reducing image size and build time.

### Live Demo & Commands

```bash
# 1. Execute all 13 unit tests — proves the CLI is fully functional and all validation logic works correctly
pytest cli/tests/ -v
# Expected output:
#   cli/tests/test_sawectl.py::TestLoadYaml::test_valid_yaml_returns_dict PASSED
#   cli/tests/test_sawectl.py::TestLoadYaml::test_invalid_yaml_exits PASSED
#   cli/tests/test_sawectl.py::TestLoadYaml::test_empty_yaml_exits PASSED
#   cli/tests/test_sawectl.py::TestSchemaValidation::test_dsl_schema_file_exists_and_is_valid_json PASSED
#   cli/tests/test_sawectl.py::TestSchemaValidation::test_module_schema_file_exists_and_is_valid_json PASSED
#   cli/tests/test_sawectl.py::TestSchemaValidation::test_sample_workflow_loads_without_error PASSED
#   cli/tests/test_sawectl.py::TestVersion::test_version_constant_exists PASSED
#   cli/tests/test_sawectl.py::TestVersion::test_version_constant_is_semver PASSED
#   cli/tests/test_sawectl.py::TestVersion::test_version_file_exists PASSED
#   cli/tests/test_sawectl.py::TestCLISubprocess::test_help_exits_zero PASSED
#   cli/tests/test_sawectl.py::TestCLISubprocess::test_validate_workflow_on_sample PASSED
#   cli/tests/test_sawectl.py::TestModuleManifest::test_load_existing_module_manifest PASSED
#   cli/tests/test_sawectl.py::TestModuleManifest::test_load_nonexistent_module_returns_none PASSED
#   ========================= 13 passed in 1.XX s =========================

# 2. Build the Engine Docker image — includes binary guard, symlink trick, and HEALTHCHECK
docker build -f docker/engine/Dockerfile \
    -t seyoawe-engine:0.1.1 \
    --build-arg VERSION=0.1.1 .

# 3. Build the CLI Docker image — uses sed to inject the version into the Python source at build time
docker build -f docker/cli/Dockerfile \
    -t seyoawe-cli:0.1.1 \
    --build-arg VERSION=0.1.1 .

# 4. Verify the CLI reports the correct injected version — proves the sed VERSION injection worked
docker run seyoawe-cli:0.1.1 --help
# Expected output: "sawectl v0.1.1 — SeyoAWE CLI tool"
#                  "usage: sawectl.py [-h] {validate-workflow,validate-module,list-modules} ..."

# 5. Run the Engine container and wait for Docker HEALTHCHECK to pass — proves the Flask server is accepting connections
docker run -d --name engine-test -p 8080:8080 seyoawe-engine:0.1.1
sleep 10
docker inspect --format='{{.State.Health.Status}}' engine-test
# Expected output: healthy
docker rm -f engine-test
```

---

## Slide 5 — Phase 4: CI (Continuous Integration) Pipelines & Version Coupling

### Project Requirement

> Task 4 — CI Pipeline (15 pts) + Smart Version Coupling (10 pts) + Git Tagging (15 pts)

### Technical Deep-Dive

#### Change Detection — Smart Version Coupling

Both CI pipelines implement **intelligent change detection** directly in Groovy, using Jenkins' built-in `GIT_PREVIOUS_SUCCESSFUL_COMMIT` environment variable:

```groovy
def baseRef = env.GIT_PREVIOUS_SUCCESSFUL_COMMIT ?: 'HEAD~5'
def changed = sh(script: "git diff ${baseRef} HEAD --name-only", returnStdout: true)

env.BUILD_ENGINE = (
    changed.contains('VERSION') ||
    changed.split('\n').any { f ->
        f.startsWith('engine/') || f.startsWith('docker/engine/')
    }
) ? 'true' : 'false'
```

**The logic in detail:**
1. `GIT_PREVIOUS_SUCCESSFUL_COMMIT` — Jenkins automatically provides the SHA of the last commit that resulted in a successful build. The diff is computed against this reference, covering all commits since the last green build (not just the latest commit).
2. **Fallback:** `HEAD~5` — On the very first build (or after a history reset), this variable is null. The fallback ensures the pipeline still has a reasonable set of files to examine.
3. **`VERSION` change → both pipelines run** — If the `VERSION` file appears in the changed file list, both `BUILD_ENGINE` and `BUILD_CLI` are set to `true`. This is the core of version coupling: bumping the version guarantees both images are rebuilt and tagged with the same version.
4. **Engine-only changes** — Files under `engine/` or `docker/engine/` set only `BUILD_ENGINE=true`.
5. **CLI-only changes** — Files under `cli/` or `docker/cli/` set only `BUILD_CLI=true`.

**`when` conditions:** Every build/push/tag stage uses `when { environment name: 'BUILD_ENGINE', value: 'true' }`. When no relevant changes are detected, all stages are skipped and Jenkins prints "No engine changes detected — build stages were skipped." in the post block. The pipeline still succeeds (green) — it just does nothing.

#### Engine CI Pipeline — `Jenkinsfile.engine`

8 stages with conditional execution:

```
Checkout → Read VERSION → Change Detection → Lint (yamllint + shellcheck)
→ Prepare Binary → Docker Build → Docker Push → Git Tag (engine-v0.1.1)
```

- **Lint:** `yamllint -d relaxed engine/configuration/config.yaml` validates the engine's YAML configuration. `shellcheck engine/run.sh` validates the shell launcher script. Both tools are installed on the Jenkins host via Ansible.
- **Prepare Binary:** Copies `seyoawe.linux` from `/var/jenkins_home/seyoawe.linux` (pre-placed on the Jenkins host once) into the workspace. This avoids storing the 30MB+ Go binary in Git while ensuring the Docker build always has access to it.
- **Docker Build:** Builds with the `-f docker/engine/Dockerfile` flag (Dockerfile is separate from the engine source), creates two tags: `danielmazh/seyoawe-engine:0.1.1` (version-pinned) and `danielmazh/seyoawe-engine:latest` (mutable). The `--build-arg VERSION=${APP_VERSION}` passes the version for OCI (Open Container Initiative) image labels.
- **Docker Push:** Logs into DockerHub via `dockerhub-creds` credential (usernamePassword type), pushes both tags, then explicitly logs out.
- **Git Tag:** Creates an annotated tag `engine-v0.1.1` with message "Engine CI build v0.1.1" and pushes it to GitHub using the `github-token` credential. Uses `|| true` to gracefully handle the case where the tag already exists (idempotent).
- **Cleanup:** `post.always` removes the local Docker images (`docker rmi`) to free disk space on the Jenkins host. If `BUILD_ENGINE=false`, prints the skip message.

#### CLI CI Pipeline — `Jenkinsfile.cli`

8 stages, same change detection pattern:

```
Checkout → Read VERSION → Change Detection → Lint (flake8)
→ Unit Tests (13 pytest) → Docker Build → Docker Push → Git Tag (cli-v0.1.1)
```

- **Lint:** `flake8 cli/` — Runs the Python linter on the entire CLI directory using settings from `.flake8`.
- **Unit Tests:** `pytest cli/tests/ -v --junitxml=test-results-cli.xml` — Runs all 13 tests in verbose mode and outputs JUnit XML for Jenkins' test result visualization. The `post.always` block uses `junit allowEmptyResults: true, testResults: 'test-results-cli.xml'` to publish results to the Jenkins Test Report tab.
- **Docker Build:** Dual-tag `danielmazh/seyoawe-cli:0.1.1` + `danielmazh/seyoawe-cli:latest`. The `--build-arg VERSION=${APP_VERSION}` is used by the `sed` version injection inside the Dockerfile.
- **Git Tag:** `cli-v0.1.1` — Same pattern as Engine CI.

#### Supporting Scripts

- **`scripts/change-detect.sh`** — 57-line standalone script that can be sourced (`source scripts/change-detect.sh`) or executed. Uses `git diff HEAD~1 --name-only` to classify changes. If `VERSION` is in the changeset, both `BUILD_ENGINE` and `BUILD_CLI` are set to `true`. Otherwise, engine paths (`^engine/`, `^docker/engine/`) set `BUILD_ENGINE=true`, and CLI paths (`^cli/`, `^docker/cli/`) set `BUILD_CLI=true`. Exports both variables for downstream use.
- **`scripts/version.sh`** — 24-line script that reads the `VERSION` file, validates it is non-empty, trims whitespace, and exports `APP_VERSION`. Used by any automation that needs the current version.

### Relevant Files & Structure

- **`jenkins/Jenkinsfile.engine`** — 155 lines, 8 stages. Environment block: `BINARY_SRC=/var/jenkins_home/seyoawe.linux`. Credentials used: `dockerhub-creds` (usernamePassword for DockerHub login/push), `github-token` (string for git tag push). Change Detection stage: inline Groovy comparing against `GIT_PREVIOUS_SUCCESSFUL_COMMIT`, sets `BUILD_ENGINE=true|false`. Lint stage: `yamllint -d relaxed` on config.yaml + `shellcheck` on run.sh. Prepare Binary stage: `cp ${BINARY_SRC} engine/seyoawe.linux && chmod +x`. Docker Build stage: `-f docker/engine/Dockerfile`, dual-tag with `${DH_USER}/seyoawe-engine:${APP_VERSION}` and `:latest`, `--build-arg VERSION`. Docker Push stage: `docker login --password-stdin` + push both tags + `docker logout`. Git Tag stage: `git tag -a "engine-v${APP_VERSION}" -m "..."` + push to GitHub remote. Post: `always` cleans up images, prints skip message if `BUILD_ENGINE=false`; `success` prints version; `failure` prints error.
- **`jenkins/Jenkinsfile.cli`** — 143 lines, 8 stages. Same pattern as Engine but: Change Detection sets `BUILD_CLI` flag. Lint stage: `flake8 cli/`. Unit Tests stage: `pytest cli/tests/ -v --junitxml=test-results-cli.xml` with `junit` post-step for Jenkins test reporting. Docker Build: `-f docker/cli/Dockerfile`, dual-tag `seyoawe-cli:${APP_VERSION}` + `:latest`. Git Tag: `cli-v${APP_VERSION}`.
- **`scripts/change-detect.sh`** — 57 lines. Detects changes via `git diff HEAD~1 --name-only` (fallback: `git diff-tree` for first commit). VERSION change → both flags true. Engine paths: `^(engine/|docker/engine/|engine/configuration/)`. CLI paths: `^(cli/|docker/cli/)`. Prints detected files with `sed 's/^/  /'`. Exports: `BUILD_ENGINE`, `BUILD_CLI`.
- **`scripts/version.sh`** — 24 lines. Resolves `VERSION` file path relative to script location. Reads and trims the version. Validates non-empty. Exports `APP_VERSION`. Prints `[version.sh] APP_VERSION=0.1.1`.

### Live Demo & Commands

```bash
# 1. 🔗 Open Jenkins UI — show both CI pipelines with their build history and stage views
# → http://<JENKINS_IP>:8080
# → What to show:
#   - Pipeline "engine-ci" — Build #14 (green/passing) → click into Console Output
#   - Pipeline "cli-ci" — Build #13 (green/passing) → click into Console Output
#   - Point out in the logs: "BUILD_ENGINE=true" / "BUILD_CLI=true" (change detection worked)
#   - Point out: "13 passed" (pytest ran inside CLI pipeline)
#   - Point out: "engine-v0.1.1" / "cli-v0.1.1" (git tags were created and pushed)

# 2. Prove all 3 semantic git tags exist locally — created by Jenkins CI/CD pipelines and pushed to GitHub
git tag -l
# Expected output:
#   cli-v0.1.1
#   engine-v0.1.1
#   deploy-v0.1.1   ← only present after the CD pipeline has run

# 3. 🔗 Show Docker images on DockerHub — proves CI pushed the built images to the registry
# → Open: https://hub.docker.com/r/danielmazh/seyoawe-engine/tags
#   What to show: tags "0.1.1" and "latest" with their push dates and image sizes
# → Open: https://hub.docker.com/r/danielmazh/seyoawe-cli/tags
#   What to show: tags "0.1.1" and "latest" — proves both images were tagged identically

# 4. Run the change detection script — demonstrates how CI decides which components to rebuild
source scripts/change-detect.sh
echo "Engine: $BUILD_ENGINE  CLI: $BUILD_CLI"
# Output depends on files changed in the last commit:
#   If VERSION changed:   BUILD_ENGINE=true  BUILD_CLI=true
#   If engine/ changed:   BUILD_ENGINE=true  BUILD_CLI=false
#   If cli/ changed:      BUILD_ENGINE=false  BUILD_CLI=true
#   If neither changed:   BUILD_ENGINE=false  BUILD_CLI=false

# 5. Read the VERSION file via the version.sh script (must run with bash — uses BASH_SOURCE)
bash scripts/version.sh
# Expected output: [version.sh] APP_VERSION=0.1.1
```

---

## Slide 6 — Phase 5: K8s (Kubernetes) Deployment

### Project Requirement

> Task 5 (continued) — K8s Deployment (10 pts): Application deployed and running on EKS (Elastic Kubernetes Service)

### Technical Deep-Dive

#### Why StatefulSet instead of Deployment?

The engine persists state to disk — workflow execution lifetimes and log files. A standard **Deployment** would lose this data on pod reschedule because PVCs (PersistentVolumeClaims) are not automatically re-bound. A **StatefulSet** guarantees:
1. **Stable PVC binding** — The PVC `data-seyoawe-engine-0` is always re-attached to the same pod, even after deletion and recreation.
2. **Ordered pod identity** — The pod name `seyoawe-engine-0` is stable and predictable, providing a stable DNS (Domain Name System) name within the cluster (`seyoawe-engine-0.seyoawe-engine.seyoawe.svc.cluster.local`).
3. **Data persistence across restarts** — Pod restart, node failure, or voluntary eviction never loses the lifetime/log data stored on the PVC.

#### Health Probes — tcpSocket

The engine has **no dedicated `/health` HTTP route** — it is a Flask server that returns 404/405 on undefined paths. Using `httpGet` probes would cause constant error logs. Instead, **tcpSocket** probes check whether port 8080 is accepting TCP connections:

```yaml
livenessProbe:
  tcpSocket:
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 15
  failureThreshold: 3

readinessProbe:
  tcpSocket:
    port: 8080
  initialDelaySeconds: 15
  periodSeconds: 10
  failureThreshold: 3
```

A successful TCP handshake confirms that Flask is listening — sufficient for liveness and readiness checks. `initialDelaySeconds: 30` gives the engine time to start (the Go binary initializes, loads modules, and starts Flask). The readiness probe uses a shorter delay (15s) so the pod becomes Ready sooner once the port opens.

#### ConfigMap — subPath Mount

The engine configuration `config.yaml` is injected via a ConfigMap using the **subPath** mount technique:

```yaml
volumeMounts:
  - name: config-vol
    mountPath: /app/configuration/config.yaml
    subPath: config.yaml
```

**Why subPath?** Without `subPath`, mounting a ConfigMap to `/app/configuration/` would **replace the entire directory** with only the ConfigMap data, deleting any other files that exist there. With `subPath`, only the single file `config.yaml` is replaced — other directory contents remain intact.

The ConfigMap (`seyoawe-config`) contains the full engine configuration: logging level (INFO for production, DEBUG for development), directory paths (lifetimes/logs redirected to `/app/data/` to leverage the PVC), app settings (port 8080, community customer_id), module dispatcher settings (port 8081, md5_strict: false, modules repo URL), and module defaults for chatbot (OpenAI GPT-4), API (timeout 15s), email (SMTP Gmail), Slack (webhook), and Git (GitHub token).

#### volumeClaimTemplates

```yaml
volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ReadWriteOnce]
      storageClassName: gp2
      resources:
        requests:
          storage: 2Gi
```

The StatefulSet's `volumeClaimTemplates` automatically creates a PVC per pod: `data-seyoawe-engine-0`. This PVC provisions a 2Gi `gp2` EBS (Elastic Block Store) volume (AWS General Purpose SSD) via the EBS CSI (Container Storage Interface) Driver. The volume is mounted to `/app/data` inside the container, where the engine stores:
- `lifetimes/` — Workflow execution state files (persistent across restarts)
- `logs/` — Application log files

**EBS CSI Driver provisioning chain:** Terraform creates the OIDC (OpenID Connect) Provider → creates the IRSA (IAM Roles for Service Accounts) role (`seyoawe-ebs-csi-role`) with `AssumeRoleWithWebIdentity` trust scoped to `kube-system:ebs-csi-controller-sa` → attaches `AmazonEBSCSIDriverPolicy` → installs the `aws-ebs-csi-driver` EKS addon with the role ARN (Amazon Resource Name). When the StatefulSet creates a PVC with `storageClassName: gp2`, the CSI controller uses IRSA to call the EC2 API and provision the EBS volume.

#### Service

A ClusterIP Service (no external exposure) with two named ports:
- `http` (8080 → 8080) — Main API endpoint for workflow execution
- `dispatcher` (8081 → 8081) — Module Dispatcher endpoint for module polling

### Relevant Files & Structure

- **`k8s/namespace.yaml`** — 14 lines. Two Namespace resources in a single file (separated by `---`): `seyoawe` and `monitoring`. Both labeled with `project: seyoawe`.
- **`k8s/engine/statefulset.yaml`** — 82 lines. StatefulSet `seyoawe-engine` in namespace `seyoawe`. `replicas: 1`, `serviceName: seyoawe-engine`. Container: `danielmazh/seyoawe-engine:0.1.1` with `imagePullPolicy: Always`. Two ports: `http` (8080/TCP) and `dispatcher` (8081/TCP). livenessProbe: `tcpSocket` port 8080, initialDelaySeconds=30, periodSeconds=15, failureThreshold=3. readinessProbe: `tcpSocket` port 8080, initialDelaySeconds=15, periodSeconds=10, failureThreshold=3. Resources: requests 100m CPU / 256Mi memory, limits 500m CPU / 512Mi memory. Two volumeMounts: `config-vol` at `/app/configuration/config.yaml` with `subPath: config.yaml`, `data` at `/app/data`. Volumes: `config-vol` from ConfigMap `seyoawe-config`. volumeClaimTemplates: `data` — 2Gi, `gp2` storageClass, `ReadWriteOnce` access mode.
- **`k8s/engine/service.yaml`** — 22 lines. ClusterIP Service `seyoawe-engine` in namespace `seyoawe`. Selector: `app: seyoawe-engine`. Two ports: `http` (8080→8080/TCP) and `dispatcher` (8081→8081/TCP). Labels: `app: seyoawe-engine`, `project: seyoawe`.
- **`k8s/engine/configmap.yaml`** — 68 lines. ConfigMap `seyoawe-config` in namespace `seyoawe`. Single data key: `config.yaml` (multi-line string). Content: `logging` block (level INFO, custom format string), `directories` block (workdir `.`, modules `./modules`, workflows `./workflows`, lifetimes `./data/lifetimes`, logs `./data/logs`), `app` block (port 8080, customer_id `community`, poll_for_modules_on_startup false, ignored_workflow_dirs [samples, deprecated], base_url `http://seyoawe-engine:8080`), `module_dispatcher` block (port 8081, url `http://localhost:8081/poll`, md5_strict false, modules_repo GitHub URL), `module_defaults` block (chatbot: OpenAI GPT-4 temp 0.7; API: timeout 15s, JSON content-type; email: SMTP Gmail 587; slack: webhook placeholder; git: token placeholder).

### Live Demo & Commands

```bash
# 1. Verify the engine pod is running with 1/1 containers ready — proves the StatefulSet deployed successfully on EKS
kubectl get pods -n seyoawe
# Expected output:
#   NAME                READY   STATUS    RESTARTS   AGE
#   seyoawe-engine-0    1/1     Running   0          XXh

# 2. Confirm the PVC (PersistentVolumeClaim) is Bound to a 2Gi EBS (Elastic Block Store) volume — proves dynamic provisioning via CSI (Container Storage Interface) worked
kubectl get pvc -n seyoawe
# Expected output:
#   NAME                    STATUS   VOLUME       CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
#   data-seyoawe-engine-0   Bound    pvc-xxxxx    2Gi        RWO            gp2            <unset>                 XXh

# 3. Show the ClusterIP Service with both named ports — proves internal networking is configured for API and Module Dispatcher
kubectl get svc -n seyoawe
# Expected output:
#   NAME             TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE
#   seyoawe-engine   ClusterIP   172.20.xx.xx     <none>        8080/TCP,8081/TCP   XXh

# 4. Display the full ConfigMap contents — shows the injected config.yaml with logging, directories, app, and module settings
kubectl describe configmap seyoawe-config -n seyoawe
# → Shows the full config.yaml with logging, directories, app, module_dispatcher, module_defaults

# 5. Port-forward and send a live request to the engine API — proves the application is functional end-to-end
kubectl port-forward svc/seyoawe-engine 8090:8080 -n seyoawe &
sleep 2

# Basic connectivity check — confirms Flask is accepting HTTP requests
curl -s http://localhost:8090/
# Expected output: Flask response (HTML or JSON)

# Execute a sample workflow via the API — proves the engine can process workflows end-to-end
curl -s -X POST http://localhost:8090/api/community/hello-world | python3 -m json.tool
# Expected output: JSON response with workflow execution result

kill %1

# 6. Tail the engine pod logs — shows real-time Flask request handling and module loading traces
kubectl logs seyoawe-engine-0 -n seyoawe --tail=20
# Expected output: Engine startup logs + request handling traces

# 7. Confirm the EBS (Elastic Block Store) CSI (Container Storage Interface) driver is healthy — controllers manage volume lifecycle, node agents handle local mounts
kubectl get pods -n kube-system | grep ebs
# Expected output:
#   ebs-csi-controller-xxxxx-xxxxx   6/6   Running   0   XXh   (2 replicas — manage create/attach/delete)
#   ebs-csi-node-xxxxx               3/3   Running   0   XXh   (1 per worker node — handles local mount/unmount)
```

---

## Slide 7 — Phase 6: Observability Bonus

### Project Requirement

> Bonus — Observability (+10 pts): Monitoring & Dashboards

### Technical Deep-Dive

#### kube-prometheus-stack

The monitoring stack is deployed via the **Helm chart** `prometheus-community/kube-prometheus-stack` with heavily customized values tuned for a 2× t3.medium node cluster (4 vCPU / 8 GiB per node — tight resource budget):

| Component | Configuration |
|-----------|---------------|
| Prometheus | 1 replica, 3-day retention, 200m/400Mi requests → 500m/600Mi limits, 5Gi PVC on gp2, image `docker.io/prom/prometheus:v3.10.0` |
| Alertmanager | 1 replica, 50m/64Mi requests → 100m/128Mi limits, image `docker.io/prom/alertmanager:v0.31.1` |
| Grafana | Admin password: `seyoawe-grafana`, default dashboards enabled (28 pre-built dashboards), timezone: browser, 100m/128Mi → 200m/256Mi, sidecar image `docker.io/kiwigrid/k8s-sidecar:2.5.0` |
| Prometheus Operator | 50m/64Mi requests, config-reloader image `ghcr.io/prometheus-operator/prometheus-config-reloader:v0.89.0` |
| kube-state-metrics | 50m/64Mi requests |
| node-exporter | 50m/32Mi per node, image `docker.io/prom/node-exporter:v1.10.2` |

**Image registry override to `docker.io`** — AWS EC2 instances inside a datacenter frequently encounter HTTP 502 errors when pulling from `quay.io` (the default registry for many kube-prometheus images). Overriding to Docker Hub mirrors resolves this reliability issue. Every component with a quay.io default is explicitly set to its docker.io equivalent.

**`serviceMonitorSelectorNilUsesHelmValues: false`** — By default, the Prometheus Operator only discovers ServiceMonitors that match the Helm release's label selectors. Setting this to `false` allows Prometheus to discover ServiceMonitors from **all namespaces with any labels**, which is required for our custom `seyoawe-engine` ServiceMonitor in the `seyoawe` namespace.

The corresponding selector overrides are also set:
```yaml
serviceMonitorNamespaceSelector: {}
serviceMonitorSelector: {}
podMonitorSelectorNilUsesHelmValues: false
podMonitorNamespaceSelector: {}
podMonitorSelector: {}
```

**Storage:** Prometheus stores its TSDB (Time Series Database) on a 5Gi gp2 PVC (`storageSpec.volumeClaimTemplate`), ensuring metrics survive pod restarts. With 3-day retention and ~14 scrape targets at 30s intervals, 5Gi is sufficient for the PoC.

#### ServiceMonitor for Engine

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: seyoawe-engine
  namespace: monitoring
  labels:
    release: monitoring   # MUST match the Helm release name
spec:
  namespaceSelector:
    matchNames: [seyoawe]
  selector:
    matchLabels:
      app: seyoawe-engine
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
      scrapeTimeout: 10s
```

**Key configuration points:**
- **`release: monitoring` label** — This label is mandatory. The Prometheus Operator filters ServiceMonitors by this label, which must match the Helm release name (`monitoring`). Without this label, Prometheus would not discover the ServiceMonitor.
- **`namespaceSelector.matchNames: [seyoawe]`** — Tells Prometheus to look for matching Services in the `seyoawe` namespace (cross-namespace discovery).
- **`selector.matchLabels: app: seyoawe-engine`** — Matches the Service object's labels.
- **`endpoints.port: http`** — References the named port `http` (8080) defined in the Service.
- **`path: /metrics`** — Standard Prometheus metrics endpoint.
- **`interval: 30s` / `scrapeTimeout: 10s`** — Scrapes every 30 seconds with a 10-second timeout.

### Relevant Files & Structure

- **`monitoring/kube-prometheus-values.yaml`** — 105 lines. Prometheus section: `replicas: 1`, `retention: 3d`, image `docker.io/prom/prometheus:v3.10.0`, `serviceMonitorSelectorNilUsesHelmValues: false`, `serviceMonitorNamespaceSelector: {}`, `serviceMonitorSelector: {}`, `podMonitorSelectorNilUsesHelmValues: false`, `podMonitorNamespaceSelector: {}`, `podMonitorSelector: {}`, resources requests 200m/400Mi limits 500m/600Mi, storageSpec `volumeClaimTemplate` 5Gi gp2 RWO. Alertmanager section: `replicas: 1`, image `docker.io/prom/alertmanager:v0.31.1`, resources 50m/64Mi → 100m/128Mi. Grafana section: `adminPassword: seyoawe-grafana`, `defaultDashboardsEnabled: true`, `defaultDashboardsTimezone: browser`, resources 100m/128Mi → 200m/256Mi, sidecar image `docker.io/kiwigrid/k8s-sidecar:2.5.0`. Operator section: resources 50m/64Mi, config-reloader `ghcr.io/prometheus-operator/prometheus-config-reloader:v0.89.0`. kube-state-metrics section: resources 50m/64Mi. node-exporter section: image `docker.io/prom/node-exporter:v1.10.2`, resources 50m/32Mi.
- **`monitoring/servicemonitor-engine.yaml`** — 22 lines. ServiceMonitor `seyoawe-engine` in namespace `monitoring`. Labels: `app: seyoawe-engine`, `project: seyoawe`, `release: monitoring` (required for Prometheus Operator discovery). `namespaceSelector.matchNames: [seyoawe]`. `selector.matchLabels: app: seyoawe-engine`. Single endpoint: port `http`, path `/metrics`, interval `30s`, scrapeTimeout `10s`.

### Live Demo & Commands

```bash
# 1. Verify all 7 monitoring pods are running — proves the kube-prometheus-stack Helm chart deployed successfully
kubectl get pods -n monitoring
# Expected output (7 pods):
#   NAME                                                     READY   STATUS    RESTARTS   AGE
#   alertmanager-monitoring-kube-prometheus-alertmanager-0    2/2     Running   0          XXh
#   monitoring-grafana-xxxxxxxxxx-xxxxx                       3/3     Running   0          XXh
#   monitoring-kube-prometheus-operator-xxxxxxxxxx-xxxxx      1/1     Running   0          XXh
#   monitoring-kube-state-metrics-xxxxxxxxxx-xxxxx            1/1     Running   0          XXh
#   monitoring-prometheus-node-exporter-xxxxx                 1/1     Running   0          XXh
#   monitoring-prometheus-node-exporter-xxxxx                 1/1     Running   0          XXh
#   prometheus-monitoring-kube-prometheus-prometheus-0        2/2     Running   0          XXh

# 2. 🔗 Open Grafana — the visualization layer with 28 pre-built K8s (Kubernetes) dashboards
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring &
sleep 2
# → Open: http://localhost:3000
# → Login: admin / seyoawe-grafana
# → What to show:
#   - Navigate to Dashboards → "Kubernetes / Compute Resources / Cluster"
#   - Show CPU Usage, Memory Usage, and Network I/O broken down by namespace
#   - Show the "seyoawe" and "monitoring" namespaces with their resource consumption
#   - Navigate to "Kubernetes / Compute Resources / Namespace (Pods)" → select "seyoawe"
#   - Show the seyoawe-engine-0 pod's CPU/Memory usage over time
kill %1

# 3. 🔗 Open Prometheus UI — the metrics collection engine that scrapes all K8s targets
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring &
sleep 2
# → Open: http://localhost:9090/targets
# → What to show:
#   - 14+ scrape targets (most in UP state) — proves Prometheus is collecting cluster-wide metrics
#   - Locate the "seyoawe-engine" target (shows DOWN — the engine has no /metrics endpoint, which is expected)
#   - Navigate to Graph tab → run query: up{job="kubelet"} → show all kubelets are UP
kill %1

# 4. List all 14 ServiceMonitors — proves Prometheus Operator is discovering targets across namespaces
kubectl get servicemonitor -n monitoring
# Expected output:
#   NAME                                                 AGE
#   monitoring-grafana                                   XXh
#   monitoring-kube-prometheus-alertmanager              XXh
#   monitoring-kube-prometheus-apiserver                 XXh
#   monitoring-kube-prometheus-coredns                   XXh
#   monitoring-kube-prometheus-kube-controller-manager   XXh
#   monitoring-kube-prometheus-kube-etcd                 XXh
#   monitoring-kube-prometheus-kube-proxy                XXh
#   monitoring-kube-prometheus-kube-scheduler            XXh
#   monitoring-kube-prometheus-kubelet                   XXh
#   monitoring-kube-prometheus-operator                  XXh
#   monitoring-kube-prometheus-prometheus                XXh
#   monitoring-kube-state-metrics                        XXh
#   monitoring-prometheus-node-exporter                  XXh
#   seyoawe-engine                                       XXh  ← our custom ServiceMonitor

# 5. Query Prometheus API via PromQL (Prometheus Query Language) — programmatic proof that the engine scrape target is registered
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring &
sleep 2
curl -s "http://localhost:9090/api/v1/query?query=up{job='seyoawe-engine'}" | python3 -m json.tool
# Expected output: "value": [timestamp, "0"]
# Note: value is "0" because the engine has no /metrics endpoint (returns 404).
# This is expected — the ServiceMonitor is correctly configured and Prometheus
# is actively scraping, but the engine does not expose Prometheus metrics natively.
# The scrape target appears in the Prometheus Targets UI as DOWN.
kill %1
```

---

## Slide 8 — Summary & Requirements Traceability

### Full Requirements Mapping — Tasks ↔ Implementation

| Task | Points | Implementation | Slide |
|------|--------|----------------|-------|
| **Task 1** — Code Structure & Docs | 5 pts | Repository skeleton, 8 Design Logs, README (189 lines), VERSION file | 2 |
| **Task 2** — Dockerize the App | 10 pts | 2 Dockerfiles (Engine: binary guard + HEALTHCHECK + symlink; CLI: sed version injection) | 4 |
| **Task 3** — Testing | 10 pts | 13 pytest tests, 5 classes, <2s execution, JUnit XML reporting | 4 |
| **Task 4** — CI (Continuous Integration) Pipeline | 15 pts | 2 Jenkins Declarative Pipelines (Engine CI, CLI CI), lint/test/build/push stages | 5 |
| **Version Coupling** | 10 pts | Single `VERSION` file, `git diff` change detection, dual-trigger on VERSION change | 5 |
| **Git Tagging** | 15 pts | `engine-v0.1.1`, `cli-v0.1.1`, `deploy-v0.1.1` — automated via Jenkins, pushed to GitHub | 5 |
| **Task 5** — IaC (Infrastructure as Code) & CD (Continuous Delivery) | 20 pts | Terraform (VPC, EKS, EC2, IRSA — 412 lines), Ansible (4 playbooks), Jenkinsfile.cd (10 stages, Approval Gate) | 3 |
| **Task 5** — K8s (Kubernetes) Deployment | 10 pts | StatefulSet (1 replica), tcpSocket probes, PVC 2Gi gp2, ConfigMap subPath, EBS CSI via IRSA | 6 |
| **Bonus** — Observability | +10 pts | kube-prometheus-stack (PoC-tuned values), ServiceMonitor, 28 Grafana dashboards, 14 scrape targets | 7 |
| | **= 105/100** | | |

### Recurring PoC-first Principles

1. **`t3.medium` everywhere** — The minimum viable instance type, ~$0.04/hr per instance. Sufficient for EKS workers (4 vCPU, 8 GiB) and Jenkins (2 vCPU headroom for Docker builds).
2. **Single NAT (Network Address Translation) Gateway** — Saves ~$0.05/hr compared to HA dual-NAT. Acceptable single point of failure for PoC (production would deploy one per AZ).
3. **S3-only state locking** — Terraform 1.14's `use_lockfile = true` eliminates DynamoDB entirely. Fewer resources, lower cost, simpler backend.
4. **1 Replica everything** — StatefulSet + Prometheus + Alertmanager all at 1 replica. Sufficient for demonstration, conserves the limited node capacity on 2× t3.medium.
5. **`lifecycle.sh` suspend/resume** — Granular cost control. Stop Jenkins when not pushing code. Scale EKS nodes to 0 when not demonstrating. `destroy --all` guarantees zero residual footprint and zero AWS charges.
6. **Flat Terraform layout** — Single `main.tf` with all ~25 resources. Easy to review, easy to debug, appropriate for PoC scope.
7. **Docker.io mirrors** — Prevents quay.io 502 errors inside AWS datacenters. Every monitoring image is explicitly pinned to its Docker Hub equivalent.

### Tool Versions

| Tool | Version |
|------|---------|
| Terraform | 1.14.0 |
| kubectl | v1.34.1 |
| Helm | v3.17.0 |
| EKS (Elastic Kubernetes Service) | v1.32 |
| Python | 3.11-slim (Docker base) |
| Jenkins | LTS (Long-Term Support, containerized on EC2) |
| Prometheus | v3.10.0 |
| Alertmanager | v0.31.1 |
| Grafana | kube-prometheus-stack default |
| AWS Provider | ~> 5.90 |
| node-exporter | v1.10.2 |
| k8s-sidecar | 2.5.0 |

---

## Slide 9 — Full Repository Structure

```
final-project-devops/
├── .cursor/
│   ├── design-logs/             # 8 Design Logs (0001–0008)
│   ├── diagrams-mmd/            # 11 Mermaid architecture diagrams
│   ├── plans/                   # Master project plan
│   ├── reports/                 # Technical report + traceability matrix
│   └── rules/                   # Cursor rules (design-log, resource-registry)
│
├── ansible/                     # Configuration Management
│   ├── inventory.ini            #   Host inventory (local + jenkins groups)
│   └── playbooks/
│       ├── configure-jenkins.yaml         # Docker + Jenkins container + kubectl + awscli
│       ├── configure-jenkins-tools.yaml   # shellcheck + yamllint for CI lint stages
│       ├── configure-eks.yaml             # kubeconfig + namespace creation
│       └── install-tools.yaml             # verify all DevOps tool versions
│
├── cli/                         # sawectl CLI (Command-Line Interface) Tool (Python)
│   ├── sawectl.py               #   CLI entrypoint (validate-workflow/module, list-modules)
│   ├── requirements.txt         #   Python deps (pyyaml, jsonschema, requests)
│   ├── dsl.schema.json          #   Workflow validation JSON Schema
│   ├── module.schema.json       #   Module manifest validation JSON Schema
│   └── tests/
│       ├── conftest.py          #   sys.path setup + shared path constants
│       └── test_sawectl.py      #   13 tests across 5 classes (<2s)
│
├── docker/                      # Dockerfiles
│   ├── engine/Dockerfile        #   python:3.11-slim, binary guard, HEALTHCHECK, symlink
│   └── cli/Dockerfile           #   python:3.11-slim, version injection via sed
│
├── engine/                      # SeyoAWE Engine (upstream app + config)
│   ├── configuration/config.yaml#   Engine configuration (ports, modules, logging)
│   ├── modules/                 #   Python modules (api, chatbot, slack, email, git, etc.)
│   ├── workflows/               #   YAML workflow definitions (samples + community)
│   └── run.sh                   #   Binary launcher script (linux/macos)
│
├── jenkins/                     # CI/CD (Continuous Integration/Delivery) Pipeline Definitions
│   ├── Jenkinsfile.engine       #   Engine CI: lint → build → push → tag (155 lines)
│   ├── Jenkinsfile.cli          #   CLI CI: lint → test → build → push → tag (143 lines)
│   └── Jenkinsfile.cd           #   CD: TF plan → approve → apply → deploy (164 lines)
│
├── k8s/                         # K8s (Kubernetes) Manifests
│   ├── namespace.yaml           #   Namespaces: seyoawe + monitoring
│   └── engine/
│       ├── statefulset.yaml     #   1 replica, tcpSocket probes, PVC 2Gi gp2 (82 lines)
│       ├── service.yaml         #   ClusterIP, ports 8080 + 8081 (22 lines)
│       └── configmap.yaml       #   Engine config.yaml injection via subPath (68 lines)
│
├── monitoring/                  # Observability Stack
│   ├── kube-prometheus-values.yaml    # Helm values: PoC-tuned, docker.io mirrors (105 lines)
│   └── servicemonitor-engine.yaml     # Scrape seyoawe-engine:8080/metrics (22 lines)
│
├── scripts/                     # Automation Scripts
│   ├── change-detect.sh         #   BUILD_ENGINE / BUILD_CLI flag logic (57 lines)
│   └── version.sh               #   Read VERSION → export APP_VERSION (24 lines)
│
├── terraform/                   # IaC (Infrastructure as Code)
│   ├── backend.tf               #   S3 backend + use_lockfile, no DynamoDB (23 lines)
│   ├── main.tf                  #   VPC, EKS, Jenkins, IRSA, addons (412 lines)
│   ├── variables.tf             #   7 variables: region, cluster, instances, IP (40 lines)
│   └── outputs.tf               #   7 outputs: IPs, ARNs, kubeconfig cmd (35 lines)
│
├── VERSION                      #   0.1.1 — Single Source of Truth for all pipelines
├── lifecycle.sh                 #   AWS resource lifecycle manager (387 lines)
├── setup-env.sh                 #   One-command environment bootstrap (241 lines)
├── requirements-infra.txt       #   Python infra deps (awscli, ansible, pytest, flake8, etc.)
├── .dockerignore                #   Exclude .venv, .git, terraform/ from Docker context
├── .flake8                      #   Python linting configuration
├── .gitignore                   #   Standard ignores + .aws-project/, .venv/
└── README.md                    #   Full project documentation (189 lines)
```

---

## Slide 10 — End-to-End Live Flow Demo

### Demonstrating the Complete DevOps Lifecycle in Action

This section walks through the **entire pipeline flow** — from a code change to a deployed, monitored application — proving every component works together as a unified system.

#### Step 1: Pre-Flight — Verify Everything is Running

```bash
# Confirm the entire stack is healthy before starting the demo
./lifecycle.sh status
# → All 5 resources should show green (ACTIVE / running / deployed / exists)

kubectl get pods -n seyoawe
# → seyoawe-engine-0 should be 1/1 Running

kubectl get pods -n monitoring
# → All 7 monitoring pods should be Running
```

#### Step 2: Show Current State

```bash
# Show the current version — this is what all images and tags are currently pinned to
cat VERSION
# → 0.1.1

# Show the current container image running in K8s (Kubernetes) — confirms it matches VERSION
kubectl get sts seyoawe-engine -n seyoawe -o jsonpath='{.spec.template.spec.containers[0].image}' && echo
# → danielmazh/seyoawe-engine:0.1.1

# Show all existing git tags — these were created by CI/CD pipelines
git tag -l
# → cli-v0.1.1, engine-v0.1.1 (+ deploy-v0.1.1 if CD has run)
```

#### Step 3: Show the CI (Continuous Integration) Pipelines on Jenkins

```bash
# 🔗 Open Jenkins dashboard — the CI/CD command center
JENKINS_IP=$(cd terraform && terraform output -raw jenkins_public_ip)
open http://${JENKINS_IP}:8080
```

**What to show on Jenkins UI:**

1. **Dashboard** → 3 pipeline jobs visible: `engine-ci`, `cli-ci`, `cd`
2. **Click `engine-ci`** → Show the Stage View with colored boxes for each stage
   - Point out: Checkout → VERSION → Change Detection → Lint → Binary → Docker Build → Push → Tag
   - Click into a successful build → Console Output → search for `BUILD_ENGINE=true`
3. **Click `cli-ci`** → Show the Stage View
   - Click into Console Output → search for `13 passed` (pytest results)
   - Show the "Test Result" tab → 13/13 tests passed (JUnit report)
4. **Click `cd`** → Show the Stage View with the **Manual Approval Gate** (⏸ icon)
   - Click into a completed build → show "Review the Terraform plan" approval prompt
   - Show all 10 stages completed green

#### Step 4: Show the Images on DockerHub

**Clickable links — open in browser:**

- [DockerHub — seyoawe-engine](https://hub.docker.com/r/danielmazh/seyoawe-engine/tags) → Show tags `0.1.1` and `latest`, pushed dates, image size
- [DockerHub — seyoawe-cli](https://hub.docker.com/r/danielmazh/seyoawe-cli/tags) → Show tags `0.1.1` and `latest`, identical version tags proving version coupling

**What to explain:** Both images share the same version tag (`0.1.1`) because the `VERSION` file is the single source of truth. When VERSION changes, both CI pipelines rebuild and push simultaneously.

#### Step 5: Show the Running Application on K8s (Kubernetes)

```bash
# Show the full K8s state — pod, PVC (PersistentVolumeClaim), and Service all healthy
kubectl get pods,pvc,svc -n seyoawe
# → seyoawe-engine-0 (1/1 Running), data-seyoawe-engine-0 (Bound 2Gi), seyoawe-engine (ClusterIP 8080+8081)

# Port-forward and hit the engine API — proves the app is serving requests
kubectl port-forward svc/seyoawe-engine 8090:8080 -n seyoawe &
sleep 2

# Execute a sample workflow — demonstrates the engine processing a real workflow definition
curl -s -X POST http://localhost:8090/api/community/hello-world | python3 -m json.tool
# → JSON response with workflow execution result

kill %1
```

**What to explain:** The StatefulSet keeps the pod name stable (`seyoawe-engine-0`), the PVC retains data across restarts, and the ClusterIP Service provides internal DNS for the engine.

#### Step 6: Show the Monitoring Dashboards

```bash
# 🔗 Open Grafana — the monitoring visualization layer
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring &
sleep 2
```

**Open [http://localhost:3000](http://localhost:3000) and show:**

1. **Login:** `admin` / `seyoawe-grafana`
2. **Dashboard → "Kubernetes / Compute Resources / Cluster"**
   - Show CPU and Memory usage broken down by namespace (`seyoawe`, `monitoring`, `kube-system`)
   - Point out: the monitoring namespace uses more resources than the app itself (expected for PoC)
3. **Dashboard → "Kubernetes / Compute Resources / Namespace (Pods)"** → select `seyoawe`
   - Show `seyoawe-engine-0` pod CPU/Memory usage over time
4. **Dashboard → "Kubernetes / Networking / Namespace (Pods)"** → select `seyoawe`
   - Show network traffic in/out for the engine pod

```bash
kill %1

# 🔗 Open Prometheus Targets — proves all scrape targets are registered and being collected
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring &
sleep 2
```

**Open [http://localhost:9090/targets](http://localhost:9090/targets) and show:**

1. **14+ scrape targets** — most showing "UP" in green
2. **Locate `seyoawe-engine`** target — shows "DOWN" (expected — engine has no `/metrics` endpoint)
3. **Navigate to Graph** → run `up{job="kubelet"}` → all kubelets are UP

```bash
kill %1
```

#### Step 7: Show Cost Management

```bash
# Display the hourly cost estimate — proves PoC cost awareness is built into the workflow
./lifecycle.sh status
# → Total: ~$0.27/hr (~$6.50/day)
#   This is the full stack: EKS control plane + 2 worker nodes + Jenkins + NAT Gateway

# Show the Resource Registry in lifecycle.sh — every cloud resource is cataloged for billing safety
head -40 lifecycle.sh | grep -A 30 "RESOURCE REGISTRY"
# → Shows all 27 registered resources organized by management tool (terraform, helm, kubectl, aws-cli)
```

#### Step 8: Final Summary Commands

```bash
# Single command that proves the entire DevOps lifecycle is functional end-to-end
cat VERSION && echo "---" && \
git tag -l && echo "---" && \
kubectl get pods -n seyoawe && echo "---" && \
kubectl get pods -n monitoring && echo "---" && \
./lifecycle.sh status

# Expected:
#   0.1.1                          ← VERSION (Single Source of Truth)
#   ---
#   cli-v0.1.1                     ← CI tagged the CLI image
#   engine-v0.1.1                  ← CI tagged the Engine image
#   ---
#   seyoawe-engine-0  1/1 Running  ← App is deployed and healthy on EKS
#   ---
#   7 monitoring pods  Running     ← Observability stack is operational
#   ---
#   All resources ACTIVE/running   ← Infrastructure is fully provisioned
```

---

## Slide 11 — Questions

### Thank You!

**GitHub:** [github.com/danielmazh/final-project-devops](https://github.com/danielmazh/final-project-devops)  
**DockerHub:** [danielmazh/seyoawe-engine](https://hub.docker.com/r/danielmazh/seyoawe-engine) | [danielmazh/seyoawe-cli](https://hub.docker.com/r/danielmazh/seyoawe-cli)

```bash
# Quick full-stack verification — all in one:
cat VERSION && \
pytest cli/tests/ -v && \
kubectl get pods -n seyoawe && \
kubectl get pods -n monitoring && \
./lifecycle.sh status
```
