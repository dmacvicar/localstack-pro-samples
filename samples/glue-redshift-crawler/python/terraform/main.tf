# Glue Redshift Crawler - Terraform configuration
# Creates Redshift cluster, Glue database, connection, and crawler

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
    glue     = "http://localhost.localstack.cloud:4566"
    redshift = "http://localhost.localstack.cloud:4566"
    iam      = "http://localhost.localstack.cloud:4566"
  }
}

variable "redshift_cluster_id" {
  default = "redshift-tf"
}

variable "redshift_db_name" {
  default = "db1"
}

variable "redshift_username" {
  default = "testuser"
}

variable "redshift_password" {
  default = "testPass123"
}

variable "glue_db_name" {
  default = "gluedb-tf"
}

# IAM role for Glue
resource "aws_iam_role" "glue" {
  name = "glue-crawler-role-tf"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Redshift cluster
resource "aws_redshift_cluster" "main" {
  cluster_identifier = var.redshift_cluster_id
  database_name      = var.redshift_db_name
  master_username    = var.redshift_username
  master_password    = var.redshift_password
  node_type          = "dc2.large"
  cluster_type       = "single-node"
  skip_final_snapshot = true
}

# Glue catalog database
resource "aws_glue_catalog_database" "main" {
  name = var.glue_db_name
}

# Glue JDBC connection to Redshift
resource "aws_glue_connection" "redshift" {
  name = "glueconn-tf"

  connection_properties = {
    USERNAME           = var.redshift_username
    PASSWORD           = var.redshift_password
    JDBC_CONNECTION_URL = "jdbc:redshift://${aws_redshift_cluster.main.endpoint}/${var.redshift_db_name}"
  }

  connection_type = "JDBC"
}

# Glue crawler
resource "aws_glue_crawler" "main" {
  name          = "crawler-tf"
  database_name = aws_glue_catalog_database.main.name
  role          = aws_iam_role.glue.arn

  jdbc_target {
    connection_name = aws_glue_connection.redshift.name
    path            = "${var.redshift_db_name}/%/sales"
  }
}

# Outputs
output "redshift_cluster_id" {
  value = aws_redshift_cluster.main.cluster_identifier
}

output "redshift_db_name" {
  value = var.redshift_db_name
}

output "redshift_table_name" {
  value = "sales"
}

output "redshift_schema_name" {
  value = "public"
}

output "redshift_username" {
  value = var.redshift_username
}

output "redshift_password" {
  value     = var.redshift_password
  sensitive = true
}

output "redshift_host" {
  value = aws_redshift_cluster.main.dns_name
}

output "redshift_port" {
  value = aws_redshift_cluster.main.port
}

output "glue_db_name" {
  value = aws_glue_catalog_database.main.name
}

output "glue_connection_name" {
  value = aws_glue_connection.redshift.name
}

output "glue_crawler_name" {
  value = aws_glue_crawler.main.name
}

output "glue_table_name" {
  value = "${var.redshift_db_name}_public_sales"
}
