# Tasks: Port High Priority Samples

## Completed

- [x] `lambda-function-urls-python` → `samples/lambda-function-urls/python`
- [x] `stepfunctions-lambda` → `samples/stepfunctions-lambda/python`
- [x] `lambda-cloudfront/python`
- [x] `lambda-s3-http/python`
- [x] `web-app-dynamodb/python`
- [x] `web-app-rds/python`
- [x] `lambda-layers/javascript`

### Infrastructure

- [x] Fix Lambda state timing issues in all deploy scripts
- [x] Fix CI workflow to run all tests on push to master
- [x] All 6 samples pass CI

## In Progress

- [x] `serverless-websockets` → `samples/apigw-websockets/javascript`
  - [x] Create directory structure with serverless.yml
  - [x] Write handler.js with WebSocket route handlers
  - [x] Write scripts/deploy.sh
  - [x] Write scripts/test.sh (9 test cases)
  - [x] Deployment works - API created, functions active, routes configured
  - [x] Test WebSocket message round-trip (using uv for websockets library)
  - [x] Add to run-samples.sh
  - [x] Verified via run-samples.sh (act conflicts with running LocalStack)

- [x] `ecs-ecr-container-app` → `samples/ecs-ecr-app/python`
  - [x] Create directory structure with Dockerfile and templates
  - [x] Write CloudFormation templates (ecs-infra.yml, ecs-service.yml)
  - [x] Write scripts/deploy.sh (ECR, Docker push, CloudFormation)
  - [x] Write scripts/test.sh (6 test cases)
  - [x] All tests pass: ECR repo, image, cluster, service, task, HTTP
  - [x] Add to run-samples.sh

- [x] `apigw-custom-domain` → `samples/apigw-custom-domain/python`
  - [x] Create directory structure with handler.py
  - [x] Write scripts/deploy.sh (SSL cert, ACM, Route53, Lambda, API Gateway, custom domain)
  - [x] Write scripts/test.sh (6 test cases)
  - [x] All tests pass: ACM cert, Route53 zone, Lambda, HTTP API, custom domain, API response
  - [x] Add to run-samples.sh

## IaC Methods

Adding Terraform, CloudFormation, and CDK deployment methods:

- [x] `lambda-function-urls/python` - All 3 IaC methods (tested, passing)
- [x] `stepfunctions-lambda/python` - All 3 IaC methods (tested, passing)
- [x] `web-app-dynamodb/python` - All 3 IaC methods (tested, passing)
- [x] `lambda-s3-http/python` - Terraform (tested, passing), CloudFormation/CDK (created)
- [ ] `lambda-cloudfront/python` - IaC methods needed
- [ ] `web-app-rds/python` - IaC methods needed
- [ ] `apigw-custom-domain/python` - IaC methods needed
- [ ] `ecs-ecr-app/python` - IaC methods needed

## pytest Migration

Migrating from bash tests to pytest for better assertions and retry handling:

- [x] Create shared fixtures in `samples/conftest.py`
- [x] Add sample discovery for test matrix (sample × IaC method)
- [x] Add AWS client fixtures (Lambda, DynamoDB, S3, SQS, Step Functions, ECS, ECR, etc.)
- [x] Add tenacity-based wait/retry utilities
- [x] Move tests inside samples (not separate tests/ dir)
- [x] Add test dependencies to pyproject.toml (run with `uv run pytest`)
- [x] Convert all 8 Python samples to pytest:
  - [x] lambda-function-urls/python - 7 tests × IaC methods
  - [x] stepfunctions-lambda/python - 10 tests × IaC methods
  - [x] web-app-dynamodb/python - 8 tests × IaC methods
  - [x] lambda-s3-http/python - 11 tests × IaC methods
  - [x] lambda-cloudfront/python - 4 tests × IaC methods
  - [x] web-app-rds/python - 7 tests × IaC methods
  - [x] apigw-custom-domain/python - 7 tests × IaC methods
  - [x] ecs-ecr-app/python - 6 tests × IaC methods
- [ ] Update run-samples.sh to use pytest (optional)

## Completed (Phase 2)

- [x] `lambda-container-image` → `samples/lambda-container-image/python`
  - [x] Create directory structure with Dockerfile and handler.py
  - [x] Write scripts/deploy.sh (ECR, Docker build/push, Lambda create)
  - [x] Write pytest tests (6 tests)
  - [x] All tests pass

## To Do

- [ ] Add remaining IaC methods to samples
- [ ] Port additional samples from original repo (Phase 2)

## CI Status

10 base samples + 4 Terraform + 3 CloudFormation + 3 CDK = 20 deployable targets.
164 pytest tests discovered (tests × IaC method combinations).
