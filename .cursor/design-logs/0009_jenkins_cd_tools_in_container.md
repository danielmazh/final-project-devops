# 0009 — Jenkins CD tools inside container

## Background & Problem

**Issue 1:** `Jenkinsfile.cd` runs `terraform`, `ansible-playbook`, and `kubectl` in the Jenkins workspace. The agent is the `jenkins/jenkins:lts` container. Only Docker CLI and shellcheck were copied in; Terraform was never installed → `terraform: not found` (exit 127).

**Issue 2:** After installing Terraform, `terraform init` failed with `failed to get shared config profile, seyoawe-tf`. Both `backend.tf` (`profile = "seyoawe-tf"`) and `main.tf` (`profile = "seyoawe-tf"`) hardcode a named profile that only exists on the developer's laptop (in `.aws-project/`). Inside the Jenkins container, AWS creds come from `withCredentials` env vars, not a profile.

## Design & Solution

### Issue 1 — Missing binaries
- Download Terraform **1.14.0** on the EC2 host (same as `setup-env.sh`), unzip to `/usr/local/bin/terraform`.
- `docker cp` **terraform** and **kubectl** into `jenkins:/usr/local/bin/`.
- `docker exec` as root: `pip3 install ansible awscli` inside the container.

### Issue 2 — Profile conflict
- **`Jenkinsfile.cd`**: removed `AWS_PROFILE = 'seyoawe-tf'` from the pipeline environment. Every `withCredentials` block now runs `unset AWS_PROFILE` + exports `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_DEFAULT_REGION`.
- **`terraform init`**: added `-backend-config="profile="` to override the hardcoded `profile` in `backend.tf` with an empty string, forcing the backend to use env var creds.
- **`main.tf` provider `profile`**: when `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` env vars are set, the AWS SDK credential chain uses them and ignores the provider's `profile` attribute. No change needed.
- **`configure-eks.yaml`**: made `--profile` conditional. Default is `seyoawe-tf` (for local use). CD pipeline passes `-e aws_profile=""` to skip it.

**Backward-compatible:** `backend.tf`, `main.tf`, and `configure-eks.yaml` are unchanged for local developer use (still default to `seyoawe-tf`).

## Verification

`docker exec jenkins bash -lc 'terraform version && kubectl version --client && ansible-playbook --version'`

## Implementation Results

- Extended `ansible/playbooks/configure-jenkins.yaml`: Terraform 1.14.0 on host + `docker cp`; kubectl `docker cp`; `pip3` + `ansible` + `awscli` inside container; verify step.
- Updated `jenkins/Jenkinsfile.cd`: removed `AWS_PROFILE` env, added `unset AWS_PROFILE` + `AWS_DEFAULT_REGION` in all stages, `-backend-config="profile="` on init.
- Updated `ansible/playbooks/configure-eks.yaml`: `--profile` flag conditional via `set_fact` + `-e aws_profile=""` override.
