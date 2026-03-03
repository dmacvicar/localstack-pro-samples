# Lambda Layers Sample (JavaScript)

This sample demonstrates AWS Lambda Layers using the Serverless Framework with LocalStack.

**Ported from:** [localstack-pro-samples/serverless-lambda-layers](https://github.com/localstack-samples/localstack-pro-samples/tree/master/serverless-lambda-layers)

## What it Does

Lambda Layers allow you to share code and libraries across multiple Lambda functions without bundling them into each function's deployment package.

This sample:
1. Creates a **Lambda Layer** containing a shared utility library (`lib.js`)
2. Creates a **Lambda function** that imports and uses the layer
3. The layer is extracted to `/opt/nodejs/` at runtime

## Architecture

```
┌─────────────────────────────────────────┐
│           Lambda Function               │
│                                         │
│   const { echo } = require('/opt/...')  │
│                                         │
└────────────────────┬────────────────────┘
                     │ uses
                     ▼
┌─────────────────────────────────────────┐
│           Lambda Layer                  │
│                                         │
│   /opt/nodejs/lib.js                    │
│   └── echo(message)                     │
│                                         │
└─────────────────────────────────────────┘
```

## Prerequisites

- LocalStack Pro running (`localstack start`)
- Node.js 18+
- npm

## Quick Start

```bash
# Deploy
./scripts/deploy.sh

# Test
./scripts/test.sh
```

## Files

| File | Description |
|------|-------------|
| `src/handler.js` | Lambda function that uses the layer |
| `src/layer/nodejs/lib.js` | Shared library (packaged as layer) |
| `serverless.yml` | Serverless Framework configuration |
| `scripts/deploy.sh` | Deployment script |
| `scripts/test.sh` | Test script with validation |

## Layer Structure

Lambda layers for Node.js must follow this structure:
```
layer/
└── nodejs/
    └── lib.js    # Available as /opt/nodejs/lib.js at runtime
```

## Tests

The test script validates:
1. Lambda function is active
2. Layer is attached to function
3. Function invocation succeeds (returns 200)
4. Response body contains expected message
5. No import/module errors (layer loaded correctly)

## AWS Services Used

- AWS Lambda
- Lambda Layers
- API Gateway (HTTP endpoint)
- S3 (deployment bucket)
