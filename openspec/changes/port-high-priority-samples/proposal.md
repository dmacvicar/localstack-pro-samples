## Why

Port samples from the original localstack-pro-samples repository to provide comprehensive AWS service examples for LocalStack users.

**Source Repository:** https://github.com/localstack-samples/localstack-pro-samples

## What Changes

### Ported from Original Repo

| Original Sample | Target Location | Status |
|-----------------|-----------------|--------|
| `lambda-function-urls-python` | `samples/lambda-function-urls/python` | Done |
| `stepfunctions-lambda` | `samples/stepfunctions-lambda/python` | Done |
| `serverless-lambda-layers` | `samples/lambda-layers/javascript` | To Do |
| `serverless-websockets` | `samples/apigw-websockets/javascript` | To Do |
| `ecs-ecr-container-app` | `samples/ecs-ecr-app/python` | To Do |
| `apigw-custom-domain` | `samples/apigw-custom-domain/python` | To Do |

### New Samples (Not from Original)

These samples were created new to fill gaps:

| Sample | Description | Status |
|--------|-------------|--------|
| `lambda-cloudfront/python` | Lambda + CloudFront pattern | Done |
| `lambda-s3-http/python` | Lambda + S3 + SQS pattern | Done |
| `web-app-dynamodb/python` | Web app with DynamoDB | Done |
| `web-app-rds/python` | Web app with RDS PostgreSQL | Done |

## Capabilities

### Ported Capabilities

- **lambda-function-urls/python**: Lambda Function URLs with public HTTP access
  - Ported from: `lambda-function-urls-python`
  - Tests: function creation, URL configuration, direct invocation, HTTP GET/POST

- **stepfunctions-lambda/python**: Step Functions parallel workflow
  - Ported from: `stepfunctions-lambda`
  - Tests: individual Lambda functions, state machine creation, execution flow

### New Capabilities

- **lambda-cloudfront/python**: Lambda with Function URL (CloudFront-ready)
- **lambda-s3-http/python**: Gaming scoreboard with Lambda, S3, SQS, DynamoDB
- **web-app-dynamodb/python**: CRUD API with Lambda + DynamoDB
- **web-app-rds/python**: Web API with Lambda + RDS PostgreSQL

## Impact

- Expands sample coverage for LocalStack users
- Preserves original sample implementations where applicable
- All 6 current samples pass CI tests
