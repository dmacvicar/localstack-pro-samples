# Glacier S3 Select - Terraform configuration

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
    s3      = "http://localhost.localstack.cloud:4566"
    glacier = "http://localhost.localstack.cloud:4566"
  }
}

# Variables
variable "bucket_name" {
  default = "glacier-s3-select"
}

variable "results_bucket" {
  default = "glacier-results"
}

variable "vault_name" {
  default = "glacier-vault"
}

# S3 bucket for CSV data
resource "aws_s3_bucket" "data" {
  bucket        = var.bucket_name
  force_destroy = true
}

# S3 bucket for query results
resource "aws_s3_bucket" "results" {
  bucket        = var.results_bucket
  force_destroy = true
}

# Upload CSV data file
resource "aws_s3_object" "data_csv" {
  bucket = aws_s3_bucket.data.bucket
  key    = "data.csv"
  source = "${path.module}/../data.csv"
  etag   = filemd5("${path.module}/../data.csv")
}

# Glacier vault
resource "aws_glacier_vault" "vault" {
  name = var.vault_name
}

# Outputs
output "bucket_name" {
  value = aws_s3_bucket.data.bucket
}

output "results_bucket" {
  value = aws_s3_bucket.results.bucket
}

output "vault_name" {
  value = aws_glacier_vault.vault.name
}
