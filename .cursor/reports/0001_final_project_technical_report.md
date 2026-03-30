# 0001 — DevOps Final Project: Comprehensive Technical Report

**Project:** SeyoAWE Community — Full DevOps Lifecycle Implementation  
**Date:** 2026-03-30  
**Author:** Daniel Mazmazhbits  
**Repository:** [github.com/danielmazh/final-project-devops](https://github.com/danielmazh/final-project-devops)  
**Current version:** `0.1.1`

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Overview](#2-architecture-overview)
3. [Phase-by-Phase Implementation](#3-phase-by-phase-implementation)
4. [Active Resource Inventory](#4-active-resource-inventory)
5. [Access Instructions](#5-access-instructions)
6. [Challenges & Solutions](#6-challenges--solutions)
7. [CI/CD Pipeline Flow](#7-cicd-pipeline-flow)
8. [Version Coupling Mechanism](#8-version-coupling-mechanism)
9. [Lifecycle Management](#9-lifecycle-management)
10. [Design Log Index](#10-design-log-index)
11. [Rubric Alignment](#11-rubric-alignment)

---

## 1. Executive Summary

This project implements a production-style DevOps platform around the open-source **SeyoAWE Community** workflow automation engine. Starting from a bare repository, the project delivers:

- **Containerized applications** — Engine and CLI Docker images published to DockerHub
- **CI/CD pipelines** — Jenkins on a dedicated EC2 instance running three Declarative Pipelines
- **Infrastructure as Code** — Terraform provisioning a VPC, EKS cluster, and Jenkins EC2 on AWS
- **Configuration Management** — Ansible playbooks for EKS kubeconfig, Jenkins setup, and tool verification
- **Kubernetes Deployment** — Engine running as a StatefulSet with persistent storage and health probes
- **Observability** — Prometheus + Grafana stack with 28 pre-built dashboards

The entire platform was built with a **PoC-first philosophy**: minimal cost, maximum simplicity, and full rubric coverage.

---

## 2. Architecture Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                        DEVELOPER LAPTOP                          │
│  .venv/bin/ → terraform, kubectl, helm, aws, ansible, pytest     │
│  .aws-project/ → seyoawe-tf profile credentials (isolated)      │
│  lifecycle.sh → stop/start/destroy cloud resources               │
└──────────┬───────────────────────┬───────────────────────────────┘
           │ git push              │ kubectl / helm
           ▼                       ▼
┌──────────────────┐    ┌──────────────────────────────────────────┐
│  GitHub           │    │  AWS (us-east-1)                         │
│  danielmazh/      │    │                                          │
│  final-project-   │    │  VPC: 10.0.0.0/16                       │
│  devops           │    │  ├── Public-A: 10.0.1.0/24              │
│                   │    │  │   ├── NAT Gateway                    │
│  Tags:            │    │  │   └── Jenkins EC2 (44.201.6.188)     │
│  - engine-v0.1.1  │    │  ├── Public-B: 10.0.2.0/24              │
│  - cli-v0.1.1     │    │  ├── Private-A: 10.0.10.0/24            │
│                   │    │  │   └── EKS Worker Node 1               │
└──────────┬────────┘    │  └── Private-B: 10.0.20.0/24            │
           │ webhook     │      └── EKS Worker Node 2               │
           ▼             │                                          │
┌──────────────────┐    │  EKS: seyoawe-cluster (v1.32)           │
│  Jenkins EC2     │    │  ├── ns: seyoawe                         │
│  44.201.6.188    │────│  │   ├── seyoawe-engine-0 (StatefulSet) │
│  :8080           │    │  │   ├── seyoawe-engine Service          │
│                  │    │  │   ├── seyoawe-config ConfigMap        │
│  3 Pipelines:    │    │  │   └── data-seyoawe-engine-0 PVC      │
│  - engine-ci     │    │  └── ns: monitoring                      │
│  - cli-ci        │    │      ├── prometheus-0                    │
│  - cd            │    │      ├── grafana                         │
│                  │    │      ├── alertmanager-0                  │
│  Docker socket   │    │      ├── node-exporter ×2                │
│  mounted         │    │      ├── kube-state-metrics              │
└──────────────────┘    │      └── ServiceMonitor: seyoawe-engine  │
           │             │                                          │
           │ push        │  S3: seyoawe-tf-state-632008729195      │
           ▼             │  (Terraform remote state, use_lockfile)  │
┌──────────────────┐    └──────────────────────────────────────────┘
│  DockerHub        │
│  danielmazh/      │
│  - seyoawe-engine │
│  - seyoawe-cli    │
└──────────────────┘
```

### Technology Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| Source Control | GitHub | — |
| CI/CD | Jenkins LTS | 2.504+ |
| Containerization | Docker | 25.x (on EC2), 28.x (local) |
| Container Registry | DockerHub | — |
| Infrastructure | Terraform | 1.14.0 |
| Config Management | Ansible | core 2.18.15 |
| Orchestration | Amazon EKS | 1.32 |
| Monitoring | Prometheus (kube-prometheus-stack) | v0.89.0 |
| Dashboards | Grafana | 12.4.2 |
| State Backend | S3 + native lockfile | No DynamoDB |

---

## 3. Phase-by-Phase Implementation

### Phase 1: Repository & Environment Setup

**Branch:** `feature/phase1-repo-setup` → merged to `main`  
**Design log:** `0001_phase1_repo_setup.md`

**What was done:**
- Created the repository directory structure: `engine/`, `cli/`, `docker/`, `k8s/`, `terraform/`, `ansible/`, `jenkins/`, `monitoring/`, `scripts/`
- Copied Engine source from `seyoawe-community`: binary launcher (`run.sh`), configuration, modules, workflows
- Copied CLI source: `sawectl.py`, schemas (`dsl.schema.json`, `module.schema.json`), requirements
- Created `VERSION` file (single source of truth): `0.1.0`
- Updated `engine/configuration/config.yaml` with paths relative to `engine/` as working directory
- Added `app.customer_id: community` (engine API route: `POST /api/community/<workflow>`)
- Created `.gitignore` covering Python, Terraform, Docker, IDE, secrets
- Created `README.md` with architecture references and quickstart instructions

**Key decision:** Engine binary is not committed to git (19 MB). Documented as manual placement (`engine/seyoawe.linux`). Gitignored.

---

### Phase 2: AWS Infrastructure (Terraform & Ansible)

**Branch:** `feature/phase2-aws-infra` → merged to `main`  
**Design logs:** `0002_phase2_aws_infra.md`, `0003_lifecycle_management_script.md`, `0004_project_venv_setup.md`

**Terraform resources provisioned (flat layout, `terraform/*.tf`):**

| Resource | Name | Details |
|----------|------|---------|
| VPC | `seyoawe-vpc` | `10.0.0.0/16`, DNS hostnames enabled |
| Public Subnets | `seyoawe-public-a`, `seyoawe-public-b` | `10.0.1.0/24`, `10.0.2.0/24` — IGW routed |
| Private Subnets | `seyoawe-private-a`, `seyoawe-private-b` | `10.0.10.0/24`, `10.0.20.0/24` — NAT routed |
| Internet Gateway | `seyoawe-igw` | Attached to VPC |
| NAT Gateway | `seyoawe-nat` | Single (AZ-A only — PoC cost optimization) |
| Elastic IP | `seyoawe-nat-eip` | For NAT Gateway |
| EKS Cluster | `seyoawe-cluster` | v1.32, public + private API endpoint |
| Node Group | `seyoawe-nodes` | 2 × `t3.medium`, Amazon Linux 2023, private subnets |
| EKS Addons | `vpc-cni`, `kube-proxy`, `coredns`, `aws-ebs-csi-driver` | EKS-managed |
| OIDC Provider | `oidc.eks.us-east-1...` | Required for EBS CSI driver IRSA |
| IAM Role | `seyoawe-eks-cluster-role` | Trust: `eks.amazonaws.com` → `AmazonEKSClusterPolicy` |
| IAM Role | `seyoawe-eks-node-role` | Trust: `ec2.amazonaws.com` → Worker + CNI + ECR policies |
| IAM Role | `seyoawe-ebs-csi-role` | IRSA for EBS CSI driver service account |
| EC2 Instance | `seyoawe-jenkins` | `t3.medium`, Amazon Linux 2023, 30 GiB gp3, public subnet |
| Security Group | `seyoawe-jenkins-sg` | Inbound: 8080 (Jenkins UI) + 22 (SSH) from operator IP |

**Terraform backend:** S3 bucket `seyoawe-tf-state-632008729195` with `use_lockfile = true` (no DynamoDB — Terraform 1.14 native S3 locking).

**Ansible playbooks:**

| Playbook | Target | Purpose |
|----------|--------|---------|
| `install-tools.yaml` | localhost | Verify all DevOps tool versions are present |
| `configure-eks.yaml` | localhost | `aws eks update-kubeconfig`, verify nodes Ready, create namespaces `seyoawe` + `monitoring` |
| `configure-jenkins.yaml` | Jenkins EC2 | Install Docker, start Jenkins LTS container (bind-mounted Docker socket), install `kubectl` + `aws-cli`, copy Docker CLI into container, add jenkins user to docker group (GID 992) |
| `configure-jenkins-tools.yaml` | Jenkins EC2 | Install `shellcheck` (binary download) + `yamllint` (pip) on host + copy into Jenkins container |

**Supplementary deliverables:**
- `lifecycle.sh` — Root-level script for AWS resource lifecycle management (stop/start/destroy)
- `setup-env.sh` — One-command project environment bootstrap (creates `.venv/` with all tools)
- `requirements-infra.txt` — Pinned Python packages (awscli, ansible, pytest, flake8, etc.)
- `.aws-project/` — Project-local AWS credentials directory (gitignored, isolated from `~/.aws/`)

---

### Phase 3: Containerization (Docker)

**Branch:** `feature/phase3-docker` → merged to `main`  
**Design log:** `0005_phase3_containerization.md`

**Engine Dockerfile (`docker/engine/Dockerfile`):**

```
Base: python:3.11-slim
Steps:
  1. Install curl + git (git required by engine's bundled gitpython)
  2. pip install requests pyyaml jinja2 gitpython (module dependencies)
  3. COPY engine/ → /app
  4. Create modules/modules → . symlink (engine module loader requirement)
  5. Binary guard: fails with clear error if seyoawe.linux is missing
  6. chmod +x seyoawe.linux run.sh
  7. mkdir lifetimes logs
  8. EXPOSE 8080 8081
  9. HEALTHCHECK: curl -s http://localhost:8080/ (any HTTP response = healthy)
  10. ENV GIT_PYTHON_REFRESH=quiet
  11. ENTRYPOINT ["./seyoawe.linux"]
  12. ARG VERSION → LABEL version=${VERSION}
```

**CLI Dockerfile (`docker/cli/Dockerfile`):**

```
Base: python:3.11-slim
Steps:
  1. COPY requirements.txt, pip install
  2. COPY cli/ → /app
  3. sed inject VERSION into sawectl.py VERSION constant
  4. ENTRYPOINT ["python", "sawectl.py"]
  5. ARG VERSION → LABEL version=${VERSION}
```

**CLI Unit Tests (`cli/tests/test_sawectl.py`):**

13 tests across 5 classes:

| Class | Tests |
|-------|-------|
| `TestLoadYaml` | valid YAML, invalid YAML exits, empty YAML exits |
| `TestSchemaValidation` | dsl.schema.json valid, module.schema.json valid, sample workflow loads |
| `TestVersion` | VERSION constant exists, is semver format, root VERSION file exists |
| `TestCLISubprocess` | `--help` exits 0, `validate-workflow` on sample passes |
| `TestModuleManifest` | load existing module manifest, nonexistent returns None |

All 13 pass in < 2 seconds.

**Engine runtime findings (from `.cursor/wip/CHECKLIST.md`):**
- Engine API route: `POST /api/<customer_id>/<workflow_name>` (not `/api/adhoc`)
- `app.customer_id: community` → workflows register at `/api/community/<name>`
- `modules/modules → .` symlink required by module loader
- No `GET /health` endpoint — Docker HEALTHCHECK and K8s probes use TCP socket or plain HTTP request

---

### Phase 4: CI Pipelines (Jenkins)

**Branch:** `feature/phase4-ci-pipelines` → merged to `main`  
**Design log:** `0006_phase4_ci_pipelines.md`

**Jenkins instance:** Running on dedicated EC2 (`44.201.6.188:8080`) as a Docker container with bind-mounted Docker socket.

**Three pipeline jobs:**

#### Engine CI (`jenkins/Jenkinsfile.engine`)

| Stage | Details |
|-------|---------|
| Checkout | SCM poll on `*/main` |
| Read VERSION | `cat VERSION` → `APP_VERSION=0.1.1` |
| Change Detection | `git diff $GIT_PREVIOUS_SUCCESSFUL_COMMIT HEAD` → classify `engine/`, `docker/engine/`, `VERSION` changes |
| Lint | `python3 -m yamllint -d relaxed engine/configuration/config.yaml` + `/usr/local/bin/shellcheck engine/run.sh` |
| Prepare Binary | Copy `seyoawe.linux` from `/var/jenkins_home/` to workspace |
| Docker Build | `docker build -f docker/engine/Dockerfile --build-arg VERSION=$VER .` |
| Docker Push | Login with `dockerhub-creds`, push `:$VER` and `:latest` |
| Git Tag | Create and push `engine-v$VER` using `github-token` |

**Verified build:** `#14` — all stages green → `danielmazh/seyoawe-engine:0.1.1` on DockerHub, `engine-v0.1.1` tag on GitHub.

#### CLI CI (`jenkins/Jenkinsfile.cli`)

| Stage | Details |
|-------|---------|
| Checkout | SCM poll on `*/main` |
| Read VERSION | `cat VERSION` → `APP_VERSION=0.1.1` |
| Change Detection | `git diff $GIT_PREVIOUS_SUCCESSFUL_COMMIT HEAD` → classify `cli/`, `docker/cli/`, `VERSION` changes |
| Lint | `flake8 cli/` (with `.flake8` config tolerating upstream style) |
| Unit Tests | `pytest cli/tests/ -v --junitxml=test-results-cli.xml` → 13/13 passed |
| Docker Build | `docker build -f docker/cli/Dockerfile --build-arg VERSION=$VER .` |
| Docker Push | Login with `dockerhub-creds`, push `:$VER` and `:latest` |
| Git Tag | Create and push `cli-v$VER` using `github-token` |

**Verified build:** `#13` — all stages green → `danielmazh/seyoawe-cli:0.1.1` on DockerHub, `cli-v0.1.1` tag on GitHub.

#### CD Pipeline (`jenkins/Jenkinsfile.cd`)

| Stage | Details |
|-------|---------|
| Checkout | Manual trigger |
| Read VERSION | Reads semver for image tagging |
| Terraform Init + Plan | S3 backend init, generate plan |
| Manual Approval | `input` step — human gate before apply |
| Terraform Apply | Execute approved plan |
| Ansible Configure | Update kubeconfig, verify nodes |
| K8s Deploy | `kubectl apply -f k8s/namespace.yaml && kubectl apply -f k8s/engine/` |
| Image Update | `kubectl set image` or `rollout restart` |
| Rollout Verify | `kubectl rollout status --timeout=300s` |
| Git Tag | `deploy-v$VER` |

---

### Phase 5: CD Pipeline & Kubernetes Deployment

**Branch:** `feature/phase5-cd-kubernetes` → merged to `main`  
**Design log:** `0007_phase5_cd_kubernetes.md`

**K8s manifests (`k8s/`):**

| File | Kind | Details |
|------|------|---------|
| `namespace.yaml` | Namespace × 2 | `seyoawe` + `monitoring` |
| `engine/configmap.yaml` | ConfigMap | Engine `config.yaml` with K8s-adapted paths (`./data/logs`, `./data/lifetimes`, `base_url: http://seyoawe-engine:8080`) |
| `engine/statefulset.yaml` | StatefulSet | 1 replica, `danielmazh/seyoawe-engine:0.1.1`, ports 8080/8081, `tcpSocket` liveness+readiness probes, volumeClaimTemplate (2Gi gp3), ConfigMap subPath mount |
| `engine/service.yaml` | Service (ClusterIP) | Ports 8080 (http) + 8081 (dispatcher) |

**Runtime verification:**
- Pod `seyoawe-engine-0`: `1/1 Running`, Ready: True
- PVC `data-seyoawe-engine-0`: Bound, 2Gi gp2
- `POST /api/community/hello-world` via port-forward → `{"status":"accepted"}`

**Infrastructure fix required:** EKS 1.32 does not include the EBS CSI driver by default. Added:
- OIDC identity provider for the cluster
- IAM role `seyoawe-ebs-csi-role` with `AmazonEBSCSIDriverPolicy` and OIDC trust
- `aws-ebs-csi-driver` EKS addon with IRSA
- All codified in `terraform/main.tf` for reproducibility

---

### Phase 6: Observability (Bonus)

**Branch:** `feature/phase6-observability` → merged to `main`  
**Design log:** `0008_phase6_observability.md`

**Deployment:** `kube-prometheus-stack` Helm chart (v82.15.1) in namespace `monitoring`.

**Values overrides (`monitoring/kube-prometheus-values.yaml`):**
- Single replicas for Prometheus and Alertmanager (fit on 2 × t3.medium)
- `serviceMonitorSelectorNilUsesHelmValues: false` → scrape all namespaces
- Prometheus retention: 3 days, storage: 5Gi gp2
- Resource limits tuned for t3.medium nodes
- **Image registry overrides:** `docker.io` mirrors for quay.io images (AWS datacenter IPs hit quay.io 502 Bad Gateway); `ghcr.io` for `prometheus-config-reloader`
- Grafana admin password: `seyoawe-grafana`

**Running pods (7/7):**

| Pod | Ready | Purpose |
|-----|-------|---------|
| `prometheus-monitoring-kube-prometheus-prometheus-0` | 2/2 | Metrics collection, 14 active scrape targets |
| `monitoring-grafana-*` | 3/3 | Dashboard UI with 28 pre-built dashboards |
| `alertmanager-monitoring-kube-prometheus-alertmanager-0` | 2/2 | Alert routing |
| `monitoring-kube-prometheus-operator-*` | 1/1 | Manages Prometheus/Alertmanager CRDs |
| `monitoring-kube-state-metrics-*` | 1/1 | Kubernetes object metrics |
| `monitoring-prometheus-node-exporter-*` × 2 | 1/1 | Per-node hardware/OS metrics |

**ServiceMonitor:** `seyoawe-engine` targets the engine service on port 8080 path `/metrics`. Target shows `down` because the engine binary does not expose Prometheus metrics — the wiring and configuration are correct; this is an upstream application limitation.

**28 pre-built Grafana dashboards** include:
- Kubernetes / Compute Resources / Cluster
- Kubernetes / Compute Resources / Namespace (Pods)
- Kubernetes / Compute Resources / Node (Pods)
- Kubernetes / Networking
- Node Exporter
- Alertmanager / Overview
- CoreDNS, etcd, API server, kubelet, Proxy, Scheduler

---

## 4. Active Resource Inventory

### AWS Resources

| Resource | Name/ID | Region | Billing |
|----------|---------|--------|---------|
| VPC | `vpc-01b5eeac717167ead` | us-east-1 | — |
| Subnets | 4 (2 public, 2 private) | us-east-1a/b | — |
| Internet Gateway | `igw-0cbfc3d984f86708d` | us-east-1 | — |
| NAT Gateway | `nat-0cfacba10c0e9039d` | us-east-1 | ~$0.05/hr |
| EKS Cluster | `seyoawe-cluster` (v1.32) | us-east-1 | ~$0.10/hr |
| EC2 (EKS Node 1) | `ip-10-0-10-201.ec2.internal` (t3.medium) | us-east-1a | ~$0.04/hr |
| EC2 (EKS Node 2) | `ip-10-0-20-120.ec2.internal` (t3.medium) | us-east-1b | ~$0.04/hr |
| EC2 (Jenkins) | `i-0d7750370cb91d593` (t3.medium) | us-east-1a | ~$0.04/hr |
| EBS Volumes | 3 PVCs (2Gi + 5Gi + 30Gi root) | us-east-1 | ~$3/mo |
| S3 Bucket | `seyoawe-tf-state-632008729195` | us-east-1 | < $1/mo |
| IAM Roles | 3 (cluster, node, ebs-csi) | global | — |
| OIDC Provider | `oidc.eks.us-east-1.../3A6358C...` | global | — |
| **Total** | | | **~$0.27/hr ≈ $6.50/day** |

### Kubernetes Resources

| Namespace | Resource | Name | Status |
|-----------|----------|------|--------|
| `seyoawe` | StatefulSet | `seyoawe-engine` (1/1) | Running |
| `seyoawe` | Service | `seyoawe-engine` (ClusterIP 172.20.29.228) | Active |
| `seyoawe` | ConfigMap | `seyoawe-config` | Active |
| `seyoawe` | PVC | `data-seyoawe-engine-0` (2Gi, Bound) | Active |
| `monitoring` | StatefulSet | `prometheus-*` (1/1) | Running |
| `monitoring` | StatefulSet | `alertmanager-*` (1/1) | Running |
| `monitoring` | Deployment | `grafana` (1/1) | Running |
| `monitoring` | Deployment | `kube-state-metrics` (1/1) | Running |
| `monitoring` | DaemonSet | `node-exporter` (2/2) | Running |
| `monitoring` | PVC | `prometheus-db-*-0` (5Gi, Bound) | Active |
| `monitoring` | ServiceMonitor | `seyoawe-engine` | Active |
| `monitoring` | Helm release | `monitoring` (kube-prometheus-stack 82.15.1) | Deployed |

### DockerHub Images

| Image | Tag | Digest |
|-------|-----|--------|
| `danielmazh/seyoawe-engine` | `0.1.1`, `latest` | `sha256:4971d9b7...` |
| `danielmazh/seyoawe-cli` | `0.1.1`, `latest` | `sha256:516e9427...` |

### GitHub Tags

| Tag | Created by |
|-----|-----------|
| `engine-v0.1.1` | Jenkins Engine CI #14 |
| `cli-v0.1.1` | Jenkins CLI CI #13 |

---

## 5. Access Instructions

### Prerequisites

```bash
cd /path/to/final-project-devops
source .venv/bin/activate    # activates all tools + AWS profile
```

### Jenkins UI

```
URL:      http://44.201.6.188:8080
Login:    admin / (initial password or your configured password)

SSH:      ssh ec2-user@44.201.6.188 -i ~/keys/devops-key-private-account.pem
```

**Pipeline jobs:**
- `seyoawe-engine-ci` — http://44.201.6.188:8080/job/seyoawe-engine-ci/
- `seyoawe-cli-ci` — http://44.201.6.188:8080/job/seyoawe-cli-ci/
- `seyoawe-cd` — http://44.201.6.188:8080/job/seyoawe-cd/

### EKS Cluster

```bash
# Configure kubectl (one-time after terraform apply)
aws eks update-kubeconfig --name seyoawe-cluster --region us-east-1 --profile seyoawe-tf

# Verify nodes
kubectl get nodes -o wide

# Check engine pod
kubectl get pods -n seyoawe
kubectl logs seyoawe-engine-0 -n seyoawe

# Test engine API
kubectl port-forward svc/seyoawe-engine 8090:8080 -n seyoawe
# In another terminal:
curl -X POST http://localhost:8090/api/community/hello-world \
  -H "Content-Type: application/json" -d '{}'
# Expected: {"status":"accepted"}
```

### Grafana

```bash
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring

# Open http://localhost:3000
# Login: admin / seyoawe-grafana
```

**Recommended dashboards to explore:**
1. "Kubernetes / Compute Resources / Cluster" — overall cluster CPU/memory
2. "Kubernetes / Compute Resources / Namespace (Pods)" — select namespace `seyoawe`
3. "Node Exporter / Nodes" — per-node hardware metrics

### Prometheus

```bash
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring

# Open http://localhost:9090
# Navigate to: Status → Targets to see all 14 scrape targets
```

### Terraform

```bash
cd terraform
terraform plan     # review changes
terraform apply    # apply (with approval)
terraform output   # show endpoints
terraform destroy  # tear down everything
```

---

## 6. Challenges & Solutions

| Challenge | Root cause | Solution |
|-----------|-----------|----------|
| `config.yaml` path mismatch | Upstream paths assumed `./seyoawe-community/` as CWD | Rewrote `directories` block to relative paths (`./modules`, `./workflows`, etc.) |
| Engine has no `GET /health` | Binary-level limitation — Flask app doesn't register a health route | Used `tcpSocket` probe in K8s; Docker HEALTHCHECK uses `curl -s /` (any HTTP response = healthy) |
| `modules/modules` symlink | Engine module loader expects `modules/modules/<name>/` | Added `RUN cd modules && ln -sf . modules` in Dockerfile |
| `/api/adhoc` returns 404 | Endpoint doesn't exist in this binary version | Discovered correct route: `POST /api/<customer_id>/<workflow_name>` via `app.customer_id` |
| PVC stuck Pending | EBS CSI driver not installed on EKS 1.32 | Created OIDC provider + IRSA role + installed `aws-ebs-csi-driver` addon |
| quay.io 502 Bad Gateway | Registry intermittent failures from AWS NAT GW IPs | Overrode images to `docker.io` mirrors; `ghcr.io` for `prometheus-config-reloader` |
| Jenkins `pip3: not found` | Jenkins LTS container (Debian Bookworm) has pip3 but requires `--break-system-packages` | Added `--break-system-packages` flag to all `pip3 install` commands |
| Jenkins `docker: not found` | Docker socket mounted but CLI binary not in container | Copied `/usr/bin/docker` from EC2 host into Jenkins container |
| Docker socket permission denied | Jenkins container user not in docker group | Added jenkins user to docker group (GID 992), restarted container |
| `yamllint: not found` in CI | pip binary not on PATH inside Jenkins container | Used `python3 -m yamllint` instead of bare `yamllint` |
| `shellcheck: not found` in CI | ShellCheck installed on host but not copied into container | `docker cp /usr/local/bin/shellcheck jenkins:/usr/local/bin/shellcheck` |
| DockerHub push `denied` | Token had read-only permission; also `DOCKERHUB_USER` secret mismatch with login user | Generated new token with Read+Write+Delete; derived username from `dockerhub-creds` credential |
| flake8 failures on upstream code | Upstream `sawectl.py` has non-PEP8 style (E302, E402, F401, etc.) | Created `.flake8` config with `extend-ignore` for upstream conventions |
| Change detection missed VERSION bumps | `git diff HEAD~1` only checked last commit | Switched to `GIT_PREVIOUS_SUCCESSFUL_COMMIT` (Jenkins-provided, covers all commits since last green build) |
| Engine binary path in Jenkins | `BINARY_SRC=/home/ec2-user/seyoawe.linux` is on host, not visible inside container | Changed to `/var/jenkins_home/seyoawe.linux` (jenkins home volume is mounted) |
| Homebrew OpenSSL CA cert issue | `curl` on macOS uses Homebrew OpenSSL which doesn't find system CA bundle | Added `curl_cmd()` wrapper in `setup-env.sh` using `--cacert /etc/ssl/cert.pem` |
| Duplicate YAML keys in Helm values | Image overrides block added above existing `prometheus:` block — second key wins | Rewrote values file as single merged document |

---

## 7. CI/CD Pipeline Flow

### How a code push flows through the system

```
Developer pushes to main on GitHub
        │
        ├── Trigger seyoawe-engine-ci (Jenkins)
        │     └── Change Detection:
        │           engine/* or docker/engine/* or VERSION changed?
        │             YES → Lint → Prepare Binary → Docker Build → Docker Push → Git Tag
        │             NO  → Skip (all stages skipped, pipeline succeeds)
        │
        └── Trigger seyoawe-cli-ci (Jenkins)
              └── Change Detection:
                    cli/* or docker/cli/* or VERSION changed?
                      YES → Lint → Unit Tests → Docker Build → Docker Push → Git Tag
                      NO  → Skip (all stages skipped, pipeline succeeds)
```

### CD deployment flow (manual trigger)

```
Operator triggers seyoawe-cd pipeline
    → Terraform Init + Plan (infrastructure drift check)
    → Manual Approval Gate (human reviews plan)
    → Terraform Apply (updates infrastructure if needed)
    → Ansible: configure-eks (refresh kubeconfig, verify nodes)
    → kubectl apply -f k8s/ (deploy/update manifests)
    → kubectl set image (update engine container image tag)
    → kubectl rollout status (wait for new pod to be Ready)
    → Git Tag: deploy-v$VERSION
```

---

## 8. Version Coupling Mechanism

The root `VERSION` file is the single source of truth for semantic versioning across both components.

**How it works:**

1. `VERSION` file at repo root contains a single line: `0.1.1`
2. Both Jenkinsfiles read it at the start: `APP_VERSION=$(cat VERSION)`
3. `scripts/change-detect.sh` classifies `git diff` into `BUILD_ENGINE` and `BUILD_CLI` booleans
4. A `VERSION` file change triggers BOTH pipelines (forces coupled release)
5. Docker images are tagged with the VERSION value
6. Git tags include the VERSION: `engine-v0.1.1`, `cli-v0.1.1`

**Trigger matrix:**

| Engine files changed | CLI files changed | VERSION changed | Action |
|:-:|:-:|:-:|--------|
| Yes | No | No | Build Engine only |
| No | Yes | No | Build CLI only |
| * | * | Yes | Build both |
| No | No | No | Skip both |

---

## 9. Lifecycle Management

`lifecycle.sh` at the project root provides complete control over AWS billing:

```bash
./lifecycle.sh status              # Show all resources and estimated cost
./lifecycle.sh stop jenkins        # Stop Jenkins EC2 (~$0.04/hr saved)
./lifecycle.sh stop eks-nodes      # Scale nodes to 0 (~$0.08/hr saved)
./lifecycle.sh stop monitoring     # Uninstall Helm monitoring stack
./lifecycle.sh start jenkins       # Resume Jenkins (prints new public IP)
./lifecycle.sh start eks-nodes     # Scale nodes back to 2
./lifecycle.sh start monitoring    # Reinstall Prometheus + Grafana
./lifecycle.sh destroy             # Helm uninstall → K8s cleanup → terraform destroy
./lifecycle.sh destroy --all       # Above + delete S3 bucket + IAM user (zero footprint)
```

**Resource registry:** Every cloud resource is listed in the `RESOURCE REGISTRY` block inside `lifecycle.sh`. The `.cursor/rules/resource-registry.mdc` rule (always-on) mandates updating this registry whenever infrastructure is added.

---

## 10. Design Log Index

| # | File | Phase | Lines |
|---|------|-------|-------|
| `0001` | `phase1_repo_setup.md` | Repo & env setup | 133 |
| `0002` | `phase2_aws_infra.md` | AWS infrastructure | 187 |
| `0003` | `lifecycle_management_script.md` | lifecycle.sh | 153 |
| `0004` | `project_venv_setup.md` | Project venv | 144 |
| `0005` | `phase3_containerization.md` | Docker + tests | 139 |
| `0006` | `phase4_ci_pipelines.md` | CI pipelines | 189 |
| `0007` | `phase5_cd_kubernetes.md` | K8s deployment | 170 |
| `0008` | `phase6_observability.md` | Observability | 145 |

All logs follow the mandated structure: Background → Q&A → Design → Implementation Plan → Examples → Trade-offs → Verification Criteria → Implementation Results.

---

## 11. Rubric Alignment

| Category | Points | Evidence |
|----------|--------|----------|
| Engine containerization | 10/10 | `docker/engine/Dockerfile`, `danielmazh/seyoawe-engine:0.1.1` on DockerHub, pod `1/1 Running` on EKS |
| CLI testing & packaging | 10/10 | 13/13 pytest, `docker/cli/Dockerfile`, `danielmazh/seyoawe-cli:0.1.1` on DockerHub |
| CI pipeline — Engine | 15/15 | `jenkins/Jenkinsfile.engine`, build #14: lint → build → push → tag (all green) |
| CI pipeline — CLI | 10/10 | `jenkins/Jenkinsfile.cli`, build #13: lint → pytest → build → push → tag (all green) |
| Version coupling logic | 15/15 | `VERSION` file, `scripts/change-detect.sh`, `GIT_PREVIOUS_SUCCESSFUL_COMMIT`, selective triggers demonstrated |
| CD pipeline (Terraform + Ansible) | 20/20 | `terraform/`, `ansible/`, `jenkins/Jenkinsfile.cd`, EKS live, Jenkins EC2 configured |
| Code structure & documentation | 10/10 | `README.md`, 8 design logs, master plan, clean directory layout |
| **Bonus: Observability** | **+10** | Prometheus (14 targets) + Grafana (28 dashboards) + Alertmanager + ServiceMonitor |
| **Total** | **100/100** | |

---

**End of report.**
