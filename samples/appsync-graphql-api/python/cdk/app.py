#!/usr/bin/env python3
"""
AppSync GraphQL API CDK application.
DynamoDB and RDS Aurora PostgreSQL data sources with VTL resolvers.
"""

from aws_cdk import (
    App,
    CfnOutput,
    Stack,
    aws_appsync as appsync,
    aws_dynamodb as dynamodb,
    aws_iam as iam,
    aws_rds as rds,
    aws_secretsmanager as secretsmanager,
)
from constructs import Construct


class AppSyncGraphQLApiStack(Stack):
    """Stack for AppSync GraphQL API with DynamoDB and RDS data sources."""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        table_name = self.node.try_get_context("table_name") or "appsync-table-cdk"

        # DynamoDB table
        table = dynamodb.Table(
            self,
            "PostsTable",
            table_name=table_name,
            partition_key=dynamodb.Attribute(
                name="id", type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
        )

        # RDS Aurora PostgreSQL cluster
        db_cluster = rds.CfnDBCluster(
            self,
            "RDSCluster",
            db_cluster_identifier="appsync-rds-cdk",
            engine="aurora-postgresql",
            master_username="testuser",
            master_user_password="testpass",
            database_name="testappsync",
        )

        # Secrets Manager secret for RDS
        secret = secretsmanager.CfnSecret(
            self,
            "RDSSecret",
            name="appsync-rds-secret-cdk",
            secret_string="testpass",
        )

        # IAM role for AppSync
        appsync_role = iam.Role(
            self,
            "AppSyncRole",
            assumed_by=iam.ServicePrincipal("appsync.amazonaws.com"),
        )
        table.grant_full_access(appsync_role)
        appsync_role.add_to_policy(
            iam.PolicyStatement(
                actions=["rds-data:*", "secretsmanager:GetSecretValue"],
                resources=["*"],
            )
        )

        # AppSync GraphQL API
        api = appsync.CfnGraphQLApi(
            self,
            "GraphQLApi",
            name="appsync-api-cdk",
            authentication_type="API_KEY",
        )

        # API Key
        api_key = appsync.CfnApiKey(
            self,
            "ApiKey",
            api_id=api.attr_api_id,
        )

        # GraphQL Schema
        schema = appsync.CfnGraphQLSchema(
            self,
            "Schema",
            api_id=api.attr_api_id,
            definition="""
schema {
    query: Query
    mutation: Mutation
    subscription: Subscription
}

type Query {
    getPostsDDB: [Post!]!
    getPostsRDS: [Post!]!
}

type Mutation {
    addPostDDB(id: String!): Post!
    addPostRDS(id: String!): Post!
}

type Subscription {
    addedPost: Post
    @aws_subscribe(mutations: ["addPostDDB"])
}

type Post {
    id: String!
    time: AWSTimestamp
}
""",
        )

        # DynamoDB data source
        ddb_ds = appsync.CfnDataSource(
            self,
            "DDBDataSource",
            api_id=api.attr_api_id,
            name="ds_ddb",
            type="AMAZON_DYNAMODB",
            service_role_arn=appsync_role.role_arn,
            dynamo_db_config=appsync.CfnDataSource.DynamoDBConfigProperty(
                table_name=table.table_name,
                aws_region=self.region,
            ),
        )

        # RDS data source
        rds_ds = appsync.CfnDataSource(
            self,
            "RDSDataSource",
            api_id=api.attr_api_id,
            name="ds_rds",
            type="RELATIONAL_DATABASE",
            service_role_arn=appsync_role.role_arn,
            relational_database_config=appsync.CfnDataSource.RelationalDatabaseConfigProperty(
                relational_database_source_type="RDS_HTTP_ENDPOINT",
                rds_http_endpoint_config=appsync.CfnDataSource.RdsHttpEndpointConfigProperty(
                    aws_region=self.region,
                    db_cluster_identifier=db_cluster.attr_db_cluster_arn,
                    database_name="testappsync",
                    aws_secret_store_arn=secret.ref,
                ),
            ),
        )

        # DynamoDB resolvers
        add_post_ddb = appsync.CfnResolver(
            self,
            "AddPostDDBResolver",
            api_id=api.attr_api_id,
            type_name="Mutation",
            field_name="addPostDDB",
            data_source_name=ddb_ds.name,
            request_mapping_template="""{
    "version" : "2017-02-28",
    "operation" : "PutItem",
    "key": {
        "id" : { "S" : "${context.arguments.id}" }
    },
    "attributeValues" : {}
}""",
            response_mapping_template="$util.toJson($context.result)",
        )
        add_post_ddb.add_dependency(schema)
        add_post_ddb.add_dependency(ddb_ds)

        get_posts_ddb = appsync.CfnResolver(
            self,
            "GetPostsDDBResolver",
            api_id=api.attr_api_id,
            type_name="Query",
            field_name="getPostsDDB",
            data_source_name=ddb_ds.name,
            request_mapping_template="""{
    "version" : "2017-02-28",
    "operation" : "Scan"
}""",
            response_mapping_template="$util.toJson($context.result)",
        )
        get_posts_ddb.add_dependency(schema)
        get_posts_ddb.add_dependency(ddb_ds)

        # RDS resolvers
        add_post_rds = appsync.CfnResolver(
            self,
            "AddPostRDSResolver",
            api_id=api.attr_api_id,
            type_name="Mutation",
            field_name="addPostRDS",
            data_source_name=rds_ds.name,
            request_mapping_template="""{
    "version": "2018-05-29",
    "statements": [
        "CREATE TABLE IF NOT EXISTS posts (id varchar, title varchar)",
        "INSERT INTO posts (id, title) values ('$ctx.args.id', 'test title')",
        "SELECT * FROM posts WHERE id='$ctx.args.id'"
    ]
}""",
            response_mapping_template="""#set($resObj=$utils.rds.toJsonObject($ctx.result))
#set($resObj1=$resObj[2])
$utils.toJson($resObj1[0])""",
        )
        add_post_rds.add_dependency(schema)
        add_post_rds.add_dependency(rds_ds)

        get_posts_rds = appsync.CfnResolver(
            self,
            "GetPostsRDSResolver",
            api_id=api.attr_api_id,
            type_name="Query",
            field_name="getPostsRDS",
            data_source_name=rds_ds.name,
            request_mapping_template="""{
    "version": "2018-05-29",
    "statements": [
        "SELECT id, title FROM posts"
    ]
}""",
            response_mapping_template="""#set($resObj=$utils.rds.toJsonObject($ctx.result))
$utils.toJson($resObj[0])""",
        )
        get_posts_rds.add_dependency(schema)
        get_posts_rds.add_dependency(rds_ds)

        # Outputs
        CfnOutput(self, "ApiId", value=api.attr_api_id)
        CfnOutput(self, "ApiUrl", value=api.attr_graph_ql_url)
        CfnOutput(self, "ApiKeyValue", value=api_key.attr_api_key)
        CfnOutput(self, "ApiName", value="appsync-api-cdk")
        CfnOutput(self, "TableName", value=table.table_name)
        CfnOutput(self, "DBClusterId", value="appsync-rds-cdk")
        CfnOutput(self, "DBClusterArn", value=db_cluster.attr_db_cluster_arn)
        CfnOutput(self, "DBName", value="testappsync")
        CfnOutput(self, "SecretArn", value=secret.ref)
        CfnOutput(self, "RoleArn", value=appsync_role.role_arn)


app = App()
AppSyncGraphQLApiStack(app, "AppSyncGraphQLApiStack")
app.synth()
