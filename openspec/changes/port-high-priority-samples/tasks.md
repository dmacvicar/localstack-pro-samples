# Tasks: Port High Priority Samples

## What "Porting" Means

Each sample must include:
1. **All 4 IaC methods**: scripts/, terraform/, cloudformation/, cdk/
2. **deploy.sh**: Deploys all resources for that IaC method
3. **teardown.sh**: Cleans up all resources
4. **pytest tests**: In `test_<sample>.py`, parameterized by IaC method
5. **Consistent .env output**: All deploy scripts write to `scripts/.env`

## Completed (Phase 1 - Initial Ports)

These have scripts/ but need other IaC methods:

- [x] `lambda-function-urls/python` - All 4 IaC methods complete
- [x] `lambda-function-urls/javascript` - All 4 IaC methods (28 tests pass)
- [x] `stepfunctions-lambda/python` - All 4 IaC methods complete
- [x] `web-app-dynamodb/python` - All 4 IaC methods complete
- [x] `lambda-s3-http/python` - All 4 IaC methods complete
- [x] `lambda-cloudfront/python` - scripts only (needs terraform, cloudformation, cdk)
- [x] `web-app-rds/python` - scripts only (needs terraform, cloudformation, cdk)
- [x] `apigw-custom-domain/python` - scripts only (needs terraform, cloudformation, cdk)
- [x] `ecs-ecr-app/python` - scripts only (needs terraform, cloudformation, cdk)
- [x] `apigw-websockets/javascript` - scripts only (Serverless Framework)
- [x] `lambda-layers/javascript` - scripts only (Serverless Framework)

## Completed (Phase 2 - Full Ports with All IaC Methods)

- [x] `lambda-container-image/python`
  - [x] All 4 IaC methods: scripts, terraform, cloudformation, cdk
  - [x] Each has deploy.sh and teardown.sh
  - [x] pytest tests (6 tests × 4 IaC methods)
  - [x] All tests pass locally

- [x] `lambda-cloudfront/python`
  - [x] All 4 IaC methods: scripts, terraform, cloudformation, cdk
  - [x] Each has deploy.sh and teardown.sh
  - [x] pytest tests (4 tests × 4 IaC methods = 16 tests, 12 pass, 4 skipped for CloudFront distribution)
  - [x] All tests pass locally

- [x] `web-app-rds/python`
  - [x] All 4 IaC methods: scripts, terraform, cloudformation, cdk
  - [x] Each has deploy.sh and teardown.sh
  - [x] All IaC methods create VPC + subnets for RDS consistency
  - [x] pytest tests (7 tests × 4 IaC methods = 28 tests)
  - [x] All tests pass locally

- [x] `apigw-custom-domain/python`
  - [x] All 4 IaC methods: scripts, terraform, cloudformation, cdk
  - [x] Each has deploy.sh and teardown.sh
  - [x] Uses ACM, Route53, API Gateway v2 HTTP API, Lambda, custom domain
  - [x] pytest tests (7 tests × 4 IaC methods = 28 tests)
  - [x] All tests pass locally

## pytest Infrastructure

- [x] Shared fixtures in `samples/conftest.py`
- [x] AWS client fixtures (Lambda, DynamoDB, S3, SQS, Step Functions, ECS, ECR, etc.)
- [x] tenacity-based wait/retry utilities
- [x] Tests inside sample directories (not separate tests/ dir)
- [x] Dependencies in pyproject.toml (run with `uv run pytest`)
- [x] Shared test support with `-k` filtering for language and IaC method

## CI Infrastructure

- [x] Matrix-based GitHub Actions workflow
- [x] Discovers sample × language × IaC combinations automatically
- [x] Uses `uv` for all Python operations (no pip)
- [x] Pinned awscli-local==0.21 to avoid --s3-endpoint-url bug

## To Do (Priority Order)

