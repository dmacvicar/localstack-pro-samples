# LocalStack Pro Samples

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![LocalStack Pro](https://img.shields.io/badge/LocalStack-Pro-purple.svg)](https://localstack.cloud)
[![AWS](https://img.shields.io/badge/AWS-Compatible-orange.svg)](https://aws.amazon.com)
[![CI](https://github.com/localstack/localstack-aws-samples/actions/workflows/run-samples.yml/badge.svg)](https://github.com/localstack/localstack-aws-samples/actions/workflows/run-samples.yml)

This repository contains sample applications demonstrating LocalStack Pro features for AWS service emulation. Each sample showcases real-world AWS patterns that can be developed and tested locally using LocalStack.

## Prerequisites

### Required Tools

- [Docker](https://docs.docker.com/get-docker/) - Container runtime for LocalStack
- [AWS CLI](https://aws.amazon.com/cli/) - AWS command line interface
- [awslocal](https://docs.localstack.cloud/user-guide/integrations/aws-cli/#localstack-aws-cli-awslocal) - LocalStack wrapper for AWS CLI
- [jq](https://stedolan.github.io/jq/) - JSON processor for parsing outputs

### Infrastructure as Code

- [Terraform](https://www.terraform.io/) - Multi-cloud infrastructure provisioning
- [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html) - Serverless Application Model
- [AWS CDK](https://docs.aws.amazon.com/cdk/latest/guide/getting_started.html) - Cloud Development Kit

### Development Tools

- [Python 3.10+](https://www.python.org/) - Required for Python samples
- [Node.js 18+](https://nodejs.org/) - Required for JavaScript/TypeScript samples

## Samples

<!-- Test badges are updated automatically by CI. See .github/workflows/run-samples.yml -->
<!-- Badge URL format: https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/USER/GIST_ID/raw/SAMPLE-LANGUAGE.json -->

| Sample | Language | IaC Methods | Tests | Notes |
|--------|----------|-------------|-------|-------|
| [lambda-function-urls](samples/lambda-function-urls/) | python | scripts, terraform, cloudformation, cdk | ![tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/dmacvicar/e64cef04f2bd02e575280d4b1184f479/raw/lambda-function-urls-python.json) | |
| [lambda-function-urls](samples/lambda-function-urls/) | javascript | scripts, terraform, cloudformation, cdk | ![tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/dmacvicar/e64cef04f2bd02e575280d4b1184f479/raw/lambda-function-urls-javascript.json) | |
| [stepfunctions-lambda](samples/stepfunctions-lambda/) | python | scripts, terraform, cloudformation, cdk | ![tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/dmacvicar/e64cef04f2bd02e575280d4b1184f479/raw/stepfunctions-lambda-python.json) | |
| [web-app-dynamodb](samples/web-app-dynamodb/) | python | scripts, terraform, cloudformation, cdk | ![tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/dmacvicar/e64cef04f2bd02e575280d4b1184f479/raw/web-app-dynamodb-python.json) | |
| [lambda-s3-http](samples/lambda-s3-http/) | python | scripts, terraform, cloudformation, cdk | ![tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/dmacvicar/e64cef04f2bd02e575280d4b1184f479/raw/lambda-s3-http-python.json) | |
| [lambda-cloudfront](samples/lambda-cloudfront/) | python | scripts, terraform, cloudformation, cdk | ![tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/dmacvicar/e64cef04f2bd02e575280d4b1184f479/raw/lambda-cloudfront-python.json) | |
| [web-app-rds](samples/web-app-rds/) | python | scripts, terraform, cloudformation, cdk | ![tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/dmacvicar/e64cef04f2bd02e575280d4b1184f479/raw/web-app-rds-python.json) | |
| [apigw-custom-domain](samples/apigw-custom-domain/) | python | scripts, terraform, cloudformation, cdk | ![tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/dmacvicar/e64cef04f2bd02e575280d4b1184f479/raw/apigw-custom-domain-python.json) | |
| [ecs-ecr-app](samples/ecs-ecr-app/) | python | scripts, terraform, cloudformation, cdk | ![tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/dmacvicar/e64cef04f2bd02e575280d4b1184f479/raw/ecs-ecr-app-python.json) | |
| [lambda-container-image](samples/lambda-container-image/) | python | scripts, terraform, cloudformation, cdk | ![tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/dmacvicar/e64cef04f2bd02e575280d4b1184f479/raw/lambda-container-image-python.json) | |
| [apigw-websockets](samples/apigw-websockets/) | javascript | scripts, terraform, cloudformation, cdk | ![tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/dmacvicar/e64cef04f2bd02e575280d4b1184f479/raw/apigw-websockets-javascript.json) | |
| [lambda-layers](samples/lambda-layers/) | javascript | scripts, terraform, cloudformation, cdk | ![tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/dmacvicar/e64cef04f2bd02e575280d4b1184f479/raw/lambda-layers-javascript.json) | |
| [lambda-event-filtering](samples/lambda-event-filtering/) | javascript | scripts, terraform, cloudformation, cdk | ![tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/dmacvicar/e64cef04f2bd02e575280d4b1184f479/raw/lambda-event-filtering-javascript.json) | |
| [lambda-xray](samples/lambda-xray/) | python | scripts, terraform, cloudformation, cdk | ![tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/dmacvicar/e64cef04f2bd02e575280d4b1184f479/raw/lambda-xray-python.json) | |
| [codecommit-git-repo](samples/codecommit-git-repo/) | python | scripts, terraform | ![tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/dmacvicar/e64cef04f2bd02e575280d4b1184f479/raw/codecommit-git-repo-python.json) | CloudFormation/CDK unsupported |
| [iot-basics](samples/iot-basics/) | python | scripts, terraform, cloudformation, cdk | ![tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/dmacvicar/e64cef04f2bd02e575280d4b1184f479/raw/iot-basics-python.json) | 1 test skipped (MQTT endpoint) |
| [athena-s3-queries](samples/athena-s3-queries/) | python | scripts, terraform, cloudformation, cdk | ![tests](https://img.shields.io/badge/tests-pending-lightgrey) | Requires Hadoop download |
| [mq-broker](samples/mq-broker/) | python | scripts, terraform, cloudformation, cdk | ![tests](https://img.shields.io/badge/tests-pending-lightgrey) | Requires JDK/ActiveMQ download |
| [transfer-ftp-s3](samples/transfer-ftp-s3/) | python | scripts | ![tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/dmacvicar/e64cef04f2bd02e575280d4b1184f479/raw/transfer-ftp-s3-python.json) | Terraform/CloudFormation/CDK unsupported |
| [glacier-s3-select](samples/glacier-s3-select/) | python | scripts | ![tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/dmacvicar/e64cef04f2bd02e575280d4b1184f479/raw/glacier-s3-select-python.json) | Terraform/CloudFormation/CDK unsupported |
| [rds-db-queries](samples/rds-db-queries/) | python | scripts | ![tests](https://img.shields.io/badge/tests-pending-lightgrey) | Requires PostgreSQL download |
| [rds-failover-test](samples/rds-failover-test/) | python | scripts | ![tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/dmacvicar/e64cef04f2bd02e575280d4b1184f479/raw/rds-failover-test-python.json) | Terraform/CloudFormation/CDK unsupported |
| [neptune-graph-db](samples/neptune-graph-db/) | python | scripts | ![tests](https://img.shields.io/badge/tests-pending-lightgrey) | Requires Java/TinkerGraph download |
| [iam-policy-enforcement](samples/iam-policy-enforcement/) | python | scripts | ![tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/dmacvicar/e64cef04f2bd02e575280d4b1184f479/raw/iam-policy-enforcement-python.json) | Requires ENFORCE_IAM=1 |
| [ec2-docker-instances](samples/ec2-docker-instances/) | python | scripts | ![tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/dmacvicar/e64cef04f2bd02e575280d4b1184f479/raw/ec2-docker-instances-python.json) | Requires EC2_VM_MANAGER=docker |

## Sample Structure

Each sample follows a consistent organization:

```
samples/{sample-name}/
├── {language}/                 # python, javascript, etc.
│   ├── README.md              # Sample documentation
│   ├── scripts/               # Deployment and test scripts
│   │   ├── deploy.sh          # Primary deployment script
│   │   ├── validate.sh        # Resource validation
│   │   └── test.sh            # Functional tests
│   ├── terraform/             # Terraform configuration (optional)
│   │   ├── main.tf
│   │   ├── providers.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── sam/                   # SAM template (optional)
│   │   └── template.yaml
│   └── src/                   # Application source code
```

## Local Testing

### Quick Start

1. Start LocalStack Pro:
```bash
export LOCALSTACK_AUTH_TOKEN=your-auth-token
docker run -d --name localstack \
  -p 4566:4566 \
  -e LOCALSTACK_AUTH_TOKEN \
  -v /var/run/docker.sock:/var/run/docker.sock \
  localstack/localstack-pro
```

2. Run all tests:
```bash
./run-samples.sh
```

3. Run a specific sample:
```bash
./run-samples.sh SHARD=1 SPLITS=5
```

### Using Make

```bash
make install    # Install dependencies
make test       # Run all tests
make logs       # Show LocalStack logs
```

## Troubleshooting

### Line Ending Issues

If scripts fail with `\r` errors on Windows/WSL:
```bash
git config core.autocrlf false
git checkout -- .
```

### LocalStack Connection

Verify LocalStack is running:
```bash
curl http://localhost:4566/_localstack/health
```

## Configuration

See [docs/LOCALSTACK.md](docs/LOCALSTACK.md) for detailed LocalStack configuration options.

## Documentation

- [LocalStack Documentation](https://docs.localstack.cloud/)
- [LocalStack Pro Features](https://docs.localstack.cloud/user-guide/aws/feature-coverage/)
- [AWS CLI with LocalStack](https://docs.localstack.cloud/user-guide/integrations/aws-cli/)

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/new-sample`
3. Make your changes following the sample structure conventions
4. Test locally with LocalStack
5. Submit a pull request

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## Support

- [GitHub Issues](https://github.com/localstack/localstack-aws-samples/issues) - Bug reports and feature requests
- [LocalStack Slack](https://localstack.cloud/contact) - Community support
- [LocalStack Pro Support](https://localstack.cloud/pricing) - Enterprise support
