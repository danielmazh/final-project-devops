# 0003 — AWS Lifecycle Management Script

## 1. Background & Problem

This is a temporary PoC environment. Every AWS resource costs money while running, and forgotten resources (NAT Gateways, EKS node groups, EC2 instances) can silently accumulate hundreds of dollars in charges. Terraform manages the bulk of infrastructure, but Helm releases (Prometheus/Grafana) and Kubernetes resources live outside of Terraform state. There is no single command today that guarantees a complete teardown of everything the project has created.

Additionally, during active development it is useful to *suspend* expensive components (stop the Jenkins EC2, scale EKS nodes to 0) without destroying the entire stack, then resume later.

**Root cause:** No unified lifecycle controller that spans Terraform + Helm + K8s + bootstrap resources.

## 2. Questions & Answers

| Question | Answer |
|----------|--------|
| Should the script wrap Terraform directly? | **Yes.** It calls `terraform destroy` in the correct directory with the correct profile. No re-implementation of destroy logic. |
| What about Helm releases? | The script must `helm uninstall` any releases before Terraform destroys the EKS cluster, otherwise the LB/EBS finalizers can block deletion. |
| What about K8s PVCs? | PVCs with `reclaimPolicy: Retain` survive pod/namespace deletion. The script deletes PVCs explicitly, then waits for EBS volumes to detach. |
| Bootstrap resources (S3 bucket, IAM user)? | The `--all` flag must also offer to destroy these. They live outside Terraform state. The script uses AWS CLI directly for them. |
| How do we prevent orphans as new resources are added in later phases? | A mandatory **resource registry** section inside the script, plus a Cursor rule that requires every new cloud resource to be registered. |

## 3. Design & Solution

### 3.1 Script location and interface

**File:** `lifecycle.sh` (project root, executable)

```
Usage: ./lifecycle.sh <command> [options]

Commands:
  status              Show what is currently running and estimated cost
  stop [component]    Suspend a component to halt billing
  start [component]   Resume a previously suspended component
  destroy             Tear down all Terraform-managed resources
  destroy --all       Tear down everything including bootstrap (S3, IAM)

Components:
  jenkins             Stop/start the Jenkins EC2 instance
  eks-nodes           Scale EKS node group to 0 / restore to desired count
  monitoring          Uninstall / reinstall the Helm monitoring stack
  nat                 Delete / recreate the NAT Gateway (stops private subnet egress)

Environment:
  AWS_PROFILE         Defaults to 'seyoawe-tf'
  AWS_REGION          Read from terraform/variables.tf or override
  TF_DIR              Defaults to './terraform'
```

### 3.2 Resource registry

The script contains a clearly delimited registry block that enumerates every cloud resource the project creates. Each entry has a type, identifier, and the layer that manages it.

```bash
# ── RESOURCE REGISTRY ──
# Every cloud resource MUST be listed here.
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
#   route_table   | seyoawe-public-rt              | terraform
#   route_table   | seyoawe-private-rt             | terraform
#
# Helm-managed (must uninstall before terraform destroy):
#   helm_release  | monitoring (ns: monitoring)    | helm
#
# K8s-managed (must delete before terraform destroy):
#   namespace     | seyoawe                        | kubectl
#   namespace     | monitoring                     | kubectl
#   statefulset   | seyoawe-engine (ns: seyoawe)   | kubectl
#   pvc           | data-seyoawe-engine-0          | kubectl
#
# Bootstrap (outside Terraform — manual or --all):
#   s3_bucket     | seyoawe-tf-state-<account-id>  | aws-cli
#   iam_user      | terraform-deployer             | aws-cli
# ── END REGISTRY ──
```

### 3.3 Destroy ordering

The `destroy` command follows this sequence to avoid finalizer deadlocks:

```
1. Helm uninstall (monitoring stack)
2. kubectl delete namespaces (seyoawe, monitoring) — waits for PVC/LB cleanup
3. terraform destroy -auto-approve (VPC, EKS, EC2, IAM roles, NAT, etc.)
4. [--all only] aws s3 rb --force, aws iam delete-user (bootstrap cleanup)
5. Verification: query for any resources tagged Project=seyoawe still existing
```

### 3.4 Stop/start granularity

| Component | Stop action | Start action |
|-----------|-------------|--------------|
| `jenkins` | `aws ec2 stop-instances` | `aws ec2 start-instances`, print new public IP |
| `eks-nodes` | `aws eks update-nodegroup-config --scaling-config minSize=0,maxSize=0,desiredSize=0` | Restore to `min=2,max=2,desired=2` |
| `monitoring` | `helm uninstall monitoring -n monitoring` | `helm install` with saved values |
| `nat` | Terraform-targeted destroy of NAT + EIP | Terraform-targeted apply to recreate |

### 3.5 Status command

Queries each resource in the registry and reports running/stopped/missing with estimated hourly cost.

## 4. Implementation Plan

1. Create `.cursor/design-logs/0003_lifecycle_management_script.md` (this file).
2. Write `lifecycle.sh` in project root.
3. Create `.cursor/rules/resource-registry.mdc` — mandates updating the registry for every new cloud resource.
4. Update master plan Section 2 with the resource-tracking rule.

## 5. Examples

- ✅ Dev pauses for the weekend → `./lifecycle.sh stop jenkins && ./lifecycle.sh stop eks-nodes` → NAT still running ($1/day) but compute is $0.
- ✅ End of semester → `./lifecycle.sh destroy --all` → zero AWS footprint.
- ❌ Only `terraform destroy` without Helm uninstall first → ELB/PVC finalizers block VPC deletion for 30+ minutes.
- ❌ Adding an RDS instance in a later phase without registering it → `destroy` misses it, billing continues silently.

## 6. Trade-offs

| Choice | Rationale |
|--------|-----------|
| Bash script (not Python/Go) | Zero extra dependencies; matches the Terraform/Ansible/shell ecosystem already in use. |
| Registry inside the script (not a YAML manifest) | One file to maintain; grep-able; no parser needed. |
| `--all` requires confirmation prompt | Prevents accidental deletion of the S3 state bucket. |

## 7. Verification Criteria

- [ ] `./lifecycle.sh status` runs and reports state of each component.
- [ ] `./lifecycle.sh stop jenkins` stops the EC2; `start jenkins` restarts it.
- [ ] `./lifecycle.sh destroy` cleans Helm + K8s + Terraform in order.
- [ ] `./lifecycle.sh destroy --all` also removes S3 bucket and IAM user after prompt.
- [ ] Registry block is up to date with all resources from Phase 2 design.

---

## Implementation Results

_(Append only after script is written and tested.)_
