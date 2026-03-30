#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# lifecycle.sh — AWS Resource Lifecycle Manager for SeyoAWE PoC
#
# Single entry point to inspect, suspend, resume, and destroy all cloud
# resources created by this project. Prevents cloud sprawl and guarantees
# zero residual footprint when the PoC is done.
# ============================================================================

# ── RESOURCE REGISTRY ────────────────────────────────────────────────────────
# Every cloud resource this project creates MUST be listed here.
# When you add infrastructure in ANY phase, update this registry.
# Format: TYPE | IDENTIFIER | MANAGED_BY
#
# Terraform-managed (destroyed via terraform destroy):
#   vpc           | seyoawe-vpc                    | terraform
#   subnet        | seyoawe-public-a               | terraform
#   subnet        | seyoawe-public-b               | terraform
#   subnet        | seyoawe-private-a              | terraform
#   subnet        | seyoawe-private-b              | terraform
#   igw           | seyoawe-igw                    | terraform
#   nat_gateway   | seyoawe-nat                    | terraform
#   eip           | seyoawe-nat-eip                | terraform
#   eks_cluster   | seyoawe-cluster                | terraform
#   eks_nodegroup | seyoawe-nodes                  | terraform
#   ec2           | seyoawe-jenkins                | terraform
#   sg            | seyoawe-jenkins-sg             | terraform
#   sg            | seyoawe-eks-cluster-sg         | terraform
#   sg            | seyoawe-eks-node-sg            | terraform
#   iam_role      | seyoawe-eks-cluster-role       | terraform
#   iam_role      | seyoawe-eks-node-role          | terraform
#   iam_role      | seyoawe-ebs-csi-role           | terraform
#   oidc_provider | oidc.eks.us-east-1.../id/3A... | terraform
#   eks_addon     | aws-ebs-csi-driver             | terraform
#   route_table   | seyoawe-public-rt              | terraform
#   route_table   | seyoawe-private-rt             | terraform
#
# Helm-managed (must uninstall BEFORE terraform destroy):
#   helm_release  | monitoring (ns: monitoring)    | helm
#
# K8s-managed (must delete BEFORE terraform destroy):
#   namespace     | seyoawe                        | kubectl
#   namespace     | monitoring                     | kubectl
#   statefulset   | seyoawe-engine (ns: seyoawe)   | kubectl
#   pvc           | data-seyoawe-engine-0          | kubectl
#
# Bootstrap (outside Terraform state — only destroyed with --all):
#   s3_bucket     | seyoawe-tf-state-<account-id>  | aws-cli
#   iam_user      | terraform-deployer             | aws-cli
# ── END REGISTRY ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${TF_DIR:-${SCRIPT_DIR}/terraform}"
AWS_PROFILE="${AWS_PROFILE:-seyoawe-tf}"
export AWS_PROFILE

CLUSTER_NAME="seyoawe-cluster"
NODEGROUP_NAME="seyoawe-nodes"
JENKINS_TAG_NAME="seyoawe-jenkins"
NODE_DESIRED=2
NODE_MIN=2
NODE_MAX=3

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[lifecycle]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
err()  { echo -e "${RED}[error]${NC} $*" >&2; }
ok()   { echo -e "${GREEN}[ok]${NC} $*"; }

get_region() {
    if [[ -n "${AWS_REGION:-}" ]]; then
        echo "$AWS_REGION"
        return
    fi
    if [[ -f "${TF_DIR}/terraform.tfvars" ]]; then
        local r
        r=$(grep -E '^\s*region\s*=' "${TF_DIR}/terraform.tfvars" 2>/dev/null | head -1 | sed 's/.*=\s*"\(.*\)"/\1/')
        if [[ -n "$r" ]]; then echo "$r"; return; fi
    fi
    echo "us-east-1"
}

REGION="$(get_region)"
export AWS_DEFAULT_REGION="$REGION"

# ── Helpers ──────────────────────────────────────────────────────────────────

jenkins_instance_id() {
    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=${JENKINS_TAG_NAME}" "Name=instance-state-name,Values=running,stopped" \
        --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || echo "None"
}

jenkins_state() {
    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=${JENKINS_TAG_NAME}" "Name=instance-state-name,Values=running,stopped,stopping,pending" \
        --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "not-found"
}

eks_nodegroup_desired() {
    aws eks describe-nodegroup \
        --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NODEGROUP_NAME" \
        --query 'nodegroup.scalingConfig.desiredSize' --output text 2>/dev/null || echo "n/a"
}

eks_cluster_status() {
    aws eks describe-cluster --name "$CLUSTER_NAME" \
        --query 'cluster.status' --output text 2>/dev/null || echo "not-found"
}

helm_release_exists() {
    helm list -n monitoring --filter '^monitoring$' -q 2>/dev/null | grep -q monitoring && echo "deployed" || echo "not-found"
}

s3_bucket_name() {
    local acct
    acct=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
    echo "seyoawe-tf-state-${acct}"
}

