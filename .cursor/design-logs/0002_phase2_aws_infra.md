# 0002 — Phase 2: AWS Infrastructure (Terraform & Ansible)

## 1. Background & Problem

Phase 5 requires a Kubernetes cluster on AWS to deploy the SeyoAWE engine. This phase provisions the underlying network and compute via Terraform, and uses Ansible to configure local tooling (kubeconfig, namespace prep). The architecture must satisfy the rubric requirement for "CD pipeline (Terraform + Ansible)" while keeping cost and complexity minimal for a PoC / beginner course.

**Root cause:** No AWS infrastructure exists yet; no remote state backend for Terraform.

## 2. Questions & Answers

| Question | Answer |
|----------|--------|
| Single region? | **Yes** — one region (e.g. `us-east-1`). |
| DynamoDB for state locking? | **No.** Terraform 1.14 supports `use_lockfile = true` on the S3 backend, which uses S3 conditional writes for locking. This eliminates DynamoDB entirely. |
| NAT strategy? | **Single NAT GW** in AZ-A. Both private subnets route outbound via it. Saves ~$32/month vs. dual NAT. Acceptable for PoC (no HA requirement). |
| EKS API visibility? | **Public endpoint.** No bastion or VPN needed. Simplifies kubectl access from laptop and Jenkins EC2. |
| IAM complexity? | **Two roles only:** EKS cluster role + node instance role. No IRSA, no OIDC provider. Node role is sufficient for pulling public DockerHub images. |
| Terraform layout? | **Flat** (`terraform/*.tf`). One environment, one apply — nested modules add indirection with no PoC benefit. |
| Where does Jenkins run? | **Dedicated EC2 (t3.medium) in the public subnet.** Local machine is too slow for Docker builds. EC2 provides native Docker socket, dedicated CPU/RAM, and is itself provisioned by Terraform + configured by Ansible (strengthens the CD rubric score). |
| Ansible scope? | **Post-apply.** Three playbooks: install-tools (localhost), configure-eks (kubeconfig + namespaces), **configure-jenkins** (Docker + Jenkins on EC2). No roles directory. |

## 3. Design & Solution

### 3.1 Remote state backend

| Resource | Details |
|----------|---------|
| S3 bucket | `seyoawe-tf-state-<account-id>`, versioning ON, public access blocked, SSE-AES256 |
| IAM user | `terraform-deployer`, `AdministratorAccess` (lab/student account) |
| DynamoDB | **Not used.** S3 native locking via `use_lockfile = true`. |

```hcl
terraform {
  backend "s3" {
    bucket       = "seyoawe-tf-state-<account-id>"
    key          = "dev/terraform.tfstate"
    region       = "<region>"
    encrypt      = true
    use_lockfile = true
  }
}
```

### 3.2 VPC

- CIDR: `10.0.0.0/16`
- 2 AZs (EKS requires subnets in at least 2 AZs)
- Public subnets: `10.0.1.0/24` (AZ-A), `10.0.2.0/24` (AZ-B) — IGW
- Private subnets: `10.0.10.0/24` (AZ-A), `10.0.20.0/24` (AZ-B) — EKS workers
- **Single NAT GW** in AZ-A public subnet; both private subnets route `0.0.0.0/0` through it
- Tags: `kubernetes.io/cluster/<name>=shared`, `kubernetes.io/role/elb=1` on public, `kubernetes.io/role/internal-elb=1` on private

```
Internet
  │
  IGW
  ├── Public-A (10.0.1.0/24) ── NAT GW, Jenkins EC2 (t3.medium)
  ├── Public-B (10.0.2.0/24)
  │
  NAT GW
  ├── Private-A (10.0.10.0/24) ── EKS workers
  └── Private-B (10.0.20.0/24) ── EKS workers
```

### 3.3 EKS

- AWS-managed control plane, **public API endpoint**
- Managed node group: **2 × t3.medium** in private subnets
- Addons: `vpc-cni`, `kube-proxy`, `coredns` (EKS-managed)
- Cluster creator (terraform-deployer) automatically gets `system:masters` access

### 3.4 Jenkins EC2

| Attribute | Value |
|-----------|-------|
| Instance type | `t3.medium` (2 vCPU, 4 GiB — enough for Jenkins + concurrent Docker builds) |
| AMI | Amazon Linux 2023 (latest, looked up via `data "aws_ami"`) |
| Subnet | Public-A (`10.0.1.0/24`) — public IP auto-assigned |
| Security group | Inbound: **8080** (Jenkins UI) + **22** (SSH) restricted to operator IP; Outbound: all |
| Key pair | Existing or newly created AWS key pair (manual step) |
| Provisioning | Terraform creates the instance; Ansible installs Docker + runs Jenkins container |

Jenkins reaches the EKS public API endpoint directly (no special networking needed).

### 3.5 IAM

| Role | Trust | Policies |
|------|-------|----------|
| `seyoawe-eks-cluster-role` | `eks.amazonaws.com` | `AmazonEKSClusterPolicy` |
| `seyoawe-eks-node-role` | `ec2.amazonaws.com` | `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly` |

No OIDC provider. No IRSA. No service-account-level permissions.

### 3.6 Ansible

