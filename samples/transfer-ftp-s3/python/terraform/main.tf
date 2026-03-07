# Transfer FTP to S3 - Terraform configuration

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
    s3       = "http://localhost.localstack.cloud:4566"
    transfer = "http://localhost.localstack.cloud:4566"
    iam      = "http://localhost.localstack.cloud:4566"
  }
}

# Variables
variable "bucket_name" {
  default = "transfer-files"
}

variable "username" {
  default = "ftpuser"
}

# S3 bucket for file storage
resource "aws_s3_bucket" "transfer" {
  bucket        = var.bucket_name
  force_destroy = true
}

# IAM role for Transfer service
resource "aws_iam_role" "transfer" {
  name = "transfer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "transfer.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# IAM policy for Transfer service to access S3
resource "aws_iam_role_policy" "transfer_s3" {
  name = "transfer-s3-access"
  role = aws_iam_role.transfer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.transfer.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.transfer.arn}/*"
      }
    ]
  })
}

# Transfer server with FTP protocol
resource "aws_transfer_server" "ftp" {
  endpoint_type          = "PUBLIC"
  identity_provider_type = "SERVICE_MANAGED"
  protocols              = ["FTP"]
}

# Transfer user
resource "aws_transfer_user" "user" {
  server_id = aws_transfer_server.ftp.id
  user_name = var.username
  role      = aws_iam_role.transfer.arn

  home_directory_type = "PATH"
  home_directory      = "/${var.bucket_name}"
}

# Outputs
output "server_id" {
  value = aws_transfer_server.ftp.id
}

output "bucket_name" {
  value = aws_s3_bucket.transfer.bucket
}

output "username" {
  value = aws_transfer_user.user.user_name
}
