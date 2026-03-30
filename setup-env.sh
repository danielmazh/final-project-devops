#!/usr/bin/env bash
# setup-env.sh — One-time project environment bootstrap
#
# Creates a self-contained .venv with ALL project tools:
#   Python tools:  aws-cli, ansible, pytest, flake8, pyyaml, jsonschema, requests
#   Go binaries:   terraform, kubectl, helm  (downloaded to .venv/bin/)
#   AWS config:    .aws-project/ (gitignored) — isolated from ~/.aws/
#
# Usage:
#   bash setup-env.sh             # first-time setup
#   source .venv/bin/activate     # every subsequent session
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/.venv"
AWS_PROJECT_DIR="${SCRIPT_DIR}/.aws-project"
ACTIVATE="${VENV_DIR}/bin/activate"
MARKER="# ── seyoawe-project-env ──"

# ── Pinned tool versions ──────────────────────────────────────────────────────
TERRAFORM_VERSION="1.14.0"
KUBECTL_VERSION="v1.34.1"
HELM_VERSION="v3.17.0"

# ── Helpers ───────────────────────────────────────────────────────────────────
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log()  { echo -e "${CYAN}[setup-env]${NC} $*"; }
ok()   { echo -e "${GREEN}[ok]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }

curl_cmd() {
    # On macOS, Homebrew's openssl can shadow the system CA bundle.
    # Use the system bundle explicitly when it exists.
    if [[ -f /etc/ssl/cert.pem ]]; then
        curl --cacert /etc/ssl/cert.pem "$@"
    else
        curl "$@"
    fi
}

detect_os_arch() {
    local os arch
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"
    case "$arch" in
        x86_64)  arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)
            echo "Unsupported architecture: $arch" >&2
            exit 1
            ;;
    esac
    # Terraform uses 'darwin' / 'linux'; kubectl/helm same
    echo "${os}/${arch}"
}

download_binary() {
    local name="$1" url="$2" dest="${VENV_DIR}/bin/${3:-$1}"
    if [[ -x "$dest" ]]; then
        ok "${name} already present at ${dest}, skipping download."
        return
    fi
    log "Downloading ${name}..."
    local tmp
    tmp="$(mktemp -d)"
    curl -fsSL "$url" -o "${tmp}/${name}.archive"

    # Detect archive type and extract
    case "$url" in
        *.zip)
            unzip -q "${tmp}/${name}.archive" -d "${tmp}/extracted"
            ;;
        *.tar.gz|*.tgz)
            tar -xzf "${tmp}/${name}.archive" -C "${tmp}/extracted" --strip-components=1 2>/dev/null \
                || tar -xzf "${tmp}/${name}.archive" -C "${tmp}/extracted"
            ;;
        *)
            # Raw binary (kubectl)
            cp "${tmp}/${name}.archive" "${tmp}/extracted/${name}"
            ;;
    esac

    # Copy the actual binary
    local found
    found="$(find "${tmp}/extracted" -maxdepth 3 -type f -name "${name}" | head -1)"
    if [[ -z "$found" ]]; then
        # Some archives put binary at root level
        found="${tmp}/extracted/${name}"
    fi
    cp "$found" "$dest"
    chmod +x "$dest"
    rm -rf "$tmp"
    ok "${name} installed to ${dest}"
}

# ── Step 1: Python venv ───────────────────────────────────────────────────────
if [[ ! -d "$VENV_DIR" ]]; then
    log "Creating Python virtual environment at .venv ..."
    python3 -m venv "$VENV_DIR"
    ok "venv created."
else
    ok "venv already exists at .venv"
fi

# ── Step 2: Python packages ───────────────────────────────────────────────────
log "Installing Python packages from requirements-infra.txt ..."
"${VENV_DIR}/bin/pip" install --quiet --upgrade pip
"${VENV_DIR}/bin/pip" install --quiet -r "${SCRIPT_DIR}/requirements-infra.txt"
ok "Python packages installed."

# ── Step 3: Go binaries ───────────────────────────────────────────────────────
OS_ARCH="$(detect_os_arch)"
OS="${OS_ARCH%%/*}"
ARCH="${OS_ARCH##*/}"

mkdir -p "${VENV_DIR}/bin"

# Terraform
TF_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_${OS}_${ARCH}.zip"
mkdir -p "${VENV_DIR}/bin/.tf_extract"
if [[ ! -x "${VENV_DIR}/bin/terraform" ]]; then
    log "Downloading Terraform ${TERRAFORM_VERSION} (${OS}/${ARCH})..."
    tmp_tf="$(mktemp -d)"
    curl_cmd -fsSL "$TF_URL" -o "${tmp_tf}/terraform.zip"
    unzip -q "${tmp_tf}/terraform.zip" -d "${tmp_tf}"
    cp "${tmp_tf}/terraform" "${VENV_DIR}/bin/terraform"
    chmod +x "${VENV_DIR}/bin/terraform"
    rm -rf "$tmp_tf"
    ok "terraform ${TERRAFORM_VERSION} installed."
