#!/usr/bin/env python3
import json
from pathlib import Path

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    CfnParameter,
    aws_msk as msk,
    aws_glue as glue,
)
from constructs import Construct


class GlueMskSchemaRegistryStack(Stack):
    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        schemas_dir = Path(__file__).parent.parent / "schemas"

        subnet1 = CfnParameter(self, "SubnetId1", type="String")
        subnet2 = CfnParameter(self, "SubnetId2", type="String")

        # MSK Cluster
        cluster = msk.CfnCluster(
            self, "MSKCluster",
            cluster_name="msk-cluster-cdk",
            kafka_version="3.5.1",
            number_of_broker_nodes=2,
            broker_node_group_info=msk.CfnCluster.BrokerNodeGroupInfoProperty(
                instance_type="kafka.m5.xlarge",
                client_subnets=[subnet1.value_as_string, subnet2.value_as_string],
            ),
        )

        # Glue Schema Registry
        registry = glue.CfnRegistry(
            self, "GlueRegistry",
            name="registry-cdk",
        )

        # Glue Schema (v1)
        schema_v1 = (schemas_dir / "unicorn_ride_request_v1.avsc").read_text()
        schema = glue.CfnSchema(
            self, "GlueSchema",
            name="schema-cdk",
            registry=glue.CfnSchema.RegistryProperty(
                arn=registry.attr_arn,
            ),
            data_format="AVRO",
            compatibility="BACKWARD",
            schema_definition=schema_v1,
        )
        schema.add_dependency(registry)

        # Outputs
        CfnOutput(self, "ClusterName", value="msk-cluster-cdk")
        CfnOutput(self, "ClusterArn", value=cluster.attr_arn)
        CfnOutput(self, "RegistryName", value="registry-cdk")
        CfnOutput(self, "RegistryArn", value=registry.attr_arn)
        CfnOutput(self, "SchemaName", value="schema-cdk")
        CfnOutput(self, "SchemaArn", value=schema.attr_arn)


app = cdk.App()
GlueMskSchemaRegistryStack(app, "GlueMskSchemaRegistryStack")
app.synth()
