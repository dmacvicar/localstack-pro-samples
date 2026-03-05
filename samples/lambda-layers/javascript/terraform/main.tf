terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
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
    lambda = "http://localhost.localstack.cloud:4566"
    iam    = "http://localhost.localstack.cloud:4566"
  }
}

variable "region" {
  default = "us-east-1"
}

variable "function_name" {
  default = "lambda-layers-tf"
}

variable "layer_name" {
  default = "shared-layer-tf"
}

# Archive the layer
data "archive_file" "layer_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../layer"
  output_path = "${path.module}/layer.zip"
}

# Archive the function
data "archive_file" "function_zip" {
  type        = "zip"
  source_file = "${path.module}/../handler.js"
  output_path = "${path.module}/function.zip"
}

# Lambda Layer
resource "aws_lambda_layer_version" "shared" {
  layer_name          = var.layer_name
  filename            = data.archive_file.layer_zip.output_path
  source_code_hash    = data.archive_file.layer_zip.output_base64sha256
  compatible_runtimes = ["nodejs18.x", "nodejs20.x"]
  description         = "Shared utility library"
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

# Lambda Function
resource "aws_lambda_function" "hello" {
  function_name    = var.function_name
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.hello"
  runtime          = "nodejs18.x"
  filename         = data.archive_file.function_zip.output_path
  source_code_hash = data.archive_file.function_zip.output_base64sha256
  timeout          = 30
  memory_size      = 128
  layers           = [aws_lambda_layer_version.shared.arn]

  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
}

output "function_name" {
  value = aws_lambda_function.hello.function_name
}

output "function_arn" {
  value = aws_lambda_function.hello.arn
}

output "layer_arn" {
  value = aws_lambda_layer_version.shared.arn
}

output "layer_name" {
  value = aws_lambda_layer_version.shared.layer_name
}