else
    ok "terraform already present, skipping."
fi

# kubectl
KUBECTL_URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl"
if [[ ! -x "${VENV_DIR}/bin/kubectl" ]]; then
    log "Downloading kubectl ${KUBECTL_VERSION} (${OS}/${ARCH})..."
    curl_cmd -fsSL "$KUBECTL_URL" -o "${VENV_DIR}/bin/kubectl"
    chmod +x "${VENV_DIR}/bin/kubectl"
    ok "kubectl ${KUBECTL_VERSION} installed."
else
    ok "kubectl already present, skipping."
fi

# Helm
HELM_OS="$OS"
HELM_ARCH="$ARCH"
[[ "$ARCH" == "amd64" ]] && HELM_ARCH="amd64"
HELM_URL="https://get.helm.sh/helm-${HELM_VERSION}-${HELM_OS}-${HELM_ARCH}.tar.gz"
if [[ ! -x "${VENV_DIR}/bin/helm" ]]; then
    log "Downloading Helm ${HELM_VERSION} (${HELM_OS}/${HELM_ARCH})..."
    tmp_helm="$(mktemp -d)"
    curl_cmd -fsSL "$HELM_URL" -o "${tmp_helm}/helm.tar.gz"
    tar -xzf "${tmp_helm}/helm.tar.gz" -C "${tmp_helm}"
    cp "${tmp_helm}/${HELM_OS}-${HELM_ARCH}/helm" "${VENV_DIR}/bin/helm"
    chmod +x "${VENV_DIR}/bin/helm"
    rm -rf "$tmp_helm"
    ok "helm ${HELM_VERSION} installed."
else
    ok "helm already present, skipping."
fi

# ── Step 4: Per-project AWS config ───────────────────────────────────────────
mkdir -p "$AWS_PROJECT_DIR"
chmod 700 "$AWS_PROJECT_DIR"

if [[ ! -f "${AWS_PROJECT_DIR}/config" ]]; then
    log "Creating .aws-project/config skeleton..."
    cat > "${AWS_PROJECT_DIR}/config" <<'EOF'
[default]
region = us-east-1
output = json

[profile seyoawe-tf]
region = us-east-1
output = json
EOF
    ok ".aws-project/config created. Edit the region if needed."
fi

if [[ ! -f "${AWS_PROJECT_DIR}/credentials" ]]; then
    log "Creating empty .aws-project/credentials..."
    cat > "${AWS_PROJECT_DIR}/credentials" <<'EOF'
# Run: aws configure --profile seyoawe-tf
# This file is gitignored. Credentials live here, NOT in ~/.aws/
[seyoawe-tf]
aws_access_key_id = REPLACE_ME
aws_secret_access_key = REPLACE_ME
EOF
    chmod 600 "${AWS_PROJECT_DIR}/credentials"
    ok ".aws-project/credentials created (placeholder)."
fi

# ── Step 5: Patch venv activate (idempotent) ──────────────────────────────────
if ! grep -q "$MARKER" "$ACTIVATE" 2>/dev/null; then
    log "Patching .venv/bin/activate with project env vars..."
    cat >> "$ACTIVATE" <<EOF

${MARKER}
# Project-local AWS config — isolated from ~/.aws/
export AWS_CONFIG_FILE="${AWS_PROJECT_DIR}/config"
export AWS_SHARED_CREDENTIALS_FILE="${AWS_PROJECT_DIR}/credentials"
export AWS_PROFILE="seyoawe-tf"
export AWS_DEFAULT_REGION="us-east-1"
export TF_DIR="${SCRIPT_DIR}/terraform"
# Restore on deactivate
_OLD_AWS_CONFIG_FILE="\${AWS_CONFIG_FILE:-}"
_OLD_AWS_SHARED_CREDENTIALS_FILE="\${AWS_SHARED_CREDENTIALS_FILE:-}"
_OLD_AWS_PROFILE="\${AWS_PROFILE:-}"
_OLD_AWS_DEFAULT_REGION="\${AWS_DEFAULT_REGION:-}"
_OLD_TF_DIR="\${TF_DIR:-}"
# ── end seyoawe-project-env ──
EOF
    ok "activate patched."
else
    ok "activate already patched, skipping."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Setup complete. Activate your environment:${NC}"
echo ""
echo -e "    source .venv/bin/activate"
echo ""
echo -e "${GREEN}  Then configure your AWS credentials (one-time):${NC}"
echo ""
echo -e "    aws configure --profile seyoawe-tf"
echo -e "    aws sts get-caller-identity --profile seyoawe-tf"
echo ""
echo -e "${GREEN}  Tool versions installed:${NC}"
echo -e "  terraform  ${TERRAFORM_VERSION}"
echo -e "  kubectl    ${KUBECTL_VERSION}"
echo -e "  helm       ${HELM_VERSION}"
echo -e "  aws-cli    (v1 via pip — see: aws --version)"
echo -e "  ansible    (via pip  — see: ansible --version)"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
