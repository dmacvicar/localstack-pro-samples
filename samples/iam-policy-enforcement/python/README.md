# IAM Policy Enforcement

This sample demonstrates IAM policy enforcement in LocalStack Pro.

## Overview

By default, LocalStack does not enforce IAM policies. This sample shows how to enable and test IAM policy enforcement, demonstrating that:

1. Default credentials are denied access when IAM enforcement is enabled
2. IAM users with proper policies are granted access

## Architecture

```
Default Credentials (test/test)
    └── Denied: Kinesis, S3 operations

IAM User with Policy
    └── Allowed: Kinesis, S3 operations (per policy)
```

## Prerequisites

- LocalStack Pro with **ENFORCE_IAM=1** enabled
- Python 3.10+

## Important: Enable IAM Enforcement

Start LocalStack with IAM enforcement enabled:

```bash
LOCALSTACK_AUTH_TOKEN=... ENFORCE_IAM=1 localstack start
```

Or with Docker:

```bash
docker run -d \
  -p 4566:4566 \
  -e LOCALSTACK_AUTH_TOKEN \
  -e ENFORCE_IAM=1 \
  localstack/localstack-pro
```

## IaC Methods

| Method | Status | Notes |
|--------|--------|-------|
| scripts | Supported | AWS CLI deployment |
| terraform | Not implemented | |
| cloudformation | Not implemented | |
| cdk | Not implemented | |

## Deployment

```bash
cd samples/iam-policy-enforcement/python

# Deploy (creates IAM user and policy)
./scripts/deploy.sh

# Teardown
./scripts/teardown.sh
```

## Testing

```bash
# Run tests (will skip IAM enforcement tests if ENFORCE_IAM not enabled)
uv run pytest samples/iam-policy-enforcement/python/ -v
```

## How It Works

1. **Deploy** creates:
   - IAM policy allowing Kinesis and S3 access
   - IAM user with the policy attached
   - Access key for the user

2. **Tests verify**:
   - Default credentials (`test/test`) are denied
   - IAM user credentials are allowed

## Resources Created

- IAM Policy: `iam-test-policy`
- IAM User: `iam-test-user`
- Access Key for the user

## Environment Variables

After deployment, the following variables are written to `scripts/.env`:

- `USER_NAME`: IAM user name
- `POLICY_NAME`: IAM policy name
- `POLICY_ARN`: IAM policy ARN
- `IAM_ACCESS_KEY_ID`: Access key for IAM user
- `IAM_SECRET_ACCESS_KEY`: Secret key for IAM user
- `IAM_ENFORCED`: Whether IAM enforcement was detected

## Troubleshooting

### Tests skipped with "IAM enforcement not enabled"

Start LocalStack with `ENFORCE_IAM=1`:

```bash
ENFORCE_IAM=1 localstack start
```

### AccessDeniedException for all operations

This is expected when IAM enforcement is enabled and you're using default credentials. Use the IAM user credentials from `.env`.

## License

Apache 2.0
