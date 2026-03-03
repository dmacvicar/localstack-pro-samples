# Lambda S3 HTTP

AWS equivalent of Azure's `function-app-storage-http` sample.

This sample demonstrates a gaming scoreboard system using Lambda with S3, SQS, and HTTP triggers.

## Architecture

```
                    ┌─────────────┐
        HTTP ──────▶│   Lambda    │
                    │  (HTTP API) │
                    └──────┬──────┘
                           │
         ┌─────────────────┼─────────────────┐
         ▼                 ▼                 ▼
    ┌─────────┐      ┌─────────┐      ┌─────────┐
    │   S3    │      │   SQS   │      │DynamoDB │
    │ (Files) │      │ (Queue) │      │(Scores) │
    └─────────┘      └─────────┘      └─────────┘
```

## Overview

The scoreboard system provides:
- HTTP endpoints for submitting and retrieving scores
- S3 for storing game replay files
- SQS for async score processing
- DynamoDB for persistent score storage

## Features

- `POST /scores` - Submit a new score
- `GET /scores` - Get top scores
- `GET /scores/{playerId}` - Get player's scores
- S3 trigger for processing uploaded replays
- SQS trigger for async score validation

## Prerequisites

- LocalStack Pro running with `LOCALSTACK_AUTH_TOKEN`
- AWS CLI or awslocal installed
- Python 3.10+

## Deployment

```bash
cd scripts
./deploy.sh
```

## Testing

```bash
cd scripts
./test.sh
```

## Files

- `src/http_handler.py` - HTTP API Lambda
- `src/s3_handler.py` - S3 event Lambda
- `src/sqs_handler.py` - SQS event Lambda
- `scripts/deploy.sh` - Deployment script
- `scripts/test.sh` - Test script
