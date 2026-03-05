# Project: LocalStack Pro Samples

Repository of AWS sample applications for LocalStack Pro.

## Quick Start

```bash
# Run all tests
uv run pytest samples/ -v

# Run specific sample
uv run pytest samples/lambda-function-urls/python/ -v

# Run specific IaC method
uv run pytest samples/lambda-function-urls/python/ -v -k terraform

# Deploy a sample manually
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 \
  bash samples/lambda-container-image/python/scripts/deploy.sh

# Teardown
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 \
  bash samples/lambda-container-image/python/scripts/teardown.sh
```

## Structure

```
samples/<sample-name>/<language>/
├── handler.py (or handler.js, Dockerfile, etc.)
├── test_<sample>.py           # pytest tests
├── scripts/
│   ├── deploy.sh              # AWS CLI deployment
│   └── teardown.sh            # Cleanup
├── terraform/
│   ├── main.tf
│   ├── deploy.sh
│   └── teardown.sh
├── cloudformation/
│   ├── template.yml
│   ├── deploy.sh
│   └── teardown.sh
└── cdk/
    ├── app.py
    ├── cdk.json
    ├── requirements.txt
    ├── deploy.sh
    └── teardown.sh
```

## Current Samples

| Sample | Languages | IaC Methods | Tests |
|--------|-----------|-------------|-------|
| lambda-function-urls | python | scripts, terraform, cloudformation, cdk | 7 |
| stepfunctions-lambda | python | scripts, terraform, cloudformation, cdk | 10 |
| web-app-dynamodb | python | scripts, terraform, cloudformation, cdk | 8 |
| lambda-s3-http | python | scripts, terraform, cloudformation, cdk | 11 |
| lambda-cloudfront | python | scripts, terraform, cloudformation, cdk | 16 |
| web-app-rds | python | scripts, terraform, cloudformation, cdk | 28 |
| apigw-custom-domain | python | scripts, terraform, cloudformation, cdk | 28 |
| ecs-ecr-app | python | scripts, terraform, cloudformation, cdk | 24 |
| apigw-websockets | javascript | scripts | 5 |
| lambda-layers | javascript | scripts | 5 |
| lambda-container-image | python | scripts, terraform, cloudformation, cdk | 6 |

## What "Porting a Sample" Means

Each sample must include:
1. **All 4 IaC methods**: scripts/, terraform/, cloudformation/, cdk/
2. **deploy.sh**: Deploys all resources for that IaC method
3. **teardown.sh**: Cleans up all resources (counterpart to deploy.sh)
4. **pytest tests**: In `test_<sample>.py`, parameterized by IaC method
5. **Consistent .env output**: All deploy scripts write to `scripts/.env`

## CI/CD

- GitHub Actions workflow at `.github/workflows/run-samples.yml`
- Matrix-based: runs each sample × language × IaC method combination
- Uses `uv run pytest` with `-k` filtering

## Dependencies

- Python 3.11+
- uv (Python package manager)
- Docker
- LocalStack Pro (running on localhost.localstack.cloud:4566)
- Node.js 20+ (for JavaScript samples)
- Terraform, AWS CDK (for respective IaC methods)

## Active Work

See `openspec/changes/port-high-priority-samples/tasks.md` for current state.

### Recently Completed
- `ecs-ecr-app/python` - Full port with all 4 IaC methods + teardown scripts
- `apigw-custom-domain/python` - Full port with all 4 IaC methods + teardown scripts
- `web-app-rds/python` - Full port with all 4 IaC methods + teardown scripts
- `lambda-cloudfront/python` - Full port with all 4 IaC methods + teardown scripts
- `lambda-container-image/python` - Full port with all 4 IaC methods + teardown scripts

### Next Steps
- Add IaC methods to remaining samples (apigw-websockets, lambda-layers)
- Port more samples from original localstack-pro-samples repo
