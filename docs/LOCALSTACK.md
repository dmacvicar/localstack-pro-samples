# LocalStack Configuration

This document describes how to configure and run LocalStack for the samples in this repository.

## Quick Start

### Using Docker

```bash
# Set your LocalStack auth token
export LOCALSTACK_AUTH_TOKEN=your-auth-token

# Start LocalStack Pro
docker run -d \
  --name localstack \
  -p 4566:4566 \
  -p 4510-4559:4510-4559 \
  -e LOCALSTACK_AUTH_TOKEN \
  -e DEBUG=1 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  localstack/localstack-pro
```

### Using Docker Compose

Create a `docker-compose.yml`:

```yaml
version: "3.8"

services:
  localstack:
    image: localstack/localstack-pro
    ports:
      - "4566:4566"
      - "4510-4559:4510-4559"
    environment:
      - LOCALSTACK_AUTH_TOKEN=${LOCALSTACK_AUTH_TOKEN}
      - DEBUG=1
      - PERSISTENCE=1
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "./volume:/var/lib/localstack"
```

Then run:

```bash
docker-compose up -d
```

## Health Check

Verify LocalStack is running:

```bash
curl http://localhost:4566/_localstack/health
```

Expected output shows available services:

```json
{
  "services": {
    "lambda": "running",
    "s3": "running",
    "dynamodb": "running",
    ...
  }
}
```

## AWS CLI Configuration

### Using awslocal

Install the LocalStack AWS CLI wrapper:

```bash
pip install awscli-local
```

Use `awslocal` instead of `aws`:

```bash
awslocal s3 ls
awslocal lambda list-functions
```

### Using Standard AWS CLI

Configure endpoint URL:

```bash
aws --endpoint-url=http://localhost:4566 s3 ls
```

Or set environment variables:

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LOCALSTACK_AUTH_TOKEN` | LocalStack Pro license token | Required |
| `DEBUG` | Enable debug logging | `0` |
| `PERSISTENCE` | Persist data across restarts | `0` |
| `LAMBDA_EXECUTOR` | Lambda execution mode | `docker` |
| `LAMBDA_DOCKER_NETWORK` | Docker network for Lambda | `bridge` |

## Pro Features Used

This repository demonstrates LocalStack Pro features including:

- **Lambda** - Full AWS Lambda emulation with layers and container images
- **RDS** - PostgreSQL and MySQL database instances
- **CloudFront** - CDN distribution emulation
- **Step Functions** - State machine orchestration
- **DynamoDB Streams** - Real-time stream processing

## Troubleshooting

### Container Not Starting

Check Docker logs:

```bash
docker logs localstack
```

### Lambda Timeout

Increase Lambda timeout or check network connectivity:

```bash
docker network inspect bridge
```

### Port Conflicts

If port 4566 is in use:

```bash
docker run -d -p 14566:4566 localstack/localstack-pro
export LOCALSTACK_ENDPOINT=http://localhost:14566
```

## Resources

- [LocalStack Documentation](https://docs.localstack.cloud/)
- [LocalStack Pro Features](https://docs.localstack.cloud/user-guide/aws/feature-coverage/)
- [GitHub Issues](https://github.com/localstack/localstack/issues)
