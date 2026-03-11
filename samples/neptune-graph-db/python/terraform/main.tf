# Neptune Graph Database - Terraform configuration
# Creates a Neptune cluster for graph database queries

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    neptune = "http://localhost.localstack.cloud:4566"
  }
}

# Variables
variable "cluster_id" {
  default = "neptune-test-cluster"
}

# Neptune cluster
resource "aws_neptune_cluster" "main" {
  cluster_identifier  = var.cluster_id
  engine              = "neptune"
  skip_final_snapshot = true
}

# Outputs
output "cluster_id" {
  value = aws_neptune_cluster.main.cluster_identifier
}

output "cluster_arn" {
  value = aws_neptune_cluster.main.arn
}

output "cluster_endpoint" {
  value = aws_neptune_cluster.main.endpoint
}

output "cluster_port" {
  value = aws_neptune_cluster.main.port
}
