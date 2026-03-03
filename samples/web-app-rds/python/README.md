# Web App RDS

AWS equivalent of Azure's `web-app-sql-database` sample.

This sample demonstrates a web application using RDS (PostgreSQL) for relational data storage.

## Architecture

```
┌─────────┐      HTTP      ┌─────────────┐      SQL      ┌─────────┐
│ Client  │ ─────────────▶ │    Lambda   │ ────────────▶ │   RDS   │
└─────────┘                │  (Web App)  │               │(Postgres)│
                           └─────────────┘               └─────────┘
```

## Overview

The web application provides a REST API backed by a PostgreSQL database:
- Full CRUD operations
- SQL query execution
- Database migrations

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
- `src/database.py` - Database utilities
- `scripts/deploy.sh` - Deployment script
- `scripts/test.sh` - Test script
