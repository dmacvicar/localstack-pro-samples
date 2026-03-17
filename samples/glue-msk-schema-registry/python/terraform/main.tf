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
    ec2                = "http://localhost.localstack.cloud:4566"
    kafka              = "http://localhost.localstack.cloud:4566"
    glue               = "http://localhost.localstack.cloud:4566"
    sts                = "http://localhost.localstack.cloud:4566"
  }
}

# Look up default VPC and subnets
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {}

data "aws_security_group" "default" {
  vpc_id = data.aws_vpc.default.id
  name   = "default"
}

# MSK Cluster
resource "aws_msk_cluster" "main" {
  cluster_name           = "msk-cluster-tf"
  kafka_version          = "3.5.1"
  number_of_broker_nodes = 2

  broker_node_group_info {
    instance_type   = "kafka.m5.xlarge"
    client_subnets  = slice(data.aws_subnets.default.ids, 0, 2)
    security_groups = [data.aws_security_group.default.id]
  }
}

# Glue Schema Registry
resource "aws_glue_registry" "main" {
  registry_name = "registry-tf"
}

# Glue Schema (v1)
resource "aws_glue_schema" "main" {
  schema_name       = "schema-tf"
  registry_arn      = aws_glue_registry.main.arn
  data_format       = "AVRO"
  compatibility     = "BACKWARD"
  schema_definition = file("${path.module}/../schemas/unicorn_ride_request_v1.avsc")
}

output "cluster_name" {
  value = aws_msk_cluster.main.cluster_name
}

output "cluster_arn" {
  value = aws_msk_cluster.main.arn
}

output "registry_name" {
  value = aws_glue_registry.main.registry_name
}

output "registry_arn" {
  value = aws_glue_registry.main.arn
}

output "schema_name" {
  value = aws_glue_schema.main.schema_name
}

output "schema_arn" {
  value = aws_glue_schema.main.arn
}
