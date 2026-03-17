# Glue Redshift Crawler

Creates an Amazon Redshift cluster, a Glue JDBC connection, database, and crawler that catalogs a Redshift table into the Glue Data Catalog.

Based on: https://github.com/localstack/localstack-pro-samples

## Resources Created

- **Redshift Cluster** - Single-node cluster with a `sales` table
- **Glue Database** - Catalog database for crawler output
- **Glue Connection** - JDBC connection to the Redshift cluster
- **Glue Crawler** - Crawls the Redshift `sales` table and populates the Glue catalog
- **IAM Role** - Service role for the Glue crawler

## Known LocalStack Gaps

### Terraform: Glue Connection ID Format (deploy fails)

LocalStack returns the Glue connection ID as `:connection-name` (with empty catalog ID prefix), but the Terraform AWS provider expects the format `CATALOG_ID:NAME`. This causes `terraform apply` to fail after creating the connection:

```
Error: unexpected format for ID (:glueconn-tf), expected CATALOG-ID:NAME
```

The same Glue connection works correctly via scripts, CloudFormation, and CDK. This is a LocalStack-specific issue with how the Glue connection resource ID is returned to Terraform's state management.

## Test Results

| IaC Method | Status | Tests |
|-----------|--------|-------|
| scripts | Pass | 10/10 |
| terraform | Deploy fails | 0/10 (LocalStack gap) |
| cloudformation | Pass | 10/10 |
| cdk | Pass | 10/10 |
