# Glue ETL Jobs - Terraform configuration
# Aurora PostgreSQL + Glue catalog (database, tables, JDBC connection, job) + S3

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
    s3              = "http://localhost.localstack.cloud:4566"
    rds             = "http://localhost.localstack.cloud:4566"
    glue            = "http://localhost.localstack.cloud:4566"
    secretsmanager  = "http://localhost.localstack.cloud:4566"
  }

  s3_use_path_style = true
}

locals {
  cluster_id      = "glue-etl-cluster1"
  connection_name = "glue-etl-cluster1-connection"
  glue_db_name    = "legislators"
  job_name        = "test-job1"
  script_bucket   = "glue-pyspark-test"
  target_bucket   = "glue-sample-target"
}

# S3 buckets
resource "aws_s3_bucket" "scripts" {
  bucket        = local.script_bucket
  force_destroy = true
}

resource "aws_s3_bucket" "target" {
  bucket        = local.target_bucket
  force_destroy = true
}

# Upload PySpark job script
resource "aws_s3_object" "job_script" {
  bucket = aws_s3_bucket.scripts.id
  key    = "job.py"
  source = "${path.module}/../src/job.py"
  etag   = filemd5("${path.module}/../src/job.py")
}

# Aurora PostgreSQL cluster
resource "aws_rds_cluster" "glue_etl" {
  cluster_identifier = local.cluster_id
  engine             = "aurora-postgresql"
  database_name      = "test"
  skip_final_snapshot = true
}

# Secrets Manager secret for RDS auth
resource "aws_secretsmanager_secret" "rds_password" {
  name = "pass"
}

resource "aws_secretsmanager_secret_version" "rds_password" {
  secret_id     = aws_secretsmanager_secret.rds_password.id
  secret_string = "test"
}

# Glue database
resource "aws_glue_catalog_database" "legislators" {
  name = local.glue_db_name
}

# Glue tables
resource "aws_glue_catalog_table" "memberships" {
  name          = "memberships_json"
  database_name = aws_glue_catalog_database.legislators.name

  parameters = {
    connectionName = local.connection_name
  }

  storage_descriptor {
    location = "test.memberships"
  }
}

resource "aws_glue_catalog_table" "persons" {
  name          = "persons_json"
  database_name = aws_glue_catalog_database.legislators.name

  parameters = {
    connectionName = local.connection_name
  }

  storage_descriptor {
    location = "test.persons"
  }
}

resource "aws_glue_catalog_table" "organizations" {
  name          = "organizations_json"
  database_name = aws_glue_catalog_database.legislators.name

  parameters = {
    connectionName = local.connection_name
  }

  storage_descriptor {
    location = "test.organizations"
  }
}

# Glue JDBC connection
resource "aws_glue_connection" "jdbc" {
  name            = local.connection_name
  connection_type = "JDBC"

  connection_properties = {
    USERNAME            = "test"
    PASSWORD            = "test"
    JDBC_CONNECTION_URL = "jdbc:postgresql://localhost.localstack.cloud:${aws_rds_cluster.glue_etl.port}"
  }
}

# Glue job
resource "aws_glue_job" "etl" {
  name     = local.job_name
  role_arn = "arn:aws:iam::000000000000:role/r1"

  command {
    name            = "pythonshell"
    script_location = "s3://${local.script_bucket}/job.py"
  }

  connections = [local.cluster_id]

  depends_on = [
    aws_s3_object.job_script,
    aws_glue_connection.jdbc,
    aws_glue_catalog_table.memberships,
    aws_glue_catalog_table.persons,
    aws_glue_catalog_table.organizations,
  ]
}

# Outputs
output "cluster_id" {
  value = aws_rds_cluster.glue_etl.cluster_identifier
}

output "cluster_port" {
  value = aws_rds_cluster.glue_etl.port
}

output "connection_name" {
  value = aws_glue_connection.jdbc.name
}

output "job_name" {
  value = aws_glue_job.etl.name
}

output "script_bucket" {
  value = aws_s3_bucket.scripts.id
}

output "target_bucket" {
  value = aws_s3_bucket.target.id
}

output "secret_arn" {
  value = aws_secretsmanager_secret.rds_password.arn
}
