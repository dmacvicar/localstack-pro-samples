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
    s3            = var.endpoint_url
    iam           = var.endpoint_url
    sts           = var.endpoint_url
    emrserverless = var.endpoint_url
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

# S3 bucket for job artifacts and logs
resource "aws_s3_bucket" "emr_bucket" {
  bucket        = "emr-spark-tf"
  force_destroy = true
}

# Upload JAR
resource "aws_s3_object" "job_jar" {
  bucket = aws_s3_bucket.emr_bucket.id
  key    = "code/java-spark/java-demo-1.0.jar"
  source = "${path.module}/../hello-world/target/java-demo-1.0.jar"
}

# IAM role for EMR Serverless
resource "aws_iam_role" "emr_role" {
  name = "emr-serverless-role-tf"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "emr-serverless.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# EMR Serverless application
resource "aws_emrserverless_application" "spark_app" {
  name          = "serverless-java-demo-tf"
  release_label = "emr-6.9.0"
  type          = "spark"
}

output "app_name" {
  value = aws_emrserverless_application.spark_app.name
}

output "app_id" {
  value = aws_emrserverless_application.spark_app.id
}

output "s3_bucket" {
  value = aws_s3_bucket.emr_bucket.id
}

output "job_role_arn" {
  value = aws_iam_role.emr_role.arn
}