confirm() {
    local msg="${1:-Are you sure?}"
    echo -en "${RED}${msg} [y/N]: ${NC}"
    read -r reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

# ── Commands ─────────────────────────────────────────────────────────────────

cmd_status() {
    log "Checking resource status (profile=${AWS_PROFILE}, region=${REGION})..."
    echo ""

    printf "  %-20s %s\n" "EKS Cluster:" "$(eks_cluster_status)"
    printf "  %-20s %s\n" "EKS Node Group:" "desired=$(eks_nodegroup_desired)"
    printf "  %-20s %s\n" "Jenkins EC2:" "$(jenkins_state)"
    printf "  %-20s %s\n" "Monitoring Helm:" "$(helm_release_exists)"

    local bucket
    bucket="$(s3_bucket_name)"
    local bucket_status="not-found"
    aws s3api head-bucket --bucket "$bucket" 2>/dev/null && bucket_status="exists"
    printf "  %-20s %s\n" "TF State Bucket:" "$bucket_status ($bucket)"

    echo ""
    log "Estimated hourly cost while all resources are running:"
    echo "  EKS control plane:  ~\$0.10/hr"
    echo "  2x t3.medium nodes: ~\$0.08/hr"
    echo "  1x t3.medium Jenkins: ~\$0.04/hr"
    echo "  NAT Gateway:        ~\$0.05/hr"
    echo "  ─────────────────────────────"
    echo "  Total:              ~\$0.27/hr (~\$6.50/day)"
}

cmd_stop() {
    local component="${1:-}"
    case "$component" in
        jenkins)
            local iid
            iid="$(jenkins_instance_id)"
            if [[ "$iid" == "None" || -z "$iid" ]]; then
                warn "Jenkins instance not found or already stopped."
                return
            fi
            log "Stopping Jenkins EC2 ($iid)..."
            aws ec2 stop-instances --instance-ids "$iid" --output text > /dev/null
            ok "Jenkins EC2 stop initiated. Billing for compute stops within minutes."
            ;;
        eks-nodes)
            log "Scaling EKS node group '${NODEGROUP_NAME}' to 0..."
            aws eks update-nodegroup-config \
                --cluster-name "$CLUSTER_NAME" \
                --nodegroup-name "$NODEGROUP_NAME" \
                --scaling-config "minSize=0,maxSize=0,desiredSize=0" > /dev/null
            ok "Node group scaling to 0. EC2 node billing stops once instances terminate."
            ;;
        monitoring)
            log "Uninstalling Helm release 'monitoring' from namespace 'monitoring'..."
            helm uninstall monitoring -n monitoring 2>/dev/null || warn "Release not found."
            ok "Monitoring stack removed."
            ;;
        nat)
            log "To stop the NAT Gateway, run a targeted Terraform destroy:"
            echo "  cd ${TF_DIR}"
            echo "  terraform destroy -target=aws_nat_gateway.main -target=aws_eip.nat"
            echo ""
            warn "This will break outbound internet from private subnets (EKS nodes can't pull images)."
            ;;
        "")
            err "Usage: $0 stop <jenkins|eks-nodes|monitoring|nat>"
            return 1
            ;;
        *)
            err "Unknown component: $component"
            err "Valid components: jenkins, eks-nodes, monitoring, nat"
            return 1
            ;;
    esac
}

cmd_start() {
    local component="${1:-}"
    case "$component" in
        jenkins)
            local iid
            iid="$(jenkins_instance_id)"
            if [[ "$iid" == "None" || -z "$iid" ]]; then
                warn "Jenkins instance not found."
                return
            fi
            log "Starting Jenkins EC2 ($iid)..."
            aws ec2 start-instances --instance-ids "$iid" --output text > /dev/null
            aws ec2 wait instance-running --instance-ids "$iid"
            local new_ip
            new_ip=$(aws ec2 describe-instances --instance-ids "$iid" \
                --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
            ok "Jenkins EC2 running. UI: http://${new_ip}:8080"
            ;;
        eks-nodes)
            log "Scaling EKS node group '${NODEGROUP_NAME}' to desired=${NODE_DESIRED}..."
            aws eks update-nodegroup-config \
                --cluster-name "$CLUSTER_NAME" \
                --nodegroup-name "$NODEGROUP_NAME" \
                --scaling-config "minSize=${NODE_MIN},maxSize=${NODE_MAX},desiredSize=${NODE_DESIRED}" > /dev/null
            ok "Node group scaling up. Nodes will be Ready in 2-3 minutes."
            ;;
        monitoring)
            local values_file="${SCRIPT_DIR}/monitoring/kube-prometheus-values.yaml"
            if [[ ! -f "$values_file" ]]; then
                err "Values file not found: $values_file"
                return 1
            fi
            log "Installing monitoring stack via Helm..."
            helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
            helm repo update > /dev/null
            helm install monitoring prometheus-community/kube-prometheus-stack \
                -n monitoring --create-namespace -f "$values_file"
            ok "Monitoring stack deployed."
            ;;
        nat)
            log "To recreate the NAT Gateway, run a targeted Terraform apply:"
            echo "  cd ${TF_DIR}"
            echo "  terraform apply -target=aws_eip.nat -target=aws_nat_gateway.main"
            ;;
        "")
            err "Usage: $0 start <jenkins|eks-nodes|monitoring|nat>"
            return 1
            ;;
        *)
            err "Unknown component: $component"
            err "Valid components: jenkins, eks-nodes, monitoring, nat"
            return 1
            ;;
    esac
}

