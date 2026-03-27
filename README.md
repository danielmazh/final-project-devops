# DevOps Final Project — SeyoAWE Platform

Production-style DevOps lifecycle around **[SeyoAWE Community](https://github.com/yuribernstein/seyoawe-community)**: containerization, CI/CD (Jenkins), AWS provisioning (Terraform), configuration (Ansible), Kubernetes deployment, and observability (Prometheus & Grafana).

**Current release (semver source of truth):** see the root [`VERSION`](./VERSION) file.

## Architecture references

High-level diagrams live under [`.cursor/diagrams-mmd/`](.cursor/diagrams-mmd/) (Mermaid source) and [`.cursor/diagrams-png/`](.cursor/diagrams-png/) (exports). Start with:

| Diagram | Topic |
|---------|--------|
| `001_Architecture_Overview.mmd` | GitHub, Jenkins, Docker Hub, Terraform, Ansible, EKS |
| `005_AWS_Infrastructure.mmd` | VPC, subnets, EKS, IAM, state backend |
| `006_Kubernetes_Deployment.mmd` | StatefulSet, Services, ConfigMaps, PVCs, probes |
| `007_Version_Coupling.mmd` | `VERSION` file, change detection, image tags |

Course requirements and rubric: [`.instructions/final_project.md`](.instructions/final_project.md).

## Repository layout

| Path | Purpose |
|------|---------|
| `engine/` | SeyoAWE engine: `run.sh`, `configuration/`, `modules/`, `workflows/`, runtime dirs `lifetimes/`, `logs/`. Place **`seyoawe.linux`** (or macOS binary) here manually — not shipped in git. |
| `cli/` | `sawectl` CLI (`sawectl.py`, schemas, `requirements.txt`). |
| `docker/` | Dockerfiles (Phase 3). |
| `k8s/` | Kubernetes manifests (Phase 5). |
| `terraform/` | AWS infrastructure as code (Phase 2). |
| `ansible/` | Playbooks and inventory (Phase 2). |
| `jenkins/` | `Jenkinsfile*` and shared pipeline libs (Phase 4–5). |
| `monitoring/` | Prometheus / Grafana config (Phase 6). |
| `.cursor/` | Plans, design logs, rules, diagrams — **administrative** artifacts. |

## Local quickstart (CLI)

```bash
cd cli
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python sawectl.py --help
```

Validate a workflow (from repo root, paths relative to `engine/`):

```bash
python cli/sawectl.py validate-workflow engine/workflows/samples/<workflow>.yaml \
  --modules-path engine/modules
```

## Local quickstart (Engine)

1. Obtain **`seyoawe.linux`** (Linux) or **`seyoawe.macos.arm`** (Apple Silicon) per project instructions / upstream releases and copy it into `engine/`.
2. From `engine/`:

```bash
cd engine
chmod +x run.sh seyoawe.linux   # or seyoawe.macos.arm
./run.sh linux                  # or: ./run.sh macos
```

The app listens on **8080** (HTTP) and **8081** (module dispatcher) per `configuration/config.yaml`.

## Tooling prerequisites

Minimum versions align with the master plan in [`.cursor/plans/0001_devops_final_project_master_plan.md`](.cursor/plans/0001_devops_final_project_master_plan.md):

| Tool | Minimum | Check |
|------|---------|--------|
| Docker | 24+ | `docker --version` |
| kubectl | 1.28+ | `kubectl version --client` |
| Terraform | 1.5+ | `terraform --version` |
| Ansible | 2.15+ | `ansible --version` |
| AWS CLI | 2.x | `aws --version` |
| Python | 3.10+ | `python3 --version` |
| Helm | 3.x | `helm version` |

Jenkins is used in later phases (local or on-cluster).

## Git workflow

Work on feature branches; do not commit directly to `main`. Merge each phase after review.

## License

Application content under `engine/` and `cli/` retains upstream **SeyoAWE Community** licensing. This repository adds infrastructure and automation around that application.
