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

| Sample | Description | Services | Azure Equivalent |
|--------|-------------|----------|------------------|
| [lambda-cloudfront](samples/lambda-cloudfront/) | Lambda function fronted by CloudFront CDN | Lambda, CloudFront | function-app-front-door |
| [lambda-s3-http](samples/lambda-s3-http/) | Gaming scoreboard with HTTP, S3, and SQS triggers | Lambda, S3, SQS, DynamoDB | function-app-storage-http |
| [web-app-dynamodb](samples/web-app-dynamodb/) | Web application with DynamoDB NoSQL backend | Lambda, DynamoDB | web-app-cosmosdb-nosql-api |
| [web-app-rds](samples/web-app-rds/) | Web application with RDS PostgreSQL backend | Lambda, RDS | web-app-sql-database |

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