cmd_destroy() {
    local destroy_all=false
    if [[ "${1:-}" == "--all" ]]; then
        destroy_all=true
    fi

    echo ""
    if $destroy_all; then
        warn "This will destroy ALL project resources AND the bootstrap infrastructure."
        warn "The Terraform state bucket and IAM user will be permanently deleted."
    else
        warn "This will destroy all Terraform-managed resources (VPC, EKS, EC2, IAM roles)."
        warn "Bootstrap resources (S3 state bucket, IAM user) will be preserved."
    fi
    echo ""

    if ! confirm "Proceed with destruction?"; then
        log "Aborted."
        return 0
    fi

    # Step 1: Helm releases
    log "Step 1/5: Removing Helm releases..."
    helm uninstall monitoring -n monitoring 2>/dev/null && ok "Monitoring uninstalled." || warn "No monitoring release found."

    # Step 2: K8s namespaces (triggers PVC/LB cleanup)
    log "Step 2/5: Deleting Kubernetes namespaces..."
    kubectl delete namespace seyoawe --ignore-not-found --timeout=120s 2>/dev/null || warn "Namespace 'seyoawe' not found or kubectl not configured."
    kubectl delete namespace monitoring --ignore-not-found --timeout=120s 2>/dev/null || warn "Namespace 'monitoring' not found or kubectl not configured."

    # Step 3: Wait for any lingering ELBs/ENIs (EKS can create these outside TF)
    log "Step 3/5: Waiting 15s for AWS resource cleanup (ELBs, ENIs)..."
    sleep 15

    # Step 4: Terraform destroy
    log "Step 4/5: Running terraform destroy..."
    if [[ -d "$TF_DIR" ]] && [[ -f "${TF_DIR}/main.tf" ]]; then
        (cd "$TF_DIR" && terraform destroy -auto-approve)
        ok "Terraform destroy complete."
    else
        warn "Terraform directory not found or not initialized at ${TF_DIR}. Skipping."
    fi

    # Step 5: Bootstrap cleanup (only with --all)
    if $destroy_all; then
        log "Step 5/5: Destroying bootstrap resources..."
        local bucket
        bucket="$(s3_bucket_name)"

        if confirm "Delete S3 bucket '${bucket}' and ALL its contents (Terraform state)?"; then
            log "Emptying and deleting S3 bucket: ${bucket}"
            aws s3 rb "s3://${bucket}" --force 2>/dev/null && ok "Bucket deleted." || warn "Bucket not found or already deleted."
        fi

        if confirm "Delete IAM user 'terraform-deployer' and its access keys?"; then
            log "Removing access keys and deleting IAM user..."
            local keys
            keys=$(aws iam list-access-keys --user-name terraform-deployer --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null || echo "")
            for key in $keys; do
                aws iam delete-access-key --user-name terraform-deployer --access-key-id "$key" 2>/dev/null
            done
            aws iam detach-user-policy --user-name terraform-deployer \
                --policy-arn arn:aws:iam::aws:policy/AdministratorAccess 2>/dev/null || true
            aws iam delete-user --user-name terraform-deployer 2>/dev/null && ok "IAM user deleted." || warn "User not found."
        fi
    else
        log "Step 5/5: Skipped (bootstrap resources preserved). Use --all to remove them."
    fi

    echo ""
    ok "Destruction complete."
    if $destroy_all; then
        ok "Zero residual footprint. All project resources have been purged."
    else
        warn "Bootstrap resources (S3 bucket, IAM user) still exist for future re-apply."
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: ./lifecycle.sh <command> [options]

Commands:
  status                Show current state of all project resources
  stop  <component>     Suspend a component to halt its billing
  start <component>     Resume a previously suspended component
  destroy               Tear down Helm + K8s + Terraform resources
  destroy --all         Full teardown including bootstrap (S3 bucket, IAM user)

Components:
  jenkins               Stop/start the Jenkins EC2 instance
  eks-nodes             Scale EKS node group to 0 / restore to desired count
  monitoring            Uninstall / reinstall the Prometheus+Grafana Helm stack
  nat                   Guidance to destroy / recreate the NAT Gateway via Terraform

Environment variables:
  AWS_PROFILE           AWS CLI profile (default: seyoawe-tf)
  AWS_REGION            Override region detection
  TF_DIR                Path to terraform directory (default: ./terraform)
EOF
}

main() {
    local cmd="${1:-}"
    shift || true

    case "$cmd" in
        status)   cmd_status ;;
        stop)     cmd_stop "$@" ;;
        start)    cmd_start "$@" ;;
        destroy)  cmd_destroy "$@" ;;
        help|-h|--help) usage ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
