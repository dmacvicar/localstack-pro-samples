# Lambda CloudFront

AWS equivalent of Azure's `function-app-front-door` sample.

This sample demonstrates a Lambda function fronted by CloudFront CDN.

## Architecture

```
┌─────────┐      HTTPS      ┌─────────────┐     Invoke    ┌─────────┐
│ Client  │ ──────────────▶ │  CloudFront │ ────────────▶ │ Lambda  │
└─────────┘                 │    (CDN)    │               │ @Edge   │
                            └─────────────┘               └─────────┘
```

## Overview

CloudFront provides:
- Global edge caching for low latency
- HTTPS termination
- Request routing to Lambda origins
- Edge functions for request/response manipulation

## Prerequisites

- LocalStack Pro running with `LOCALSTACK_AUTH_TOKEN`
- AWS CLI or awslocal installed
- Python 3.10+

## Deployment

### Using Scripts (AWS CLI)

```bash
cd scripts
./deploy.sh
```

### Using Terraform

```bash
cd terraform
./deploy.sh
```

## Testing

```bash
cd scripts
./test.sh
```

## Files

- `src/handler.py` - Lambda function code
- `scripts/deploy.sh` - AWS CLI deployment script
- `scripts/test.sh` - Functional test script
- `terraform/` - Terraform configuration
