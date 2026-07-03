terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "devops-launchboard"
      Environment = "phase-14-terraform-production"
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  ecr_registry   = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  backend_image  = "${local.ecr_registry}/launchboard-backend:${var.image_tag}"
  frontend_image = "${local.ecr_registry}/launchboard-frontend:${var.image_tag}"
}
