# EC2 Docker Instances
# Creates Docker-backed EC2 instance (requires EC2_VM_MANAGER=docker)

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
    ec2 = var.localstack_endpoint
  }
}

variable "region" {
  default = "us-east-1"
}

variable "localstack_endpoint" {
  default = "http://localhost.localstack.cloud:4566"
}

variable "ami_id" {
  default = "ami-00a001"
}

variable "instance_name" {
  default = "ec2-docker-test"
}

# EC2 Instance
resource "aws_instance" "docker_instance" {
  ami           = var.ami_id
  instance_type = "t2.micro"

  tags = {
    Name = var.instance_name
  }
}

# Outputs
output "ami_id" {
  value = var.ami_id
}

output "instance_id" {
  value = aws_instance.docker_instance.id
}

output "instance_name" {
  value = var.instance_name
}

output "private_ip" {
  value = aws_instance.docker_instance.private_ip
}

output "public_ip" {
  value = aws_instance.docker_instance.public_ip
}
