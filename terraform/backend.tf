terraform {
  required_version = ">= 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.90"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    # bucket is passed at init, so the account id stays out of the repo:
    #   terraform init -backend-config="bucket=seyoawe-tf-state-$(aws sts get-caller-identity --query Account --output text)"
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
    profile      = "seyoawe-tf"
  }
}
