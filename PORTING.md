# Porting Guide: Old Samples to New Convention

This document tracks the migration of samples from the old `localstack-pro-samples` structure to the new `localstack-aws-samples` convention (matching `localstack-azure-samples`).

## New Convention

```
samples/{sample-name}/{language}/
├── README.md
├── scripts/
│   ├── deploy.sh
│   └── test.sh
├── terraform/          # optional
│   ├── deploy.sh
│   ├── main.tf
│   └── ...
└── src/
    └── *.py|*.js|...
```

## Already Ported

| Old Sample | New Sample | Status |
|------------|------------|--------|
| (new) | lambda-cloudfront | ✅ Done |
| (new) | lambda-s3-http | ✅ Done |
| (new) | web-app-dynamodb | ✅ Done |
| (new) | web-app-rds | ✅ Done |

## To Port - High Priority

These are commonly used patterns that should be ported first:

| Old Sample | New Name | Languages | IaC Options | Notes |
|------------|----------|-----------|-------------|-------|
| lambda-function-urls-python | lambda-function-urls | python | scripts, terraform | Simple Lambda with Function URL |
| lambda-function-urls-javascript | lambda-function-urls | javascript | scripts, terraform | JS version |
| stepfunctions-lambda | stepfunctions-lambda | python | scripts | Step Functions orchestration |
| serverless-websockets | apigw-websockets | python, javascript | serverless | WebSocket API |
| serverless-lambda-layers | lambda-layers | javascript | serverless | Lambda layers |
| apigw-custom-domain | apigw-custom-domain | javascript | serverless | Custom domain mapping |
| terraform-resources | terraform-basics | - | terraform | Basic Terraform resources |
| ecs-ecr-container-app | ecs-ecr-app | - | cloudformation | Container app on ECS |

## To Port - Medium Priority

| Old Sample | New Name | Languages | IaC Options | Notes |
|------------|----------|-----------|-------------|-------|
| lambda-container-image | lambda-container | python | scripts | Lambda with container image |
| lambda-hot-reloading | lambda-hot-reload | javascript, typescript | scripts, terraform | Hot reloading demo |
| lambda-event-filtering | lambda-event-filter | javascript | sam | Event filtering |
| lambda-xray | lambda-xray | python | sam | X-Ray tracing |
| cognito-jwt | cognito-auth | java | scripts | Cognito JWT validation |
| rds-db-queries | rds-queries | python | scripts | RDS query examples |
| elb-load-balancing | elb-alb | javascript | serverless | Load balancer setup |
| iot-basics | iot-mqtt | python | cloudformation | IoT basics |
| glue-etl-jobs | glue-etl | python | scripts | Glue ETL jobs |

## To Port - Lower Priority

| Old Sample | New Name | Languages | IaC Options | Notes |
|------------|----------|-----------|-------------|-------|
| appsync-graphql-api | appsync-graphql | python | serverless | GraphQL API |
| athena-s3-queries | athena-queries | - | scripts | Athena SQL queries |
| cdk-resources | cdk-basics | typescript | cdk | CDK examples |
| cdk-for-terraform | cdktf-basics | python | cdktf | CDKTF examples |
| chalice-rest-api | chalice-api | python | chalice | Chalice framework |
| cloudwatch-metrics-aws | cloudwatch-metrics | python | scripts | CloudWatch metrics |
| codecommit-git-repo | codecommit-repo | - | scripts | CodeCommit setup |
| ec2-docker-instances | ec2-docker | - | scripts | EC2 with Docker |
| emr-serverless-* | emr-serverless | python, java | terraform | EMR Serverless |
| glacier-s3-select | glacier-select | - | scripts | Glacier/S3 Select |
| glue-msk-schema-registry | glue-msk | java | scripts | MSK Schema Registry |
| glue-redshift-crawler | glue-redshift | - | scripts | Redshift crawler |
| iam-policy-enforcement | iam-policies | - | scripts | IAM policy demo |
| java-notification-app | sns-sqs-java | java | cloudformation | Java notification |
| lambda-debugging-sam-* | lambda-debug | python, java, js, ts | sam | SAM debugging |
| lambda-php-bref-cdk-app | lambda-php-bref | php | cdk | PHP Bref runtime |
| mediastore-uploads | mediastore | - | scripts | MediaStore uploads |
| mq-broker | amazon-mq | - | scripts | Amazon MQ broker |
| multi-account-multi-region-s3-access | s3-cross-account | go | scripts | Cross-account S3 |
| neptune-graph-db | neptune-graph | python | scripts | Neptune graph DB |
| qldb-ledger-queries | qldb-ledger | python | scripts | QLDB ledger |
| rds-failover-test | rds-failover | python | scripts | RDS failover |
| reproducible-ml | sagemaker-ml | python | scripts | ML reproducibility |
| route53-dns-failover | route53-failover | - | scripts | DNS failover |
| sagemaker-inference | sagemaker-inference | python | scripts | SageMaker inference |
| testcontainers-java-sample | testcontainers | java | - | Testcontainers |
| transfer-ftp-s3 | transfer-ftp | python | scripts | AWS Transfer FTP |

## Archived (Not Porting)

These are in `sample-archive/` and likely outdated:

- aws-sam-amplify-lambda-webapp
- azure-functions (not AWS)
- cloudfront-distributions (superseded by lambda-cloudfront)
- ec2-custom-ami (Packer-specific)
- emr-hadoop-spark-jobs (old EMR)
- kinesis-analytics (outdated)
- sagemaker-ml-jobs (superseded by sagemaker-inference)
- serverless-request-workers (complex demo)
- spring-cloud-function-microservice (Spring-specific)

## Porting Checklist

When porting a sample:

1. [ ] Create `samples/{name}/{language}/` structure
2. [ ] Write `README.md` with architecture diagram
3. [ ] Create `scripts/deploy.sh` using awslocal
4. [ ] Create `scripts/test.sh` with assertions
5. [ ] Add `src/` with application code
6. [ ] Optionally add `terraform/` with IaC
7. [ ] Update `run-samples.sh` SCRIPT_SAMPLES array
8. [ ] Update root `README.md` samples table
9. [ ] Test locally with `./run-samples.sh`
10. [ ] Test with `act` for CI verification
