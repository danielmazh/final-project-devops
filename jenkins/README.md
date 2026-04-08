# jenkins/

Three Jenkins Declarative Pipelines implementing CI for both application components and CD for infrastructure + deployment.

## Files

```
jenkins/
├── Jenkinsfile.engine     # Engine CI: lint → build → push → tag
├── Jenkinsfile.cli        # CLI CI: lint → test → build → push → tag
└── Jenkinsfile.cd         # CD: terraform → ansible → kubectl deploy
```

## Jenkins Instance

Jenkins runs as a Docker container on a dedicated EC2 instance provisioned by Terraform:

- **URL:** `http://<JENKINS_IP>:8080` (get IP from `cd terraform && terraform output jenkins_public_ip`)
- **Host:** `t3.medium`, Amazon Linux 2023, public subnet
- **Docker socket:** Bind-mounted from host — enables Docker builds inside pipelines
- **Persistent home:** `/var/jenkins_home` on host volume

## Pipeline Flow

```
                     ┌──────────────────────┐
  git push to main → │  GitHub Webhook      │ ── triggers { githubPush() }
                     │  → Change Detection  │
                     │  git diff analysis   │
                     └────────┬─────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
     ┌────────────┐  ┌────────────┐  ┌──────────────┐
     │ Engine CI  │  │  CLI CI    │  │  CD Pipeline  │
     │            │  │            │  │  (manual)     │
     │ yamllint   │  │ flake8     │  │               │
     │ shellcheck │  │ pytest     │  │ tf plan       │
     │ docker     │  │ docker     │  │ approval gate │
     │  build     │  │  build     │  │ tf apply      │
     │  push      │  │  push      │  │ ansible       │
     │ git tag    │  │ git tag    │  │ kubectl apply │
     └────────────┘  └────────────┘  └──────────────┘
```

## Engine CI (`Jenkinsfile.engine`)

| Stage | Condition | What it does |
|-------|-----------|-------------|
| Checkout | Always | Clone repo from GitHub |
| Read VERSION | Always | `cat VERSION` → `APP_VERSION` |
| Change Detection | Always | `git diff $GIT_PREVIOUS_SUCCESSFUL_COMMIT HEAD` → `BUILD_ENGINE=true/false` |
| Lint | `BUILD_ENGINE=true` | `yamllint -d relaxed config.yaml` + `shellcheck run.sh` |
| Prepare Binary | `BUILD_ENGINE=true` | Copy `seyoawe.linux` from `/var/jenkins_home/` to workspace |
| Docker Build | `BUILD_ENGINE=true` | Build `$DH_USER/seyoawe-engine:$VER` |
| Docker Push | `BUILD_ENGINE=true` | Push `:$VER` + `:latest` to DockerHub |
| Git Tag | `BUILD_ENGINE=true` | Create + push `engine-v$VER` |

**Triggers on:** changes to `engine/`, `docker/engine/`, or `VERSION`.

## CLI CI (`Jenkinsfile.cli`)

| Stage | Condition | What it does |
|-------|-----------|-------------|
| Checkout | Always | Clone repo |
| Read VERSION | Always | Read semver |
| Change Detection | Always | Sets `BUILD_CLI` |
| Lint | `BUILD_CLI=true` | `flake8 cli/` (using `.flake8` config) |
| Unit Tests | `BUILD_CLI=true` | `pytest cli/tests/ -v --junitxml` (13 tests, JUnit report) |
| Docker Build | `BUILD_CLI=true` | Build `$DH_USER/seyoawe-cli:$VER` |
| Docker Push | `BUILD_CLI=true` | Push to DockerHub |
| Git Tag | `BUILD_CLI=true` | Create + push `cli-v$VER` |

**Triggers on:** changes to `cli/`, `docker/cli/`, or `VERSION`.

## CD Pipeline (`Jenkinsfile.cd`)

| Stage | What it does |
|-------|-------------|
| Checkout | Clone repo |
| Read VERSION | Read semver for image tagging |
| Terraform Init | `terraform init -input=false` with AWS credentials |
| Terraform Plan | `terraform plan -out=tfplan` |
| **Approval** | `input` step — human must click "Apply" to proceed |
| Terraform Apply | `terraform apply -auto-approve tfplan` |
| Ansible Configure | `ansible-playbook configure-eks.yaml` |
| K8s Deploy | `kubectl apply -f k8s/namespace.yaml && kubectl apply -f k8s/engine/` |
| K8s Image Update | `kubectl set image` or `rollout restart` |
| Rollout Verify | `kubectl rollout status --timeout=300s` |
| Git Tag | `deploy-v$VER` |

**Trigger:** Manual only (click "Build Now" in Jenkins UI).

## Required Credentials

| Credential ID | Type | Purpose |
|---------------|------|---------|
| `dockerhub-creds` | Username + Password | DockerHub login + push + image namespace |
| `github-token` | Secret text | Git tag push authentication |
| `aws-credentials` | Username + Password | AWS access for Terraform in CD pipeline |

## Change Detection Logic

Uses `GIT_PREVIOUS_SUCCESSFUL_COMMIT` (set automatically by Jenkins) as the diff base — this covers all commits since the last successful build, preventing missed changes when multiple commits are pushed at once.

```groovy
def baseRef = env.GIT_PREVIOUS_SUCCESSFUL_COMMIT ?: 'HEAD~5'
def changed = sh(script: "git diff ${baseRef} HEAD --name-only", returnStdout: true)
```

A `VERSION` file change triggers BOTH Engine and CLI pipelines (coupled release).

## GitHub Webhook

CI pipelines use `triggers { githubPush() }` to automatically start on push events. This requires a GitHub webhook configured on the repository:

- **Payload URL:** `http://<JENKINS_IP>:8080/github-webhook/`
- **Content type:** `application/json`
- **Events:** Push only
- **Security group:** The Terraform Jenkins SG allows port 8080 from GitHub's webhook IP ranges (`192.30.252.0/22`, `185.199.108.0/22`, `140.82.112.0/20`, `143.55.64.0/20`) in addition to the operator IP. These ranges come from [api.github.com/meta](https://api.github.com/meta).

After first creating the webhook, run each CI job manually once ("Build Now") so Jenkins reads the Jenkinsfile and registers the `githubPush()` trigger.
