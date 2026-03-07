# CloudWatch Metrics with Lambda and SNS Alarm
# Creates Lambda, SNS topic, and CloudWatch alarm

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
    lambda     = var.localstack_endpoint
    sns        = var.localstack_endpoint
    cloudwatch = var.localstack_endpoint
    iam        = var.localstack_endpoint
  }
}

variable "region" {
  default = "us-east-1"
}

variable "localstack_endpoint" {
  default = "http://localhost.localstack.cloud:4566"
}

variable "function_name" {
  default = "cw-failing-lambda"
}

variable "topic_name" {
  default = "cw-alarm-topic"
}

variable "alarm_name" {
  default = "cw-lambda-alarm"
}

variable "test_email" {
  default = "test@example.com"
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "cw-lambda-role"

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

# Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../handler.py"
  output_path = "${path.module}/handler.zip"
}

# Lambda function
resource "aws_lambda_function" "failing_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.function_name
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 30
}

# SNS Topic
resource "aws_sns_topic" "alarm_topic" {
  name = var.topic_name
}

# SNS Email Subscription
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarm_topic.arn
  protocol  = "email"
  endpoint  = var.test_email
}

# CloudWatch Alarm
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = var.alarm_name
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarm_topic.arn]

  dimensions = {
    FunctionName = aws_lambda_function.failing_lambda.function_name
  }
}

# Outputs
output "function_name" {
  value = aws_lambda_function.failing_lambda.function_name
}

output "lambda_arn" {
  value = aws_lambda_function.failing_lambda.arn
}

output "topic_name" {
  value = aws_sns_topic.alarm_topic.name
}

output "topic_arn" {
  value = aws_sns_topic.alarm_topic.arn
}

output "alarm_name" {
  value = aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
}

output "test_email" {
  value = var.test_email
}
