## Why

Provide comprehensive AWS service examples for LocalStack users.

## What "Porting" Means

Each sample must include:

1. **All IaC methods**: scripts/, terraform/, cloudformation/, cdk/ directories
2. **deploy.sh**: Deploys all resources for that IaC method
3. **teardown.sh**: Cleans up all resources (counterpart to deploy.sh)
4. **pytest tests**: Tests in `test_<sample>.py` parameterized by IaC method
5. **Consistent .env output**: All deploy scripts write to `scripts/.env`

The sample should work independently with any IaC method, starting from a fresh LocalStack.

## What Changes

### Samples

| Sample | Description | Status |
|--------|-------------|--------|
| `lambda-function-urls/python` | Lambda Function URLs with public HTTP access | Done |
| `stepfunctions-lambda/python` | Step Functions parallel workflow | Done |
| `lambda-layers/javascript` | Lambda Layers with Serverless Framework | Done |
| `lambda-cloudfront/python` | Lambda + CloudFront pattern | Done |
| `lambda-s3-http/python` | Lambda + S3 + SQS pattern | Done |
| `web-app-dynamodb/python` | Web app with DynamoDB | Done |
| `web-app-rds/python` | Web app with RDS PostgreSQL | Done |
| `apigw-websockets/javascript` | WebSockets with Serverless Framework | In Progress |
| `ecs-ecr-app/python` | ECS with ECR container app | To Do |
| `apigw-custom-domain/python` | API Gateway custom domain | To Do |

## Capabilities

- **lambda-function-urls/python**: Lambda Function URLs with public HTTP access
- **stepfunctions-lambda/python**: Step Functions parallel workflow with Lambda
- **lambda-layers/javascript**: Lambda Layers using Serverless Framework
- **lambda-cloudfront/python**: Lambda with Function URL (CloudFront-ready)
- **lambda-s3-http/python**: Gaming scoreboard with Lambda, S3, SQS, DynamoDB
- **web-app-dynamodb/python**: CRUD API with Lambda + DynamoDB
- **web-app-rds/python**: Web API with Lambda + RDS PostgreSQL

## Impact

- Expands sample coverage for LocalStack users
- All 6 current samples pass CI tests
