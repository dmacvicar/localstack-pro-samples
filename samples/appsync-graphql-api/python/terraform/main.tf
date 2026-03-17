# AppSync GraphQL API - Terraform configuration
# Creates AppSync API with DynamoDB and RDS Aurora data sources

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
    appsync          = "http://localhost.localstack.cloud:4566"
    dynamodb         = "http://localhost.localstack.cloud:4566"
    iam              = "http://localhost.localstack.cloud:4566"
    rds              = "http://localhost.localstack.cloud:4566"
    secretsmanager   = "http://localhost.localstack.cloud:4566"
  }
}

variable "table_name" {
  default = "appsync-table-tf"
}

variable "db_cluster_id" {
  default = "appsync-rds-tf"
}

variable "db_name" {
  default = "testappsync"
}

variable "db_user" {
  default = "testuser"
}

variable "db_password" {
  default = "testpass"
}

# DynamoDB table
resource "aws_dynamodb_table" "posts" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# RDS Aurora PostgreSQL cluster
resource "aws_rds_cluster" "main" {
  cluster_identifier = var.db_cluster_id
  engine             = "aurora-postgresql"
  master_username    = var.db_user
  master_password    = var.db_password
  database_name      = var.db_name
  skip_final_snapshot = true
}

# Secrets Manager secret for RDS
resource "aws_secretsmanager_secret" "rds" {
  name                    = "appsync-rds-secret-tf"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id     = aws_secretsmanager_secret.rds.id
  secret_string = var.db_password
}

# IAM role for AppSync
resource "aws_iam_role" "appsync" {
  name = "appsync-role-tf"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "appsync.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "appsync_ddb" {
  name = "appsync-ddb-policy"
  role = aws_iam_role.appsync.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "dynamodb:*"
      Resource = aws_dynamodb_table.posts.arn
    }]
  })
}

resource "aws_iam_role_policy" "appsync_rds" {
  name = "appsync-rds-policy"
  role = aws_iam_role.appsync.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["rds-data:*", "secretsmanager:GetSecretValue"]
      Resource = "*"
    }]
  })
}

# AppSync GraphQL API
resource "aws_appsync_graphql_api" "main" {
  name                = "appsync-api-tf"
  authentication_type = "API_KEY"

  schema = file("${path.module}/../schema.graphql")
}

# API Key
resource "aws_appsync_api_key" "main" {
  api_id = aws_appsync_graphql_api.main.id
}

# DynamoDB data source
resource "aws_appsync_datasource" "ddb" {
  api_id           = aws_appsync_graphql_api.main.id
  name             = "ds_ddb"
  type             = "AMAZON_DYNAMODB"
  service_role_arn = aws_iam_role.appsync.arn

  dynamodb_config {
    table_name = aws_dynamodb_table.posts.name
    region     = "us-east-1"
  }
}

# RDS data source
resource "aws_appsync_datasource" "rds" {
  api_id           = aws_appsync_graphql_api.main.id
  name             = "ds_rds"
  type             = "RELATIONAL_DATABASE"
  service_role_arn = aws_iam_role.appsync.arn

  relational_database_config {
    source_type = "RDS_HTTP_ENDPOINT"

    http_endpoint_config {
      aws_secret_store_arn = aws_secretsmanager_secret.rds.arn
      db_cluster_identifier = aws_rds_cluster.main.arn
      database_name         = var.db_name
      region                = "us-east-1"
    }
  }
}

# DynamoDB resolvers
resource "aws_appsync_resolver" "add_post_ddb" {
  api_id      = aws_appsync_graphql_api.main.id
  type        = "Mutation"
  field       = "addPostDDB"
  data_source = aws_appsync_datasource.ddb.name

  request_template  = file("${path.module}/../templates/ddb.PutItem.request.vlt")
  response_template = file("${path.module}/../templates/ddb.PutItem.response.vlt")
}

resource "aws_appsync_resolver" "get_posts_ddb" {
  api_id      = aws_appsync_graphql_api.main.id
  type        = "Query"
  field       = "getPostsDDB"
  data_source = aws_appsync_datasource.ddb.name

  request_template  = file("${path.module}/../templates/ddb.Scan.request.vlt")
  response_template = file("${path.module}/../templates/ddb.Scan.response.vlt")
}

# RDS resolvers
resource "aws_appsync_resolver" "add_post_rds" {
  api_id      = aws_appsync_graphql_api.main.id
  type        = "Mutation"
  field       = "addPostRDS"
  data_source = aws_appsync_datasource.rds.name

  request_template  = file("${path.module}/../templates/rds.insert.request.vlt")
  response_template = file("${path.module}/../templates/rds.insert.response.vlt")
}

resource "aws_appsync_resolver" "get_posts_rds" {
  api_id      = aws_appsync_graphql_api.main.id
  type        = "Query"
  field       = "getPostsRDS"
  data_source = aws_appsync_datasource.rds.name

  request_template  = file("${path.module}/../templates/rds.select.request.vlt")
  response_template = file("${path.module}/../templates/rds.select.response.vlt")
}

# Outputs
output "api_id" {
  value = aws_appsync_graphql_api.main.id
}

output "api_url" {
  value = aws_appsync_graphql_api.main.uris["GRAPHQL"]
}

output "api_key" {
  value     = aws_appsync_api_key.main.key
  sensitive = true
}

output "api_name" {
  value = aws_appsync_graphql_api.main.name
}

output "table_name" {
  value = aws_dynamodb_table.posts.name
}

output "db_cluster_id" {
  value = aws_rds_cluster.main.cluster_identifier
}

output "db_cluster_arn" {
  value = aws_rds_cluster.main.arn
}

output "db_name" {
  value = var.db_name
}

output "secret_arn" {
  value = aws_secretsmanager_secret.rds.arn
}

output "role_arn" {
  value = aws_iam_role.appsync.arn
}
