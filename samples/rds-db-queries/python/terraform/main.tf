# RDS Database Queries - Terraform configuration
# Creates a PostgreSQL RDS instance for database queries

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
    rds = "http://localhost.localstack.cloud:4566"
  }
}

# Variables
variable "db_instance_id" {
  default = "rds-db"
}

variable "db_name" {
  default = "testdb"
}

variable "db_user" {
  default = "testuser"
}

variable "db_password" {
  default = "testpass123"
}

# RDS PostgreSQL instance
resource "aws_db_instance" "main" {
  identifier          = var.db_instance_id
  engine              = "postgres"
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  db_name             = var.db_name
  username            = var.db_user
  password            = var.db_password
  skip_final_snapshot = true
}

# Outputs
output "db_instance_id" {
  value = aws_db_instance.main.identifier
}

output "db_name" {
  value = var.db_name
}

output "db_user" {
  value = var.db_user
}

output "db_password" {
  value     = var.db_password
  sensitive = true
}
