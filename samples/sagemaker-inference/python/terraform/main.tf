terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  endpoints {
    s3        = var.endpoint_url
    iam       = var.endpoint_url
    sts       = var.endpoint_url
    sagemaker = var.endpoint_url
  }

  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  s3_use_path_style = true
}

variable "endpoint_url" {
  default = "http://localhost.localstack.cloud:4566"
}

# S3 bucket for model artifacts
resource "aws_s3_bucket" "model_bucket" {
  bucket        = "sagemaker-models-tf"
  force_destroy = true
}

# Upload model
resource "aws_s3_object" "model" {
  bucket = aws_s3_bucket.model_bucket.id
  key    = "model.tar.gz"
  source = "${path.module}/../data/model.tar.gz"
}

# IAM role for SageMaker
resource "aws_iam_role" "sagemaker_role" {
  name = "sagemaker-role-tf"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sagemaker.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# SageMaker model
resource "aws_sagemaker_model" "model" {
  name               = "sample-tf"
  execution_role_arn = aws_iam_role.sagemaker_role.arn

  primary_container {
    image          = "763104351884.dkr.ecr.us-east-1.amazonaws.com/pytorch-inference:1.5.0-cpu-py3"
    model_data_url = "s3://${aws_s3_bucket.model_bucket.id}/model.tar.gz"
  }

  depends_on = [aws_s3_object.model]
}

# SageMaker endpoint configuration
resource "aws_sagemaker_endpoint_configuration" "config" {
  name = "sample-cf-tf"

  production_variants {
    variant_name           = "var-1"
    model_name             = aws_sagemaker_model.model.name
    initial_instance_count = 1
    instance_type          = "ml.m5.large"
  }
}

# SageMaker endpoint
resource "aws_sagemaker_endpoint" "endpoint" {
  name                 = "sample-ep-tf"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.config.name
}

output "s3_bucket" {
  value = aws_s3_bucket.model_bucket.id
}

output "model_name" {
  value = aws_sagemaker_model.model.name
}

output "config_name" {
  value = aws_sagemaker_endpoint_configuration.config.name
}

output "endpoint_name" {
  value = aws_sagemaker_endpoint.endpoint.name
}
