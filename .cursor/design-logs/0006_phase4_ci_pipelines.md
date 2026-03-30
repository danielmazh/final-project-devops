# 0006 — Phase 4: CI Pipelines (Jenkins)

## 1. Background & Problem

Both application components (Engine and CLI) are now containerised. There is no automated process that:
- Detects which component changed on a push
- Runs linting and tests
- Builds and pushes versioned Docker images to DockerHub
- Tags the git repository with semantic version identifiers

Manually performing these steps on every commit is error-prone and does not satisfy the rubric requirement for CI pipelines with version coupling.

**Root cause:** No CI pipeline definitions exist yet; VERSION coupling between Engine and CLI is informal.

## 2. Questions & Answers

| Question | Answer |
|----------|--------|
| Single Jenkinsfile or separate? | **Separate** per component (`Jenkinsfile.engine`, `Jenkinsfile.cli`) + one CD pipeline (`Jenkinsfile.cd`). Each can be triggered independently via SCM polling or webhook. |
| Version coupling mechanism? | Root `VERSION` file is the single source of truth. Both pipelines read it at build time. `scripts/change-detect.sh` classifies which component(s) changed via `git diff`. |
| How does Jenkins clone the repo? | Jenkins is on the EC2 instance; it needs a GitHub credential and the repo URL. The `git` tool inside the pipeline checks out the branch that triggered the build. |
| Engine binary in CI? | The engine binary (`seyoawe.linux`) is not in git. Jenkins must copy it from a known location on the EC2 host before running `docker build`. The binary is copied to the Jenkins workspace from `~/seyoawe.linux` (pre-placed on the host). |
| DockerHub org/namespace? | Set via `DOCKERHUB_USER` env var in Jenkins credentials or pipeline env block. Images: `$DOCKERHUB_USER/seyoawe-engine`, `$DOCKERHUB_USER/seyoawe-cli`. |
| Git tagging from Jenkins? | Yes — after a successful push, the pipeline creates and pushes `engine-vX.Y.Z` / `cli-vX.Y.Z` tags using the GitHub token credential. |
| Lint tools? | Engine: `yamllint` (config files), `shellcheck` (run.sh). CLI: `flake8` (already in venv/requirements-infra.txt). |
| Change detection skips? | If no engine/CLI files changed AND VERSION is unchanged, the respective pipeline stage is skipped via `when { expression { ... } }`. |

## 3. Design & Solution

### 3.1 VERSION file & change detection

```
VERSION (root file)  →  single semver line, e.g. 0.1.0
scripts/version.sh   →  reads VERSION, exports $APP_VERSION
scripts/change-detect.sh  →  classifies git diff into ENGINE / CLI / BOTH / NONE
```

**Change classification logic:**
```
engine_paths: engine/  docker/engine/  engine/configuration/
cli_paths:    cli/      docker/cli/
version_path: VERSION
```

| Engine changed | CLI changed | VERSION changed | Result |
|:-:|:-:|:-:|--------|
| Yes | No | No | BUILD_ENGINE=true |
| No | Yes | No | BUILD_CLI=true |
| * | * | Yes | BUILD_ENGINE=true BUILD_CLI=true |
| No | No | No | BUILD_ENGINE=false BUILD_CLI=false |

### 3.2 Engine CI (`jenkins/Jenkinsfile.engine`)

```
Stages:
  1. Checkout
  2. Read VERSION
  3. Change Detection → set BUILD_ENGINE
  4. Lint (yamllint config, shellcheck run.sh)   [skipped if !BUILD_ENGINE]
  5. Docker Build (--build-arg VERSION=$VER)       [skipped if !BUILD_ENGINE]
  6. Docker Push (:$VER, :latest)                  [skipped if !BUILD_ENGINE]
  7. Git Tag (engine-v$VER)                         [skipped if !BUILD_ENGINE]
```

### 3.3 CLI CI (`jenkins/Jenkinsfile.cli`)

```
Stages:
  1. Checkout
  2. Read VERSION
  3. Change Detection → set BUILD_CLI
  4. Lint (flake8 cli/)                             [skipped if !BUILD_CLI]
  5. Unit Tests (pytest cli/tests/ --junitxml)      [skipped if !BUILD_CLI]
  6. Docker Build (--build-arg VERSION=$VER)        [skipped if !BUILD_CLI]
  7. Docker Push (:$VER, :latest)                   [skipped if !BUILD_CLI]
  8. Git Tag (cli-v$VER)                             [skipped if !BUILD_CLI]
```

