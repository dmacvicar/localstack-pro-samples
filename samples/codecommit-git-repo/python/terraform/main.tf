terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
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
    codecommit = "http://localhost.localstack.cloud:4566"
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  repo_name = "repo-${random_id.suffix.hex}"
}

resource "aws_codecommit_repository" "main" {
  repository_name = local.repo_name
  description     = "Test repository for LocalStack CodeCommit sample"
}

output "repo_name" {
  value = aws_codecommit_repository.main.repository_name
}

output "repo_arn" {
  value = aws_codecommit_repository.main.arn
}

output "repo_id" {
  value = aws_codecommit_repository.main.repository_id
}

output "clone_url_ssh" {
  value = aws_codecommit_repository.main.clone_url_ssh
}

output "clone_url_http" {
  value = aws_codecommit_repository.main.clone_url_http
}
