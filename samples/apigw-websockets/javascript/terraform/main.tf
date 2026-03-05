terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
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
    lambda         = "http://localhost.localstack.cloud:4566"
    iam            = "http://localhost.localstack.cloud:4566"
    apigatewayv2   = "http://localhost.localstack.cloud:4566"
  }
}

variable "region" {
  default = "us-east-1"
}

variable "api_name" {
  default = "apigw-websockets-tf"
}

# Archive the handler
data "archive_file" "function_zip" {
  type        = "zip"
  source_file = "${path.module}/../handler.js"
  output_path = "${path.module}/function.zip"
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.api_name}-lambda-role"

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

# Lambda Functions
resource "aws_lambda_function" "connection_handler" {
  function_name    = "${var.api_name}-connectionHandler"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.handler"
  runtime          = "nodejs18.x"
  filename         = data.archive_file.function_zip.output_path
  source_code_hash = data.archive_file.function_zip.output_base64sha256
  timeout          = 30
  memory_size      = 128

  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
}

resource "aws_lambda_function" "default_handler" {
  function_name    = "${var.api_name}-defaultHandler"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.handler"
  runtime          = "nodejs18.x"
  filename         = data.archive_file.function_zip.output_path
  source_code_hash = data.archive_file.function_zip.output_base64sha256
  timeout          = 30
  memory_size      = 128

  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
}

resource "aws_lambda_function" "action_handler" {
  function_name    = "${var.api_name}-actionHandler"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.handler"
  runtime          = "nodejs18.x"
  filename         = data.archive_file.function_zip.output_path
  source_code_hash = data.archive_file.function_zip.output_base64sha256
  timeout          = 30
  memory_size      = 128

  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
}

# WebSocket API
resource "aws_apigatewayv2_api" "websocket_api" {
  name                       = var.api_name
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"
}

# Integrations
resource "aws_apigatewayv2_integration" "connection_integration" {
  api_id             = aws_apigatewayv2_api.websocket_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.connection_handler.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_integration" "default_integration" {
  api_id             = aws_apigatewayv2_api.websocket_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.default_handler.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_integration" "action_integration" {
  api_id             = aws_apigatewayv2_api.websocket_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.action_handler.invoke_arn
  integration_method = "POST"
}

# Routes
resource "aws_apigatewayv2_route" "connect_route" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.connection_integration.id}"
}

resource "aws_apigatewayv2_route" "disconnect_route" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.connection_integration.id}"
}

resource "aws_apigatewayv2_route" "default_route" {
  api_id                              = aws_apigatewayv2_api.websocket_api.id
  route_key                           = "$default"
  target                              = "integrations/${aws_apigatewayv2_integration.default_integration.id}"
  route_response_selection_expression = "$default"
}

resource "aws_apigatewayv2_route" "action_route" {
  api_id                              = aws_apigatewayv2_api.websocket_api.id
  route_key                           = "test-action"
  target                              = "integrations/${aws_apigatewayv2_integration.action_integration.id}"
  route_response_selection_expression = "$default"
}

# Route responses for bidirectional communication
resource "aws_apigatewayv2_route_response" "default_response" {
  api_id             = aws_apigatewayv2_api.websocket_api.id
  route_id           = aws_apigatewayv2_route.default_route.id
  route_response_key = "$default"
}

resource "aws_apigatewayv2_route_response" "action_response" {
  api_id             = aws_apigatewayv2_api.websocket_api.id
  route_id           = aws_apigatewayv2_route.action_route.id
  route_response_key = "$default"
}

# Lambda Permissions
resource "aws_lambda_permission" "connection_permission" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.connection_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "default_permission" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.default_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "action_permission" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.action_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/*"
}

# Stage and Deployment
resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.websocket_api.id
  name        = "prod"
  auto_deploy = true

  depends_on = [
    aws_apigatewayv2_route.connect_route,
    aws_apigatewayv2_route.disconnect_route,
    aws_apigatewayv2_route.default_route,
    aws_apigatewayv2_route.action_route,
  ]
}

# Outputs
output "api_id" {
  value = aws_apigatewayv2_api.websocket_api.id
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.websocket_api.api_endpoint
}

output "stage" {
  value = aws_apigatewayv2_stage.prod.name
}

output "connection_handler_name" {
  value = aws_lambda_function.connection_handler.function_name
}

output "default_handler_name" {
  value = aws_lambda_function.default_handler.function_name
}

output "action_handler_name" {
  value = aws_lambda_function.action_handler.function_name
}