### 3.4 CD Pipeline (`jenkins/Jenkinsfile.cd`)

```
Stages:
  1. Checkout
  2. Read VERSION
  3. Terraform Init + Plan
  4. Manual Approval Gate (input step)
  5. Terraform Apply
  6. Ansible: configure-eks (update kubeconfig, verify nodes)
  7. K8s Deploy (kubectl apply -f k8s/)
  8. Image update (kubectl set image)
  9. Rollout verification (kubectl rollout status)
```

### 3.5 Scripts

| File | Purpose |
|------|---------|
| `scripts/version.sh` | `export APP_VERSION=$(cat VERSION \| tr -d '[:space:]')` |
| `scripts/change-detect.sh` | `git diff HEAD~1 --name-only` → sets BUILD_ENGINE / BUILD_CLI |

### 3.6 Jenkins prerequisites

Jenkins EC2 (`44.201.6.188`) needs:
- `yamllint`: `pip3 install yamllint`
- `shellcheck`: `dnf install shellcheck`
- `engine/seyoawe.linux` at `~/seyoawe.linux` on the host
- DockerHub credentials: ID `dockerhub-creds`
- GitHub token: ID `github-token`

## 4. Implementation Plan

1. Create `scripts/version.sh` and `scripts/change-detect.sh`.
2. Write `jenkins/Jenkinsfile.engine`.
3. Write `jenkins/Jenkinsfile.cli`.
4. Write `jenkins/Jenkinsfile.cd`.
5. Install `yamllint` and `shellcheck` on Jenkins EC2 (Ansible or manual).
6. Place `seyoawe.linux` binary on Jenkins EC2 host.
7. Create Jenkins pipeline jobs pointing to each Jenkinsfile.
8. Trigger a build and verify all stages green.

## 5. Examples

- ✅ Push changes to `cli/sawectl.py` only → CLI pipeline triggers, engine pipeline skips.
- ✅ Push changes to `VERSION` → both pipelines trigger.
- ❌ Hardcoded version string in Jenkinsfile → breaks coupling, images may get mismatched tags.
- ✅ `engine-v0.1.0` tag created after successful push → traceable release.

## 6. Trade-offs

| Choice | Rationale |
|--------|-----------|
| Separate Jenkinsfiles per component | Independent trigger, clear ownership, easier debugging than a monolithic pipeline. |
| Inline change detection (not shared library) | Three pipelines; shared library overhead not justified for PoC. |
| `git tag` from Jenkins | Ties image version to git history; no external version service needed. |
| Binary on Jenkins host (not in git) | Binary is 19 MB and gitignored; host placement is the simplest CI approach for PoC. |

## 7. Verification Criteria

- [ ] `scripts/change-detect.sh` outputs correct BUILD_ENGINE/BUILD_CLI for each change scenario.
- [ ] Engine CI pipeline: lint → build → push → tag (all stages green on engine-only change).
- [ ] CLI CI pipeline: lint → pytest (13/13) → build → push → tag (green on CLI-only change).
- [ ] VERSION change triggers both pipelines.
- [ ] DockerHub shows `seyoawe-engine:0.1.0` and `seyoawe-cli:0.1.0`.
- [ ] Git tags `engine-v0.1.0`, `cli-v0.1.0` visible in repo.

---

## Implementation Results

**When:** 2026-03-30

### Setup completed

- `scripts/version.sh` — verified locally, outputs `APP_VERSION=0.1.0` ✅
- `scripts/change-detect.sh` — verified locally, correctly classifies changed files ✅
- `ansible/playbooks/configure-jenkins-tools.yaml` — ran against EC2, `shellcheck` + `yamllint 1.37.1` installed ✅
- `seyoawe.linux` binary placed at `/home/ec2-user/seyoawe.linux` on Jenkins EC2 ✅
- Jenkins credentials configured:
  - `dockerhub-creds` (Username with password) ✅
  - `github-token` (Secret text) ✅
  - `dockerhub-user` (Secret text) ✅
  - `aws-credentials` (Username with password) ✅

### Pipeline execution — pending first build run
