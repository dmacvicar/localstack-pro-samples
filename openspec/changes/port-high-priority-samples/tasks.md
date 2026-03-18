# Tasks: Port High Priority Samples

## What "Porting" Means

Each sample must include:
1. **All 4 IaC methods**: scripts/, terraform/, cloudformation/, cdk/
2. **deploy.sh**: Deploys all resources for that IaC method
3. **teardown.sh**: Cleans up all resources
4. **pytest tests**: In `test_<sample>.py`, parameterized by IaC method
5. **Consistent .env output**: All deploy scripts write to `scripts/.env`

## Completed Samples (All 4 IaC Methods)

| Sample | Language | Tests | Notes |
|--------|----------|-------|-------|
| apigw-custom-domain | python | 7×4=28 | ACM, Route53, API Gateway v2 HTTP API |
| apigw-websockets | javascript | 7×4=28 | WebSocket API Gateway |
| athena-s3-queries | python | 8×4=32 | Requires Hadoop download |
| chalice-rest-api | python | 10×4=40 | scripts uses chalice-local, others use Lambda+APIGW |
| cloudwatch-metrics-aws | python | 9×4=36 | Email requires SMTP |
| cognito-jwt | python | 10×4=40 | User pool, client, JWT tokens |
| ec2-docker-instances | python | 7×4=28 | Requires EC2_VM_MANAGER=docker |
| ecs-ecr-app | python | 6×4=24 | ECS Fargate + ECR |
| elb-load-balancing | javascript | 10×4=40 | ALB with Lambda targets |
| glacier-s3-select | python | 7×4=28 | Glacier vault, S3 Select |
| glue-etl-jobs | python | 10×4=40 | Aurora PostgreSQL + Glue JDBC + PySpark ETL |
| iam-policy-enforcement | python | 8×4=32 | Requires ENFORCE_IAM=1 |
| iot-basics | python | 9×4=36 | IoT thing, cert, policy (MQTT endpoint skipped) |
| lambda-cloudfront | python | 4×4=16 | CloudFront distribution |
| lambda-container-image | python | 6×4=24 | Docker container Lambda |
| lambda-event-filtering | python+js | 8×4=32 | EventBridge filtering |
| lambda-function-urls | python+js | 7×4=28 | Function URLs |
| lambda-layers | javascript | 5×4=20 | Lambda layers |
| lambda-s3-http | python | 10×4=40 | S3 triggers |
| lambda-xray | python | 6×4=24 | X-Ray tracing |
| mq-broker | python | 8×4=32 | Requires JDK/ActiveMQ download |
| neptune-graph-db | python | 10×4=40 | Gremlin graph queries + TinkerPop |
| rds-db-queries | python | 6×4=24 | PostgreSQL RDS instance + queries |
| route53-dns-failover | python | 10×4=40 | DNS failover with health checks |
| appsync-graphql-api | python | 13×4=52 | AppSync + DynamoDB + RDS Aurora (1 DDB Scan gap) |
| glue-redshift-crawler | python | 10×4=40 | Redshift + Glue Crawler (terraform deploy fails: connection ID format) |
| glue-msk-schema-registry | python | 12×4=48 | MSK + Glue Schema Registry + AVRO schema evolution |
| emr-serverless-spark | java | 10×4=40 | EMR Serverless + Java Spark (TF/CFN/CDK fail: LocalStack gaps) |
| reproducible-ml | python | 10×4=40 | scikit-learn SVM on Lambda with sklearn layer |
| rds-failover-test | python | 7×4=28 | Aurora global cluster failover |
| stepfunctions-lambda | python | 10×4=40 | Step Functions |
| transfer-ftp-s3 | python | 7×4=28 | AWS Transfer FTP |
| web-app-dynamodb | python | 8×4=32 | DynamoDB + Lambda |
| web-app-rds | python | 7×4=28 | RDS PostgreSQL + Lambda |

**Total: 34 samples × 4 IaC methods = 136 deployment configurations**
**Total tests: ~1114 pytest tests**

## Partial IaC Methods

| Sample | Language | IaC Methods | Tests | Notes |
|--------|----------|-------------|-------|-------|
| codecommit-git-repo | python | scripts, terraform | 7×2=14 | CloudFormation/CDK unsupported for CodeCommit |

## Remaining Samples (scripts only, need IaC methods)

(None - all current samples have all 4 IaC methods)

## Skipped Samples

- `qldb-ledger-queries` - AWS deprecated QLDB (EOL July 2025)
- `lambda-hot-reloading` - Development workflow demo, requires special config
- `mediastore-uploads` - MediaStore not supported by LocalStack

## Not Yet Ported (from original repo)

### Medium complexity
- [x] `route53-dns-failover` - Route53 DNS failover — all 4 IaC methods
- [ ] `lambda-php-bref-cdk-app` - PHP Lambda with Bref

### Complex (heavy dependencies)
- [x] `appsync-graphql-api` - AppSync + DynamoDB + RDS Aurora — all 4 IaC methods (1 DDB Scan VTL gap)
- [x] `glue-etl-jobs` - Glue ETL (needs Hadoop/Spark) — all 4 IaC methods
- [x] `glue-msk-schema-registry` - Glue + MSK — all 4 IaC methods (48 tests)
- [x] `glue-redshift-crawler` - Glue + Redshift — all 4 IaC methods (terraform deploy fails: Glue connection ID format gap)
- [ ] `emr-serverless-sample` - EMR Serverless
- [x] `emr-serverless-spark` - EMR Spark — all 4 IaC methods (scripts passes, TF/CFN/CDK have LocalStack gaps)
- [ ] `emr-serverless-python-dependencies` - EMR Python
- [ ] `sagemaker-inference` - SageMaker inference
- [x] `reproducible-ml` - ML reproducibility — all 4 IaC methods (40/40 tests pass)

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
- [x] Sample-specific env vars (EC2_VM_MANAGER=docker, ENFORCE_IAM=1)
