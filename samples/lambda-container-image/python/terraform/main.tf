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
    ecr    = "http://localhost:4566"
    lambda = "http://localhost:4566"
    iam    = "http://localhost:4566"
  }
}

variable "region" {
  default = "us-east-1"
}

variable "function_name" {
  default = "lambda-container-tf"
}

variable "repo_name" {
  default = "lambda-container-tf"
}

# ECR Repository
resource "aws_ecr_repository" "lambda_repo" {
  name                 = var.repo_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda Function (created after image is pushed)
resource "aws_lambda_function" "container_lambda" {
  function_name = var.function_name
  role          = aws_iam_role.lambda_role.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.lambda_repo.repository_url}:latest"
  timeout       = 30
  memory_size   = 256

  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
}

output "function_name" {
  value = aws_lambda_function.container_lambda.function_name
}

output "repo_name" {
  value = aws_ecr_repository.lambda_repo.name
}

output "repo_uri" {
  value = aws_ecr_repository.lambda_repo.repository_url
}