| File | Purpose |
|------|---------|
| `ansible/inventory.ini` | Two groups: `[local]` (localhost, `ansible_connection=local`) and `[jenkins]` (EC2 public IP, SSH via key pair) |
| `ansible/playbooks/install-tools.yaml` | Idempotent check for `kubectl`, `helm`, `aws` CLI on localhost |
| `ansible/playbooks/configure-eks.yaml` | `aws eks update-kubeconfig --name <cluster> --profile seyoawe-tf`, `kubectl get nodes`, `kubectl create namespace seyoawe`, `kubectl create namespace monitoring` |
| `ansible/playbooks/configure-jenkins.yaml` | **On Jenkins EC2:** install Docker, start `jenkins/jenkins:lts` container (bind-mount Docker socket + jenkins_home volume), install `kubectl` + `aws` CLI on the host so pipeline steps can deploy to EKS |

## 4. Implementation Plan (post–`aws-ready`)

1. Write `terraform/backend.tf` with S3 backend + `use_lockfile = true`.
2. Write `terraform/variables.tf`, `terraform/main.tf` (VPC + EKS + IAM + Jenkins EC2 + SG), `terraform/outputs.tf`.
3. `terraform init && terraform plan` → review.
4. `terraform apply` → VPC + EKS + Jenkins EC2 provisioned.
5. Write `ansible/inventory.ini` (two groups: local + jenkins) and three playbooks.
6. Run `ansible-playbook -i ansible/inventory.ini ansible/playbooks/configure-jenkins.yaml` → Docker + Jenkins on EC2.
7. Run `ansible-playbook -i ansible/inventory.ini ansible/playbooks/configure-eks.yaml` → kubeconfig + namespaces.
8. Verify: `kubectl get nodes` + open Jenkins at `http://<ec2-ip>:8080`.

## 5. Examples

- ✅ `use_lockfile = true` in backend → S3-only locking, no DynamoDB needed.
- ❌ `dynamodb_table = "..."` with Terraform 1.14 → unnecessary resource and cost.
- ✅ Single NAT GW for PoC → ~$35/mo total NAT cost.
- ❌ Dual NAT for a lab environment → $70/mo with no availability benefit for coursework.

## 6. Trade-offs

| Choice | Rationale |
|--------|-----------|
| S3-only lock (no DynamoDB) | Terraform 1.10+ feature; eliminates a resource and table management. |
| Single NAT GW | PoC has no HA requirement; saves ~$32/month. |
| Public EKS endpoint | No bastion/VPN setup; simplifies kubectl and Jenkins access. |
| Jenkins on EC2 (not EKS) | Dedicated resources, native Docker socket (no DinD), more Terraform + Ansible to demonstrate for the CD rubric. |
| Flat Terraform layout | One environment — nested modules are overhead for a single apply target. |
| `AdministratorAccess` on deployer | Lab account; not appropriate for production. |

## 7. Verification Criteria

- [ ] `aws sts get-caller-identity --profile seyoawe-tf` returns expected account.
- [ ] `aws s3 ls s3://seyoawe-tf-state-<account-id>/ --profile seyoawe-tf` succeeds.
- [ ] `terraform init` initializes S3 backend without error.
- [ ] `terraform plan` shows expected resources (VPC, subnets, NAT, EKS, node group, IAM roles, Jenkins EC2, SG).
- [ ] `terraform apply` completes; `kubectl get nodes` returns 2 Ready nodes.
- [ ] Jenkins UI reachable at `http://<ec2-ip>:8080`.
- [ ] Ansible playbooks run clean (all three).

---

## Implementation Results

**When:** 2026-03-27 (Phase 2 IaC authoring)

### Deviations from plan

- IAM user is `devops-trainer` (pre-existing) rather than a newly created `terraform-deployer`. Profile `seyoawe-tf` is configured to use this user. All required permissions are in place.
- AWS provider resolved to `5.100.0` (compatible with `~> 5.90` pin).

### What was done

1. S3 state bucket `seyoawe-tf-state-632008729195` created (versioning, public-access-block, SSE-AES256).
2. Terraform files written (flat layout):
   - `backend.tf` — S3 backend, `use_lockfile = true`, no DynamoDB
   - `variables.tf` — region, cluster/node/jenkins config, `jenkins_key_pair`, `operator_ip`
   - `main.tf` — VPC (10.0.0.0/16), 2 public + 2 private subnets, IGW, single NAT, route tables, EKS cluster (1.32), managed node group (2 × t3.medium), EKS addons (vpc-cni, kube-proxy, coredns), IAM roles (cluster + node), Jenkins EC2 (t3.medium) + security group
   - `outputs.tf` — cluster name/endpoint, kubeconfig command, Jenkins public IP + UI URL, VPC ID
   - `terraform.tfvars.example` — template for required values (tracked)
3. Ansible files written:
   - `ansible/inventory.ini` — localhost + Jenkins host comment/instructions
   - `ansible/playbooks/install-tools.yaml` — verify tool versions locally
   - `ansible/playbooks/configure-eks.yaml` — update-kubeconfig, wait for nodes, create namespaces
   - `ansible/playbooks/configure-jenkins.yaml` — install Docker, start Jenkins container, install kubectl + aws-cli on EC2
4. `terraform init` — **SUCCESS** (S3 backend connected, provider `aws 5.100.0` installed).

### Remaining before apply

- Create `terraform/terraform.tfvars` from example (fill `jenkins_key_pair` and `operator_ip`)
- Ensure the named AWS key pair exists in `us-east-1`
- `terraform plan` → review → `terraform apply`
