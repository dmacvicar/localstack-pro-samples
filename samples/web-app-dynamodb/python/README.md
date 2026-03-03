# Web App DynamoDB

AWS equivalent of Azure's `web-app-cosmosdb-nosql-api` sample.

This sample demonstrates a web application using DynamoDB for NoSQL data storage.

## Architecture

```
┌─────────┐      HTTP      ┌─────────────┐     Query     ┌──────────┐
│ Client  │ ─────────────▶ │    Lambda   │ ────────────▶ │ DynamoDB │
└─────────┘                │  (Web App)  │               │ (NoSQL)  │
                           └─────────────┘               └──────────┘
```

## Overview

The web application provides a REST API for managing items in DynamoDB:
- Create, read, update, delete operations
- Query by partition key
- Scan with filters

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

- `src/app.py` - Web application Lambda
- `scripts/deploy.sh` - Deployment script
- `scripts/test.sh` - Test script
