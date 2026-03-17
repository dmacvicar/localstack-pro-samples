# AppSync GraphQL API

AppSync GraphQL API with DynamoDB and RDS Aurora PostgreSQL data sources, using VTL mapping templates.

Ported from the original [localstack-pro-samples](https://github.com/localstack/localstack-pro-samples) repo.

## What it does

1. Creates an AppSync GraphQL API with API key authentication
2. Creates a DynamoDB table and an RDS Aurora PostgreSQL cluster as data sources
3. Wires up VTL resolvers for mutations (insert) and queries (scan/select) against both backends
4. GraphQL schema exposes `addPostDDB`, `getPostsDDB`, `addPostRDS`, `getPostsRDS`

## Resources created

- AppSync GraphQL API + API key
- GraphQL schema with Query, Mutation, and Subscription types
- DynamoDB table (posts)
- RDS Aurora PostgreSQL cluster
- Secrets Manager secret (RDS password)
- IAM role for AppSync
- 2 data sources (DynamoDB, RDS)
- 4 resolvers with VTL mapping templates

## Known LocalStack gaps

**DynamoDB Scan VTL resolver returns empty data.** The `getPostsDDB` query uses a standard DynamoDB Scan VTL template (`$util.toJson($context.result)`) identical to the original sample. LocalStack returns `{"data": {}}` instead of the scan results. The mutation (`addPostDDB`) works correctly, and the equivalent RDS operations (`addPostRDS`, `getPostsRDS`) both work. This is specific to LocalStack's AppSync VTL engine handling of DynamoDB Scan operations.

This causes `test_graphql_ddb_query` to fail across all 4 IaC methods (4 failures out of 52 total tests).
