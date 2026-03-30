# 0004 — Project-local Virtual Environment & Tool Setup

## 1. Background & Problem

All DevOps tools (Terraform, AWS CLI, kubectl, Ansible, Helm, pytest, flake8) are currently expected to be installed globally on the operator's machine. This creates three problems:

1. **Version drift** — a globally installed `terraform 1.5` will fail against code written for `1.14`.
2. **Portability** — cloning the repo on a new machine or CI node requires re-installing every tool manually.
3. **Working directory confusion** — AWS CLI profiles (`seyoawe-tf`) and region config exist globally in `~/.aws/`, making it easy to accidentally act on the wrong account.

**Root cause:** No project-local environment contract.

## 2. Questions & Answers

| Question | Answer |
|----------|--------|
| Can Terraform/kubectl/Helm go in a Python venv? | Indirectly — they are Go binaries. `setup-env.sh` downloads them to `.venv/bin/` so they appear on `PATH` after `source .venv/bin/activate`. |
| AWS CLI v1 vs v2? | v1 is pip-installable and fully sufficient for all operations in this project (S3, EC2, EKS, IAM). We pin it in `requirements-infra.txt`. |
| Per-project AWS config? | `setup-env.sh` writes `AWS_CONFIG_FILE` and `AWS_SHARED_CREDENTIALS_FILE` to `.aws-project/` (gitignored). When venv is activated, these env vars point AWS CLI at the project-local config, not `~/.aws/`. |
| How does AWS profile survive shell restarts? | `source .venv/bin/activate` re-exports all env vars. One command restores the full environment. |
| Pinning strategy? | Python packages pinned with `~=` (compatible release). Binaries pinned to exact versions matching the `terraform --version` already on this machine (1.14), kubectl 1.34, helm 3.17. |

## 3. Design & Solution

### 3.1 File layout

```
final-project-devops/
├── setup-env.sh              # One-time setup: creates venv + downloads binaries
├── requirements-infra.txt    # Python infra tools (pip-installable)
├── .aws-project/             # Gitignored, per-project AWS config + credentials
│   ├── config
│   └── credentials
└── .venv/                    # Gitignored, standard Python venv
    └── bin/
        ├── activate          # Patched to export project env vars
        ├── aws               # awscli v1 (pip)
        ├── ansible*          # ansible (pip)
        ├── pytest / flake8   # test/lint tools (pip)
        ├── terraform         # downloaded binary
        ├── kubectl           # downloaded binary
        └── helm              # downloaded binary
```

### 3.2 setup-env.sh responsibilities

1. Create `.venv` if it doesn't exist.
2. `pip install -r requirements-infra.txt` and `pip install -r cli/requirements.txt`.
3. Detect OS + arch; download and extract Terraform, kubectl, Helm into `.venv/bin/`.
4. Create `.aws-project/config` skeleton (region = `us-east-1`, profile = `seyoawe-tf`).
5. Append env var exports to `.venv/bin/activate` (idempotent, keyed by a marker comment):
   - `AWS_CONFIG_FILE`, `AWS_SHARED_CREDENTIALS_FILE` → `.aws-project/`
   - `AWS_PROFILE=seyoawe-tf`
   - `AWS_DEFAULT_REGION` from config (or `us-east-1`)
   - `TF_DIR` → `./terraform`
6. Print a one-line instruction: `source .venv/bin/activate && aws configure --profile seyoawe-tf`.

### 3.3 Activation flow (after first setup)

```bash
source .venv/bin/activate
# PATH now includes .venv/bin/ — terraform, kubectl, helm, aws, ansible all available
# AWS_CONFIG_FILE and AWS_SHARED_CREDENTIALS_FILE point at .aws-project/
# AWS_PROFILE=seyoawe-tf
```

### 3.4 AWS profile bootstrap (manual — happens once)

After activating the venv, the operator runs:

```bash
aws configure --profile seyoawe-tf
```

Credentials are written to `.aws-project/credentials` (gitignored) instead of `~/.aws/credentials`, keeping this project isolated from any other AWS accounts.

## 4. Implementation Plan

1. Create design log `0004_project_venv_setup.md` (this file).
2. Create `requirements-infra.txt`.
3. Create `setup-env.sh` (idempotent, cross-platform: macOS x86/arm + Linux x86/arm).
4. Add `.aws-project/` to `.gitignore`.
5. Rewrite the README quickstart section.

## 5. Examples

- ✅ `source .venv/bin/activate && terraform --version` → shows project-pinned `1.14`.
- ✅ `source .venv/bin/activate && aws s3 ls` → uses `seyoawe-tf` profile automatically.
- ❌ Running `terraform` without activating → picks up global version (may differ).
- ❌ Running `aws configure` without activating → writes to `~/.aws/`, polluting global config.

## 6. Trade-offs

| Choice | Rationale |
|--------|-----------|
| Binary downloads to `.venv/bin/` | Single activation gives all tools; no separate `tools/` directory to manage. |
| awscli v1 via pip (not v2 standalone) | pip-installable, no curl/bash install gymnastics; all required API calls work on v1. |
| `.aws-project/` (not `.env` file) | AWS CLI natively reads `AWS_CONFIG_FILE`/`AWS_SHARED_CREDENTIALS_FILE`; no custom parsing needed. |

## 7. Verification Criteria

- [ ] `source .venv/bin/activate` works on a fresh clone (after running `setup-env.sh`).
- [ ] `terraform --version` returns `1.14.x`.
- [ ] `kubectl version --client` returns `1.34.x`.
- [ ] `helm version` returns `3.x`.
- [ ] `aws --version` returns aws-cli/1.x.
- [ ] `ansible --version` returns core 2.x.
- [ ] `aws configure --profile seyoawe-tf` writes to `.aws-project/credentials`, not `~/.aws/`.

---

## Implementation Results

**When:** 2026-03-27

### Execution

- `setup-env.sh` created and validated on macOS (darwin/amd64).
- CA cert fix applied: Homebrew OpenSSL shadowed system bundle; resolved with `--cacert /etc/ssl/cert.pem` wrapper function.
- All binaries installed to `.venv/bin/`, `activate` patched, `.aws-project/` created.

### Verified tool versions after `source .venv/bin/activate`

| Tool | Version |
|------|---------|
| terraform | v1.14.0 |
| kubectl (client) | v1.34.1 |
| helm | v3.17.0 |
| aws-cli | 1.44.68 (v1 via pip) |
| ansible | core 2.18.15 |
| pytest | 8.4.2 |
| flake8 | 7.3.0 |

### Verified env vars

- `AWS_PROFILE=seyoawe-tf`
- `AWS_CONFIG_FILE` → `.aws-project/config`
- `AWS_SHARED_CREDENTIALS_FILE` → `.aws-project/credentials`
- `TF_DIR` → `./terraform`

### Deviations

- awscli installed as v1.44.68 (pip resolves latest compatible with `~=1.38`). All required AWS API calls confirmed supported.
