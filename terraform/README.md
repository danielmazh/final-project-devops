# terraform/

AWS infrastructure provisioned via Terraform — VPC, EKS cluster, Jenkins EC2, IAM roles, and EBS CSI driver. Uses a flat layout (single `main.tf`) suitable for a single-environment PoC.

## Files

```
terraform/
├── backend.tf               # S3 remote state with use_lockfile (no DynamoDB)
├── main.tf                   # All resources
├── variables.tf              # Input variables with defaults
├── outputs.tf                # Cluster endpoint, Jenkins IP, kubeconfig command
├── terraform.tfvars.example  # Template — copy to terraform.tfvars (gitignored)
└── terraform.tfvars          # Actual values (gitignored — never committed)
```

## Resources Provisioned

```
VPC: 10.0.0.0/16
├── Public Subnet A (10.0.1.0/24) ── NAT Gateway + Jenkins EC2
├── Public Subnet B (10.0.2.0/24)
├── Private Subnet A (10.0.10.0/24) ── EKS Worker Node 1
├── Private Subnet B (10.0.20.0/24) ── EKS Worker Node 2
├── Internet Gateway
├── Route Tables (public → IGW, private → NAT)
│
├── EKS Cluster: seyoawe-cluster (v1.32)
│   ├── Managed Node Group: 2 × t3.medium (private subnets)
│   ├── Addons: vpc-cni, kube-proxy, coredns, aws-ebs-csi-driver
│   └── Access: public + private API endpoint
│
├── Jenkins EC2: t3.medium (public subnet, 30 GiB gp3)
│   └── Security Group: 8080 (UI) from operator IP + GitHub webhook CIDRs, 22 (SSH) from operator IP
│
├── IAM Roles:
│   ├── seyoawe-eks-cluster-role → AmazonEKSClusterPolicy
│   ├── seyoawe-eks-node-role → Worker + CNI + ECR policies
│   └── seyoawe-ebs-csi-role → AmazonEBSCSIDriverPolicy (IRSA)
│
└── OIDC Identity Provider (required for EBS CSI IRSA)
```

## Usage

```bash
# First-time setup
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set jenkins_key_pair and operator_ip

# Initialize (connects to S3 backend)
terraform init

# Review changes
terraform plan

# Apply (~15 minutes for EKS)
terraform apply

# Show outputs
terraform output
# cluster_endpoint, jenkins_public_ip, jenkins_ui_url, kubeconfig_command, vpc_id

# Destroy everything
terraform destroy
```

## State Backend

```hcl
backend "s3" {
  bucket       = "seyoawe-tf-state-632008729195"
  key          = "dev/terraform.tfstate"
  region       = "us-east-1"
  encrypt      = true
  use_lockfile = true   # S3-native locking — no DynamoDB needed (Terraform 1.14+)
}
```

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region |
| `cluster_name` | `seyoawe-cluster` | EKS cluster name |
| `node_instance_type` | `t3.medium` | EKS worker node instance type |
| `node_desired_count` | `2` | Number of EKS worker nodes |
| `jenkins_instance_type` | `t3.medium` | Jenkins EC2 instance type |
| `jenkins_key_pair` | (required) | AWS EC2 key pair name for SSH |
| `operator_ip` | (required) | Your public IP in CIDR (e.g. `1.2.3.4/32`) |

## Cost Estimate

| Resource | Monthly (24/7) |
|----------|---------------|
| EKS control plane | $73 |
| 2 × t3.medium nodes | ~$60 |
| 1 × t3.medium Jenkins | ~$30 |
| NAT Gateway | ~$35 |
| EBS + S3 | ~$4 |
| **Total** | **~$202/mo** |

Use `./lifecycle.sh destroy` or `terraform destroy` after sessions to minimize cost.

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Flat layout (no modules/) | Single environment — nested modules add indirection without PoC benefit |
| Single NAT Gateway | HA not required for coursework; saves ~$32/month |
| Public EKS API endpoint | No bastion or VPN; simplifies kubectl and Jenkins access |
| S3 `use_lockfile` (no DynamoDB) | Terraform 1.14+ feature; eliminates DynamoDB table |
| `AdministratorAccess` on deployer | Lab account; not appropriate for production |
