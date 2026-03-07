# RDS Failover Test - Terraform configuration
# Aurora global cluster with primary (us-east-1) and secondary (us-west-1) clusters

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  alias                       = "primary"
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    rds = "http://localhost.localstack.cloud:4566"
  }
}

provider "aws" {
  alias                       = "secondary"
  region                      = "us-west-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    rds = "http://localhost.localstack.cloud:4566"
  }
}

# Variables
variable "global_cluster_id" {
  default = "global-cluster"
}

variable "primary_cluster_id" {
  default = "rds-cluster-1"
}

variable "secondary_cluster_id" {
  default = "rds-cluster-2"
}

# Global cluster
resource "aws_rds_global_cluster" "global" {
  provider = aws.primary

  global_cluster_identifier = var.global_cluster_id
  engine                    = "aurora-postgresql"
  engine_version            = "13.7"
  database_name             = "test"
}

# Primary cluster (us-east-1)
resource "aws_rds_cluster" "primary" {
  provider = aws.primary

  cluster_identifier        = var.primary_cluster_id
  engine                    = aws_rds_global_cluster.global.engine
  engine_version            = aws_rds_global_cluster.global.engine_version
  database_name             = "test"
  global_cluster_identifier = aws_rds_global_cluster.global.id
  skip_final_snapshot       = true
}

# Primary instance
resource "aws_rds_cluster_instance" "primary" {
  provider = aws.primary

  cluster_identifier = aws_rds_cluster.primary.id
  instance_class     = "db.r5.large"
  engine             = aws_rds_cluster.primary.engine
  engine_version     = aws_rds_cluster.primary.engine_version
  identifier         = "inst-1"
}

# Secondary cluster (us-west-1)
resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = var.secondary_cluster_id
  engine                    = aws_rds_global_cluster.global.engine
  engine_version            = aws_rds_global_cluster.global.engine_version
  global_cluster_identifier = aws_rds_global_cluster.global.id
  skip_final_snapshot       = true

  depends_on = [aws_rds_cluster_instance.primary]
}

# Secondary instance
resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary

  cluster_identifier = aws_rds_cluster.secondary.id
  instance_class     = "db.r5.large"
  engine             = aws_rds_cluster.secondary.engine
  engine_version     = aws_rds_cluster.secondary.engine_version
  identifier         = "inst-2"
}

# Outputs
output "global_cluster_id" {
  value = aws_rds_global_cluster.global.id
}

output "primary_cluster_id" {
  value = aws_rds_cluster.primary.id
}

output "secondary_cluster_id" {
  value = aws_rds_cluster.secondary.id
}

output "primary_arn" {
  value = aws_rds_cluster.primary.arn
}

output "secondary_arn" {
  value = aws_rds_cluster.secondary.arn
}
