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

## Quickstart — one-time environment setup

All tools (Terraform, kubectl, Helm, AWS CLI, Ansible, pytest, flake8) are managed inside a project-local Python venv. Only **Python 3.10+** and **Docker** need to be installed globally.

**Step 1 — run the setup script (one time per machine):**

```bash
bash setup-env.sh
```

This creates `.venv/`, downloads all Go binaries into `.venv/bin/`, and creates `.aws-project/` for project-local AWS credentials.

**Step 2 — activate the environment (every new terminal session):**

```bash
source .venv/bin/activate
```

After activation: `terraform`, `kubectl`, `helm`, `aws`, `ansible`, `pytest`, `flake8` are all on your `PATH`, pinned to the project's versions.

**Step 3 — configure AWS credentials (one time):**

```bash
aws configure --profile seyoawe-tf
```

Credentials are written to `.aws-project/credentials` (gitignored), not to `~/.aws/`.  
Verify with: `aws sts get-caller-identity --profile seyoawe-tf`

**Tool versions bundled by `setup-env.sh`:**

| Tool | Version | Type |
|------|---------|------|
| Terraform | 1.14.0 | Downloaded binary → `.venv/bin/` |
| kubectl | v1.34.1 | Downloaded binary → `.venv/bin/` |
| Helm | v3.17.0 | Downloaded binary → `.venv/bin/` |
| AWS CLI | 1.38.x | pip (`requirements-infra.txt`) |
| Ansible | 11.3.x | pip (`requirements-infra.txt`) |
| pytest / flake8 | 8.3.x / 7.2.x | pip (`requirements-infra.txt`) |

Only Docker must be installed separately (required for container builds).

---

## CLI quickstart (after venv is active)

```bash
python cli/sawectl.py --help
python cli/sawectl.py validate-workflow engine/workflows/samples/scheduled_api_watchdog.yaml \
  --modules engine/modules
```

## Engine quickstart

1. Obtain **`seyoawe.linux`** (Linux) or **`seyoawe.macos.arm`** (Apple Silicon) from upstream releases and copy it into `engine/`.
2. From `engine/`:

```bash
cd engine
chmod +x run.sh seyoawe.linux
./run.sh linux    # or: ./run.sh macos
```

The app listens on **8080** (HTTP) and **8081** (module dispatcher).

## AWS Lifecycle management

Use `lifecycle.sh` to suspend or destroy cloud resources to avoid unnecessary billing:

```bash
./lifecycle.sh status          # see what's running and estimated cost
./lifecycle.sh stop jenkins    # stop Jenkins EC2 billing
./lifecycle.sh stop eks-nodes  # scale EKS nodes to 0
./lifecycle.sh destroy         # full Terraform + Helm + K8s teardown
./lifecycle.sh destroy --all   # + remove S3 state bucket and IAM user
```

## Git workflow

Work on feature branches; do not commit directly to `main`. Merge each phase after review.

## License

Application content under `engine/` and `cli/` retains upstream **SeyoAWE Community** licensing. This repository adds infrastructure and automation around that application.