1. Add IaC methods + teardown scripts to existing samples:
   - [x] `lambda-cloudfront/python`
   - [x] `web-app-rds/python`
   - [x] `apigw-custom-domain/python`
   - [x] `ecs-ecr-app/python`

2. Port more samples from original repo:
   - [x] `lambda-event-filtering/javascript` - All 4 IaC methods
   - [x] `iot-basics/python` - All 4 IaC methods (8 tests pass, 1 skipped - MQTT endpoint)
   - [~] `athena-s3-queries/python` - All 4 IaC methods created, NEEDS TESTING (requires Hadoop download)
   - [~] `mq-broker/python` - All 4 IaC methods created, NEEDS TESTING (requires JDK/ActiveMQ download)

## Remaining Samples to Port (from localstack-pro-samples-original)

### Simple (no heavy dependencies)
- [x] `qldb-ledger-queries` - SKIP: AWS deprecated QLDB (EOL July 2025)
- [x] `lambda-xray/python` - All 4 IaC methods (24 tests pass)
- [ ] `cloudwatch-metrics-aws` - CloudWatch metrics
- [ ] `iam-policy-enforcement` - IAM policy testing
- [x] `codecommit-git-repo/python` - scripts, terraform only (14 tests pass, CloudFormation/CDK unsupported)
- [x] `lambda-hot-reloading` - SKIP: Development workflow demo, requires special config
- [x] `mediastore-uploads` - SKIP: MediaStore not supported by LocalStack
- [~] `rds-db-queries/python` - All 4 IaC methods created, NEEDS TESTING (requires PostgreSQL download)
- [x] `transfer-ftp-s3/python` - scripts only (7 tests pass, Terraform/CloudFormation/CDK unsupported)
- [x] `glacier-s3-select/python` - scripts only (7 tests pass, Terraform times out, CloudFormation/CDK unsupported)

### Medium complexity
- [ ] `cognito-jwt` - Cognito JWT (requires SMTP - may skip)
- [ ] `chalice-rest-api` - Chalice framework REST API
- [ ] `ec2-docker-instances` - EC2 with Docker
- [ ] `elb-load-balancing` - ELB (uses Serverless Framework)
- [ ] `glacier-s3-select` - Glacier + S3 Select
- [ ] `neptune-graph-db` - Neptune graph database
- [x] `rds-failover-test/python` - scripts only (7 tests pass, Terraform/CloudFormation/CDK unsupported)
- [ ] `route53-dns-failover` - Route53 DNS failover
- [ ] `lambda-php-bref-cdk-app` - PHP Lambda with Bref

### Complex (heavy dependencies or multiple services)
- [ ] `appsync-graphql-api` - AppSync + DynamoDB + RDS + WebSockets
- [ ] `glue-etl-jobs` - Glue ETL (needs Hadoop/Spark)
- [ ] `glue-msk-schema-registry` - Glue + MSK
- [ ] `glue-redshift-crawler` - Glue + Redshift
- [ ] `emr-serverless-sample` - EMR Serverless
- [ ] `emr-serverless-spark` - EMR Spark
- [ ] `emr-serverless-python-dependencies` - EMR Python
- [ ] `sagemaker-inference` - SageMaker inference
- [ ] `reproducible-ml` - ML reproducibility

### Debugging/tooling samples (different purpose)
- [ ] `lambda-debugging-sam-java` - SAM debugging (Java)
- [ ] `lambda-debugging-sam-javascript` - SAM debugging (JS)
- [ ] `lambda-debugging-sam-python` - SAM debugging (Python)
- [ ] `lambda-debugging-sam-typescript` - SAM debugging (TS)
- [ ] `cdk-for-terraform` - CDKTF example
- [ ] `cdk-resources` - CDK resources demo
- [ ] `terraform-resources` - Terraform resources demo
- [ ] `testcontainers-java-sample` - Testcontainers Java
- [ ] `multi-account-multi-region-s3-access` - Multi-account S3

## CI Status

15 samples ported, ~200 pytest tests across all IaC method combinations.
