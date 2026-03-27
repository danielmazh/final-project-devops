# 0001 — DevOps Final Project: Master Plan

**Project:** SeyoAWE Community — Full DevOps Lifecycle Implementation  
**Created:** 2026-03-27  
**Status:** Active  
**Score Target:** 100/100 (including Observability bonus)

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
12. [Phase Checklist & Progress Tracker](#phase-checklist--progress-tracker)

---

## 1. Project Overview

Transform the open-source **SeyoAWE Community** workflow automation engine into a production-grade, fully automated DevOps platform deployed on AWS. The system consists of two components:

| Component | Language | Description |
|-----------|----------|-------------|
| **Engine** | Pre-compiled binary (Flask, ports 8080/8081) | Modular workflow automation runtime. Executes YAML-defined workflows with approvals, Git, Slack, email, API, and chatbot modules. |
| **CLI (`sawectl`)** | Python 3.10+ | Command-line tool to init, validate, and run workflows against the Engine via REST API (`POST /api/adhoc`). |

**Source repo:** `seyoawe-community` (local clone at `~/CProjects/seyoawe-community`)  
**Infrastructure repo:** `final-project-devops` (this repo, `~/CProjects/final-project-devops`)  
**Remote:** GitHub (both repos)

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

When an action requires human execution (AWS console, API tokens, DNS, Jenkins UI), the assistant MUST:
1. **STOP** automated execution
2. Provide explicit step-by-step instructions with links and expected values
3. **WAIT** for user confirmation ("done") before proceeding

Examples of manual steps:
- Creating AWS IAM users/access keys
- Generating GitHub/DockerHub API tokens
- Configuring Jenkins plugins via UI
- Setting up DNS records
- Creating S3 buckets for Terraform state (if not bootstrapped)

---

## 3. Source Application Summary

### Engine
- **Binary:** `seyoawe.linux` / `seyoawe.macos.arm` (not included in git — must be downloaded from GitHub releases or built externally)
- **Launcher:** `run.sh` (selects binary by OS)
- **Config:** `configuration/config.yaml` (ports, directories, module defaults)
- **Ports:** 8080 (app), 8081 (module dispatcher)
- **Directories used at runtime:** `modules/`, `workflows/`, `lifetimes/`, `logs/`
- **Health endpoint:** `GET /health` on port 8080 (per K8s diagram probes)

### CLI (`sawectl`)
- **Entry:** `sawectl/sawectl.py`
- **Deps:** `sawectl/requirements.txt` → `pyyaml`, `jsonschema`, `requests`, `argparse`
- **Version constant:** `VERSION = "0.0.1"` (in `sawectl.py`)
- **Key commands:** `init`, `validate-workflow`, `validate-modules`, `run`, `list-modules`, `module create`
- **Engine interaction:** `requests.post(f"http://{server}/api/adhoc", json={"workflow": ...})`

### Shared Contracts
- Workflow YAML validated by `sawectl/dsl.schema.json`
- Module manifests validated by `sawectl/module.schema.json`
- Both rely on `modules/` directory and `configuration/config.yaml`

---

## 4. Target Repository Structure

```
final-project-devops/
├── engine/                          # Engine source + binary + config
│   ├── seyoawe.linux                # Engine binary (Linux)
│   ├── run.sh                       # Launcher script
│   ├── configuration/
│   │   └── config.yaml              # Runtime configuration
│   ├── modules/                     # Built-in Python modules
│   └── workflows/                   # Sample workflows
│       └── samples/
├── cli/                             # CLI source
│   ├── sawectl.py                   # CLI entry point
│   ├── requirements.txt             # Python dependencies
│   ├── dsl.schema.json              # Workflow schema
│   ├── module.schema.json           # Module schema
│   └── tests/                       # Unit tests for CLI
│       ├── __init__.py
│       ├── test_sawectl.py
│       └── conftest.py
├── docker/                          # Dockerfiles
│   ├── engine/
│   │   └── Dockerfile
│   └── cli/
│       └── Dockerfile
├── k8s/                             # Kubernetes manifests
│   ├── namespace.yaml
│   ├── engine/
│   │   ├── statefulset.yaml
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   └── pvc.yaml
│   └── jenkins/
│       ├── statefulset.yaml
│       ├── service.yaml
│       └── pvc.yaml
├── terraform/                       # IaC — AWS provisioning
│   ├── environments/
│   │   └── dev/
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       ├── terraform.tfvars
│   │       └── backend.tf
│   └── modules/
│       ├── vpc/
│       ├── eks/
│       ├── iam/
│       └── s3-backend/
├── ansible/                         # Configuration management
│   ├── inventory/
│   │   └── aws_hosts.ini
│   ├── playbooks/
│   │   ├── configure-eks.yaml
│   │   └── install-tools.yaml
│   └── roles/
│       ├── kubectl/
│       └── helm/
├── jenkins/                         # Pipeline definitions
│   ├── Jenkinsfile.engine           # Engine CI pipeline
│   ├── Jenkinsfile.cli              # CLI CI pipeline
│   ├── Jenkinsfile.cd               # CD pipeline
│   └── shared-libs/                 # Shared pipeline functions
│       └── vars/
│           ├── versionCoupling.groovy
│           └── changeDetection.groovy
├── monitoring/                      # Observability stack
│   ├── prometheus/
│   │   ├── prometheus-values.yaml   # Helm values
│   │   └── alerting-rules.yaml
│   └── grafana/
│       ├── grafana-values.yaml
│       └── dashboards/
│           └── seyoawe-dashboard.json
├── scripts/                         # Build/version helper scripts
│   ├── version.sh                   # Version coupling logic
│   ├── change-detect.sh             # Git diff change detection
│   └── bump-version.sh              # Semantic version bumper
├── VERSION                          # Single source of truth for semver
├── README.md                        # Project documentation
├── .gitignore
├── .cursor/                         # Administrative files
│   ├── plans/
│   ├── design-logs/
│   ├── helpers-scripts/
│   ├── logs/
│   ├── wip/
│   ├── rules/
│   ├── diagrams-mmd/
│   └── diagrams-png/
└── .instructions/                   # Course assignment materials
```

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
**Points covered:** 10 (Code structure & documentation — foundation)  
**Estimated effort:** 1–2 sessions

### Goals
- Structure the `final-project-devops` repo with the directory layout from Section 4
- Copy Engine and CLI source from `seyoawe-community` into the correct locations
- Create the `VERSION` file (initial `0.1.0`)
- Initialize `.gitignore` for the project
- Write a project `README.md`
- Verify the engine runs locally (if binary is available)

### Tasks

#### 1.1 Create Directory Skeleton
Create all top-level directories:
```
engine/, cli/, docker/engine/, docker/cli/, k8s/engine/, k8s/jenkins/,
terraform/environments/dev/, terraform/modules/vpc/, terraform/modules/eks/,
terraform/modules/iam/, terraform/modules/s3-backend/,
ansible/inventory/, ansible/playbooks/, ansible/roles/,
jenkins/shared-libs/vars/, monitoring/prometheus/, monitoring/grafana/dashboards/,
scripts/
```

#### 1.2 Copy Source from `seyoawe-community`
- `engine/`: Copy `run.sh`, `configuration/`, `modules/`, `workflows/`
- `cli/`: Copy `sawectl.py`, `requirements.txt`, `dsl.schema.json`, `module.schema.json`
- **Engine binary:** Check GitHub releases for `seyoawe.linux`. If unavailable, document as a manual step. For Docker builds, the binary must be present.

#### 1.3 Create VERSION File
```
0.1.0
```
Single line, no trailing content. This is the single source of truth for semantic versioning across both Engine and CLI.

#### 1.4 Create .gitignore
Cover: Python (`__pycache__`, `.venv`, `*.pyc`), Terraform (`.terraform/`, `*.tfstate*`, `*.tfvars` with secrets), Docker, IDE files, OS files, secrets (`*.pem`, `.env`).

#### 1.5 Create README.md
Project overview, architecture diagram reference, directory structure explanation, quickstart instructions, tooling prerequisites.

#### 1.6 Prerequisites Verification

> **MANUAL STEP** — The following tools must be installed locally:

| Tool | Minimum Version | Check Command |
|------|----------------|---------------|
| Docker | 24+ | `docker --version` |
| kubectl | 1.28+ | `kubectl version --client` |
| Terraform | 1.5+ | `terraform --version` |
| Ansible | 2.15+ | `ansible --version` |
| AWS CLI | 2.x | `aws --version` |
| Python | 3.10+ | `python3 --version` |
| Jenkins (local or remote) | 2.400+ | N/A |
| Helm | 3.x | `helm version` |

#### 1.7 Completion Criteria
- [ ] All directories exist and are not empty (contain at least `.gitkeep` or real files)
- [ ] Engine source + config copied correctly
- [ ] CLI source + deps copied correctly
- [ ] `VERSION` file exists with `0.1.0`
- [ ] `.gitignore` covers all tool artifacts
- [ ] `README.md` is present and informative
- [ ] Commit on `feature/phase1-repo-setup`, pushed to origin

---

## Phase 2 — AWS Infrastructure (Terraform & Ansible)

**Branch:** `feature/phase2-aws-infra`  
**Points covered:** 20 (CD pipeline — Terraform + Ansible)  
**Estimated effort:** 2–3 sessions  
**Depends on:** Phase 1

### Goals
- Provision a production-style AWS environment: VPC, subnets (public/private, multi-AZ), NAT gateways, Internet Gateway, security groups
- Deploy an EKS cluster with a managed node group
- Configure S3 + DynamoDB for Terraform remote state
- Use Ansible to install/configure tooling on the bastion or configure kubeconfig
- All infrastructure is code — repeatable, destroyable, idempotent

### Architecture (per diagram 005)
```
VPC: 10.0.0.0/16
├── AZ-A
│   ├── Public Subnet: 10.0.1.0/24  (NAT GW, bastion)
│   └── Private Subnet: 10.0.10.0/24 (EKS worker nodes)
├── AZ-B
│   ├── Public Subnet: 10.0.2.0/24  (NAT GW)
│   └── Private Subnet: 10.0.20.0/24 (EKS worker nodes)
EKS Cluster:
├── Control Plane (AWS-managed)
└── Managed Node Group: 2–3 × t3.medium
```

### Tasks

#### 2.1 Terraform State Bootstrap

> **MANUAL STEP** — Before Terraform can run:
> 1. Create an S3 bucket for state: `seyoawe-tf-state-<account-id>`
> 2. Create a DynamoDB table for locking: `seyoawe-tf-lock` (partition key: `LockID`, type String)
> 3. Create an IAM user `terraform-deployer` with AdministratorAccess (or scoped policy)
> 4. Generate Access Key + Secret Key, store securely
> 5. Configure AWS CLI: `aws configure --profile seyoawe-tf`

#### 2.2 Terraform Modules

| Module | Path | Resources |
|--------|------|-----------|
| `vpc` | `terraform/modules/vpc/` | VPC, subnets (2 public, 2 private), IGW, NAT GWs, route tables |
| `eks` | `terraform/modules/eks/` | EKS cluster, managed node group, OIDC provider, addons (CoreDNS, kube-proxy, vpc-cni) |
| `iam` | `terraform/modules/iam/` | EKS cluster role, node instance role, Jenkins IRSA |
| `s3-backend` | `terraform/modules/s3-backend/` | (Documentation only — bootstrapped manually) |

#### 2.3 Terraform Environment Config
- `terraform/environments/dev/main.tf` — root module wiring all child modules
- `terraform/environments/dev/variables.tf` — parameterized (region, instance types, cluster name)
- `terraform/environments/dev/backend.tf` — S3 remote backend config
- `terraform/environments/dev/outputs.tf` — cluster endpoint, kubeconfig command, VPC ID

#### 2.4 Ansible Playbooks
- `ansible/playbooks/install-tools.yaml` — Install `kubectl`, `helm`, `aws-cli` on bastion/local
- `ansible/playbooks/configure-eks.yaml` — Update kubeconfig, verify cluster access, apply initial namespaces

#### 2.5 Completion Criteria
- [ ] `terraform plan` succeeds with no errors
- [ ] `terraform apply` provisions VPC + EKS (or can be demonstrated)
- [ ] `kubectl get nodes` returns healthy worker nodes
- [ ] Ansible playbook runs without errors
- [ ] All state is remote (S3 + DynamoDB)
- [ ] Committed on `feature/phase2-aws-infra`, pushed

---

## Phase 3 — Containerization (Docker)

**Branch:** `feature/phase3-docker`  
**Points covered:** 10 (Engine containerization) + 10 (CLI testing & packaging)  
**Estimated effort:** 1–2 sessions  
**Depends on:** Phase 1

### Goals
- Write production-quality Dockerfiles for Engine and CLI
- Implement CLI unit tests (pytest)
- Test containers locally with `docker run` and `docker-compose`
- Ensure version injection via build args

### Tasks

#### 3.1 Engine Dockerfile (`docker/engine/Dockerfile`)
```
Base: python:3.11-slim (or ubuntu:22.04 for binary compatibility)
Strategy:
  1. Copy engine binary (seyoawe.linux)
  2. Copy configuration/, modules/, workflows/
  3. Install Python deps for modules (each module may have its own requirements)
  4. Expose ports 8080, 8081
  5. HEALTHCHECK: curl /health
  6. ENTRYPOINT: ./seyoawe.linux
  7. ARG VERSION → LABEL version=${VERSION}
```

#### 3.2 CLI Dockerfile (`docker/cli/Dockerfile`)
```
Base: python:3.11-slim
Strategy:
  1. Copy cli/ source
  2. pip install -r requirements.txt
  3. ARG VERSION → inject into sawectl.py or env var
  4. ENTRYPOINT: python sawectl.py
```

#### 3.3 CLI Unit Tests
- Create `cli/tests/test_sawectl.py`
- Test: schema validation, workflow loading, version display, error handling
- Run with: `pytest cli/tests/ -v`

#### 3.4 Local Testing
```bash
# Engine
docker build -f docker/engine/Dockerfile -t seyoawe-engine:local --build-arg VERSION=0.1.0 .
docker run -p 8080:8080 -p 8081:8081 seyoawe-engine:local
# Verify: curl http://localhost:8080/health

# CLI
docker build -f docker/cli/Dockerfile -t seyoawe-cli:local --build-arg VERSION=0.1.0 .
docker run seyoawe-cli:local --help
```

#### 3.5 Completion Criteria
- [ ] Engine Docker image builds and runs (responds on 8080)
- [ ] CLI Docker image builds and runs (`--help` works)
- [ ] Unit tests pass: `pytest cli/tests/ -v` (minimum 5 test cases)
- [ ] Images tagged with version from `VERSION` file
- [ ] Committed on `feature/phase3-docker`, pushed

---

## Phase 4 — CI Pipelines (Jenkins)

**Branch:** `feature/phase4-ci-pipelines`  
**Points covered:** 15 (Engine CI) + 10 (CLI CI) + 15 (Version coupling)  
**Estimated effort:** 2–3 sessions  
**Depends on:** Phase 3

### Goals
- Set up Jenkins (locally or on EKS)
- Create CI pipeline for Engine: lint, test, build, version-tag, push to DockerHub
- Create CI pipeline for CLI: lint, pytest, build, version-tag, push to DockerHub
- Implement version coupling: shared `VERSION` file, change detection, selective builds
- Implement semantic versioning and git tagging

### Tasks

#### 4.1 Jenkins Setup

> **MANUAL STEP** — Jenkins must be running and accessible:
> - Option A: Local Jenkins via Docker
> - Option B: Jenkins on EKS (deployed in Phase 5)
> 
> Required plugins: Pipeline, Git, Docker Pipeline, Credentials Binding, Blue Ocean (optional)
> 
> Required credentials (configure in Jenkins > Manage > Credentials):
> 1. `dockerhub-creds` — DockerHub username + token
> 2. `github-token` — GitHub personal access token
> 3. `aws-credentials` — AWS access key + secret (for CD pipeline later)

#### 4.2 Version Coupling Logic

**`VERSION` file** (repo root): Single source of truth, e.g., `0.1.0`

**`scripts/version.sh`**: Reads VERSION, exports as env var, injects into Docker builds and CLI source.

**`scripts/change-detect.sh`**: Uses `git diff HEAD~1 --name-only` to classify changes:
- Engine paths: `engine/`, `docker/engine/`, `configuration/`
- CLI paths: `cli/`, `docker/cli/`
- VERSION path: `VERSION` → triggers both

**Trigger matrix:**
| Engine changed | CLI changed | VERSION changed | Action |
|:-:|:-:|:-:|--------|
| Yes | No | No | Build Engine only |
| No | Yes | No | Build CLI only |
| Yes | Yes | * | Build both |
| No | No | Yes | Build both (version bump) |
| No | No | No | Skip builds |

#### 4.3 Engine CI Pipeline (`jenkins/Jenkinsfile.engine`)
```
Stages:
  1. Checkout
  2. Read VERSION
  3. Change Detection (skip if no engine changes)
  4. Lint (shellcheck for scripts, yamllint for config)
  5. Test (engine health check in temp container)
  6. Docker Build (--build-arg VERSION=$VER)
  7. Docker Push to DockerHub ($DOCKERHUB_USER/seyoawe-engine:$VER, :latest)
  8. Git Tag (engine-v$VER)
```

#### 4.4 CLI CI Pipeline (`jenkins/Jenkinsfile.cli`)
```
Stages:
  1. Checkout
  2. Read VERSION
  3. Change Detection (skip if no CLI changes)
  4. Lint (flake8 / pylint)
  5. Unit Tests (pytest with JUnit report)
  6. Docker Build (--build-arg VERSION=$VER)
  7. Docker Push to DockerHub ($DOCKERHUB_USER/seyoawe-cli:$VER, :latest)
  8. Git Tag (cli-v$VER)
```

#### 4.5 DockerHub Setup

> **MANUAL STEP:**
> 1. Create DockerHub account (if not existing)
> 2. Create repositories: `<username>/seyoawe-engine`, `<username>/seyoawe-cli`
> 3. Generate an access token: DockerHub > Account Settings > Security > New Access Token
> 4. Add to Jenkins as `dockerhub-creds` (Username with password)

#### 4.6 Completion Criteria
- [ ] Engine CI pipeline: lint → test → build → push → tag (green)
- [ ] CLI CI pipeline: lint → pytest → build → push → tag (green)
- [ ] Version coupling: VERSION file change triggers both pipelines
- [ ] Change detection: only affected pipeline triggers on partial changes
- [ ] Images visible on DockerHub with correct version tags
- [ ] Git tags created: `engine-v0.1.0`, `cli-v0.1.0`
- [ ] Committed on `feature/phase4-ci-pipelines`, pushed

---

## Phase 5 — CD Pipeline & Kubernetes Deployment

**Branch:** `feature/phase5-cd-kubernetes`  
**Points covered:** 20 (CD pipeline) — reinforces Phase 2  
**Estimated effort:** 2–3 sessions  
**Depends on:** Phase 2, Phase 4

### Goals
- Deploy Engine to Kubernetes as a StatefulSet
- Implement health probes, persistent storage, service configuration
- Create a Jenkins CD pipeline that provisions infra (Terraform), configures (Ansible), and deploys (kubectl/helm)

### Architecture (per diagram 006)
```
Namespace: seyoawe
├── StatefulSet: seyoawe-engine (replicas: 2)
│   ├── Container: engine (ports: 8080, 8081)
│   ├── Liveness Probe: HTTP GET /health :8080
│   ├── Readiness Probe: HTTP GET /health :8080
│   ├── Volume: /app/logs (PVC)
│   └── Volume: /app/configuration (ConfigMap)
├── Service: seyoawe-engine (ClusterIP → 8080, 8081)
├── ConfigMap: seyoawe-config (config.yaml)
└── PVCs: data-seyoawe-engine-{0,1}

Namespace: jenkins
├── StatefulSet: jenkins-controller
├── Service: jenkins (8080)
└── PVC: jenkins-home
```

### Tasks

#### 5.1 Kubernetes Manifests
| File | Content |
|------|---------|
| `k8s/namespace.yaml` | Namespaces: `seyoawe`, `jenkins`, `monitoring` |
| `k8s/engine/configmap.yaml` | Engine `config.yaml` as ConfigMap |
| `k8s/engine/statefulset.yaml` | StatefulSet with probes, volume mounts, resource limits |
| `k8s/engine/service.yaml` | ClusterIP service exposing 8080, 8081 |
| `k8s/engine/pvc.yaml` | VolumeClaimTemplates for logs/lifetimes |
| `k8s/jenkins/statefulset.yaml` | Jenkins controller deployment |
| `k8s/jenkins/service.yaml` | Jenkins service (8080 + 50000 for agents) |
| `k8s/jenkins/pvc.yaml` | Jenkins home persistent volume |

#### 5.2 CD Pipeline (`jenkins/Jenkinsfile.cd`)
```
Stages:
  1. Checkout
  2. Read VERSION
  3. Terraform Init + Plan (terraform/environments/dev/)
  4. Manual Approval Gate (for terraform apply)
  5. Terraform Apply
  6. Ansible Configure (update kubeconfig, install tools)
  7. Kubernetes Deploy:
     a. kubectl apply -f k8s/namespace.yaml
     b. kubectl apply -f k8s/engine/
     c. Update image tag: kubectl set image statefulset/seyoawe-engine engine=$IMAGE:$VER
  8. Health Verification (kubectl rollout status, curl /health)
  9. Git Tag (deploy-v$VER)
```

#### 5.3 Completion Criteria
- [ ] StatefulSet pods running: `kubectl get pods -n seyoawe`
- [ ] Engine responds to health checks inside cluster
- [ ] PVCs bound and logs persisting across pod restarts
- [ ] ConfigMap mounted correctly at `/app/configuration`
- [ ] CD pipeline executes end-to-end (with approval gate)
- [ ] Committed on `feature/phase5-cd-kubernetes`, pushed

---

## Phase 6 — Observability (Bonus)

**Branch:** `feature/phase6-observability`  
**Points covered:** +10 bonus  
**Estimated effort:** 1–2 sessions  
**Depends on:** Phase 5

### Goals
- Deploy Prometheus to scrape Engine metrics
- Deploy Grafana with pre-configured dashboards
- Set up alerting rules for critical conditions
- All deployed in the `monitoring` namespace on EKS

### Architecture (per diagram 008)
```
Namespace: monitoring
├── Prometheus (StatefulSet, scrapes seyoawe-engine:8080/metrics)
├── Grafana (Deployment, port 3000)
├── Alertmanager (Deployment)
└── ServiceMonitor: seyoawe-engine
```

### Tasks

#### 6.1 Prometheus Setup
- Use Helm chart: `prometheus-community/kube-prometheus-stack`
- Custom values: `monitoring/prometheus/prometheus-values.yaml`
- ServiceMonitor targeting `seyoawe-engine` service on port 8080
- Alerting rules: `monitoring/prometheus/alerting-rules.yaml`
  - Pod restart count > 3 in 5m
  - Engine response time > 5s
  - Pod not ready for > 2m

#### 6.2 Grafana Dashboards
- `monitoring/grafana/dashboards/seyoawe-dashboard.json`
- Panels: request rate, error rate, response latency, pod status, CPU/memory usage
- Data source: auto-provisioned Prometheus

#### 6.3 Access

> **MANUAL STEP:**
> - Port-forward Grafana: `kubectl port-forward svc/grafana 3000:3000 -n monitoring`
> - Default login: admin / (retrieve from secret)
> - Import dashboard from JSON

#### 6.4 Completion Criteria
- [ ] Prometheus scraping Engine metrics
- [ ] Grafana dashboard shows live data
- [ ] Alert rules configured and visible
- [ ] Committed on `feature/phase6-observability`, pushed

---

## Phase Checklist & Progress Tracker

| Phase | Branch | Status | Design Log | Merged to Main |
|-------|--------|--------|------------|----------------|
| 1. Repo & Env Setup | `feature/phase1-repo-setup` | ⬜ Not Started | — | ⬜ |
| 2. AWS Infrastructure | `feature/phase2-aws-infra` | ⬜ Not Started | ⬜ Required | ⬜ |
| 3. Containerization | `feature/phase3-docker` | ⬜ Not Started | ⬜ Required | ⬜ |
| 4. CI Pipelines | `feature/phase4-ci-pipelines` | ⬜ Not Started | ⬜ Required | ⬜ |
| 5. CD & Kubernetes | `feature/phase5-cd-kubernetes` | ⬜ Not Started | ⬜ Required | ⬜ |
| 6. Observability | `feature/phase6-observability` | ⬜ Not Started | ⬜ Required | ⬜ |

### Legend
- ⬜ Not Started
- 🔄 In Progress
- ✅ Complete
- ⛔ Blocked

---

**End of Master Plan — v1.0**

*Next action: Confirm readiness to begin Phase 1.*
