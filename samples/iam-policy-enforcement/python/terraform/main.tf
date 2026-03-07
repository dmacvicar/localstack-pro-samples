# IAM Policy Enforcement
# Creates IAM user and policy for testing IAM enforcement

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region                      = var.region
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    iam = var.localstack_endpoint
  }
}

variable "region" {
  default = "us-east-1"
}

variable "localstack_endpoint" {
  default = "http://localhost.localstack.cloud:4566"
}

variable "user_name" {
  default = "iam-test-user"
}

variable "policy_name" {
  default = "iam-test-policy"
}

# IAM Policy
resource "aws_iam_policy" "test_policy" {
  name = var.policy_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowKinesisAndS3"
        Effect = "Allow"
        Action = [
          "kinesis:*",
          "s3:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM User
resource "aws_iam_user" "test_user" {
  name = var.user_name
}

# Attach policy to user
resource "aws_iam_user_policy_attachment" "test_attach" {
  user       = aws_iam_user.test_user.name
  policy_arn = aws_iam_policy.test_policy.arn
}

# IAM Access Key
resource "aws_iam_access_key" "test_key" {
  user = aws_iam_user.test_user.name
}

# Outputs
output "user_name" {
  value = aws_iam_user.test_user.name
}

output "policy_name" {
  value = aws_iam_policy.test_policy.name
}

output "policy_arn" {
  value = aws_iam_policy.test_policy.arn
}

output "access_key_id" {
  value = aws_iam_access_key.test_key.id
}

output "secret_access_key" {
  value     = aws_iam_access_key.test_key.secret
  sensitive = true
}
