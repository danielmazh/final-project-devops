# DevOps Final Project — SeyoAWE Platform

Full DevOps lifecycle implementation around **[SeyoAWE Community](https://github.com/yuribernstein/seyoawe-community)**, a modular workflow automation engine. This project delivers containerization, CI/CD pipelines (Jenkins), AWS infrastructure (Terraform + Ansible), Kubernetes deployment (EKS), and observability (Prometheus + Grafana).

**Current version:** `0.1.1` (see [`VERSION`](./VERSION))  
**GitHub:** [github.com/danielmazh/final-project-devops](https://github.com/danielmazh/final-project-devops)  
**DockerHub:** [danielmazh/seyoawe-engine](https://hub.docker.com/r/danielmazh/seyoawe-engine) | [danielmazh/seyoawe-cli](https://hub.docker.com/r/danielmazh/seyoawe-cli)

---

## Architecture

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
│ engine-v0.1.1│      │  ├── Public-A ── NAT GW + Jenkins EC2 :8080    │
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

---

## Repository Structure

```
final-project-devops/
├── engine/              # SeyoAWE automation engine (binary + config + modules)
├── cli/                 # sawectl CLI tool (Python) + unit tests
├── docker/              # Dockerfiles for engine and CLI
│   ├── engine/Dockerfile
│   └── cli/Dockerfile
├── k8s/                 # Kubernetes manifests (StatefulSet, Service, ConfigMap)
│   ├── namespace.yaml
│   └── engine/
├── terraform/           # AWS infrastructure as code (VPC, EKS, Jenkins EC2)
├── ansible/             # Configuration playbooks (EKS, Jenkins, tools)
├── jenkins/             # CI/CD pipeline definitions
│   ├── Jenkinsfile.engine
│   ├── Jenkinsfile.cli
│   └── Jenkinsfile.cd
├── monitoring/          # Prometheus + Grafana Helm values + ServiceMonitor
├── scripts/             # Version coupling and change detection
├── lifecycle.sh         # AWS resource lifecycle manager (stop/start/destroy)
├── setup-env.sh         # One-command environment bootstrap
├── VERSION              # Semantic version source of truth (0.1.1)
└── requirements-infra.txt
```

Each directory has its own `README.md` with detailed documentation.

---

## Quick Start

### 1. Environment Setup (one-time)

Only **Python 3.10+** and **Docker** are required globally. Everything else is managed inside the project.

```bash
git clone https://github.com/danielmazh/final-project-devops.git
cd final-project-devops
bash setup-env.sh          # creates .venv with all tools
source .venv/bin/activate   # activates terraform, kubectl, helm, aws, ansible
```

### 2. AWS Credentials (one-time)

```bash
aws configure --profile seyoawe-tf
# Credentials are stored in .aws-project/ (gitignored), not ~/.aws/
aws sts get-caller-identity --profile seyoawe-tf
```

### 3. Deploy Infrastructure

```bash
cd terraform
terraform init && terraform plan
terraform apply   # provisions VPC, EKS, Jenkins EC2 (~15 min)
cd ..

# Configure kubectl
aws eks update-kubeconfig --name seyoawe-cluster --region us-east-1 --profile seyoawe-tf

# Run Ansible
ansible-playbook ansible/playbooks/configure-eks.yaml -i ansible/inventory.ini
```

### 4. Deploy Application

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/engine/
kubectl get pods -n seyoawe   # seyoawe-engine-0  1/1  Running
```

### 5. Install Monitoring

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring -f monitoring/kube-prometheus-values.yaml
kubectl apply -f monitoring/servicemonitor-engine.yaml
```

---

## Access Points

| Service | Command | URL |
|---------|---------|-----|
| **Engine API** | `kubectl port-forward svc/seyoawe-engine 8090:8080 -n seyoawe` | `POST http://localhost:8090/api/community/hello-world` |
| **Grafana** | `kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring` | `http://localhost:3000` (admin / seyoawe-grafana) |
| **Prometheus** | `kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring` | `http://localhost:9090/targets` |
| **Jenkins** | Direct access | `http://44.201.6.188:8080` |
| **SSH to Jenkins** | `ssh ec2-user@44.201.6.188 -i ~/keys/devops-key-private-account.pem` | — |

---

## CI/CD Pipelines

Three Jenkins Declarative Pipelines with automatic change detection:

| Pipeline | Trigger | Stages |
|----------|---------|--------|
| **Engine CI** | `engine/` or `VERSION` changes | Lint (yamllint + shellcheck) → Docker Build → Push to DockerHub → Git Tag `engine-v*` |
| **CLI CI** | `cli/` or `VERSION` changes | Lint (flake8) → Unit Tests (13 pytest) → Docker Build → Push → Git Tag `cli-v*` |
| **CD** | Manual trigger | Terraform Plan → Approval Gate → Apply → Ansible → kubectl deploy → Rollout verify |

Changing `VERSION` triggers both CI pipelines simultaneously, ensuring engine and CLI always share the same version.

---

## Cost Management

```bash
./lifecycle.sh status          # show all resources + hourly cost estimate
./lifecycle.sh stop jenkins    # stop Jenkins EC2 billing
./lifecycle.sh stop eks-nodes  # scale EKS nodes to 0
./lifecycle.sh destroy         # full Helm + K8s + Terraform teardown
./lifecycle.sh destroy --all   # above + delete S3 bucket + IAM user (zero footprint)
```

Estimated cost while running: **~$0.27/hr (~$6.50/day)**. Run `terraform destroy` after sessions to minimize cost.

---

## Documentation

| Document | Location |
|----------|----------|
| Master Plan | [`.cursor/plans/0001_devops_final_project_master_plan.md`](.cursor/plans/0001_devops_final_project_master_plan.md) |
| Technical Report | [`.cursor/reports/0001_final_project_technical_report.md`](.cursor/reports/0001_final_project_technical_report.md) |
| Requirements Traceability | [`.cursor/reports/0002_requirements_traceability_report.md`](.cursor/reports/0002_requirements_traceability_report.md) |
| Design Logs (8) | [`.cursor/design-logs/`](.cursor/design-logs/) |
| Architecture Diagrams | [`.cursor/diagrams-mmd/`](.cursor/diagrams-mmd/) (Mermaid) / [`.cursor/diagrams-png/`](.cursor/diagrams-png/) (PNG) |

---

## License

Application content under `engine/` and `cli/` retains upstream [SeyoAWE Community](https://github.com/yuribernstein/seyoawe-community) licensing. This repository adds infrastructure and automation around that application.
