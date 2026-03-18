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
    s3     = var.endpoint_url
    iam    = var.endpoint_url
    sts    = var.endpoint_url
    lambda = var.endpoint_url
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

# S3 bucket for data and models
resource "aws_s3_bucket" "ml_bucket" {
  bucket        = "reproducible-ml-tf"
  force_destroy = true
}

# Upload data files
resource "aws_s3_object" "digits_csv" {
  bucket = aws_s3_bucket.ml_bucket.id
  key    = "digits.csv.gz"
  source = "${path.module}/../data/digits.csv.gz"
}

resource "aws_s3_object" "digits_rst" {
  bucket = aws_s3_bucket.ml_bucket.id
  key    = "digits.rst"
  source = "${path.module}/../data/digits.rst"
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "ml-lambda-role-tf"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Lambda function code (zipped in deploy.sh)
resource "aws_lambda_function" "train" {
  function_name = "ml-train-tf"
  role          = aws_iam_role.lambda_role.arn
  handler       = "train.handler"
  runtime       = "python3.8"
  timeout       = 600
  filename      = "${path.module}/train.zip"
  layers        = ["arn:aws:lambda:us-east-1:446751924810:layer:python-3-8-scikit-learn-0-22-0:3"]

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.ml_bucket.id
    }
  }
}

resource "aws_lambda_function" "predict" {
  function_name = "ml-predict-tf"
  role          = aws_iam_role.lambda_role.arn
  handler       = "infer.handler"
  runtime       = "python3.8"
  timeout       = 600
  filename      = "${path.module}/infer.zip"
  layers        = ["arn:aws:lambda:us-east-1:446751924810:layer:python-3-8-scikit-learn-0-22-0:3"]

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.ml_bucket.id
    }
  }
}

output "s3_bucket" {
  value = aws_s3_bucket.ml_bucket.id
}

output "train_function" {
  value = aws_lambda_function.train.function_name
}

output "predict_function" {
  value = aws_lambda_function.predict.function_name
}
