# 0001 — DevOps Final Project: Master Plan

**Project:** SeyoAWE Community — Full DevOps Lifecycle Implementation  
**Created:** 2026-03-27  
**Updated:** 2026-03-27 — rewritten for PoC / beginner-course scope  
**Status:** Active  
**Score Target:** 100/100 (including Observability bonus)  
**Approach:** Proof-of-Concept — fast, cheap, simple. Meets every rubric requirement without over-engineering.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Operational Rules (Always Active)](#2-operational-rules-always-active)
3. [Source Application Summary](#3-source-application-summary)
4. [Target Repository Structure](#4-target-repository-structure)
5. [Evaluation Breakdown](#5-evaluation-breakdown)
6. [Phase 1 — Repository & Environment Setup](#phase-1--repository--environment-setup)
7. [Phase 2 — AWS Infrastructure (Terraform & Ansible)](#phase-2--aws-infrastructure-terraform--ansible)
8. [Phase 3 — Containerization (Docker)](#phase-3--containerization-docker)
9. [Phase 4 — CI Pipelines (Jenkins)](#phase-4--ci-pipelines-jenkins)
10. [Phase 5 — CD Pipeline & Kubernetes Deployment](#phase-5--cd-pipeline--kubernetes-deployment)
11. [Phase 6 — Observability (Bonus)](#phase-6--observability-bonus)
12. [PoC Cost Summary](#poc-cost-summary)
13. [Phase Checklist & Progress Tracker](#phase-checklist--progress-tracker)

---

## 1. Project Overview

Build a **proof-of-concept DevOps platform** around the open-source SeyoAWE Community workflow automation engine, deployed to AWS. The goal is rapid demonstration of all rubric requirements (CI/CD, IaC, containers, K8s, monitoring) with minimal cost and zero unnecessary complexity.

| Component | Language | Description |
|-----------|----------|-------------|
| **Engine** | Pre-compiled binary (Flask, ports 8080/8081) | Modular workflow automation runtime. |
| **CLI (`sawectl`)** | Python 3.10+ | CLI to init, validate, and run workflows against the Engine via `POST /api/adhoc`. |

**Source repo:** `seyoawe-community` (local clone at `~/CProjects/seyoawe-community`)  
**Infrastructure repo:** `final-project-devops` (this repo, `~/CProjects/final-project-devops`)

### PoC Design Principles

| Principle | What it means in practice |
|-----------|--------------------------|
| **Cost-first** | Single NAT Gateway, smallest viable node count, S3-only state locking (no DynamoDB), tear down when not in use. |
| **Simplicity-first** | Public EKS API (no bastion/VPN), out-of-the-box Grafana dashboards, no IRSA/OIDC federation. |
| **Rubric-complete** | Every graded item is implemented — nothing is skipped, only right-sized. |
| **Adequate sizing** | `t3.medium` for EKS nodes and Jenkins EC2 — enough headroom without throttling. |

---

## 2. Operational Rules (Always Active)

These rules apply to EVERY phase. They are non-negotiable.

### 2.1 File Placement & Sequential Naming (`NNNN_`)

| Directory | Purpose |
|-----------|---------|
| `.cursor/plans/` | High-level roadmaps, phase plans |
| `.cursor/design-logs/` | Formal technical design specs (pre-computation required) |
| `.cursor/helpers-scripts/` | Bash/Python automation scripts |
| `.cursor/logs/` | Execution outputs, error dumps |
| `.cursor/wip/` | Drafts, scratchpads |

**Convention:** Before creating any file, scan the target directory for the highest `NNNN_` prefix and increment by 1. Default to `0001` if empty.

### 2.2 Design Log Constraint

**Before ANY code changes or infrastructure generation:**
1. Create a Design Log in `.cursor/design-logs/NNNN_<phase>_<topic>.md`
2. Sections: Background, Questions/Answers, Design/Solution, Implementation Plan, Examples, Trade-offs, Verification Criteria
3. Once implementation begins, only append to "Implementation Results" at the bottom
4. Do NOT modify the original Design/Solution section after work starts

### 2.3 Git Branching Strategy

```
main (protected — never commit directly)
├── feature/phase1-repo-setup
├── feature/phase2-aws-infra
├── feature/phase3-docker
├── feature/phase4-ci-pipelines
├── feature/phase5-cd-kubernetes
└── feature/phase6-observability
```

**Workflow per phase:**
1. `git checkout main && git pull`
2. `git checkout -b feature/phaseN-<name>`
3. Work, commit incrementally with meaningful messages
4. Push: `git push -u origin feature/phaseN-<name>`
5. Merge to main (PR or local merge), tag if applicable

### 2.4 Manual Intervention Protocol

When an action requires human execution (AWS console, API tokens, Jenkins UI), the assistant MUST:
1. **STOP** automated execution
2. Provide explicit step-by-step instructions with links and expected values
3. **WAIT** for user confirmation ("done") before proceeding

---

## 3. Source Application Summary

### Engine
- **Binary:** `seyoawe.linux` / `seyoawe.macos.arm` (not in git — manual download)
- **Launcher:** `run.sh` (selects binary by OS)
- **Config:** `configuration/config.yaml` (ports, directories, module defaults)
- **Ports:** 8080 (app), 8081 (module dispatcher)
- **Directories at runtime:** `modules/`, `workflows/`, `lifetimes/`, `logs/`
- **Health endpoint:** `GET /health` on port 8080

### CLI (`sawectl`)
- **Entry:** `sawectl.py`
- **Deps:** `requirements.txt` → `pyyaml`, `jsonschema`, `requests`, `argparse`
- **Version constant:** `VERSION = "0.0.1"` (in `sawectl.py`)
- **Engine interaction:** `requests.post(f"http://{server}/api/adhoc", json={"workflow": ...})`

### Shared Contracts
- Workflow YAML validated by `dsl.schema.json`
- Module manifests validated by `module.schema.json`
- Both rely on `modules/` directory and `configuration/config.yaml`

---

## 4. Target Repository Structure

```
final-project-devops/
├── engine/                          # Engine source + binary + config
│   ├── seyoawe.linux                # Engine binary (manual, not in git)
│   ├── run.sh
│   ├── configuration/config.yaml
│   ├── modules/
│   └── workflows/samples/
├── cli/                             # CLI source
│   ├── sawectl.py
│   ├── requirements.txt
│   ├── dsl.schema.json
│   ├── module.schema.json
│   └── tests/
│       └── test_sawectl.py
├── docker/                          # Dockerfiles
│   ├── engine/Dockerfile
│   └── cli/Dockerfile
├── k8s/                             # Kubernetes manifests
│   ├── namespace.yaml
│   └── engine/
│       ├── statefulset.yaml
│       ├── service.yaml
│       └── configmap.yaml
├── terraform/                       # IaC — AWS provisioning
│   ├── main.tf                      # Flat layout (no nested modules for PoC)
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars
│   └── backend.tf
├── ansible/                         # Configuration management
│   ├── inventory.ini
│   └── playbooks/
│       ├── configure-eks.yaml
│       ├── install-tools.yaml
│       └── configure-jenkins.yaml   # Install Docker + Jenkins on EC2
├── jenkins/                         # Pipeline definitions
│   ├── Jenkinsfile.engine
│   ├── Jenkinsfile.cli
│   └── Jenkinsfile.cd
├── monitoring/                      # Observability (Helm values only)
│   └── kube-prometheus-values.yaml
├── scripts/                         # Build/version helpers
│   ├── version.sh
│   └── change-detect.sh
├── VERSION
├── README.md
└── .gitignore
```

**PoC simplifications vs. the original plan:**

| Original | PoC | Why |
|----------|-----|-----|
| `terraform/modules/{vpc,eks,iam}/` + `environments/dev/` | Flat `terraform/*.tf` | One environment, one apply — nested modules add indirection with no PoC benefit. |
| `ansible/roles/{kubectl,helm}/` | Simple playbooks, no roles | Two tasks don't justify role scaffolding. |
| `jenkins/shared-libs/vars/*.groovy` | Inline logic in each Jenkinsfile | Three pipelines sharing two functions doesn't warrant a shared library. |
| `monitoring/prometheus/`, `monitoring/grafana/dashboards/` | Single `kube-prometheus-values.yaml` | Helm chart ships with working dashboards; one values file overrides what matters. |
| `k8s/jenkins/` manifests (Jenkins on EKS) | Jenkins on dedicated EC2 (Terraform + Ansible) | Keeps cluster resources for the workload; native Docker socket for builds; more Terraform/Ansible to show for the CD rubric. |

---

## 5. Evaluation Breakdown

| # | Category | Points | Phase | Key Deliverables |
|---|----------|--------|-------|------------------|
| 1 | Engine containerization | 10 | Phase 3 | Dockerfile, image builds, local test |
| 2 | CLI testing & packaging | 10 | Phase 3+4 | Unit tests, Dockerfile, pytest |
| 3 | CI pipeline for Engine | 15 | Phase 4 | Jenkinsfile: lint, test, build, push |
| 4 | CI pipeline for CLI | 10 | Phase 4 | Jenkinsfile: lint, pytest, build, push |
| 5 | Version coupling logic | 15 | Phase 4 | VERSION file, change detection, selective triggers |
| 6 | CD pipeline (Terraform + Ansible) | 20 | Phase 2+5 | IaC, config mgmt, K8s deploy |
| 7 | Code structure & documentation | 10 | All phases | README, clean layout, comments |
| 8 | Bonus: Observability | +10 | Phase 6 | Prometheus, Grafana, dashboards, alerts |
| | **Total** | **100** | | |

---

## Phase 1 — Repository & Environment Setup

**Branch:** `feature/phase1-repo-setup`  
**Status:** ✅ Complete (merged to `main` as `a32fe25`)

Delivered: directory skeleton, engine/cli source copy, `VERSION 0.1.0`, `.gitignore`, `README.md`, design log `0001`.

---

## Phase 2 — AWS Infrastructure (Terraform & Ansible)

**Branch:** `feature/phase2-aws-infra`  
**Points covered:** 20 (CD pipeline — Terraform + Ansible)  
**Estimated effort:** 1–2 sessions  
**Depends on:** Phase 1

### Goals
- Provision a PoC-grade AWS environment: VPC, EKS, and a Jenkins EC2 instance
- Keep costs minimal: single NAT gateway, S3-only state backend (no DynamoDB)
- Use a public EKS API endpoint for simplicity (no bastion, no VPN)
- Jenkins on a dedicated EC2 in the public subnet — fast Docker builds, no local-machine bottleneck
- Ansible configures both the Jenkins host and local kubeconfig

### Architecture

```
VPC: 10.0.0.0/16  (single region, e.g. us-east-1)
├── AZ-A
│   ├── Public Subnet: 10.0.1.0/24   (NAT GW, Jenkins EC2)
│   └── Private Subnet: 10.0.10.0/24  (EKS workers)
├── AZ-B
│   ├── Public Subnet: 10.0.2.0/24   (no NAT — routes via AZ-A NAT)
│   └── Private Subnet: 10.0.20.0/24  (EKS workers)

EKS Cluster:
├── Control Plane (AWS-managed, public API endpoint)
└── Managed Node Group: 2 × t3.medium (private subnets)

Jenkins:  1 × t3.medium EC2 in Public-A (Docker + Jenkins via Ansible)

State: S3 bucket + use_lockfile (no DynamoDB)
```

**Cost-saving choices (vs. original plan):**

| Item | Original | PoC | Monthly saving |
|------|----------|-----|---------------|
| NAT Gateways | 2 (one per AZ) | 1 (AZ-A only) | ~$32 |
| DynamoDB lock table | PAY_PER_REQUEST | Eliminated (S3 native lock via `use_lockfile = true`, Terraform 1.10+) | ~$0.25 + complexity |
| EKS API access | Private + bastion | Public endpoint | No bastion EC2 cost |
| Node count | 3 × t3.medium | 2 × t3.medium | ~$30 |

### Tasks

#### 2.1 Terraform State Bootstrap

> **MANUAL STEP** — Before Terraform can run:
> 1. Create S3 bucket: `seyoawe-tf-state-<account-id>` (versioning ON, public access blocked, SSE-AES256)
> 2. Create IAM user `terraform-deployer` with `AdministratorAccess`
> 3. Generate Access Key + Secret Key
> 4. `aws configure --profile seyoawe-tf`
>
> **No DynamoDB table needed.** Terraform 1.14 uses S3 conditional writes for locking (`use_lockfile = true`).

#### 2.2 Terraform Files (flat layout)

| File | Content |
|------|---------|
| `terraform/backend.tf` | S3 backend with `use_lockfile = true` |
| `terraform/main.tf` | VPC, subnets, IGW, single NAT, route tables, EKS cluster, managed node group, IAM roles, **Jenkins EC2 + security group + key pair** |
| `terraform/variables.tf` | Region, cluster name, instance type, node count, Jenkins AMI, your IP for SSH |
| `terraform/outputs.tf` | Cluster endpoint, kubeconfig command, VPC ID, **Jenkins public IP** |
| `terraform/terraform.tfvars` | Concrete values (gitignored if contains secrets) |

IAM roles (defined directly in `main.tf`):

| Role | Trust principal | Attached policies |
|------|-----------------|-------------------|
| EKS cluster role | `eks.amazonaws.com` | `AmazonEKSClusterPolicy` |
| Node instance role | `ec2.amazonaws.com` | `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly` |

Jenkins EC2 (defined directly in `main.tf`):

| Resource | Details |
|----------|---------|
| Instance | `t3.medium`, Amazon Linux 2023 AMI, public subnet AZ-A |
| Security group | Inbound: 8080 (Jenkins UI) + 22 (SSH) from your IP; outbound: all |
| Key pair | Reference an existing AWS key pair (or create one — manual step) |

No IRSA, no OIDC provider, no service-account-level roles — node role is sufficient for PoC.

#### 2.3 Ansible (post-apply)

| File | Purpose |
|------|---------|
| `ansible/inventory.ini` | Two groups: `[local]` (localhost) and `[jenkins]` (EC2 public IP from Terraform output) |
| `ansible/playbooks/install-tools.yaml` | Ensure `kubectl`, `helm`, `aws-cli` are present on localhost (idempotent) |
| `ansible/playbooks/configure-eks.yaml` | `aws eks update-kubeconfig`, `kubectl get nodes`, create namespaces (`seyoawe`, `monitoring`) |
| `ansible/playbooks/configure-jenkins.yaml` | **On Jenkins EC2:** install Docker, start Jenkins container (`jenkins/jenkins:lts`), open firewall, install `kubectl` + `aws-cli` inside the host so pipelines can deploy to EKS |

No Ansible roles directory — three short playbooks are clearer than role scaffolding.

#### 2.4 Completion Criteria
- [ ] `terraform plan` succeeds with no errors
- [ ] `terraform apply` provisions VPC + EKS + Jenkins EC2
- [ ] `kubectl get nodes` returns 2 healthy `t3.medium` workers
- [ ] Jenkins UI accessible at `http://<jenkins-ec2-ip>:8080`
- [ ] Ansible playbooks run without errors
- [ ] State is remote in S3 (no local `.tfstate`)
- [ ] Committed on `feature/phase2-aws-infra`, pushed

---

## Phase 3 — Containerization (Docker)

**Branch:** `feature/phase3-docker`  
**Points covered:** 10 (Engine containerization) + 10 (CLI testing & packaging)  
**Estimated effort:** 1 session  
**Depends on:** Phase 1

### Goals
- Dockerfiles for Engine and CLI
- CLI unit tests (pytest)
- Local `docker build` + `docker run` validation
- Version injection via `--build-arg`

### Tasks

#### 3.1 Engine Dockerfile (`docker/engine/Dockerfile`)

```
FROM python:3.11-slim
ARG VERSION=dev
LABEL version=${VERSION}
WORKDIR /app
COPY engine/ .
RUN pip install --no-cache-dir requests pyyaml  # module deps
RUN chmod +x run.sh seyoawe.linux
EXPOSE 8080 8081
HEALTHCHECK CMD curl -f http://localhost:8080/health || exit 1
ENTRYPOINT ["./seyoawe.linux"]
```

Build context is repo root; Dockerfile `COPY engine/ .` pulls the whole engine tree.

#### 3.2 CLI Dockerfile (`docker/cli/Dockerfile`)

```
FROM python:3.11-slim
ARG VERSION=dev
LABEL version=${VERSION}
WORKDIR /app
COPY cli/ .
RUN pip install --no-cache-dir -r requirements.txt
ENTRYPOINT ["python", "sawectl.py"]
```

#### 3.3 CLI Unit Tests

Create `cli/tests/test_sawectl.py` with minimum 5 test cases:
- YAML loading (valid + invalid)
- Schema validation pass/fail
- `--help` exits 0
- Version string matches `VERSION` file
- Workflow validation against sample

Run: `pytest cli/tests/ -v`

#### 3.4 Local Testing

```bash
docker build -f docker/engine/Dockerfile -t seyoawe-engine:local --build-arg VERSION=0.1.0 .
docker run -d -p 8080:8080 -p 8081:8081 seyoawe-engine:local
curl http://localhost:8080/health

docker build -f docker/cli/Dockerfile -t seyoawe-cli:local --build-arg VERSION=0.1.0 .
docker run seyoawe-cli:local --help
```

#### 3.5 Completion Criteria
- [ ] Engine image builds and responds on 8080
- [ ] CLI image builds and `--help` works
- [ ] `pytest cli/tests/ -v` passes (minimum 5 cases)
- [ ] Images tagged with version from `VERSION`
- [ ] Committed on `feature/phase3-docker`, pushed

---

## Phase 4 — CI Pipelines (Jenkins)

**Branch:** `feature/phase4-ci-pipelines`  
**Points covered:** 15 (Engine CI) + 10 (CLI CI) + 15 (Version coupling)  
**Estimated effort:** 2 sessions  
**Depends on:** Phase 3

### Goals
- Use the Jenkins EC2 instance provisioned in Phase 2 (configured by Ansible)
- Engine CI pipeline: lint, test, build, push, tag
- CLI CI pipeline: lint, pytest, build, push, tag
- Version coupling: shared `VERSION` file, `scripts/change-detect.sh`, selective builds

### Tasks

#### 4.1 Jenkins Setup (EC2 — already running from Phase 2)

Jenkins should already be running at `http://<jenkins-ec2-ip>:8080` (provisioned by Terraform, configured by Ansible in Phase 2).

> **MANUAL STEP:**
> 1. Open `http://<jenkins-ec2-ip>:8080` in your browser
> 2. Retrieve initial admin password: `ssh ec2-user@<ip> "docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"`
> 3. Install suggested plugins + add: Docker Pipeline, Credentials Binding
> 4. Add credentials:
>    - `dockerhub-creds` — DockerHub username + token
>    - `github-token` — GitHub PAT

#### 4.2 Version Coupling Logic

**`VERSION` file** (repo root): single source of truth, e.g. `0.1.0`.

**`scripts/version.sh`**: Reads `VERSION`, exports as env var.

**`scripts/change-detect.sh`**: Uses `git diff HEAD~1 --name-only`:
- Engine paths: `engine/`, `docker/engine/`
- CLI paths: `cli/`, `docker/cli/`
- VERSION path: `VERSION` → triggers both

| Engine changed | CLI changed | VERSION changed | Action |
|:-:|:-:|:-:|--------|
| Yes | No | No | Build Engine only |
| No | Yes | No | Build CLI only |
| Yes | Yes | * | Build both |
| No | No | Yes | Build both |
| No | No | No | Skip |

#### 4.3 Engine CI (`jenkins/Jenkinsfile.engine`)

Stages: Checkout → Read VERSION → Change Detection → Lint (yamllint on config, shellcheck on scripts) → Docker Build → Docker Push (`$USER/seyoawe-engine:$VER`, `:latest`) → Git Tag (`engine-v$VER`).

#### 4.4 CLI CI (`jenkins/Jenkinsfile.cli`)

Stages: Checkout → Read VERSION → Change Detection → Lint (flake8) → Unit Tests (pytest, JUnit report) → Docker Build → Docker Push (`$USER/seyoawe-cli:$VER`, `:latest`) → Git Tag (`cli-v$VER`).

#### 4.5 DockerHub Setup

> **MANUAL STEP:**
> 1. Create repos on DockerHub: `<username>/seyoawe-engine`, `<username>/seyoawe-cli`
> 2. Generate access token: DockerHub > Account Settings > Security > New Access Token
> 3. Add to Jenkins as `dockerhub-creds`

#### 4.6 Completion Criteria
- [ ] Engine CI: lint → build → push → tag (green)
- [ ] CLI CI: lint → pytest → build → push → tag (green)
- [ ] VERSION change triggers both pipelines
- [ ] Partial change triggers only the affected pipeline
- [ ] Images on DockerHub with correct tags
- [ ] Git tags: `engine-v0.1.0`, `cli-v0.1.0`
- [ ] Committed on `feature/phase4-ci-pipelines`, pushed

---

## Phase 5 — CD Pipeline & Kubernetes Deployment

**Branch:** `feature/phase5-cd-kubernetes`  
**Points covered:** 20 (CD pipeline, reinforces Phase 2)  
**Estimated effort:** 1–2 sessions  
**Depends on:** Phase 2, Phase 4

### Goals
- Deploy Engine to EKS as a StatefulSet with health probes and persistent storage
- Jenkins CD pipeline (running on EC2): Terraform → Ansible → kubectl apply

### K8s Architecture

```
Namespace: seyoawe
├── StatefulSet: seyoawe-engine (replicas: 1)
│   ├── Container: engine (8080, 8081)
│   ├── Liveness Probe:  HTTP GET /health :8080
│   ├── Readiness Probe: HTTP GET /health :8080
│   ├── Volume: /app/logs          (PVC, volumeClaimTemplate)
│   └── Volume: /app/configuration (ConfigMap)
├── Service: seyoawe-engine (ClusterIP → 8080, 8081)
└── ConfigMap: seyoawe-config (config.yaml)
```

Single replica is sufficient for PoC. The StatefulSet kind, PVCs, probes, and ConfigMap mount satisfy all rubric items.

### Tasks

#### 5.1 Kubernetes Manifests

| File | Content |
|------|---------|
| `k8s/namespace.yaml` | Namespaces: `seyoawe`, `monitoring` |
| `k8s/engine/configmap.yaml` | Engine `config.yaml` as ConfigMap |
| `k8s/engine/statefulset.yaml` | StatefulSet with probes, volumeClaimTemplate, resource requests/limits |
| `k8s/engine/service.yaml` | ClusterIP exposing 8080, 8081 |

No separate PVC file — `volumeClaimTemplates` inside the StatefulSet spec handles this automatically.

#### 5.2 CD Pipeline (`jenkins/Jenkinsfile.cd`)

Stages:
1. Checkout
2. Read VERSION
3. Terraform Init + Plan
4. Manual Approval Gate
5. Terraform Apply
6. Ansible: update kubeconfig, verify nodes
7. `kubectl apply -f k8s/namespace.yaml && kubectl apply -f k8s/engine/`
8. `kubectl set image` to new version tag
9. Health verification (`kubectl rollout status`)

#### 5.3 Completion Criteria
- [ ] StatefulSet pod running: `kubectl get pods -n seyoawe`
- [ ] Engine responds to health checks
- [ ] PVC bound, logs persist across pod restart
- [ ] ConfigMap mounted at `/app/configuration`
- [ ] CD pipeline runs end-to-end with approval gate
- [ ] Committed on `feature/phase5-cd-kubernetes`, pushed

---

## Phase 6 — Observability (Bonus)

**Branch:** `feature/phase6-observability`  
**Points covered:** +10 bonus  
**Estimated effort:** 1 session  
**Depends on:** Phase 5

### Goals
- Prometheus + Grafana on EKS using the `kube-prometheus-stack` Helm chart
- Use the **built-in dashboards** that ship with the chart (Kubernetes / Node / Pod)
- Minimal custom config: one values file override

### Tasks

#### 6.1 Install via Helm

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f monitoring/kube-prometheus-values.yaml
```

#### 6.2 Values file (`monitoring/kube-prometheus-values.yaml`)

Override only what matters for PoC:
- Grafana `adminPassword` (or reference a secret)
- `prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues: false` (scrape everything)
- Disable components we don't need to save resources (e.g. `alertmanager.enabled: false` if not needed, but keeping it shows awareness)
- Resource requests tuned low for t3.medium nodes

The chart ships with **~20 pre-built Grafana dashboards** (Kubernetes / Nodes / Pods / Namespaces / etc.). No custom JSON needed — they work immediately and satisfy the rubric.

#### 6.3 Access

> **MANUAL STEP:**
> ```bash
> kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
> ```
> Login: `admin` / password from `kubectl get secret monitoring-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 -d`

#### 6.4 Completion Criteria
- [ ] Prometheus running and scraping cluster metrics
- [ ] Grafana accessible with built-in dashboards showing live data
- [ ] Engine pods visible in Kubernetes dashboards
- [ ] Committed on `feature/phase6-observability`, pushed

---

## PoC Cost Summary

Estimated monthly cost if left running 24/7 in `us-east-1` (tear down after demo to pay nothing):

| Resource | Monthly estimate |
|----------|-----------------|
| EKS control plane | $73 |
| 2 × t3.medium EKS nodes (on-demand) | ~$60 |
| 1 × t3.medium Jenkins EC2 (on-demand) | ~$30 |
| 1 × NAT Gateway + data | ~$35 |
| S3 (state, negligible) | < $1 |
| EBS (PVCs + Jenkins root, ~30 GiB gp3) | ~$3 |
| **Total** | **~$202/month** |

**Recommendation:** Run `terraform destroy` after each working session; re-apply takes ~15 minutes. This brings real cost to a few dollars total.

---

## Phase Checklist & Progress Tracker

| Phase | Branch | Status | Design Log | Merged to Main |
|-------|--------|--------|------------|----------------|
| 1. Repo & Env Setup | `feature/phase1-repo-setup` | ✅ Complete | `0001` | ✅ `a32fe25` |
| 2. AWS Infrastructure | `feature/phase2-aws-infra` | 🔄 In Progress | `0002` | ⬜ |
| 3. Containerization | `feature/phase3-docker` | ⬜ Not Started | ⬜ Required | ⬜ |
| 4. CI Pipelines | `feature/phase4-ci-pipelines` | ⬜ Not Started | ⬜ Required | ⬜ |
| 5. CD & Kubernetes | `feature/phase5-cd-kubernetes` | ⬜ Not Started | ⬜ Required | ⬜ |
| 6. Observability | `feature/phase6-observability` | ⬜ Not Started | ⬜ Required | ⬜ |

---

**End of Master Plan — v2.0 (PoC)**
